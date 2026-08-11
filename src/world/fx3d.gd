## fx3d.gd — 3D 表现层公共工厂
## 地面贴片(阴影/充能环/射程圈/攻击扇形)、简单几何材质、GLB 加载缓存。
## 全部 unshaded 贴地 quad,兼容 gl_compatibility;比 Decal 便宜且全平台可用。

class_name Fx3D

static var _scene_cache := {}
static var _blob_tex: ImageTexture = null
static var _ring_shader: Shader = null
static var _sector_shader: Shader = null


## GLB/GLTF 场景缓存加载(角色/道具模型)
static func scene(path: String) -> PackedScene:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	return _scene_cache[path]


static func instance(path: String) -> Node3D:
	var ps: PackedScene = scene(path)
	if ps == null:
		push_warning("Fx3D: 模型缺失 " + path)
		return Node3D.new()
	return ps.instantiate() as Node3D


## 简单色块材质(墙基座、锅体等)
static func mat(color: Color, metallic: float = 0.0, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	return m


static func mat_unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## 贴地柔和阴影(径向渐变 quad)。返回 MeshInstance3D,父节点自行定位。
static func ground_blob(radius: float, alpha: float = 0.32) -> MeshInstance3D:
	if _blob_tex == null:
		var s := 64
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y in range(s):
			for x in range(s):
				var d := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5).length() / (s / 2.0)
				var a := clampf(1.0 - smoothstep(0.55, 1.0, d), 0.0, 1.0)
				img.set_pixel(x, y, Color(0, 0, 0, a))
		_blob_tex = ImageTexture.create_from_image(img)
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.0, radius * 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = _blob_tex
	m.albedo_color = Color(0, 0, 0, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.02
	return mi


## 环形指示(充能环/射程圈/翻窗进度):shader 画环 + 径向填充进度
static func ring(radius: float, color: Color, width: float = 0.16) -> MeshInstance3D:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;  // 径向填充比例(从 -90° 顺时针)
uniform float inner : hint_range(0.0, 1.0) = 0.78;    // 环内径(比例)
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float band = smoothstep(inner - 0.06, inner, d) * (1.0 - smoothstep(0.97, 1.0, d));
	float ang = fract((atan(uv.y, uv.x) + PI * 0.5) / TAU);
	float seg = step(ang, progress);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * band * max(seg, 0.18);  // 未填充部分留 18% 底环
}
"""
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.0, radius * 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	mi.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("inner", 1.0 - width / maxf(radius, 0.01))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.035
	return mi


static func ring_set(mi: MeshInstance3D, progress: float, color: Color = Color(0, 0, 0, 0)) -> void:
	var m := mi.material_override as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))
	if color.a > 0.0:
		m.set_shader_parameter("tint", color)


## 攻击预示扇形(±half_deg,半径 r)
static func sector(r: float, half_deg: float, color: Color) -> MeshInstance3D:
	if _sector_shader == null:
		_sector_shader = Shader.new()
		_sector_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.75, 0.30);
uniform float half_angle = 0.873;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float ang = abs(atan(uv.y, uv.x));
	float inside = (1.0 - step(1.0, d)) * (1.0 - step(half_angle, ang));
	float rim = smoothstep(0.92, 1.0, d) + smoothstep(half_angle - 0.06, half_angle, ang);
	ALBEDO = mix(tint.rgb, tint.rgb * 0.7, clamp(rim, 0.0, 1.0));
	ALPHA = tint.a * inside * (0.65 + 0.35 * rim);
}
"""
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(r * 2.0, r * 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	mi.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = _sector_shader
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("half_angle", deg_to_rad(half_deg))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.03
	return mi


## 合并局部 AABB(遍历 MeshInstance3D;用于把任意模型规格化到目标尺寸)
static func local_aabb(n: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var node: Node = top[0]
		var xf: Transform3D = top[1]
		if node is Node3D and node != n:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var bb: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
			result = bb if first else result.merge(bb)
			first = false
		for c in node.get_children():
			stack.append([c, xf])
	return result


## 等比缩放到目标高度;返回缩放后模型的 AABB(便于再对齐)
## ⚠️ 防爆:很多食材模型是「平放」的(奶酪片 y=0.02、汤勺 y=0.024),
## 直接按 y 高度放大会得到几十倍的巨物 —— 以最长边为上限夹住。
static func fit_height(n: Node3D, target_h: float) -> AABB:
	var bb := local_aabb(n)
	var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	var s := target_h / maxf(bb.size.y, 0.001)
	s = minf(s, target_h * 2.0 / maxf(longest, 0.001))   # 最长边不超过 2×目标
	n.scale = Vector3.ONE * s
	return AABB(bb.position * s, bb.size * s)


## 等比缩放到目标最大水平尺寸
static func fit_width(n: Node3D, target_w: float) -> AABB:
	var bb := local_aabb(n)
	var s := target_w / maxf(maxf(bb.size.x, bb.size.z), 0.001)
	n.scale = Vector3.ONE * s
	return AABB(bb.position * s, bb.size * s)


## 等比缩放到目标最长边(方向无关,最稳)
static func fit_length(n: Node3D, target: float) -> AABB:
	var bb := local_aabb(n)
	var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	var s := target / maxf(longest, 0.001)
	n.scale = Vector3.ONE * s
	return AABB(bb.position * s, bb.size * s)


## 通用 3D 提示标牌(翻窗/推板/道具名):billboard Label3D
static func label3d(text: String, size_px: int = 48, color: Color = Color(1, 0.96, 0.8)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size_px
	l.modulate = color
	l.outline_size = size_px / 4
	l.outline_modulate = Color(0.12, 0.07, 0.04)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.01
	l.no_depth_test = true
	var f: FontFile = load("res://assets/fonts/zcool_kuaile.ttf")
	if f != null:
		l.font = f
	return l


## 2D 世界坐标 → 3D(x, y, z):2D 的 +y 映射为 3D 的 +z
static func to3(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(p.x, h, p.y)


## 2D 朝向角(0=+x,y 向下顺时针) → 3D yaw(模型面向 +Z)
static func yaw_of(aim: float) -> float:
	return PI / 2.0 - aim
