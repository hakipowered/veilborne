shader_type canvas_item;
render_mode blend_add;
// Procedural hand-painted-looking fire tongue on a quad. Additive. `seed` de-syncs instances.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 core : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 mid : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform vec4 outer : source_color = vec4(0.75, 0.12, 0.05, 1.0);
uniform float seed = 0.0;
uniform float intensity = 1.0;

void fragment() {
	float y = 1.0 - UV.y; // 0 bottom .. 1 top
	float t = TIME + seed * 7.0;
	float n1 = texture(noise_tex, vec2(UV.x * 0.9 + seed, UV.y * 0.7 + t * 1.5)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 1.9 - seed, UV.y * 1.4 + t * 2.6)).g;
	float n = n1 * 0.6 + n2 * 0.4;
	float x = (UV.x - 0.5) * 2.0 + (n - 0.5) * 0.9 * y;
	float w = sqrt(max(0.0, 1.0 - y)) * (0.35 + 0.65 * smoothstep(0.0, 0.22, y));
	float body = 1.0 - smoothstep(w * 0.45, w, abs(x));
	float heat = body * (1.25 - y) + (n - 0.5) * 0.7 * y;
	float a = smoothstep(0.18, 0.45, heat);
	vec3 col = mix(outer.rgb, mid.rgb, smoothstep(0.3, 0.6, heat));
	col = mix(col, core.rgb, smoothstep(0.7, 1.0, heat));
	COLOR = vec4(col * a * intensity, a);
}
