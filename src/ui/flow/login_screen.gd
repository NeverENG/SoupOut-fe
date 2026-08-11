## login_screen.gd — 登录页（A0001M13F01）
## ⚠️ 零网络请求（T0005M01F03：没有账号/登录态，只是本地填昵称）。
## 昵称 ≤16 字节 UTF-8（对齐 T0001M02F02 的 nickname[16]）。
## 视觉：厨房动态背景 + 居中奶油卡片；logo 走 UiKit.make_title（白字厚描边）。

extends Control

var _nick_input: LineEdit = null


func _ready() -> void:
	UiKit.kitchen_bg(self)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# logo 放卡片外面：大标题压在暖背景上才有「游戏封面」的劲儿
	var page := VBoxContainer.new()
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_theme_constant_override("separation", 28)
	center.add_child(page)

	var logo := UiKit.make_title("🍲 SoupOut", 84)
	page.add_child(logo)
	var brand := UiKit.make_title("一锅好汤", 36, UiKit.YELLOW)
	page.add_child(brand)

	var card := UiKit.make_panel()
	page.add_child(card)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 36)
	card.add_child(pad)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	pad.add_child(vbox)

	var tagline := UiKit.make_label("四个食材，各占一角。按住扩张，把汤铺出去。", 24, UiKit.INK_SOFT)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tagline)

	_nick_input = LineEdit.new()
	_nick_input.placeholder_text = "给自己起个名字（≤16 字节）"
	_nick_input.max_length = 16
	_nick_input.custom_minimum_size = Vector2(520, 72)
	_nick_input.add_theme_font_size_override("font_size", 30)
	_nick_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var saved: String = SettingsDb.get_string("nickname", "食材")
	_nick_input.text = saved
	vbox.add_child(_nick_input)

	var start := UiKit.make_button("开火！", Vector2(380, 92), UiKit.Btn.SUCCESS, 34)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(_on_start)
	vbox.add_child(start)

	# 版本号：右下角低调蹲着（描边全关，别抢戏）
	var ver := UiKit.make_label("P0 原型 · Godot 4.x", 14, Color(1, 1, 1, 0.55))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -280
	ver.offset_top = -40
	ver.offset_right = -20
	ver.offset_bottom = -12
	add_child(ver)


func _on_start() -> void:
	var nick := _nick_input.text.strip_edges()
	if nick.is_empty():
		nick = "食材"
	SettingsDb.set_value("nickname", nick)
	App.instance.on_login_done(nick)
