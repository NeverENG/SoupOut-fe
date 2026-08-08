## result_screen.gd — 结算（A0001M13F07，G0001M07）
## 排名只看地盘面积，击杀只展示不参与排名（「击杀（不计分）」列头明写）。
## 入场动画：四条面积横条从 0 长到终值。若 65% 提前结束改文案「一锅端了！」。

extends Control

var result: Dictionary = {}


func _ready() -> void:
	UiKit.full_rect_bg(self, Color(0.14, 0.10, 0.08))
	var early_win := _is_early_win()
	var title := UiKit.make_label("一锅端了！" if early_win else "炖好了！", 64, Color(0.95, 0.85, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position = Vector2(0, 60)
	add_child(title)

	var players: Array = result.get("players", [])
	players.sort_custom(func(a, b): return a.rank < b.rank)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.position = Vector2(-420, -200)
	center.add_theme_constant_override("separation", 20)
	add_child(center)

	# 列头
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 40)
	head.add_child(UiKit.make_label("名次", 20, Color(0.8, 0.7, 0.55)))
	head.add_child(UiKit.make_label("玩家", 20, Color(0.8, 0.7, 0.55)))
	head.add_child(UiKit.make_label("最终面积 %", 20, Color(0.8, 0.7, 0.55)))
	head.add_child(UiKit.make_label("击杀（不计分）", 20, Color(0.8, 0.7, 0.55)))
	center.add_child(head)

	for p in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 40)
		var rank := UiKit.make_label("%d" % p.rank, 30)
		if p.rank == 1:
			rank.text = "👑 1"
		row.add_child(rank)
		row.add_child(UiKit.make_label(_name_of(p.player_id), 26))
		row.add_child(UiKit.make_label("%.1f%%" % (p.area_permyriad / 100.0), 26))
		row.add_child(UiKit.make_label("%d" % p.kills, 24, Color(0.7, 0.65, 0.55)))
		# 面积横条（入场动画：从 0 长到终值）
		var bar := ProgressBar.new()
		bar.max_value = 10000
		bar.value = 0
		bar.custom_minimum_size = Vector2(300, 26)
		bar.show_percentage = false
		bar.add_theme_stylebox_override("fill", _fill_style(_color_of(p.player_id)))
		row.add_child(bar)
		center.add_child(row)
		var tween := create_tween()
		tween.tween_property(bar, "value", float(p.area_permyriad), 1.0)

	var again := UiKit.make_button("再来一锅", Vector2(340, 76))
	again.set_anchors_preset(Control.PRESET_BOTTOM_CENTER)
	again.position = Vector2(-360, -80)
	again.pressed.connect(func(): App.instance.on_quick_match())
	add_child(again)
	var back := UiKit.make_button("返回", Vector2(300, 76))
	back.set_anchors_preset(Control.PRESET_BOTTOM_CENTER)
	back.position = Vector2(20, -80)
	back.pressed.connect(func(): App.instance.on_back_to_menu())
	add_child(back)


func _is_early_win() -> bool:
	for p in result.get("players", []):
		if p.area_permyriad >= 6500:   # KNOB_early_win_ratio = 65%
			return true
	return false


func _name_of(pid: int) -> String:
	var names := {1: "排骨", 2: "紫菜", 3: "玉米", 4: "茄子"}
	return names.get(pid, "玩家%d" % pid)


func _color_of(pid: int) -> Color:
	match pid:
		1: return Color(0.949, 0.565, 0.608)
		2: return Color(0.18, 0.604, 0.525)
		3: return Color(1.0, 0.824, 0.118)
		4: return Color(0.545, 0.361, 0.839)
	return Color.WHITE


func _fill_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(4)
	return s
