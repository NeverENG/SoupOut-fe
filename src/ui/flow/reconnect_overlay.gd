## reconnect_overlay.gd — 重连覆盖层（A0001M12F08）
## 触发：连续 KNOB_client_timeout 未收到快照。半透黑 + 冒泡 loading。
## 文案「汤还在锅上… 正在重连 (剩余 Xs)」倒计时实时走（上限跟随服务端 reconnect_grace，不得硬编码）。
## 底下保持最后一帧战场，不清屏；输入全禁用；恢复后淡出 + 「汤续上了」，允许画面瞬跳。
## 视觉：暗罩不动（要透出战场），中央换奶油小卡：咕嘟冒泡的锅 + 转圈汤勺 + 倒计时。

extends Control

var grace_total_s: float = 20.0

var _countdown: Label = null
var _elapsed := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP    # 输入全禁用（A0001M12F08）
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := UiKit.make_panel()
	center.add_child(card)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 36)
	card.add_child(pad)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	pad.add_child(vbox)

	# 咕嘟咕嘟：锅做轻微缩放脉动（scale 不参与容器排版，动画安全）
	var pot := UiKit.make_label("🍲", 110)
	pot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pot.resized.connect(func() -> void: pot.pivot_offset = pot.size / 2.0)
	vbox.add_child(pot)
	var boil := pot.create_tween()
	boil.set_loops()
	boil.tween_property(pot, "scale", Vector2(1.07, 1.07), 0.55).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	boil.tween_property(pot, "scale", Vector2.ONE, 0.55).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# 转圈汤勺 = loading 指示
	var ladle := UiKit.make_label("🥄", 40)
	ladle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ladle.resized.connect(func() -> void: ladle.pivot_offset = ladle.size / 2.0)
	vbox.add_child(ladle)
	var spin := ladle.create_tween()
	spin.set_loops()
	spin.tween_property(ladle, "rotation", TAU, 1.6).from(0.0)

	_countdown = UiKit.make_label("", 30)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_countdown)
	var note := UiKit.make_label("你不在，但你还在锅里（角色留在原地）", 20, UiKit.INK_SOFT)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(note)
	_update_label()


func _process(delta: float) -> void:
	_elapsed += delta
	_update_label()


func _update_label() -> void:
	var remain := int(ceilf(grace_total_s - _elapsed))
	_countdown.text = "汤还在锅上… 正在重连 (剩余 %ds)" % maxi(0, remain)
