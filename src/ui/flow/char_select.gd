## char_select.gd — 角色选择（A0001M13F03）
## 四食材横排大卡：排骨/紫菜/玉米/茄子；卡内立绘+名字+地盘色样块。
## 「外观不同，实力一样」无差异声明。主菜单选择是本地偏好（T0005M14F03-4）。

extends Control

const NAMES := ["排骨", "紫菜", "玉米", "茄子"]
const COLORS := [Color(0.949, 0.565, 0.608), Color(0.18, 0.604, 0.525),
	Color(1.0, 0.824, 0.118), Color(0.545, 0.361, 0.839)]
const ICONS := ["🍖", "🥬", "🌽", "🍆"]

var selected: int = App.instance.ingredient_pref if App.instance != null else 0


func _ready() -> void:
	UiKit.full_rect_bg(self, Color(0.16, 0.11, 0.08))
	var title := UiKit.make_label("选个食材下锅", 48, Color(0.95, 0.85, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position = Vector2(0, 60)
	add_child(title)
	var note := UiKit.make_label("外观不同，实力一样", 20, Color(0.85, 0.75, 0.6))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.set_anchors_preset(Control.PRESET_TOP_WIDE)
	note.position = Vector2(0, 130)
	add_child(note)

	var cards := HBoxContainer.new()
	cards.set_anchors_preset(Control.PRESET_CENTER)
	cards.position = Vector2(-520, -160)
	cards.add_theme_constant_override("separation", 24)
	add_child(cards)
	for i in range(4):
		var idx := i
		var card := Button.new()
		card.custom_minimum_size = Vector2(240, 300)
		card.text = "%s\n%s" % [ICONS[idx], NAMES[idx]]
		card.add_theme_font_size_override("font_size", 34)
		card.modulate = COLORS[idx]
		card.pressed.connect(func(): _select(idx))
		cards.add_child(card)
		# 地盘色样块
		var swatch := ColorRect.new()
		swatch.color = COLORS[idx]
		swatch.custom_minimum_size = Vector2(240, 12)
		cards.add_child(swatch)

	var confirm := UiKit.make_button("就它了", Vector2(360, 80))
	confirm.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	confirm.position = Vector2(-400, -80)
	confirm.pressed.connect(_confirm)
	add_child(confirm)
	_rebuild_cards()


func _select(idx: int) -> void:
	selected = idx
	_rebuild_cards()


func _rebuild_cards() -> void:
	pass   # 选中态由 modulate 表现（保持简单占位）


func _confirm() -> void:
	App.instance.on_select_ingredient(selected)
	App.instance.on_back_to_menu()
