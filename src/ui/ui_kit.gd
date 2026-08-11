## ui_kit.gd — UI 设计系统（胡闹厨房式卡通风格）
## 设计令牌 + 组件工厂 + 全局 Theme。所有界面统一从这里取样式,不再各自硬编码。
## 全部程序化 StyleBoxFlat:任意分辨率下锐利,调色只改 tokens。
## 所有文案仍走 .tr()(A0001M06F01:不得把文字烧进贴图)。

class_name UiKit

# ── 设计令牌:配色(暖厨房) ─────────────────────────────────────────────
const INK := Color("3d2417")            # 深可可 · 主文字
const INK_SOFT := Color("6b4a33")       # 浅可可 · 次要文字
const CREAM := Color("fff3dd")          # 奶油 · 卡片底
const CREAM_DARK := Color("f2dfbe")     # 奶油(按压)
const WOOD := Color("9c6238")           # 木色 · 边框/台面
const WOOD_DARK := Color("6e4224")      # 深木 · 描边
const APRON := Color("faf0e0")          # 围裙白
const ORANGE := Color("f58a3c")         # 主按钮 · 热汤橙
const ORANGE_DARK := Color("c4632a")
const RED := Color("e8503f")            # 危险/退出 · 番茄红
const RED_DARK := Color("b03427")
const GREEN := Color("59b85c")          # 确认/开锅 · 青菜绿
const GREEN_DARK := Color("3c8a41")
const YELLOW := Color("ffc93c")         # 高亮 · 玉米黄
const YELLOW_DARK := Color("d19a1d")
const BLUE := Color("3fa7d6")           # 次要 · 瓷碗蓝
const BLUE_DARK := Color("2b7ba0")
const SHADOW := Color(0.24, 0.12, 0.05, 0.35)

## 玩家四色(与地盘 shader / 角色保持一致,勿改)
const P_COLORS: Array[Color] = [
	Color(0.720, 0.300, 0.200), Color(0.440, 0.550, 0.250),
	Color(0.840, 0.630, 0.250), Color(0.500, 0.360, 0.530)]
const P_DARKS: Array[Color] = [
	Color(0.500, 0.190, 0.120), Color(0.290, 0.380, 0.160),
	Color(0.600, 0.430, 0.140), Color(0.330, 0.230, 0.370)]
const INGREDIENT_NAMES: Array[String] = ["番茄", "青菜", "玉米", "紫芋"]

static var _font: FontFile = null
static var _theme: Theme = null


# ── 字体 ─────────────────────────────────────────────────────────────────
static func font() -> FontFile:
	if _font == null:
		_font = load("res://assets/fonts/zcool_kuaile.ttf")
		var fallbacks: Array[Font] = []
		var baloo: FontFile = load("res://assets/fonts/baloo2.ttf")
		if baloo != null:
			fallbacks.append(baloo)
		# 系统 emoji 兜底(👑 🍲 等;按平台路径尝试,失败无害)
		for p in ["/System/Library/Fonts/Apple Color Emoji.ttc",
				"C:/Windows/Fonts/seguiemj.ttf",
				"/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"]:
			if FileAccess.file_exists(p):
				var ef := FontFile.new()
				if ef.load_dynamic_font(p) == OK:
					fallbacks.append(ef)
				break
		if not fallbacks.is_empty():
			_font.fallbacks = fallbacks
	return _font


# ── StyleBox 工厂 ────────────────────────────────────────────────────────
static func sb(bg: Color, border: Color = Color.TRANSPARENT, bw: int = 0,
		radius: int = 18, shadow_size: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	if bw > 0:
		s.set_border_width_all(bw)
		s.border_color = border
	if shadow_size > 0:
		s.shadow_color = SHADOW
		s.shadow_size = shadow_size
		s.shadow_offset = Vector2(0, shadow_size * 0.6)
	s.anti_aliasing = true
	return s


## 带「底边加厚」的立体按钮面(胡闹厨房式厚底)
static func sb_chunky(bg: Color, dark: Color, radius: int = 18, lift: int = 6) -> StyleBoxFlat:
	var s := sb(bg, dark, 3, radius, 4)
	s.border_width_bottom = lift + 3
	s.border_color = dark
	s.content_margin_left = 26.0
	s.content_margin_right = 26.0
	s.content_margin_top = 10.0
	s.content_margin_bottom = 10.0 + float(lift) * 0.4
	return s


# ── 全局主题(app 启动时挂到 root window) ────────────────────────────────
static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 26

	# Label
	t.set_color("font_color", "Label", INK)

	# Button:奶油底默认款
	t.set_stylebox("normal", "Button", sb_chunky(CREAM, WOOD))
	t.set_stylebox("hover", "Button", sb_chunky(Color("fffbef"), WOOD))
	t.set_stylebox("pressed", "Button", _pressed_of(sb_chunky(CREAM_DARK, WOOD)))
	t.set_stylebox("disabled", "Button", sb_chunky(Color("d9cbb4"), Color("a8977f")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(0.42, 0.36, 0.3, 0.8))
	t.set_font_size("font_size", "Button", 28)

	# LineEdit
	var le := sb(Color(1, 1, 1, 0.9), WOOD, 3, 14)
	le.content_margin_left = 18.0
	le.content_margin_right = 18.0
	t.set_stylebox("normal", "LineEdit", le)
	var lef := sb(Color.WHITE, ORANGE, 3, 14)
	lef.content_margin_left = 18.0
	lef.content_margin_right = 18.0
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.55, 0.45, 0.36, 0.7))
	t.set_color("caret_color", "LineEdit", ORANGE)

	# Panel / PanelContainer:奶油卡片
	t.set_stylebox("panel", "PanelContainer", sb(CREAM, WOOD, 4, 24, 8))
	t.set_stylebox("panel", "Panel", sb(CREAM, WOOD, 4, 24, 8))

	# HSlider
	var groove := sb(Color(0.32, 0.2, 0.12, 0.35), Color.TRANSPARENT, 0, 8)
	groove.content_margin_top = 7.0
	groove.content_margin_bottom = 7.0
	t.set_stylebox("slider", "HSlider", groove)
	var gfill := sb(ORANGE, Color.TRANSPARENT, 0, 8)
	gfill.content_margin_top = 7.0
	gfill.content_margin_bottom = 7.0
	t.set_stylebox("grabber_area", "HSlider", gfill)
	t.set_stylebox("grabber_area_highlight", "HSlider", gfill)
	t.set_icon("grabber", "HSlider", _circle_icon(14, Color.WHITE, WOOD_DARK))
	t.set_icon("grabber_highlight", "HSlider", _circle_icon(15, Color("fff3dd"), ORANGE_DARK))

	# CheckBox
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_color("font_color", "CheckBox", INK)

	# ProgressBar
	t.set_stylebox("background", "ProgressBar", sb(Color(0.32, 0.2, 0.12, 0.3), Color.TRANSPARENT, 0, 10))
	t.set_stylebox("fill", "ProgressBar", sb(GREEN, Color.TRANSPARENT, 0, 10))

	# 弹窗
	t.set_stylebox("panel", "PopupPanel", sb(CREAM, WOOD, 4, 18, 10))
	_theme = t
	return t


static func _pressed_of(s: StyleBoxFlat) -> StyleBoxFlat:
	# 按压:厚底变薄 + 内容下移 = 「按进去」
	var p := s.duplicate() as StyleBoxFlat
	p.border_width_bottom = 3
	p.content_margin_top = s.content_margin_top + 4.0
	p.content_margin_bottom = s.content_margin_bottom - 4.0
	p.shadow_size = 0
	return p


static func _circle_icon(r: int, fill: Color, border: Color) -> ImageTexture:
	var d := r * 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	for y in range(d):
		for x in range(d):
			var dist := Vector2(x - r + 0.5, y - r + 0.5).length()
			if dist < r - 0.8:
				img.set_pixel(x, y, fill if dist < r - 3.2 else border)
	return ImageTexture.create_from_image(img)


static func _check_icon(checked: bool) -> ImageTexture:
	var s := 30
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in range(s):
		for x in range(s):
			var edge := x < 3 or y < 3 or x >= s - 3 or y >= s - 3
			var col := WOOD_DARK if edge else (GREEN if checked else Color(1, 1, 1, 0.9))
			img.set_pixel(x, y, col)
	if checked:
		for i in range(6, s - 8):
			var yy := int(s * 0.62 - absf(i - s * 0.38) * 0.55)
			for w in range(3):
				if yy + w >= 0 and yy + w < s:
					img.set_pixel(i, yy + w, Color.WHITE)
	return ImageTexture.create_from_image(img)


# ── 组件工厂 ─────────────────────────────────────────────────────────────
static func make_label(text: String, size: int = 24, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## 大标题:白字 + 深色厚描边 + 投影(游戏 logo 风)
static func make_title(text: String, size: int = 64, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", WOOD_DARK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 7))
	l.add_theme_color_override("font_shadow_color", SHADOW)
	l.add_theme_constant_override("shadow_offset_y", maxi(3, size / 16))
	return l


enum Btn { DEFAULT, PRIMARY, SUCCESS, DANGER, GHOST }

static func make_button(text: String, size: Vector2 = Vector2(360, 84),
		kind: int = Btn.DEFAULT, font_size: int = 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", font_size)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bg: Color
	var dark: Color
	var fg := Color.WHITE
	match kind:
		Btn.PRIMARY:
			bg = ORANGE
			dark = ORANGE_DARK
		Btn.SUCCESS:
			bg = GREEN
			dark = GREEN_DARK
		Btn.DANGER:
			bg = RED
			dark = RED_DARK
		Btn.GHOST:
			bg = Color(1, 1, 1, 0.10)
			dark = Color(1, 1, 1, 0.45)
		_:
			bg = CREAM
			dark = WOOD
			fg = INK
	if kind != Btn.DEFAULT:
		b.add_theme_stylebox_override("normal", sb_chunky(bg, dark))
		b.add_theme_stylebox_override("hover", sb_chunky(bg.lightened(0.08), dark))
		b.add_theme_stylebox_override("pressed", _pressed_of(sb_chunky(bg.darkened(0.08), dark)))
		b.add_theme_stylebox_override("disabled", sb_chunky(Color("d9cbb4"), Color("a8977f")))
		b.add_theme_color_override("font_color", fg)
		b.add_theme_color_override("font_hover_color", fg)
		b.add_theme_color_override("font_pressed_color", fg)
		if kind != Btn.GHOST:
			b.add_theme_color_override("font_outline_color", dark.darkened(0.2))
			b.add_theme_constant_override("outline_size", 4)
	bounce(b)
	return b


## 悬停/按压弹性动画:企业级手感的一半来自这 20 行
static func bounce(c: Control) -> void:
	c.pivot_offset = c.size / 2.0
	c.resized.connect(func() -> void: c.pivot_offset = c.size / 2.0)
	c.mouse_entered.connect(func() -> void: _tw_scale(c, Vector2(1.05, 1.05), 0.10))
	c.mouse_exited.connect(func() -> void: _tw_scale(c, Vector2.ONE, 0.12))
	if c is BaseButton:
		(c as BaseButton).button_down.connect(func() -> void: _tw_scale(c, Vector2(0.94, 0.94), 0.06))
		(c as BaseButton).button_up.connect(func() -> void: _tw_scale(c, Vector2(1.05, 1.05), 0.10))


static func _tw_scale(c: Control, to: Vector2, dur: float) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	var tw := c.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(c, "scale", to, dur)


static func make_panel(color: Color = CREAM) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(color, WOOD, 4, 24, 8))
	return p


## 全屏背景容器(兼容旧接口)
static func full_rect_bg(parent: Control, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(r)
	return r


## 厨房风全屏动态背景:暖色渐变 + 缓慢漂浮的食材图形。所有 flow 页面共用。
static func kitchen_bg(parent: Control, dim: float = 0.0) -> Control:
	var bg := Control.new()
	bg.name = "KitchenBg"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_script(load("res://src/ui/kitchen_bg.gd"))
	bg.set("dim", dim)
	parent.add_child(bg)
	return bg


## 圆角色块(食材色卡等)
static func icon_swatch(color: Color, size: float = 44.0) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.add_theme_stylebox_override("panel", sb(color, color.darkened(0.35), 3, int(size / 2.6)))
	return p
