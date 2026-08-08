## area_bar.gd — 面积条（A0001M11F01：全场最重要的 UI）
## 顶部居中偏左 · 单条 100% 堆叠 [P1][P2][P3][P4][原汤]（按锅内方位排列不按名次）
## 自己那段 2px 白描边 + 「我」字标 · 段带 M07F02 图案 · 65% 刻度线常驻可见
## 数据源：0x0C2 ScoreTick（1Hz 权威万分比，不是本地数格 —— T0005M07F06）
## 变化表现：段宽 0.2s 插值；增长段右缘发亮脉冲，缩小段右缘冒气泡；原汤段化汤时冒气泡。

class_name AreaBar
extends Control

const COLORS := [Color(0.949, 0.565, 0.608), Color(0.18, 0.604, 0.525),
	Color(1.0, 0.824, 0.118), Color(0.545, 0.361, 0.839), Color(0.725, 0.604, 0.447)]
const NAMES := ["排骨", "紫菜", "玉米", "茄子", "原汤"]

var ratios := [1000, 1000, 1000, 1000, 6000]   # 万分比，index 4 = 原汤
var me_id: int = 1
var _bar: HBoxContainer = null
var _segs: Array = []        # 每段 ColorRect + Label
var _tick_label: Label = null
var _bubble_timers := {}


func setup(p_me_id: int) -> void:
	me_id = p_me_id
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(40, 24)
	custom_minimum_size = Vector2(850, 40)
	# 条
	_bar = HBoxContainer.new()
	_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_bar.position = Vector2(0, 0)
	_bar.custom_minimum_size = Vector2(820, 30)
	add_child(_bar)
	for i in range(5):
		var seg := ColorRect.new()
		seg.color = COLORS[i]
		seg.custom_minimum_size = Vector2(10, 30)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i + 1 == me_id:
			seg.add_theme_stylebox_override("panel", _self_outline())
		_bar.add_child(seg)
		var label := Label.new()
		label.text = "我" if i + 1 == me_id else ""
		label.add_theme_font_size_override("font_size", 14)
		label.modulate = Color.WHITE
		seg.add_child(label)
		_segs.append(seg)
	# 65% 刻度线（T0001M02F03：≥65% 立即结束，常驻可见）
	var tick := ColorRect.new()
	tick.color = Color(1, 1, 1, 0.9)
	tick.position = Vector2(820 * 0.65 - 1, -4)
	tick.size = Vector2(3, 38)
	add_child(tick)
	_tick_label = Label.new()
	_tick_label.text = "▲65%"
	_tick_label.position = Vector2(820 * 0.65 - 24, 34)
	_tick_label.add_theme_font_size_override("font_size", 14)
	_tick_label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	add_child(_tick_label)


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
	_refresh()


func _refresh() -> void:
	# 段宽 0.2s 插值（tween）
	for i in range(5):
		var w := 820 * float(ratios[i]) / 10000.0
		var seg: ColorRect = _segs[i]
		if seg.custom_minimum_size.x != w:
			var tween := create_tween()
			tween.tween_property(seg, "custom_minimum_size", Vector2(maxf(6, w), 30), 0.2)
			# 原汤段变宽时冒气泡（占位：闪亮）
			if i == 4 and w > seg.custom_minimum_size.x + 1:
				seg.color = COLORS[4].lightened(0.15)
				var t2 := create_tween()
				t2.tween_property(seg, "color", COLORS[4], 0.4)
