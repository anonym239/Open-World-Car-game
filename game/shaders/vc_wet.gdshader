// Generischer Vertex-Color-Shader für Figuren, Laternen, Bäume, Räder.
// COLOR.a = Materialklasse: 1.0 matt (Stoff/Haut/Rinde) | 0.66 Metall |
// 0.33 Dauerleuchten (Neon) | 0.0 Nachtleuchten (Laternenkopf)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

global uniform float wetness;
global uniform float night_factor;

uniform float base_roughness = 0.78;
uniform float wet_exposure = 1.0;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 alb = COLOR.rgb;
	float cls = COLOR.a;
	float rough = base_roughness;
	float metal = 0.0;
	vec3 emis = vec3(0.0);
	if (cls < 0.2) {
		emis = alb * (0.15 + night_factor * 5.0);
		rough = 0.3;
	} else if (cls < 0.5) {
		emis = alb * 1.6;
	} else if (cls < 0.8) {
		metal = 0.85;
		rough = 0.35;
	}
	float w = wetness * wet_exposure * (0.6 + 0.4 * clamp(world_normal.y, 0.0, 1.0));
	alb *= mix(1.0, 0.62, w * step(0.8, cls));
	rough = mix(rough, rough * 0.45, w);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emis;
}
