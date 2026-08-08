## vault.gd — 翻窗（A0001M09F05 / M12F06）
## 重装惩罚：越重翻越慢（非锁死）；窗框常亮描边（远处就能看见）；翻越时窗框走一圈进度描边。
## 占位：圆环（漏勺孔）/ 半月（锅耳）。

class_name Vault
extends Node2D

var vault_id: int = 0
var kind: String = MapData.VAULT_LOUSHAO
var _ring: Polygon2D = null
var _progress_ring: Polygon2D = null
var _progress := 0.0
var active := false


func setup(v_id: int, p_kind: String, pos: Vector2) -> void:
	vault_id = v_id
	kind = p_kind
	position = pos
	_ring = _make_ring(0.55, 0.06, Color(0.9, 0.85, 0.7, 0.9))
	_ring.outline_color = Color(1.0, 0.95, 0.8)   # 常亮描边
	add_child(_ring)
	_progress_ring = _make_ring(0.55, 0.10, Color(0.98, 0.9, 0.5, 0.0))
	add_child(_progress_ring)
	z_index = 4


func _make_ring(radius: float, width: float, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(32):
		var a := TAU * i / 32.0
		pts.append(Vector2(cos(a), sin(a)) * (radius + width / 2))
		inner.append(Vector2(cos(a), sin(a)) * (radius - width / 2))
	# 环 = 外多边形 - 内多边形（简化：用双圈近似）
	poly.polygon = pts
	poly.color = color
	poly.outline_size = 2
	poly.outline_color = color
	return poly


## 翻越进度（0..1），active 时显示进度描边（M12F06）
func set_progress(p: float) -> void:
	_progress = clampf(p, 0.0, 1.0)
	active = _progress > 0.0 and _progress < 1.0
	if _progress_ring != null:
		_progress_ring.color.a = 0.7 if active else 0.0
		_progress_ring.rotation = -PI / 2 + _progress * TAU
