## stir.gd — 搅一搅（A0001M09F07，全图唯一动态机制）
## 客户端只做预告与表现；推人/刮除/飞地化汤是服务端权威（A0001M15F03-4）。
## 时序（M09F07 预告表）：T−3s 勺子影子+半透预警带 → T−1s 预警带变实+起波 → T=0 扫过
## 入场位按 90° 轮转（P1→P2→P3→P4），轨迹从锅沿进入掠过锅心外缘从相邻 90° 穿出。
## 占位视觉：半透弧形预警带（Polygon2D）+ 汤勺（圆+柄）。正式资产：fx_stir_warnband / env_stir_ladle。

class_name Stir
extends Node2D

const STIR_INTERVAL_S := 45.0      # KNOB_stir_interval（A0001M15F01-7）
const WARN_LEAD_S := 3.0           # T−3s 预告
const SWEEP_DURATION_S := 2.5
const BAND_WIDTH := 1.5            # 带宽（世界单位）

var next_stir_at := STIR_INTERVAL_S
var warn_elapsed := 0.0            # 进入 T−3s 后的计时
var sweeping := false
var sweep_t := 0.0
var sweep_entry_angle := 0.0       # 汤勺入场角（服务端权威下发；客户端本地轮转兜底）

var _warn_band: Polygon2D = null
var _ladle: Node2D = null
var _ladle_pos := Vector2.ZERO


func setup() -> void:
	_warn_band = Polygon2D.new()
	_warn_band.color = Color(1.0, 0.9, 0.6, 0.25)
	add_child(_warn_band)
	_ladle = Node2D.new()
	var handle := Polygon2D.new()
	handle.polygon = PackedVector2Array([
		Vector2(-1.6, -0.12), Vector2(1.6, -0.12), Vector2(1.6, 0.12), Vector2(-1.6, 0.12)])
	handle.color = Color(0.65, 0.5, 0.35)
	_ladle.add_child(handle)
	var bowl := _circle(0.5, Color(0.6, 0.45, 0.3))
	bowl.position = Vector2(1.4, 0.0)
	_ladle.add_child(bowl)
	_ladle.visible = false
	add_child(_ladle)
	z_index = 3


func _circle(r: float, c: Color) -> Polygon2D:
	var p := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(24):
		var a := TAU * i / 24.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	p.polygon = pts
	p.color = c
	return p


## 服务端下发 StirWarn 时调用（entry_angle 为权威值，T0005M14F02-2）
func announce_warn(fire_tick: int, entry_angle: int, arc_span: int) -> void:
	sweep_entry_angle = Fixed.uint16_to_angle(entry_angle)
	next_stir_at = 0.0
	warn_elapsed = 0.0
	# 预警带：以 entry 角为起点扫 arc_span 弧
	var arc := float(arc_span) / 65536.0 * TAU
	_build_warn_band(sweep_entry_angle, arc)


func _build_warn_band(entry: float, arc: float) -> void:
	var pts := PackedVector2Array()
	var c := MapData.CENTER
	var steps := 24
	var outer := MapData.POT_RADIUS * 0.85
	var inner := MapData.POT_RADIUS * 0.85 - BAND_WIDTH
	for i in range(steps + 1):
		var a := entry + arc * i / steps
		pts.append(c + Vector2(cos(a), sin(a)) * outer)
	for i in range(steps + 1):
		var a := entry + arc * (steps - i) / steps
		pts.append(c + Vector2(cos(a), sin(a)) * inner)
	_warn_band.polygon = pts


## 每帧推进（battle_root 驱动）
func tick(delta: float) -> void:
	next_stir_at -= delta
	if not sweeping and next_stir_at <= WARN_LEAD_S and next_stir_at > 0.0:
		# T−3s 预告期：预警带闪烁 + 勺子影子
		warn_elapsed += delta
		_warn_band.visible = true
		_warn_band.color.a = 0.15 + 0.15 * absf(sin(warn_elapsed * 4.0))
		_ladle.visible = true
		var c := MapData.CENTER
		_ladle_pos = c + Vector2(cos(sweep_entry_angle), sin(sweep_entry_angle)) * (MapData.POT_RADIUS + 1.5)
		_ladle.position = _ladle_pos
		_ladle.rotation = sweep_entry_angle + PI / 2
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


func _animate_ladle() -> void:
	# 占位：从锅沿沿弧线移到对侧
	var c := MapData.CENTER
	var a0 := sweep_entry_angle
	var a1 := a0 + PI
	var t := clampf(sweep_t / SWEEP_DURATION_S, 0.0, 1.0)
	var r := lerpf(MapData.POT_RADIUS + 1.5, MapData.POT_RADIUS + 1.5, t)
	var a := lerpf(a0, a1, t)
	_ladle.position = c + Vector2(cos(a), sin(a)) * r
	_ladle.rotation = a + PI / 2
	_ladle.visible = true
