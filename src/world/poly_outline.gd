## poly_outline.gd — 给 Polygon2D 加描边
##
## Godot 4 的 Polygon2D **没有** outline_size / outline_color，那是 Godot 3 的 API。
## 直接赋值会在运行期抛 "Invalid assignment of property 'outline_size'"，
## 而占位美术全靠 Polygon2D 画，所以墙/板/窗/角色四处都会炸。
## 这里用一个闭合 Line2D 子节点代替，视觉等价。
##
## 宽度单位是**世界单位**（1 单位 ≈ 175px @1920 宽、摄像机 11 单位视野），
## 所以 0.06 大约是 10px 的描边，不要照搬 Godot 3 那种像素值。

class_name PolyOutline
extends Object


## 假 2.5D 立体块：底面（暗，原位）+ 顶面（亮，上移 height）+ 地面投影。
## 不改坐标系、不改碰撞 —— 逻辑仍是纯俯视，只是渲染上给物件加了厚度，
## 视觉立刻变成「从上往下看偏一点」。真等距投影要重做网格/碰撞/膨胀，代价差一个数量级。
## 返回顶面节点（调用方可能还要在它上面挂东西）。
static func attach_block(parent: Node2D, poly_points: PackedVector2Array,
		top_color: Color, height: float = 0.9, outline_w: float = 0.07) -> Polygon2D:
	# 用 darkened 而不是分量相乘：相乘会把白萝卜压成水泥灰，
	# darkened 保留色相，侧壁看着还是同一种食材，只是背光面。
	var side_color := top_color.darkened(0.42)
	var edge_color := top_color.darkened(0.68)
	edge_color.a = 0.95

	# ① 地面投影：朝右下偏，和物体错开
	var shadow := Polygon2D.new()
	shadow.polygon = poly_points
	shadow.color = Color(0.08, 0.05, 0.03, 0.32)
	shadow.position = Vector2(height * 0.35, height * 0.45)
	parent.add_child(shadow)

	# ② 侧壁：底面 ∪ 顶面 的**凸包轮廓**。
	# 上一版只是把同一个多边形错位画两次，露出来的那点边缘几乎看不见（0.32 单位≈十几像素）。
	# 凸包才是真正的挤出剪影 —— 矩形会变成一个更高的矩形，菱形会变成六边形，
	# 侧面是连续的一整块，看着才像有厚度的实体。
	var all := PackedVector2Array()
	all.append_array(poly_points)
	for p in poly_points:
		all.append(p - Vector2(0, height))
	var side := Polygon2D.new()
	side.polygon = Geometry2D.convex_hull(all)
	side.color = side_color
	parent.add_child(side)
	attach(side, outline_w, edge_color)

	# ③ 顶面：上移 height
	var top := Polygon2D.new()
	top.polygon = poly_points
	top.color = top_color
	top.position = Vector2(0, -height)
	parent.add_child(top)
	attach(top, outline_w, edge_color)
	return top


## 脚下椭圆投影（角色/道具用）
static func attach_ground_shadow(parent: Node2D, rx: float, ry: float,
		alpha: float = 0.30) -> Polygon2D:
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	var sh := Polygon2D.new()
	sh.polygon = pts
	sh.color = Color(0.10, 0.06, 0.03, alpha)
	sh.position = Vector2(0.06, 0.22)
	sh.z_index = -2
	parent.add_child(sh)
	return sh


static func attach(poly: Polygon2D, width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.points = poly.polygon
	line.closed = true
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	poly.add_child(line)
	return line
