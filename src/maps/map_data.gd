## map_data.gd — 地图定义（A0001M09：严格 4 重旋转对称 · 5 组团 · 8 板 12 窗 · 13 墙）
## 坐标系：世界 48×48，锅心 (24,24)，锅半径 24 单位（T0001M01F03）
## 出生角：θ = 45° + 90°k（P1 右上 / P2 左上 / P3 左下 / P4 右下）
## 组团：灶台角组团×4（落后者的家）+ 锅心漩涡组团（热区）
## 数值（A0001M09F03/F04）：长墙 2.4u · 短墙 1.4u · 放射墙 1.2u · 菱形对角 1.6u
## 绕行代价 D 设计指标 3–6 单位（D0001M03F02）
## 纯 GDScript，不 extends Node（静态数据，可无头单测）。

class_name MapData

const WORLD := 48.0
const CENTER := Vector2(24.0, 24.0)
const POT_RADIUS := 24.0

# 墙
const WALL_LONG := "wall_long"
const WALL_SHORT := "wall_short"
const WALL_DIAMOND := "wall_diamond"
# 板：葱段（外围）/ 姜片（锅心）
const PALLET_CONG := "pallet_cong"
const PALLET_JIANG := "pallet_jiang"
# 窗：漏勺孔 / 锅耳
const VAULT_LOUSHAO := "vault_loushao"
const VAULT_GUOER := "vault_guoer"


static func build_map(map_id: int = 1) -> Dictionary:
	var d := {
		"map_id": map_id,
		"world_size": WORLD,
		"pot_center": CENTER,
		"pot_radius": POT_RADIUS,
		"grid_w": Fixed.GRID,
		"grid_h": Fixed.GRID,
		"spawns": [],
		"walls": [],
		"pallets": [],
		"vaults": [],
	}
	# ── 灶台角组团 ×4（θ = 45° + 90°k）────────────────────────────────────
	for k in range(4):
		var theta := deg_to_rad(45.0 + 90.0 * k)
		var dir := Vector2(cos(theta), sin(theta))
		var tangent := Vector2(-dir.y, dir.x)
		# 组团中心 r=0.62，出生点 r=0.72（组团外侧偏一点）
		var group_center := CENTER + dir * (0.62 * POT_RADIUS)
		var spawn := CENTER + dir * (0.72 * POT_RADIUS)
		d.spawns.append({"player_id": k + 1, "x": spawn.x, "y": spawn.y, "angle": theta})
		# 长墙：切向 2.4u，位于组团外侧（挡住外侧+一侧）
		d.walls.append(_rect_wall(group_center + dir * 1.15, tangent, 2.4, 0.32, WALL_LONG))
		# 短墙：径向 1.4u，与长墙成 90°（L 形围合）
		d.walls.append(_rect_wall(group_center - tangent * 0.9, dir, 0.32, 1.4, WALL_SHORT))
		# 板 ×1：长墙中段外侧通道口（葱段）
		d.pallets.append({
			"id": k, "x": (group_center + dir * 1.45).x, "y": (group_center + dir * 1.45).y,
			"kind": PALLET_CONG, "angle": theta,
		})
		# 窗 ×2：长墙正中（漏勺孔）+ 短墙靠外端（锅耳）
		d.vaults.append({
			"id": k, "x": (group_center + dir * 1.15).x, "y": (group_center + dir * 1.15).y,
			"kind": VAULT_LOUSHAO, "angle": theta,
		})
		d.vaults.append({
			"id": k + 4, "x": (group_center - tangent * 0.9).x, "y": (group_center - tangent * 0.9).y,
			"kind": VAULT_GUOER, "angle": theta + PI / 2,
		})
	# ── 锅心漩涡组团（r ≤ 0.30，本身 4 重对称）──────────────────────────────
	# 中央菱形墙块：对角 1.6u（正方形旋转 45°）
	d.walls.append(_diamond_wall(CENTER, 1.6, WALL_DIAMOND))
	# 放射短墙 ×4（θ=0/90/180/270）：放在四人边界交界方向
	for k in range(4):
		var theta := deg_to_rad(90.0 * k)
		var dir := Vector2(cos(theta), sin(theta))
		var start := CENTER + dir * 5.2
		d.walls.append(_rect_wall(start + dir * 0.6, dir, 0.3, 1.2, WALL_SHORT))
		# 板 ×4（姜片）：每条放射墙外端的通道口
		d.pallets.append({
			"id": 4 + k, "x": (start + dir * 1.6).x, "y": (start + dir * 1.6).y,
			"kind": PALLET_JIANG, "angle": theta,
		})
	# 窗 ×4：中央菱形墙的四条边（漏勺孔，可直接翻进锅心最中央）
	for k in range(4):
		var theta := deg_to_rad(45.0 + 90.0 * k)
		var dir := Vector2(cos(theta), sin(theta))
		d.vaults.append({
			"id": 8 + k, "x": (CENTER + dir * 0.85).x, "y": (CENTER + dir * 0.85).y,
			"kind": VAULT_LOUSHAO, "angle": theta,
		})
	return d


## 轴对齐矩形墙（中心点 + 朝向单位向量 + 长宽）
static func _rect_wall(center: Vector2, facing: Vector2, len: float, width: float, kind: String) -> Dictionary:
	var perp := Vector2(-facing.y, facing.x)
	# 四个角（局部 ±len/2 × ±width/2）
	var hw := width / 2.0
	var hl := len / 2.0
	return {
		"x": center.x, "y": center.y, "kind": kind,
		"half_extent": Vector2(hl, hw), "facing": facing,
		"corners": [
			center + facing * hl + perp * hw,
			center + facing * hl - perp * hw,
			center - facing * hl - perp * hw,
			center - facing * hl + perp * hw,
		],
	}


## 菱形墙（正方形旋转 45°），diagonal = 对角长度
static func _diamond_wall(center: Vector2, diagonal: float, kind: String) -> Dictionary:
	var r := diagonal / 2.0
	var c := center
	return {
		"x": center.x, "y": center.y, "kind": kind,
		"half_extent": Vector2(r * 0.7071, r * 0.7071), "facing": Vector2.RIGHT,
		"corners": [
			c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
		],
	}


## 锅形：世界坐标是否在锅内（供本地权威/交互判定）
static func inside_pot(pos: Vector2) -> bool:
	return pos.distance_to(CENTER) <= POT_RADIUS
