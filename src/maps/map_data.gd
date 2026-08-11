## map_data.gd — 地图定义（A0001M09 的数量约束已按「地图要更复杂」的要求打破）
## 坐标系：世界 48×48，锅心 (24,24)，锅半径 24 单位（T0001M01F03）
##
## ── 结构：每个象限一个「街区」，锅心一个十字路口 ──────────────────────────
## 四重旋转对称（四个玩家必须公平），但**象限内部有层次**，不再是一座孤零零的屋：
##
##   大屋   三面墙 + 门洞朝锅心 + 两扇窗 + 门口一块板   ← 主绕点
##   小屋   L 形两面墙 + 一扇窗                        ← 次绕点，短促
##   夹道   两堵平行墙形成通道，道中卡一块板            ← 一夫当关
##   散柱   两根玉米段单柱                              ← 微掩体，能贴着绕
##   外环   仍留开阔汤面 —— 铺地盘的地方，色块要完整
##
## 锅心：冻豆腐屋（四面藕孔）+ 四条放射走廊墙 → 十字路口，四条道通向四个象限。
##
## ── 建材（汤主题，不用面包那种不下锅的东西）────────────────────────────────
##   白菜垛 层叠绿 · 心里美萝卜 粉白 · 冻豆腐 暖米黄 · 玉米段 明黄
##   藕片 = 窗（藕天然有孔，「从藕孔翻过去」比抽象圆环贴题）
##
## 纯 GDScript，不 extends Node（静态数据，可无头单测）。

class_name MapData

const WORLD := 48.0
const CENTER := Vector2(24.0, 24.0)
const POT_RADIUS := 24.0

# ── 布局参数 ──────────────────────────────────────────────────────────────
const WALL_THICK := 0.45
const SPAWN_R := 20.4           # 出生点：外环开阔地
# 大屋
const HOUSE_R := 10.5
const HOUSE_HALF := 2.8         # 半宽（沿切向）
const HOUSE_DEPTH := 2.6        # 半进深（沿径向）
# 小屋（偏一侧）
const HUT_R := 16.0
const HUT_OFF := 5.0            # 切向偏移
const HUT_LEN := 3.2
# 夹道（偏另一侧）
const LANE_R := 15.0
const LANE_OFF := -5.6
const LANE_LEN := 4.4
const LANE_GAP := 2.2           # 通道宽
# 散柱
const PILLAR_R := 12.6
const PILLAR_OFF := 7.6
const PILLAR_SIZE := 0.9
# 锅心
const CORE_HALF := 2.8
const CORRIDOR_IN := 4.6
const CORRIDOR_LEN := 3.0

# 墙（食材）
const WALL_CABBAGE := "wall_cabbage"        # 白菜垛
const WALL_RADISH := "wall_radish"          # 心里美萝卜
const WALL_TOFU := "wall_tofu"              # 冻豆腐
const WALL_CORN := "wall_corn"              # 玉米段
# 兼容旧命名
const WALL_LONG := WALL_CABBAGE
const WALL_SHORT := WALL_RADISH
const WALL_DIAMOND := WALL_TOFU
# 板：葱段（外围）/ 姜片（锅心）
const PALLET_CONG := "pallet_cong"
const PALLET_JIANG := "pallet_jiang"
# 窗：藕片 / 锅耳
const VAULT_LOTUS := "vault_lotus"
const VAULT_LOUSHAO := VAULT_LOTUS
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
	var wid := 0
	var vid := 0
	var pid := 0
	# ── 四个街区（θ = 45° + 90°k）────────────────────────────────────────
	for k in range(4):
		var theta := deg_to_rad(45.0 + 90.0 * k)
		var dir := Vector2(cos(theta), sin(theta))          # 指向锅外
		var tan := Vector2(-dir.y, dir.x)

		var spawn := CENTER + dir * SPAWN_R
		d.spawns.append({"player_id": k + 1, "x": spawn.x, "y": spawn.y, "angle": theta + PI})

		# ① 大屋：后墙（白菜）+ 两侧墙（萝卜），门洞朝锅心
		var hc := CENTER + dir * HOUSE_R
		d.walls.append(_rect_wall(hc + dir * HOUSE_DEPTH, tan,
			HOUSE_HALF * 2.0, WALL_THICK, WALL_CABBAGE))
		for side in [1.0, -1.0]:
			var sc: Vector2 = hc + tan * (HOUSE_HALF * side)
			d.walls.append(_rect_wall(sc, dir, HOUSE_DEPTH * 2.0, WALL_THICK, WALL_RADISH))
		# 窗：后墙正中（藕孔）+ 一侧墙中段（锅耳）
		var bw: Vector2 = hc + dir * HOUSE_DEPTH
		d.vaults.append({"id": vid, "x": bw.x, "y": bw.y, "kind": VAULT_LOTUS, "angle": theta})
		vid += 1
		var sw: Vector2 = hc + tan * HOUSE_HALF
		d.vaults.append({"id": vid, "x": sw.x, "y": sw.y,
			"kind": VAULT_GUOER, "angle": theta + PI / 2})
		vid += 1
		# 板：门口
		var door: Vector2 = hc - dir * HOUSE_DEPTH
		d.pallets.append({"id": pid, "x": door.x, "y": door.y,
			"kind": PALLET_CONG, "angle": theta})
		pid += 1

		# ② 小屋：L 形两面墙 + 一扇藕孔
		var uc := CENTER + dir * HUT_R + tan * HUT_OFF
		d.walls.append(_rect_wall(uc, tan, HUT_LEN, WALL_THICK, WALL_CABBAGE))
		d.walls.append(_rect_wall(uc + dir * (HUT_LEN * 0.5) - tan * (HUT_LEN * 0.5),
			dir, HUT_LEN, WALL_THICK, WALL_RADISH))
		d.vaults.append({"id": vid, "x": uc.x, "y": uc.y, "kind": VAULT_LOTUS, "angle": theta})
		vid += 1

		# ③ 夹道：两堵平行墙（沿径向）+ 道中一块板 —— 一夫当关
		var lc := CENTER + dir * LANE_R + tan * LANE_OFF
		for side2 in [1.0, -1.0]:
			d.walls.append(_rect_wall(lc + tan * (LANE_GAP * 0.5 * side2), dir,
				LANE_LEN, WALL_THICK, WALL_CABBAGE))
		d.pallets.append({"id": pid, "x": lc.x, "y": lc.y, "kind": PALLET_CONG, "angle": theta})
		pid += 1

		# ④ 散柱 ×2（玉米段）：贴着能绕的微掩体
		for j in range(2):
			var pc := CENTER + dir * (PILLAR_R + float(j) * 2.6) + tan * (PILLAR_OFF - float(j) * 1.6)
			d.walls.append(_rect_wall(pc, dir, PILLAR_SIZE, PILLAR_SIZE, WALL_CORN))

	# ── 锅心十字路口：冻豆腐屋 + 四条放射走廊墙 ──────────────────────────
	d.walls.append(_diamond_wall(CENTER, CORE_HALF * 2.0, WALL_TOFU))
	for k in range(4):
		var ta := deg_to_rad(45.0 + 90.0 * k)
		var dd := Vector2(cos(ta), sin(ta))
		var wv: Vector2 = CENTER + dd * (CORE_HALF * 0.707)
		d.vaults.append({"id": vid, "x": wv.x, "y": wv.y, "kind": VAULT_LOTUS, "angle": ta})
		vid += 1
		# 放射走廊墙（θ=90°k）：把锅心和四个象限之间隔出通道
		var tb := deg_to_rad(90.0 * k)
		var db := Vector2(cos(tb), sin(tb))
		var tb_perp := Vector2(-db.y, db.x)
		d.walls.append(_rect_wall(CENTER + db * (CORRIDOR_IN + CORRIDOR_LEN * 0.5),
			db, CORRIDOR_LEN, WALL_THICK, WALL_TOFU))
		# 板：走廊外端两侧
		var pv: Vector2 = CENTER + db * (CORRIDOR_IN + CORRIDOR_LEN + 1.1)
		d.pallets.append({"id": pid, "x": pv.x, "y": pv.y, "kind": PALLET_JIANG, "angle": tb})
		pid += 1
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
