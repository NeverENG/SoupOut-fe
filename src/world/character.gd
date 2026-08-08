## character.gd — 角色表现（A0001M08：三档体型 + 动画状态机 + 占位美术接口）
## 无正式美术 → 程序化占位（Polygon2D 圆 + 大眼睛），assets/temp/chr 有素材后自动替换。
## - 体型三档：轻 1.0u / 中 1.35u / 重 1.80u 硬夹（A0001M08F02），档位切换 0.25s 阻尼
## - 动画：hop 由位移量驱动相位（M08：插值和动画不脱节）
## - 充能环：脚下汤色环 + 径向填充（A0001M12F01 ① 主载体）
## - 头顶提示气泡（A0001M12F02：要站在自己的汤里）

class_name Character
extends Node2D

const TIER_LIGHT := 0
const TIER_MID := 1
const TIER_HEAVY := 2

const TIER_DAMP_S := 0.25          # 档位切换阻尼（A0001M08F02）
const BASE_RADIUS := 0.5           # 轻装直径 1.0u → 半径 0.5u

enum Anim { IDLE, HOP, HOP_CHARGE, CHARGE_IDLE, SWING, HURT, DEATH, RESPAWN, VAULT, PALLET_PUSH }

var player_id: int = 0
var ingredient_id: int = 0
var main_color := Color.WHITE
var dark_color := Color.GRAY

# 状态
var current_tier: int = TIER_LIGHT
var _tier_scale := 1.0             # 当前平滑缩放
var _target_tier_scale := 1.0
var anim: int = Anim.IDLE
var charging := false
var dead := false
var vaulting := false
var overweight := false
var hp := 100
var area_permyriad := 1000

# 动画驱动
var _hop_phase := 0.0              # 由位移量驱动
var _last_pos := Vector2.ZERO
var _moved := 0.0
var _idle_phase := 0.0
var _charge_phase := 0.0

# 节点
var _body: Polygon2D = null
var _eye_l: Polygon2D = null
var _eye_r: Polygon2D = null
var _pupil_l: Polygon2D = null
var _pupil_r: Polygon2D = null
var _ring: Node2D = null           # 充能环
var _ring_progress: float = 0.0
var _tip: Label = null
var _tip_timer := 0.0
var _flash_timer := 0.0            # 受击白闪
var _invuln_timer := 0.0

# 插值（远端玩家，M08）
var remote_buffer: Array = []      # [{pos, aim, t}]
var remote_frozen := false


func setup(p_player_id: int, p_ingredient: int, p_color: Color, p_dark: Color) -> void:
	player_id = p_player_id
	ingredient_id = p_ingredient
	main_color = p_color
	dark_color = p_dark
	_build_placeholder()
	z_index = 5


## 占位美术：圆身体 + 大眼睛（正式素材替换点：assets/temp/chr/chr_{name}_{anim}_{frame}.png）
func _build_placeholder() -> void:
	_body = _make_circle(BASE_RADIUS, main_color)
	_body.outline_size = 3
	_body.outline_color = dark_color
	add_child(_body)
	# 大眼睛（design-system：Q 版大眼睛）
	_eye_l = _make_circle(0.16, Color.WHITE)
	_eye_r = _make_circle(0.16, Color.WHITE)
	_pupil_l = _make_circle(0.08, Color(0.13, 0.13, 0.13))
	_pupil_r = _make_circle(0.08, Color(0.13, 0.13, 0.13))
	for n in [_eye_l, _eye_r, _pupil_l, _pupil_r]:
		add_child(n)
	_eye_l.position = Vector2(-0.14, -0.06)
	_eye_r.position = Vector2(0.14, -0.06)
	_pupil_l.position = Vector2(-0.12, -0.02)
	_pupil_r.position = Vector2(0.16, -0.02)


func _make_circle(radius: float, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	poly.color = color
	return poly


# ══ 状态输入（battle_root 驱动）═══════════════════════════════════════════

func set_visual_state(p_pos: Vector2, p_aim: float, p_flags: int, p_hp: int, p_area: int) -> void:
	position = p_pos
	rotation = p_aim
	hp = p_hp
	area_permyriad = p_area
	charging = p_flags & MsgIds.FLAG_CHARGING != 0
	vaulting = p_flags & MsgIds.FLAG_VAULTING != 0
	dead = p_flags & MsgIds.FLAG_DEAD != 0
	overweight = p_flags & MsgIds.FLAG_OVERWEIGHT != 0
	# 体型档（A0001M08F02）
	var tier := Sim.mass_tier(area_permyriad, 3500)
	if tier != current_tier:
		current_tier = tier
		_target_tier_scale = Sim.tier_diameter(tier)
	_update_anim()


func set_charge_ring(active: bool, progress: float) -> void:
	charging = active
	_ring_progress = progress
	if _ring != null:
		_ring.visible = active


func play_swing() -> void:
	anim = Anim.SWING
	_update_anim()


func show_tip(text: String, duration: float = 0.8) -> void:
	if _tip == null:
		_tip = Label.new()
		_tip.add_theme_font_size_override("font_size", 22)
		_tip.add_theme_color_override("font_color", Color.WHITE)
		_tip.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.05))
		_tip.add_theme_constant_override("outline_size", 4)
		_tip.z_index = 100
		_tip.position = Vector2(-80, -90)
		add_child(_tip)
	_tip.text = text
	_tip.visible = true
	_tip_timer = duration


func flash_white() -> void:
	_flash_timer = 0.08


func set_invuln(time_left: float) -> void:
	_invuln_timer = time_left


# ══ 动画 ══════════════════════════════════════════════════════════════════

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


func _process(delta: float) -> void:
	# 位移驱动 hop 相位（M08：不靠计时器）
	var dist := position.distance_to(_last_pos)
	_moved = lerpf(_moved, dist, 0.3)
	_last_pos = position
	_hop_phase += _moved * 3.0
	_idle_phase += delta * 2.0
	_charge_phase += delta * 4.0

	# 体型阻尼（0.25s）
	_tier_scale = lerpf(_tier_scale, _target_tier_scale, delta / TIER_DAMP_S)
	if absf(_tier_scale - _target_tier_scale) < 0.01:
		_tier_scale = _target_tier_scale
	_update_body()

	# 受击白闪
	if _flash_timer > 0.0:
		_flash_timer -= delta
		_body.color = Color.WHITE
	else:
		_body.color = main_color

	# 无敌闪烁（4Hz，结束前 1s 翻倍，A0001M12F05）
	if _invuln_timer > 0.0:
		_invuln_timer -= delta
		var freq := 8.0 if _invuln_timer < 1.0 else 4.0
		_body.visible = int(_invuln_timer * freq) % 2 == 0

	# 提示气泡
	if _tip != null and _tip.visible:
		_tip_timer -= delta
		if _tip_timer <= 0.0:
			_tip.visible = false


func _update_body() -> void:
	# 跳跳动画：y 位移（饥荒式一跳一跳）+ 缩放鼓胀
	var hop_bob := 0.0
	if anim == Anim.HOP:
		hop_bob = absf(sin(_hop_phase)) * 0.25
	elif anim == Anim.HOP_CHARGE:
		hop_bob = absf(sin(_hop_phase * 0.7)) * 0.14   # 更矮更慢（A0001M08F03）
	elif anim == Anim.CHARGE_IDLE:
		hop_bob = sin(_charge_phase) * 0.05 + 0.06     # 鼓胀脉动与充能环同频
	elif anim == Anim.IDLE:
		hop_bob = sin(_idle_phase) * 0.04
	var s := _tier_scale
	_body.scale = Vector2(s * (1.0 + hop_bob * 0.3), s * (1.0 - hop_bob * 0.35))
	_body.position.y = -hop_bob * s
	var eye_scale := s
	_eye_l.scale = Vector2(eye_scale, eye_scale)
	_eye_r.scale = Vector2(eye_scale, eye_scale)
	_pupil_l.scale = Vector2(eye_scale, eye_scale)
	_pupil_r.scale = Vector2(eye_scale, eye_scale)
	# 重装附加层：头顶蒸汽（占位 = 半透白圈呼吸）
	if current_tier == TIER_HEAVY:
		_body.outline_size = 5
	else:
		_body.outline_size = 3
