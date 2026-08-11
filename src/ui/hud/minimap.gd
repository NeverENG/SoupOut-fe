## minimap.gd — 小地图（A0001M11F02，3D 版：锅俯视圆盘）
## 复用 renderer 的同一张 field ImageTexture（T0005M07F05：小地图白送，零额外成本），
## 经 minimap.gdshader 把 R/G/B/A 覆盖度重映射回玩家调色板 + 圆形锅体遮罩
## （3D 版修正：直接贴原始纹理会把覆盖度当颜色显示）。
## 奶油锅沿圆环 + 双耳 · 玩家点每帧重绘于覆盖层（自己 = 白描边大点）。

class_name Minimap
extends Control

const D := 220.0          # 直径（设计参考：短边 22%）
const FRAME_W := 9.0      # 奶油锅沿厚度
const INSET := 6.0        # field 纹理距外框内缩

var battle: Node = null
var field_texture: ImageTexture = null
var _overlay: Control = null


## 覆盖层：玩家点/锅沿画在 field 纹理之上（父节点 _draw 会被子节点盖住，需独立 CanvasItem）
class Overlay extends Control:
	var map = null   # Minimap（不打类型注解，避免内嵌类循环解析）

	func _draw() -> void:
		if map != null:
			map._draw_overlay(self)


func setup(p_battle: Node) -> void:
	battle = p_battle
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 右上角锚定，任意分辨率成立
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -D - 24.0
	offset_right = -24.0
	offset_top = 24.0
	offset_bottom = 24.0 + D
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	# 地盘：复用 field 纹理（T0005M07F05），调色板映射 + 裁圆都在 shader 内
	var tr: TerritoryRenderer = battle.renderer if battle != null else null
	if tr != null:
		field_texture = tr.get_texture()
		var field := TextureRect.new()
		field.name = "field"
		field.texture = field_texture
		field.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		field.stretch_mode = TextureRect.STRETCH_SCALE
		field.position = Vector2(INSET, INSET)
		field.size = Vector2(D - INSET * 2.0, D - INSET * 2.0)
		field.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # 与主渲染一致（有意例外）
		field.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = load("res://src/ui/hud/minimap.gdshader")
		field.material = mat
		add_child(field)
	_overlay = Overlay.new()
	_overlay.map = self
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


func _draw() -> void:
	# 底盘（锅内阴影，画在 field 之下）
	draw_circle(Vector2(D / 2.0, D / 2.0), D / 2.0 - 2.0, Color(0.15, 0.10, 0.07, 0.75))


func _process(_delta: float) -> void:
	if battle == null or _overlay == null:
		return
	_overlay.queue_redraw()


## 覆盖层绘制：玩家点 → 双耳 → 奶油锅沿（沿最后画，收住贴边的点）
func _draw_overlay(c: Control) -> void:
	if battle == null:
		return
	var ctr := Vector2(D / 2.0, D / 2.0)
	var r := D / 2.0
	var ms: MatchState = battle.get("match_state")
	if ms != null:
		var span := D - INSET * 2.0
		for pid in ms.players.keys():
			var p: Dictionary = ms.players[pid]
			var wx := float(p.pos_x) / 64.0
			var wy := float(p.pos_y) / 64.0
			var pos := Vector2(wx / 48.0, wy / 48.0) * span + Vector2(INSET, INSET)
			var color := _color(pid)
			if pid == battle.me_id:
				# 自己 = 白描边大点
				c.draw_circle(pos, 9.0, Color.WHITE)
				c.draw_circle(pos, 6.0, color)
			else:
				c.draw_circle(pos, 7.0, _dark(pid))
				c.draw_circle(pos, 5.2, color)
	# 双耳（锅把手）
	for hx: float in [-1.0, 1.0]:
		var hp := ctr + Vector2(hx * (r + 1.0), 0.0)
		c.draw_circle(hp, 11.0, UiKit.WOOD)
		c.draw_circle(hp, 6.5, UiKit.WOOD_DARK)
	# 奶油锅沿 + 内外木描线
	c.draw_arc(ctr, r - FRAME_W / 2.0, 0.0, TAU, 72, UiKit.CREAM, FRAME_W, true)
	c.draw_arc(ctr, r, 0.0, TAU, 72, UiKit.WOOD, 2.5, true)
	c.draw_arc(ctr, r - FRAME_W, 0.0, TAU, 72, UiKit.WOOD, 2.0, true)


func _color(pid: int) -> Color:
	if pid >= 1 and pid <= 4:
		return UiKit.P_COLORS[pid - 1]
	return Color.WHITE


func _dark(pid: int) -> Color:
	if pid >= 1 and pid <= 4:
		return UiKit.P_DARKS[pid - 1]
	return UiKit.WOOD_DARK
