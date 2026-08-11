## top_bar.gd — 顶部信息（A0001M11F08，3D 版卡通重制）
## 奶油药丸横幅居中置顶：炖煮计时（最后 30s 变红心跳）/ 排名徽章（你是第 N/M 名）/
## 搅拌倒计时小勺纸片（<10s 才弹出，T−3s 起闪烁）/ 击杀横幅（顶部滑入 + 凶手色卡，2.5s 自散）。
## 对外契约不变：setup / update_timer / update_rank / update_stir_countdown / show_kill_banner。

class_name TopBar
extends Control

var battle: Node = null
var _timer: Label = null
var _rank: Label = null
var _stir: Label = null
var _stir_chip: PanelContainer = null
var _banner: PanelContainer = null
var _banner_label: Label = null
var _banner_swatch: Panel = null
var _banner_tween: Tween = null


func setup(p_battle: Node) -> void:
	battle = p_battle
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 药丸主横幅（顶部居中，随内容自适应宽度）
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_sb := UiKit.sb(
		Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.95), UiKit.WOOD, 3, 28, 5)
	pill_sb.content_margin_left = 26.0
	pill_sb.content_margin_right = 26.0
	pill_sb.content_margin_top = 7.0
	pill_sb.content_margin_bottom = 10.0
	pill.add_theme_stylebox_override("panel", pill_sb)
	_anchor_center_top(pill, 14.0)
	add_child(pill)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(hbox)

	hbox.add_child(UiKit.make_label("🍲", 26))
	_timer = UiKit.make_label("03:00", 38)
	hbox.add_child(_timer)
	hbox.add_child(_divider())

	# 排名徽章（玉米黄小牌）
	var rank_chip := PanelContainer.new()
	rank_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_chip.add_theme_stylebox_override("panel", _chip_sb(UiKit.YELLOW, UiKit.YELLOW_DARK))
	_rank = UiKit.make_label("你是第 -/- 名", 20)
	rank_chip.add_child(_rank)
	hbox.add_child(rank_chip)

	# 搅拌倒计时纸片（<10s 才出现）
	_stir_chip = PanelContainer.new()
	_stir_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stir_chip.add_theme_stylebox_override("panel", _chip_sb(UiKit.CREAM_DARK, UiKit.WOOD))
	_stir = UiKit.make_label("🥄 --s", 20)
	_stir_chip.add_child(_stir)
	_stir_chip.visible = false
	hbox.add_child(_stir_chip)

	# 击杀横幅（药丸下方滑入，凶手色卡 + 文案）
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b_sb := UiKit.sb(
		Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.96), UiKit.WOOD_DARK, 3, 20, 6)
	b_sb.content_margin_left = 20.0
	b_sb.content_margin_right = 20.0
	b_sb.content_margin_top = 8.0
	b_sb.content_margin_bottom = 10.0
	_banner.add_theme_stylebox_override("panel", b_sb)
	_anchor_center_top(_banner, 96.0)
	var b_box := HBoxContainer.new()
	b_box.alignment = BoxContainer.ALIGNMENT_CENTER
	b_box.add_theme_constant_override("separation", 12)
	b_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(b_box)
	_banner_swatch = Panel.new()
	_banner_swatch.custom_minimum_size = Vector2(26, 26)
	_banner_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b_box.add_child(_banner_swatch)
	_banner_label = UiKit.make_label("", 26)
	b_box.add_child(_banner_label)
	_banner.visible = false
	add_child(_banner)


## 居中置顶锚点（宽度随内容双向生长）
func _anchor_center_top(c: Control, y: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_top = y
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_END


func _chip_sb(bg: Color, border: Color) -> StyleBoxFlat:
	var s := UiKit.sb(bg, border, 2, 14)
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 3.0
	s.content_margin_bottom = 4.0
	return s


func _divider() -> Panel:
	var d := Panel.new()
	d.custom_minimum_size = Vector2(3, 30)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_theme_stylebox_override("panel",
		UiKit.sb(Color(UiKit.WOOD.r, UiKit.WOOD.g, UiKit.WOOD.b, 0.4), Color.TRANSPARENT, 0, 2))
	return d


func update_timer(remain_ticks: int) -> void:
	var secs := maxi(0, remain_ticks / 20)
	var mm := secs / 60
	var ss := secs % 60
	_timer.text = "%02d:%02d" % [mm, ss]
	if secs <= 30:
		# 最后 30s：番茄红 + 心跳（scale 不参与容器排版，安全）
		_timer.add_theme_color_override("font_color", UiKit.RED)
		_timer.pivot_offset = _timer.size / 2.0
		var k := 1.0 + 0.08 * sin(Time.get_ticks_msec() / 180.0)
		_timer.scale = Vector2(k, k)
	else:
		_timer.add_theme_color_override("font_color", UiKit.INK)
		_timer.scale = Vector2.ONE


func update_rank(rank: int, total: int) -> void:
	_rank.text = "你是第 %d/%d 名" % [rank, total]


func update_stir_countdown(secs: int) -> void:
	_stir.text = "🥄 %ds" % secs
	_stir_chip.visible = secs < 10
	if secs <= 3:
		_stir_chip.modulate = Color(1, 0.5, 0.4) \
			if int(Time.get_ticks_msec() / 250) % 2 == 0 else Color.WHITE
	else:
		_stir_chip.modulate = Color.WHITE


func show_kill_banner(killer_name: String, victim_name: String, killer_color: Color) -> void:
	_banner_label.text = "%s 把 %s 炖了！" % [killer_name, victim_name]
	_banner_swatch.add_theme_stylebox_override("panel",
		UiKit.sb(killer_color, killer_color.darkened(0.35), 2, 9))
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner.offset_top = 60.0
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_property(_banner, "offset_top", 96.0, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.set_parallel(false)
	_banner_tween.tween_interval(2.5)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.35)
	_banner_tween.tween_callback(func() -> void: _banner.visible = false)
