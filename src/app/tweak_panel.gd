## tweak_panel.gd — 实时调参面板（V0001M02F01 第 9 条：P0 必做，跳过就白做了）
## 游戏里直接拖 expandRate / vaultSlope / heavyThreshold，验证「多少才爽」。
## Tab 键开关（battle_root）。

class_name TweakPanel
extends Control

const KNOB_EXPAND_RATE_MIN := 8
const KNOB_EXPAND_RATE_MAX := 256      # 64 = D0001 起始值

var battle: Node = null
var _expand_slider: HSlider = null
var _speed_slider: HSlider = null
var _label_expand: Label = null
var _label_speed: Label = null


func setup(p_battle: Node) -> void:
	battle = p_battle
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(20, 120)
	custom_minimum_size = Vector2(320, 240)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	_label_expand = Label.new()
	_label_expand.text = "expandRate (Chamfer/tick)"
	vbox.add_child(_label_expand)
	_expand_slider = HSlider.new()
	_expand_slider.min_value = KNOB_EXPAND_RATE_MIN
	_expand_slider.max_value = KNOB_EXPAND_RATE_MAX
	_expand_slider.step = 1
	_expand_slider.value = 256
	_expand_slider.value_changed.connect(_on_expand_changed)
	vbox.add_child(_expand_slider)

	_label_speed = Label.new()
	_label_speed.text = "moveSpeed ×"
	vbox.add_child(_label_speed)
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.5
	_speed_slider.max_value = 1.5
	_speed_slider.step = 0.05
	_speed_slider.value = 1.0
	_speed_slider.value_changed.connect(_on_speed_changed)
	vbox.add_child(_speed_slider)

	var hint := Label.new()
	hint.text = "Tab 开关 · expandRate 决定单局时长（D0001M05F01，最先要测）"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.7)
	vbox.add_child(hint)

	add_child(panel)
	visible = true


func _on_expand_changed(v: float) -> void:
	var fixed_v := int(v)
	battle.set_expand_rate_fixed(fixed_v)
	_label_expand.text = "expandRate = %d（默认已拉满 256）" % fixed_v


func _on_speed_changed(v: float) -> void:
	battle.set_speed_mult(v)
	_label_speed.text = "moveSpeed × %.2f" % v
