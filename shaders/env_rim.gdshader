shader_type canvas_item;
// Front ledge of the floating chamber: painted foundation that dissolves into the abyss, with pulsing veins.

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float shade = 0.9;
uniform vec4 glow_key : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform float glow_strength = 0.0;
uniform vec4 abyss_color : source_color = vec4(0.02, 0.04, 0.04, 1.0);

void fragment() {
	vec3 c = texture(tex, UV).rgb * shade;
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	float kd = distance(normalize(c + 0.001), normalize(glow_key.rgb + 0.001));
	float gk = smoothstep(0.35, 0.05, kd) * smoothstep(0.1, 0.35, lum);
	c += glow_key.rgb * gk * glow_strength * (0.55 + 0.45 * sin(TIME * 1.7 + UV.x * 6.0));
	// ragged dissolve into the void
	float n = texture(noise_tex, vec2(UV.x * 1.3, UV.y * 0.6)).r;
	float fade = smoothstep(0.35 + n * 0.3, 0.95, UV.y);
	c = mix(c, abyss_color.rgb, smoothstep(0.2, 0.8, UV.y) * 0.55);
	COLOR = vec4(c, 1.0 - fade);
}
