## compass.gd — 化汤罗盘（A0001M11F07，3D 版）
## 触发：场上存在化汤区期间持续显示；屏幕边缘箭头 + 剩余面积 %，指向化汤区质心；
## 配色 = 死者主色，饱和度衰减向原汤色；箭头旁剩余面积 % 实时下降。
## 3D 版修正：show_compass 收到的是世界坐标（48×48 世界单位，旧版误当屏幕像素比较）。
## 经当前 Camera3D unproject 到屏幕：目标在屏内 → 隐藏（改为化汤区本身冒气泡）；
## 屏外 → 吸附屏缘 40px 内缘、箭头指向目标。
## 数据源：0x100 PlayerDied 定位 + authGrid 残余格质心（T0005M09F01）；占位接口。

class_name Compass
extends Control

const EDGE_MARGIN := 40.0

var _arrow: Label = null
var _info: Label = null
var active := false
var target_pos := Vector2.ZERO     # 世界坐标（48×48 世界单位）
var remaining_permyriad := 0


func setup() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow = Label.new()
	_arrow.text = "➜"
	_arrow.add_theme_font_size_override("font_size", 46)
	_arrow.add_theme_color_override("font_outline_color", UiKit.WOOD_DARK)
	_arrow.add_theme_constant_override("outline_size", 6)
	_arrow.visible = false
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arrow)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 20)
	_info.add_theme_color_override("font_color", UiKit.CREAM)
	_info.add_theme_color_override("font_outline_color", UiKit.WOOD_DARK)
	_info.add_theme_constant_override("outline_size", 5)
	_info.visible = false
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_arrow.visible = false
		_info.visible = false
		return
	# 世界(48×48 平面 y=0) → 屏幕像素
	var screen := cam.unproject_position(Vector3(target_pos.x, 0.0, target_pos.y))
	var vp := get_viewport_rect().size
	# 屏内时箭头消失（A0001M11F07：改为化汤区本身冒气泡）
	if screen.x >= 0.0 and screen.y >= 0.0 and screen.x <= vp.x and screen.y <= vp.y:
		_arrow.visible = false
		_info.visible = false
		return
	_arrow.visible = true
	_info.visible = true
	# 吸附屏缘 40px 内缘，箭头指向真实目标方向
	var clamped := Vector2(
		clampf(screen.x, EDGE_MARGIN, vp.x - EDGE_MARGIN),
		clampf(screen.y, EDGE_MARGIN, vp.y - EDGE_MARGIN))
	var dirn := (screen - clamped).normalized()
	_arrow.pivot_offset = _arrow.size / 2.0
	_arrow.rotation = dirn.angle()
	_arrow.position = clamped - _arrow.size / 2.0
	_info.text = "%.0f%%" % (remaining_permyriad / 100.0)
	_info.position = clamped - dirn * 44.0 - _info.size / 2.0
