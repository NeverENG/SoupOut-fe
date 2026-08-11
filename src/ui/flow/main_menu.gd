## main_menu.gd — 主菜单（A0001M13F02）
## 人机练习（本地，主入口）· 开锅！（QuickMatch）· 和朋友炖（CreateRoom）· 输入房间码（JoinRoom）
## 左：当前所选食材大卡（点击换）；右：按钮组；右上：昵称+齿轮；底部：三操作提示。
## 不做：商店/任务/赛季/公告墙/抽卡（A0001M13F02 明确）。
## 视觉：UiKit 厨房背景 + 奶油卡片；联机三条未接服务端，降为 GHOST 半透明并明标「开发中」。

extends Control

var _room_input: LineEdit = null


## 布局全部走容器 + size_flags，不用「anchor preset + 手填 position 偏移」——
## 后者在任何非 1920×1080 的分辨率下都会散架，之前元素挤成一坨就是这么来的。
func _ready() -> void:
	UiKit.kitchen_bg(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	margin.add_child(root)

	# ── 顶栏：标题（左） ⟷ 昵称牌 + 齿轮（右）──────────────────────────────
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := UiKit.make_title("🍲 一锅好汤", 56)
	top.add_child(title)
	var top_gap := Control.new()
	top_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(top_gap)

	var ing: int = App.instance.ingredient_pref
	var name_card := UiKit.make_panel()
	name_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(name_card)
	var name_pad := MarginContainer.new()
	for side in ["left", "right"]:
		name_pad.add_theme_constant_override("margin_" + side, 16)
	for side in ["top", "bottom"]:
		name_pad.add_theme_constant_override("margin_" + side, 8)
	name_card.add_child(name_pad)
	var name_box := HBoxContainer.new()
	name_box.add_theme_constant_override("separation", 12)
	name_pad.add_child(name_box)
	var chip := UiKit.icon_swatch(UiKit.P_COLORS[ing], 32)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_box.add_child(chip)
	var nick := UiKit.make_label(SettingsDb.get_string("nickname", "食材"), 26)
	nick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_box.add_child(nick)
	var gear := UiKit.make_button("⚙", Vector2(72, 60))
	gear.pressed.connect(func(): App.instance.on_show_settings())
	name_box.add_child(gear)

	# ── 主区：食材卡（左） ⟷ 按钮卡（右），两边各自垂直居中 ─────────────
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 64)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 14)
	body.add_child(left)
	var icons := ["🍅", "🥬", "🌽", "🍠"]
	var card := _card_button(Vector2(360, 380))
	card.pressed.connect(func(): App.instance.on_show_char_select())
	left.add_child(card)
	var cv := VBoxContainer.new()
	cv.set_anchors_preset(Control.PRESET_FULL_RECT)
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 10)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cv)
	var big_icon := UiKit.make_label(icons[ing], 110)
	big_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(big_icon)
	var ing_name := UiKit.make_label(UiKit.INGREDIENT_NAMES[ing], 40, UiKit.P_DARKS[ing])
	ing_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(ing_name)
	var swatch := UiKit.icon_swatch(UiKit.P_COLORS[ing], 40)
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(swatch)
	var hint := UiKit.make_title("点击更换食材（本地偏好，进房自动带）", 18)
	left.add_child(hint)

	var mid_gap := Control.new()
	mid_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mid_gap)

	var right_card := UiKit.make_panel()
	right_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(right_card)
	var right_pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		right_pad.add_theme_constant_override("margin_" + side, 32)
	right_card.add_child(right_pad)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 18)
	right_pad.add_child(right)
	# 主按钮 = 人机练习。联机三条现在连不上服务端，点进去只会卡在匹配中，
	# 所以把唯一真能玩的入口放大，联机降为次级并明标「开发中」。
	var big := UiKit.make_button("人机练习", Vector2(560, 128), UiKit.Btn.SUCCESS, 48)
	big.pressed.connect(func(): App.instance.on_practice_room())
	right.add_child(big)
	var big_hint := UiKit.make_label("和 1~3 个 Bot 打一局 · 立刻开锅", 20, UiKit.INK_SOFT)
	big_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(big_hint)

	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", UiKit.sb(Color(0.55, 0.38, 0.22, 0.25), Color.TRANSPARENT, 0, 2))
	right.add_child(sep)

	var online_head := UiKit.make_label("联机（开发中）", 18, Color(0.55, 0.45, 0.36, 0.85))
	online_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(online_head)
	var quick := UiKit.make_button("开锅！（开发中）", Vector2(560, 68), UiKit.Btn.GHOST, 24)
	quick.pressed.connect(func(): App.instance.on_quick_match())
	right.add_child(quick)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	right.add_child(row)
	var friend := UiKit.make_button("和朋友炖（开发中）", Vector2(272, 64), UiKit.Btn.GHOST, 20)
	friend.pressed.connect(func(): App.instance.on_create_room())
	row.add_child(friend)
	var join := UiKit.make_button("输入房间码（开发中）", Vector2(272, 64), UiKit.Btn.GHOST, 20)
	join.pressed.connect(_on_join_click)
	row.add_child(join)

	# 房间码输入（点击「输入房间码」后就地展开，不再是浮在角落的孤儿控件）
	_room_input = LineEdit.new()
	_room_input.placeholder_text = "4 位房间码（A-Z0-9，自动大写）"
	_room_input.max_length = 4
	_room_input.custom_minimum_size = Vector2(560, 60)
	_room_input.add_theme_font_size_override("font_size", 28)
	_room_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_input.text_changed.connect(func(t: String): _room_input.text = t.to_upper())
	_room_input.visible = false
	_room_input.text_submitted.connect(_on_room_submitted)
	right.add_child(_room_input)

	# ── 底部：三操作提示（G0001M01F02：三个操作，一局学会）────────────────
	var tip := UiKit.make_title("摇杆移动 · 万能键：短按翻窗/推板/挥击，长按铺汤", 22)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(tip)


## 奶油卡片感的可点大按钮（食材立绘卡）：面板质感 + UiKit 弹性手感
func _card_button(min_size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", UiKit.sb(UiKit.CREAM, UiKit.WOOD, 4, 24, 8))
	b.add_theme_stylebox_override("hover", UiKit.sb(Color("fffbef"), UiKit.WOOD, 4, 24, 10))
	b.add_theme_stylebox_override("pressed", UiKit.sb(UiKit.CREAM_DARK, UiKit.WOOD, 4, 24, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UiKit.bounce(b)
	return b


func _on_join_click() -> void:
	_room_input.visible = not _room_input.visible
	if _room_input.visible:
		_room_input.grab_focus()


func _on_room_submitted(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() == 4:
		_room_input.visible = false
		App.instance.on_join_room(code)
