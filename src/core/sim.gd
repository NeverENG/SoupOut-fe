## sim.gd — 移动/扩张模拟，与服务端同规则（T0005M06 / M10）
## 客户端预测路径：无 float、无随机、除法走 fixed 显式辅助（与 Go 逐位对齐）。
## 纯 GDScript，不 extends Node。

class_name Sim
extends RefCounted

## 一步移动（定点）。move_x/move_y ∈ -100..100（T0001M02F04），speed 定点 1/16 单位/tick。
## 返回 {x, y}（定点 1/64 单位）
static func step(pos_x: int, pos_y: int, move_x: int, move_y: int, speed_fixed: int) -> Dictionary:
	var vel := Fixed.dir_to_velocity(move_x, move_y, speed_fixed)
	var nx := pos_x + vel.x * Fixed.POS_SCALE / Fixed.VEL_SCALE
	var ny := pos_y + vel.y * Fixed.POS_SCALE / Fixed.VEL_SCALE
	nx = Fixed.clamp_i(nx, 0, Fixed.WORLD_SIZE * Fixed.POS_SCALE)
	ny = Fixed.clamp_i(ny, 0, Fixed.WORLD_SIZE * Fixed.POS_SCALE)
	return {"x": nx, "y": ny}


## 速度 → 位置增量（供插值/外推用，M08）
static func velocity_delta(vx: int, vy: int) -> Vector2:
	return Vector2(float(vx) / Fixed.VEL_SCALE, float(vy) / Fixed.VEL_SCALE) * (1.0 / 20.0)


## 按面积百分比查主属性表（D0001M02，线性插值；LUT 语义）
static func speed_for_area(area_permyriad: int) -> int:
	## area 万分比 → 移速（定点 1/16）。LUT：5%→6.2 · 10%→6.0 · 35%→5.0 · 65%→4.5
	var a := float(area_permyriad) / 100.0
	var s := 6.2
	if a >= 65.0:
		s = 4.5
	elif a >= 50.0:
		s = lerpf(4.7, 4.5, (a - 50.0) / 15.0)
	elif a >= 40.0:
		s = lerpf(4.9, 4.7, (a - 40.0) / 10.0)
	elif a >= 35.0:
		s = lerpf(5.0, 4.9, (a - 35.0) / 5.0)
	elif a >= 30.0:
		s = lerpf(5.2, 5.0, (a - 30.0) / 5.0)
	elif a >= 20.0:
		s = lerpf(5.6, 5.2, (a - 20.0) / 10.0)
	elif a >= 10.0:
		s = lerpf(6.0, 5.6, (a - 10.0) / 10.0)
	elif a >= 5.0:
		s = lerpf(6.2, 6.0, (a - 5.0) / 5.0)
	return int(round(s * Fixed.VEL_SCALE))


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


## 摄像机 zoom 基准（A0001M10F02）：视野短边高度 = N 个轻装直径，轻11/中13/重15
static func camera_view_diameter(tier: int) -> float:
	match tier:
		1: return 13.0
		2: return 15.0
		_: return 11.0
