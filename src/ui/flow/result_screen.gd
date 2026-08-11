## result_screen.gd — 结算（A0001M13F07，G0001M07）
## 排名只看地盘面积，击杀只展示不参与排名（「击杀（不计分）」列头明写）。
## 若 65% 提前结束改文案「一锅端了！」。
##
## 视觉（本页是门面）：暗化厨房背景 + 领奖台式奶油行卡：奖牌 🥇🥈🥉 + 色样 + 名字 +
## 面积横条（按玩家色染色，入场从 0 长到终值）+ 击杀数；冠军行金边加大。
## 入场动画：行卡右侧滑入 + 淡入，逐行错峰（create_tween，等两帧排版后再取终点坐标）。
##
## 布局全部走容器 + size_flags（同 main_menu.gd）——
## 原来是 anchor preset + 手填 position 偏移（-420/-200 那套），换分辨率就散架。
## 行数也不再假定 4 人：人机练习可以是 2/3/4 人局。

extends Control

## 各列固定宽度：表头和数据行用同一组值，容器自己撑高撑宽，
## 靠这个对齐而不是靠算像素坐标。
const COL_RANK := 100
const COL_NAME := 260
const COL_AREA := 150
const COL_BAR := 360
const COL_KILL := 190

var result: Dictionary = {}

var _rows: Array = []   # {row: Control, bar: ProgressBar, target: int}


func _ready() -> void:
	UiKit.kitchen_bg(self, 0.25)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	margin.add_child(root)

	# ── 顶部：大标题横幅 ─────────────────────────────────────────────────
	var early_win := _is_early_win()
	var title := UiKit.make_title("一锅端了！" if early_win else "炖好了！", 76)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(title)
	var sub := UiKit.make_title("排名只看地盘面积", 24, UiKit.YELLOW)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(sub)

	# ── 主区：成绩表（水平居中，垂直吃掉剩余空间）─────────────────────────
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left_gap := Control.new()
	left_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left_gap)

	var table := VBoxContainer.new()
	table.alignment = BoxContainer.ALIGNMENT_CENTER
	table.add_theme_constant_override("separation", 14)
	body.add_child(table)

	var right_gap := Control.new()
	right_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right_gap)

	# 列头（左右缩进对齐行卡内边距）
	var head_pad := MarginContainer.new()
	head_pad.add_theme_constant_override("margin_left", 22)
	head_pad.add_theme_constant_override("margin_right", 22)
	table.add_child(head_pad)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	head.add_child(_head_cell("名次", COL_RANK))
	head.add_child(_head_cell("玩家", COL_NAME))
	head.add_child(_head_cell("最终面积 %", COL_AREA))
	head.add_child(_head_cell("", COL_BAR))
	head.add_child(_head_cell("击杀（不计分）", COL_KILL))
	head_pad.add_child(head)

	var players: Array = result.get("players", [])
	players.sort_custom(func(a, b): return a.rank < b.rank)
	_rows.clear()
	for p in players:
		table.add_child(_make_row(p))

	# ── 底部：再来一锅（主） ⟷ 返回（次）──────────────────────────────────
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 32)
	bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(bottom)
	var again := UiKit.make_button("再来一锅", Vector2(380, 92), UiKit.Btn.SUCCESS, 34)
	again.pressed.connect(_on_again)
	bottom.add_child(again)
	var back := UiKit.make_button("返回", Vector2(260, 92))
	back.pressed.connect(_on_back)
	bottom.add_child(back)

	_animate_in.call_deferred()


## 一行成绩 = 奶油行卡：奖牌 | 色样+名字 | 面积% | 染色横条 | 击杀。冠军金边加大。
func _make_row(p: Dictionary) -> PanelContainer:
	var winner: bool = p.rank == 1
	var pcol := _color_of(p.player_id)
	var panel := PanelContainer.new()
	if winner:
		panel.add_theme_stylebox_override("panel", UiKit.sb(UiKit.CREAM, UiKit.YELLOW, 6, 20, 10))
	else:
		panel.add_theme_stylebox_override("panel", UiKit.sb(UiKit.CREAM, UiKit.WOOD, 3, 20, 6))
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16 if winner else 12)
	panel.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	pad.add_child(row)

	var medal_text := "%d" % p.rank
	match int(p.rank):
		1: medal_text = "🥇"
		2: medal_text = "🥈"
		3: medal_text = "🥉"
	var medal := UiKit.make_label(medal_text, 40 if winner else 34)
	medal.custom_minimum_size = Vector2(COL_RANK, 0)
	medal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(medal)

	var name_cell := HBoxContainer.new()
	name_cell.custom_minimum_size = Vector2(COL_NAME, 0)
	name_cell.add_theme_constant_override("separation", 12)
	row.add_child(name_cell)
	var swatch := UiKit.icon_swatch(pcol, 44 if winner else 38)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_cell.add_child(swatch)
	var name_text := _name_of(p.player_id)
	if winner:
		name_text = "👑 " + name_text
	var name_l := UiKit.make_label(name_text, 32 if winner else 27, _dark_of(p.player_id))
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_cell.add_child(name_l)

	var area_l := UiKit.make_label("%.1f%%" % (p.area_permyriad / 100.0), 30 if winner else 26)
	area_l.custom_minimum_size = Vector2(COL_AREA, 0)
	area_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	area_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(area_l)

	# 面积横条（入场动画：从 0 长到终值，按玩家色染色）
	var bar := ProgressBar.new()
	bar.max_value = 10000
	bar.value = 0
	bar.custom_minimum_size = Vector2(COL_BAR, 30)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UiKit.sb(Color(0.3, 0.18, 0.1, 0.22), Color.TRANSPARENT, 0, 10))
	bar.add_theme_stylebox_override("fill", _fill_style(pcol))
	row.add_child(bar)

	var kill_l := UiKit.make_label("%d" % p.kills, 26, UiKit.INK_SOFT)
	kill_l.custom_minimum_size = Vector2(COL_KILL, 0)
	kill_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(kill_l)

	panel.modulate.a = 0.0   # 入场前隐身，_animate_in 逐行点亮
	_rows.append({"row": panel, "bar": bar, "target": int(p.area_permyriad)})
	return panel


## 入场：等两帧让容器排完版（终点坐标才可信），然后逐行错峰滑入 + 淡入 + 长条。
func _animate_in() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for i in range(_rows.size()):
		var e: Dictionary = _rows[i]
		var row: Control = e.row
		var delay := 0.12 * i
		var end_x: float = row.position.x
		row.position.x = end_x + 64.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(row, "modulate:a", 1.0, 0.28).set_delay(delay)
		tw.tween_property(row, "position:x", end_x, 0.4) \
			.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(e.bar, "value", float(e.target), 0.9) \
			.set_delay(delay + 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _head_cell(text: String, width: int) -> Label:
	var l := UiKit.make_label(text, 20, Color(1.0, 0.95, 0.85, 0.9))
	l.custom_minimum_size = Vector2(width, 0)
	return l


## 「再来一锅」原来走 on_quick_match（联机），现在联机连不上 ——
## 直接用上一局的 Bot 数量重开一局人机，别把人扔进连不上的匹配。
func _on_again() -> void:
	App.instance.on_solo_play(App.instance.bot_count_pref)


func _on_back() -> void:
	App.instance.on_back_to_menu()


func _is_early_win() -> bool:
	for p in result.get("players", []):
		if p.area_permyriad >= 6500:   # KNOB_early_win_ratio = 65%
			return true
	return false


func _name_of(pid: int) -> String:
	if pid >= 1 and pid <= 4:
		return UiKit.INGREDIENT_NAMES[pid - 1]
	return "玩家%d" % pid


func _color_of(pid: int) -> Color:
	if pid >= 1 and pid <= 4:
		return UiKit.P_COLORS[pid - 1]
	return Color.WHITE


## 名字用深色变体：奶油底上原亮色（玉米黄尤甚）对比度不够
func _dark_of(pid: int) -> Color:
	if pid >= 1 and pid <= 4:
		return UiKit.P_DARKS[pid - 1]
	return UiKit.INK


func _fill_style(c: Color) -> StyleBoxFlat:
	return UiKit.sb(c, c.darkened(0.3), 2, 10)
