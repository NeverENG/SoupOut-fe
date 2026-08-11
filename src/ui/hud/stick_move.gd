## stick_move.gd — 左摇杆双环（A0001M11F03：全作最核心的控件）
## 【输入逻辑与 2D 版等价，勿动】外圈（100%）拖出 = 移动；内圈（40%）长按 ≥ KNOB_hold_threshold → 扩张态。
## 扩张态细则（别做错）：成立后拇指可继续拖出去缓慢移动（手指没抬 = 持续）；
## 抬手即停；快速外拖（threshold 内离开内圈）= 只移动不充能。
## 判定「站在自己地盘」走客户端本地（A0001M12F02：不要服务端往返）。
## 3D 版仅重绘外观：奶油底盘 35% + 木沿 + 橙色拇指钮（软阴影）；
## 充能进度 = 玉米黄→热汤橙径向弧（get_charge_progress 本地预测驱动，保留）。

class_name StickMove
extends Control

const OUTER_R := 130.0
const INNER_R := 52.0              # 40% 内圈
const HOLD_THRESHOLD_S := 0.12     # KNOB_hold_threshold（设置可调）
const KNOB_R := 28.0

var battle: Node = null
var active := false
var charging := false
var _touch_idx := -1
var _touch_start := Vector2.ZERO
var _hold_time := 0.0
var _knob: Control = null
var _charge := 0.0                 # 充能进度 0..1（本地预测）
var _flash := 0.0                  # 拒绝充能红闪 0..1
var _reject_timer := 0.0

var _center := Vector2(OUTER_R, OUTER_R)   # 控件局部中心（_gui_input 事件为局部坐标）


## 拇指钮：橙色圆 + 软阴影 + 高光（独立子节点，永远盖在底盘绘制之上）
class Knob extends Control:
	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c + Vector2(0, 3), 26.0, UiKit.SHADOW)
		draw_circle(c, 26.0, UiKit.ORANGE)
		draw_arc(c, 26.0, 0.0, TAU, 40, UiKit.ORANGE_DARK, 3.0, true)
		draw_circle(c + Vector2(-7.0, -8.0), 8.0, Color(1, 1, 1, 0.30))


func setup(p_battle: Node) -> void:
	battle = p_battle
	# 左下角锚定（任意分辨率成立；圆环下缘沉出屏 30px = 拇指热区，与 2D 版一致）
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 30.0
	offset_right = 30.0 + OUTER_R * 2.0
	offset_top = 30.0 - OUTER_R * 2.0
	offset_bottom = 30.0
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_knob = Knob.new()
	_knob.size = Vector2(KNOB_R * 2.0, KNOB_R * 2.0)
	_knob.position = _center - Vector2(KNOB_R, KNOB_R)
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_knob)


func _draw() -> void:
	# 底盘：奶油 35% + 木沿
	draw_circle(_center, OUTER_R,
		Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.35))
	draw_arc(_center, OUTER_R - 3.0, 0.0, TAU, 64,
		Color(UiKit.WOOD.r, UiKit.WOOD.g, UiKit.WOOD.b, 0.55), 6.0, true)
	# 内圈（充能热区）：常态淡木描线，拒绝充能时红闪
	var inner := Color(UiKit.WOOD_DARK.r, UiKit.WOOD_DARK.g, UiKit.WOOD_DARK.b, 0.35) \
		.lerp(Color(1, 0.25, 0.2, 0.9), _flash)
	draw_arc(_center, INNER_R, 0.0, TAU, 48, inner, 3.0, true)
	if charging or _flash > 0.0:
		var fill := Color(UiKit.YELLOW.r, UiKit.YELLOW.g, UiKit.YELLOW.b,
			0.20 + 0.25 * _charge).lerp(Color(1, 0.3, 0.3, 0.5), _flash)
		draw_circle(_center, INNER_R - 2.0, fill)
	# 充能进度弧：玉米黄→热汤橙，12 点起顺时针
	if charging and _charge > 0.0:
		var col := UiKit.YELLOW.lerp(UiKit.ORANGE, _charge)
		draw_arc(_center, OUTER_R - 12.0, -PI / 2.0,
			-PI / 2.0 + TAU * clampf(_charge, 0.0, 1.0), 64, col, 9.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not active:
			active = true
			_touch_idx = t.index
			_touch_start = t.position
			_hold_time = 0.0
			charging = false
			_knob.position = t.position - Vector2(KNOB_R, KNOB_R)
		elif not t.pressed and t.index == _touch_idx:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_idx:
		_handle_drag(event.position)


func _handle_drag(pos: Vector2) -> void:
	_knob.position = pos - Vector2(KNOB_R, KNOB_R)
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
	_knob.position = _center - Vector2(KNOB_R, KNOB_R)


func _reject() -> void:
	## A0001M12F02：不在自己地盘 → 头顶提示 + 红环碎裂 + 短震动，1.5s 频率限制
	if _reject_timer > 0.0:
		return
	_reject_timer = 1.5
	var battle_root: Node = battle
	if battle_root.has_method("reject_charge"):
		battle_root.call("reject_charge")
	# 红环碎裂占位：内圈红闪（_draw 内按 _flash 插值）
	_flash = 1.0


func _process(delta: float) -> void:
	if _reject_timer > 0.0:
		_reject_timer -= delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
	# 充能进度显示（本地预测驱动：爽点不能等 RTT，T0005M09F01）
	if charging and battle != null and battle.has_method("get_charge_progress"):
		_charge = battle.call("get_charge_progress")
	elif not charging:
		_charge = 0.0
	queue_redraw()
