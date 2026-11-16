shader_type canvas_item;
// Back wall facade on a sheared quad: side shading, ceiling darkness, faded ends, flickering candle
// highlights painted into the facade, pulsing glow on keyed (window/crystal) colors, light from braziers.

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float shade = 1.0;
uniform float top_dark = 0.30;      // fraction of height that fades into ceiling darkness
uniform vec2 end_fade = vec2(0.0, 0.08); // fade near u=0 / u=1 (in 0..1 of the span)
uniform float span = 1.0;           // UV.x at the far end of this wall (for end fade)
uniform float u_start = 0.0;
uniform vec4 glow_key : source_color = vec4(0.5, 0.3, 1.0, 1.0);
uniform float glow_strength = 0.0;
uniform float candle_flicker = 0.35;
uniform int light_count = 0;
uniform vec4 light_a[6];
uniform vec4 light_b[6];
uniform float ambient = 0.78;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	// candles / warm highlights flicker
	float warm = smoothstep(0.55, 0.9, lum) * smoothstep(0.05, 0.25, c.r - c.b);
	float fl = texture(noise_tex, vec2(UV.x * 3.0, TIME * 0.9)).r;
	c *= 1.0 + warm * candle_flicker * (fl - 0.35) * 2.0;
	// keyed glow (stained glass, crystals)
	float kd = distance(normalize(c + 0.001), normalize(glow_key.rgb + 0.001));
	float gk = smoothstep(0.35, 0.05, kd) * smoothstep(0.15, 0.4, lum);
	float pulse = 0.6 + 0.4 * sin(TIME * 1.3 + UV.x * 4.0);
	c += glow_key.rgb * gk * glow_strength * pulse;

	vec3 light = vec3(ambient);
	for (int i = 0; i < 6; i++) {
		if (i >= light_count) break;
		vec4 a = light_a[i];
		vec2 d = (world - a.xy) / (a.z * 1.1);
		d.y *= 0.8;
		float att = max(1.0 - dot(d, d), 0.0);
		light += light_b[i].rgb * (att * att * a.w * 0.8);
	}
	c *= light * shade;
	// ceiling darkness + floor contact shadow
	float v = UV.y;
	c *= smoothstep(0.0, top_dark, v);
	c *= 1.0 - smoothstep(0.93, 1.0, v) * 0.35;
	float u = (UV.x - u_start) / max(span - u_start, 0.0001);
	c *= smoothstep(0.0, max(end_fade.x, 0.0001), u) * (1.0 - smoothstep(1.0 - max(end_fade.y, 0.0001), 1.0, u));
	COLOR = vec4(c, 1.0);
}
