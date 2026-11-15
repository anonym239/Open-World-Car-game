// Prozeduraler Straßen-/Gehweg-/Platz-Shader.
// Markierungen, Zebrastreifen, Bordsteine und Pfützen werden aus der
// Weltposition berechnet: KEINE überlappende Decal-Geometrie => kein
// Z-Fighting. Alle Muster sind über fwidth() analytisch antialiased und
// werden mit der Distanz zum Mittelwert ausgeblendet => kein Shader-Flimmern.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float wetness;
global uniform float puddle_level;
global uniform float rain_intensity;

uniform bool park = false;

const float CELL = 80.0;
const float ROAD_HALF = 7.0;
const float SIDEWALK_OUT = 11.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 1.0 innerhalb |d| < half_w, mit Pixel-Footprint-Antialiasing.
float band(float d, float half_w, float fw) {
	return 1.0 - smoothstep(half_w - fw, half_w + fw, d);
}

// Regentropfen-Ringe (eine Zelle pro Layer, sehr günstig).
vec2 ripple(vec2 uv, float t, float seed) {
	vec2 cell = floor(uv);
	vec2 f = fract(uv) - 0.5;
	float h = hash12(cell + seed);
	vec2 off = (vec2(hash12(cell + seed + 3.1), hash12(cell + seed + 7.7)) - 0.5) * 0.4;
	vec2 d = f - off;
	float r = length(d);
	float phase = fract(t * (0.8 + 0.4 * h) + h);
	float ring = r - phase * 0.42;
	float amp = (1.0 - phase) * smoothstep(0.0, 0.06, phase);
	float wave = sin(clamp(ring * 45.0, -6.2831, 6.2831)) * exp(-ring * ring * 350.0);
	return (d / max(r, 0.0001)) * wave * amp;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 c = p - round(p / CELL) * CELL;
	vec2 ac = abs(c);
	vec2 fw = max(fwidth(p), vec2(0.0001));
	float fwl = max(fw.x, fw.y);

	float road_x = band(ac.x, ROAD_HALF, fw.x);
	float road_z = band(ac.y, ROAD_HALF, fw.y);
	float road = max(road_x, road_z);
	float walk_x = band(ac.x, SIDEWALK_OUT, fw.x);
	float walk_z = band(ac.y, SIDEWALK_OUT, fw.y);
	float walk = max(walk_x, walk_z) * (1.0 - road);
	float block = clamp(1.0 - road - walk, 0.0, 1.0);

	float n1 = vnoise(p * 1.7);
	float n2 = vnoise(p * 0.13);
	float n3 = vnoise(p * 6.0);

	// --- Asphalt -----------------------------------------------------------
	vec3 asphalt = vec3(0.055, 0.057, 0.062) * (0.85 + 0.3 * n1) * (0.88 + 0.24 * n2);
	asphalt *= 0.92 + 0.16 * n3 * (1.0 - smoothstep(0.02, 0.08, fwl));
	float in_ns = road_x * (1.0 - road_z);
	float in_ew = road_z * (1.0 - road_x);

	// Doppelte Mittellinie (gelb), Parkstreifen-Linie (weiß)
	float center_ns = max(band(abs(ac.x - 0.16), 0.055, fw.x), 0.0) * step(12.0, ac.y) * in_ns;
	float center_ew = band(abs(ac.y - 0.16), 0.055, fw.y) * step(12.0, ac.x) * in_ew;
	float park_ns = band(abs(ac.x - 4.0), 0.06, fw.x) * step(12.0, ac.y) * in_ns;
	float park_ew = band(abs(ac.y - 4.0), 0.06, fw.y) * step(12.0, ac.x) * in_ew;
	// Zebrastreifen
	float zebra_zone_ns = step(7.6, ac.y) * step(ac.y, 10.4) * step(ac.x, 6.6);
	float zebra_zone_ew = step(7.6, ac.x) * step(ac.x, 10.4) * step(ac.y, 6.6);
	float zebra_ns = band(abs(fract(c.x / 1.1) - 0.5), 0.25, fw.x / 1.1) * zebra_zone_ns;
	float zebra_ew = band(abs(fract(c.y / 1.1) - 0.5), 0.25, fw.y / 1.1) * zebra_zone_ew;
	// Haltelinie nur auf der zufahrenden Fahrbahnhälfte
	float stop_ns = band(abs(ac.y - 11.25), 0.22, fw.y) * step(ac.x, 6.8) * step(0.0, c.x * c.y);
	float stop_ew = band(abs(ac.x - 11.25), 0.22, fw.x) * step(ac.y, 6.8) * step(c.x * c.y, 0.0);

	float yellow = max(center_ns, center_ew);
	float white = max(max(park_ns, park_ew), max(max(zebra_ns, zebra_ew), max(stop_ns, stop_ew)));
	float wear = 0.7 + 0.3 * n1;
	vec3 road_col = asphalt;
	road_col = mix(road_col, vec3(0.62, 0.43, 0.06) * wear, yellow);
	road_col = mix(road_col, vec3(0.62, 0.62, 0.6) * wear, white * (1.0 - yellow));

	// --- Gehweg ---------------------------------------------------------------
	vec2 tile_edge = (0.5 - abs(fract(p * 0.5) - 0.5)) * 2.0;
	float groove = max(band(tile_edge.x, 0.025, fw.x), band(tile_edge.y, 0.025, fw.y));
	groove *= 1.0 - smoothstep(0.05, 0.15, fwl);
	vec3 walk_col = vec3(0.26, 0.255, 0.24) * (0.9 + 0.2 * n1) * (1.0 - 0.35 * groove);
	float curb_x = band(abs(ac.x - 7.12), 0.12, fw.x) * (1.0 - road_z) * walk_x;
	float curb_z = band(abs(ac.y - 7.12), 0.12, fw.y) * (1.0 - road_x) * walk_z;
	float curb = max(curb_x, curb_z);
	walk_col = mix(walk_col, vec3(0.38, 0.38, 0.36), curb);

	// --- Blockinneres: Park (Rasen) oder Platz (Pflaster) ---------------------
	vec3 block_col;
	float block_rough;
	if (park) {
		float gn = vnoise(p * 0.35) * 0.6 + vnoise(p * 3.0) * 0.4;
		block_col = mix(vec3(0.045, 0.09, 0.025), vec3(0.08, 0.14, 0.035), gn);
		block_rough = 0.95;
	} else {
		vec2 pe = (0.5 - abs(fract(p) - 0.5)) * 2.0;
		float pg = max(band(pe.x, 0.03, fw.x), band(pe.y, 0.03, fw.y)) * (1.0 - smoothstep(0.03, 0.1, fwl));
		block_col = vec3(0.21, 0.19, 0.17) * (0.88 + 0.24 * n1) * (1.0 - 0.3 * pg);
		block_rough = 0.85;
	}

	vec3 albedo = road_col * road + walk_col * walk + block_col * block;
	float rough = 0.9 * road + 0.85 * walk + block_rough * block;

	// --- Nässe (stufenlos) --------------------------------------------------
	float grass = park ? block : 0.0;
	float wet = wetness * (1.0 - 0.6 * grass);
	albedo *= mix(1.0, 0.5, wet);
	rough = mix(rough, mix(0.2, 0.6, grass), wet);

	// --- Pfützen: statisches Welt-Rauschen + Rinnstein-Bias -------------------
	float pn = vnoise(p * 0.11) * 0.65 + vnoise(p * 0.37 + 17.0) * 0.35;
	float gutter = max(in_ns * smoothstep(5.0, 6.9, ac.x), in_ew * smoothstep(5.0, 6.9, ac.y)) * 0.25;
	float thr = 1.0 - puddle_level * 0.55;
	float pud = smoothstep(thr, thr + 0.06, pn + gutter) * step(0.001, puddle_level) * (1.0 - grass);
	albedo = mix(albedo, albedo * 0.3, pud);
	rough = mix(rough, 0.03, pud);

	vec2 slope = vec2(0.0);
	if (rain_intensity > 0.01 && pud > 0.01) {
		slope = ripple(p * 2.2, TIME, 0.0) + ripple(p * 2.2 + vec2(0.5, 0.37), TIME * 1.13, 5.0);
		slope *= rain_intensity * pud * (1.0 - smoothstep(0.03, 0.12, fwl));
	}
	vec3 nw = normalize(vec3(-slope.x * 0.5, 1.0, -slope.y * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
