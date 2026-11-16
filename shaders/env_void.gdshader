shader_type canvas_item;
// Abyss backdrop (opaque, far parallax). Kept to two texture fetches: it covers the whole screen.
// Drifting mist, optional twinkling stars, lightning `flash` and water `caustics`.

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
	vec4 n = texture(noise_tex, uv * vec2(1.6, 1.0) + TIME * vec2(0.010, 0.003));
	float m = smoothstep(0.4, 0.85, n.r);
	c = mix(c, mist_color.rgb, m * mist);
	c += vec3(0.9, 0.85, 1.0) * smoothstep(0.80, 0.86, n.a) * (0.5 + 0.5 * sin(TIME * 2.0 + n.g * 30.0)) * stars;
	float ca = 1.0 - abs(n.b - n.g) * 7.0;
	c += caustic_color.rgb * clamp(ca, 0.0, 1.0) * caustics * uv.y;
	c += flash_color.rgb * flash * (0.4 + 0.6 * n.r);
	COLOR = vec4(c, 1.0);
}
