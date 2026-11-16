shader_type canvas_item;
// Shallow glowing water pool on a quad (UV 0..1 spans the pool box). Jagged elliptic mask, depth tint,
// drifting caustics, slow ripple rings, bright shoreline. Two noise fetches + one for the shore.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 shallow : source_color = vec4(0.25, 0.75, 0.68, 1.0);
uniform vec4 deep : source_color = vec4(0.02, 0.16, 0.2, 1.0);
uniform vec4 glow : source_color = vec4(0.45, 1.0, 0.9, 1.0);
uniform float pad = 1.12;      // quad half size / pool radius
uniform float seed = 0.0;
uniform float jag = 0.08;
uniform float lowq = 0.0;
varying vec2 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * pad;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float e = 1.0 - jag + jag * texture(noise_tex, vec2(ang * 0.31831 + seed, seed * 3.1)).r * 1.6;
	float inside = 1.0 - smoothstep(e - 0.03, e, r);
	float depth = clamp(1.0 - r / e, 0.0, 1.0);
	vec3 c = mix(shallow.rgb, deep.rgb, smoothstep(0.0, 0.7, depth));
	vec2 w = world / 260.0;
	float n1 = texture(noise_tex, w + TIME * vec2(0.021, 0.013)).b;
	float n2 = texture(noise_tex, w * 1.37 - TIME * vec2(0.017, 0.024) + 0.5).g;
	float ca = clamp(1.0 - abs(n1 - n2) * 7.0, 0.0, 1.0);
	c += glow.rgb * ca * ca * (0.55 - 0.25 * lowq);
	float ring = smoothstep(0.75, 1.0, sin(r * 26.0 - TIME * 2.2 + seed * 10.0)) * smoothstep(0.1, 0.5, depth) * (n1 * 0.6);
	c += glow.rgb * ring * 0.25;
	float shore = smoothstep(0.16, 0.0, depth) * inside;
	c = mix(c, glow.rgb * 1.1 + 0.15, shore * 0.55);
	float a = inside * mix(0.62, 0.9, smoothstep(0.0, 0.5, depth));
	COLOR = vec4(c, a);
}
