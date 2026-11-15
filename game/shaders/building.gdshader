// Fassaden-Shader: prozedurales Fensterraster in Metern (UV), beleuchtete
// Fenster/Ladenfronten nachts, Nässe. Muster werden ab Subpixel-Größe zum
// Flächenmittel überblendet (kein Moiré / Flimmern in der Distanz).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

global uniform float wetness;
global uniform float night_factor;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 rect_mask(vec2 uv, vec2 spacing, vec2 win, vec2 fw) {
	vec2 f = fract(uv / spacing) * spacing;
	vec2 d = abs(f - spacing * 0.5);
	vec2 m = 1.0 - smoothstep(win * 0.5 - fw, win * 0.5 + fw, d);
	return m;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float seed = COLOR.a;
	float top = UV2.x;
	float variant = UV2.y;
	vec2 uv = UV;
	vec2 fw = max(fwidth(uv), vec2(0.0001));
	bool roof = world_normal.y > 0.5;

	vec3 albedo = base;
	float rough = 0.8;
	float spec = 0.5;
	vec3 emission = vec3(0.0);
	float exposure = 0.55;

	if (variant < -0.5) {
		// Dachaufbauten / schlichte Flächen
		rough = 0.7;
		exposure = 1.0;
	} else if (roof) {
		float n = hash12(floor(uv * 2.0));
		albedo = vec3(0.075, 0.075, 0.08) * (0.85 + 0.3 * n);
		rough = 0.9;
		exposure = 1.0;
	} else {
		vec2 spacing = vec2(3.2, 3.2);
		vec2 win = vec2(1.4, 1.8);
		if (variant < 0.5) { spacing = vec2(2.4, 3.6); win = vec2(2.15, 3.0); }
		else if (variant > 1.5) { spacing = vec2(2.8, 3.4); win = vec2(1.2, 2.0); }

		bool ground_floor = uv.y < 4.2;
		float window = 0.0;
		vec2 cell = vec2(0.0);
		if (ground_floor) {
			vec2 gs = vec2(6.0, 8.4);
			vec2 m = rect_mask(uv - vec2(0.0, 0.3), gs, vec2(5.0, 6.6), fw);
			window = m.x * m.y * step(uv.y, 3.7) * step(0.45, uv.y);
			cell = floor((uv - vec2(0.0, 0.3)) / gs);
		} else {
			vec2 m = rect_mask(uv - vec2(0.0, 4.2), spacing, win, fw);
			window = m.x * m.y;
			cell = floor((uv - vec2(0.0, 4.2)) / spacing);
		}
		float cornice = smoothstep(top - 0.9 - fw.y, top - 0.9 + fw.y, uv.y);
		window *= 1.0 - cornice;

		// Distanz-Fade: Fenster kleiner als ~1.5 Pixel -> Flächenmittel
		float pix = max(fw.x, fw.y) / min(win.x, win.y);
		float fade = 1.0 - smoothstep(0.25, 0.8, pix);
		float avg = (win.x * win.y) / (spacing.x * spacing.y);
		float wmix = mix(avg * 0.85, window, fade);

		vec3 wall = base * (0.88 + 0.24 * hash12(floor(uv * 0.25) + seed * 31.0));
		wall = mix(wall, wall * 0.7, cornice);
		vec3 glass = variant < 0.5 ? vec3(0.03, 0.05, 0.06) : vec3(0.025, 0.028, 0.032);
		albedo = mix(wall, glass, wmix);
		rough = mix(0.85, 0.07, wmix);
		spec = mix(0.5, 0.9, wmix);

		// Nachtbeleuchtung (deterministisch pro Fenster)
		float h = hash12(cell + vec2(seed * 97.0, seed * 13.0));
		float lit = step(0.5, h);
		vec3 warm = mix(vec3(1.0, 0.72, 0.42), vec3(0.75, 0.85, 1.0), step(0.85, h));
		if (ground_floor) {
			float hs = hash12(cell + seed * 41.0);
			vec3 neon = hs < 0.33 ? vec3(1.0, 0.25, 0.55) : (hs < 0.66 ? vec3(0.2, 0.85, 1.0) : vec3(1.0, 0.65, 0.2));
			emission = neon * window * fade * (0.25 + night_factor * 2.6);
		} else {
			float lit_avg = mix(0.5 * avg, window * lit, fade);
			emission = warm * lit_avg * night_factor * 1.8;
		}
	}

	float w = wetness * exposure;
	albedo *= mix(1.0, 0.62, w);
	rough = mix(rough, min(rough, 0.25), w);

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = spec;
	EMISSION = emission;
}
