## minimap.gd — 小地图（A0001M11F02，跟随摄像机下的强制项）
## 圆形（就是那口锅的俯视轮廓）· 右上角 · 直径 = 短边 22% · 底板半透 α0.75
## 内容：四色地盘 + 原汤（降采样）+ 4 玩家点 + 自己的视野框 + 搅拌预警弧（占位）
## 复用同一张 field 纹理（T0005M07F05：小地图白送，零额外成本）。

class_name Minimap
extends Control

var battle: Node = null
var field_texture: ImageTexture = null
var _players: Array = []       # {pid, pos(Vector2), me}


func setup(p_battle: Node) -> void:
	battle = p_battle
	var size := int(mini(1080, 1920) * 0.22)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(-size - 24, 24)
	custom_minimum_size = Vector2(size, size)
	# 底板（圆形锅）
	var bg := Polygon2D.new()
	var pts := PackedVector2Array()
	var r := size / 2.0
	for i in range(48):
		var a := TAU * i / 48.0
		pts.append(Vector2(r, r) + Vector2(cos(a), sin(a)) * r)
	bg.polygon = pts
	bg.color = Color(0.15, 0.10, 0.07, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# 地盘：复用 field 纹理（T0005M07F05：小地图白送）
	var tr: TerritoryRenderer = battle.renderer if battle != null else null
	if tr != null:
		var field := TextureRect.new()
		field.name = "field"
		field.texture = tr.get_texture()
		field.size = Vector2(size * 0.92, size * 0.92)
		field.position = Vector2(size * 0.04, size * 0.04)
		field.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # 与主渲染一致（有意例外）
		field.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(field)


func _process(_delta: float) -> void:
	if battle == null:
		return
	var size := custom_minimum_size.x
	# 清掉每帧重绘的玩家点（保留 field 与底板）
	for child in get_children():
		if child is ColorRect:
			child.queue_free()
	_draw_players(size)


func _draw_players(size: float) -> void:
	var ms: MatchState = battle.get("match_state", null)
	if ms == null:
		return
	for pid in ms.players.keys():
		var p: Dictionary = ms.players[pid]
		var wx := float(p.pos_x) / 64.0
		var wy := float(p.pos_y) / 64.0
		var pos := Vector2(wx / 48.0, wy / 48.0) * size * 0.92 + Vector2(size * 0.04, size * 0.04)
		var dot := ColorRect.new()
		var color := _color(pid)
		dot.color = color if pid != battle.me_id else Color.WHITE
		dot.size = Vector2(10, 10) if pid != battle.me_id else Vector2(14, 14)
		dot.position = pos - dot.size / 2
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)


func _color(pid: int) -> Color:
	match pid:
		1: return Color(0.949, 0.565, 0.608)
		2: return Color(0.18, 0.604, 0.525)
		3: return Color(1.0, 0.824, 0.118)
		4: return Color(0.545, 0.361, 0.839)
	return Color.WHITE
