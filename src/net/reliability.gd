## reliability.gd — 可靠层（T0005M03F03）
## - RTO = SRTT + 4×RTTVAR，夹 [50ms, 1000ms]（Jacobson/Karels）
## - 重传队列 ≤ 64 条/通道，溢出 → 断连并报错
## - 序号比较用带符号差值 (int16)(a-b) > 0（u16 回绕安全）
## - ack_bits 32 位滑窗
## 纯 GDScript，不 extends Node（可无头单测）。

class_name ReliabilityChannel

const RETRANS_MAX := 64
const RETRANS_ATTEMPT_MAX := 16     # 单包最大重传次数，超出视为链路不可用（防无限退避）
const RTO_MIN_MS := 50.0
const RTO_MAX_MS := 1000.0

# 发送侧
var send_seq: int = 0
var retrans: Array = []        # [{seq:int, data:PackedByteArray, sent_at_ms:float, attempts:int}]
var broken := false            # 有包超限 → 调用方断连

# 接收侧
var last_recv_seq: int = -1    # 已投递/已确认的最大连续 seq（Ch2 语义）
var ack_bits: int = 0          # 最近 32 个收包位图（bit0 = last_recv_seq 是否已收）

# RTT 估计（喂给 M05F02 的 lead 计算：SRTT/RTTVAR 直接复用这里）
var srtt_ms: float = 100.0
var rttvar_ms: float = 50.0
var rto_ms: float = 300.0

# 诊断
var sent_count: int = 0
var retrans_count: int = 0
var dropped_old_count: int = 0


## 带符号差值比较：a 是否比 b 新（u16 回绕安全，T0005M03F03）
static func seq_newer(a: int, b: int) -> bool:
	var diff := (a - b) & 0xFFFF
	if diff >= 0x8000:
		return false
	return diff > 0


## 登记发送帧（seq 由调用方给定 —— 全局序号空间，跨通道统一，保证 ack_bits 正确裁剪）
## 返回 -1 表示队列溢出（调用方断连并报错）
func register_sent(seq: int, data: PackedByteArray) -> int:
	retrans.append({"seq": seq, "data": data, "sent_at_ms": 0.0, "last_sent_ms": 0.0})
	if retrans.size() > RETRANS_MAX:
		return -1
	return seq


## 收到对端 ack/ack_bits，裁剪本地重传队列
func on_ack(ack: int, ack_bits_in: int) -> void:
	var keep: Array = []
	for item in retrans:
		if item.seq == ack:
			continue   # 该 seq 已被确认
		var bit := (ack - item.seq) & 0xFFFF
		if bit > 0 and bit <= 32 and (ack_bits_in & (1 << (bit - 1))) != 0:
			continue   # 在滑窗内且被确认
		keep.append(item)
	retrans = keep


## 收到对端数据帧 seq：登记接收侧 ack 状态。
## 返回 true 表示该 seq 是新的（未被去重），false 表示重复/过期。
## ack 语义（review 修复）：last_recv_seq = 连续收到的最末 seq（非跳变），
## 缺失帧不进入确认段 → 对端 RTO 重传补齐（Ch2 有序的可靠性来源）。
func on_recv(seq: int) -> bool:
	if last_recv_seq < 0:
		last_recv_seq = seq
		ack_bits = 1
		return true
	if seq == last_recv_seq:
		return false
	if seq_newer(seq, last_recv_seq):
		var dist := (seq - last_recv_seq) & 0xFFFF
		if dist > 32:
			dist = 32
		ack_bits = ((ack_bits << dist) | 1) & 0xFFFFFFFF
		# 连续推进（review 修复）：仅当 seq 恰好接续（dist==1）才推进 last_recv_seq；
		# 跳变（dist>1）只置位不推进 → 缺失帧不在确认段内 → 对端 RTO 重传补齐
		if dist == 1:
			last_recv_seq = seq
		return true
	# 过期包：检查是否在滑窗内（在窗内说明重复投递，去重；窗外丢弃）
	var back := (last_recv_seq - seq) & 0xFFFF
	if back > 0 and back <= 32:
		if (ack_bits & (1 << (back - 1))) != 0:
			return false
		ack_bits |= (1 << (back - 1))
		return false
	dropped_old_count += 1
	return false


## RTT 采样（Jacobson/Karels，同 T0002M03F03）
func sample_rtt(rtt_ms: float) -> void:
	if rtt_ms < 0.0:
		return
	srtt_ms = 0.875 * srtt_ms + 0.125 * rtt_ms
	var dev := absf(rtt_ms - srtt_ms)
	rttvar_ms = 0.75 * rttvar_ms + 0.25 * dev
	rto_ms = srtt_ms + 4.0 * rttvar_ms
	rto_ms = clampf(rto_ms, RTO_MIN_MS, RTO_MAX_MS)


## 每帧驱动：超时重传（返回是否有重传发生；attempts 超限置 broken）
func poll_retrans(now_ms: float, delta_ms: float) -> bool:
	var any := false
	for item in retrans:
		if item.last_sent_ms <= 0.0:
			item.last_sent_ms = now_ms
			continue
		if now_ms - item.last_sent_ms >= rto_ms:
			item.last_sent_ms = now_ms
			item.attempts = item.get("attempts", 0) + 1
			if item.attempts > RETRANS_ATTEMPT_MAX:
				broken = true   # 链路不可用，调用方断连
				continue
			retrans_count += 1
			any = true
			# 指数退避
			rto_ms = minf(rto_ms * 2.0, RTO_MAX_MS)
	return any


func pending_count() -> int:
	return retrans.size()
