## territory_renderer.gd — 地盘场渲染器（T0005M07F05 / M07F03）
## - 一张 RGBA8 96×96 纹理 + 一个 quad（战场 1 draw call；小地图 = 同一材质贴小 quad，白送）
## - R/G/B/A = 玩家 1/2/3/4 覆盖度 0..255；原汤四通道全低；锅外 0（锅体遮罩）
## - 150ms 漫开：dirty 格的目标通道值渐变而非直接写死（掩盖 10Hz 离散感，T0001M03F08 ④）
## - predOverlay 直接调制到同一张纹理，与权威格视觉一致
## - ⚠️ 材质过滤覆盖为 Linear（A0001M06F01 全局 Nearest 的唯一例外）
## 表现层：extends Node2D，持有 TerritoryGrid（core）引用。

class_name TerritoryRenderer
extends Node2D

const GRID := Fixed.GRID
const CELL_TEX := 256.0          # 覆盖度满值
const ANIM_MS := 150.0           # 漫开时长（T0001M03F08）
const BROTH_LEVEL := 40          # 原汤四通道低覆盖度

var grid: TerritoryGrid = null
var _image := Image.create(GRID, GRID, false, Image.FORMAT_RGBA8)
var _texture: ImageTexture = null
var _anim_value := PackedByteArray()   # 9216×4
var _target_value := PackedByteArray() # 9216×4
var _flash := PackedByteArray()        # 9216×4（漫开瞬间闪亮色）
var _sprite: Sprite2D = null
var _prev_dirty_time := {}

var _elapsed_ms := 0.0


func _init() -> void:
	_anim_value.resize(GRID * GRID * 4)
	_target_value.resize(GRID * GRID * 4)
	_flash.resize(GRID * GRID * 4)


func setup(p_grid: TerritoryGrid) -> void:
	grid = p_grid
	_texture = ImageTexture.create_from_image(_image)
	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	# 96×96 格 → 48×48 世界单位
	_sprite.scale = Vector2(float(Fixed.WORLD_SIZE) / GRID, float(Fixed.WORLD_SIZE) / GRID)
	_sprite.position = Vector2(Fixed.WORLD_SIZE / 2.0, Fixed.WORLD_SIZE / 2.0)
	_sprite.centered = true
	var mat := ShaderMaterial.new()
	var shader := load("res://src/world/territory.gdshader")
	mat.shader = shader
	# ⚠️ 有意例外：field 纹理 Linear 过滤（平滑有机边界），全局是 Nearest（A0001M06F01）
	_sprite.material = mat
	add_child(_sprite)
	_rebuild_all()


func get_texture() -> ImageTexture:
	return _texture


func _process(delta: float) -> void:
	if grid == null:
		return
	_elapsed_ms += delta * 1000.0
	# 1) 更新目标值（权威 + 预测叠加）
	_recompute_targets()
	# 2) 渐变动画 + 闪亮
	var dirty := false
	for i in range(GRID * GRID):
		for ch in range(4):
			var idx := i * 4 + ch
			var cur: int = _anim_value[idx]
			var target: int = _target_value[idx]
			if cur != target:
				# 150ms 线性逼近（简化：一步到位分段，视觉等效）
				var step_n := maxi(1, int(256.0 * delta * 1000.0 / ANIM_MS))
				if absi(target - cur) <= step_n:
					_anim_value[idx] = target
				else:
					_anim_value[idx] = cur + step_n if target > cur else cur - step_n
				dirty = true
	# 3) 上传（只在 dirty 时，M12 预算）
	if dirty:
		_upload()
		mat_set_anim_time()


func _recompute_targets() -> void:
	for y in range(GRID):
		for x in range(GRID):
			var i := y * GRID + x
			var owner := grid.render_owner_at(i)   # authGrid + 存活 predOverlay
			var base := 0
			if owner == TerritoryGrid.OUTSIDE:
				base = 0
			elif owner == TerritoryGrid.BROTH:
				base = BROTH_LEVEL
			else:
				base = CELL_TEX
			for ch in range(4):
				var chan := CELL_TEX if (ch + 1) == owner and owner <= 4 else 0
				if owner == TerritoryGrid.BROTH:
					chan = BROTH_LEVEL
				_target_value[i * 4 + ch] = maxi(chan, base if owner == TerritoryGrid.BROTH else 0)


func _rebuild_all() -> void:
	# 初始全量：直接写死目标值（开局无漫开）
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
	if _sprite != null and _sprite.material is ShaderMaterial:
		(_sprite.material as ShaderMaterial).set_shader_parameter("anim_time", _elapsed_ms / 1000.0)
