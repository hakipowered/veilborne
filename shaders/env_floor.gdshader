shader_type canvas_item;
// Veilborne chamber floor: isometric slab tiling from a 4x4 slab atlas (random slab + rotation per cell),
// inked seams, large-scale grime, edge occlusion, carved Warden sigil with glow/pulse/clear-wave,
// warm light pools from up to 12 flickering lights, and drifting ground fog. One pass, no screen reads.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D sigil_tex : filter_linear_mipmap, repeat_disable;

uniform vec2 iso = vec2(140.0, 74.0);       // world half-extent of one slab diamond (x, y)
uniform vec2 half_size = vec2(1140.0, 608.0); // visual floor diamond half extents
uniform float inset = 0.006;
uniform vec4 seam_color : source_color = vec4(0.83, 0.66, 0.30, 1.0);
uniform float seam_width = 0.018;
uniform float seam_ink = 0.012;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 grime : source_color = vec4(0.10, 0.16, 0.10, 1.0);
uniform float ambient = 0.62;

uniform vec2 sigil_center = vec2(0.0);
uniform float sigil_radius = 430.0;
uniform vec4 sigil_color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float sigil_base = 0.35;  // idle glow strength
uniform float sigil_lit = 0.0;    // 0..1 room cleared
uniform float sigil_wave = 1.0;   // 0..1 expanding clear-wave progress (1 = done)

uniform int light_count = 0;
uniform vec4 light_a[12];  // x, y, radius, intensity
uniform vec4 light_b[12];  // r, g, b, flicker amount

uniform vec4 fog_color : source_color = vec4(0.45, 0.6, 0.55, 1.0);
uniform float fog_amount = 0.22;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 rot_q(vec2 f, float r) {
	// rotate/flip a 0..1 local coordinate by quarter turns
	vec2 c = f - 0.5;
	if (r < 1.0) return f;
	if (r < 2.0) return vec2(-c.y, c.x) + 0.5;
	if (r < 3.0) return vec2(-c.x, -c.y) + 0.5;
	return vec2(c.y, -c.x) + 0.5;
}

void fragment() {
	vec2 w = world;
	// iso -> slab space
	vec2 uv = vec2(w.x / iso.x + w.y / iso.y, w.y / iso.y - w.x / iso.x) * 0.5;
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float h = hash(cell);
	float idx = floor(h * 16.0);
	float r = floor(fract(h * 7.31) * 4.0);
	vec2 lf = rot_q(f, r);
	vec2 auv = (vec2(mod(idx, 4.0), floor(idx / 4.0)) + inset + lf * (1.0 - 2.0 * inset)) * 0.25;
	vec2 gx = dFdx(uv) * 0.25;
	vec2 gy = dFdy(uv) * 0.25;
	vec3 col = textureGrad(atlas, auv, gx, gy).rgb;

	// seams (inked gold inlay)
	float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float px = length(fwidth(uv)) * 0.7;
	float seam = 1.0 - smoothstep(seam_width - px, seam_width + px, e);
	float ink = 1.0 - smoothstep(seam_width + seam_ink - px, seam_width + seam_ink + px, e);
	col = mix(col, vec3(0.03, 0.02, 0.03), ink * 0.85);
	col = mix(col, seam_color.rgb * (0.75 + 0.5 * hash(cell + 3.1)), seam * seam_color.a);

	// large-scale variation
	vec4 n1 = texture(noise_tex, w / 1100.0);
	vec4 n2 = texture(noise_tex, w / 420.0 + 0.37);
	col *= tint.rgb * (0.86 + 0.28 * n1.r);
	col = mix(col, grime.rgb, smoothstep(0.55, 0.85, n1.g * 0.7 + n2.b * 0.5) * grime.a * 0.55);

	// occlusion toward the room rim; stronger under the back walls
	float k = abs(w.x) / half_size.x + abs(w.y) / half_size.y;
	float occ = smoothstep(0.70, 1.0, k) * (w.y < 0.0 ? 0.72 : 0.5);
	float back = smoothstep(0.88, 1.0, k) * step(w.y, 0.0) * 0.25;

	// sigil (top-down texture mapped into iso floor space)
	vec2 sp = (w - sigil_center);
	sp.y *= iso.x / iso.y;
	vec2 suv = sp / sigil_radius * 0.5 + 0.5;
	float sm = 0.0;
	if (suv.x > 0.0 && suv.x < 1.0 && suv.y > 0.0 && suv.y < 1.0) {
		sm = texture(sigil_tex, suv).r;
	}
	float sr = length(sp) / sigil_radius;
	// carved: darken the stone where lines are, then glow
	col = mix(col, col * 0.35 + vec3(0.12, 0.09, 0.04), sm * 0.55);

	// lighting
	vec3 light = vec3(ambient);
	for (int i = 0; i < 12; i++) {
		if (i >= light_count) break;
		vec4 a = light_a[i];
		vec4 b = light_b[i];
		vec2 d = w - a.xy;
		d.y *= 1.75;
		float att = clamp(1.0 - length(d) / a.z, 0.0, 1.0);
		att *= att;
		float fl = 1.0 - b.a * (0.5 + 0.5 * sin(TIME * (6.3 + float(i) * 1.7) + float(i) * 2.1)) * (0.6 + 0.4 * sin(TIME * 13.1 + float(i)));
		light += b.rgb * att * a.w * fl;
	}
	col *= light;
	col *= 1.0 - occ - back;

	// sigil glow
	float pulse = 0.5 + 0.5 * sin(TIME * 1.6 - sr * 5.0);
	float glow = sm * (sigil_base * (0.6 + 0.4 * pulse) + sigil_lit * (1.1 + 0.3 * pulse));
	float wave = 0.0;
	if (sigil_wave < 1.0) {
		float wr = sigil_wave * 1.6;
		wave = exp(-abs(sr - wr) * 14.0) * (1.0 - sigil_wave) * 1.6;
		glow += sm * wave * 2.0;
	}
	vec3 em = sigil_color.rgb * glow + sigil_color.rgb * wave * 0.25 * smoothstep(1.4, 0.2, sr);
	// faint halo around a lit sigil
	em += sigil_color.rgb * sigil_lit * 0.10 * smoothstep(1.05, 0.2, sr);
	col += em;

	// ground fog
	float fog = texture(noise_tex, w / 760.0 + TIME * vec2(0.012, 0.005)).b;
	fog *= texture(noise_tex, w / 330.0 - TIME * vec2(0.008, -0.011)).a * 1.6;
	fog = smoothstep(0.25, 0.95, fog) * fog_amount * (0.6 + 0.6 * smoothstep(0.5, 1.0, k));
	col = mix(col, fog_color.rgb, fog);

	COLOR = vec4(col, 1.0);
}
