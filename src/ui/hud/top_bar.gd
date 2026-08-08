## top_bar.gd — 顶部信息（A0001M11F08）
## 炖煮计时（锅盖形徽章 + MM:SS，最后 30s 变红心跳）/ 当前排名（2/4，翻牌动画）/
## 搅拌倒计时（🥄 + 秒数，T−3s 起图标震动）/ 击杀横幅（双方名字用各自主色）。

class_name TopBar
extends Control

var battle: Node = null
var _timer: Label = null
var _rank: Label = null
var _stir: Label = null
var _banner: Label = null
var _banner_timer := 0.0


func setup(p_battle: Node) -> void:
	battle = p_battle
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	position = Vector2(0, 20)
	# 面积条下方居中（A0001M11F08：计时在面积条正下方居中）
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 30)
	hbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hbox.position = Vector2(0, 64)
	add_child(hbox)
	_timer = UiKit.make_label("03:00", 30)
	hbox.add_child(_timer)
	_rank = UiKit.make_label("2/4", 26)
	hbox.add_child(_rank)
	_stir = UiKit.make_label("🥄 45s", 24)
	hbox.add_child(_stir)
	# 击杀横幅（计时下方滑入）
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.position = Vector2(0, 120)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 30)
	_banner.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.06))
	_banner.add_theme_constant_override("outline_size", 4)
	_banner.visible = false
	add_child(_banner)


func update_timer(remain_ticks: int) -> void:
	var secs := maxi(0, remain_ticks / 20)
	var mm := secs / 60
	var ss := secs % 60
	_timer.text = "%02d:%02d" % [mm, ss]
	if secs <= 30:
		_timer.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		_timer.scale = Vector2(1.0 + 0.1 * sin(Time.get_ticks_msec() / 200.0), 1.0)


func update_rank(rank: int, total: int) -> void:
	_rank.text = "%d/%d" % [rank, total]


func update_stir_countdown(secs: int) -> void:
	_stir.text = "🥄 %ds" % secs
	if secs <= 3:
		_stir.modulate = Color(1, 0.4, 0.3) if int(Time.get_ticks_msec() / 300) % 2 == 0 else Color.WHITE
	else:
		_stir.modulate = Color.WHITE


func show_kill_banner(killer_name: String, victim_name: String, killer_color: Color) -> void:
	_banner.text = "%s 击倒了 %s！%s 的汤正在化开！" % [killer_name, victim_name, victim_name]
	_banner.add_theme_color_override("font_color", killer_color)
	_banner.visible = true
	_banner_timer = 2.5


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner.visible = false
