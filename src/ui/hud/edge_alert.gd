## edge_alert.gd — 屏幕边缘边界告警（A0001M11F06，跟随摄像机的必要补偿）
## 触发：我的任一段边界正被他人推进且该段在屏幕外 → 对应边缘内侧楔形辉光（进攻方主色）
## 强度按被推速率映射亮度；同侧合并，最多 3 个。
## ⚠️ 数据源：T0001 目前不提供该量（T0005M09F01），待 0x0C4 BorderPressure 下发（T0005M14F02-4/5）。
## 本组件为占位接口，set_pressure() 由数据接入后调用。
## 3D 版改锚点布局：任意分辨率成立（原实现写死 1920×1080）；辉光 = 白色渐隐纹理 × self_modulate 上色。

class_name EdgeAlert
extends Control

const SIDES := ["left", "right", "top", "bottom"]
const THICK := 46.0    # 辉光向屏内延伸厚度

var _wedges := {}      # side 名 → TextureRect


func setup() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in SIDES:
		var w := TextureRect.new()
		w.texture = _glow_tex(s)
		w.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		w.stretch_mode = TextureRect.STRETCH_SCALE
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.self_modulate = Color(1, 0.8, 0.2, 0.0)
		match s:
			"left":
				w.anchor_left = 0.0
				w.anchor_right = 0.0
				w.anchor_top = 0.28
				w.anchor_bottom = 0.72
				w.offset_right = THICK
			"right":
				w.anchor_left = 1.0
				w.anchor_right = 1.0
				w.anchor_top = 0.28
				w.anchor_bottom = 0.72
				w.offset_left = -THICK
			"top":
				w.anchor_left = 0.30
				w.anchor_right = 0.70
				w.anchor_top = 0.0
				w.anchor_bottom = 0.0
				w.offset_bottom = THICK
			"bottom":
				w.anchor_left = 0.30
				w.anchor_right = 0.70
				w.anchor_top = 1.0
				w.anchor_bottom = 1.0
				w.offset_top = -THICK
		add_child(w)
		_wedges[s] = w


## 内侧渐隐辉光纹理（白 → 透明，实际颜色由 self_modulate 上色）
func _glow_tex(side: String) -> GradientTexture2D:
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.gradient = grad
	g.width = 64
	g.height = 64
	match side:
		"left":
			g.fill_from = Vector2(0, 0.5)
			g.fill_to = Vector2(1, 0.5)
		"right":
			g.fill_from = Vector2(1, 0.5)
			g.fill_to = Vector2(0, 0.5)
		"top":
			g.fill_from = Vector2(0.5, 0)
			g.fill_to = Vector2(0.5, 1)
		"bottom":
			g.fill_from = Vector2(0.5, 1)
			g.fill_to = Vector2(0.5, 0)
	return g


## 数据接入（待 0x0C4）：side 0..3 = 左/右/上/下（与 2D 版一致），intensity 0..1，attacker_color
func set_pressure(side: int, intensity: float, attacker_color: Color) -> void:
	if side < 0 or side > 3:
		return
	var w: TextureRect = _wedges[SIDES[side]]
	w.self_modulate = Color(attacker_color.r, attacker_color.g, attacker_color.b,
		clampf(intensity, 0.0, 0.8))
