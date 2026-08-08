## stick_move.gd — 左摇杆双环（A0001M11F03：全作最核心的控件）
## 外圈（100%）拖出 = 移动；内圈（40%）长按 ≥ KNOB_hold_threshold → 扩张态。
## 扩张态细则（别做错）：成立后拇指可继续拖出去缓慢移动（手指没抬 = 持续）；
## 抬手即停；快速外拖（threshold 内离开内圈）= 只移动不充能。
## 判定「站在自己地盘」走客户端本地（A0001M12F02：不要服务端往返）。

class_name StickMove
extends Control

const OUTER_R := 130.0
const INNER_R := 52.0              # 40% 内圈
const HOLD_THRESHOLD_S := 0.12     # KNOB_hold_threshold（设置可调）

var battle: Node = null
var active := false
var charging := false
var _touch_idx := -1
var _touch_start := Vector2.ZERO
var _hold_time := 0.0
var _knob: ColorRect = null
var _inner_fill: TextureProgressBar = null
var _hint_timer := 0.0
var _reject_timer := 0.0

var _center := Vector2(160, 980)   # 距左 = 短边12%，距下 = 短边14%（A0001M11F03）


func setup(p_battle: Node) -> void:
	battle = p_battle
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	position = _center - Vector2(OUTER_R, OUTER_R)
	custom_minimum_size = Vector2(OUTER_R * 2, OUTER_R * 2)
	# 外圈底盘（半透汤锅纹圆环）
	var outer := _ring(OUTER_R, Color(1, 1, 1, 0.18))
	outer.position = Vector2(OUTER_R, OUTER_R)
	add_child(outer)
	# 内圈（充能径向填充占位：TextureProgressBar 用程序化纹理）
	_inner_fill = TextureProgressBar.new()
	_inner_fill.position = Vector2(OUTER_R - INNER_R, OUTER_R - INNER_R)
	_inner_fill.size = Vector2(INNER_R * 2, INNER_R * 2)
	_inner_fill.value = 0
	_inner_fill.max_value = 100
	_inner_fill.texture_progress = _radial_texture()
	_inner_fill.modulate = Color(1, 0.9, 0.5, 0.7)
	add_child(_inner_fill)
	# 拇指点
	_knob = ColorRect.new()
	_knob.color = Color(1, 0.95, 0.8, 0.9)
	_knob.size = Vector2(56, 56)
	_knob.position = Vector2(OUTER_R - 28, OUTER_R - 28)
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_knob)


func _ring(r: float, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(48):
		var a := TAU * i / 48.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	p.polygon = pts
	p.color = color
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _radial_texture() -> GradientTexture2D:
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 0.85, 0.4, 0.9), Color(1, 0.85, 0.4, 0.15)])
	g.gradient = grad
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	return g


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not active:
			active = true
			_touch_idx = t.index
			_touch_start = t.position
			_hold_time = 0.0
			charging = false
			_knob.position = t.position - Vector2(28, 28)
		elif not t.pressed and t.index == _touch_idx:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_idx:
		_handle_drag(event.position)


func _handle_drag(pos: Vector2) -> void:
	_knob.position = pos - Vector2(28, 28)
	var offset := pos - _center
	var dist := offset.length()
	var stick := offset / OUTER_R
	# 扩张态判定（A0001M11F03 细则）
	if not charging:
		if dist <= INNER_R:
			_hold_time += get_process_delta_time()
			if _hold_time >= SettingsDb.get_float("hold_threshold", HOLD_THRESHOLD_S):
				if battle.can_charge():
					charging = true
					battle.set_charging(true)
				else:
					_reject()
					_hold_time = 0.0
		else:
			# 快速外拖：只移动，不触发充能
			_hold_time = 0.0
			battle.set_move_stick(stick)
	else:
		# 扩张态：可继续拖出去缓慢移动（移动向量由 battle 内部降速）
		battle.set_move_stick(stick)
		battle.set_charging(true)
	if not charging:
		battle.set_move_stick(stick)


func _release() -> void:
	active = false
	charging = false
	_touch_idx = -1
	battle.set_charging(false)
	battle.set_move_stick(Vector2.ZERO)
	_knob.position = Vector2(OUTER_R - 28, OUTER_R - 28)


func _reject() -> void:
	## A0001M12F02：不在自己地盘 → 头顶提示 + 红环碎裂 + 短震动，1.5s 频率限制
	if _reject_timer > 0.0:
		return
	_reject_timer = 1.5
	var battle_root: Node = battle
	if battle_root.has_method("reject_charge"):
		battle_root.call("reject_charge")
	# 红环碎裂占位：内圈闪红
	_inner_fill.modulate = Color(1, 0.3, 0.3, 0.9)
	var tween := create_tween()
	tween.tween_property(_inner_fill, "modulate", Color(1, 0.9, 0.5, 0.7), 0.4)


func _process(delta: float) -> void:
	if _reject_timer > 0.0:
		_reject_timer -= delta
	# 充能进度显示（本地预测驱动：爽点不能等 RTT，T0005M09F01）
	if charging and battle != null and battle.has_method("get_charge_progress"):
		_inner_fill.value = battle.call("get_charge_progress") * 100.0
