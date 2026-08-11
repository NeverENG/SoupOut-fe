## self_status.gd — 自身状态区（A0001M11F05，3D 版：底部中偏左奶油纸片）
## ❤ HP 条（低于 30% 变深红）+ 体型徽章（轻/中/重文字牌 + 图标，升档放大回弹，M04F05）
## 对外契约不变：setup(battle) / update_status(hp, area_permyriad)；档位仍走 Sim.mass_tier。

class_name SelfStatus
extends Control

const TIER_ICONS := ["🪶", "🥄", "🍳"]    # 轻/中/重（羽毛/汤勺/铁锅占位）
const TIER_NAMES := ["轻", "中", "重"]
const HP_W := 168.0

var battle: Node = null
var _hp_fill: Panel = null
var _badge: Label = null
var _badge_panel: PanelContainer = null
var _pct: Label = null
var _last_tier := -1
var _hp_low := false
var _sb_hp_ok: StyleBoxFlat = null
var _sb_hp_low: StyleBoxFlat = null


func setup(p_battle: Node) -> void:
	battle = p_battle
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 底部中偏左锚定（拇指禁区之外），任意分辨率成立
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -340.0
	offset_right = -30.0
	offset_top = -86.0
	offset_bottom = -26.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	# 奶油卡片
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_sb := UiKit.sb(
		Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.92), UiKit.WOOD, 3, 18, 5)
	card_sb.content_margin_left = 16.0
	card_sb.content_margin_right = 16.0
	card_sb.content_margin_top = 6.0
	card_sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", card_sb)
	add_child(card)
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hbox)
	# ❤ + HP 槽
	hbox.add_child(UiKit.make_label("❤", 22, UiKit.RED))
	var hp_slot := Control.new()
	hp_slot.custom_minimum_size = Vector2(HP_W + 4.0, 18.0)
	hp_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hp_bg := Panel.new()
	hp_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_bg.add_theme_stylebox_override("panel",
		UiKit.sb(Color(0.24, 0.13, 0.07, 0.45), Color.TRANSPARENT, 0, 9))
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_slot.add_child(hp_bg)
	_sb_hp_ok = UiKit.sb(Color(0.90, 0.36, 0.30), Color.TRANSPARENT, 0, 7)
	_sb_hp_low = UiKit.sb(Color(0.9, 0.25, 0.2), Color.TRANSPARENT, 0, 7)
	_hp_fill = Panel.new()
	_hp_fill.position = Vector2(2, 2)
	_hp_fill.size = Vector2(HP_W, 14)
	_hp_fill.add_theme_stylebox_override("panel", _sb_hp_ok)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_slot.add_child(_hp_fill)
	hbox.add_child(hp_slot)
	# 体型徽章（升档放大回弹）
	_badge_panel = PanelContainer.new()
	_badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_panel.add_theme_stylebox_override("panel", _tier_sb(0))
	_badge = UiKit.make_label("%s %s" % [TIER_ICONS[0], TIER_NAMES[0]], 22)
	_badge_panel.add_child(_badge)
	hbox.add_child(_badge_panel)
	_pct = UiKit.make_label("10%", 18, UiKit.INK_SOFT)
	hbox.add_child(_pct)


func _tier_sb(tier: int) -> StyleBoxFlat:
	var bg := [UiKit.GREEN, UiKit.YELLOW, UiKit.ORANGE][clampi(tier, 0, 2)] as Color
	var dark := [UiKit.GREEN_DARK, UiKit.YELLOW_DARK, UiKit.ORANGE_DARK][clampi(tier, 0, 2)] as Color
	var s := UiKit.sb(bg, dark, 2, 12)
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 2.0
	s.content_margin_bottom = 4.0
	return s


func update_status(hp: int, area_permyriad: int) -> void:
	var frac := clampf(hp / 100.0, 0.0, 1.0)
	_hp_fill.size = Vector2(maxf(0.0, HP_W * frac), 14.0)
	var low := frac <= 0.3
	if low != _hp_low:
		_hp_low = low
		_hp_fill.add_theme_stylebox_override("panel", _sb_hp_low if low else _sb_hp_ok)
	var tier := Sim.mass_tier(area_permyriad, 3500)
	_badge.text = "%s %s" % [TIER_ICONS[tier], TIER_NAMES[tier]]
	_pct.text = "%d%%" % (area_permyriad / 100)
	if tier != _last_tier:
		_last_tier = tier
		_badge_panel.add_theme_stylebox_override("panel", _tier_sb(tier))
		_badge_panel.pivot_offset = _badge_panel.size / 2.0
		var tween := create_tween()
		tween.tween_property(_badge_panel, "scale", Vector2(1.5, 1.5), 0.1)
		tween.tween_property(_badge_panel, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
