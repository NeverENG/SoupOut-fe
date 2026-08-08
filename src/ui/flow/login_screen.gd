## login_screen.gd — 登录页（A0001M13F01）
## ⚠️ 零网络请求（T0005M01F03：没有账号/登录态，只是本地填昵称）。
## 昵称 ≤16 字节 UTF-8（对齐 T0001M02F02 的 nickname[16]）。

extends Control

var _nick_input: LineEdit = null


func _ready() -> void:
	UiKit.full_rect_bg(self, Color(0.16, 0.11, 0.08))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)

	var logo := UiKit.make_label("🍲 一锅好汤", 72, Color(0.95, 0.85, 0.6))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(logo)
	vbox.add_child(UiKit.make_label("四个食材，各占一角。按住扩张，把汤铺出去。", 22, Color(0.8, 0.7, 0.55)))

	_nick_input = LineEdit.new()
	_nick_input.placeholder_text = "给自己起个名字（≤16 字节）"
	_nick_input.max_length = 16
	_nick_input.custom_minimum_size = Vector2(480, 64)
	_nick_input.add_theme_font_size_override("font_size", 26)
	var saved: String = SettingsDb.get_string("nickname", "食材")
	_nick_input.text = saved
	vbox.add_child(_nick_input)

	var start := UiKit.make_button("开火！")
	start.pressed.connect(_on_start)
	vbox.add_child(start)

	var ver := UiKit.make_label("P0 原型 · Godot 4.x", 14, Color(0.6, 0.55, 0.5))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.position = Vector2(0, 1040)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	add_child(ver)


func _on_start() -> void:
	var nick := _nick_input.text.strip_edges()
	if nick.is_empty():
		nick = "食材"
	SettingsDb.set_value("nickname", nick)
	App.instance.on_login_done(nick)
