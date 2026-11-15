// Dynamischer Himmel: Tag/Nacht-Verlauf, Sonne, Mond, Sterne, prozedurale
// Wolken mit wetterabhängiger Bedeckung. Wolkenbewegung kommt als Uniform
// (niedrige Update-Rate) statt TIME, damit die Radiance-Cubemap auf Mobile
// nicht jedes Frame neu gefiltert werden muss.
shader_type sky;

uniform vec3 sun_dir = vec3(0.3, 0.8, 0.2);
uniform vec3 moon_dir = vec3(-0.3, 0.6, -0.2);
uniform float cloud_cover = 0.3;
uniform float storm = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float flash = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	float sun_h = sd.y;
	float day = smoothstep(-0.12, 0.22, sun_h);
	float twilight = smoothstep(-0.25, 0.0, sun_h) * (1.0 - smoothstep(0.0, 0.3, sun_h));
	float toward_sun = pow(max(dot(normalize(vec3(dir.x, 0.0, dir.z) + 0.0001), normalize(vec3(sd.x, 0.0, sd.z) + 0.0001)), 0.0), 3.0);

	vec3 zenith = mix(vec3(0.004, 0.006, 0.018), vec3(0.09, 0.22, 0.55), day);
	vec3 horizon = mix(vec3(0.015, 0.02, 0.04), vec3(0.5, 0.62, 0.78), day);
	horizon += twilight * mix(vec3(0.35, 0.12, 0.08), vec3(1.1, 0.42, 0.12), toward_sun);
	float y = max(dir.y, 0.0);
	vec3 col = mix(horizon, zenith, pow(y, 0.45));

	float gray = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(gray) * (0.75 + 0.25 * day), cloud_cover * 0.75);
	col *= 1.0 - storm * 0.55;

	// Sterne + Mond
	if (!AT_CUBEMAP_PASS) {
		float star = step(0.9975, hash13(floor(dir * 260.0))) * (1.0 - day) * (1.0 - cloud_cover) * smoothstep(0.05, 0.3, dir.y);
		col += vec3(star) * 0.8;
	}
	float md = dot(dir, normalize(moon_dir));
	col += vec3(0.75, 0.8, 0.95) * smoothstep(0.9990, 0.9994, md) * (1.0 - day) * (1.0 - cloud_cover * 0.8) * 1.5;

	// Sonne
	float sdot = dot(dir, sd);
	float sun_vis = smoothstep(-0.05, 0.02, sun_h) * (1.0 - cloud_cover * 0.92);
	col += vec3(1.0, 0.88, 0.7) * (smoothstep(0.9994, 0.9997, sdot) * 22.0 + pow(max(sdot, 0.0), 80.0) * (0.5 + twilight * 1.5)) * sun_vis;

	// Wolken (Ebenenprojektion)
	if (dir.y > 0.0) {
		vec2 cuv = dir.xz / (dir.y + 0.12) * 0.7 + cloud_offset;
		float n = fbm(cuv * 1.3);
		float cov = clamp(cloud_cover, 0.0, 1.0);
		float c = smoothstep(1.0 - cov - 0.1, 1.0 - cov + 0.35, n);
		vec3 lit = mix(vec3(0.05, 0.055, 0.07), vec3(0.95, 0.95, 0.97), day);
		lit += twilight * vec3(0.7, 0.3, 0.1) * toward_sun;
		lit *= mix(1.0, 0.45, storm) * (0.75 + 0.25 * (1.0 - n));
		col = mix(col, lit, c * smoothstep(0.0, 0.15, dir.y) * 0.95);
	} else {
		col = mix(horizon * 0.6, vec3(0.03, 0.03, 0.035) * (0.3 + day), smoothstep(0.0, -0.3, dir.y));
	}
	col += vec3(0.6, 0.65, 0.8) * flash;
	COLOR = col;
}
