// Ampeln: Zustand kommt global aus 'traffic_phase' (vom TrafficManager),
// die Achse (Nord-Süd / Ost-West) aus der Instanz-Orientierung.
// => Keine Per-Ampel-Updates auf der CPU, beliebig viele Instanzen (MultiMesh).
// COLOR.a: 1 = Gehäuse, 0 = Lampe; COLOR.r (Lampe): 0 rot, 0.5 gelb, 1 grün.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

global uniform float traffic_phase;
global uniform float night_factor;

varying float v_axis;

void vertex() {
	vec3 facing = MODEL_MATRIX[2].xyz;
	v_axis = abs(facing.x) > abs(facing.z) ? 1.0 : 0.0;
}

void fragment() {
	if (COLOR.a > 0.5) {
		ALBEDO = COLOR.rgb;
		ROUGHNESS = 0.6;
		METALLIC = 0.3;
	} else {
		int code = int(traffic_phase + 0.5);
		int state = 2;
		if (v_axis < 0.5) {
			state = code == 0 ? 0 : (code == 1 ? 1 : 2);
		} else {
			state = code == 3 ? 0 : (code == 4 ? 1 : 2);
		}
		int lamp = COLOR.r < 0.25 ? 2 : (COLOR.r < 0.75 ? 1 : 0);
		vec3 col = lamp == 2 ? vec3(1.0, 0.07, 0.04) : (lamp == 1 ? vec3(1.0, 0.55, 0.04) : vec3(0.08, 1.0, 0.35));
		float on = lamp == state ? 1.0 : 0.0;
		ALBEDO = col * 0.12;
		ROUGHNESS = 0.2;
		EMISSION = col * mix(0.02, 2.6 + night_factor * 2.0, on);
	}
}
