## codec.gd — T0001M02 全部消息编解码（冻结契约）
## 约定（T0005M04F02）：
##   - 全部小端；未知 msg_id 丢弃并计数不报错；长度不符丢弃并计数
##   - 热路径（0x080/0x0C0/0x0C1）复用预分配 writer，不每帧 new
##   - decode 失败一律返回 null，绝不抛错（对齐 T0002M08F02）
## 纯 GDScript，不 extends Node。

class_name codec

# ── 丢弃计数（诊断/埋点用，喂 T0001M08 的异常计数）──────────────────────────
static var drop_count := 0          # 长度不符/畸形
static var unknown_count := 0       # 未知 msg_id

# ══ 大厅（Ch2）═════════════════════════════════════════════════════════════

static func encode_create_room(nickname: String) -> PackedByteArray:
	var w := ByteWriter.new(16)
	w.write_fixed_string(nickname, ByteReader.NICKNAME_LEN)
	return w.data()


static func encode_join_room(room_code: String, nickname: String) -> PackedByteArray:
	var w := ByteWriter.new(20)
	w.write_fixed_string(room_code, 4)
	w.write_fixed_string(nickname, ByteReader.NICKNAME_LEN)
	return w.data()


static func encode_quick_match(nickname: String) -> PackedByteArray:
	return encode_create_room(nickname)


static func encode_leave_room() -> PackedByteArray:
	return PackedByteArray()


static func encode_select_ingredient(ingredient_id: int) -> PackedByteArray:
	var w := ByteWriter.new(1)
	w.write_u8(ingredient_id)
	return w.data()


static func encode_set_ready(ready: bool) -> PackedByteArray:
	var w := ByteWriter.new(1)
	w.write_u8(1 if ready else 0)
	return w.data()


static func decode_room_created(body: PackedByteArray) -> Dictionary:
	var r := ByteReader.new(body)
	if body.size() < 5:
		drop_count += 1
		return {}
	return {"room_code": r.read_fixed_string(4), "your_player_id": r.read_u8()}


static func decode_join_result(body: PackedByteArray) -> Dictionary:
	var r := ByteReader.new(body)
	if body.size() < 2:
		drop_count += 1
		return {}
	return {"code": r.read_u8(), "your_player_id": r.read_u8()}


static func decode_room_state(body: PackedByteArray) -> Dictionary:
	## roomCode[4] · n u8 · n×{playerId u8, nickname[16], ingredientId u8, ready u8}
	var r := ByteReader.new(body)
	if body.size() < 5:
		drop_count += 1
		return {}
	var d := {
		"room_code": r.read_fixed_string(4),
		"n": r.read_u8(),
		"players": [],
	}
	for i in range(d.n):
		if r.remaining() < 19:
			drop_count += 1
			return {}
		d.players.append({
			"player_id": r.read_u8(),
			"nickname": r.read_fixed_string(16),
			"ingredient_id": r.read_u8(),
			"ready": r.read_u8() != 0,
		})
	return d


static func decode_room_closed(body: PackedByteArray) -> Dictionary:
	if body.size() < 1:
		drop_count += 1
		return {}
	return {"reason": body[0]}


# ══ 对局控制（Ch2）═════════════════════════════════════════════════════════

static func decode_match_start(body: PackedByteArray) -> Dictionary:
	## mapId u16 · startTick u32 · stewTicks u32 · gridW u8 · gridH u8 · playerCount u8
	## [per player] playerId u8 · ingredientId u8 · nickname[16] · spawnX u16 · spawnY u16
	var r := ByteReader.new(body)
	## mapId u16 · startTick u32 · stewTicks u32 · gridW u8 · gridH u8 · playerCount u8 = 13B
	if body.size() < 13:
		drop_count += 1
		return {}
	var d := {
		"map_id": r.read_u16(),
		"start_tick": r.read_u32(),
		"stew_ticks": r.read_u32(),
		"grid_w": r.read_u8(),
		"grid_h": r.read_u8(),
		"player_count": r.read_u8(),
		"players": [],
	}
	## 每玩家 playerId u8 · ingredientId u8 · nickname[16] · spawnX u16 · spawnY u16 = 22B
	for i in range(d.player_count):
		if r.remaining() < 22:
			drop_count += 1
			return {}
		d.players.append({
			"player_id": r.read_u8(),
			"ingredient_id": r.read_u8(),
			"nickname": r.read_fixed_string(16),
			"spawn_x": r.read_u16(),
			"spawn_y": r.read_u16(),
		})
	return d


static func decode_match_end(body: PackedByteArray) -> Dictionary:
	## playerCount u8 · [per player] playerId u8 · rank u8 · areaPermyriad u16 · kills u8
	var r := ByteReader.new(body)
	if body.size() < 1:
		drop_count += 1
		return {}
	var d := {"player_count": r.read_u8(), "players": []}
	for i in range(d.player_count):
		if r.remaining() < 5:
			drop_count += 1
			return {}
		d.players.append({
			"player_id": r.read_u8(),
			"rank": r.read_u8(),
			"area_permyriad": r.read_u16(),
			"kills": r.read_u8(),
		})
	return d


static func decode_full_state(body: PackedByteArray) -> Dictionary:
	## serverTick u32 · stewRemain u32 · playerCount u8
	## [per player] playerId u8 · posX u16 · posY u16 · aim u16 · mass u16 · stateFlags u8 · hp u8 · deathCount u8 · respawnAtTick u32
	## palletCount u8 → [palletId u8 · state u8]
	## dropCount u8 → [dropId u8 · type u8 · posX u16 · posY u16]
	var r := ByteReader.new(body)
	if body.size() < 9:
		drop_count += 1
		return {}
	var d := {
		"server_tick": r.read_u32(),
		"stew_remain": r.read_u32(),
		"player_count": r.read_u8(),
		"players": [],
		"pallets": [],
		"drops": [],
	}
	## 每玩家 playerId u8 · posX u16 · posY u16 · aim u16 · mass u16 · stateFlags u8 · hp u8 · deathCount u8 · respawnAtTick u32 = 16B
	for i in range(d.player_count):
		if r.remaining() < 16:
			drop_count += 1
			return {}
		d.players.append({
			"player_id": r.read_u8(),
			"pos_x": r.read_u16(),
			"pos_y": r.read_u16(),
			"aim": r.read_u16(),
			"mass": r.read_u16(),
			"state_flags": r.read_u8(),
			"hp": r.read_u8(),
			"death_count": r.read_u8(),
			"respawn_at_tick": r.read_u32(),
		})
	if r.remaining() >= 1:
		var n := r.read_u8()
		for i in range(n):
			if r.remaining() < 2:
				drop_count += 1
				return {}
			d.pallets.append({"pallet_id": r.read_u8(), "state": r.read_u8()})
	if r.remaining() >= 1:
		var m := r.read_u8()
		for i in range(m):
			if r.remaining() < 5:
				drop_count += 1
				return {}
			d.drops.append({"drop_id": r.read_u8(), "type": r.read_u8(), "pos_x": r.read_u16(), "pos_y": r.read_u16()})
	return d


# ══ 输入（Ch1，C→S）════════════════════════════════════════════════════════

## 编码 0x080 PlayerInput（携带最近 3 帧冗余 + 两个 baseline 回传，T0001M02F04）
## frames: Array[Dictionary]，最新在前，每个 {move_x, move_y, aim, buttons}
static func encode_player_input(client_tick: int, input_seq: int, frames: Array,
		last_recv_snapshot_tick: int, last_recv_territory_tick: int) -> PackedByteArray:
	var w := ByteWriter.new(33)
	w.write_u32(client_tick)
	w.write_u16(input_seq)
	w.write_u8(frames.size())
	for f in frames:
		w.write_i8(f.move_x)
		w.write_i8(f.move_y)
		w.write_u16(f.aim)
		w.write_u8(f.buttons)
	w.write_u32(last_recv_snapshot_tick)
	w.write_u32(last_recv_territory_tick)
	return w.data()


# ══ 同步（S→C）═════════════════════════════════════════════════════════════

static func decode_snapshot(body: PackedByteArray) -> Dictionary:
	## serverTick u32 · ackInputSeq u16 · playerCount u8
	## [per player] playerId u8 · posX u16 · posY u16 · velX i8 · velY i8 · aimAngle u16 · mass u16 · stateFlags u8 · hp u8
	## 每玩家 14B：13B 原字段 + attackCdMs10 u8（攻击冷却剩余，单位 10ms）
	## —— 加上冷却之后正好等于 T0001M02F05 文档写的 14 B/player。
	var r := ByteReader.new(body)
	if body.size() < 7:
		drop_count += 1
		return {}
	var d := {
		"server_tick": r.read_u32(),
		"ack_input_seq": r.read_u16(),
		"player_count": r.read_u8(),
		"players": [],
	}
	for i in range(d.player_count):
		if r.remaining() < 14:
			drop_count += 1
			return {}
		d.players.append({
			"player_id": r.read_u8(),
			"pos_x": r.read_u16(),
			"pos_y": r.read_u16(),
			"vel_x": r.read_i8(),
			"vel_y": r.read_i8(),
			"aim": r.read_u16(),
			"mass": r.read_u16(),
			"state_flags": r.read_u8(),
			"hp": r.read_u8(),
			"atk_cd_ms": r.read_u8() * 10,     # 攻击冷却剩余（编码单位 10ms）
		})
	return d


## 解码 0x0C1 TerritoryDelta：返回 {server_tick, since_tick, groups: [{owner, cells: PackedInt32Array}]}
static func decode_territory_delta(body: PackedByteArray) -> Dictionary:
	var r := ByteReader.new(body)
	if body.size() < 9:
		drop_count += 1
		return {}
	var d := {
		"server_tick": r.read_u32(),
		"since_tick": r.read_u32(),
		"group_count": r.read_u8(),
		"groups": [],
	}
	for i in range(d.group_count):
		if r.remaining() < 3:
			drop_count += 1
			return {}
		var owner := r.read_u8()
		var cell_count := r.read_u16()
		var cells := PackedInt32Array()
		cells.resize(cell_count)
		var idx := 0
		for j in range(cell_count):
			idx += r.read_varint()
			cells[j] = idx
		d.groups.append({"owner": owner, "cells": cells})
	return d


static func decode_score_tick(body: PackedByteArray) -> Dictionary:
	## serverTick u32 · ratios[4] u16 = 12B
	if body.size() < 12:
		drop_count += 1
		return {}
	# ⚠️ 顺序必须是 tick 在前。原来这里先读 4 个 u16 再读 u32，
	# 与编码端（local_authority._emit_score / 服务端 room）和上面那行文档都相反，
	# 结果 ratios = [tick低16位, tick高16位, p1面积, p2面积] ——
	# 面积条上「我」那一段显示的是 tick 数值，p3/p4 永远不显示。
	# verify_proto.py 没覆盖 0x0C2，所以一直没被抓到。
	var r := ByteReader.new(body)
	var server_tick := r.read_u32()
	var ratios := PackedInt32Array()
	for i in range(4):
		ratios.append(r.read_u16())
	return {"server_tick": server_tick, "ratios": ratios}


## 解码 0x0C3 TerritoryKeyframe：返回 {server_tick, runs: [{length, owner}]}
static func decode_territory_keyframe(body: PackedByteArray) -> Dictionary:
	var r := ByteReader.new(body)
	if body.size() < 6:
		drop_count += 1
		return {}
	var d := {"server_tick": r.read_u32(), "run_count": r.read_u16(), "runs": []}
	for i in range(d.run_count):
		if r.remaining() < 3:
			drop_count += 1
			return {}
		d.runs.append({"length": r.read_u16(), "owner": r.read_u8()})
	return d


## 编码 0x0C3 TerritoryKeyframe（本地权威/测试用，与服务端同构）
static func encode_territory_keyframe(server_tick: int, runs: Array) -> PackedByteArray:
	var w := ByteWriter.new(64)
	w.write_u32(server_tick)
	w.write_u16(runs.size())
	for run in runs:
		w.write_u16(run.length)
		w.write_u8(run.owner)
	return w.data()


# ══ 事件（Ch3，S→C）—— 只驱动表现，不改状态（T0005M04F03 铁律）──────────────

static func decode_player_died(body: PackedByteArray) -> Dictionary:
	if body.size() < 6:
		drop_count += 1
		return {}
	var r := ByteReader.new(body)
	return {"victim": r.read_u8(), "killer": r.read_u8(), "tick": r.read_u32()}


static func decode_player_respawn(body: PackedByteArray) -> Dictionary:
	## playerId u8 · posX u16 · posY u16 · tick u32 = 9B
	if body.size() < 9:
		drop_count += 1
		return {}
	var r := ByteReader.new(body)
	return {"player_id": r.read_u8(), "pos_x": r.read_u16(), "pos_y": r.read_u16(), "tick": r.read_u32()}


static func decode_pallet_down(body: PackedByteArray) -> Dictionary:
	if body.size() < 6:
		drop_count += 1
		return {}
	var r := ByteReader.new(body)
	return {"pallet_id": r.read_u8(), "by_player": r.read_u8(), "tick": r.read_u32()}


static func decode_drop_spawn(body: PackedByteArray) -> Dictionary:
	if body.size() < 6:
		drop_count += 1
		return {}
	var r := ByteReader.new(body)
	return {"drop_id": r.read_u8(), "type": r.read_u8(), "pos_x": r.read_u16(), "pos_y": r.read_u16()}


static func decode_drop_taken(body: PackedByteArray) -> Dictionary:
	if body.size() < 2:
		drop_count += 1
		return {}
	return {"drop_id": body[0], "player_id": body[1]}


static func decode_vault_start(body: PackedByteArray) -> Dictionary:
	if body.size() < 3:
		drop_count += 1
		return {}
	return {"player_id": body[0], "vault_id": body[1], "duration_ticks": body[2]}


static func decode_vault_end(body: PackedByteArray) -> Dictionary:
	if body.size() < 1:
		drop_count += 1
		return {}
	return {"player_id": body[0]}


static func decode_stir_warn(body: PackedByteArray) -> Dictionary:
	## 待 T0001 补充（T0005M14F02-2），预留布局：fireTick u32 · entryAngle u16 · arcSpan u16
	if body.size() < 8:
		drop_count += 1
		return {}
	var r := ByteReader.new(body)
	return {"fire_tick": r.read_u32(), "entry_angle": r.read_u16(), "arc_span": r.read_u16()}


static func decode_stir_sweep(body: PackedByteArray) -> Dictionary:
	## 待 T0001 补充，预留：tick u32 = 4B
	if body.size() < 4:
		drop_count += 1
		return {}
	return {"tick": ByteReader.new(body).read_u32()}


## 通用分发：msg_id → decode 函数（供收包侧统一调用，未知 id 计数不报错）
static func decode(msg_id: int, body: PackedByteArray) -> Dictionary:
	match msg_id:
		MsgIds.ROOM_CREATED: return decode_room_created(body)
		MsgIds.JOIN_RESULT: return decode_join_result(body)
		MsgIds.ROOM_STATE: return decode_room_state(body)
		MsgIds.ROOM_CLOSED: return decode_room_closed(body)
		MsgIds.MATCH_START: return decode_match_start(body)
		MsgIds.MATCH_END: return decode_match_end(body)
		MsgIds.FULL_STATE: return decode_full_state(body)
		MsgIds.SNAPSHOT: return decode_snapshot(body)
		MsgIds.TERRITORY_DELTA: return decode_territory_delta(body)
		MsgIds.SCORE_TICK: return decode_score_tick(body)
		MsgIds.TERRITORY_KEYFRAME: return decode_territory_keyframe(body)
		MsgIds.PLAYER_DIED: return decode_player_died(body)
		MsgIds.PLAYER_RESPAWN: return decode_player_respawn(body)
		MsgIds.PALLET_DOWN: return decode_pallet_down(body)
		MsgIds.DROP_SPAWN: return decode_drop_spawn(body)
		MsgIds.DROP_TAKEN: return decode_drop_taken(body)
		MsgIds.VAULT_START: return decode_vault_start(body)
		MsgIds.VAULT_END: return decode_vault_end(body)
		MsgIds.STIR_WARN: return decode_stir_warn(body)
		MsgIds.STIR_SWEEP: return decode_stir_sweep(body)
		_:
			unknown_count += 1
			return {}
