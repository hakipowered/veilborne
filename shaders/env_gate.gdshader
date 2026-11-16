shader_type canvas_item;
// Exit gate: portcullis bars (from the closed painting) slide up into the arch while warm light floods in.

uniform sampler2D open_tex : source_color, filter_linear_mipmap;
uniform sampler2D mask_tex : filter_linear_mipmap;
uniform float open_t = 0.0;     // 0 closed .. 1 fully open
uniform float travel = 0.75;    // how far (in UV) the bars slide
uniform float glow = 0.0;

void fragment() {
	vec4 closed = texture(TEXTURE, UV);
	vec4 opened = texture(open_tex, UV);
	float m = texture(mask_tex, UV).r;
	vec2 suv = UV + vec2(0.0, open_t * travel);
	float sm = texture(mask_tex, suv).r * step(suv.y, 1.0);
	vec4 bars = texture(TEXTURE, suv);
	float blum = dot(bars.rgb, vec3(0.33));
	float bar_a = smoothstep(0.10, 0.28, blum) * sm;
	// what is behind the bars: darkness -> light
	vec3 dark = closed.rgb * (1.0 - open_t);
	float pulse = 0.85 + 0.15 * sin(TIME * 2.2);
	vec3 lightc = opened.rgb * (1.0 + glow * 0.5 * pulse);
	vec3 behind = mix(dark, lightc, smoothstep(0.0, 0.6, open_t));
	vec3 inside = mix(behind, bars.rgb, bar_a);
	vec3 outside = closed.rgb;
	COLOR = vec4(mix(outside, inside, m), closed.a);
}
