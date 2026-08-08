## room_screen.gd — 房间（A0001M13F05）
## 顶部房间码（大字号等宽 + 一键复制）；四个位：头像+昵称+食材+已准备勾；
## 改食材（点自己 → 弹食材卡，0x018 撞车可换）；底部「我准备好了」（0x019）。
## 数据源：0x017 RoomState（app 已缓存到字典，经 App.instance 查询）。

extends Control

var _players_box: VBoxContainer = null
var _ready_btn: Button = null
var _code_label: Label = null


func _ready() -> void:
	UiKit.full_rect_bg(self, Color(0.16, 0.11, 0.08))
	# 顶部：房间码
	_code_label = UiKit.make_label("房间码：----", 40, Color(0.95, 0.85, 0.6))
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_code_label.position = Vector2(0, 40)
	add_child(_code_label)

	var copy := UiKit.make_button("复制", Vector2(140, 56))
	copy.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	copy.position = Vector2(-220, 56)
	copy.pressed.connect(_copy_code)
	add_child(copy)

	# 中央：四玩家位
	_players_box = VBoxContainer.new()
	_players_box.set_anchors_preset(Control.PRESET_CENTER)
	_players_box.position = Vector2(-400, -240)
	_players_box.add_theme_constant_override("separation", 16)
	add_child(_players_box)

	# 底部：准备
	_ready_btn = UiKit.make_button("我准备好了", Vector2(420, 84))
	_ready_btn.set_anchors_preset(Control.PRESET_BOTTOM_CENTER)
	_ready_btn.position = Vector2(-210, -80)
	_ready_btn.pressed.connect(_toggle_ready)
	add_child(_ready_btn)
	var back := UiKit.make_button("退出房间", Vector2(200, 56))
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.position = Vector2(40, -64)
	back.pressed.connect(func(): App.instance.on_leave_room())
	add_child(back)
	_refresh()


func _refresh() -> void:
	var code: String = App.instance.my_room_code
	if code.is_empty():
		code = "----"
	_code_label.text = "房间码：%s" % code
	# 从 RoomState 读玩家（app 未缓存则显示本地占位）
	for child in _players_box.get_children():
		child.queue_free()
	var room_state: Dictionary = App.instance.get("_last_room_state", {})
	var players: Array = room_state.get("players", [])
	if players.is_empty():
		for i in range(4):
			players.append({"player_id": i + 1, "nickname": "等待下锅…", "ingredient_id": 0, "ready": false})
	for p in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name := UiKit.make_label(p.nickname, 22)
		row.add_child(name)
		var ready := UiKit.make_label("✅" if p.ready else "…", 22)
		row.add_child(ready)
		_players_box.add_child(row)


func _toggle_ready() -> void:
	App.instance.on_set_ready(true)
	_ready_btn.text = "已准备 ✓"
	_ready_btn.disabled = true


func _copy_code() -> void:
	DisplayServer.clipboard_set(App.instance.my_room_code)
