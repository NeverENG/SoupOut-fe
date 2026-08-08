## local_authority.gd — 单机本地权威（T0005M13F05：P0 主要交付物，不是测试工具）
## fake_transport 环回 + 跑在客户端进程里的极简权威，只实现移动、扩张、边界对抗。
## 服务端规则（T0001M03F04 边界对抗）：
##   目标格=原汤 → 占领正常速率；敌方且对方不在充能 → 抢占；敌方且对方在充能 → 僵持；锅外跳过
## 输出：0x0C0 Snapshot(20Hz) · 0x0C1 TerritoryDelta(10Hz, 累积式) · 0x0C2 ScoreTick(1Hz)
## 上层（battle_root）无感知 —— 它就是"服务端"。

class_name LocalAuthority
extends Node

const TICK_S := 0.05
const P1_COLOR_INDEX := 0

var transport: FakeTransport = null
var grid := TerritoryGrid.new()
var players := {}                  # id → {pos_x, pos_y, vel_x, vel_y, aim, buttons, hp, flags, nickname}
var me_id: int = 1
var expand_rate_fixed := 64
var tick: int = 0
var _tick_acc := 0.0
var _delta_accum := {}             # owner → Array[翻转记录 {tick, idx}]
var _last_delta_tick := 0
var _score_acc := 0.0
var _inside_cells := 0
var _seeding := false

var _match_start: Dictionary = {}


func begin_match(nickname: String, ingredient_id: int) -> void:
	grid = TerritoryGrid.new(96, 96)
	# 4 名玩家（me + 3 Bot），四角开局各 10% 地盘
	players.clear()
	var map_data := MapData.build_map(1)
	_inside_cells = _count_inside()
	for k in range(4):
		var pid := k + 1
		var spawn: Dictionary = map_data.spawns[k]
		players[pid] = {
			"pos_x": Fixed.world_to_fixed(spawn.x),
			"pos_y": Fixed.world_to_fixed(spawn.y),
			"vel_x": 0, "vel_y": 0,
			"aim": Fixed.angle_to_uint16(spawn.angle),
			"buttons": 0, "hp": 100,
			"flags": 0,
			"nickname": nickname if k == 0 else "Bot%d" % k,
			"ingredient": ingredient_id if k == 0 else k,
			"expand_r": 0,
		}
		# 开局 10% 圆盘（半径 ≈ 15.2 格，T0001M03F01）
		_seeding = true
		_seed_area(pid, spawn.x, spawn.y, 15.2)
		_seeding = false
	me_id = 1
	_match_start = {
		"map_id": 1, "start_tick": 0, "stew_ticks": 3600,   # D0001：3:00
		"grid_w": 96, "grid_h": 96, "player_count": 4, "players": [],
	}
	for k in range(4):
		var spawn: Dictionary = map_data.spawns[k]
		_match_start.players.append({
			"player_id": k + 1,
			"ingredient_id": players[k + 1].ingredient,
			"nickname": players[k + 1].nickname,
			"spawn_x": Fixed.world_to_fixed(spawn.x),
			"spawn_y": Fixed.world_to_fixed(spawn.y),
		})


func mock_match_start() -> Dictionary:
	return _match_start


func mock_me_id() -> int:
	return me_id


## 开局关键帧（0x0C3 格式）：从本地权威的 authGrid 行优先 RLE 生成（供客户端初始化）
func mock_keyframe() -> PackedByteArray:
	var runs := []
	var prev := -1
	var length := 0
	for i in range(grid.auth_grid.size()):
		var v: int = grid.auth_grid[i]
		if v == prev:
			length += 1
		else:
			if prev != -1:
				runs.append({"length": length, "owner": prev})
			prev = v
			length = 1
	if length > 0:
		runs.append({"length": length, "owner": prev})
	return codec.encode_territory_keyframe(0, runs)


func attach_transport(t: FakeTransport) -> void:
	transport = t


func _count_inside() -> int:
	var n := 0
	for i in range(grid.auth_grid.size()):
		if grid.auth_grid[i] != TerritoryGrid.OUTSIDE:
			n += 1
	return n


func _seed_area(pid: int, wx: float, wy: float, radius_units: float) -> void:
	## 出生圆盘：世界坐标 → 格
	var cx := Fixed.fixed_to_grid(Fixed.world_to_fixed(wx))
	var cy := Fixed.fixed_to_grid(Fixed.world_to_fixed(wy))
	var rr := int(radius_units * 2.0)   # 格半径
	for y in range(maxi(0, cy - rr), mini(95, cy + rr)):
		for x in range(maxi(0, cx - rr), mini(95, cx + rr)):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= rr * rr and grid.auth_grid[y * 96 + x] == TerritoryGrid.BROTH:
				grid.auth_grid[y * 96 + x] = pid
				_flip(pid, y * 96 + x)


func _flip(owner: int, idx: int) -> void:
	if _seeding:
		return   # 开局由 Keyframe 初始化，不产生增量
	if not _delta_accum.has(owner):
		_delta_accum[owner] = []
	_delta_accum[owner].append({"tick": tick, "idx": idx})


func set_expand_rate_fixed(v: int) -> void:
	expand_rate_fixed = v


# ══ 客户端消息入口（fake_transport 调用）═══════════════════════════════════

func handle_client_message(msg_id: int, body: PackedByteArray) -> void:
	if msg_id == MsgIds.PLAYER_INPUT:
		var r := ByteReader.new(body)
		## 头部 clientTick u32 · inputSeq u16 · frameCount u8 = 7B
		if body.size() < 7:
			return
		r.read_u32()                       # clientTick
		var seq := r.read_u16()            # inputSeq（最新帧）
		var frame_count := r.read_u8()
		# 最新帧在前（T0001M02F04）
		var frames := []
		for i in range(frame_count):
			frames.append({
				"move_x": r.read_i8(), "move_y": r.read_i8(),
				"aim": r.read_u16(), "buttons": r.read_u8(),
			})
		var last_snap_tick := r.read_u32()
		var last_terr_tick := r.read_u32()
		if frames.size() > 0:
			var f: Dictionary = frames[0]
			var p: Dictionary = players[me_id]
			p.move_x = f.move_x
			p.move_y = f.move_y
			p.aim = f.aim
			p.buttons = f.buttons
			p.input_seq = seq
			p.last_terr_tick = last_terr_tick
		_trim_delta_accum(last_terr_tick)


func _trim_delta_accum(ack_tick: int) -> void:
	## 累积式增量：客户端 ACK 之后裁剪（T0001M03F06）
	for owner in _delta_accum.keys():
		var list: Array = _delta_accum[owner]
		var keep: Array = []
		for rec in list:
			if rec.tick > ack_tick:
				keep.append(rec)
		if keep.is_empty():
			_delta_accum.erase(owner)
		else:
			_delta_accum[owner] = keep


# ══ 权威 tick（20Hz）═══════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if transport == null:
		return
	_tick_acc += delta
	while _tick_acc >= TICK_S:
		_tick_acc -= TICK_S
		tick += 1
		_authority_tick()


func _authority_tick() -> void:
	# 0) Bot 简单 AI：朝锅心缓慢移动（P0 可玩性；本地权威是服务端角色，允许简单规则）
	_bot_ai()
	# 1) 移动（含充能时减速，D0001M05：KNOB_charge_movespeed = 0.45×）
	for pid in players:
		var p: Dictionary = players[pid]
		if p.buttons & MsgIds.BUTTON_CHARGE != 0:
			_apply_movement(pid, 0.45)
		else:
			_apply_movement(pid, 1.0)
	# 2) 扩张（边界对抗，T0001M03F04）
	for pid in players:
		var p: Dictionary = players[pid]
		if p.buttons & MsgIds.BUTTON_CHARGE != 0:
			_expand_authority(pid)
	# 3) 输出
	_emit_snapshot()
	if tick % 5 == 0:               # 10Hz 地盘帧
		_emit_delta()
	if tick % 20 == 0:              # 1Hz 面积
		_emit_score()


func _bot_ai() -> void:
	## Bot：若被玩家逼近或长期静止则朝锅心缓慢移动；充能期不移动
	for pid in players:
		if pid == me_id:
			continue
		var p: Dictionary = players[pid]
		if p.get("move_x", 0) == 0 and p.get("move_y", 0) == 0:
			var to_center := MapData.CENTER - Vector2(p.pos_x / 64.0, p.pos_y / 64.0)
			if to_center.length() > 1.0:
				var dir := to_center.normalized()
				p.move_x = int(dir.x * 50.0)
				p.move_y = int(dir.y * 50.0)


func _apply_movement(pid: int, speed_mult: float) -> void:
	var p: Dictionary = players[pid]
	var area := _area_permyriad(pid)
	var base_speed := Sim.speed_for_area(area)
	var speed := int(base_speed * speed_mult)
	var vel := Fixed.dir_to_velocity(p.get("move_x", 0), p.get("move_y", 0), speed)
	var nx := p.pos_x + vel.x * Fixed.POS_SCALE / Fixed.VEL_SCALE
	var ny := p.pos_y + vel.y * Fixed.POS_SCALE / Fixed.VEL_SCALE
	# 锅壁约束（圆形汤锅）
	var world := Vector2(float(nx) / Fixed.POS_SCALE, float(ny) / Fixed.POS_SCALE)
	if not MapData.inside_pot(world):
		world = MapData.CENTER + (world - MapData.CENTER).limit_length(MapData.POT_RADIUS - 0.3)
		nx = Fixed.world_to_fixed(world.x)
		ny = Fixed.world_to_fixed(world.y)
	p.pos_x = nx
	p.pos_y = ny
	p.vel_x = vel.x
	p.vel_y = vel.y


## 权威扩张（服务端规则，与客户端预测同构但允许抢占）
func _expand_authority(pid: int) -> void:
	var p: Dictionary = players[pid]
	if not grid._expand_r.has(pid):
		grid._expand_r[pid] = 0
		grid._frontier[pid] = []
		grid._in_frontier[pid] = {}
		_build_authority_frontier(pid)
	grid._expand_r[pid] += Fixed.expand_rate_to_r_inc(expand_rate_fixed)
	var r: int = grid._expand_r[pid]
	var heap: Array = grid._frontier[pid]
	var seen: Dictionary = grid._in_frontier[pid]
	while heap.size() > 0:
		var top: Dictionary = heap[0]
		if top.dist > r:
			break
		heap.remove_at(0)
		seen.erase(top.cell)
		var cell: int = top.cell
		var cur: int = grid.auth_grid[cell]
		if cur == TerritoryGrid.BROTH or (cur >= 1 and cur <= 4 and cur != pid):
			# 原汤 → 占领；敌方 → 若对方不在充能则抢占，在充能则僵持（留在 frontier）
			if cur >= 1 and cur <= 4 and cur != pid:
				var enemy: Dictionary = players.get(cur, {})
				if enemy.get("buttons", 0) & MsgIds.BUTTON_CHARGE != 0:
					continue   # 僵持：本 tick 不推进该格，留在堆里每 tick 重试
			grid.auth_grid[cell] = pid
			grid.dirty[cell] = 1
			_flip(pid, cell)
			_push_authority_neighbors(pid, cell, seen)
		# 锅外：跳过


func _build_authority_frontier(pid: int) -> void:
	var seen: Dictionary = grid._in_frontier[pid]
	for y in range(96):
		for x in range(96):
			var idx := y * 96 + x
			if grid.auth_grid[idx] != pid:
				continue
			var boundary := false
			for nb in grid._neighbor_offsets():
				var nx := x + nb.x
				var ny := y + nb.y
				if not grid.in_bounds(nx, ny):
					continue
				if grid.auth_grid[ny * 96 + nx] != pid:
					boundary = true
					break
			if boundary:
				grid._push_into(pid, x, y, 0, seen)


func _push_authority_neighbors(pid: int, cell: int, seen: Dictionary) -> void:
	var x := cell % 96
	var y := cell / 96
	for nb in grid._neighbor_offsets():
		var nx := x + nb.x
		var ny := y + nb.y
		if not grid.in_bounds(nx, ny):
			continue
		var nidx := ny * 96 + nx
		if seen.has(nidx):
			continue
		grid._push_into(pid, nx, ny, Fixed.geodesic_dist(nb.x, nb.y), seen)


func _area_permyriad(pid: int) -> int:
	var n := grid.count_owner(pid)
	return int(round(float(n) / float(maxi(1, _inside_cells)) * 10000.0))


# ══ 下行输出 ═══════════════════════════════════════════════════════════════

func _emit_snapshot() -> void:
	var w := ByteWriter.new(64)
	w.write_u32(tick)
	w.write_u16(_last_input_seq())
	w.write_u8(players.size())
	for pid in range(1, 5):
		var p: Dictionary = players[pid]
		var flags := 0
		if p.buttons & MsgIds.BUTTON_CHARGE != 0:
			flags |= MsgIds.FLAG_CHARGING
		w.write_u8(pid)
		w.write_u16(p.pos_x)
		w.write_u16(p.pos_y)
		w.write_i8(p.vel_x)
		w.write_i8(p.vel_y)
		w.write_u16(p.aim)
		w.write_u16(_area_permyriad(pid))   # mass = 面积万分比（T0001M02F05）
		w.write_u8(flags)
		w.write_u8(p.hp)
	transport.inject(MsgIds.CH_UNRELIABLE_UNORDERED, MsgIds.SNAPSHOT, w.data())


func _last_input_seq() -> int:
	return players[me_id].get("input_seq", 0)


func _emit_delta() -> void:
	## 按 owner 分组、组内 cellIndex 升序差值 varint（T0001M03F06）
	var w := ByteWriter.new(64)
	w.write_u32(tick)
	w.write_u32(_last_delta_tick)
	var owners := _delta_accum.keys()
	owners.sort()
	w.write_u8(owners.size())
	for owner in owners:
		var recs: Array = _delta_accum[owner]
		var cells := PackedInt32Array()
		for rec in recs:
			cells.append(rec.idx)
		cells.sort()
		# 去重（同格多 tick 翻转只发最新归属）
		var uniq := PackedInt32Array()
		for c in cells:
			if uniq.size() == 0 or uniq[uniq.size() - 1] != c:
				uniq.append(c)
		w.write_u8(owner)
		w.write_u16(uniq.size())
		var prev := 0
		for c in uniq:
			w.write_varint(c - prev)
			prev = c
	_last_delta_tick = tick
	transport.inject(MsgIds.CH_UNRELIABLE_UNORDERED, MsgIds.TERRITORY_DELTA, w.data())


func _emit_score() -> void:
	var w := ByteWriter.new(12)
	w.write_u32(tick)
	for pid in range(1, 5):
		w.write_u16(_area_permyriad(pid))
	transport.inject(MsgIds.CH_UNRELIABLE_UNORDERED, MsgIds.SCORE_TICK, w.data())
