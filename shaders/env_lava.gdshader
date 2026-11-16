shader_type canvas_item;
// Molten lava: crusted plates drifting over a white-hot core, glowing banks. Pools (mode 0: elliptic
// jagged mask over a quad) or channels (mode 1: Polygon2D strip, UV.x = length in px / 256, UV.y across).
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform int mode = 0;
uniform float pad = 1.12;
uniform float seed = 0.0;
uniform float flow = 0.18;
uniform vec4 hot : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform vec4 mid : source_color = vec4(1.0, 0.38, 0.06, 1.0);
uniform vec4 crust : source_color = vec4(0.16, 0.05, 0.035, 1.0);
uniform vec4 bank : source_color = vec4(0.06, 0.04, 0.04, 1.0);
varying vec2 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	float inside;
	float edge;
	vec2 fuv;
	if (mode == 0) {
		vec2 p = (UV - 0.5) * 2.0 * pad;
		float r = length(p);
		float ang = atan(p.y, p.x);
		float e = 0.9 + 0.13 * texture(noise_tex, vec2(ang * 0.31831 + seed, seed * 2.3)).r;
		inside = 1.0 - smoothstep(e - 0.025, e, r);
		edge = clamp((e - r) / 0.22, 0.0, 1.0);
		fuv = world / 190.0 + vec2(TIME * flow * 0.08, TIME * flow * 0.05);
	} else {
		float x = abs(UV.y - 0.5) * 2.0;
		float n = texture(noise_tex, vec2(UV.x * 0.37 + seed, 0.2)).r;
		float e = 0.86 + 0.14 * n;
		inside = 1.0 - smoothstep(e - 0.05, e, x);
		edge = clamp((e - x) / 0.45, 0.0, 1.0);
		fuv = vec2(UV.x * 1.9 - TIME * flow, UV.y * 0.8 + seed);
	}
	float n1 = texture(noise_tex, fuv).r;
	float n2 = texture(noise_tex, fuv * 2.3 + vec2(TIME * 0.03, 0.0)).g;
	float n3 = texture(noise_tex, fuv * 5.1 - vec2(0.0, TIME * 0.05)).r;
	float heat = n1 * 0.6 + n2 * 0.3 + n3 * 0.1;
	float pulse = 0.88 + 0.12 * sin(TIME * 2.3 + n1 * 9.0 + seed * 5.0);
	// molten body: deep red at the banks, orange, white-yellow down the hottest core
	float core = smoothstep(0.05, 0.9, edge);
	vec3 c = mix(vec3(0.62, 0.08, 0.02), mid.rgb, smoothstep(0.0, 0.45, core));
	c = mix(c, hot.rgb, smoothstep(0.4, 1.0, core) * (1.0 - smoothstep(0.32, 0.56, heat)));
	c *= pulse;
	// drifting crust plates with glowing seams between them
	float plate = smoothstep(0.55, 0.6, heat);
	float seam = smoothstep(0.47, 0.55, heat) * (1.0 - plate);
	vec3 cr = crust.rgb * (0.75 + 0.45 * n3) + mid.rgb * 0.12 * (1.0 - smoothstep(0.6, 0.75, heat));
	c = mix(c, cr, plate * 0.94);
	c += hot.rgb * seam * 0.35;
	// charred bank, lit orange where the lava laps it
	float b = smoothstep(0.32, 0.0, edge);
	c = mix(c, bank.rgb + mid.rgb * smoothstep(0.3, 0.06, edge) * 0.55 * (0.6 + 0.4 * n2), b * 0.9);
	COLOR = vec4(c * 1.2, inside);
}
