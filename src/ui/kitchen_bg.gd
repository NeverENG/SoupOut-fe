## kitchen_bg.gd — flow 页面共用动态背景
## 暖色对角渐变 + 大圆斑点纹理 + 缓慢漂浮旋转的食材剪影(_draw 程序化,零素材)。
## dim > 0 时叠加暗化(对局后的结算页等)。

extends Control

var dim := 0.0

var _t := 0.0
var _items: Array = []   # {pos_n: Vector2(0..1), r, speed, phase, kind, tint}

const TOP := Color("a9713d")     # 暖褐(瓦罐汤面)
const BOTTOM := Color("6e4526")  # 深褐(罐底)
const KINDS := 5


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260808
	for i in range(14):
		_items.append({
			"pos_n": Vector2(rng.randf(), rng.randf()),
			"r": rng.randf_range(28.0, 76.0),
			"speed": rng.randf_range(0.05, 0.16) * (1.0 if i % 2 == 0 else -1.0),
			"phase": rng.randf() * TAU,
			"kind": i % KINDS,
			"tint": Color(1, 1, 1, rng.randf_range(0.05, 0.11)),
		})


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	# 渐变底(手绘四角插值:draw_polygon 支持逐顶点色)
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)])
	var cols := PackedColorArray([TOP, TOP.lerp(BOTTOM, 0.35), BOTTOM, BOTTOM.lerp(TOP, 0.35)])
	draw_polygon(pts, cols)
	# 大圆斑点(奶油泡泡感)
	for i in range(6):
		var a := float(i) / 6.0 * TAU + _t * 0.03
		var c := Vector2(s.x * (0.5 + 0.46 * cos(a)), s.y * (0.5 + 0.46 * sin(a * 1.3)))
		draw_circle(c, s.y * 0.22, Color(1, 1, 1, 0.035))
	# 漂浮食材剪影
	for it in _items:
		var base: Vector2 = it.pos_n
		var p := Vector2(
			s.x * base.x + sin(_t * it.speed * 3.0 + it.phase) * 40.0,
			s.y * base.y + cos(_t * it.speed * 2.2 + it.phase) * 30.0)
		var rot: float = _t * it.speed + it.phase
		_draw_food(p, it.r, rot, it.kind, it.tint)
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.15, 0.05, 0.02, dim))


func _draw_food(p: Vector2, r: float, rot: float, kind: int, tint: Color) -> void:
	draw_set_transform(p, rot, Vector2.ONE)
	match kind:
		0:  # 番茄:圆 + 叶
			draw_circle(Vector2.ZERO, r, tint)
			for i in range(4):
				var a := TAU * i / 4.0
				draw_circle(Vector2(cos(a), sin(a)) * r * 0.32 + Vector2(0, -r * 0.9),
					r * 0.18, tint)
		1:  # 蘑菇:帽 + 柄
			draw_circle(Vector2(0, -r * 0.2), r * 0.85, tint)
			draw_rect(Rect2(-r * 0.3, 0, r * 0.6, r * 0.8), tint)
		2:  # 玉米:胶囊
			draw_circle(Vector2(0, -r * 0.5), r * 0.42, tint)
			draw_circle(Vector2(0, r * 0.5), r * 0.42, tint)
			draw_rect(Rect2(-r * 0.42, -r * 0.5, r * 0.84, r), tint)
		3:  # 汤勺:柄 + 头
			draw_rect(Rect2(-r * 0.12, -r, r * 0.24, r * 1.2), tint)
			draw_circle(Vector2(0, r * 0.5), r * 0.5, tint)
		_:  # 白菜:叠圆
			draw_circle(Vector2.ZERO, r * 0.8, tint)
			draw_circle(Vector2(-r * 0.45, -r * 0.2), r * 0.5, tint)
			draw_circle(Vector2(r * 0.45, -r * 0.2), r * 0.5, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
