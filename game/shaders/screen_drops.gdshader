// Kamera-Wassertropfen ("Screen Drops"): zwei prozedurale Tropfen-Layer
// verzerren das Bild. Nur aktiv (sichtbar), wenn es regnet.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float intensity = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 drop_layer(vec2 uv, float t, float scale, float seed) {
	uv *= scale;
	vec2 id = floor(uv);
	vec2 f = fract(uv) - 0.5;
	float h = hash12(id + seed);
	float life = fract(t * (0.12 + h * 0.18) + h);
	vec2 c = (vec2(hash12(id + seed + 3.1), hash12(id + seed + 5.7)) - 0.5) * 0.6;
	c.y += life * 0.3 - 0.15;
	vec2 d = f - c;
	d.y *= 0.8;
	float r = 0.1 + h * 0.13;
	float m = smoothstep(r, r * 0.65, length(d)) * step(0.5, h) * (1.0 - life);
	return vec3(d / r * m, m);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.000001);
	vec2 auv = vec2(uv.x * aspect, uv.y);
	vec3 l1 = drop_layer(auv, TIME, 5.0, 0.0);
	vec3 l2 = drop_layer(auv, TIME * 1.3, 9.0, 11.0);
	vec2 offs = (l1.xy + l2.xy) * 0.025 * intensity;
	float mask = clamp(max(l1.z, l2.z) * intensity, 0.0, 1.0);
	vec3 col = texture(screen_tex, uv - offs).rgb;
	COLOR = vec4(col * (1.0 + 0.12 * mask), smoothstep(0.0, 0.08, mask));
}
