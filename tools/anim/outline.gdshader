// Inverted-hull ink line (inner + silhouette) for the offline sprite renderer.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
uniform float width = 0.012;
uniform vec4 ink : source_color = vec4(0.07, 0.04, 0.06, 1.0);
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = ink.rgb;
}
