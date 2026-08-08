## fake_transport.gd — 环回 + 故障注入（T0005M13F01 / M13F05）
## 实现 ISoupTransport 同一接口，上层永远不知道自己连的是真网络还是环回。
## 用途：
##   1. 单机原型（P0 主交付）：attach_local_authority 后，0x080 输入进本地权威，
##      权威按服务端规则模拟并回投 Snapshot/TerritoryDelta。
##   2. 故障注入测试：固定延迟 / 抖动 / 丢包 / 乱序 / 重复 / 突发全丢。

class_name FakeTransport
extends ISoupTransport

# 故障参数
var latency_ms: float = 0.0
var jitter_ms: float = 0.0
var loss_rate: float = 0.0        # 0..1
var reorder_rate: float = 0.0     # 0..1（投递队列乱序）
var duplicate_rate: float = 0.0   # 0..1
var burst_loss_left: float = 0.0  # >0 = 突发全丢剩余秒数

var _state: int = State.CLOSED
var _queue: Array = []            # {delay: float, ch, msg_id, body, seq: int}
var _seq: int = 0
var _authority: Node = null       # LocalAuthority（单机模式）

# 诊断（喂 A0001 网络指示）
var _srtt_ms: int = 0
var _rttvar_ms: int = 0
var _loss_permille: int = 0


func set_fault(p_latency_ms: float, p_jitter_ms: float, p_loss_rate: float,
		p_reorder_rate: float, p_duplicate_rate: float,
		p_burst_loss_on: bool, burst_duration_s: float) -> void:
	latency_ms = p_latency_ms
	jitter_ms = p_jitter_ms
	loss_rate = p_loss_rate
	reorder_rate = p_reorder_rate
	duplicate_rate = p_duplicate_rate
	if p_burst_loss_on:
		burst_loss_left = burst_duration_s if burst_duration_s > 0.0 else 2.0


func attach_local_authority(authority: Node) -> void:
	_authority = authority


## 服务端→客户端方向的注入（本地权威调用），同样走故障注入管线
func inject(ch: int, msg_id: int, body: PackedByteArray) -> void:
	_enqueue(ch, msg_id, body)


# ══ ISoupTransport 实现 ═══════════════════════════════════════════════════

func connect_to(_host: String, _port: int, _token: PackedByteArray) -> void:
	_state = State.CONNECTING
	_set_state(State.OPEN)   # 环回立即可用


func disconnect_from() -> void:
	_queue.clear()
	_set_state(State.CLOSED)


func poll(delta: float) -> void:
	if _state != State.OPEN:
		return
	if burst_loss_left > 0.0:
		burst_loss_left -= delta
		# 突发全丢：不投递任何包（保留队列）
		return
	var dt := delta * 1000.0
	var deliver: Array = []
	for i in range(_queue.size()):
		var item: Dictionary = _queue[i]
		item.delay -= dt
		if item.delay <= 0.0:
			deliver.append(i)
	# 倒序取（避免索引失效）
	deliver.sort()
	for i in range(deliver.size() - 1, -1, -1):
		var idx: int = deliver[i]
		var item: Dictionary = _queue[idx]
		_queue.remove_at(idx)
		_emit(item)


func send(ch: int, msg_id: int, body: PackedByteArray) -> void:
	if _state != State.OPEN:
		return
	if _authority != null and MsgIds.is_client_to_server(msg_id):
		# 单机模式：输入直接进本地权威（不走故障注入的下行管线）
		_authority.handle_client_message(msg_id, body)
		return
	_enqueue(ch, msg_id, body)


func _enqueue(ch: int, msg_id: int, body: PackedByteArray) -> void:
	if _state != State.OPEN:
		return
	if loss_rate > 0.0 and randf() < loss_rate:
		_loss_permille = int(loss_rate * 1000.0)
		return   # 丢包
	var delay := latency_ms
	if jitter_ms > 0.0:
		delay += randf_range(-jitter_ms, jitter_ms)
	if delay < 0.0:
		delay = 0.0
	_seq += 1
	var item := {"delay": delay, "ch": ch, "msg_id": msg_id, "body": body, "seq": _seq}
	# 乱序：小概率插到队首附近（让后面先到）
	if reorder_rate > 0.0 and _queue.size() > 0 and randf() < reorder_rate:
		_queue.insert(randi() % _queue.size(), item)
	else:
		_queue.append(item)
	if duplicate_rate > 0.0 and randf() < duplicate_rate:
		var dup := item.duplicate()
		dup.delay += 5.0
		dup.seq = _seq + 1000
		_queue.append(dup)


func _emit(item: Dictionary) -> void:
	message_received.emit(item.ch, item.msg_id, item.body)


func get_srtt_ms() -> int:
	return _srtt_ms

func get_rttvar_ms() -> int:
	return _rttvar_ms

func get_loss_permille() -> int:
	return _loss_permille

func get_state() -> int:
	return _state

func enter_grace() -> void:
	if _state == State.OPEN:
		_set_state(State.GRACE)

func tick_heartbeat(_delta: float) -> void:
	pass   # 环回无需心跳


func _set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	state_changed.emit(s)
