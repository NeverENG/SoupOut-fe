## edge_alert.gd — 屏幕边缘边界告警（A0001M11F06，跟随摄像机的必要补偿）
## 触发：我的任一段边界正被他人推进且该段在屏幕外 → 对应边缘内侧楔形辉光（进攻方主色）
## 强度按被推速率映射亮度/厚度；同侧合并，最多 3 个。
## ⚠️ 数据源：T0001 目前不提供该量（T0005M09F01），待 0x0C4 BorderPressure 下发（T0005M14F02-4/5）。
## 本组件为占位接口，set_pressure() 由数据接入后调用。

class_name EdgeAlert
extends Control

var _wedges := {}    # side(0..3) → ColorRect

const SIDES := ["left", "right", "top", "bottom"]


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in SIDES:
		var w := ColorRect.new()
		w.color = Color(1, 0.8, 0.2, 0.0)
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		match s:
			"left":
				w.position = Vector2(0, 300)
				w.size = Vector2(40, 480)
			"right":
				w.position = Vector2(1880, 300)
				w.size = Vector2(40, 480)
			"top":
				w.position = Vector2(760, 0)
				w.size = Vector2(400, 40)
			"bottom":
				w.position = Vector2(760, 1040)
				w.size = Vector2(400, 40)
		add_child(w)
		_wedges[s] = w


## 数据接入（待 0x0C4）：side 0..3，intensity 0..1，attacker_color
func set_pressure(side: int, intensity: float, attacker_color: Color) -> void:
	if side < 0 or side > 3:
		return
	var w: ColorRect = _wedges[SIDES[side]]
	w.color = attacker_color
	w.color.a = clampf(intensity, 0.0, 0.8)
