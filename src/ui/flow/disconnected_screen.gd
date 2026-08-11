## disconnected_screen.gd — 已断开页（A0001M12F08 超时）
## 「这锅汤没等到你」+ 返回主菜单。
## 视觉：暗化厨房背景 + 居中奶油卡：委屈的锅 + 一句话 + 返回按钮。

extends Control


func _ready() -> void:
	UiKit.kitchen_bg(self, 0.25)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := UiKit.make_panel()
	center.add_child(card)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 40)
	card.add_child(pad)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	pad.add_child(vbox)

	var pot := UiKit.make_label("😢🍲", 96)
	pot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(pot)
	var title := UiKit.make_label("这锅汤没等到你", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var note := UiKit.make_label("连接断开太久，这局已经散伙了", 22, UiKit.INK_SOFT)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(note)
	var back := UiKit.make_button("返回主菜单", Vector2(380, 92), UiKit.Btn.PRIMARY, 32)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): App.instance.on_back_to_menu())
	vbox.add_child(back)
