shader_type canvas_item;
// Gentle cloth sway for banners (bottom moves most). Vertex-only cost.
uniform float amp = 6.0;
uniform float speed = 1.3;
uniform float seed = 0.0;
void vertex() {
	float k = UV.y * UV.y;
	VERTEX.x += sin(TIME * speed + seed * 6.0 + UV.y * 3.0) * amp * k;
	VERTEX.y += sin(TIME * speed * 1.3 + seed) * amp * 0.15 * k;
}
