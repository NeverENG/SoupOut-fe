## territory_renderer.gd — 地盘场渲染器 3D 版(T0005M07F05 / M07F03)
## - 数据契约不变:一张 RGBA8 96×96 纹理,R/G/B/A = 玩家 1/2/3/4 覆盖度 0..255;
##   原汤四通道全零;150ms 漫开渐变在 CPU 侧;predOverlay 调制同一张纹理。
## - 表现改为 3D:48×48 PlaneMesh 汤面 + territory_3d.gdshader(世界空间图案)。
## - get_texture() 继续供小地图使用(同一张 ImageTexture,白送)。
## - ⚠️ field 采样 Linear(平滑有机边界),在 shader 里声明,与 2D 版一致。

class_name TerritoryRenderer
extends Node3D

const GRID := Fixed.GRID
## 覆盖度满值。**必须是 255**(PackedByteArray,写 256 会回绕成 0)。
const CELL_TEX := 255
const ANIM_MS := 150.0           # 漫开时长(T0001M03F08)
## 原汤 = 四通道**全零**(shader 判定 total < 0.25 → 原汤)。
const BROTH_LEVEL := 0

var grid: TerritoryGrid = null
var _image := Image.create(GRID, GRID, false, Image.FORMAT_RGBA8)
var _texture: ImageTexture = null
var _anim_value := PackedByteArray()   # 9216×4
var _target_value := PackedByteArray() # 9216×4
var _plane: MeshInstance3D = null
var _mat: ShaderMaterial = null

var _elapsed_ms := 0.0


func _init() -> void:
	_anim_value.resize(GRID * GRID * 4)
	_target_value.resize(GRID * GRID * 4)


func setup(p_grid: TerritoryGrid) -> void:
	grid = p_grid
	_texture = ImageTexture.create_from_image(_image)
	_plane = MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	# 96×96 格 → 48×48 世界单位;平面中心 = 锅心 (24, 24)
	mesh.size = Vector2(float(Fixed.WORLD_SIZE), float(Fixed.WORLD_SIZE))
	_plane.mesh = mesh
	_plane.position = Vector3(Fixed.WORLD_SIZE / 2.0, 0.0, Fixed.WORLD_SIZE / 2.0)
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/world/territory_3d.gdshader")
	# 关键:shader 读 `uniform sampler2D field`,必须显式喂纹理,
	# 否则采样到空贴图 → 四通道恒 0 → 全锅判成原汤。
	_mat.set_shader_parameter("field", _texture)
	_plane.material_override = _mat
	add_child(_plane)
	_rebuild_all()


func get_texture() -> ImageTexture:
	return _texture


func _process(delta: float) -> void:
	if grid == null:
		return
	_elapsed_ms += delta * 1000.0
	# 1) 更新目标值(权威 + 预测叠加)
	_recompute_targets()
	# 2) 渐变动画
	var dirty := false
	for i in range(GRID * GRID):
		for ch in range(4):
			var idx := i * 4 + ch
			var cur: int = _anim_value[idx]
			var target: int = _target_value[idx]
			if cur != target:
				# 150ms 线性逼近(简化:一步到位分段,视觉等效)
				var step_n := maxi(1, int(256.0 * delta * 1000.0 / ANIM_MS))
				if absi(target - cur) <= step_n:
					_anim_value[idx] = target
				else:
					_anim_value[idx] = cur + step_n if target > cur else cur - step_n
				dirty = true
	# 3) 上传(只在 dirty 时,M12 预算)
	if dirty:
		_upload()
	mat_set_anim_time()


func _recompute_targets() -> void:
	for y in range(GRID):
		for x in range(GRID):
			var i := y * GRID + x
			var owner := grid.render_owner_at(i)   # authGrid + 存活 predOverlay
			for ch in range(4):
				var chan := CELL_TEX if (ch + 1) == owner and owner <= 4 else 0
				if owner == TerritoryGrid.BROTH:
					chan = BROTH_LEVEL
				_target_value[i * 4 + ch] = chan


func _rebuild_all() -> void:
	# 初始全量:直接写死目标值(开局无漫开)
	for y in range(GRID):
		for x in range(GRID):
			var i := y * GRID + x
			var owner := grid.render_owner_at(i)
			for ch in range(4):
				var v := 0
				if owner == TerritoryGrid.BROTH:
					v = BROTH_LEVEL
				elif owner == ch + 1:
					v = CELL_TEX
				_anim_value[i * 4 + ch] = v
	_upload()


func _upload() -> void:
	for i in range(GRID * GRID):
		_image.set_pixel(i % GRID, i / GRID,
			Color(_anim_value[i * 4] / 255.0, _anim_value[i * 4 + 1] / 255.0,
				_anim_value[i * 4 + 2] / 255.0, _anim_value[i * 4 + 3] / 255.0))
	_texture.update(_image)


func mat_set_anim_time() -> void:
	if _mat != null:
		_mat.set_shader_parameter("anim_time", _elapsed_ms / 1000.0)
