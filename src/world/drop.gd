## drop.gd — 道具掉落 3D 版(D0001M08)
## 正式美术:食材模型(Kenney Food Kit,CC0)悬浮旋转 + 汤色光环呼吸。
## 四种效果的模型/颜色一眼分得清 —— 抢点博弈的前提是「远远看见那是什么」:
##   润甜=蘑菇 · 护盾=洋葱(层层护体) · 加速=辣椒 · 瘦身=芹菜
## 对外契约不变:setup / play_taken / color_for / icon_for / label_for / kind。

class_name Drop
extends Node

const RUNTIAN := 0
const SHIELD := 1
const SPEED := 2
const SLIM := 3
const RADIUS := 0.45

var drop_id: int = 0
var kind: int = 0

var position: Vector2 = Vector2.ZERO:
	set(v):
		position = v
		if _rig != null:
			_rig.position = Vector3(v.x, 0.0, v.y)

var _rig: Node3D = null
var _model: Node3D = null
var _halo: MeshInstance3D = null
var _phase := 0.0

const _MODELS := {
	RUNTIAN: "res://assets/props/mushroom.glb",
	SHIELD: "res://assets/props/onion.glb",
	SPEED: "res://assets/props/pepper.glb",
	SLIM: "res://assets/props/celery-stick.glb",
}


static func color_for(k: int) -> Color:
	match k:
		SHIELD: return Color(0.55, 0.78, 0.95)     # 护盾 冷蓝
		SPEED: return Color(0.98, 0.72, 0.30)      # 加速 橙
		SLIM: return Color(0.72, 0.92, 0.62)       # 瘦身 青绿
		_: return Color(0.98, 0.55, 0.72)          # 润甜 粉


static func icon_for(k: int) -> String:
	match k:
		SHIELD: return "🛡"
		SPEED: return "⚡"
		SLIM: return "🍃"
		_: return "🍯"


static func label_for(k: int) -> String:
	match k:
		SHIELD: return "护盾"
		SPEED: return "加速"
		SLIM: return "瘦身"
		_: return "润甜"


func setup(p_id: int, p_kind: int, pos: Vector2) -> void:
	drop_id = p_id
	kind = p_kind
	_rig = Node3D.new()
	add_child(_rig)
	position = pos

	var col := color_for(kind)
	_rig.add_child(Fx3D.ground_blob(0.34, 0.22))
	_halo = Fx3D.ring(RADIUS * 1.35, Color(col, 0.75), 0.12)
	Fx3D.ring_set(_halo, 1.0)
	_rig.add_child(_halo)

	_model = Fx3D.instance(_MODELS.get(kind, _MODELS[RUNTIAN]))
	Fx3D.fit_length(_model, 0.62)   # 按最长边:辣椒/芹菜是躺平模型,按高度会爆
	_model.position.y = 0.35
	_rig.add_child(_model)

	# 点光:远处也能注意到「那儿有个东西」
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.6
	light.omni_range = 2.2
	light.position = Vector3(0, 0.8, 0)
	_rig.add_child(light)


func _process(delta: float) -> void:
	if _model == null:
		return
	# 悬浮旋转 + 呼吸
	_phase += delta
	_model.rotation.y += delta * 1.6
	_model.position.y = 0.35 + sin(_phase * 2.2) * 0.09
	if _halo != null:
		_halo.scale = Vector3.ONE * (1.0 + 0.1 * sin(_phase * 2.2))


## 被捡走:弹一下放大消失
func play_taken() -> void:
	if _rig == null:
		queue_free()
		return
	var tw := _rig.create_tween()
	tw.set_parallel(true)
	tw.tween_property(_rig, "scale", Vector3.ONE * 1.8, 0.18)
	tw.tween_property(_model, "position:y", 1.2, 0.18)
	tw.chain().tween_callback(queue_free)
