## disconnected_screen.gd — 已断开页（A0001M12F08 超时）
## 「这锅汤没等到你」+ 返回主菜单。

extends Control


func _ready() -> void:
	UiKit.full_rect_bg(self, Color(0.13, 0.09, 0.07))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)
	var title := UiKit.make_label("这锅汤没等到你", 56, Color(0.9, 0.75, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var back := UiKit.make_button("返回主菜单", Vector2(360, 80))
	back.pressed.connect(func(): App.instance.on_back_to_menu())
	vbox.add_child(back)
