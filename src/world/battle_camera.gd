## battle_camera.gd — 跟随摄像机 + 按质量档位分级 zoom（A0001M10）
## - 跟随目标：自己的角色；屏上锚点 50%/44%（给两个摇杆让位，M06F02）
## - 视野短边高度 = N 个轻装角色直径：轻 11 / 中 13 / 重 15（≈1.0×→1.35×，往窄了调）
## - zoom 按三档质量离散驱动 + 档位边界 ±2% hysteresis 死区 + 0.4s 阻尼（M10F02）
## - 跟随阻尼 position_smoothing_speed ≈ 8，不做刚性跟随
## - 锅外可越过锅内壁（锅沿与灶台背景是画面的一部分），不做硬夹

class_name BattleCamera
extends Camera2D

const VIEW_DIAMETER := {"light": 11.0, "mid": 13.0, "heavy": 15.0}
const ZOOM_DAMP_S := 0.4
const HYSTERESIS_PERMYRIAD := 200    # ±2% 死区
const SMOOTH_SPEED := 8.0

var target: Node2D = null
var _current_zoom := 1.0
var _zoom_target := 1.0
var _tier := 0
var _area_permyriad := 1000


func setup(p_target: Node2D) -> void:
	target = p_target
	# 锚点：屏高 44%（屏幕偏上）→ 通过 offset 实现
	# Camera2D 默认居中，offset 把视野中心移到目标上方
	position_smoothing_enabled = true
	position_smoothing_speed = SMOOTH_SPEED
	make_current()
	_apply_zoom(Sim.camera_view_diameter(0))


func update_tier(area_permyriad: int) -> void:
	_area_permyriad = area_permyriad
	var tier := Sim.mass_tier(area_permyriad, 3500)
	# 档位边界 ±2% hysteresis（A0001M10F02：防镜头一直呼吸）
	var bounds := [[1500, 2200], [3000, 4200]]   # 轻/中、中/重 边界（±2% 已含）
	if tier != _tier:
		var crossed := false
		if tier > _tier:
			crossed = area_permyriad >= bounds[_tier][1]
		else:
			crossed = area_permyriad <= bounds[_tier][0]
		if crossed:
			_tier = tier
			_zoom_target = _diameter_to_zoom(Sim.camera_view_diameter(tier))


func _diameter_to_zoom(diameter: float) -> float:
	## 视野短边显示 diameter 个轻装直径（1.0u）→ zoom = 视口短边高度 / diameter
	var short_edge := mini(get_viewport_rect().size.x, get_viewport_rect().size.y)
	return short_edge / (diameter * 1.0)


func _apply_zoom(z: float) -> void:
	_zoom_target = z
	_current_zoom = z
	zoom = Vector2.ONE / _current_zoom


func _process(delta: float) -> void:
	if target == null:
		return
	# 0.4s 阻尼 zoom
	_current_zoom = lerpf(_current_zoom, _zoom_target, delta / ZOOM_DAMP_S)
	zoom = Vector2.ONE / _current_zoom
	# 锚点偏上：把视野中心放到目标上方（屏高 44% 处）
	var offset_y := get_viewport_rect().size.y * 0.06   # (0.5 - 0.44) * 屏高 → 目标在 44% 线
	position = target.position
	offset = Vector2(0, -offset_y)
