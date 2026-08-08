## udp_transport.gd — T0002M03 UDP 线路协议客户端实现（T0005M03）
## - 包头 16B：magic u16(0x5A50) · version u8 · flags u8 · conn_id u32 · seq u16 · ack u16 · ack_bits u32
##   （T0002M03F01 标 "14 B" 为文档笔误，字段求和 = 16B）
## - 同一 datagram 合并多条消息；MTU 1200；超限仅 Ch2 分片（frag_id u16 · frag_idx u8 · frag_cnt u8）
## - 序号空间全局统一（所有包共享 seq），可靠层重传队列按通道独立、ack 全局裁剪（跨通道正确）
## - Ch2 可靠有序：接收侧按 seq 缓冲连续投递；Ch3 可靠无序：去重即投递；Ch0 直接投递
## - 心跳 1Hz（显式）；Grace 期 2~4Hz 纯 ACK 探针（T0005M03F06：沉默就回不来了）
## - NAT 漂移：conn_id 独立于 IP:Port，切网后不重建 socket，继续用同一 socket 发
## - P0 握手：T0002 握手包体格式未定（T0005M14F01），P0 明文直连（flags.bit3 占位），
##   发一个 flags.bit2 空包后直接置 OPEN；格式下发后在此替换（M14F01 已上报）

class_name UdpTransport
extends ISoupTransport

const MAGIC := 0x5A50
const VERSION := 1
const FLAG_FRAG := 0x01
const FLAG_PURE_ACK := 0x02
const FLAG_HANDSHAKE := 0x04
const FLAG_ENCRYPT := 0x08          # v1 占位（T0002M03F04：明文跑通）
const MTU := 1200
## 包头字段求和 = 16B（magic u16 + version u8 + flags u8 + conn_id u32 + seq u16 + ack u16 + ack_bits u32）
## T0002M03F01 写 "14 B" 为文档笔误，双方按字段布局 16B 实现
const HEADER_LEN := 16
const HEARTBEAT_INTERVAL_S := 1.0
const GRACE_PROBE_INTERVAL_S := 0.35   # ~3 Hz（T0005M03F06：2~4Hz 探针）

var _socket: PacketPeerUDP = null
var _conn_id: int = 0
var _send_seq: int = 0              # 全局发送序号（所有包共享）
var _recv_tracker := ReliabilityChannel.new()   # 接收侧去重 + ack 记账（对端全局 seq）
var _state: int = State.CLOSED

# 可靠通道重传队列（Ch2/Ch3；seq 为全局序号）
var _rel: Dictionary = {}
# Ch2 有序投递缓冲：ch → {expected: int, buffer: {seq: Array[Dictionary{msg_id, body}]}}
var _ordered_recv: Dictionary = {}
# Ch2 分片
var _reassembly := Reassembly.new()
var _frag_id: int = 0

# 心跳
var _heartbeat_acc: float = 0.0
var _grace_probe_acc: float = 0.0

# 待发消息队列（本帧合并打包）：Array[{ch, msg_id, body}]
var _pending: Array = []

# 诊断
var _bad_magic: int = 0
var _malformed: int = 0
var _packets_out: int = 0
var _packets_in: int = 0
var _bytes_out: int = 0


func _init() -> void:
	_rel[MsgIds.CH_RELIABLE_ORDERED] = ReliabilityChannel.new()
	_rel[MsgIds.CH_RELIABLE_UNORDERED] = ReliabilityChannel.new()
	_reassembly.set_rto_ms(_rel[MsgIds.CH_RELIABLE_ORDERED].rto_ms)


# ══ ISoupTransport 实现 ═══════════════════════════════════════════════════

func connect_to(host: String, port: int, _token: PackedByteArray) -> void:
	disconnect_from()
	_socket = PacketPeerUDP.new()
	var err := _socket.connect_to_host(host, port)
	if err != OK:
		_set_state(State.CLOSED)
		return
	_state = State.CONNECTING
	_conn_id = _rand_conn_id()
	# P0 明文直连：发握手占位包（格式待 T0002 下发，T0005M14F01）
	_send_datagram_raw(_build_datagram(_next_seq(), FLAG_HANDSHAKE, PackedByteArray()))
	_set_state(State.OPEN)


func disconnect_from() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	_pending.clear()
	for ch in _rel:
		_rel[ch].retrans.clear()
	_recv_tracker = ReliabilityChannel.new()
	_ordered_recv.clear()
	_state = State.CLOSED


func poll(delta: float) -> void:
	if _socket == null:
		return
	var now_ms := Time.get_ticks_msec() / 1000.0
	_recv_all()
	_flush_pending()
	# 重传驱动（T0005M03F03：RTO 超时重发，载荷不变、套最新 ack）
	var broken := false
	for ch in _rel:
		var rc: ReliabilityChannel = _rel[ch]
		rc.poll_retrans(now_ms * 1000.0, delta * 1000.0)
		if rc.broken:
			broken = true
		for item in rc.retrans:
			if item.last_sent_ms > 0.0 and now_ms * 1000.0 - item.last_sent_ms >= rc.rto_ms:
				_send_datagram_raw(_build_datagram(item.seq, 0, item.data))
	if broken:
		_set_state(State.CLOSED)
		push_error("可靠层重传超限，断连")
		return
	# 心跳（对局中由 PlayerInput 天然覆盖；大厅/结算由 app 显式 tick）
	_heartbeat_acc += delta
	if _heartbeat_acc >= HEARTBEAT_INTERVAL_S:
		_heartbeat_acc = 0.0
		if _state == State.OPEN and _pending.is_empty():
			_send_pure_ack()
	# Grace 探针：2~4 Hz 纯 ACK（T0005M03F06）
	if _state == State.GRACE:
		_grace_probe_acc += delta
		if _grace_probe_acc >= GRACE_PROBE_INTERVAL_S:
			_grace_probe_acc = 0.0
			_send_pure_ack()
	_reassembly.poll_expiry(now_ms * 1000.0)


func tick_heartbeat(delta: float) -> void:
	_heartbeat_acc += delta
	if _heartbeat_acc >= HEARTBEAT_INTERVAL_S:
		_heartbeat_acc = 0.0
		if _state == State.OPEN:
			_send_pure_ack()


func send(ch: int, msg_id: int, body: PackedByteArray) -> void:
	if _state != State.OPEN and _state != State.CONNECTING:
		return
	_pending.append({"ch": ch, "msg_id": msg_id, "body": body})


func get_srtt_ms() -> int:
	var rc: ReliabilityChannel = _rel.get(MsgIds.CH_RELIABLE_ORDERED)
	return int(rc.srtt_ms) if rc != null else 0


func get_rttvar_ms() -> int:
	var rc: ReliabilityChannel = _rel.get(MsgIds.CH_RELIABLE_ORDERED)
	return int(rc.rttvar_ms) if rc != null else 0


func get_loss_permille() -> int:
	return 0   # 由上层统计（预留）


func get_state() -> int:
	return _state


func enter_grace() -> void:
	if _state == State.OPEN:
		_set_state(State.GRACE)
		_grace_probe_acc = 1.0   # 立即发第一发探针
		_pending.clear()


# ══ 发送侧 ═════════════════════════════════════════════════════════════════

func _next_seq() -> int:
	var s := _send_seq
	_send_seq = (_send_seq + 1) & 0xFFFF
	return s


func _flush_pending() -> void:
	if _pending.is_empty():
		return
	var batch: Array = _pending
	_pending = []
	for item in batch:
		var ch: int = item.ch
		var msg_id: int = item.msg_id
		var body: PackedByteArray = item.body
		var seq := _next_seq()
		if ch == MsgIds.CH_RELIABLE_ORDERED or ch == MsgIds.CH_RELIABLE_UNORDERED:
			# 可靠：登记重传（全局 seq），载荷 = 单条消息帧
			var frame := _encode_frame(ch, msg_id, body)
			if frame.size() > MTU - HEADER_LEN - 5:
				# 分片（仅 Ch2，T0005M03F04）
				if ch != MsgIds.CH_RELIABLE_ORDERED:
					_malformed += 1
					continue
				_frag_and_send(seq, msg_id, body)
				continue
			var rc: ReliabilityChannel = _rel[ch]
			if rc.register_sent(seq, frame) < 0:
				_set_state(State.CLOSED)
				push_error("可靠层重传队列溢出，断连")
				return
			_send_datagram_raw(_build_datagram(seq, 0, frame))
		else:
			# 不可靠：不登记
			_send_datagram_raw(_build_datagram(seq, 0, _encode_frame(ch, msg_id, body)))


func _frag_and_send(seq: int, msg_id: int, body: PackedByteArray) -> void:
	## 分片帧各自带真实 msg_id（接收端重组后据此分发）；全部登记同一可靠 seq（重传整体重发）
	var chunk_len := MTU - HEADER_LEN - 5
	var frag_cnt := ceili(float(body.size()) / float(chunk_len))
	if frag_cnt > Reassembly.MAX_FRAG_CNT:
		_malformed += 1
		return
	_frag_id = (_frag_id + 1) & 0xFFFF
	var rc: ReliabilityChannel = _rel[MsgIds.CH_RELIABLE_ORDERED]
	for i in range(frag_cnt):
		var w := ByteWriter.new(64)
		w.write_u16(_frag_id)
		w.write_u8(i)
		w.write_u8(frag_cnt)
		var chunk := body.slice(i * chunk_len, mini(body.size(), (i + 1) * chunk_len))
		w.write_bytes(chunk)
		var frame := _encode_frame(MsgIds.CH_RELIABLE_ORDERED, msg_id, w.data())
		if rc.register_sent(seq, frame) < 0:
			_set_state(State.CLOSED)
			push_error("可靠层重传队列溢出，断连")
			return
		_send_datagram_raw(_build_datagram(seq, FLAG_FRAG, frame))


func _build_datagram(seq: int, flags: int, payload: PackedByteArray) -> PackedByteArray:
	var w := ByteWriter.new(HEADER_LEN + payload.size())
	w.write_u16(MAGIC)
	w.write_u8(VERSION)
	w.write_u8(flags)
	w.write_u32(_conn_id)
	w.write_u16(seq)
	w.write_u16(_recv_tracker.last_recv_seq if _recv_tracker.last_recv_seq >= 0 else 0)
	w.write_u32(_recv_tracker.ack_bits)
	w.write_bytes(payload)
	return w.data()


func _send_datagram_raw(datagram: PackedByteArray) -> void:
	if _socket == null:
		return
	_socket.put_packet(datagram)
	_packets_out += 1
	_bytes_out += datagram.size()


func _send_pure_ack() -> void:
	if _socket == null:
		return
	_send_datagram_raw(_build_datagram(_next_seq(), FLAG_PURE_ACK, PackedByteArray()))


func _encode_frame(ch: int, msg_id: int, body: PackedByteArray) -> PackedByteArray:
	var w := ByteWriter.new(4 + body.size())
	w.write_u16((ch << 12) | (msg_id & 0x0FFF))
	w.write_u16(body.size())
	w.write_bytes(body)
	return w.data()


# ══ 接收侧 ═════════════════════════════════════════════════════════════════

func _recv_all() -> void:
	if _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var datagram: PackedByteArray = _socket.get_packet()
		_packets_in += 1
		_parse_datagram(datagram)


func _parse_datagram(datagram: PackedByteArray) -> void:
	var r := ByteReader.new(datagram)
	if datagram.size() < HEADER_LEN:
		_malformed += 1
		return
	if r.read_u16() != MAGIC:
		_bad_magic += 1
		return
	if r.read_u8() > VERSION:
		_malformed += 1
		return
	var flags := r.read_u8()
	r.read_u32()                       # conn_id（NAT 漂移：仅用于会话识别，不做校验）
	var peer_seq := r.read_u16()
	var peer_ack := r.read_u16()
	var peer_ack_bits := r.read_u32()
	# ack 回传裁剪：对端确认了我方发的哪些 seq（全局序号空间，跨通道统一裁剪）
	for ch in _rel:
		_rel[ch].on_ack(peer_ack, peer_ack_bits)
	# RTT 采样（接口保留：真联网后由 ack 时间戳补充）
	if flags & FLAG_PURE_ACK:
		return   # 纯 ACK 帧无消息
	# 解析消息帧
	while r.remaining() >= 4:
		var head := r.read_u16()
		var ch := head >> 12
		var msg_id := head & 0x0FFF
		var len := r.read_u16()
		if r.remaining() < len:
			_malformed += 1
			return
		var body := r.read_bytes(len)
		if flags & FLAG_FRAG:
			# 分片（Ch2）：body 前置分片头；重组完成用帧头真实 msg_id 分发
			var fr := ByteReader.new(body)
			var frag_id := fr.read_u16()
			var frag_idx := fr.read_u8()
			var frag_cnt := fr.read_u8()
			var done = _reassembly.feed(frag_id, frag_idx, frag_cnt, fr.read_rest(),
				Time.get_ticks_msec() / 1000.0)
			if done == null or done.is_empty():
				continue   # 畸形（已计数）/ 未集齐 / 重复
			_deliver_frame(ch, peer_seq, msg_id, done)
			continue
		_deliver_frame(ch, peer_seq, msg_id, body)


func _deliver_frame(ch: int, peer_seq: int, msg_id: int, body: PackedByteArray) -> void:
	match ch:
		MsgIds.CH_RELIABLE_ORDERED:
			_ordered_deliver(peer_seq, msg_id, body)
		MsgIds.CH_RELIABLE_UNORDERED:
			# 可靠无序：去重即投递（T0005M03F02）
			if _recv_tracker.on_recv(peer_seq):
				message_received.emit(ch, msg_id, body)
		_:
			# Ch0 直接投递（不去重不排序）
			_recv_tracker.on_recv(peer_seq)   # 仍参与 ack 记账
			message_received.emit(ch, msg_id, body)




func _ordered_deliver(peer_seq: int, msg_id: int, body: PackedByteArray) -> void:
	## Ch2 可靠有序投递（review 修复：墓碑去重 + ack 记账回路，杜绝重复投递/静默丢失/对端重传超限）。
	## 协议裁定：Ch2 每 datagram 至多一条帧（发送端逐条独立 datagram，已如此；T0002M03 的
	## 同 datagram 合并仅适用于 Ch0/Ch1 —— 已在 README 标注，服务端对齐此约定）。
	## 工程权衡（对 UDP 乱序）：先到先投（无握手序号同步时无法做严格 HOL blocking）；
	## 有序性由三层保证 —— ① 墓碑去重（每 seq 至多投递一次，杜绝旧帧重复覆盖）
	## ② ack 连续语义（reliability.on_recv 只确认连续段，缺失帧被 RTO 重传补齐，杜绝静默丢失）
	## ③ 关键消息自带 serverTick（Keyframe/FullState），上层拒绝旧 tick 覆盖（防状态回退）。
	## ⚠️ ack 记账（review blocking 修复）：Ch2 帧必须参与 on_recv，
	##    否则 datagram 头的 ack/ack_bits 永不包含 Ch2 seq → 对端重传队列永不裁剪 → RTO 超限断连。
	_recv_tracker.on_recv(peer_seq)
	if not _ordered_recv.has(MsgIds.CH_RELIABLE_ORDERED):
		_ordered_recv[MsgIds.CH_RELIABLE_ORDERED] = {"seen": {}, "buffer": {}}
	var st: Dictionary = _ordered_recv[MsgIds.CH_RELIABLE_ORDERED]
	var seen: Dictionary = st.seen
	if seen.has(peer_seq):
		return   # 重复/已投递（墓碑）
	seen[peer_seq] = true
	var buf: Dictionary = st.buffer
	if not buf.has(peer_seq):
		buf[peer_seq] = []
	buf[peer_seq].append({"msg_id": msg_id, "body": body})
	# 按到达序投递本 seq 的全部帧（同 datagram 内帧序由编码序保证）
	for frame in buf[peer_seq]:
		message_received.emit(MsgIds.CH_RELIABLE_ORDERED, frame.msg_id, frame.body)
	buf.erase(peer_seq)
	# seen 上限防护（u16 序号空间，正常会话帧数远低于上限）
	if seen.size() > 16384:
		var keys := seen.keys()
		keys.sort()
		for i in range(keys.size() - 16384):
			seen.erase(keys[i])


func _rand_conn_id() -> int:
	return (randi() & 0xFFFF) | ((randi() & 0xFFFF) << 16)


func _set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	state_changed.emit(s)
