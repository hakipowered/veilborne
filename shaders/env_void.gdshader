shader_type canvas_item;
// Abyss backdrop (opaque, far parallax): drifting mist banks, slow breathing light, optional stars,
// lightning flashes (driven by `flash`) and water caustics (`caustics`).

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 mist_color : source_color = vec4(0.25, 0.45, 0.42, 1.0);
uniform float mist = 0.35;
uniform vec4 grade : source_color = vec4(1.0);
uniform float darken = 0.75;
uniform float stars = 0.0;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(0.6, 0.75, 1.0, 1.0);
uniform float caustics = 0.0;
uniform vec4 caustic_color : source_color = vec4(0.3, 0.8, 0.8, 1.0);

void fragment() {
	vec2 uv = UV;
	vec3 c = texture(TEXTURE, uv).rgb * grade.rgb * darken;
	float m1 = texture(noise_tex, uv * vec2(1.2, 0.8) + TIME * vec2(0.010, 0.002)).r;
	float m2 = texture(noise_tex, uv * vec2(2.3, 1.4) - TIME * vec2(0.006, -0.004)).g;
	float m = smoothstep(0.35, 0.9, m1 * 0.65 + m2 * 0.55);
	c = mix(c, mist_color.rgb, m * mist);
	c *= 0.9 + 0.1 * sin(TIME * 0.5);
	if (stars > 0.0) {
		float s = texture(noise_tex, uv * 9.0).a;
		float tw = 0.5 + 0.5 * sin(TIME * 2.0 + s * 40.0);
		c += vec3(0.9, 0.85, 1.0) * smoothstep(0.86, 0.95, s) * tw * stars;
	}
	if (caustics > 0.0) {
		float a = texture(noise_tex, uv * 3.0 + TIME * vec2(0.03, 0.01)).b;
		float b = texture(noise_tex, uv * 3.7 - TIME * vec2(0.02, 0.025)).b;
		float ca = 1.0 - abs(a - b) * 9.0;
		c += caustic_color.rgb * clamp(ca, 0.0, 1.0) * caustics * smoothstep(0.2, 1.0, uv.y);
	}
	c += flash_color.rgb * flash * (0.4 + 0.6 * m1);
	// edge vignette of the backdrop itself
	vec2 d = uv - 0.5;
	c *= 1.0 - dot(d, d) * 1.2;
	COLOR = vec4(c, 1.0);
}
