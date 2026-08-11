## prediction.gd — 移动预测与和解（T0005M06）
## 环形缓冲 64（3.2s @20Hz），预分配，热路径零分配（M12）。
## 收到 0x0C0 Snapshot：误差 ≤ RECONCILE_EPS 不动；超阈 → 硬置权威 + 重放 ack+1..latest；
## 视觉不硬跳：修正量记 visualError，0.1s 内衰减到 0（逻辑瞬移、画面平滑）。
## 纯 GDScript，不 extends Node。

class_name Prediction
extends RefCounted

const BUFFER_SIZE := 64
const RECONCILE_EPS := 2          # 2 个定点单位 = 2/64 世界单位（M06F02）
const ERROR_DECAY_S := 0.1

var inputs: Array = []            # 环形缓冲 {seq, move_x, move_y, aim, buttons}
var predicted: Array = []         # {x, y} 定点位置
var head: int = 0                 # 最新帧索引
var latest_seq: int = -1

# 当前权威位置（定点）
var auth_x: int = 0
var auth_y: int = 0

# 视觉平滑
var visual_error := Vector2.ZERO
var _error_remaining_s := 0.0

# 状态
var paused := false               # 死亡/搅拌推开/复活期间停预测（M06F03）


func _init() -> void:
	for i in range(BUFFER_SIZE):
		inputs.append({"seq": 0, "move_x": 0, "move_y": 0, "aim": 0, "buttons": 0})
		predicted.append({"x": 0, "y": 0})


## 输入 tick：采样 → 写入环形缓冲 → 本地立即跑一步（M05F03 第 5 步）
func record_input(seq: int, move_x: int, move_y: int, aim: int, buttons: int,
		speed_fixed: int) -> void:
	if paused:
		return
	var slot := head
	head = (head + 1) % BUFFER_SIZE
	latest_seq = seq
	var inp: Dictionary = inputs[slot]
	inp.seq = seq
	inp.move_x = move_x
	inp.move_y = move_y
	inp.aim = aim
	inp.buttons = buttons
	# 从**当前**预测位置往前推一步，然后把结果存进本槽。
	# 原来是从 predicted[slot] 起步 —— 那是 64 帧之前的陈旧值（hard_set 还会把
	# 所有槽填成同一个位置），结果每次输入都从上次权威修正的地方重新走一步，
	# 预测位置永远只前进一步，联网时本地预测等于没有。
	var step := Sim.step(auth_x, auth_y, move_x, move_y, speed_fixed)
	auth_x = step.x
	auth_y = step.y
	var p: Dictionary = predicted[slot]
	p.x = auth_x
	p.y = auth_y


## 用权威位置初始化（复活/重连，M09F04）
func hard_set(x: int, y: int) -> void:
	auth_x = x
	auth_y = y
	visual_error = Vector2.ZERO
	_error_remaining_s = 0.0
	for p in predicted:
		p.x = x
		p.y = y


## 和解（M06F02）：Snapshot 到达时用 ackInputSeq 定位缓冲
func reconcile(ack_seq: int, auth_pos_x: int, auth_pos_y: int, speed_fixed: int) -> void:
	if ack_seq < 0 or latest_seq < 0:
		return
	var slot := _find_slot(ack_seq)
	if slot < 0:
		return
	var ack_pred: Dictionary = predicted[slot]
	var dx := absi(auth_pos_x - ack_pred.x)
	var dy := absi(auth_pos_y - ack_pred.y)
	if dx <= RECONCILE_EPS and dy <= RECONCILE_EPS:
		return   # 误差可接受，什么都不做
	# 回滚：硬置权威 + 重放 ack+1 .. latest
	hard_set(auth_pos_x, auth_pos_y)
	visual_error = Vector2(float(auth_pos_x - ack_pred.x) / Fixed.POS_SCALE,
		float(auth_pos_y - ack_pred.y) / Fixed.POS_SCALE)
	_error_remaining_s = ERROR_DECAY_S
	var i := (slot + 1) % BUFFER_SIZE
	var guard := 0
	while guard < BUFFER_SIZE:
		var inp: Dictionary = inputs[i]
		if inp.seq > ack_seq and inp.seq <= latest_seq:
			var step := Sim.step(auth_x, auth_y, inp.move_x, inp.move_y, speed_fixed)
			auth_x = step.x
			auth_y = step.y
			predicted[i].x = auth_x
			predicted[i].y = auth_y
		i = (i + 1) % BUFFER_SIZE
		guard += 1


## 渲染位置 = 逻辑位置 + visualError 衰减
func get_render_pos() -> Vector2:
	var base := Vector2(float(auth_x) / Fixed.POS_SCALE, float(auth_y) / Fixed.POS_SCALE)
	if _error_remaining_s > 0.0:
		return base + visual_error * (_error_remaining_s / ERROR_DECAY_S)
	return base


## 每帧推进 visualError 衰减（渲染层驱动）
func advance_error(delta: float) -> void:
	if _error_remaining_s > 0.0:
		_error_remaining_s = maxf(0.0, _error_remaining_s - delta)


func _find_slot(seq: int) -> int:
	for i in range(BUFFER_SIZE):
		if inputs[i].seq == seq:
			return i
	return -1


func clear() -> void:
	head = 0
	latest_seq = -1
	paused = false
	hard_set(auth_x, auth_y)
