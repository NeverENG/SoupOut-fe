## fixed.gd — 定点数辅助（T0005M10 确定性纪律）
## 位置 u16 定点 1/64 世界单位（T0001M01F03）· 速度 i8 定点 1/16 单位/tick
## 扩张半径 R int64 单位 1/1024 格 · 测地距离权重：直邻 1024 / 斜邻 1448（=round(1024×√2)）
## 预测路径禁止 float、禁止随机；定点除法一律走本文件显式辅助函数（舍入方向明确，与 Go 逐位一致）。
## 纯 GDScript，不 extends Node。

class_name Fixed

const POS_SCALE := 64          # 位置 1/64 世界单位
const VEL_SCALE := 16          # 速度 1/16 单位/**秒**（D0001M02 主属性表的移速列就是 单位/s）
const TICK_HZ := 20            # 权威 tick 率；速度换算成每 tick 位移必须除它
const R_SCALE := 1024          # 扩张半径 / 测地距离 1/1024 格
const SQRT2_FIXED := 1448      # round(1024 × √2) —— 必须与 Go 侧逐位一致（两端单测，M13F03）
const CHAMFER_ORTHO := 8       # Chamfer 距离正交步长（D0001M05F01）
const CHAMFER_DIAG := 11       # Chamfer 距离对角步长
const ANGLE_MAX := 65536       # u16 角度映射 0..2π
const WORLD_SIZE := 48         # 世界 48×48（T0001M01F03）
const GRID := 96               # 网格 96×96
const GRID_CELL := 2           # 格边长 = 0.5 世界单位 → 世界→格 ×2

## 扩张半径 R 口径（T0005M07F01 与 D0001 的统一）：
##   frontier 的 dist 用「格 × 1024」定点（直邻 +1024 / 斜邻 +1448）。
##   D0001 的 expandRate = 64（Q22.10）= 0.0625 Chamfer/tick = 0.0078125 格/tick。
##   → R 每 tick 增量 = round(64/8) = 8 定点（120s 后 ΔR = 2400×8 = 19200 = 18.75 格 ≈ Δr 18.7 ✓）
static func expand_rate_to_r_inc(expand_rate_fixed: int) -> int:
	return div_round(expand_rate_fixed, CHAMFER_ORTHO)


## 定点除法（向负无穷舍入，与 Go 的整数除法一致）
static func div_floor(a: int, b: int) -> int:
	if b == 0:
		return 0
	var q := a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


## 定点除法（四舍五入）
static func div_round(a: int, b: int) -> int:
	if b == 0:
		return 0
	return div_floor(a + (b / 2), b)


static func clamp_i(v: int, lo: int, hi: int) -> int:
	return maxi(lo, mini(hi, v))


## 世界单位 ↔ 定点
static func world_to_fixed(world: float) -> int:
	return int(round(world * POS_SCALE))

static func fixed_to_world(fx: int) -> float:
	return float(fx) / POS_SCALE

## 定点 ↔ 格坐标（世界 ×GRID_CELL → 格；0..95）
## 注意方向：世界→格是**乘** GRID_CELL（1 单位 = 2 格），不是除。
## 原来写成 fx/(POS_SCALE×GRID_CELL) 等于又除了一次 2 —— 整体差 4 倍，
## 出生点 (36.22, 36.22) 会被算到格 (18, 18)，四人圆盘全挤在一角。
## 向下取整而不是四舍五入：问的是「这个坐标落在哪一格」。
## 用 div_round 的话格中心（.5 位置）会被算进下一格，round-trip 差 1。
static func fixed_to_grid(fx: int) -> int:
	return clamp_i(fx * GRID_CELL / POS_SCALE, 0, GRID - 1)

static func grid_to_fixed_center(g: int) -> int:
	## 格中心：世界 (g + 0.5) / GRID_CELL → 定点。g=0 → 世界 0.25，g=95 → 世界 47.75。
	return div_round((2 * g + 1) * POS_SCALE, 2 * GRID_CELL)

## 角度
static func angle_to_uint16(angle_rad: float) -> int:
	var a := fmod(angle_rad, TAU)
	if a < 0.0:
		a += TAU
	return int(round(a / TAU * ANGLE_MAX)) & 0xFFFF

static func uint16_to_angle(v: int) -> float:
	return float(v) / ANGLE_MAX * TAU

## 归一化方向（moveX/moveY -100..100 → 单位向量 × speed，定点）
## 返回 {x, y} 定点速度（1/16 单位/tick）
static func dir_to_velocity(move_x: int, move_y: int, speed_fixed: int) -> Dictionary:
	if move_x == 0 and move_y == 0:
		return {"x": 0, "y": 0}
	# 无 float 的近似归一化：用 Chebyshev→Euclidean 混合（服务端同款）
	# 简化：以 max 分量归一，再乘 speed（与 Go 侧 sim 对齐的实现要点，见 sim.gd 注释）
	var ax := absi(move_x)
	var ay := absi(move_y)
	var m := maxi(ax, ay)
	if m == 0:
		return {"x": 0, "y": 0}
	# v = move/m * speed，全部定点（1/16）
	var vx := div_round(move_x * speed_fixed, m * VEL_SCALE) * VEL_SCALE
	var vy := div_round(move_y * speed_fixed, m * VEL_SCALE) * VEL_SCALE
	return {"x": vx, "y": vy}


## 网格测地距离（T0005M07F01：直邻 1024，斜邻 1448）→ 定点 1/1024 格
static func geodesic_dist(dx: int, dy: int) -> int:
	var ax := absi(dx)
	var ay := absi(dy)
	var diag := mini(ax, ay)
	var ortho := maxi(ax, ay) - diag
	return diag * SQRT2_FIXED + ortho * R_SCALE
