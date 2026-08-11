## env_builder.gd — 对局场景环境(3D)
## 「玩家是锅里的食材」:红珐琅大汤锅 + 巨物尺度的厨房背景(灶台/料箱/坛坛罐罐),
## 胡闹厨房式暖色打光。全部静态节点,一次构建零逐帧成本。
## 模型:KayKit Restaurant Bits + Kenney Food Kit(CC0,assets/kitchen/ assets/props/)。

class_name EnvBuilder


static func build(parent: Node3D) -> void:
	_lighting(parent)
	_pot(parent)
	_kitchen(parent)
	_steam(parent)


# ── 打光:瓦罐汤氛围 —— 暖而不亮,像灶台上一盏昏黄的灯 ─────────────────
static func _lighting(parent: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.84, 0.62)        # 昏黄灶灯
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	parent.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.55, 0.55, 0.65)      # 冷补光压得很低
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-38.0, 141.0, 0.0)
	parent.add_child(fill)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("17100a")          # 视野外近黑的深褐
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.70, 0.52)
	env.ambient_light_energy = 0.55                 # 环境光收暗:亮部留给主光
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.12                       # 辉光只留一点点热气感
	env.glow_bloom = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92                # 略降饱和,炖过的颜色
	env.adjustment_brightness = 0.98
	we.environment = env
	parent.add_child(we)


# ── 汤锅:瓦罐 —— 陶土罐身 + 陶沿 + 双罐耳(世界 48×48,锅心 24/24,半径 24)
static func _pot(parent: Node3D) -> void:
	var c := Vector3(MapData.CENTER.x, 0.0, MapData.CENTER.y)
	var r := MapData.POT_RADIUS
	var pot_col := Color(0.42, 0.29, 0.20)    # 陶土棕(无釉粗陶)
	var rim_col := Color(0.50, 0.36, 0.25)    # 罐沿略浅(手捏厚边)

	# 锅壁(外筒,汤面 y=0 上下各留量)
	var wall := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r + 1.6
	cyl.bottom_radius = r + 0.9
	cyl.height = 5.0
	cyl.radial_segments = 96
	# ⚠️ 顶/底盖必须关掉:默认 cap_top=true 会在 y=1.5 生成一整块圆盘,
	# 等于给锅扣了个盖子,锅里的汤面/角色/地形全被盖住。
	cyl.cap_top = false
	cyl.cap_bottom = false
	wall.mesh = cyl
	wall.position = c + Vector3(0, 1.5 - 2.5, 0)   # 顶沿 y=1.5
	wall.material_override = Fx3D.mat(pot_col, 0.0, 0.92)   # 粗陶,不反光
	parent.add_child(wall)

	# 锅沿(压扁圆环,盖住锅壁顶)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r - 0.4
	torus.outer_radius = r + 1.9
	torus.rings = 96
	rim.mesh = torus
	rim.scale = Vector3(1.0, 0.42, 1.0)
	rim.position = c + Vector3(0, 1.5, 0)
	rim.material_override = Fx3D.mat(rim_col, 0.0, 0.88)
	parent.add_child(rim)

	# 汤面与锅沿之间的内壁(汤贴壁)
	var inner := MeshInstance3D.new()
	var icyl := CylinderMesh.new()
	icyl.top_radius = r + 0.02
	icyl.bottom_radius = r - 0.35
	icyl.height = 1.5
	icyl.radial_segments = 96
	icyl.cap_top = false       # 同上:内壁也不能有盖
	icyl.cap_bottom = false
	inner.mesh = icyl
	inner.position = c + Vector3(0, 0.75, 0)
	var im := Fx3D.mat(pot_col.darkened(0.35), 0.0, 0.95)
	im.cull_mode = BaseMaterial3D.CULL_FRONT       # 只画内面
	inner.material_override = im
	parent.add_child(inner)

	# 双锅耳
	for side in [0.0, PI]:
		var ear := MeshInstance3D.new()
		var et := TorusMesh.new()
		et.inner_radius = 1.1
		et.outer_radius = 2.1
		ear.mesh = et
		ear.rotation = Vector3(0.0, 0.0, PI / 2.0)
		ear.rotation.y = side
		ear.position = c + Vector3(cos(side) * (r + 2.6), 1.1, sin(side) * (r + 2.6))
		ear.material_override = Fx3D.mat(rim_col, 0.0, 0.88)
		parent.add_child(ear)


# ── 厨房背景:巨物尺度(我们是锅里的食材) ────────────────────────────────
static func _kitchen(parent: Node3D) -> void:
	var c := Vector3(MapData.CENTER.x, 0.0, MapData.CENTER.y)
	var floor_y := -3.4

	# 灶台格纹地面
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(560, 560)
	floor_mesh.mesh = pm
	floor_mesh.position = c + Vector3(0, floor_y, 0)
	var fm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode shadows_disabled, specular_disabled;
uniform vec4 col_a : source_color = vec4(0.30, 0.21, 0.14, 1.0);
uniform vec4 col_b : source_color = vec4(0.26, 0.18, 0.12, 1.0);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 t = floor(wp.xz / vec2(6.0, 24.0));   // 长条木板
	float chk = mod(t.x + t.y, 2.0);
	vec3 col = mix(col_a.rgb, col_b.rgb, chk);
	// 砖缝
	vec2 f = abs(fract(wp.xz / vec2(6.0, 24.0)) - 0.5);
	float line = smoothstep(0.47, 0.5, max(f.x, f.y));
	ALBEDO = mix(col, col * 0.78, line);
}
"""
	fm.shader = sh
	floor_mesh.material_override = fm
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(floor_mesh)

	# 背景道具环(锅外一圈,巨物缩放;正交俯视下作为画面四周的「厨房味」)
	var props := [
		# [路径, 极角°, 距锅心, 缩放, 朝向锅心?]
		["res://assets/kitchen/stove_multi_decorated.gltf", -90.0, 66.0, 16.0, true],
		["res://assets/kitchen/fridge_A_decorated.gltf", -38.0, 74.0, 18.0, true],
		["res://assets/kitchen/kitchencounter_straight_A.gltf", -132.0, 70.0, 16.0, true],
		["res://assets/kitchen/kitchencounter_straight_B.gltf", -160.0, 72.0, 16.0, true],
		["res://assets/kitchen/crate_tomatoes.gltf", 24.0, 58.0, 11.0, false],
		["res://assets/kitchen/crate_onions.gltf", 44.0, 64.0, 11.0, false],
		["res://assets/kitchen/crate_cheese.gltf", 68.0, 60.0, 11.0, false],
		["res://assets/kitchen/jar_A_large.gltf", 108.0, 62.0, 12.0, false],
		["res://assets/kitchen/jar_B_medium.gltf", 118.0, 58.0, 10.0, false],
		["res://assets/kitchen/cuttingboard.gltf", 152.0, 62.0, 13.0, false],
		["res://assets/kitchen/pot_A_stew.gltf", 178.0, 68.0, 13.0, false],
		["res://assets/kitchen/chair_stool.gltf", 92.0, 70.0, 14.0, false],
	]
	for p in props:
		var n := Fx3D.instance(p[0])
		if n.get_child_count() == 0:
			continue
		var a: float = deg_to_rad(p[1])
		var dist: float = p[2]
		n.scale = Vector3.ONE * p[3]
		n.position = c + Vector3(cos(a) * dist, floor_y, sin(a) * dist)
		if p[4]:
			n.rotation.y = -a + PI / 2.0   # 面向锅心
		else:
			n.rotation.y = randf() * TAU
		parent.add_child(n)

	# 案头食材点缀(散落在地面)
	var foods := ["res://assets/props/tomato.glb", "res://assets/props/onion.glb",
		"res://assets/props/carrot.glb", "res://assets/props/broccoli.glb"]
	for i in range(8):
		var f := Fx3D.instance(foods[i % foods.size()])
		var a := TAU * i / 8.0 + 0.4
		f.scale = Vector3.ONE * 6.0
		f.position = c + Vector3(cos(a) * 52.0, floor_y, sin(a) * 52.0)
		f.rotation.y = randf() * TAU
		parent.add_child(f)


# ── 汤面蒸汽:GPU 粒子,锅沿一圈缓慢升腾 ────────────────────────────────
static func _steam(parent: Node3D) -> void:
	var c := Vector3(MapData.CENTER.x, 0.0, MapData.CENTER.y)
	var particles := GPUParticles3D.new()
	particles.amount = 32
	particles.lifetime = 5.0
	particles.preprocess = 4.0
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3.UP
	mat.emission_ring_radius = MapData.POT_RADIUS * 0.8
	mat.emission_ring_inner_radius = MapData.POT_RADIUS * 0.35
	mat.emission_ring_height = 0.5
	mat.direction = Vector3.UP
	mat.spread = 12.0
	mat.initial_velocity_min = 0.7
	mat.initial_velocity_max = 1.3
	mat.gravity = Vector3(0.25, 0.35, 0.1)
	mat.scale_min = 2.0
	mat.scale_max = 4.5
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.25, 0.55))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	mat.alpha_curve = ct
	particles.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 2.4)
	particles.draw_pass_1 = quad
	var qm := StandardMaterial3D.new()
	# 软边圆纹理:没有它,半透明方片在深色汤面上会露出硬边
	var ss := 64
	var img := Image.create(ss, ss, false, Image.FORMAT_RGBA8)
	for y in range(ss):
		for x in range(ss):
			var d := Vector2(x - ss / 2.0 + 0.5, y - ss / 2.0 + 0.5).length() / (ss / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - smoothstep(0.15, 1.0, d), 0.0, 1.0)))
	qm.albedo_texture = ImageTexture.create_from_image(img)
	qm.albedo_color = Color(1.0, 0.93, 0.82, 0.16)
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particles.material_override = qm
	particles.position = c + Vector3(0, 0.4, 0)
	parent.add_child(particles)
