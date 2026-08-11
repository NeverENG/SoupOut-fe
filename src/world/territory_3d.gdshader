// territory_3d.gdshader — 地盘场 3D 版(canvas territory.gdshader 的 spatial 移植)
// 契约不变(T0005M07F05):
//   field 96×96 RGBA8,R/G/B/A = 玩家 1/2/3/4 覆盖度;原汤四通道全零;
//   total < 0.25 → 原汤;等值线/颗粒带/描边/五色图案照搬。
// 差异:图案从屏幕像素空间改为**世界空间**(UV×48,3D 下屏幕空间会随镜头漂移);
//   平面自身 UV(0..1) 对应世界 (0..48)²,锅外由圆形遮罩丢弃。
shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled;

uniform sampler2D field : source_color, filter_linear;
uniform vec4 pal_broth : source_color = vec4(0.545, 0.386, 0.212, 1.0);
uniform vec4 pal_p1 : source_color = vec4(0.720, 0.300, 0.200, 1.0);
uniform vec4 pal_p2 : source_color = vec4(0.440, 0.550, 0.250, 1.0);
uniform vec4 pal_p3 : source_color = vec4(0.840, 0.630, 0.250, 1.0);
uniform vec4 pal_p4 : source_color = vec4(0.500, 0.360, 0.530, 1.0);
uniform vec4 dark_broth : source_color = vec4(0.380, 0.260, 0.130, 1.0);
uniform vec4 dark_p1 : source_color = vec4(0.500, 0.190, 0.120, 1.0);
uniform vec4 dark_p2 : source_color = vec4(0.290, 0.380, 0.160, 1.0);
uniform vec4 dark_p3 : source_color = vec4(0.600, 0.430, 0.140, 1.0);
uniform vec4 dark_p4 : source_color = vec4(0.330, 0.230, 0.370, 1.0);
uniform float edge_w = 0.12;
uniform float grain_strength = 0.6;
uniform float pattern_strength = 0.5;
uniform float anim_time = 0.0;
uniform float pot_radius_uv = 0.5;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 palette(int owner) {
	if (owner == 1) { return pal_p1.rgb; }
	if (owner == 2) { return pal_p2.rgb; }
	if (owner == 3) { return pal_p3.rgb; }
	if (owner == 4) { return pal_p4.rgb; }
	return pal_broth.rgb;
}

vec3 dark_palette(int owner) {
	if (owner == 1) { return dark_p1.rgb; }
	if (owner == 2) { return dark_p2.rgb; }
	if (owner == 3) { return dark_p3.rgb; }
	if (owner == 4) { return dark_p4.rgb; }
	return dark_broth.rgb;
}

// 每方一种世界空间图案(色弱可辨,pattern_strength 调对比)
float pattern_of(int owner, vec2 wp) {
	if (owner == 1) { // 45° 斜条纹
		return step(2.0, mod((wp.x + wp.y) * 2.0, 4.0));
	}
	if (owner == 2) { // 横向波浪
		return smoothstep(0.35, 0.6, abs(sin(wp.y * 4.0 + anim_time * 0.5)));
	}
	if (owner == 3) { // 圆点阵
		vec2 g = mod(wp * 2.0, 1.0) - 0.5;
		return 1.0 - step(0.24, length(g));
	}
	if (owner == 4) { // 十字网格
		vec2 f = mod(wp * 2.0, 1.0);
		return clamp(step(0.88, f.x) + step(0.88, f.y), 0.0, 1.0);
	}
	// 原汤:慢速大颗粒噪声(汤面微沸)
	return smoothstep(0.4, 0.9,
		sin(wp.x * 1.7 + anim_time * 0.6) * sin(wp.y * 1.9 - anim_time * 0.45) * 0.5 + 0.5);
}

void fragment() {
	// 锅体圆形遮罩
	float dist_c = distance(UV, vec2(0.5));
	if (dist_c > pot_radius_uv) {
		discard;
	}
	vec4 c = texture(field, UV);
	// top1/top2:最高与次高覆盖度 → 等值线
	float top1 = max(max(c.r, c.g), max(c.b, c.a));
	float top2 = 0.0;
	int owner = 0;
	if (c.r >= top1) { owner = 1; top2 = max(max(c.g, c.b), c.a); }
	else if (c.g >= top1) { owner = 2; top2 = max(max(c.r, c.b), c.a); }
	else if (c.b >= top1) { owner = 3; top2 = max(max(c.r, c.g), c.a); }
	else { owner = 4; top2 = max(max(c.r, c.g), c.b); }
	float total = c.r + c.g + c.b + c.a;
	if (total < 0.25) {
		owner = 0;
	}
	float edge = (owner == 0) ? 1.0 : smoothstep(0.0, edge_w, top1 - top2);

	vec2 wp = UV * 48.0;   // 世界坐标(图案空间)
	vec3 col = palette(owner);
	float pat = pattern_of(owner, wp);
	col = mix(col, col * (0.7 + 0.5 * pat), pattern_strength * ((owner == 0) ? 0.35 : edge));

	// 颗粒带(边界内侧,马赛克质感)
	float grain_zone = smoothstep(0.25, 0.65, edge) * (1.0 - smoothstep(0.65, 0.9, edge));
	float g = hash12(floor(wp * 6.0) + floor(anim_time * 2.0) * 0.37);
	col = mix(col, dark_palette(owner), grain_zone * grain_strength * g * 0.5);

	// 描边(等值线外缘)
	float outline = smoothstep(edge_w * 0.7, edge_w, edge) * (1.0 - edge);
	col = mix(col, dark_palette(owner), outline * 0.8);

	// 锅沿内侧一圈暗晕(汤贴着锅壁的阴影,白送的立体感)
	float rim = smoothstep(pot_radius_uv - 0.045, pot_radius_uv, dist_c);
	col = mix(col, col * 0.72, rim);

	ALBEDO = col;
}
