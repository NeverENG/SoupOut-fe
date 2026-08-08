## reconnect_overlay.gd — 重连覆盖层（A0001M12F08）
## 触发：连续 KNOB_client_timeout 未收到快照。半透黑 + 冒泡 loading。
## 文案「汤还在锅上… 正在重连 (剩余 Xs)」倒计时实时走（上限跟随服务端 reconnect_grace，不得硬编码）。
## 底下保持最后一帧战场，不清屏；输入全禁用；恢复后淡出 + 「汤续上了」，允许画面瞬跳。

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
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	var pot := UiKit.make_label("🍲", 120)
	pot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(pot)
	_countdown = UiKit.make_label("", 30)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_countdown)
	var note := UiKit.make_label("你不在，但你还在锅里（角色留在原地）", 20, Color(0.8, 0.72, 0.6))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(note)
	_update_label()


func _process(delta: float) -> void:
	_elapsed += delta
	_update_label()


func _update_label() -> void:
	var remain := int(ceilf(grace_total_s - _elapsed))
	_countdown.text = "汤还在锅上… 正在重连 (剩余 %ds)" % maxi(0, remain)
