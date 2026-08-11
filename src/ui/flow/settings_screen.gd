## settings_screen.gd — 设置（A0001M13F06）
## 操作（摇杆灵敏度/长按判定/浮动摇杆）/ 画面（震屏强度含关闭档/顿帧/粒子）/
## 可读性（色盲模式/图案强度/UI 缩放）/ 音频（主/音乐/音效 → Bus）/ 账号（昵称）
## 震屏强度必须能关（无障碍底线，M12F03）。
## 视觉：厨房背景 + 居中奶油大卡，行内滚动；分区用 HSeparator + 橙字小标。

extends Control

var from_ui_state: int = -1


func _ready() -> void:
	UiKit.kitchen_bg(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	margin.add_child(root)

	var title := UiKit.make_title("设置", 56)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(title)

	var card := UiKit.make_panel()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(card)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 32)
	card.add_child(pad)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(980, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(vbox)

	vbox.add_child(_section("音频"))
	vbox.add_child(_slider_row("主音量", "master_volume", 0.0, 1.0))
	vbox.add_child(_slider_row("音乐音量", "music_volume", 0.0, 1.0))
	vbox.add_child(_slider_row("音效音量", "sfx_volume", 0.0, 1.0))

	vbox.add_child(_section("操作"))
	vbox.add_child(_slider_row("左摇杆灵敏度", "left_stick_sens", 0.5, 2.0))
	vbox.add_child(_slider_row("右摇杆灵敏度", "right_stick_sens", 0.5, 2.0))
	vbox.add_child(_slider_row("长按判定时长 KNOB_hold_threshold", "hold_threshold", 0.05, 0.3))
	vbox.add_child(_check_row("浮动摇杆", "floating_stick"))

	vbox.add_child(_section("画面"))
	vbox.add_child(_slider_row("震屏强度（0 = 关闭）", "shake_intensity", 0.0, 1.0))
	vbox.add_child(_slider_row("顿帧强度", "hitstop_intensity", 0.0, 1.0))
	vbox.add_child(_slider_row("粒子密度", "particle_density", 0.0, 1.0))

	vbox.add_child(_section("可读性"))
	vbox.add_child(_check_row("色盲模式（提高地盘图案对比度）", "colorblind_mode"))

	var back := UiKit.make_button("返回", Vector2(320, 80))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_back)
	root.add_child(back)


## 分区头：细分隔线 + 橙色小标（分隔线颜色压得很淡，别把卡片切碎）
func _section(heading: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", UiKit.sb(Color(0.55, 0.38, 0.22, 0.22), Color.TRANSPARENT, 0, 2))
	box.add_child(sep)
	var l := UiKit.make_label(heading, 28, UiKit.ORANGE_DARK)
	box.add_child(l)
	return box


func _slider_row(label_text: String, key: String, lo: float, hi: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := UiKit.make_label(label_text, 26, UiKit.INK_SOFT)
	label.custom_minimum_size = Vector2(420, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(420, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = SettingsDb.get_float(key, UiKit_default(key))
	slider.value_changed.connect(func(v: float): SettingsDb.set_value(key, v))
	row.add_child(slider)
	return row


func _check_row(label_text: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var cb := CheckBox.new()
	cb.text = tr(label_text)
	cb.add_theme_font_size_override("font_size", 26)
	cb.button_pressed = SettingsDb.get_bool(key, false)
	cb.toggled.connect(func(v: bool): SettingsDb.set_value(key, v))
	row.add_child(cb)
	return row


func _back() -> void:
	App.instance.on_back_to_menu()


func UiKit_default(key: String) -> float:
	match key:
		"master_volume": return 1.0
		"music_volume": return 0.8
		"sfx_volume": return 1.0
		"left_stick_sens": return 1.0
		"right_stick_sens": return 1.0
		"hold_threshold": return 0.12
		"shake_intensity": return 1.0
		"hitstop_intensity": return 1.0
		"particle_density": return 1.0
	return 1.0
