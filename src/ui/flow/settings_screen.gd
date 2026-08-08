## settings_screen.gd — 设置（A0001M13F06）
## 操作（摇杆灵敏度/长按判定/浮动摇杆）/ 画面（震屏强度含关闭档/顿帧/粒子）/ 
## 可读性（色盲模式/图案强度/UI 缩放）/ 音频（主/音乐/音效 → Bus）/ 账号（昵称）
## 震屏强度必须能关（无障碍底线，M12F03）。

extends Control

var from_ui_state: int = -1


func _ready() -> void:
	UiKit.full_rect_bg(self, Color(0.15, 0.11, 0.08))
	var title := UiKit.make_label("设置", 44, Color(0.95, 0.85, 0.6))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position = Vector2(0, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.position = Vector2(0, 120)
	add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(1600, 0)
	vbox.add_theme_constant_override("separation", 18)
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

	var back := UiKit.make_button("返回", Vector2(320, 72))
	back.set_anchors_preset(Control.PRESET_BOTTOM_CENTER)
	back.position = Vector2(-160, -60)
	back.pressed.connect(_back)
	add_child(back)


func _section(name: String) -> Label:
	var l := UiKit.make_label(name, 26, Color(0.95, 0.8, 0.5))
	l.add_theme_constant_override("outline_size", 0)
	return l


func _slider_row(label_text: String, key: String, lo: float, hi: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := UiKit.make_label(label_text, 20, Color(0.85, 0.75, 0.6))
	label.custom_minimum_size = Vector2(420, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(400, 0)
	slider.value = SettingsDb.get_float(key, UiKit_default(key))
	slider.value_changed.connect(func(v: float): SettingsDb.set_value(key, v))
	row.add_child(slider)
	return row


func _check_row(label_text: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var cb := CheckBox.new()
	cb.text = tr(label_text)
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
