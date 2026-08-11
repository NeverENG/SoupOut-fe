## character.gd — 角色表现 3D 版(A0001M08:三档体型 + 动画状态机)
## 玩家扮演的就是**食材本体**:番茄 / 青菜 / 玉米 / 甜菜头(紫芋),Q 版大眼睛。
## 模型:Kenney Food Kit(CC0,assets/props/)。食材没有骨骼 —— 全部程序化动画:
##   位移驱动蹦跳(hop 相位,与 2D 版同公式,插值和动画不脱节 M08)+ 压扁拉伸,
##   充能鼓胀脉动 / 翻窗跳跃 / 挥击前倾 / 死亡翻倒半沉进汤 / 复活弹出。
##
## 结构:Character 是**普通 Node 包装器**,自定义 position(Vector2)/rotation(float)
## 属性,与 battle_root 的既有读写(`ch.position = ...`)完全兼容。
## - 体型:连续缩放跟随 Sim.size_for_area,0.25s 阻尼(A0001M08F02)
## - 玩家归属:脚下汤色描边环 + 名牌配色(食材本体即身份,色环二次确认)
## - 名牌:屏幕空间 Control,每帧 unproject 跟随头顶

class_name Character
extends Node

const TIER_LIGHT := 0
const TIER_MID := 1
const TIER_HEAVY := 2

const TIER_DAMP_S := 0.25          # 档位切换阻尼(A0001M08F02)
const BASE_RADIUS := 0.5           # 轻装直径 1.0u → 半径 0.5u
const BODY_SIZE := 1.05            # 轻装食材最长边(世界单位)

enum Anim { IDLE, HOP, HOP_CHARGE, CHARGE_IDLE, SWING, HURT, DEATH, RESPAWN, VAULT, PALLET_PUSH }

## 食材 → 模型(和地盘汤色一一对应)
const _MODELS := [
	"res://assets/props/tomato.glb",    # P1 番茄
	"res://assets/props/cabbage.glb",   # P2 青菜
	"res://assets/props/corn.glb",      # P3 玉米
	"res://assets/props/beet.glb",      # P4 紫芋(甜菜头)
]

var player_id: int = 0
var ingredient_id: int = 0
var main_color := Color.WHITE
var dark_color := Color.GRAY

# ── 2D 契约属性(battle_root 直接读写) ────────────────────────────────────
var position: Vector2 = Vector2.ZERO:
	set(v):
		position = v
		if _rig != null:
			_rig.position = Vector3(v.x, 0.0, v.y)
var rotation: float = 0.0:
	set(v):
		rotation = v
		if _rig != null:
			_rig.rotation.y = PI / 2.0 - v   # 2D 角(0=+x,y 下) → yaw(脸朝 +Z)
var global_position: Vector2:
	get:
		return position

# 状态
var current_tier: int = TIER_LIGHT
var _tier_scale := 1.0
var _target_tier_scale := 1.0
var anim: int = Anim.IDLE
var charging := false
var dead := false
var vaulting := false
var overweight := false
var winding_up := false
var hp := 100
var area_permyriad := 1000
var atk_cd_ms := 0
var in_reach := false

# 程序化动画驱动
var _last_pos := Vector2.ZERO
var _moved := 0.0
var _hop_phase := 0.0              # 位移驱动(M08:不靠计时器)
var _idle_phase := 0.0
var _charge_phase := 0.0
var _lunge_left := 0.0             # 挥击前倾剩余时长
var _vault_left := 0.0             # 翻窗跳跃剩余时长
var _blink_timer := 2.5
var _blink_left := 0.0
var _dead_visual := false          # 翻倒姿态是否已应用

# 3D 节点
var _rig: Node3D = null
var _body: Node3D = null           # 食材模型(缩放/压扁拉伸作用于此)
var _model: Node3D = null
var _face: Node3D = null           # 大眼睛组(挂在 body 前脸)
var _eye_l: MeshInstance3D = null
var _eye_r: MeshInstance3D = null
var _body_r := 0.5                 # 规格化后模型半径(眼睛定位用)
var _shadow: MeshInstance3D = null
var _owner_ring: MeshInstance3D = null
var _charge_ring: MeshInstance3D = null
var _reach_ring: MeshInstance3D = null
var _swing_sector: MeshInstance3D = null
var _hit_light: OmniLight3D = null
var _ring_progress := 0.0
var _invuln_timer := 0.0

# 名牌(屏幕空间)
var _plate: Control = null
var _nameplate: Label = null
var _tip: Label = null
var _tip_timer := 0.0
var _hp_ghost: ColorRect = null
var _hp_fill: ColorRect = null
var _cd_fill: ColorRect = null
var _plate_name := ""
var _is_me := false
var _is_leader := false
const PLATE_W := 150.0
const PLATE_H := 52.0
const PLATE_BAR_H := 11.0
const PLATE_CD_H := 6.0
const PLATE_CD_MAX_MS := 700.0   # 挥空后摇做分母:条涨得慢 = 他刚挥空

# 插值(远端玩家,M08;battle_root 读写)
var remote_buffer: Array = []
var remote_frozen := false


func setup(p_player_id: int, p_ingredient: int, p_color: Color, p_dark: Color,
		p_name: String = "", p_is_me: bool = false) -> void:
	player_id = p_player_id
	ingredient_id = p_ingredient
	main_color = p_color
	dark_color = p_dark

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	# 食材本体(body 承接压扁拉伸,model 内部只做规格化)
	_body = Node3D.new()
	_rig.add_child(_body)
	_model = Fx3D.instance(_MODELS[clampi(ingredient_id, 0, _MODELS.size() - 1)])
	var bb := Fx3D.fit_length(_model, BODY_SIZE)
	_body_r = maxf(bb.size.x, bb.size.z) * 0.5
	# 模型底部贴地
	_model.position.y = -bb.position.y
	_body.add_child(_model)

	# Q 版大眼睛(白球 + 黑瞳),贴在食材前脸(+Z)
	_face = Node3D.new()
	_face.position = Vector3(0.0, bb.size.y * 0.62, _body_r * 0.72)
	_body.add_child(_face)
	_eye_l = _make_eye(Vector3(-0.13, 0.0, 0.0))
	_eye_r = _make_eye(Vector3(0.13, 0.0, 0.0))

	# 脚下:柔影 + 汤色归属环 + 射程圈 + 充能环 + 攻击扇形
	_shadow = Fx3D.ground_blob(0.52, 0.34)
	_rig.add_child(_shadow)
	_owner_ring = Fx3D.ring(0.62, Color(main_color, 0.85), 0.10)
	Fx3D.ring_set(_owner_ring, 1.0)
	_rig.add_child(_owner_ring)
	_reach_ring = Fx3D.ring(0.85, Color(1.0, 0.88, 0.5, 0.0), 0.12)
	Fx3D.ring_set(_reach_ring, 1.0)
	_rig.add_child(_reach_ring)
	_charge_ring = Fx3D.ring(1.05, Color(main_color, 0.9), 0.16)
	_charge_ring.visible = false
	_rig.add_child(_charge_ring)
	_swing_sector = Fx3D.sector(2.4, 50.0, Color(1.0, 0.9, 0.65, 0.28))
	_swing_sector.visible = false
	_rig.add_child(_swing_sector)

	# 受击闪光灯
	_hit_light = OmniLight3D.new()
	_hit_light.light_color = Color(1, 0.9, 0.8)
	_hit_light.omni_range = 3.0
	_hit_light.light_energy = 0.0
	_hit_light.position = Vector3(0, 1.0, 0)
	_rig.add_child(_hit_light)

	_build_nameplate(p_name, p_is_me)


func _make_eye(offset: Vector3) -> MeshInstance3D:
	var eye := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.085
	sm.height = 0.17
	eye.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.97, 0.96, 0.92)
	m.roughness = 0.4
	eye.material_override = m
	eye.position = offset
	eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_face.add_child(eye)
	var pupil := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.042
	pm.height = 0.084
	pupil.mesh = pm
	pupil.material_override = Fx3D.mat(Color(0.16, 0.11, 0.08), 0.0, 0.5)
	pupil.position = Vector3(0, 0.008, 0.062)
	pupil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eye.add_child(pupil)
	return eye


# ── 名牌(屏幕空间,每帧 unproject 跟随) ─────────────────────────────────
func _build_nameplate(p_name: String, p_is_me: bool) -> void:
	if p_name.is_empty():
		return
	_plate_name = p_name
	_is_me = p_is_me
	_plate = Control.new()
	_plate.size = Vector2(PLATE_W, PLATE_H + PLATE_CD_H + 3.0)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.z_index = 20
	add_child(_plate)

	_nameplate = Label.new()
	_nameplate.size = Vector2(PLATE_W, 30)
	_nameplate.add_theme_font_size_override("font_size", 22)
	_nameplate.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.04))
	_nameplate.add_theme_constant_override("outline_size", 6)
	_nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate.add_child(_nameplate)

	# 血条:底 → 白色残影(看得清掉了多少)→ 实血(自己绿/别人红)
	var bar_y := 32.0
	_bar(Vector2(0, bar_y), PLATE_W, PLATE_BAR_H, Color(0.10, 0.07, 0.05, 0.85))
	_hp_ghost = _bar(Vector2(0, bar_y), PLATE_W, PLATE_BAR_H, Color(1, 1, 1, 0.55))
	_hp_fill = _bar(Vector2(0, bar_y), PLATE_W, PLATE_BAR_H,
		Color(0.36, 0.82, 0.42) if p_is_me else Color(0.88, 0.30, 0.30))
	# 冷却条:满 = 能出手(涨得快 = 刚打中 250ms,涨得慢 = 刚挥空 700ms)
	var cd_y := bar_y + PLATE_BAR_H + 3.0
	_bar(Vector2(0, cd_y), PLATE_W, PLATE_CD_H, Color(0.10, 0.07, 0.05, 0.7))
	_cd_fill = _bar(Vector2(0, cd_y), PLATE_W, PLATE_CD_H, Color(0.98, 0.82, 0.35))

	# 提示气泡(名牌上方)
	_tip = Label.new()
	_tip.size = Vector2(PLATE_W + 120, 28)
	_tip.position = Vector2(-60, -30)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.add_theme_font_size_override("font_size", 22)
	_tip.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_tip.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.05))
	_tip.add_theme_constant_override("outline_size", 5)
	_tip.visible = false
	_plate.add_child(_tip)
	_update_nameplate()


func _bar(pos: Vector2, w: float, h: float, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = Vector2(w, h)
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(r)
	return r


## 「够得着了」:进入本地玩家攻击距离 → 脚下亮一圈暖黄
func set_in_reach(on: bool) -> void:
	if in_reach == on:
		return
	in_reach = on
	if _reach_ring != null:
		Fx3D.ring_set(_reach_ring, 1.0,
			Color(1.0, 0.88, 0.5, 0.55 if on else 0.0))


## 领先标记:第一名戴皇冠 + 名字染金(battle_root 按面积排名下发)
func set_leader(is_leader: bool) -> void:
	_is_leader = is_leader


func _update_nameplate(delta: float = 0.0) -> void:
	if _plate == null or _rig == null or not _rig.is_inside_tree():
		return
	var cam := _rig.get_viewport().get_camera_3d()
	if cam == null:
		_plate.visible = false
		return
	var head := _rig.global_position + Vector3(0, BODY_SIZE * _tier_scale + 0.5, 0)
	var screen := cam.unproject_position(head)
	_plate.position = screen + Vector2(-PLATE_W * 0.5, -PLATE_H - PLATE_CD_H)
	_plate.visible = not dead

	var pct := int(round(area_permyriad / 100.0))
	_nameplate.text = ("👑 %s  %d%%" % [_plate_name, pct]) if _is_leader \
		else ("%s  %d%%" % [_plate_name, pct])
	var col: Color
	if _is_leader:
		col = Color(1.0, 0.84, 0.30)
	elif _is_me:
		col = Color(1, 1, 1)
	else:
		col = Color(0.86, 0.83, 0.79, 0.8)
	_nameplate.add_theme_color_override("font_color", col)

	var ratio := clampf(float(hp) / 100.0, 0.0, 1.0)
	_hp_fill.size.x = PLATE_W * ratio
	if _cd_fill != null:
		var ready := 1.0 - clampf(float(atk_cd_ms) / PLATE_CD_MAX_MS, 0.0, 1.0)
		_cd_fill.size.x = PLATE_W * ready
		_cd_fill.color = Color(0.45, 0.92, 0.52) if ready >= 0.999 else Color(0.98, 0.82, 0.35)
	# 残影只往下追,掉血瞬间留白条,0.6s 内收拢
	var ghost_w: float = _hp_ghost.size.x
	if ghost_w < _hp_fill.size.x:
		ghost_w = _hp_fill.size.x
	elif delta > 0.0:
		ghost_w = maxf(_hp_fill.size.x, ghost_w - PLATE_W * delta / 0.6)
	_hp_ghost.size.x = ghost_w


# ══ 状态输入(battle_root 驱动)═══════════════════════════════════════════

func set_visual_state(p_pos: Vector2, p_aim: float, p_flags: int, p_hp: int, p_area: int,
		p_cd_ms: int = 0) -> void:
	position = p_pos
	rotation = p_aim
	hp = p_hp
	area_permyriad = p_area
	var was_dead := dead
	var was_vaulting := vaulting
	charging = p_flags & MsgIds.FLAG_CHARGING != 0
	vaulting = p_flags & MsgIds.FLAG_VAULTING != 0
	dead = p_flags & MsgIds.FLAG_DEAD != 0
	overweight = p_flags & MsgIds.FLAG_OVERWEIGHT != 0
	winding_up = p_flags & MsgIds.FLAG_WINDUP != 0
	atk_cd_ms = p_cd_ms
	if _swing_sector != null:
		_swing_sector.visible = winding_up and not dead
	if not was_vaulting and vaulting:
		_vault_left = 0.5
	if was_dead and not dead:
		_respawn_pop()
	# 体型连续跟随面积(A0001M08F02)
	current_tier = Sim.mass_tier(area_permyriad, 3500)
	_target_tier_scale = Sim.size_for_area(area_permyriad)
	_update_anim()


func set_charge_ring(active: bool, progress: float) -> void:
	charging = active
	_ring_progress = progress
	if _charge_ring != null:
		_charge_ring.visible = active
		Fx3D.ring_set(_charge_ring, progress)


func play_swing() -> void:
	anim = Anim.SWING
	_lunge_left = 0.3


func show_tip(text: String, duration: float = 0.8) -> void:
	if _tip == null:
		return
	_tip.text = text
	_tip.visible = true
	_tip_timer = duration


func flash_white() -> void:
	if _hit_light != null:
		_hit_light.light_energy = 3.5
	# 受击瞬间压扁一下
	if _body != null and not dead:
		_body.scale = Vector3(1.18, 0.78, 1.18)


func set_invuln(time_left: float) -> void:
	_invuln_timer = time_left


# ══ 程序化动画 ═════════════════════════════════════════════════════════════

func _update_anim() -> void:
	if dead:
		anim = Anim.DEATH
	elif vaulting:
		anim = Anim.VAULT
	elif charging:
		anim = Anim.HOP_CHARGE if _moved > 0.01 else Anim.CHARGE_IDLE
	elif _moved > 0.01:
		anim = Anim.HOP
	else:
		anim = Anim.IDLE


func _respawn_pop() -> void:
	# 复活:从 0 弹出 + 姿态复位
	_dead_visual = false
	if _body == null:
		return
	_body.rotation = Vector3.ZERO
	_body.position.y = 0.0
	_body.scale = Vector3.ONE * 0.01
	var tw := _body.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_body, "scale", Vector3.ONE, 0.35)


func _apply_death_pose() -> void:
	# 翻倒 + 半沉进汤(食材炖进去了)
	_dead_visual = true
	if _body == null:
		return
	var tw := _body.create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_property(_body, "rotation:z", PI * 0.52, 0.5)
	tw.tween_property(_body, "position:y", -BODY_SIZE * 0.3, 0.7)


func _process(delta: float) -> void:
	# 位移驱动(M08:不靠计时器)
	var dist := position.distance_to(_last_pos)
	_moved = lerpf(_moved, dist, 0.3)
	_last_pos = position
	_hop_phase += _moved * 3.2
	_idle_phase += delta * 2.0
	_charge_phase += delta * 5.0

	# 体型阻尼(0.25s)
	_tier_scale = lerpf(_tier_scale, _target_tier_scale, clampf(delta / TIER_DAMP_S, 0.0, 1.0))

	if _lunge_left > 0.0:
		_lunge_left -= delta
	if _vault_left > 0.0:
		_vault_left -= delta
	if _lunge_left <= 0.0:
		_update_anim()

	# ── 姿态合成:缩放(体型 × 压扁拉伸) + 弹跳高度 + 前倾 ────────────────
	if _body != null:
		if dead:
			if not _dead_visual:
				_apply_death_pose()
		else:
			if _dead_visual:
				_dead_visual = false
				_body.rotation = Vector3.ZERO
			var s := _tier_scale
			var bob := 0.0          # 离地高度(0..1)
			var squash := 0.0       # >0 拉伸 / <0 压扁
			var tilt := 0.0         # 前倾(移动方向)
			match anim:
				Anim.HOP:
					bob = absf(sin(_hop_phase)) * 0.30
					squash = sin(_hop_phase * 2.0) * 0.12
					tilt = clampf(_moved * 4.0, 0.0, 0.22)
				Anim.HOP_CHARGE:
					bob = absf(sin(_hop_phase * 0.7)) * 0.16   # 更矮更慢(A0001M08F03)
					squash = sin(_charge_phase) * 0.05
					tilt = 0.1
				Anim.CHARGE_IDLE:
					squash = sin(_charge_phase) * 0.07 + 0.05  # 鼓胀脉动与充能环同频
				Anim.VAULT:
					bob = sin(clampf(1.0 - _vault_left / 0.5, 0.0, 1.0) * PI) * 0.9
					squash = 0.18
				_:
					squash = sin(_idle_phase) * 0.035          # 呼吸
			if _lunge_left > 0.0:
				# 挥击:朝脸向猛一探
				var t := _lunge_left / 0.3
				tilt = sin(t * PI) * 0.5
				squash = sin(t * PI) * 0.15
			var sy := 1.0 + squash
			var sxz := 1.0 - squash * 0.55
			# 受击压扁的恢复(flash_white 里直接改了 scale,这里弹回)
			_body.scale = _body.scale.lerp(Vector3(sxz * s, sy * s, sxz * s),
				clampf(delta * 14.0, 0.0, 1.0))
			_body.position.y = bob * 0.5 * s
			_body.rotation.x = lerpf(_body.rotation.x, tilt, clampf(delta * 10.0, 0.0, 1.0))

	# 眨眼
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.2, 4.5)
		_blink_left = 0.1
	if _blink_left > 0.0:
		_blink_left -= delta
	var eye_sy := 0.12 if _blink_left > 0.0 else 1.0
	if _eye_l != null:
		_eye_l.scale.y = eye_sy
		_eye_r.scale.y = eye_sy

	# 受击白闪(灯)衰减
	if _hit_light != null and _hit_light.light_energy > 0.0:
		_hit_light.light_energy = maxf(0.0, _hit_light.light_energy - delta * 40.0)

	# 无敌闪烁:4Hz,最后 1 秒 8Hz
	if _invuln_timer > 0.0:
		_invuln_timer -= delta
		var hz := 8.0 if _invuln_timer < 1.0 else 4.0
		if _body != null:
			_body.visible = fmod(_invuln_timer, 1.0 / hz) > 0.5 / hz
	elif _body != null and not _body.visible and not dead:
		_body.visible = true

	# 死亡:影子淡出、归属环隐藏
	if _shadow != null:
		var sm := _shadow.material_override as StandardMaterial3D
		if sm != null:
			sm.albedo_color.a = 0.06 if dead else 0.34
	if _owner_ring != null:
		_owner_ring.visible = not dead

	# 提示气泡计时
	if _tip != null and _tip.visible:
		_tip_timer -= delta
		if _tip_timer <= 0.0:
			_tip.visible = false

	_update_nameplate(delta)
