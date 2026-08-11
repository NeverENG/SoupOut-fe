## wall.gd — 墙体 3D 版(A0001M09F06:阻挡角色移动,不阻挡地盘扩张)
## 食材化建材(汤主题):
##   白菜垛 = 一排白菜 · 心里美萝卜 = 一排萝卜 · 冻豆腐 = 奶酪块(米黄带孔,神形兼备)
##   玉米段 = 横躺玉米棒。模型来自 Kenney Food Kit(CC0,assets/props/)。
## 底部配深汤色基座条,墙的「足迹」与碰撞范围一目了然。
## 对外契约不变:setup(data) / collides_with(pos, radius) / color_for(kind)。

class_name TerrainWall
extends Node3D

var wall_data: Dictionary = {}

## 墙高(世界单位)。窗要抬到同样高度,否则会埋进墙里。
const WALL_HEIGHT := 0.9

const COLOR_CABBAGE := Color(0.42, 0.68, 0.34)
const COLOR_RADISH := Color(0.95, 0.72, 0.76)
const COLOR_TOFU := Color(0.99, 0.94, 0.78)
const COLOR_CORN := Color(1.0, 0.84, 0.28)

const _KIND_MODEL := {
	"wall_cabbage": "res://assets/props/cabbage.glb",
	"wall_radish": "res://assets/props/radish.glb",
	"wall_tofu": "res://assets/props/cheese.glb",   # 整块奶酪(cheese-cut 是 2cm 薄片,勿用)
	"wall_corn": "res://assets/props/corn.glb",
}


static func color_for(kind: String) -> Color:
	match kind:
		MapData.WALL_RADISH: return COLOR_RADISH
		MapData.WALL_TOFU: return COLOR_TOFU
		MapData.WALL_CORN: return COLOR_CORN
		_: return COLOR_CABBAGE


func setup(data: Dictionary) -> void:
	wall_data = data
	var kind: String = data.get("kind", "")
	var c := Vector2(data.x, data.y)
	var facing: Vector2 = data.facing
	var half: Vector2 = data.half_extent
	var length := half.x * 2.0
	var thick := half.y * 2.0

	# 朝向基(3D):along = 墙走向,perp = 法向
	var along3 := Vector3(facing.x, 0.0, facing.y)
	var yaw := atan2(along3.x, along3.z)

	# ① 基座条:深汤色矮条,标出足迹(墙根阴影感)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick + 0.16, 0.22, length + 0.16)   # BoxMesh z 轴当长边
	base.mesh = bm
	base.material_override = Fx3D.mat(Color(0.32, 0.20, 0.12), 0.0, 0.95)
	base.position = Vector3(c.x, 0.11, c.y)
	base.rotation.y = yaw
	add_child(base)

	# ② 食材阵列:沿墙线摆一排,交替微旋转/微缩放,手摆感
	var model_path: String = _KIND_MODEL.get(kind, _KIND_MODEL["wall_cabbage"])
	var target_h := WALL_HEIGHT
	var lay_flat := kind == MapData.WALL_CORN     # 玉米横躺
	# 先实例一个量尺寸
	var probe := Fx3D.instance(model_path)
	var bb := Fx3D.local_aabb(probe)
	probe.queue_free()
	var unit_w := maxf(bb.size.x, bb.size.z)
	var longest := maxf(unit_w, bb.size.y)
	var scale_v := target_h / maxf(bb.size.y, 0.001)
	if lay_flat:
		# 横躺:直径压到墙高,长轴贴墙走向
		scale_v = (WALL_HEIGHT * 0.95) / maxf(minf(bb.size.x, bb.size.z), 0.001)
	# 防爆:平放/薄片模型按 y 放大会爆炸,最长边夹在 2×墙高以内
	scale_v = minf(scale_v, WALL_HEIGHT * 2.0 / maxf(longest, 0.001))
	var unit_len := (bb.size.y if lay_flat else unit_w) * scale_v
	var step := maxf(unit_len * 0.82, 0.55)
	var count := maxi(1, int(ceil(length / step)))
	step = length / float(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(c)) & 0x7fffffff
	for i in range(count):
		var m := Fx3D.instance(model_path)
		m.scale = Vector3.ONE * (scale_v * rng.randf_range(0.94, 1.06))
		var t := (float(i) + 0.5) / float(count) - 0.5
		var p := c + facing * (length * t)
		var wobble := rng.randf_range(-0.06, 0.06)
		m.position = Vector3(p.x, 0.16, p.y)
		if lay_flat:
			# 旋转序 YXZ:先 Rx(90°) 把长轴(Y)放倒到 +Z,再 Ry(yaw) 对齐墙走向
			m.rotation = Vector3(PI / 2.0, yaw, 0.0)
			m.position.y = WALL_HEIGHT * 0.5
		else:
			m.rotation.y = yaw + rng.randf_range(-0.5, 0.5)
		m.position += Vector3(-facing.y, 0.0, facing.x) * wobble
		add_child(m)


## 碰撞判定(角色圆形 vs 有向矩形,供本地权威/交互)—— 逻辑与 2D 版逐行一致
func collides_with(pos: Vector2, radius: float) -> bool:
	var hl: Vector2 = wall_data.half_extent
	var facing: Vector2 = wall_data.facing
	var perp := Vector2(-facing.y, facing.x)
	var rel := pos - Vector2(wall_data.x, wall_data.y)
	var along := absf(rel.dot(facing))
	var across := absf(rel.dot(perp))
	if along < hl.x + radius and across < hl.y + radius:
		return true
	var cx := maxf(0.0, along - hl.x)
	var cy := maxf(0.0, across - hl.y)
	return cx * cx + cy * cy < radius * radius
