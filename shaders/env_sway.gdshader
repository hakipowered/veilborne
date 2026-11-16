shader_type canvas_item;
// Gentle cloth sway for banners (bottom moves most). Vertex-only cost.
// band >= 0: fragment ripple instead, only UV.y inside [band.x, band.y] moves (cloth on a fixed pole).
uniform float amp = 6.0;
uniform float speed = 1.3;
uniform float seed = 0.0;
uniform vec2 band = vec2(-1.0, -1.0);
varying vec4 vc;
void vertex() {
	vc = COLOR;
	if (band.x < 0.0) {
		float k = UV.y * UV.y;
		VERTEX.x += sin(TIME * speed + seed * 6.0 + UV.y * 3.0) * amp * k;
		VERTEX.y += sin(TIME * speed * 1.3 + seed) * amp * 0.15 * k;
	}
}
void fragment() {
	vec2 uv = UV;
	if (band.x >= 0.0) {
		float k = smoothstep(band.x, band.y, UV.y) * (1.0 - smoothstep(band.y + 0.25, band.y + 0.3, UV.y));
		k *= (UV.y - band.x) / max(band.y - band.x, 0.01);
		uv.x += sin(TIME * speed + seed * 6.0 + UV.y * 9.0) * amp * 0.0025 * k;
	}
	COLOR = texture(TEXTURE, uv) * vc;
}
