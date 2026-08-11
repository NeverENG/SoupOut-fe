## stir.gd — 搅一搅 3D 版(A0001M09F07,全图唯一动态机制)
## 客户端只做预告与表现;推人/刮除/飞地化汤是服务端权威(A0001M15F03-4)。
## 时序(M09F07 预告表):T−3s 大汤勺悬停 + 半透预警带闪烁 → T=0 沿弧线扫过。
## 正式美术:巨型汤勺模型(Kenney Food Kit cooking-spoon,CC0)+ 地面弧形预警带。
## 对外契约不变:setup() / tick(delta) / announce_warn(fire_tick, entry_angle, arc_span)
## HUD 读 `next_stir_at`。

class_name Stir
extends Node3D

const STIR_INTERVAL_S := 45.0      # KNOB_stir_interval(A0001M15F01-7)
const WARN_LEAD_S := 3.0           # T−3s 预告
const SWEEP_DURATION_S := 2.5
const BAND_WIDTH := 1.5            # 带宽(世界单位)

var next_stir_at := STIR_INTERVAL_S
var warn_elapsed := 0.0
var sweeping := false
var sweep_t := 0.0
var sweep_entry_angle := 0.0       # 汤勺入场角(服务端权威下发;客户端本地轮转兜底)

var _warn_band: MeshInstance3D = null
var _band_mat: StandardMaterial3D = null
var _ladle: Node3D = null
var _ladle_model: Node3D = null


func setup() -> void:
	# 预警带:弧形贴地网格(announce_warn 时重建形状)
	_warn_band = MeshInstance3D.new()
	_band_mat = Fx3D.mat_unshaded(Color(1.0, 0.9, 0.6, 0.25))
	_warn_band.material_override = _band_mat
	_warn_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warn_band.position.y = 0.04
	_warn_band.visible = false
	add_child(_warn_band)
	_build_warn_band(0.0, PI)

	# 巨型汤勺:从天而降的厨师之手(胡闹厨房既视感的主角)
	_ladle = Node3D.new()
	_ladle.visible = false
	add_child(_ladle)
	_ladle_model = Fx3D.instance("res://assets/props/cooking-spoon.glb")
	# 勺模型是平放的(长轴 = x,厚度 y 仅 0.024),按最长边定尺寸
	Fx3D.fit_length(_ladle_model, 9.0)          # 勺长 ≈ 9 单位,巨物感
	# 绕 Z 抬起 70°:勺柄指天、勺头朝下探进汤里(留 20° 前倾)
	_ladle_model.rotation = Vector3(0.0, 0.0, deg_to_rad(70.0))
	_ladle_model.position = Vector3(0.0, 3.2, 0.0)
	_ladle.add_child(_ladle_model)


## 服务端下发 StirWarn 时调用(entry_angle 为权威值,T0005M14F02-2)
func announce_warn(fire_tick: int, entry_angle: int, arc_span: int) -> void:
	sweep_entry_angle = Fixed.uint16_to_angle(entry_angle)
	next_stir_at = 0.0
	warn_elapsed = 0.0
	var arc := float(arc_span) / 65536.0 * TAU
	_build_warn_band(sweep_entry_angle, arc)


## 弧形预警带网格(内外双圈三角带)
func _build_warn_band(entry: float, arc: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := MapData.CENTER
	var steps := 32
	var outer := MapData.POT_RADIUS * 0.85
	var inner := outer - BAND_WIDTH
	for i in range(steps):
		var a0 := entry + arc * i / steps
		var a1 := entry + arc * (i + 1) / steps
		var o0 := Vector3(c.x + cos(a0) * outer, 0, c.y + sin(a0) * outer)
		var o1 := Vector3(c.x + cos(a1) * outer, 0, c.y + sin(a1) * outer)
		var i0 := Vector3(c.x + cos(a0) * inner, 0, c.y + sin(a0) * inner)
		var i1 := Vector3(c.x + cos(a1) * inner, 0, c.y + sin(a1) * inner)
		for v in [o0, o1, i1, o0, i1, i0]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	_warn_band.mesh = st.commit()


## 每帧推进(battle_root 驱动)
func tick(delta: float) -> void:
	next_stir_at -= delta
	if not sweeping and next_stir_at <= WARN_LEAD_S and next_stir_at > 0.0:
		# T−3s 预告期:预警带闪烁 + 勺子悬停入场位
		warn_elapsed += delta
		_warn_band.visible = true
		_band_mat.albedo_color.a = 0.15 + 0.15 * absf(sin(warn_elapsed * 4.0))
		_ladle.visible = true
		_place_ladle(sweep_entry_angle, 2.2 + sin(warn_elapsed * 3.0) * 0.3)
	elif next_stir_at <= 0.0:
		# 扫过阶段
		sweeping = true
		sweep_t += delta
		_warn_band.visible = false
		_animate_ladle()
		if sweep_t >= SWEEP_DURATION_S:
			sweeping = false
			sweep_t = 0.0
			next_stir_at = STIR_INTERVAL_S
			_ladle.visible = false
	else:
		_warn_band.visible = false


func _place_ladle(a: float, hover_h: float) -> void:
	var c := MapData.CENTER
	var r := MapData.POT_RADIUS * 0.85 - BAND_WIDTH * 0.5
	_ladle.position = Vector3(c.x + cos(a) * r, hover_h, c.y + sin(a) * r)
	# 勺柄朝外(背向锅心),沿切向前进
	_ladle.rotation.y = -a


func _animate_ladle() -> void:
	# 沿预警弧扫半圈:勺头压进汤里,推着浪走
	var t := clampf(sweep_t / SWEEP_DURATION_S, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var a := sweep_entry_angle + PI * eased
	# 入水 → 拖行 → 抬起
	var dip := sin(clampf(t * PI, 0.0, PI)) * 2.4
	_place_ladle(a, 2.4 - dip)
	_ladle.visible = true
