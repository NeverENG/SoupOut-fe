## stick_aim.gd — 右摇杆：方向挥击（A0001M11F04）
## 拖出 = 持续朝向（角色转向 + 朝向指示）；抬手 = 挥击；轻触 = 朝当前朝向挥一次。
## 扩张态下底盘变灰 + 小锁，点击锁抖一下（不做文字弹窗，A0001M11F04）。

class_name StickAim
extends Control

const OUTER_R := 110.0

var battle: Node = null
var active := false
var _touch_idx := -1
var _knob: ColorRect = null
var _center := Vector2(1760, 980)
var _aim := Vector2.ZERO
var _locked := false


func setup(p_battle: Node) -> void:
	battle = p_battle
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	position = _center - Vector2(OUTER_R, OUTER_R)
	custom_minimum_size = Vector2(OUTER_R * 2, OUTER_R * 2)
	var outer := _ring(OUTER_R, Color(1, 1, 1, 0.15))
	outer.position = Vector2(OUTER_R, OUTER_R)
	add_child(outer)
	_knob = ColorRect.new()
	_knob.color = Color(1, 0.9, 0.7, 0.9)
	_knob.size = Vector2(48, 48)
	_knob.position = Vector2(OUTER_R - 24, OUTER_R - 24)
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


func set_locked(l: bool) -> void:
	_locked = l
	modulate = Color(0.55, 0.55, 0.55, 0.8) if l else Color.WHITE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not active:
			active = true
			_touch_idx = t.index
			_knob.position = t.position - Vector2(24, 24)
		elif not t.pressed and t.index == _touch_idx:
			# 抬手 = 挥击（A0001M11F04）
			if _locked:
				_lock_shake()
			elif _aim.length_squared() > 0.01:
				battle.queue_attack()
			else:
				battle.queue_attack()   # 轻触 = 朝当前朝向挥一次
			active = false
			_knob.position = Vector2(OUTER_R - 24, OUTER_R - 24)
			_aim = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == _touch_idx:
		var offset := event.position - _center
		_aim = offset / OUTER_R
		battle.set_aim_stick(_aim)
		_knob.position = event.position - Vector2(24, 24)


func _lock_shake() -> void:
	## 扩张态下点击：锁抖一下（A0001M11F04：不做文字弹窗）
	var tween := create_tween()
	tween.tween_property(self, "position", position + Vector2(6, 0), 0.04)
	tween.tween_property(self, "position", position - Vector2(6, 0), 0.04)
	tween.tween_property(self, "position", position, 0.04)
