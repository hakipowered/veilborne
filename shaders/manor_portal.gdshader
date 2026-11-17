shader_type canvas_item;
// The manor's Gate to the Hollow: the purple veil inside the arch turns as a living whirlpool.
// Everything is masked to the arch's opening (mask_tex), so the stone frame is never touched.

uniform sampler2D mask_tex : filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec2 center = vec2(0.46, 0.56);   // swirl eye, in UV
uniform vec2 tex_px = vec2(249.0, 420.0); // texture size (for a round swirl on a tall opening)
uniform float radius_px = 124.0;          // opening half height in texture pixels
uniform float speed = 1.0;

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float m = texture(mask_tex, UV).r;
	if (m < 0.003) {
		COLOR = base;
	} else {
		float t = TIME * speed;
		vec2 p = (UV - center) * tex_px / radius_px;
		p.y *= 0.62;
		float r = length(p);
		float a = atan(p.y, p.x);
		// two spiral arms turning around the eye
		float arms = 0.5 + 0.5 * sin(2.0 * a + 8.0 * sqrt(r + 0.02) - t * 2.4);
		// painterly noise, twisted more toward the center and spun
		vec2 q1 = rot(p, -t * 0.9 + 3.2 * (1.0 - clamp(r, 0.0, 1.0)));
		vec2 q2 = rot(p, -t * 0.55 + 1.8 * (1.0 - clamp(r, 0.0, 1.0)));
		float n1 = texture(noise_tex, q1 * 0.55 + vec2(0.5)).r;
		float n2 = texture(noise_tex, q2 * 1.25 + vec2(0.17, 0.61)).g;
		float v = arms * 0.6 + n1 * 0.28 + n2 * 0.22;
		v = smoothstep(0.25, 0.95, v);
		vec3 deep = vec3(0.16, 0.04, 0.30);
		vec3 violet = vec3(0.52, 0.22, 0.92);
		vec3 lilac = vec3(0.86, 0.62, 1.0);
		vec3 col = mix(deep, violet, smoothstep(0.0, 0.55, v));
		col = mix(col, lilac, smoothstep(0.55, 1.0, v));
		// keep the painting's brushwork under the motion
		float lum = dot(base.rgb, vec3(0.3, 0.45, 0.25));
		col *= 0.7 + 0.6 * lum;
		// bright pulsing eye
		float pulse = 0.94 + 0.08 * sin(TIME * 1.7);
		col += vec3(1.0, 0.85, 1.0) * exp(-r * 3.6) * 0.75 * pulse;
		// motes pulled into the eye along the spiral
		float motes = 0.0;
		for (int i = 0; i < 8; i++) {
			float fi = float(i);
			float ph = fract(TIME * 0.16 + fi / 8.0);
			float rr = (1.0 - ph) * 0.95;
			float ang = fi * 2.399 + ph * 5.5 + TIME * 0.4;
			vec2 mp = vec2(cos(ang), sin(ang)) * rr;
			float d = length(p - mp);
			motes += smoothstep(0.055, 0.0, d) * sin(ph * 3.14159);
		}
		col += vec3(1.0, 0.9, 1.0) * motes;
		col *= pulse;
		// a soft violet rim where the veil meets the stone
		col += vec3(0.6, 0.35, 1.0) * (1.0 - smoothstep(0.0, 0.9, m)) * 0.6;
		COLOR = vec4(mix(base.rgb, col, m), base.a);
	}
}
