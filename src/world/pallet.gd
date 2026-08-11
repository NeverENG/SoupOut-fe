## pallet.gd — 板子 3D 版(A0001M09F05 / M12F06)
## 三态:Standing / Down / Recovering(KNOB_pallet_respawn 后自动立起,A0001M15F01-6)
## 视觉:菜板模型(Kenney Food Kit,CC0)。葱段=染绿,姜片=染姜黄。
## Standing 竖立 · Down 倒平(弹跳落地) · Recovering 半竖 + 环形倒计时。
## 重装限制(M04F05):板身红晕 + 浮 🚫,不播推板动画。
## 对外契约不变:setup / set_state / set_highlight / set_locked_for_heavy / is_standing
## battle_root 读 `position`(Vector2)与 `state`。

class_name Pallet
extends Node

enum State { STANDING, DOWN, RECOVERING }

const RECOVER_TIME_S := 20.0       # KNOB_pallet_respawn(A0001M15F01-6)
const BOARD_W := 1.35              # 板宽(世界单位)

var pallet_id: int = 0
var kind: String = MapData.PALLET_CONG
var state: int = State.STANDING
var recover_elapsed: float = 0.0
var highlighted := false

var position: Vector2 = Vector2.ZERO:
	set(v):
		position = v
		if _rig != null:
			_rig.position = Vector3(v.x, 0.0, v.y)

var _rig: Node3D = null
var _board: Node3D = null           # 菜板模型(绕根部翻转)
var _tilt: Node3D = null            # 翻转轴
var _ring: MeshInstance3D = null    # 复位环形倒计时
var _hint: Label3D = null
var _ban: Label3D = null
var _base_y := 0.0
var _locked := false


func setup(p_id: int, p_kind: String, pos: Vector2) -> void:
	pallet_id = p_id
	kind = p_kind
	_rig = Node3D.new()
	add_child(_rig)
	position = pos

	var color := Color(0.62, 0.85, 0.48) if kind == MapData.PALLET_CONG \
		else Color(0.95, 0.82, 0.48)

	# 菜板:模型立起来当门板;翻转轴在根部
	_tilt = Node3D.new()
	_rig.add_child(_tilt)
	_board = Fx3D.instance("res://assets/props/cutting-board-japanese.glb")
	var bb := Fx3D.fit_width(_board, BOARD_W)
	# 平放模型 → 立起:绕 X 转 -90°,板面朝向玩家来向
	_board.rotation.x = -PI / 2.0
	_board.position = Vector3(0.0, bb.size.z * 0.5 + 0.05, 0.0)
	_tilt.add_child(_board)
	# 染色(葱绿/姜黄):整板轻着色
	_tint(_board, color)

	# 底部阴影 + 常亮足迹
	_rig.add_child(Fx3D.ground_blob(0.7, 0.25))

	# 复位倒计时环
	_ring = Fx3D.ring(0.8, Color(1.0, 0.9, 0.5, 0.9), 0.13)
	_ring.visible = false
	_rig.add_child(_ring)

	# 情境提示
	_hint = Fx3D.label3d("推板")
	_hint.position = Vector3(0, 1.5, 0)
	_hint.visible = false
	_rig.add_child(_hint)
	_ban = Fx3D.label3d("🚫", 56, Color(1, 0.5, 0.45))
	_ban.position = Vector3(0, 1.5, 0)
	_ban.visible = false
	_rig.add_child(_ban)


func _tint(n: Node3D, color: Color) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		(mi as MeshInstance3D).material_override = m


## 万能键是情境键 —— 走近了必须告诉玩家「按下去会推板」(A0001M12F06)
func set_highlight(on: bool) -> void:
	if highlighted == on:
		return
	highlighted = on
	if _hint != null:
		_hint.visible = on and not _locked and state == State.STANDING
	if _ban != null:
		_ban.visible = on and _locked and state == State.STANDING


func set_state(s: int) -> void:
	if state == s:
		return
	state = s
	recover_elapsed = 0.0
	if _tilt == null:
		return
	var tw := _tilt.create_tween()
	match s:
		State.DOWN:
			# 推倒:弹跳落地
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
			tw.tween_property(_tilt, "rotation:x", PI / 2.0 * 0.94, 0.5)
		State.RECOVERING:
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(_tilt, "rotation:x", PI / 2.0 * 0.55, 0.4)
		_:
			# 立起
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(_tilt, "rotation:x", 0.0, 0.35)
	if _ring != null:
		_ring.visible = s == State.RECOVERING


func set_locked_for_heavy(locked: bool) -> void:
	_locked = locked
	if _hint != null:
		_hint.visible = highlighted and not locked and state == State.STANDING
	if _ban != null:
		_ban.visible = highlighted and locked and state == State.STANDING


func is_standing() -> bool:
	return state == State.STANDING


func _process(delta: float) -> void:
	if state == State.RECOVERING and _ring != null:
		recover_elapsed += delta
		Fx3D.ring_set(_ring, clampf(recover_elapsed / RECOVER_TIME_S, 0.0, 1.0))
