shader_type canvas_item;
// Heat shimmer over lava: one screen read for the whole (multi-polygon) node. Disabled in low quality.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float strength = 0.006;
varying vec2 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	vec2 n = texture(noise_tex, world / 160.0 + vec2(0.0, TIME * 0.35)).rg - 0.5;
	float k = COLOR.a;
	vec3 c = texture(screen_tex, SCREEN_UV + n * strength * k).rgb;
	c += vec3(0.08, 0.025, 0.0) * k;
	COLOR = vec4(c, smoothstep(0.0, 0.4, k));
}
