## ui_kit.gd — UI 构建小工具（无美术 → 代码构建，九宫格正式素材接入点）
## 所有文案走 .tr()（A0001M06F01：不得把文字烧进贴图）

class_name UiKit


static func make_label(text: String, size: int = 24, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.06))
	l.add_theme_constant_override("outline_size", 3)
	return l


static func make_button(text: String, size: Vector2 = Vector2(360, 84)) -> Button:
	var b := Button.new()
	b.text = tr(text)
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", 28)
	return b


static func make_panel(color: Color = Color(0.18, 0.14, 0.10, 0.85)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(color))
	return p


static func _style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(12)
	s.set_border_width_all(2)
	s.border_color = Color(0.45, 0.33, 0.22)
	return s


## 全屏背景容器（暖色渐变占位）
static func full_rect_bg(parent: Control, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(r)
	return r
