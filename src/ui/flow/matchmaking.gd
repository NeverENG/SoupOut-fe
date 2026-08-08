## matchmaking.gd — 匹配中（A0001M13F04）
## 一口空锅四个锅位逐个点亮 + 「等其他食材下锅… 2/4」+ 取消。
## 说明：0x015 QuickMatchStatus 待 T0001 补充（T0005M14F02-1），此处先显示本地占位，
## 服务端下发后接入真实队列数。

extends Control

var _queue_label: Label = null
var _seats: Array = []
var _elapsed := 0.0
var _fake_fill := 1


func _ready() -> void:
	UiKit.full_rect_bg(self, Color(0.15, 0.10, 0.08))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)

	# 空锅 + 四个锅位（占位点）
	var pot := Label.new()
	pot.text = "🍲"
	pot.add_theme_font_size_override("font_size", 140)
	pot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(pot)
	var seats := HBoxContainer.new()
	seats.alignment = BoxContainer.ALIGNMENT_CENTER
	seats.add_theme_constant_override("separation", 30)
	vbox.add_child(seats)
	for i in range(4):
		var seat := Label.new()
		seat.text = "○"
		seat.add_theme_font_size_override("font_size", 44)
		seat.modulate = Color(0.5, 0.42, 0.32)
		seats.add_child(seat)
		_seats.append(seat)

	_queue_label = UiKit.make_label("等其他食材下锅… 1/4", 26, Color(0.9, 0.82, 0.7))
	_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_queue_label)

	var cancel := UiKit.make_button("算了，不炖了", Vector2(360, 72))
	cancel.pressed.connect(func(): App.instance.on_back_to_menu())
	vbox.add_child(cancel)


func _process(delta: float) -> void:
	_elapsed += delta
	# 占位动画：每 1.2s 点亮一个锅位（真实队列数等 0x015 下发）
	if _fake_fill < 4 and _elapsed > 1.2 * _fake_fill:
		_fake_fill += 1
		for i in range(_fake_fill):
			_seats[i].text = "●"
			_seats[i].modulate = Color(0.95, 0.8, 0.45)
		_queue_label.text = "等其他食材下锅… %d/4" % _fake_fill
