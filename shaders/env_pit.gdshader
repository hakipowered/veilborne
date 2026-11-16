shader_type canvas_item;
// Void pit cut into the island floor: jagged elliptic hole on a quad, the far inner cliff painted with the
// ledge texture, falling into the chapter's void colour, soft occlusion ring on the floor around it.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D cliff_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float pad = 1.25;
uniform float seed = 0.0;
uniform float cliff_depth = 0.55;   // in units of the pit's vertical radius
uniform float cliff_rep = 3.0;      // texture repeats around the half circumference
uniform vec4 void_color : source_color = vec4(0.03, 0.02, 0.05, 1.0);
uniform vec4 glow : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform float glow_amount = 0.25;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * pad;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float e = 0.92 + 0.1 * texture(noise_tex, vec2(ang * 0.31831 + seed, seed)).r;
	float inside = 1.0 - smoothstep(e - 0.02, e, r);
	// far inner wall at this column
	float x = clamp(p.x / e, -0.999, 0.999);
	float ytop = -sqrt(1.0 - x * x) * e;
	float d = (p.y - ytop) / (cliff_depth * 2.0);
	float u = (asin(x) / 3.14159 + 0.5) * cliff_rep;
	vec3 cl = texture(cliff_tex, vec2(u, clamp(d, 0.0, 1.0) * 0.9)).rgb * (0.75 - 0.45 * d);
	float fade = smoothstep(0.55, 1.0, d);
	vec3 c = mix(cl, void_color.rgb, fade);
	float n = texture(noise_tex, UV * 1.7 + TIME * vec2(0.01, 0.02)).b;
	c += glow.rgb * glow_amount * smoothstep(0.6, 1.4, d) * (0.5 + n);
	// outside: occlusion ring on the floor
	float ring = (1.0 - inside) * smoothstep(e + 0.22, e, r);
	vec4 col = vec4(c, inside);
	col = mix(col, vec4(0.0, 0.0, 0.0, 0.5 * ring), 1.0 - inside);
	COLOR = col;
}
