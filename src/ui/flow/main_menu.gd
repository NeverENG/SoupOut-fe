## main_menu.gd — 主菜单（A0001M13F02）
## 开锅！（QuickMatch）· 和朋友炖（CreateRoom）· 输入房间码（JoinRoom）· 单机试玩（P0）
## 左 1/3：当前所选食材大立绘 + 地盘色样；右上：头像/昵称/齿轮；底部：三操作提示轮播。
## 不做：商店/任务/赛季/公告墙/抽卡（A0001M13F02 明确）。

extends Control

var _room_input: LineEdit = null


func _ready() -> void:
	UiKit.full_rect_bg(self, Color(0.17, 0.12, 0.09))
	# 右上：昵称 + 齿轮（设置）
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.position = Vector2(-360, 24)
	add_child(top)
	top.add_child(UiKit.make_label(SettingsDb.get_string("nickname", "食材"), 22))
	var gear := UiKit.make_button("⚙", Vector2(64, 48))
	gear.pressed.connect(func(): App.instance.on_show_settings())
	top.add_child(gear)

	# 左 1/3：当前食材
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.position = Vector2(60, 220)
	add_child(left)
	var ing := App.instance.ingredient_pref
	var names := ["排骨", "紫菜", "玉米", "茄子"]
	var colors := [Color(0.949, 0.565, 0.608), Color(0.18, 0.604, 0.525),
		Color(1.0, 0.824, 0.118), Color(0.545, 0.361, 0.839)]
	var card := Button.new()
	card.custom_minimum_size = Vector2(280, 280)
	card.text = "🍖\n%s" % names[ing]
	card.add_theme_font_size_override("font_size", 40)
	card.modulate = colors[ing]
	card.pressed.connect(func(): App.instance.on_show_char_select())
	left.add_child(card)
	var hint := UiKit.make_label("点击更换食材（本地偏好，进房自动带）", 16, Color(0.8, 0.7, 0.55))
	left.add_child(hint)

	# 中央主按钮区（中偏右）
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.position = Vector2(120, -120)
	center.add_theme_constant_override("separation", 20)
	add_child(center)
	var big := UiKit.make_button("开锅！", Vector2(520, 120))
	big.add_theme_font_size_override("font_size", 44)
	big.pressed.connect(func(): App.instance.on_quick_match())
	center.add_child(big)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	center.add_child(row)
	var friend := UiKit.make_button("和朋友炖", Vector2(250, 72))
	friend.pressed.connect(func(): App.instance.on_create_room())
	row.add_child(friend)
	var join := UiKit.make_button("输入房间码", Vector2(250, 72))
	join.pressed.connect(_on_join_click)
	row.add_child(join)
	var solo := UiKit.make_button("单机试玩（P0）", Vector2(520, 64))
	solo.pressed.connect(func(): App.instance.on_solo_play())
	center.add_child(solo)

	# 房间码输入（点击「输入房间码」后弹出）
	_room_input = LineEdit.new()
	_room_input.placeholder_text = "4 位房间码（A-Z0-9，自动大写）"
	_room_input.max_length = 4
	_room_input.custom_minimum_size = Vector2(300, 56)
	_room_input.add_theme_font_size_override("font_size", 28)
	_room_input.text_changed.connect(func(t: String): _room_input.text = t.to_upper())
	_room_input.visible = false
	_room_input.text_submitted.connect(_on_room_submitted)
	add_child(_room_input)

	# 底部：三操作提示（G0001M01F02：三个操作，一局学会）
	var tip := UiKit.make_label("左摇杆外圈移动 · 内圈长按扩张 · 右摇杆方向挥击", 20, Color(0.85, 0.75, 0.6))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tip.position = Vector2(0, -60)
	add_child(tip)


func _on_join_click() -> void:
	_room_input.visible = not _room_input.visible
	if _room_input.visible:
		_room_input.grab_focus()


func _on_room_submitted(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() == 4:
		_room_input.visible = false
		App.instance.on_join_room(code)
