// Fahrzeug-Shader (ein Draw-Call pro Karosserie). Material-ID in COLOR.a:
// 1.0 Lack | 0.8 Kunststoff/Gummi | 0.6 Glas | 0.4 Scheinwerfer | 0.2 Rücklicht | 0.0 Chrom
// Nässe: Wasserfilm senkt Rauheit, Tropfen per Surface-Gradient-Bump
// (ohne Tangenten), distanzbasiert ausgeblendet gegen Specular-Aliasing.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

global uniform float wetness;
global uniform float night_factor;

uniform vec4 paint_color : source_color = vec4(0.6, 0.05, 0.05, 1.0);
uniform float paint_metallic = 0.45;
uniform float paint_roughness = 0.3;
uniform float engine_on = 0.0;
uniform float brake_lights = 0.0;
uniform float alarm = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float droplets(vec2 dp) {
	vec2 g = dp * 9.0;
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash12(cell);
	vec2 o = (vec2(hash12(cell + 1.3), hash12(cell + 7.1)) - 0.5) * 0.5;
	float r = 0.12 + 0.16 * h;
	float l = length(f - o) / r;
	return clamp(1.0 - l * l, 0.0, 1.0) * step(0.4, h);
}

vec3 perturb_normal(vec3 n, vec3 pos, float height) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhdx = dFdx(height);
	float dhdy = dFdy(height);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - grad);
}

void fragment() {
	float id = COLOR.a;
	vec3 alb = COLOR.rgb;
	float rough = 0.6;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emis = vec3(0.0);
	float lights = engine_on * clamp(night_factor * 1.5, 0.0, 1.0);
	float blink = alarm * step(0.5, fract(TIME * 2.0));

	if (id > 0.9) {
		alb = paint_color.rgb;
		rough = paint_roughness;
		metal = paint_metallic;
	} else if (id > 0.7) {
		rough = 0.65;
	} else if (id > 0.5) {
		alb = vec3(0.015, 0.018, 0.022);
		rough = 0.04;
		spec = 0.9;
	} else if (id > 0.3) {
		alb = vec3(0.8);
		rough = 0.08;
		emis = vec3(1.0, 0.95, 0.85) * (0.08 + lights * 4.0 + blink * 3.0);
	} else if (id > 0.1) {
		alb = vec3(0.3, 0.015, 0.015);
		rough = 0.12;
		emis = vec3(1.0, 0.04, 0.02) * (0.05 + lights * 1.2 + brake_lights * 3.5 + blink * 3.0);
	} else {
		alb = vec3(0.75);
		rough = 0.12;
		metal = 1.0;
	}

	if (wetness > 0.01) {
		float dist = length(VERTEX);
		float fade = 1.0 - smoothstep(5.0, 16.0, dist);
		vec3 an = abs(world_normal);
		vec2 dp = an.y > 0.6 ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);
		float drop = droplets(dp) * wetness * fade * step(0.5, id);
		NORMAL = perturb_normal(NORMAL, VERTEX, drop * 0.006);
		rough = mix(rough, min(rough, 0.09), wetness);
		if (id > 0.7 && id < 0.9) {
			alb *= 0.8;
		}
	}

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emis;
}
