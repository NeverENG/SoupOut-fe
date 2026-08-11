## room_screen.gd — 房间（A0001M13F05）
## 顶部房间码（大字号 + 一键复制）；四个位：色样+昵称+已准备勾；
## 改食材（点自己 → 弹食材卡，0x018 撞车可换）；底部「我准备好了」（0x019）。
## 数据源：0x017 RoomState（app 已缓存到字典，经 App.instance 查询）。
## 视觉：厨房背景 + 居中奶油卡；名单行是围裙白小面板，色样走 UiKit.P_COLORS。

extends Control

const ICONS := ["🍅", "🥬", "🌽", "🍠"]

var _players_box: VBoxContainer = null
var _ready_btn: Button = null
var _code_label: Label = null


func _ready() -> void:
	UiKit.kitchen_bg(self)

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
	vbox.add_theme_constant_override("separation", 20)
	pad.add_child(vbox)

	# 顶部：房间码 + 复制
	var code_row := HBoxContainer.new()
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_row.add_theme_constant_override("separation", 20)
	vbox.add_child(code_row)
	_code_label = UiKit.make_label("房间码：----", 40)
	_code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code_row.add_child(_code_label)
	var copy := UiKit.make_button("复制", Vector2(140, 64), UiKit.Btn.PRIMARY, 24)
	copy.pressed.connect(_copy_code)
	code_row.add_child(copy)

	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", UiKit.sb(Color(0.55, 0.38, 0.22, 0.25), Color.TRANSPARENT, 0, 2))
	vbox.add_child(sep)

	# 中央：四玩家位
	_players_box = VBoxContainer.new()
	_players_box.custom_minimum_size = Vector2(560, 0)
	_players_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_players_box)

	# 底部：准备（主 CTA） + 退出
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 24)
	vbox.add_child(bottom)
	_ready_btn = UiKit.make_button("我准备好了", Vector2(380, 92), UiKit.Btn.SUCCESS, 34)
	_ready_btn.pressed.connect(_toggle_ready)
	bottom.add_child(_ready_btn)
	var back := UiKit.make_button("退出房间", Vector2(220, 92), UiKit.Btn.DANGER, 26)
	back.pressed.connect(func(): App.instance.on_leave_room())
	bottom.add_child(back)
	_refresh()


func _refresh() -> void:
	var code: String = App.instance.my_room_code
	if code.is_empty():
		code = "----"
	_code_label.text = "房间码：%s" % code
	# 从 RoomState 读玩家（app 未缓存则显示本地占位）
	for child in _players_box.get_children():
		child.queue_free()
	var _rs = App.instance.get("_last_room_state")
	var room_state: Dictionary = _rs if _rs is Dictionary else {}
	var players: Array = room_state.get("players", [])
	if players.is_empty():
		for i in range(4):
			players.append({"player_id": i + 1, "nickname": "等待下锅…", "ingredient_id": 0, "ready": false})
	for p in players:
		_players_box.add_child(_player_row(p))


## 名单行：围裙白小面板 = 色样 + 食材 + 昵称 ⟷ 准备状态
func _player_row(p: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.sb(UiKit.APRON, UiKit.WOOD, 2, 16))
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	pad.add_child(row)
	var ing: int = clampi(int(p.get("ingredient_id", 0)), 0, 3)
	var swatch := UiKit.icon_swatch(UiKit.P_COLORS[ing], 36)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var name_l := UiKit.make_label("%s  %s" % [ICONS[ing], p.nickname], 24)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_l)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var ready_l := UiKit.make_label("✅" if p.ready else "…", 24, UiKit.GREEN_DARK if p.ready else UiKit.INK_SOFT)
	ready_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(ready_l)
	return panel


func _toggle_ready() -> void:
	App.instance.on_set_ready(true)
	_ready_btn.text = "已准备 ✓"
	_ready_btn.disabled = true


func _copy_code() -> void:
	DisplayServer.clipboard_set(App.instance.my_room_code)
