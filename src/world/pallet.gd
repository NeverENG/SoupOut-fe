## pallet.gd — 板子（A0001M09F05 / M12F06）
## 三态：Standing / Down / Recovering（KNOB_pallet_respawn 后自动立起，A0001M15F01-6）
## 重装限制可读性（M04F05 落地，否则被当 bug）：板身叠锁链纹 + 半透红；接近时浮 🚫，
## 不播推板动画、正常擦过。占位：葱段=绿色圆段，姜片=浅黄圆段。
## 正式资产：assets/temp/ter/ter_pallet_cong_{standing,down,recovering}.png

class_name Pallet
extends Node2D

enum State { STANDING, DOWN, RECOVERING }

const RECOVER_TIME_S := 20.0       # KNOB_pallet_respawn（A0001M15F01-6）

var pallet_id: int = 0
var kind: String = MapData.PALLET_CONG
var state: int = State.STANDING
var recover_elapsed: float = 0.0

var _body: Polygon2D = null
var _lock_icon: Polygon2D = null
var _ban_icon: Label = null
var _ring: Polygon2D = null         # 复位环形倒计时


func setup(p_id: int, p_kind: String, pos: Vector2) -> void:
	pallet_id = p_id
	kind = p_kind
	position = pos
	var color := Color(0.55, 0.78, 0.42) if kind == MapData.PALLET_CONG else Color(0.9, 0.78, 0.45)
	_body = _make_rect(Vector2(0.9, 0.22), color)
	add_child(_body)
	# 锁链纹占位：半透红斜纹（重装禁用提示）
	_lock_icon = _make_rect(Vector2(0.9, 0.22), Color(0.8, 0.2, 0.2, 0.35))
	_lock_icon.visible = false
	add_child(_lock_icon)
	_ban_icon = Label.new()
	_ban_icon.text = "🚫"
	_ban_icon.position = Vector2(-16, -40)
	_ban_icon.visible = false
	add_child(_ban_icon)
	z_index = 4


func _make_rect(size: Vector2, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-size.x / 2, -size.y / 2), Vector2(size.x / 2, -size.y / 2),
		Vector2(size.x / 2, size.y / 2), Vector2(-size.x / 2, size.y / 2),
	])
	poly.color = color
	poly.outline_size = 3
	poly.outline_color = Color(0.3, 0.22, 0.15)
	return poly


func set_state(s: int) -> void:
	state = s
	_body.rotation = 0.0 if s == State.STANDING else PI / 2   # 倒下横躺
	_body.color = Color(0.55, 0.78, 0.42) if s == State.STANDING else Color(0.45, 0.6, 0.35)
	if s == State.RECOVERING:
		recover_elapsed = 0.0


func set_locked_for_heavy(locked: bool) -> void:
	_lock_icon.visible = locked
	_ban_icon.visible = locked


func _process(delta: float) -> void:
	if state == State.RECOVERING:
		recover_elapsed += delta
		# 环形倒计时占位：透明度渐变 + 微旋转
		_body.color.a = 0.5 + 0.5 * (recover_elapsed / RECOVER_TIME_S)
		if recover_elapsed >= RECOVER_TIME_S:
			set_state(State.STANDING)
			_body.color.a = 1.0


func is_standing() -> bool:
	return state == State.STANDING
