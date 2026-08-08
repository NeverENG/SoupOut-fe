## self_status.gd — 自身状态区（A0001M11F05，左摇杆正上方、拇指禁区之上）
## HP 条（受击白闪 + 左抖）+ 质量徽章（轻=羽毛/中=汤勺/重=铁锅，旁写面积 %）
## 档位切换：升档瞬间徽章放大回弹 + 头顶飘字（重装负面可读性主载体，M04F05）。

class_name SelfStatus
extends Control

var battle: Node = null
var _hp_fill: ColorRect = null
var _hp_frame: ColorRect = null
var _badge: Label = null
var _last_tier := -1


func setup(p_battle: Node) -> void:
	battle = p_battle
	# 位置：左下摇杆上方（拇指禁区之上）
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	position = Vector2(40, 780)
	custom_minimum_size = Vector2(360, 80)
	_hp_frame = ColorRect.new()
	_hp_frame.color = Color(0.1, 0.07, 0.05, 0.8)
	_hp_frame.position = Vector2(0, 0)
	_hp_frame.size = Vector2(300, 24)
	add_child(_hp_frame)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.85, 0.35, 0.3)
	_hp_fill.position = Vector2(2, 2)
	_hp_fill.size = Vector2(296, 20)
	add_child(_hp_fill)
	_badge = Label.new()
	_badge.position = Vector2(310, -4)
	_badge.add_theme_font_size_override("font_size", 30)
	add_child(_badge)


func update_status(hp: int, area_permyriad: int) -> void:
	var frac := clampf(hp / 100.0, 0.0, 1.0)
	_hp_fill.size.x = 296 * frac
	_hp_fill.color = Color(0.85, 0.35, 0.3) if frac > 0.3 else Color(0.9, 0.25, 0.2)
	var tier := Sim.mass_tier(area_permyriad, 3500)
	var icons := ["🪶", "🥄", "🍳"]    # 轻/中/重（羽毛/汤勺/铁锅占位）
	var names := ["轻", "中", "重"]
	_badge.text = "%s %s  %d%%" % [icons[tier], names[tier], area_permyriad / 100]
	if tier != _last_tier:
		_last_tier = tier
		_badge.modulate = Color(1, 1, 1, 1)
		var tween := create_tween()
		tween.tween_property(_badge, "scale", Vector2(1.6, 1.6), 0.1)
		tween.tween_property(_badge, "scale", Vector2.ONE, 0.2)
