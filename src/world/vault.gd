## vault.gd — 翻窗 3D 版(A0001M09F05 / M12F06)
## 「从藕孔翻过去」:藕片 = 竖立的白玉环(藕白暖色,带一圈小孔),锅耳 = 铜色半环。
## 窗框常亮,走近高亮 + 浮「翻窗」;翻越时头顶进度环走一圈(重装翻更慢,非锁死)。
## 对外契约不变:setup(v_id, kind, pos) / set_highlight(on) / set_progress(p)
## battle_root 读 `position`(Vector2)。

class_name Vault
extends Node

var vault_id: int = 0
var kind: String = MapData.VAULT_LOUSHAO
var active := false
var highlighted := false

var position: Vector2 = Vector2.ZERO:
	set(v):
		position = v
		if _rig != null:
			_rig.position = Vector3(v.x, 0.0, v.y)

var _rig: Node3D = null
var _frame: Node3D = null            # 窗框(竖立环)
var _ring_mesh: MeshInstance3D = null
var _progress_ring: MeshInstance3D = null
var _hint: Label3D = null
var _progress := 0.0
var _angle := 0.0


func setup(v_id: int, p_kind: String, pos: Vector2, p_angle: float = 0.0) -> void:
	vault_id = v_id
	kind = p_kind
	_angle = p_angle
	_rig = Node3D.new()
	add_child(_rig)
	position = pos

	var is_lotus := kind == MapData.VAULT_LOTUS
	var main := Color(0.98, 0.94, 0.88) if is_lotus else Color(0.82, 0.58, 0.34)

	# 窗框:竖立的环。抬到墙高中心,孔轴沿墙法向(玩家从孔里钻过去)。
	_frame = Node3D.new()
	_frame.position = Vector3(0.0, TerrainWall.WALL_HEIGHT * 0.62, 0.0)
	_rig.add_child(_frame)
	_ring_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.62
	_ring_mesh.mesh = torus
	var m := Fx3D.mat(main, 0.05, 0.7)
	m.emission_enabled = true
	m.emission = main * 0.12
	_ring_mesh.material_override = m
	# TorusMesh 孔轴 = +Y → 竖起(绕 X 转 90°),再按墙角度对孔轴定向
	_ring_mesh.rotation = Vector3(PI / 2.0, atan2(cos(_angle), sin(_angle)), 0.0)
	_frame.add_child(_ring_mesh)

	if is_lotus:
		# 藕孔:环内一圈小珠(远处也认得出是藕片)
		for i in range(6):
			var a := TAU * i / 6.0
			var pearl := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.07
			sm.height = 0.14
			pearl.mesh = sm
			pearl.material_override = Fx3D.mat(Color(0.93, 0.86, 0.78), 0.0, 0.8)
			var dir3 := Vector3(cos(_angle), 0.0, sin(_angle))
			var tang := Vector3(-dir3.z, 0.0, dir3.x)
			pearl.position = (tang * cos(a) + Vector3.UP * sin(a)) * 0.42
			_frame.add_child(pearl)

	# 脚下:足迹光斑(常亮,远处能看见「这有个窗」)
	var mark := Fx3D.ring(0.55, Color(1.0, 0.95, 0.8, 0.4), 0.1)
	Fx3D.ring_set(mark, 1.0)
	_rig.add_child(mark)

	# 翻越进度环(头顶)
	_progress_ring = Fx3D.ring(0.7, Color(0.98, 0.9, 0.5, 0.0), 0.14)
	_progress_ring.position.y = TerrainWall.WALL_HEIGHT + 0.55
	_rig.add_child(_progress_ring)

	# 情境提示
	_hint = Fx3D.label3d("翻窗")
	_hint.position = Vector3(0, TerrainWall.WALL_HEIGHT + 1.0, 0)
	_hint.visible = false
	_rig.add_child(_hint)


## 万能键是情境键 —— 走近了必须告诉玩家「按下去会翻窗」(A0001M12F06)
func set_highlight(on: bool) -> void:
	if highlighted == on:
		return
	highlighted = on
	if _hint != null:
		_hint.visible = on
	if _ring_mesh != null:
		var m := _ring_mesh.material_override as StandardMaterial3D
		if m != null:
			m.emission = (m.albedo_color * (0.55 if on else 0.12))


## 翻越进度(0..1),active 时显示进度环(M12F06)
func set_progress(p: float) -> void:
	_progress = clampf(p, 0.0, 1.0)
	active = _progress > 0.0 and _progress < 1.0
	if _progress_ring != null:
		Fx3D.ring_set(_progress_ring, _progress,
			Color(0.98, 0.9, 0.5, 0.85 if active else 0.0))
