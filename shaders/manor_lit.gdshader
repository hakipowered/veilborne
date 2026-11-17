shader_type canvas_item;
// Manor hub surfaces: painted floors projected onto the iso ground (mirror-tiled so seams never show)
// or wall facades on sheared quads, lit by warm ambient + up to 8 flickering light pools (culled and
// flickered on the CPU in scenes/manor.gd). One pass, no screen reads: cheap on mobile.

uniform bool ground = true;
uniform float tile = 620.0;            // ground units per texture repeat
uniform float ambient = 0.52;
uniform vec4 ambient_tint : source_color = vec4(1.0, 0.86, 0.74, 1.0);
uniform float top_dark = 0.0;          // walls: darken toward the top (ceiling shadow)
uniform float bottom_dark = 0.0;       // walls / lips: darken toward the bottom
uniform float light_squash = 2.0;      // y stretch for light falloff (2 = flat on the floor)
uniform int light_count = 0;
uniform vec4 light_a[8];               // x, y, radius, intensity
uniform vec4 light_b[8];               // r, g, b, unused
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float grime = 0.22;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec2 mirror_uv(vec2 p) {
	vec2 m = mod(p, 2.0);
	return 1.0 - abs(1.0 - m);
}

void fragment() {
	vec4 base;
	if (ground) {
		vec2 g = vec2(world.x * 0.5 + world.y, world.y - world.x * 0.5);
		base = texture(TEXTURE, mirror_uv(g / tile));
		// large soft grime blotches break up the repetition
		float n = texture(noise_tex, g / 2600.0).r;
		base.rgb *= 1.0 - grime * smoothstep(0.35, 0.85, n);
	} else {
		base = texture(TEXTURE, UV);
	}
	vec3 l = ambient * ambient_tint.rgb;
	for (int i = 0; i < 8; i++) {
		if (i >= light_count) {
			break;
		}
		vec4 a = light_a[i];
		vec2 d = world - a.xy;
		d.y *= light_squash;
		float f = 1.0 - clamp(length(d) / a.z, 0.0, 1.0);
		l += light_b[i].rgb * a.w * f * f;
	}
	if (!ground) {
		float v = fract(UV.y);
		l *= 1.0 - top_dark * (1.0 - smoothstep(0.0, 0.55, v));
		l *= 1.0 - bottom_dark * smoothstep(0.3, 1.0, v);
	}
	COLOR = vec4(base.rgb * l, base.a * COLOR.a);
}
