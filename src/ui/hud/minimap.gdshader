// minimap.gdshader — 小地图调色板映射（A0001M11F02，3D 版）
// 输入 TEXTURE = renderer 的 96×96 RGBA 覆盖度纹理（R/G/B/A = 玩家 1/2/3/4，T0005M07F05）。
// 直接贴图会把覆盖度当颜色显示（伪彩）—— 此处按 territory.gdshader 同一调色板重映射：
// 四通道全低（< 0.25）= 原汤，否则取最大通道对应玩家色；并按锅体裁圆（UV 半径 0.5）。

shader_type canvas_item;

uniform vec4 pal_broth : source_color = vec4(0.545, 0.386, 0.212, 1.0);
uniform vec4 pal_p1 : source_color = vec4(0.720, 0.300, 0.200, 1.0);
uniform vec4 pal_p2 : source_color = vec4(0.440, 0.550, 0.250, 1.0);
uniform vec4 pal_p3 : source_color = vec4(0.840, 0.630, 0.250, 1.0);
uniform vec4 pal_p4 : source_color = vec4(0.500, 0.360, 0.530, 1.0);
uniform float broth_threshold = 0.25;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// argmax 四通道 → 玩家色
	float top = c.r;
	vec3 col = pal_p1.rgb;
	if (c.g > top) { top = c.g; col = pal_p2.rgb; }
	if (c.b > top) { top = c.b; col = pal_p3.rgb; }
	if (c.a > top) { top = c.a; col = pal_p4.rgb; }
	if (c.r + c.g + c.b + c.a < broth_threshold) {
		col = pal_broth.rgb;
	}
	float d = distance(UV, vec2(0.5));
	// 锅沿内侧微暗角，读出「锅」的弧度
	col *= 1.0 - smoothstep(0.40, 0.50, d) * 0.22;
	// 圆形锅体遮罩（一像素级平滑边）
	float mask = 1.0 - smoothstep(0.492, 0.5, d);
	COLOR = vec4(col, mask * 0.92);
}
