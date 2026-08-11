## sim.gd — 移动/扩张模拟，与服务端同规则（T0005M06 / M10）
## 客户端预测路径：无 float、无随机、除法走 fixed 显式辅助（与 Go 逐位对齐）。
## 纯 GDScript，不 extends Node。

class_name Sim
extends RefCounted

## 一步移动（定点）。move_x/move_y ∈ -100..100（T0001M02F04），speed 定点 1/16 单位/**秒**。
## 返回 {x, y}（定点 1/64 单位）
static func step(pos_x: int, pos_y: int, move_x: int, move_y: int, speed_fixed: int) -> Dictionary:
	var vel := Fixed.dir_to_velocity(move_x, move_y, speed_fixed)
	# speed 的单位是 单位/**秒**（D0001M02 主属性表），换成每 tick 位移要再除 TICK_HZ。
	# 漏掉这一下的话人物快 20 倍：6 单位/s 会变成 6 单位/tick = 120 单位/s，
	# 而整张地图才 48 单位宽，按一下方向键就贴到锅壁了。
	var nx: int = pos_x + vel.x * Fixed.POS_SCALE / (Fixed.VEL_SCALE * Fixed.TICK_HZ)
	var ny: int = pos_y + vel.y * Fixed.POS_SCALE / (Fixed.VEL_SCALE * Fixed.TICK_HZ)
	nx = Fixed.clamp_i(nx, 0, Fixed.WORLD_SIZE * Fixed.POS_SCALE)
	ny = Fixed.clamp_i(ny, 0, Fixed.WORLD_SIZE * Fixed.POS_SCALE)
	return {"x": nx, "y": ny}


## OBB 阻挡：把半径 radius 的圆心 pos 推出矩形墙外，返回修正后的位置。
## 墙来自 MapData._rect_wall / _diamond_wall（center + facing + half_extent）。
## 没有墙体碰撞的话「绕板子 / 翻窗」整条张力不成立（V0001M05 Q2），所以这是必需品不是打磨。
static func resolve_wall(pos: Vector2, radius: float, wall: Dictionary) -> Vector2:
	var center := Vector2(wall.x, wall.y)
	var facing: Vector2 = wall.facing
	var perp := Vector2(-facing.y, facing.x)
	var half: Vector2 = wall.half_extent
	# 转到墙局部坐标
	var rel := pos - center
	var lx := rel.dot(facing)
	var ly := rel.dot(perp)
	# 最近点（贴到盒子上）
	var cx := clampf(lx, -half.x, half.x)
	var cy := clampf(ly, -half.y, half.y)
	var dx := lx - cx
	var dy := ly - cy
	var d2 := dx * dx + dy * dy
	if d2 > radius * radius:
		return pos                      # 圆在盒外且不接触
	if d2 > 0.000001:
		# 圆心在盒外：沿最近点→圆心方向推到刚好相切
		var d := sqrt(d2)
		var push := (radius - d) / d
		lx += dx * push
		ly += dy * push
	else:
		# 圆心陷在盒内：沿穿透最浅的轴弹出
		var pen_x := half.x - absf(lx) + radius
		var pen_y := half.y - absf(ly) + radius
		if pen_x < pen_y:
			lx = (half.x + radius) * signf(lx) if lx != 0.0 else half.x + radius
		else:
			ly = (half.y + radius) * signf(ly) if ly != 0.0 else half.y + radius
	return center + facing * lx + perp * ly


## 圆形阻挡（倒下的板子）：把 pos 推出半径 obstacle_r 的圆外
static func resolve_circle(pos: Vector2, radius: float, c: Vector2, obstacle_r: float) -> Vector2:
	var d := pos - c
	var min_d := radius + obstacle_r
	var len := d.length()
	if len >= min_d:
		return pos
	if len < 0.000001:
		return c + Vector2(min_d, 0)
	return c + d / len * min_d


## 速度 → 位置增量（供插值/外推用，M08）
static func velocity_delta(vx: int, vy: int) -> Vector2:
	return Vector2(float(vx) / Fixed.VEL_SCALE, float(vy) / Fixed.VEL_SCALE) / float(Fixed.TICK_HZ)


## ── 主属性表：四档锚点 5% / 10% / 30% / 35%，初始 10% ────────────────────
## 区间比原来的 5–65% 收窄很多，是刻意的：
## 数值要「肉眼可读」——「3 刀打死小的、大的 200 血」这种话玩家能记住，
## 5–65% 那种大跨度会让每一档的差异糊成一片。
## 35% 同时是过重阈值（不能下板子，D0001M04）。
##
##   面积% | HP  | 移速  | 攻击距离 | 攻击倍率 | 体型直径
##      5  |  80 | 7.5  | 1.8     | 0.80    | 0.80
##     10  | 100 | 7.0  | 2.0     | 0.90    | 1.00   ← 初始
##     30  | 170 | 4.4  | 2.9     | 1.25    | 1.55
##     35  | 200 | 3.6  | 3.2     | 1.35    | 1.80   ← 过重
const AREA_ANCHOR := [500, 1000, 3000, 3500]
const HP_ANCHOR := [80.0, 100.0, 170.0, 200.0]
## 移速差**刻意收窄**（原来 7.5→3.6，大的慢一半）。
## 差一倍不是博弈，是硬克制：大的永远追不上小的，小的可以无限风筝。
## 现在大的慢 25%，追不上但配合板子/地形堵得住 —— 差距要够让人有感，
## 又不能大到「跑得快就赢」。真正的距离博弈来自出手的位移惩罚，不是底速差。
## 整体再降一档（原 6.6/6.4/5.2/4.8）。48 单位的锅横穿要 12 秒而不是 7.5 秒 ——
## 太快的话地图再复杂也走马观花，绕点/翻窗的取舍来不及想。
## 大小比例仍是 0.75（4.0 → 3.0），博弈结构不变，只是整体放慢。
## 想现场调用 Tab 面板的 moveSpeed × 滑杆。
const SPEED_ANCHOR := [4.2, 4.0, 3.2, 3.0]
const RANGE_ANCHOR := [1.8, 2.0, 2.9, 3.2]
const ATK_ANCHOR := [0.80, 0.90, 1.25, 1.35]
const SIZE_ANCHOR := [0.80, 1.00, 1.55, 1.80]


## 在四档锚点之间线性插值（超出两端就夹住）
static func _lut(area_permyriad: int, anchor: Array) -> float:
	var a := area_permyriad
	if a <= AREA_ANCHOR[0]:
		return anchor[0]
	for i in range(AREA_ANCHOR.size() - 1):
		if a <= AREA_ANCHOR[i + 1]:
			var t := float(a - AREA_ANCHOR[i]) / float(AREA_ANCHOR[i + 1] - AREA_ANCHOR[i])
			return lerpf(anchor[i], anchor[i + 1], t)
	return anchor[anchor.size() - 1]


## area 万分比 → 移速（定点 1/16 单位/秒）
static func speed_for_area(area_permyriad: int) -> int:
	return int(round(_lut(area_permyriad, SPEED_ANCHOR) * Fixed.VEL_SCALE))


## 最大生命：小 80 / 初始 100 / 大 200。
## 血量随体型是「大的耐打、小的灵活」这条博弈的一半，另一半是移速差。
static func hp_max_for_area(area_permyriad: int) -> int:
	return int(round(_lut(area_permyriad, HP_ANCHOR)))


## 攻击距离：小 1.8 / 大 3.2。
## 自动锁定之后，「够不够得着」是玩家唯一要判断的事 —— 距离博弈的载体。
static func attack_range_for_area(area_permyriad: int) -> float:
	return _lut(area_permyriad, RANGE_ANCHOR)


## 攻击倍率
static func attack_mult_for_area(area_permyriad: int) -> float:
	return _lut(area_permyriad, ATK_ANCHOR)


## 体型直径（连续，不再是三档跳变）
static func size_for_area(area_permyriad: int) -> float:
	return _lut(area_permyriad, SIZE_ANCHOR)


## 翻窗耗时（D0001M03F01：T_vault(A) = 0.40 + 0.025×(A−10)，夹 [0.35, 1.80]s）
static func vault_time_for_area(area_permyriad: int) -> float:
	var a := float(area_permyriad) / 100.0
	var t := 0.40 + 0.025 * (a - 10.0)
	return clampf(t, 0.35, 1.80)


## 体型档（A0001M08F02：三档 + 硬夹）：轻 <20% / 中 20%~threshold / 重 ≥threshold
static func mass_tier(area_permyriad: int, heavy_threshold_permyriad: int = 3500) -> int:
	## 返回 0=轻 1=中 2=重
	var a := area_permyriad
	if a >= heavy_threshold_permyriad:
		return 2
	if a >= 2000:
		return 1
	return 0


## 档位直径（轻 1.0u / 中 1.35u / 重 1.80u 硬夹，A0001M08F02）
static func tier_diameter(tier: int) -> float:
	match tier:
		1: return 1.35
		2: return 1.80
		_: return 1.0


## 摄像机视野（Agar.io 口径）：视野短边 = k × √面积，**连续**变化，不再是三档跳变。
##
## A0001M10F02 原定轻/中/重 = 11/13/15 个角色直径，离散跳档；实测两头都不对 ——
## 固定值要么开局看不见地盘边界，要么长大后画面空。改成随体积连续拉远：
## 开局 10% → 14 个直径（贴身，看得清板子和窗）；长到 65% → 约 36（能看见半个锅）。
## 越大视野越宽 + 越大移速越慢（speed_for_area 的 LUT）= 球球大作战那套手感。
##
## ⚠️ P0 待回填的手感值，调完要同步 A0001M10F02。
const VIEW_K := 0.4427             # 14 / √1000，让 10% 面积正好落在 14 个直径
const VIEW_MIN := 12.0
const VIEW_MAX := 38.0


static func camera_view_diameter_for_area(area_permyriad: int) -> float:
	var a := maxf(float(area_permyriad), 1.0)
	return clampf(VIEW_K * sqrt(a), VIEW_MIN, VIEW_MAX)
