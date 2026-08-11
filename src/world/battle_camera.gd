## battle_camera.gd — 2.5D 跟随相机(3D 版,A0001M10)
## 逃跑吧少年式拍法:正交投影 + 固定俯角 55°,只平移不转向。
## - 视野短边 = k × √面积(Agar.io 口径,连续):Sim.camera_view_diameter_for_area
## - zoom(正交 size)连续跟随面积 + 0.4s 阻尼;位置指数平滑 ≈ 8
## - 屏上锚点:目标在屏高约 44%(v_offset,给底部摇杆让位,M06F02)
## - 对外契约不变:setup(target) / update_area(area_permyriad)
##   target 可以是任何带 `position: Vector2`(世界单位)的对象(Character 包装节点)。

class_name BattleCamera
extends Node3D

const ZOOM_DAMP_S := 0.4
const SMOOTH_SPEED := 8.0
const PITCH_DEG := 55.0            # 俯角(和胡闹厨房同一档)
const CAM_DIST := 60.0             # 正交投影下距离只影响裁剪,取够远即可

var target = null                  # 鸭子类型:读 .position (Vector2)
var _cam: Camera3D = null
var _size_target := 14.0
var _size_current := 14.0
var _follow := Vector3.ZERO
var _snapped := false


func setup(p_target) -> void:
	target = p_target
	if _cam == null:
		_cam = Camera3D.new()
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.near = 1.0
		_cam.far = 220.0
		add_child(_cam)
	_size_target = Sim.camera_view_diameter_for_area(1000)
	_size_current = _size_target
	_follow = _target_pos3()
	_snapped = false
	_apply()
	_cam.make_current()


## 连续跟随面积(Agar.io 口径);实际变化走 _process 的 0.4s 阻尼
func update_area(area_permyriad: int) -> void:
	_size_target = Sim.camera_view_diameter_for_area(area_permyriad)


func _target_pos3() -> Vector3:
	if target == null:
		return Vector3(24.0, 0.0, 24.0)
	var p: Vector2 = target.position
	return Vector3(p.x, 0.0, p.y)


func _process(delta: float) -> void:
	if target == null or _cam == null:
		return
	# 0.4s 阻尼 zoom
	_size_current = lerpf(_size_current, _size_target, clampf(delta / ZOOM_DAMP_S, 0.0, 1.0))
	# 指数平滑跟随
	var goal := _target_pos3()
	if not _snapped:
		_follow = goal
		_snapped = true
	else:
		var k := 1.0 - exp(-SMOOTH_SPEED * delta)
		_follow = _follow.lerp(goal, k)
	_apply()


func _apply() -> void:
	# 相机从目标正南(2D 的 +y / 3D 的 +z)后上方俯视,只平移不转向。
	var pitch := deg_to_rad(PITCH_DEG)
	var back := Vector3(0.0, sin(pitch), cos(pitch)) * CAM_DIST
	_cam.global_position = _follow + back
	_cam.look_at(_follow, Vector3.UP)
	_cam.size = maxf(4.0, _size_current)
	# 锚点偏上:把目标推到屏高 ~44%(正交 size 是竖直可视范围,6% 即 0.06×size)
	_cam.v_offset = -_size_current * 0.06


## HUD 需要世界→屏幕投影时用(名牌/罗盘)
func unproject(world: Vector3) -> Vector2:
	if _cam == null:
		return Vector2.ZERO
	return _cam.unproject_position(world)
