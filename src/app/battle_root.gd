## battle_root.gd — 对局容器（T0005M05/M06/M07 的编排者）
## - 输入循环固定 20Hz 与渲染解耦：采样摇杆 → 组 0x080（3 帧冗余 + 双 baseline）→ 本地预测
## - 本地玩家：Prediction 回滚重放；远端玩家：2 tick 缓冲插值 + 3 tick 外推（M08）
## - 地盘：TerritoryGrid（core）← TerritoryRenderer（表现）；ACK 纪律见 T0005M07F02
## - 收包分发：Snapshot/Delta/ScoreTick/事件（事件只驱动表现，不改状态）

extends Node2D

const INPUT_INTERVAL_S := 0.05     # 20 Hz
const REDUNDANT_FRAMES := 3        # T0001M02F04

var app: Node = null
var transport: ISoupTransport = null
var local_authority: Node = null

# 核心层（纯逻辑）
var grid := TerritoryGrid.new()
var match_state := MatchState.new()
var prediction := Prediction.new()
var soup_clock := SoupClock.new()

# 表现层
var renderer: TerritoryRenderer = null
var camera: BattleCamera = null
var hud: Control = null
var stir: Stir = null
var tweak: Control = null
var characters := {}               # player_id → Character
var walls: Array = []
var pallets: Array = []
var vaults: Array = []

# 输入
var _input_acc := 0.0
var _input_seq := 0
var _input_history: Array = []     # 最近 3 帧（最新在前）
var _stick_move := Vector2.ZERO    # -1..1
var _stick_aim := Vector2.ZERO
var _charging := false
var _attack_pending := false

var _match_data: Dictionary = {}
var map_data: Dictionary = {}
var me_id: int = 0
var _solo_mode := false
var _speed_fixed := 6 * Fixed.VEL_SCALE   # 开局移速 6.0（D0001M02）
var _prev_charging := false               # 扩张音效状态机（本地立即，A0001M02F04）

# 远端插值（M08）
var _remote_snapshots := {}        # player_id → [{pos, aim}]


func begin_match(p_app: Node, match_start: Dictionary, keyframe: PackedByteArray,
		p_transport: ISoupTransport) -> void:
	app = p_app
	transport = p_transport
	_match_data = match_start
	me_id = app.my_player_id
	_solo_mode = transport is FakeTransport and app.local_authority != null
	if _solo_mode:
		local_authority = app.local_authority
		me_id = local_authority.mock_me_id()
	map_data = MapData.build_map(match_start.get("map_id", 1))
	grid = TerritoryGrid.new(map_data.get("grid_w", 96), map_data.get("grid_h", 96))
	grid.set_me(me_id)
	match_state.set_me(me_id)
	_build_world()
	_build_hud()
	# 初始地盘（单机：由本地权威生成 keyframe；联网：等待 0x0C3）
	if keyframe.size() > 0:
		var kf := codec.decode_territory_keyframe(keyframe)
		if kf.size() > 0:
			grid.apply_keyframe(kf.server_tick, kf.runs)
	# 出生点
	for p in match_start.get("players", []):
		_spawn_character(p)
	if _solo_mode:
		# 本地权威：角色位置以 Snapshot 为准（后续 _apply_snapshot 持续覆盖）
		for p in _match_data.get("players", []):
			var ch: Character = characters.get(p.player_id)
			if ch != null:
				ch.position = Vector2(p.spawn_x / 64.0, p.spawn_y / 64.0)




func _build_world() -> void:
	# 汤底占位（层序 1）
	var bg := Polygon2D.new()
	var pts := PackedVector2Array()
	var r := MapData.POT_RADIUS
	for i in range(48):
		var a := TAU * i / 48.0
		pts.append(MapData.CENTER + Vector2(cos(a), sin(a)) * r)
	bg.polygon = pts
	bg.color = Color(0.72, 0.55, 0.36, 0.55)
	bg.z_index = 1
	add_child(bg)

	# 地盘场（层序 2）
	renderer = TerritoryRenderer.new()
	renderer.name = "TerritoryRenderer"
	renderer.setup(grid)
	add_child(renderer)

	# 地形（层序 4）：墙 / 板 / 窗
	for w in map_data.walls:
		var wall := TerrainWall.new()
		wall.setup(w)
		add_child(wall)
		walls.append(wall)
	for p in map_data.pallets:
		var pallet := Pallet.new()
		pallet.setup(p.id, p.kind, Vector2(p.x, p.y))
		add_child(pallet)
		pallets.append(pallet)
	for v in map_data.vaults:
		var vault := Vault.new()
		vault.setup(v.id, v.kind, Vector2(v.x, v.y))
		add_child(vault)
		vaults.append(vault)

	# 搅拌（层序 3）
	stir = Stir.new()
	stir.setup()
	add_child(stir)

	# 摄像机
	camera = BattleCamera.new()
	camera.name = "BattleCamera"
	add_child(camera)


func _build_hud() -> void:
	hud = preload("res://src/ui/hud/hud.gd").new()
	hud.name = "Hud"
	var layer := CanvasLayer.new()
	layer.layer = 7
	layer.add_child(hud)
	add_child(layer)
	hud.call("setup", self, grid, match_state, me_id)


func _spawn_character(p: Dictionary) -> void:
	var ch := Character.new()
	var color := _player_color(p.player_id)
	var dark := _player_dark(p.player_id)
	ch.setup(p.player_id, p.ingredient_id, color, dark)
	ch.position = Vector2(p.spawn_x / 64.0, p.spawn_y / 64.0)
	add_child(ch)
	characters[p.player_id] = ch
	if p.player_id == me_id:
		camera.setup(ch)


func _player_color(player_id: int) -> Color:
	match player_id:
		1: return Color(0.949, 0.565, 0.608)
		2: return Color(0.180, 0.604, 0.525)
		3: return Color(1.0, 0.824, 0.118)
		4: return Color(0.545, 0.361, 0.839)
	return Color.WHITE


func _player_dark(player_id: int) -> Color:
	match player_id:
		1: return Color(0.753, 0.337, 0.416)
		2: return Color(0.090, 0.369, 0.322)
		3: return Color(0.780, 0.588, 0.000)
		4: return Color(0.337, 0.200, 0.580)
	return Color.GRAY


func _my_character() -> Character:
	return characters.get(me_id, null)


# ══ 每帧驱动 ══════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	soup_clock.advance(delta * 1000.0)
	prediction.advance_error(delta)
	stir.tick(delta)
	# 输入循环（20Hz，与渲染解耦）
	_input_acc += delta
	while _input_acc >= INPUT_INTERVAL_S:
		_input_acc -= INPUT_INTERVAL_S
		_run_input_tick()
	# 远端插值渲染
	_interpolate_remotes(delta)
	# 本地玩家渲染位置（solo：以权威 Snapshot 为准；联网：预测 + visualError）
	var me_ch := _my_character()
	if me_ch != null and not match_state.is_dead(me_id):
		if _solo_mode:
			var ms := match_state.my_state()
			if ms.size() > 0:
				me_ch.position = Vector2(float(ms.pos_x) / 64.0, float(ms.pos_y) / 64.0)
		else:
			me_ch.position = prediction.get_render_pos()
	# 摄像机档位
	if me_ch != null:
		camera.update_tier(match_state.my_area_permyriad())


func _run_input_tick() -> void:
	if match_state.is_dead(me_id):
		return   # 死亡停输入（M06F03）
	# 采样 → 帧
	var move_x := int(round(_stick_move.x * 100.0))
	var move_y := int(round(_stick_move.y * 100.0))
	var aim := Fixed.angle_to_uint16(_aim_angle())
	var buttons := 0
	if _charging:
		buttons |= MsgIds.BUTTON_CHARGE
	if _attack_pending:
		buttons |= MsgIds.BUTTON_ATTACK
	_attack_pending = false
	var frame := {"move_x": move_x, "move_y": move_y, "aim": aim, "buttons": buttons}
	_input_history.push_front(frame)
	if _input_history.size() > REDUNDANT_FRAMES:
		_input_history.pop_back()
	_input_seq += 1
	# 本地预测（M05F03 第 5 步：本地立即跑一步）
	if not _solo_mode:
		prediction.record_input(_input_seq, move_x, move_y, aim, buttons, _speed_fixed)
		if buttons & MsgIds.BUTTON_CHARGE:
			var input_tick := soup_clock.input_tick_for(transport.get_srtt_ms(), transport.get_rttvar_ms())
			grid.expand_tick(me_id, input_tick)
	# 组包发送（3 帧冗余 + 双 baseline，T0001M02F04）
	var body := codec.encode_player_input(
		soup_clock.est_server_tick,
		_input_seq,
		_input_history,
		match_state.last_snapshot_tick,
		grid.last_auth_tick)     # ← 只反映 authGrid（T0005M07F03）
	if _solo_mode:
		local_authority.handle_client_message(MsgIds.PLAYER_INPUT, body)
	elif transport != null:
		transport.send_msg(MsgIds.PLAYER_INPUT, body)
	# 扩张音效（本地立即：自己向原汤的扩张是预测的，A0001M02F04）
	var charging_now := buttons & MsgIds.BUTTON_CHARGE != 0
	if charging_now and not _prev_charging:
		App.instance.sfx.play_expand_start()
	if charging_now:
		App.instance.sfx.update_expand_progress(get_charge_progress())
	if _prev_charging and not charging_now:
		App.instance.sfx.play_expand_end()
	_prev_charging = charging_now


## 是否可充能：查自己所在格的渲染归属（A0001M12F02：客户端本地判，不走服务端往返）
func can_charge() -> bool:
	var ch := _my_character()
	if ch == null or match_state.is_dead(me_id):
		return false
	var fx := Fixed.world_to_fixed(ch.position.x)
	var fy := Fixed.world_to_fixed(ch.position.y)
	return grid.owner_at_fixed(fx, fy) == me_id


## 扩张拒绝反馈（A0001M12F02：头顶提示 + 红环 + 短震动，1.5s 频率限制在摇杆侧）
func reject_charge() -> void:
	var ch := _my_character()
	if ch != null:
		ch.show_tip("要站在自己的汤里")
	App.instance.sfx.play_charge_blocked()


## 充能进度（本地预测驱动：爽点不能等 RTT，T0005M09F01）
func get_charge_progress() -> float:
	var n := 0
	for i in range(grid.pred_owner.size()):
		if grid.pred_owner[i] == me_id:
			n += 1
	return clampf(float(n) / 400.0, 0.0, 1.0)


func _aim_angle() -> float:
	if _stick_aim.length_squared() > 0.01:
		return _stick_aim.angle()
	return _my_character().rotation if _my_character() != null else 0.0


# ══ 收包分发（app 转发）═══════════════════════════════════════════════════

func on_server_message(msg_id: int, body: PackedByteArray) -> void:
	match msg_id:
		MsgIds.SNAPSHOT:
			var snap := codec.decode_snapshot(body)
			if snap.size() > 0:
				_apply_snapshot(snap)
		MsgIds.TERRITORY_DELTA:
			var d := codec.decode_territory_delta(body)
			if d.size() > 0:
				grid.apply_delta(d.server_tick, d.groups)
		MsgIds.TERRITORY_KEYFRAME:
			## serverTick 防回退（Ch2 乱序旧帧保护，_ordered_deliver 第③层）
			var kf := codec.decode_territory_keyframe(body)
			if kf.size() > 0 and kf.server_tick >= grid.last_auth_tick:
				grid.apply_keyframe(kf.server_tick, kf.runs)
		MsgIds.FULL_STATE:
			## 重连/纠偏：serverTick 防回退 + 时钟硬对齐（M09F04）
			var fs := codec.decode_full_state(body)
			if fs.size() > 0 and fs.server_tick >= match_state.last_snapshot_tick:
				match_state.apply_full_state(fs)
				soup_clock.hard_set(fs.server_tick)
		MsgIds.SCORE_TICK:
			var st := codec.decode_score_tick(body)
			if st.size() > 0:
				if hud != null and hud.has_method("on_score_tick"):
					hud.call("on_score_tick", st)
		MsgIds.PLAYER_DIED, MsgIds.PLAYER_RESPAWN, MsgIds.PALLET_DOWN,
		MsgIds.DROP_SPAWN, MsgIds.DROP_TAKEN, MsgIds.VAULT_START,
		MsgIds.VAULT_END, MsgIds.STIR_WARN, MsgIds.STIR_SWEEP:
			_handle_event(msg_id, body)


func _apply_snapshot(snap: Dictionary) -> void:
	match_state.apply_snapshot(snap)
	soup_clock.on_snapshot(snap.server_tick, Time.get_ticks_msec())
	# 自己的位置 → 预测和解（M06F02）
	var me_snap: Dictionary = {}
	for p in snap.players:
		if p.player_id == me_id:
			me_snap = p
			break
	if me_snap.size() > 0:
		if not _solo_mode:
			prediction.reconcile(snap.ack_input_seq, me_snap.pos_x, me_snap.pos_y, _speed_fixed)
	# 所有玩家视觉状态 + 远端插值缓冲
	for p in snap.players:
		var ch: Character = characters.get(p.player_id)
		if ch == null:
			continue
		if p.player_id == me_id:
			if _solo_mode:
				ch.set_visual_state(Vector2(p.pos_x / 64.0, p.pos_y / 64.0),
					Fixed.uint16_to_angle(p.aim), p.state_flags, p.hp, p.mass)
			else:
				ch.set_visual_state(prediction.get_render_pos(), Fixed.uint16_to_angle(p.aim),
					p.state_flags, p.hp, p.mass)
		else:
			_remote_snapshots[p.player_id] = {
				"pos": Vector2(p.pos_x / 64.0, p.pos_y / 64.0),
				"aim": Fixed.uint16_to_angle(p.aim),
				"vel": Vector2(p.vel_x, p.vel_y),
				"flags": p.state_flags, "hp": p.hp, "mass": p.mass,
			}
			ch.set_visual_state(ch.position, _remote_snapshots[p.player_id].aim,
				p.state_flags, p.hp, p.mass)


func _interpolate_remotes(delta: float) -> void:
	# 简化插值：直接朝目标位置 lerp（M08 的 2 tick 缓冲/3 tick 外推留接口，见注释）
	for pid in _remote_snapshots:
		var ch: Character = characters.get(pid)
		if ch == null:
			continue
		var rs: Dictionary = _remote_snapshots[pid]
		var target: Vector2 = rs.pos
		var k := 1.0 - exp(-12.0 * delta)   # 平滑跟随
		ch.position = ch.position.lerp(target, k)
		# 外推（缓冲空时）：vel 外推上限 3 tick = 150ms（M08）
		if ch.position.distance_to(target) < 0.02:
			ch.position += Vector2(float(rs.vel.x), float(rs.vel.y)) * (0.05 * 0.6)


func _handle_event(msg_id: int, body: PackedByteArray) -> void:
	## 铁律：事件不改状态，只驱动表现（T0005M04F03）
	var ev := codec.decode(msg_id, body)
	match msg_id:
		MsgIds.PLAYER_DIED:
			var ch: Character = characters.get(ev.get("victim", -1))
			if ch != null:
				ch.set_visual_state(ch.position, ch.rotation, MsgIds.FLAG_DEAD, 0, ch.area_permyriad)
				ch.flash_white()
		MsgIds.PLAYER_RESPAWN:
			var ch: Character = characters.get(ev.get("player_id", -1))
			if ch != null:
				ch.set_invuln(1.5)
		MsgIds.STIR_WARN:
			stir.announce_warn(ev.get("fire_tick", 0), ev.get("entry_angle", 0), ev.get("arc_span", 0))
		MsgIds.STIR_SWEEP:
			pass   # 推人/刮除由服务端权威，客户端只播表现（占位：不处理）


# ══ 输入接口（HUD 摇杆调用）════════════════════════════════════════════════

func set_move_stick(v: Vector2) -> void:
	_stick_move = v.limit_length(1.0)
	if _stick_move.length() < 0.05:
		_stick_move = Vector2.ZERO


func set_aim_stick(v: Vector2) -> void:
	_stick_aim = v.limit_length(1.0)


func set_charging(c: bool) -> void:
	_charging = c
	var ch := _my_character()
	if ch != null:
		ch.set_charge_ring(c, 1.0)


func queue_attack() -> void:
	_attack_pending = true
	var ch := _my_character()
	if ch != null:
		ch.play_swing()


func on_unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_tweak_panel()


func _toggle_tweak_panel() -> void:
	if tweak == null:
		tweak = preload("res://src/app/tweak_panel.gd").new()
		tweak.name = "TweakPanel"
		var layer := CanvasLayer.new()
		layer.layer = 20
		layer.add_child(tweak)
		add_child(layer)
		tweak.call("setup", self)
	else:
		tweak.visible = not tweak.visible


# ══ 调参面板接口 ══════════════════════════════════════════════════════════

func set_expand_rate_fixed(v: int) -> void:
	grid.set_expand_rate(v)
	if local_authority != null and local_authority.has_method("set_expand_rate_fixed"):
		local_authority.call("set_expand_rate_fixed", v)


func set_speed_mult(mult: float) -> void:
	_speed_fixed = int(6 * Fixed.VEL_SCALE * mult)
