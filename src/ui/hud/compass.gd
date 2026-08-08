## compass.gd — 化汤罗盘（A0001M11F07）
## 触发：场上存在化汤区期间持续显示；屏幕边缘箭头 + 距离，指向化汤区质心；
## 配色 = 死者主色，饱和度衰减向原汤色；箭头旁剩余面积 % 实时下降。
## 数据源：0x100 PlayerDied 定位 + authGrid 残余格质心（T0005M09F01）；占位接口。

class_name Compass
extends Control

var _arrow: Label = null
var _info: Label = null
var active := false
var target_pos := Vector2.ZERO
var remaining_permyriad := 0


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow = Label.new()
	_arrow.add_theme_font_size_override("font_size", 48)
	_arrow.text = "➜"
	_arrow.visible = false
	add_child(_arrow)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 22)
	_info.add_theme_color_override("font_color", Color(0.9, 0.8, 0.7))
	_info.visible = false
	add_child(_info)


func show_compass(world_pos: Vector2, remaining: int, color: Color) -> void:
	active = true
	target_pos = world_pos
	remaining_permyriad = remaining
	_arrow.modulate = color
	_arrow.visible = true
	_info.visible = true


func hide_compass() -> void:
	active = false
	_arrow.visible = false
	_info.visible = false


func _process(_delta: float) -> void:
	if not active:
		return
	# 屏内时箭头消失（A0001M11F07：改为化汤区本身冒气泡）
	var center := get_viewport_rect().size / 2.0
	var dir := target_pos - center
	if dir.length() < 500.0:
		_arrow.visible = false
		return
	_arrow.visible = true
	_arrow.rotation = dir.angle()
	_arrow.position = center + dir.normalized() * 380.0 - Vector2(24, 24)
	_info.text = "%.0f%%" % (remaining_permyriad / 100.0)
	_info.position = _arrow.position + Vector2(0, 40)
