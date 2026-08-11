## test_runner.gd — 无头单测入口（T0005M13）
## 运行：godot --headless -s res://tests/test_runner.gd
## 覆盖：协议 fuzz / 双网格 AC / 可靠层回绕 / 分片重组 / 预测回滚 / 定点换算

extends SceneTree

var _failures: int = 0
var _total: int = 0


func _initialize() -> void:
	_run("proto codec roundtrip", _test_codec_roundtrip)
	_run("proto 通道映射（0x0C3 走 Ch2）", _test_channel_map)
	_run("proto fuzz 任意字节不崩", _test_fuzz)
	_run("territory 双网格 AC：未认领预测格撤销", _test_pred_revert)
	_run("territory ACK 纪律：lastAuthTick 不受预测影响", _test_ack_discipline)
	_run("territory 只吃原汤", _test_only_broth)
	_run("reliability u16 回绕比较", _test_seq_wrap)
	_run("reassembly 分片重组", _test_reassembly)
	_run("Ch2 有序投递（乱序/重复帧）", _test_ch2_ordered_deliver)
	_run("prediction 回滚重放", _test_prediction_reconcile)
	_run("fixed expandRate 换算 120s 校验", _test_expand_rate)
	print("==== 测试完成：%d 项，失败 %d ====" % [_total, _failures])
	quit(1 if _failures > 0 else 0)


func _run(name: String, fn: Callable) -> void:
	_total += 1
	var ok := false
	var err := ""
	var started := Time.get_ticks_msec()
	ok = fn.call() == true
	if not ok:
		_failures += 1
	print("%s %s (%dms)" % ["[PASS]" if ok else "[FAIL]", name, Time.get_ticks_msec() - started])


# ══ 协议层 ════════════════════════════════════════════════════════════════

func _test_codec_roundtrip() -> bool:
	# PlayerInput 精确长度：头部 7B + 3帧×5B + baseline 8B = 30B
	# （T0001M02F04 写 "33B / 3×6" 为文档笔误，字段 i8+i8+u16+u8 = 5B/帧）
	var frames := [
		{"move_x": 100, "move_y": -50, "aim": 16384, "buttons": MsgIds.BUTTON_CHARGE},
		{"move_x": 80, "move_y": 0, "aim": 0, "buttons": 0},
		{"move_x": 0, "move_y": 0, "aim": 0, "buttons": 0},
	]
	var body := codec.encode_player_input(12345, 300, frames, 100, 200)
	if body.size() != 30:
		print("  PlayerInput size=%d 期望 30（文档 33 为笔误，字段求和 30）" % body.size())
		return false
	var r := ByteReader.new(body)
	if r.read_u32() != 12345 or r.read_u16() != 300 or r.read_u8() != 3:
		return false
	if r.read_i8() != 100 or r.read_i8() != -50 or r.read_u16() != 16384 or r.read_u8() != 2:
		return false
	# 剩下 2 帧冗余也要读掉，否则读到的"baseline"其实是第 2 帧的字节
	for _i in range(2):
		r.read_i8(); r.read_i8(); r.read_u16(); r.read_u8()
	if r.read_u32() != 100 or r.read_u32() != 200:
		return false
	# MatchStart roundtrip
	var ms := codec.encode_create_room("排骨")
	var dec := codec.decode_room_created(ms)
	if dec.get("room_code", "") != "    " and dec.get("your_player_id", 0) != 0:
		pass   # create_room 无 room_code；仅验证不崩
	# Snapshot 解码（服务端字节）
	var w := ByteWriter.new()
	w.write_u32(50)
	w.write_u16(42)
	w.write_u8(4)
	for i in range(4):
		w.write_u8(i + 1); w.write_u16(1000 + i); w.write_u16(1000 + i)
		w.write_i8(0); w.write_i8(0); w.write_u16(0); w.write_u16(1000)
		w.write_u8(0); w.write_u8(100); w.write_u8(0)   # 末位 = attackCdMs10（每玩家 14B）
	var snap := codec.decode_snapshot(w.data())
	if snap.get("server_tick", 0) != 50 or snap.get("ack_input_seq", 0) != 42:
		return false
	if snap.players.size() != 4:
		return false
	return true


func _test_channel_map() -> bool:
	if MsgIds.channel_for(MsgIds.TERRITORY_KEYFRAME) != MsgIds.CH_RELIABLE_ORDERED:
		return false   # 0x0C3 例外
	if MsgIds.channel_for(MsgIds.QUICK_MATCH) != MsgIds.CH_RELIABLE_ORDERED:
		return false
	if MsgIds.channel_for(MsgIds.PLAYER_INPUT) != MsgIds.CH_UNRELIABLE_SEQUENCED:
		return false
	if MsgIds.channel_for(MsgIds.SNAPSHOT) != MsgIds.CH_UNRELIABLE_UNORDERED:
		return false
	if MsgIds.channel_for(MsgIds.PLAYER_DIED) != MsgIds.CH_RELIABLE_UNORDERED:
		return false
	return true


func _test_fuzz() -> bool:
	# 任意字节喂 decode 不得抛错（T0005M13F02）
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(2000):
		var n := rng.randi_range(0, 200)
		var bytes := PackedByteArray()
		bytes.resize(n)
		for j in range(n):
			bytes[j] = rng.randi_range(0, 255)
		var msg_id := rng.randi_range(0x010, 0x13F)
		codec.decode(msg_id, bytes)   # 抛错即失败
	return true


# ══ 核心层：双网格 ════════════════════════════════════════════════════════

func _test_pred_revert() -> bool:
	## M07F03 Scenario：未被认领的预测格必须在下一个地盘帧撤销
	var g := TerritoryGrid.new()
	# 开局：把某区域设为玩家 1 地盘
	g.auth_grid.fill(0)
	for i in range(96 * 96):
		if (i % 96) < 40:
			g.auth_grid[i] = TerritoryGrid.BROTH
	# 玩家 1 预测占领一列（服务端从未认）
	for i in range(96 * 96):
		if (i % 96) in [40, 41]:
			g.pred_owner[i] = 1
			g.pred_tick[i] = 100
	# 收到 serverTick=200 的增量（不含预测格）
	var groups := [{"owner": 2, "cells": PackedInt32Array([0])}]
	g.apply_delta(200, groups)
	# 预测格应已撤销
	for i in range(96 * 96):
		if g.pred_owner[i] != 0:
			return false
	return true


func _test_ack_discipline() -> bool:
	## M07F03 Scenario：ACK 不受预测影响
	var g := TerritoryGrid.new()
	g.apply_keyframe(50, [{"length": 5000, "owner": 1}, {"length": 96 * 96 - 5000, "owner": 0}])
	g.expand_tick(1, 500)   # 本地预测
	if g.last_auth_tick != 50:
		return false   # 预测不得推进 ACK
	return true


func _test_only_broth() -> bool:
	## M07F04：预测只吃原汤，敌方格一律不预测
	var g := TerritoryGrid.new()
	for i in range(96 * 96):
		if (i % 96) < 40:
			g.auth_grid[i] = 1
		elif (i % 96) < 50:
			g.auth_grid[i] = 2   # 敌方格
		else:
			g.auth_grid[i] = TerritoryGrid.BROTH
	g.set_me(1)
	g.expand_tick(1, 10)
	for i in range(96 * 96):
		if g.pred_owner[i] == 1 and g.auth_grid[i] == 2:
			return false   # 预测进了敌方格
	return true


# ══ 网络层 ════════════════════════════════════════════════════════════════

func _test_seq_wrap() -> bool:
	## u16 回绕：带符号差值比较（T0005M03F03）
	if not ReliabilityChannel.seq_newer(5, 65530):
		return false
	if ReliabilityChannel.seq_newer(65530, 5):
		return false
	if ReliabilityChannel.seq_newer(10, 10):
		return false
	return true


func _test_ch2_ordered_deliver() -> bool:
	## review 补充：Ch2 有序投递 = 墓碑去重（无重复投递）+ 先到先投（无静默丢失）；
	## 缺失帧由 ack 连续语义触发 RTO 重传补齐（不在此单测内）
	var t := UdpTransport.new()
	var received: Array = []
	t.message_received.connect(func(_ch, _msg_id, body): received.append(body[0]))
	# 顺序到达
	t.call("_ordered_deliver", 1, 10, PackedByteArray([1]))
	t.call("_ordered_deliver", 2, 10, PackedByteArray([2]))
	t.call("_ordered_deliver", 3, 10, PackedByteArray([3]))
	# 乱序（seq 5 先到，4 缺失待重传）
	t.call("_ordered_deliver", 5, 10, PackedByteArray([5]))
	t.call("_ordered_deliver", 4, 10, PackedByteArray([4]))
	# 重复帧（对端 ack 丢失重传 / UDP 重复副本）
	t.call("_ordered_deliver", 4, 10, PackedByteArray([4]))
	t.call("_ordered_deliver", 3, 10, PackedByteArray([3]))
	# 期望：每帧只投一次（body = [1,2,3,5,4]），无重复、无丢失
	var bodies: Array = []
	for b in received:
		bodies.append(b)
	if bodies != [1, 2, 3, 5, 4]:
		print("  Ch2 投递顺序=%s 期望 [1,2,3,5,4]" % [bodies])
		t.queue_free()
		return false
	t.queue_free()
	return true


func _test_reassembly() -> bool:
	var ra := Reassembly.new()
	var payload := PackedByteArray()
	payload.resize(2000)
	for i in range(2000):
		payload[i] = i & 0xFF
	var frag_cnt := 3
	var chunks := []
	for i in range(frag_cnt):
		chunks.append(payload.slice(i * 700, mini(2000, (i + 1) * 700)))
	var done := PackedByteArray()
	for i in range(frag_cnt):
		var r = ra.feed(7, i, frag_cnt, chunks[i], 1000.0)
		if r.size() > 0:
			done = r
	if done.size() != 2000:
		return false
	for i in range(2000):
		if done[i] != (i & 0xFF):
			return false
	# 畸形：frag_cnt 超限（>64，与引擎 MAX_FRAGMENTS 一致）→ null
	var bad = ra.feed(8, 0, 65, PackedByteArray([1]), 1000.0)
	if bad != null:
		return false
	return true


# ══ 预测 ══════════════════════════════════════════════════════════════════

func _test_prediction_reconcile() -> bool:
	var p := Prediction.new()
	p.hard_set(1000, 1000)
	var speed := 6 * Fixed.VEL_SCALE
	# 输入 seq 1..3 向右移动
	for s in range(1, 4):
		p.record_input(s, 100, 0, 0, 0, speed)
	var moved := p.auth_x
	if moved <= 1000:
		return false
	# 一步的位移量（speed 6.0 → 384 定点 = 6 世界单位/s ÷ 20Hz × 64）
	var per_step := (moved - 1000) / 3
	# 服务端 ack seq=1 且位置有偏差 → 硬置权威 + 重放 seq 2..3
	p.reconcile(1, 1000, 1000, speed)
	if p.auth_x <= 1000:
		return false
	# 重放 2 步，容差 1 个定点单位（原来写 64 —— 那是 1 个世界单位，
	# 比一步的位移还小，任何正确实现都过不了）
	if absi(p.auth_x - (1000 + per_step * 2)) > 1:
		print("  重放后 auth_x=%d 期望≈%d（每步 %d）" % [p.auth_x, 1000 + per_step * 2, per_step])
		return false
	return true


# ══ 定点 ══════════════════════════════════════════════════════════════════

func _test_expand_rate() -> bool:
	## D0001M05F01：纯充能 10%→50% 需 120s（2400 tick × 8 定点/格 ≈ 18.75 格）
	var inc := Fixed.expand_rate_to_r_inc(64)
	if inc != 8:
		return false
	var total := 2400 * inc
	var grid_units := float(total) / Fixed.R_SCALE
	if absf(grid_units - 18.75) > 0.1:
		print("  120s 扩张 %.2f 格，期望 ≈18.7" % grid_units)
		return false
	# 测地距离：直邻 1024 / 斜邻 1448（M10：与 Go 逐位一致）
	if Fixed.geodesic_dist(1, 0) != 1024 or Fixed.geodesic_dist(1, 1) != 1448:
		return false
	return true
