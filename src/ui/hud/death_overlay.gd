## death_overlay.gd — 阵亡遮罩（3D 版新增，挂 A0001M11 HUD 层）
## 全屏暗红晕影 + 「你被炖进汤里了…」大标题 + 「复活中…」动点；仅阵亡期间可见。
## 由 hud._process 以 match_state.is_dead(me_id)（权威 FLAG_DEAD）驱动 set_dead()。
## 晕影走 _draw 分层描框：零纹理零 shader，GL Compatibility 下开销可忽略。

class_name DeathOverlay
extends Control

const FADE_IN := 0.25
const FADE_OUT := 0.4
const VIGNETTE := Color(0.30, 0.03, 0.02)

var _dead := false
var _title: Label = null
var _sub: Label = null
var _tween: Tween = null
var _dot_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0
	resized.connect(queue_redraw)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_title = UiKit.make_title("你被炖进汤里了…", 56)
	box.add_child(_title)
	_sub = UiKit.make_label("复活中", 28, UiKit.CREAM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_color_override("font_outline_color", UiKit.WOOD_DARK)
	_sub.add_theme_constant_override("outline_size", 5)
	box.add_child(_sub)


## 唯一对外入口：淡入 0.25s / 淡出 0.4s（重复同值调用无副作用）
func set_dead(is_dead: bool) -> void:
	if is_dead == _dead:
		return
	_dead = is_dead
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if is_dead:
		visible = true
		_dot_t = 0.0
		_tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	else:
		_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
		_tween.tween_callback(func() -> void: visible = false)


func _process(delta: float) -> void:
	if not visible:
		return
	_dot_t += delta
	_sub.text = "复活中" + ".".repeat(int(_dot_t * 2.0) % 4)


func _draw() -> void:
	# 中央轻压暗 + 边缘分层描框 = 廉价晕影（无渐变纹理）
	draw_rect(Rect2(Vector2.ZERO, size), Color(VIGNETTE.r, VIGNETTE.g, VIGNETTE.b, 0.22))
	var bands := 6
	var band_w := minf(size.x, size.y) * 0.035
	for i in range(bands):
		var inset := band_w * float(i)
		var a := 0.30 * (1.0 - float(i) / float(bands))
		var r := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			break
		draw_rect(r, Color(VIGNETTE.r, VIGNETTE.g, VIGNETTE.b, a), false, band_w)
