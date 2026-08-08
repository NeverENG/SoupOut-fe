// territory.gdshader — 地盘场 GPU 渲染（T0005M07F05，覆盖 T0001M03F08 的 CPU marching squares）
// ⚠️ 唯一例外：field 纹理材质强制 Linear 过滤（平滑有机边界全靠它），
//    项目全局是 Nearest（A0001M06F01），此材质单独覆盖 —— 有意例外，Review 勿改。
// 输入：96×96 RGBA8 覆盖度纹理，R/G/B/A = 玩家 1/2/3/4 覆盖度；原汤四通道全低；锅外由锅体遮罩。
// 四层（A0001M07F03）：
//   ① 等值线：双线性 + smoothstep（等价平滑后的 marching squares）
//   ② 马赛克颗粒带：沿边界向内的量化抖动带（该玩家深色）
//   ③ 描边：edge 窄带（深色 1~2px）
//   ④ 150ms 漫开：CPU 侧把 dirty 格目标通道渐变到 255（renderer 驱动），此处只读
// 图案（A0001M07F02，屏幕空间恒定不随 zoom 缩放）：斜纹/横波纹/点阵/网格，shader 内计算，
//   正式图案纹理可经 uniform 替换。

shader_type canvas_item;

uniform sampler2D field : source_color, filter_linear;

// 五色（A0001M07F01）：原汤低饱和米褐 + 四玩家色
uniform vec4 pal_broth = vec4(0.725, 0.604, 0.447, 1.0);
uniform vec4 pal_p1 = vec4(0.949, 0.565, 0.608, 1.0);    // 排骨 暖粉红 #F2909B
uniform vec4 pal_p2 = vec4(0.180, 0.604, 0.525, 1.0);    // 紫菜 深青绿 #2E9A86
uniform vec4 pal_p3 = vec4(1.0, 0.824, 0.118, 1.0);      // 玉米 明黄 #FFD21E
uniform vec4 pal_p4 = vec4(0.545, 0.361, 0.839, 1.0);    // 茄子 紫罗兰 #8B5CD6
// 深色（描边/颗粒带）：C0566A / 175E52 / C79600 / 563394 / 8E7050
uniform vec4 dark_p1 = vec4(0.753, 0.337, 0.416, 1.0);
uniform vec4 dark_p2 = vec4(0.090, 0.369, 0.322, 1.0);
uniform vec4 dark_p3 = vec4(0.780, 0.588, 0.000, 1.0);
uniform vec4 dark_p4 = vec4(0.337, 0.200, 0.580, 1.0);
uniform vec4 dark_broth = vec4(0.557, 0.439, 0.314, 1.0);

uniform float edge_w = 0.12;          // 等值线宽度（纹理空间）
uniform float grain_strength = 0.6;   // 马赛克颗粒带强度
uniform float pattern_strength = 0.5; // 图案对比度（色盲模式可调高）
uniform vec2 viewport_size = vec2(1920.0, 1080.0);

// 漫开：CPU 侧直接写覆盖度；TIME 驱动颗粒带/波纹动画
uniform float anim_time = 0.0;

vec4 palette_for(int owner) {
	if (owner == 1) return pal_p1;
	if (owner == 2) return pal_p2;
	if (owner == 3) return pal_p3;
	if (owner == 4) return pal_p4;
	return pal_broth;
}

vec4 dark_for(int owner) {
	if (owner == 1) return dark_p1;
	if (owner == 2) return dark_p2;
	if (owner == 3) return dark_p3;
	if (owner == 4) return dark_p4;
	return dark_broth;
}

// 图案（A0001M07F02，屏幕空间恒定）：pixel = 屏幕像素坐标
float pattern_for(int owner, vec2 pixel) {
	if (owner == 1) {
		// 排骨：斜纹（45° 交替像素条）
		float d = mod(pixel.x + pixel.y, 8.0);
		return step(4.0, d);
	} else if (owner == 2) {
		// 紫菜：横波纹（水平起伏像素带）
		float w = abs(sin(pixel.y * 0.5 + anim_time * 0.5));
		return smoothstep(0.35, 0.6, w);
	} else if (owner == 3) {
		// 玉米：点阵（规则圆点）
		vec2 cell = mod(pixel, 8.0);
		return 1.0 - step(0.38, distance(cell, vec2(4.0)));
	} else if (owner == 4) {
		// 茄子：网格（细十字格）
		vec2 f = mod(pixel, 8.0);
		return step(7.0, f.x) + step(7.0, f.y);
	}
	// 原汤：无图案（纯色 + 极缓噪波）
	return 0.5 + 0.5 * sin(pixel.x * 0.05 + anim_time * 0.3);
}

void fragment() {
	vec4 c = texture(field, UV);

	// ① 等值线：top1/top2 差分（双线性已平滑）
	float ch0 = c.r;
	float ch1 = c.g;
	float ch2 = c.b;
	float ch3 = c.a;
	float top1 = 0.0; float top2 = 0.0;
	int owner = 0;
	if (ch0 > top1) { top2 = top1; top1 = ch0; owner = 1; } else if (ch0 > top2) { top2 = ch0; }
	if (ch1 > top1) { top2 = top1; top1 = ch1; owner = 2; } else if (ch1 > top2) { top2 = ch1; }
	if (ch2 > top1) { top2 = top1; top1 = ch2; owner = 3; } else if (ch2 > top2) { top2 = ch2; }
	if (ch3 > top1) { top2 = top1; top1 = ch3; owner = 4; } else if (ch3 > top2) { top2 = ch3; }
	// 原汤 = 四通道全低（< 0.25 视为无人区）
	float total = c.r + c.g + c.b + c.a;
	bool is_broth = total < 0.25;
	if (is_broth) { owner = 0; top1 = total; top2 = 0.0; }

	float edge = smoothstep(0.0, edge_w, top1 - top2);

	vec4 base = palette_for(owner);
	vec4 dark = dark_for(owner);

	// 图案（屏幕空间恒定）
	vec2 pixel = SCREEN_UV * viewport_size;
	float pat = pattern_for(owner, pixel);
	vec3 col = base.rgb;
	col = mix(col, col * (0.7 + 0.5 * pat), pattern_strength * edge);

	// ② 马赛克颗粒带：沿边界内侧的量化抖动带（取该玩家深色）
	float grain_zone = smoothstep(0.25, 0.65, edge) * (1.0 - smoothstep(0.65, 0.9, edge));
	vec2 q = floor(pixel / 3.0) * 3.0;
	float noise = fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);
	float grain = step(0.5, noise) * grain_zone * grain_strength;
	col = mix(col, dark.rgb, grain);

	// ③ 描边：edge 最外沿的窄带（深色）
	float outline = smoothstep(edge_w * 0.7, edge_w, edge) * (1.0 - edge);
	col = mix(col, dark.rgb, outline * 0.8);

	// ④ 漫开初始闪亮色（覆盖度在 0.85..1.0 且刚翻转 → 已由 CPU 渐变覆盖，此处无需额外处理）

	float alpha = 1.0 - (1.0 - edge) * 0.35;   // 汤面整体不透明，边缘略透
	COLOR = vec4(col, alpha);
}
