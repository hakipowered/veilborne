// Toon shading used only by the offline sprite renderer (tools/anim/render.gd).
// Painted Meshy albedo + 2-band cel light + cool shadow tint + warm rim light.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 light_dir_view = vec3(-0.45, 0.75, 0.5);   // view space, toward light
uniform vec4 shadow_tint : source_color = vec4(0.68, 0.62, 0.82, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float rim_strength = 0.55;
uniform float saturation = 1.25;
uniform float brightness = 1.22;
uniform float emission_boost = 0.0;   // 0..1 for glowing parts (weapons)
uniform vec4 emission_color : source_color = vec4(1.0, 0.6, 0.2, 1.0);

void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo_color;
	vec3 c = t.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * brightness;
	vec3 n = normalize(NORMAL);
	vec3 L = normalize(light_dir_view);
	float ndl = dot(n, L);
	float lit = smoothstep(-0.05, 0.08, ndl);
	vec3 shaded = mix(c * shadow_tint.rgb, c, lit);
	// soft highlight band
	shaded += c * 0.12 * smoothstep(0.75, 0.8, ndl);
	float fres = 1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	float rim = smoothstep(0.62, 0.7, fres) * smoothstep(-0.2, 0.3, dot(n, normalize(vec3(0.6, 0.5, 0.0))));
	shaded += rim_color.rgb * rim * rim_strength;
	shaded = mix(shaded, emission_color.rgb * 1.3, emission_boost);
	ALBEDO = clamp(shaded, 0.0, 1.0);
}
