## char_select.gd — 角色选择（A0001M13F03）
## 四食材横排大卡：番茄/青菜/玉米/紫芋（配色/名字统一走 UiKit，与地盘 shader 一致）。
## 「外观不同，实力一样」无差异声明。主菜单选择是本地偏好（T0005M14F03-4）。
## 视觉：奶油大卡 + 色样圆 + 名字；选中卡放大 1.06 并换橙色描边，悬停走 UiKit.bounce。

extends Control

const ICONS := ["🍅", "🥬", "🌽", "🍠"]
const CARD_SIZE := Vector2(250, 340)

var selected: int = App.instance.ingredient_pref if App.instance != null else 0
## 从人机练习房进来时置 true：确认后回房而不是回主菜单（否则改个食材要重走一遍菜单）
var return_to_practice: bool = false

var _card_wraps: Array = []
var _card_btns: Array = []


func _ready() -> void:
	UiKit.kitchen_bg(self)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	add_child(margin)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 28)
	margin.add_child(root)

	var title := UiKit.make_title("选个食材下锅", 60)
	root.add_child(title)
	var note := UiKit.make_title("外观不同，实力一样", 24, UiKit.YELLOW)
	root.add_child(note)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 32)
	root.add_child(cards)
	_card_wraps.clear()
	_card_btns.clear()
	for i in range(4):
		var idx := i
		# 外层 wrapper 承接「选中放大」，内层按钮承接 UiKit.bounce 悬停——
		# 两层各管各的 scale，互不打架。
		var wrap := Control.new()
		wrap.custom_minimum_size = CARD_SIZE
		wrap.resized.connect(func() -> void: wrap.pivot_offset = wrap.size / 2.0)
		cards.add_child(wrap)
		var btn := Button.new()
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(func(): _select(idx))
		UiKit.bounce(btn)
		wrap.add_child(btn)
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 12)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(vb)
		var icon := UiKit.make_label(ICONS[idx], 84)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(icon)
		var name_l := UiKit.make_label(UiKit.INGREDIENT_NAMES[idx], 34, UiKit.P_DARKS[idx])
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(name_l)
		var swatch := UiKit.icon_swatch(UiKit.P_COLORS[idx], 52)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(swatch)
		_card_wraps.append(wrap)
		_card_btns.append(btn)

	var confirm := UiKit.make_button("就它了", Vector2(380, 92), UiKit.Btn.SUCCESS, 34)
	confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm.pressed.connect(_confirm)
	root.add_child(confirm)
	_refresh_cards()


func _select(idx: int) -> void:
	selected = idx
	_refresh_cards()


## 选中态：橙描边 + 放大 1.06；未选中回奶油描边、还原大小。
func _refresh_cards() -> void:
	for i in range(_card_btns.size()):
		var btn: Button = _card_btns[i]
		var wrap: Control = _card_wraps[i]
		var chosen := i == selected
		var border := UiKit.ORANGE if chosen else UiKit.WOOD
		var bw := 6 if chosen else 4
		btn.add_theme_stylebox_override("normal", UiKit.sb(UiKit.CREAM, border, bw, 24, 10 if chosen else 8))
		btn.add_theme_stylebox_override("hover", UiKit.sb(Color("fffbef"), border, bw, 24, 10))
		btn.add_theme_stylebox_override("pressed", UiKit.sb(UiKit.CREAM_DARK, border, bw, 24, 2))
		var target := Vector2(1.06, 1.06) if chosen else Vector2.ONE
		if wrap.is_inside_tree():
			var tw := wrap.create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(wrap, "scale", target, 0.18)
		else:
			wrap.scale = target


func _confirm() -> void:
	App.instance.on_select_ingredient(selected)
	if return_to_practice:
		App.instance.on_practice_room()
	else:
		App.instance.on_back_to_menu()
