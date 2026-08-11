## matchmaking.gd — 匹配中（A0001M13F04）
## 一口汤锅轻轻上下颠 + 四个锅位逐个「啵」地弹出食材色样 + 「等其他食材下锅… 2/4」+ 取消。
## 说明：0x015 QuickMatchStatus 待 T0001 补充（T0005M14F02-1），此处先显示本地占位，
## 服务端下发后接入真实队列数。

extends Control

const SEAT := 52.0

var _queue_label: Label = null
var _seats: Array = []            # 每项是锅位 wrapper（Control），点亮时往里弹色样
var _elapsed := 0.0
var _fake_fill := 1


func _ready() -> void:
	UiKit.kitchen_bg(self)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := UiKit.make_panel()
	center.add_child(card)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 40)
	card.add_child(pad)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	pad.add_child(vbox)

	# 汤锅：放进普通 Control 里手动摆位再做上下颠——
	# 直接 tween 容器子节点的 position 会被下一次排版打回去。
	var pot_wrap := Control.new()
	pot_wrap.custom_minimum_size = Vector2(240, 190)
	vbox.add_child(pot_wrap)
	var pot := Label.new()
	pot.text = "🍲"
	pot.add_theme_font_size_override("font_size", 140)
	pot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pot.set_anchors_preset(Control.PRESET_FULL_RECT)
	pot_wrap.add_child(pot)
	var bob := pot.create_tween()
	bob.set_loops()
	bob.tween_property(pot, "position:y", -12.0, 0.9).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	bob.tween_property(pot, "position:y", 0.0, 0.9).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# 四个锅位：空位是暗色圆片，点亮时弹出对应玩家色样
	var seats := HBoxContainer.new()
	seats.alignment = BoxContainer.ALIGNMENT_CENTER
	seats.add_theme_constant_override("separation", 28)
	vbox.add_child(seats)
	_seats.clear()
	for i in range(4):
		var wrap := Control.new()
		wrap.custom_minimum_size = Vector2(SEAT, SEAT)
		var hole := Panel.new()
		hole.position = Vector2.ZERO
		hole.size = Vector2(SEAT, SEAT)
		hole.add_theme_stylebox_override("panel",
			UiKit.sb(Color(0.35, 0.2, 0.1, 0.18), UiKit.WOOD, 3, int(SEAT / 2.6)))
		wrap.add_child(hole)
		seats.add_child(wrap)
		_seats.append(wrap)
	_light_seat(0)   # 第一个锅位是自己，进来就亮

	_queue_label = UiKit.make_label("等其他食材下锅… 1/4", 28)
	_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_queue_label)

	var cancel := UiKit.make_button("算了，不炖了", Vector2(380, 80), UiKit.Btn.DANGER, 30)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func(): App.instance.on_back_to_menu())
	vbox.add_child(cancel)


func _process(delta: float) -> void:
	_elapsed += delta
	# 占位动画：每 1.2s 点亮一个锅位（真实队列数等 0x015 下发）
	if _fake_fill < 4 and _elapsed > 1.2 * _fake_fill:
		_fake_fill += 1
		for i in range(_fake_fill):
			_light_seat(i)
		_queue_label.text = "等其他食材下锅… %d/4" % _fake_fill


## 点亮锅位 i：弹出该位玩家色样（TRANS_BACK 回弹，「啵」一下）
func _light_seat(i: int) -> void:
	var wrap: Control = _seats[i]
	if wrap.get_meta("lit", false):
		return
	wrap.set_meta("lit", true)
	var sw := UiKit.icon_swatch(UiKit.P_COLORS[i], SEAT)
	sw.position = Vector2.ZERO
	sw.size = Vector2(SEAT, SEAT)
	sw.pivot_offset = Vector2(SEAT / 2.0, SEAT / 2.0)
	sw.scale = Vector2(0.15, 0.15)
	wrap.add_child(sw)
	var tw := sw.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(sw, "scale", Vector2.ONE, 0.3)
