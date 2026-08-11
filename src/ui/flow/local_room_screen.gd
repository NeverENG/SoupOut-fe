## local_room_screen.gd — 人机练习房（本地，零网络）
## 从主菜单「人机练习」进入：选 Bot 数量（1/2/3 → 2/3/4 人局）、确认自己的食材、开锅。
## 与 room_screen.gd（联机 0x017 RoomState）不是一回事：这里没有房间码、没有准备勾、没有别的真人。
##
## 布局全部走容器 + size_flags（同 main_menu.gd）——
## 不用「anchor preset + 手填 position 偏移」，那套换分辨率就散架。
## 视觉：厨房背景 + 左右两张奶油卡；Bot 数量 = 三颗切换钮，选中的换 PRIMARY 橙。

extends Control

const ING_ICONS := ["🍅", "🥬", "🌽", "🍠"]

var bot_count: int = 3

var _bot_buttons: Array = []
var _roster_box: VBoxContainer = null
var _summary: Label = null


func _ready() -> void:
	UiKit.kitchen_bg(self)
	if App.instance != null:
		bot_count = clampi(App.instance.bot_count_pref, 1, 3)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	margin.add_child(root)

	# ── 顶栏：标题（左） ⟷ 返回（右）────────────────────────────────────────
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := UiKit.make_title("🍲 人机练习", 52)
	top.add_child(title)
	var top_gap := Control.new()
	top_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(top_gap)
	var back := UiKit.make_button("返回", Vector2(180, 64))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_on_back)
	top.add_child(back)

	# ── 主区：我的食材卡（左） ⟷ Bot 数量 + 名单卡（右）───────────────────────
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 64)
	root.add_child(body)

	# 左：自己的食材（读 App.instance.ingredient_pref，点一下可以去换）
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 14)
	body.add_child(left)
	var mine := UiKit.make_title("我的食材", 24)
	left.add_child(mine)
	var ing: int = _my_ingredient()
	var card := Button.new()
	card.custom_minimum_size = Vector2(320, 340)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("normal", UiKit.sb(UiKit.CREAM, UiKit.WOOD, 4, 24, 8))
	card.add_theme_stylebox_override("hover", UiKit.sb(Color("fffbef"), UiKit.WOOD, 4, 24, 10))
	card.add_theme_stylebox_override("pressed", UiKit.sb(UiKit.CREAM_DARK, UiKit.WOOD, 4, 24, 2))
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.pressed.connect(_on_change_ingredient)
	UiKit.bounce(card)
	left.add_child(card)
	var cv := VBoxContainer.new()
	cv.set_anchors_preset(Control.PRESET_FULL_RECT)
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 10)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cv)
	var big_icon := UiKit.make_label(ING_ICONS[ing], 96)
	big_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(big_icon)
	var ing_name := UiKit.make_label(UiKit.INGREDIENT_NAMES[ing], 36, UiKit.P_DARKS[ing])
	ing_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(ing_name)
	var nick := UiKit.make_label(SettingsDb.get_string("nickname", "食材"), 24, UiKit.INK_SOFT)
	nick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(nick)
	var swap_hint := UiKit.make_title("点击更换食材", 18)
	left.add_child(swap_hint)

	var mid_gap := Control.new()
	mid_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mid_gap)

	# 右：Bot 数量选择 + 本局名单，装进一张奶油卡
	var right_card := UiKit.make_panel()
	right_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(right_card)
	var right_pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		right_pad.add_theme_constant_override("margin_" + side, 32)
	right_card.add_child(right_pad)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 16)
	right_pad.add_child(right)

	var pick := UiKit.make_label("几个 Bot 陪你？", 30)
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(pick)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	right.add_child(btn_row)
	_bot_buttons.clear()
	for n in range(1, 4):
		var count: int = n
		var b := UiKit.make_button("%d 个" % count, Vector2(168, 96), UiKit.Btn.DEFAULT, 32)
		b.pressed.connect(func(): _set_bot_count(count))
		btn_row.add_child(b)
		_bot_buttons.append(b)

	_summary = UiKit.make_label("", 22, UiKit.INK_SOFT)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(_summary)

	_roster_box = VBoxContainer.new()
	_roster_box.custom_minimum_size = Vector2(460, 0)
	_roster_box.add_theme_constant_override("separation", 8)
	right.add_child(_roster_box)

	var start := UiKit.make_button("开锅", Vector2(560, 112), UiKit.Btn.SUCCESS, 44)
	start.pressed.connect(_on_start)
	right.add_child(start)

	# ── 底部：操作提示（和主菜单同一行文案，进局前最后一次露出）──────────────
	var tip := UiKit.make_title("摇杆移动 · 万能键：短按翻窗/推板/挥击，长按铺汤", 22)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(tip)

	_refresh()


func _my_ingredient() -> int:
	if App.instance == null:
		return 0
	var idx: int = App.instance.ingredient_pref
	return clampi(idx, 0, 3)


func _set_bot_count(n: int) -> void:
	bot_count = clampi(n, 1, 3)
	# 立刻写回 App：否则「点卡片换食材」再回来时 _ready 又从 bot_count_pref 读，
	# 玩家刚选的 1 个 Bot 会被悄悄重置回 3 个。
	if App.instance != null:
		App.instance.bot_count_pref = bot_count
	_refresh()


## 选中态 + 本局名单。名单跟着 Bot 数量变，玩家点之前就知道自己进的是几人局。
func _refresh() -> void:
	for i in range(_bot_buttons.size()):
		_apply_bot_style(_bot_buttons[i], (i + 1) == bot_count)
	_summary.text = "本局 %d 人：你 + %d 个 Bot" % [1 + bot_count, bot_count]
	if _roster_box != null:
		for child in _roster_box.get_children():
			child.queue_free()
		var me_ing := _my_ingredient()
		_roster_box.add_child(_roster_row("%s（你）" % SettingsDb.get_string("nickname", "食材"), me_ing))
		for k in range(1, bot_count + 1):
			_roster_box.add_child(_roster_row("Bot%d" % k, k))


## 切换钮：选中 = PRIMARY 橙立体面，未选中撤掉覆盖、回主题奶油默认。
func _apply_bot_style(b: Button, chosen: bool) -> void:
	if chosen:
		b.add_theme_stylebox_override("normal", UiKit.sb_chunky(UiKit.ORANGE, UiKit.ORANGE_DARK))
		b.add_theme_stylebox_override("hover", UiKit.sb_chunky(UiKit.ORANGE.lightened(0.08), UiKit.ORANGE_DARK))
		b.add_theme_stylebox_override("pressed", UiKit.sb_chunky(UiKit.ORANGE.darkened(0.08), UiKit.ORANGE_DARK))
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", UiKit.ORANGE_DARK.darkened(0.2))
		b.add_theme_constant_override("outline_size", 4)
	else:
		b.remove_theme_stylebox_override("normal")
		b.remove_theme_stylebox_override("hover")
		b.remove_theme_stylebox_override("pressed")
		b.remove_theme_color_override("font_color")
		b.remove_theme_color_override("font_hover_color")
		b.remove_theme_color_override("font_pressed_color")
		b.remove_theme_color_override("font_outline_color")
		b.remove_theme_constant_override("outline_size")


func _roster_row(label_text: String, ing: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var swatch := UiKit.icon_swatch(UiKit.P_COLORS[clampi(ing, 0, 3)], 28)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var l := UiKit.make_label("%s  %s" % [ING_ICONS[clampi(ing, 0, 3)], label_text], 22)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return row


func _on_change_ingredient() -> void:
	App.instance.on_show_char_select(true)


func _on_start() -> void:
	App.instance.on_solo_play(bot_count)


func _on_back() -> void:
	App.instance.on_back_to_menu()
