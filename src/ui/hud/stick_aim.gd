## stick_aim.gd — 右摇杆：方向挥击（A0001M11F04）
## 【输入逻辑与 2D 版等价，勿动】拖出 = 持续朝向（角色转向 + 朝向指示）；抬手 = 挥击；
## 轻触 = 朝当前朝向挥一次。扩张态下底盘变灰 + 小锁，点击锁抖一下（不做文字弹窗）。
## 3D 版仅重绘外观：奶油底盘 35% + 木沿 + 橙色拇指钮（软阴影）+ 拖拽时玉米黄朝向指示。

class_name StickAim
extends Control

const OUTER_R := 110.0
const KNOB_R := 24.0

var battle: Node = null
var active := false
var _touch_idx := -1
var _knob: Control = null
var _center := Vector2(OUTER_R, OUTER_R)   # 控件局部中心（_gui_input 事件为局部坐标）
var _aim := Vector2.ZERO
var _locked := false
var _lock_label: Label = null


## 拇指钮：橙色圆 + 软阴影 + 高光
class Knob extends Control:
	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c + Vector2(0, 3), 22.0, UiKit.SHADOW)
		draw_circle(c, 22.0, UiKit.ORANGE)
		draw_arc(c, 22.0, 0.0, TAU, 40, UiKit.ORANGE_DARK, 3.0, true)
		draw_circle(c + Vector2(-6.0, -7.0), 7.0, Color(1, 1, 1, 0.30))


func setup(p_battle: Node) -> void:
	battle = p_battle
	# 右下角锚定（任意分辨率成立；下缘沉出屏 30px = 拇指热区）
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -40.0 - OUTER_R * 2.0
	offset_right = -40.0
	offset_top = 30.0 - OUTER_R * 2.0
	offset_bottom = 30.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_knob = Knob.new()
	_knob.size = Vector2(KNOB_R * 2.0, KNOB_R * 2.0)
	_knob.position = _center - Vector2(KNOB_R, KNOB_R)
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_knob)
	# 扩张态小锁（set_locked 时显示，A0001M11F04）
	_lock_label = UiKit.make_label("🔒", 30)
	_lock_label.position = _center - Vector2(18, 22)
	_lock_label.visible = false
	_lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lock_label)


func _draw() -> void:
	# 底盘：奶油 35% + 木沿
	draw_circle(_center, OUTER_R,
		Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.35))
	draw_arc(_center, OUTER_R - 3.0, 0.0, TAU, 64,
		Color(UiKit.WOOD.r, UiKit.WOOD.g, UiKit.WOOD.b, 0.55), 6.0, true)
	# 拖拽中：玉米黄朝向指示（中心 → 环缘）
	if active and _aim.length_squared() > 0.0025 and not _locked:
		var dirn := _aim.normalized()
		draw_line(_center + dirn * 22.0, _center + dirn * (OUTER_R - 14.0),
			Color(UiKit.YELLOW.r, UiKit.YELLOW.g, UiKit.YELLOW.b, 0.65), 6.0, true)
		draw_circle(_center + dirn * (OUTER_R - 14.0), 6.0, UiKit.YELLOW)


func set_locked(l: bool) -> void:
	_locked = l
	modulate = Color(0.55, 0.55, 0.55, 0.8) if l else Color.WHITE
	_lock_label.visible = l


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not active:
			active = true
			_touch_idx = t.index
			_knob.position = t.position - Vector2(KNOB_R, KNOB_R)
		elif not t.pressed and t.index == _touch_idx:
			# 抬手 = 挥击（A0001M11F04）
			if _locked:
				_lock_shake()
			elif _aim.length_squared() > 0.01:
				battle.queue_attack()
			else:
				battle.queue_attack()   # 轻触 = 朝当前朝向挥一次
			active = false
			_knob.position = _center - Vector2(KNOB_R, KNOB_R)
			_aim = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == _touch_idx:
		var offset: Vector2 = event.position - _center
		_aim = offset / OUTER_R
		battle.set_aim_stick(_aim)
		_knob.position = event.position - Vector2(KNOB_R, KNOB_R)


func _lock_shake() -> void:
	## 扩张态下点击：锁抖一下（A0001M11F04：不做文字弹窗）
	var tween := create_tween()
	tween.tween_property(self, "position", position + Vector2(6, 0), 0.04)
	tween.tween_property(self, "position", position - Vector2(6, 0), 0.04)
	tween.tween_property(self, "position", position, 0.04)


func _process(_delta: float) -> void:
	queue_redraw()
