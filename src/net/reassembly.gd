## reassembly.gd — Ch2 分片重组（T0005M03F04）
## - 仅 Ch2 支持分片；分片头（flags.bit0=1 时，6B）：
##   frag_id(group) u16 · first_seq u16 · frag_idx u8 · frag_cnt u8
##   —— T0002M03F03 把分片格式留白，以引擎 `src/reliable/fragment.rs` 实现为准
## - frag_cnt ≤ 64（与引擎 MAX_FRAGMENTS 一致；引擎每片 ≤1100B → 约 70KB），超出视为畸形包
## - 按 frag_id 聚合，超时 2×RTO 未集齐 → 丢弃整组并计数（缺片由可靠层重传补上）
## 纯 GDScript，不 extends Node。

class_name Reassembly

const MAX_FRAG_CNT := 64           # = 引擎 fragment::MAX_FRAGMENTS
const BODY_MTU := 1200

# frag_id → {parts: {idx: PackedByteArray}, cnt: int, total: int, first_ms: float}
var _groups: Dictionary = {}
var discarded_count := 0
var malformed_count := 0

var _rto_ms := 300.0


func set_rto_ms(rto: float) -> void:
	_rto_ms = rto


## 喂入一个 Ch2 载荷。返回 null 表示畸形（已计数）；返回空数组表示尚未集齐/重复；返回非空数组表示整组重组完成。
func feed(frag_id: int, frag_idx: int, frag_cnt: int, payload: PackedByteArray, now_ms: float):
	if frag_cnt <= 0 or frag_cnt > MAX_FRAG_CNT:
		malformed_count += 1
		return null
	if frag_idx >= frag_cnt:
		malformed_count += 1
		return null
	if payload.size() > BODY_MTU - 5:
		malformed_count += 1
		return null
	if not _groups.has(frag_id):
		_groups[frag_id] = {
			"parts": {},
			"cnt": frag_cnt,
			"total": 0,
			"first_ms": now_ms,
		}
	var g: Dictionary = _groups[frag_id]
	if g.cnt != frag_cnt:
		malformed_count += 1
		_groups.erase(frag_id)
		return null
	if g.parts.has(frag_idx):
		return PackedByteArray()  # 重复片，忽略（非畸形非完成）
	g.parts[frag_idx] = payload
	g.total += payload.size()
	# 上限是「整条消息」的上限，不是单片的上限。
	# 原来拿 BODY_MTU(1200) 卡总长 —— 需要分片的消息按定义就 >1200，
	# 于是每一条分片消息都被判成畸形丢掉，Ch2 分片重组 100% 不可用
	# （0x0C3 地盘关键帧走 Ch2，联网时开局全量帧永远收不到）。
	if g.total > MAX_FRAG_CNT * BODY_MTU:
		malformed_count += 1
		_groups.erase(frag_id)
		return null
	if g.parts.size() == frag_cnt:
		var out := PackedByteArray()
		for i in range(frag_cnt):
			out.append_array(g.parts[i])
		_groups.erase(frag_id)
		return out
	return PackedByteArray()


## 每帧驱动：超时未集齐的整组丢弃（2×RTO）
func poll_expiry(now_ms: float) -> void:
	var expired: Array = []
	for fid in _groups:
		var g: Dictionary = _groups[fid]
		if now_ms - g.first_ms > 2.0 * _rto_ms:
			expired.append(fid)
	for fid in expired:
		_groups.erase(fid)
		discarded_count += 1


func pending_groups() -> int:
	return _groups.size()
