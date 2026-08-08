## clock.gd — 服务器 tick 估计与输入提前量（T0005M05）
## estServerTick = lastSnapshot.serverTick + floor(msSince/50)
## EWMA 平滑：只调速率不跳变（偏差大时本地 tick 累加器步进临时 ±10%，绝不直接改 estServerTick）
## lead = clamp(ceil((SRTT/2 + 2×RTTVAR)/50ms) + JITTER_DEPTH, 2, 8)
## estServerTick 单调不减。纯 GDScript，不 extends Node。

class_name SoupClock
extends RefCounted

const TICK_MS := 50.0            # 20 Hz
const JITTER_DEPTH := 2          # T0001M01F02 抖动缓冲深度
const LEAD_MIN := 2
const LEAD_MAX := 8

var est_server_tick: int = 0     # 单调不减
var last_snapshot_tick: int = 0
var last_snapshot_at_ms: int = 0 # Time.get_ticks_msec()
var _rate := 1.0                 # 本地 tick 累加速率（EWMA 调节 0.9..1.1）
var _acc_ms := 0.0


func on_snapshot(server_tick: int, now_ms: int) -> void:
	if server_tick > last_snapshot_tick:
		# 偏差 = 服务器 tick 推进速度 vs 本地时钟
		var dt_ms := float(maxi(1, now_ms - last_snapshot_at_ms))
		var server_advance := server_tick - last_snapshot_tick
		var actual_rate := server_advance * TICK_MS / dt_ms
		# EWMA：只微调速率，不跳变（M05F01）
		_rate = clampf(0.9 * _rate + 0.1 * actual_rate, 0.9, 1.1)
		last_snapshot_tick = server_tick
		last_snapshot_at_ms = now_ms
		est_server_tick = maxi(est_server_tick, server_tick)


## 每渲染帧推进本地 tick 累加器（保持 estServerTick 单调不减、连续）
func advance(delta_ms: float) -> void:
	_acc_ms += delta_ms * _rate
	while _acc_ms >= TICK_MS:
		_acc_ms -= TICK_MS
		est_server_tick += 1


## 输入提前量（M05F02）：SRTT/RTTVAR 直接复用可靠层为 RTO 算好的两个值
func compute_lead(srtt_ms: int, rttvar_ms: int) -> int:
	var base := ceili((float(srtt_ms) / 2.0 + 2.0 * float(rttvar_ms)) / TICK_MS)
	return clampi(base + JITTER_DEPTH, LEAD_MIN, LEAD_MAX)


func input_tick_for(srtt_ms: int, rttvar_ms: int) -> int:
	return est_server_tick + compute_lead(srtt_ms, rttvar_ms)


## 重连恢复（M09F04）：唯一允许跳变的地方
func hard_set(server_tick: int) -> void:
	est_server_tick = server_tick
	last_snapshot_tick = server_tick
	_rate = 1.0
	_acc_ms = 0.0
