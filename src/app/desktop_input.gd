## desktop_input.gd — 电脑端输入（正式包在触屏设备上不挂载）
##
## 操作已收敛成**两个控件**（北极星）：
##   摇杆 / WASD  →  移动
##   万能键       →  短按 = 情境动作（近窗翻窗 / 近板推板 / 否则挥击）
##                   长按 = 按住扩张
##
## 键鼠映射到 battle_root 与触屏**完全相同**的接口，不是第二套逻辑，只是第二只手：
##   set_move_stick / set_charging / queue_action / can_charge / reject_charge
##
## 键位：
##   WASD / ↑↓←→        移动
##   鼠标左键 / 空格      万能键（长短按）
##   Tab                 调参面板（battle_root.on_unhandled_input）
##
## 朝向由 battle_root._aim_angle 统一决定：移动面向移动方向、
## 挥击前摇自动转向最近对手。这里只负责移动和万能键。
##
## 直接轮询 Input 而不走 _gui_input：HUD 的 Control 铺满屏幕会吃掉事件。

class_name DesktopInput
extends Node

## 长短按阈值。跨过它的**瞬间**就进扩张态，不等抬手 ——
## 否则「按住看它涨」会平白多 200ms 延迟，第一下手感就糊了。
const HOLD_THRESHOLD_S := 0.2
const REJECT_COOLDOWN_S := 1.5     # 与 stick_move 的拒绝反馈频率限制一致

var battle: Node = null

var _held := false                 # 万能键是否按下
var _held_time := 0.0
var _charging := false             # 是否已跨阈值进入扩张态
var _reject_cd := 0.0


func setup(p_battle: Node) -> void:
	battle = p_battle


func _process(delta: float) -> void:
	if battle == null:
		return
	if _reject_cd > 0.0:
		_reject_cd -= delta
	_poll_move()
	_poll_universal(delta)


# ══ 移动（WASD / 方向键）══════════════════════════════════════════════════

func _poll_move() -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1.0
	# 斜向归一化：否则对角线快 √2 倍，会污染 expandRate 的手感判断
	if v.length_squared() > 0.0:
		v = v.normalized()
	battle.set_move_stick(v)


# ══ 万能键（长短按）═══════════════════════════════════════════════════════

func _poll_universal(delta: float) -> void:
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)

	if down and not _held:                 # ── 按下沿
		_held = true
		_held_time = 0.0
		return

	if down and _held:                     # ── 持续按住
		_held_time += delta
		if not _charging and _held_time >= HOLD_THRESHOLD_S:
			_try_start_charge()
		return

	if not down and _held:                 # ── 抬手
		_held = false
		if _charging:
			_charging = false
			battle.set_charging(false)
		else:
			# 没跨过阈值 = 短按 → 情境动作
			battle.queue_action()
		_held_time = 0.0


## 进扩张态。与 stick_move 同一条判定：不在自己汤里 → 拒绝反馈，不进扩张。
func _try_start_charge() -> void:
	if battle.can_charge():
		_charging = true
		battle.set_charging(true)
	elif _reject_cd <= 0.0:
		_reject_cd = REJECT_COOLDOWN_S
		battle.reject_charge()
	# 拒绝后不再重试，等这次抬手；否则会每帧刷提示
	_held_time = -1e9
