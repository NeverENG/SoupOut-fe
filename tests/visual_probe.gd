## visual_probe.gd — 3D 表现层视觉冒烟(开发期工具,不进正式包)
## 不依赖 net/proto 编解码:直接用 MapData + 假数据把整个战场搭出来,
## 拍多角度截图到 user://probe_*.png 后退出。用法:
##   xvfb-run godot --path . res://tests/visual_probe.tscn

extends Node3D

var _frame := 0
var _grid: TerritoryGrid = null
var _renderer: TerritoryRenderer = null
var _cam: BattleCamera = null
var _chars: Array = []
var _shot := 0

const P_COLORS := [
	Color(0.949, 0.565, 0.608), Color(0.180, 0.604, 0.525),
	Color(1.0, 0.824, 0.118), Color(0.545, 0.361, 0.839)]
const P_DARKS := [
	Color(0.753, 0.337, 0.416), Color(0.090, 0.369, 0.322),
	Color(0.780, 0.588, 0.000), Color(0.337, 0.200, 0.580)]


func _ready() -> void:
	EnvBuilder.build(self)

	# 地盘:四角各铺一大块 + 中间犬牙交错
	_grid = TerritoryGrid.new()
	for y in range(96):
		for x in range(96):
			var i := y * 96 + x
			if _grid.auth_grid[i] == TerritoryGrid.OUTSIDE:
				continue
			var q := (0 if x < 48 else 1) + (0 if y < 48 else 2)
			var d := Vector2(x - 48, y - 48).length()
			if d < 38 and d > 14 and randf() < 0.55:
				_grid.auth_grid[i] = q + 1
			elif d >= 38:
				_grid.auth_grid[i] = q + 1
	_renderer = TerritoryRenderer.new()
	_renderer.setup(_grid)
	add_child(_renderer)

	# 地形
	var map: Dictionary = MapData.build_map(1)
	for w in map.walls:
		var wall := TerrainWall.new()
		wall.setup(w)
		add_child(wall)
	for p in map.pallets:
		var pallet := Pallet.new()
		pallet.setup(p.id, p.kind, Vector2(p.x, p.y))
		add_child(pallet)
	for v in map.vaults:
		var vault := Vault.new()
		vault.setup(v.id, v.kind, Vector2(v.x, v.y), v.get("angle", 0.0))
		add_child(vault)

	var stir := Stir.new()
	stir.setup()
	stir.next_stir_at = 2.5   # 快进到预告期,截图能拍到大勺
	add_child(stir)

	# 四个角色:不同状态
	for k in range(4):
		var ch := Character.new()
		ch.setup(k + 1, k, P_COLORS[k], P_DARKS[k], "玩家%d" % (k + 1), k == 0)
		add_child(ch)
		var spawn: Dictionary = map.spawns[k]
		ch.set_visual_state(Vector2(spawn.x, spawn.y), spawn.angle,
			(MsgIds.FLAG_CHARGING if k == 1 else 0) | (MsgIds.FLAG_WINDUP if k == 2 else 0),
			100 - k * 25, 1000 + k * 1200, 0)
		if k == 1:
			ch.set_charge_ring(true, 0.6)
		if k == 3:
			ch.set_leader(true)
		_chars.append(ch)
	_chars[0].set_in_reach(true)

	# 道具
	for d in range(4):
		var drop := Drop.new()
		var a := TAU * d / 4.0 + 0.5
		drop.setup(d, d, Vector2(24, 24) + Vector2(cos(a), sin(a)) * 7.0)
		add_child(drop)

	# 相机跟第一个角色
	_cam = BattleCamera.new()
	add_child(_cam)
	_cam.setup(_chars[0])


func _process(_delta: float) -> void:
	_frame += 1
	# 让角色 0 小跑一段,驱动跑动动画
	if _frame < 40:
		var c: Character = _chars[0]
		c.position = c.position + Vector2(0.06, -0.03)
	match _frame:
		45:
			_snap("probe_gameplay")
		50:
			_cam.update_area(6000)   # 拉远
		110:
			_snap("probe_zoomout")
		115:
			# 俯瞰全场(先停掉跟随相机,否则每帧被 _apply 抢回去)
			_cam.set_process(false)
			var cam3d := get_viewport().get_camera_3d()
			cam3d.size = 58.0
			cam3d.v_offset = 0.0
			cam3d.global_position = Vector3(24, 60, 52)
			cam3d.look_at(Vector3(24, 0, 22))
		125:
			_snap("probe_overview")
		130:
			get_tree().quit(0)


func _snap(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % tag)
	print("SNAP ", tag, " ", img.get_width(), "x", img.get_height())
