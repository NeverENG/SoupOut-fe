## wall.gd — 墙体（A0001M09F06：阻挡角色移动，不阻挡地盘扩张）
## 占位视觉（A0001M06F04 硬规则）：矮平面俯视足迹 · 内部镂空半透 α≈0.35 · 描边表达体积，
## 不得大面积实心色块遮挡地盘边界。正式资产：assets/temp/ter/ter_wall_*.png

class_name TerrainWall
extends Node2D

var wall_data: Dictionary = {}


func setup(data: Dictionary) -> void:
	wall_data = data
	# 占位：轴对齐矩形（从 corners 计算）+ 描边 + 中心半透
	var corners: PackedVector2Array = data.corners
	var poly := Polygon2D.new()
	poly.polygon = corners
	poly.color = Color(0.78, 0.62, 0.45, 0.35)      # 内部镂空半透（M06F04）
	poly.outline_size = 4
	poly.outline_color = Color(0.45, 0.33, 0.22, 0.9)
	add_child(poly)
	# 中心标记图案（表达体积）
	var core := Polygon2D.new()
	var c := Vector2(data.x, data.y)
	var r := 0.18
	var pts := PackedVector2Array()
	for i in range(6):
		var a := TAU * i / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	core.polygon = pts
	core.color = Color(0.45, 0.33, 0.22, 0.6)
	add_child(core)
	z_index = 4


## 碰撞判定（角色圆形 vs 轴对齐矩形，供本地权威/交互）
func collides_with(pos: Vector2, radius: float) -> bool:
	var hl: Vector2 = wall_data.half_extent
	var facing: Vector2 = wall_data.facing
	var perp := Vector2(-facing.y, facing.x)
	var rel := pos - Vector2(wall_data.x, wall_data.y)
	var along := absf(rel.dot(facing))
	var across := absf(rel.dot(perp))
	if along < hl.x + radius and across < hl.y + radius:
		return true
	# 圆角矩形近似：角落圆
	var cx := maxf(0.0, along - hl.x)
	var cy := maxf(0.0, across - hl.y)
	return cx * cx + cy * cy < radius * radius
