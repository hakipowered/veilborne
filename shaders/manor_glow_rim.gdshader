shader_type canvas_item;
// A soft pulsing glow hugging a sprite's silhouette (weapon racks and their floating weapons).
// glow: 0 = none; the hub drives it (pulse + brighter when the heroine is near).

uniform vec4 glow_color : source_color = vec4(1.0, 0.75, 0.35, 1.0);
uniform float glow = 0.5;
uniform float width_px = 6.0;
uniform float sheen = 0.0;   // 0..1 a light sweep across the art

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * width_px;
	float n = 0.0;
	n += texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	n += texture(TEXTURE, UV - vec2(px.x, 0.0)).a;
	n += texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	n += texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	n += texture(TEXTURE, UV + px * 0.7).a;
	n += texture(TEXTURE, UV - px * 0.7).a;
	n += texture(TEXTURE, UV + vec2(px.x, -px.y) * 0.7).a;
	n += texture(TEXTURE, UV + vec2(-px.x, px.y) * 0.7).a;
	n /= 8.0;
	// outer halo (outside the silhouette) and inner rim (edge pixels of the silhouette)
	float halo = n * (1.0 - c.a);
	float rim = c.a * (1.0 - n) * 2.5;
	// a slow diagonal sheen across the metal
	float sw = fract(TIME * 0.18 + UV.x * 0.35 - UV.y * 0.35);
	float sh = smoothstep(0.0, 0.06, sw) * smoothstep(0.14, 0.06, sw) * sheen * c.a;
	vec3 rgb = c.rgb + glow_color.rgb * (rim * glow + sh * 0.8);
	float a = max(c.a, clamp(halo * glow * 1.3, 0.0, 1.0));
	vec3 outc = mix(glow_color.rgb * 1.2, rgb, c.a / max(a, 0.001));
	COLOR = vec4(outc, a) * COLOR;
}
