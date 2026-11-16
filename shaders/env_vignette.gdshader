shader_type canvas_item;
// Screen-space vignette + top/bottom cinematic darkening. No screen reads (cheap blend).
uniform vec4 color : source_color = vec4(0.02, 0.01, 0.03, 1.0);
uniform float strength = 0.75;
uniform float radius = 0.62;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.82);
	float v = smoothstep(radius * 0.55, radius, length(d) * 1.25);
	float bands = smoothstep(0.82, 1.0, UV.y) * 0.35 + smoothstep(0.12, 0.0, UV.y) * 0.25;
	COLOR = vec4(color.rgb, clamp(v * strength + bands, 0.0, 0.92));
}
