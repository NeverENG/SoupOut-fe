## area_bar.gd — 面积条（A0001M11F01：全场最重要的 UI，3D 版卡通重制）
## 左下角奶油圆角框内的 100% 堆叠条 [P1][P2][P3][P4][原汤]（按锅内方位排列不按名次）
## 自己那段白描边 + 「我」字标 · 65% 胜利刻度旗常驻（T0001M02F03）· 条下自己面积 % 小标签
## 数据源不变：0x0C2 ScoreTick（1Hz 权威万分比，不是本地数格 —— T0005M07F06）
## 变化表现：段宽 0.2s 插值保留；原汤段变宽时闪亮占位气泡。

class_name AreaBar
extends Control

const COLORS := [Color(0.949, 0.565, 0.608), Color(0.18, 0.604, 0.525),
	Color(1.0, 0.824, 0.118), Color(0.545, 0.361, 0.839), Color(0.725, 0.604, 0.447)]
const NAMES := ["排骨", "紫菜", "玉米", "茄子", "原汤"]
const BAR_W := 440.0
const BAR_H := 26.0
const PAD := 6.0

var ratios := [1000, 1000, 1000, 1000, 6000]   # 万分比，index 4 = 原汤
var me_id: int = 1
var _bar: HBoxContainer = null
var _segs: Array = []        # 每段 ColorRect
var _tick_label: Label = null
var _me_label: Label = null


func setup(p_me_id: int) -> void:
	me_id = p_me_id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 左下角锚定（触屏拇指区上方），任意分辨率成立
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 24.0
	offset_right = 24.0 + BAR_W + PAD * 2.0
	offset_top = -252.0
	offset_bottom = -252.0 + BAR_H + PAD * 2.0 + 26.0
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	# 奶油底框（木边圆角卡）
	var frame := Panel.new()
	frame.position = Vector2.ZERO
	frame.size = Vector2(BAR_W + PAD * 2.0, BAR_H + PAD * 2.0)
	frame.add_theme_stylebox_override("panel", UiKit.sb(UiKit.CREAM, UiKit.WOOD, 3, 14, 5))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	# 堆叠条（框内衬收边）
	_bar = HBoxContainer.new()
	_bar.position = Vector2(PAD, PAD)
	_bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	_bar.add_theme_constant_override("separation", 0)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	for i in range(5):
		var seg := ColorRect.new()
		seg.color = COLORS[i]
		seg.custom_minimum_size = Vector2(10, BAR_H)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i + 1 == me_id:
			# 自己那段：白描边覆盖层（ColorRect 不吃 panel stylebox，改用子 Panel）
			var outline := Panel.new()
			outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			outline.add_theme_stylebox_override("panel", _self_outline())
			outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			seg.add_child(outline)
		var label := Label.new()
		label.text = "我" if i + 1 == me_id else ""
		label.position = Vector2(5, 1)
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
		label.add_theme_constant_override("outline_size", 3)
		seg.add_child(label)
		_bar.add_child(seg)
		_segs.append(seg)
	# 65% 胜利刻度旗（T0001M02F03：≥65% 立即结束，常驻可见）
	var tick := ColorRect.new()
	tick.color = Color(1, 1, 1, 0.92)
	tick.position = Vector2(PAD + BAR_W * 0.65 - 1.5, 2.0)
	tick.size = Vector2(3, BAR_H + PAD * 2.0 - 4.0)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tick)
	_tick_label = Label.new()
	_tick_label.text = "🚩65%"
	_tick_label.position = Vector2(PAD + BAR_W * 0.65 - 22.0, -24.0)
	_tick_label.add_theme_font_size_override("font_size", 15)
	_tick_label.add_theme_color_override("font_color", UiKit.CREAM)
	_tick_label.add_theme_color_override("font_outline_color", UiKit.WOOD_DARK)
	_tick_label.add_theme_constant_override("outline_size", 4)
	add_child(_tick_label)
	# 自己面积 % 小标签（条下方）
	_me_label = Label.new()
	_me_label.text = "我的地盘 10%"
	_me_label.position = Vector2(PAD, BAR_H + PAD * 2.0 + 2.0)
	_me_label.add_theme_font_size_override("font_size", 16)
	_me_label.add_theme_color_override("font_color",
		COLORS[clampi(me_id - 1, 0, 3)].lightened(0.25))
	_me_label.add_theme_color_override("font_outline_color", UiKit.WOOD_DARK)
	_me_label.add_theme_constant_override("outline_size", 4)
	add_child(_me_label)


func _self_outline() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.0)
	s.set_border_width_all(2)
	s.border_color = Color.WHITE
	return s


## 0x0C2 ScoreTick 数据入口（T0005M09F01：唯一数据源）
func on_score_tick(ratios_in: PackedInt32Array) -> void:
	for i in range(4):
		ratios[i] = ratios_in[i]
	var sum := 0
	for i in range(4):
		sum += ratios_in[i]
	ratios[4] = maxi(0, 10000 - sum)   # 原汤 = 100% - 四家
	if me_id >= 1 and me_id <= 4:
		_me_label.text = "我的地盘 %d%%" % (ratios[me_id - 1] / 100)
	_refresh()


func _refresh() -> void:
	# 段宽 0.2s 插值（tween）
	for i in range(5):
		var w := BAR_W * float(ratios[i]) / 10000.0
		var seg: ColorRect = _segs[i]
		if seg.custom_minimum_size.x != w:
			var tween := create_tween()
			tween.tween_property(seg, "custom_minimum_size", Vector2(maxf(6, w), BAR_H), 0.2)
			# 原汤段变宽时冒气泡（占位：闪亮）
			if i == 4 and w > seg.custom_minimum_size.x + 1:
				seg.color = COLORS[4].lightened(0.15)
				var t2 := create_tween()
				t2.tween_property(seg, "color", COLORS[4], 0.4)
