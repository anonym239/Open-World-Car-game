// Regenstreifen (GPU-Partikel, gekreuzte Quads, an der Geschwindigkeit
// ausgerichtet => Windablenkung sichtbar). Unbeleuchtet, kein Tiefen-Schreiben.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

global uniform float night_factor;
uniform float opacity = 0.32;

void fragment() {
	float a = smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.55, UV.y);
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = mix(vec3(0.72, 0.77, 0.85), vec3(0.32, 0.36, 0.45), night_factor);
	ALPHA = a * edge * opacity * COLOR.a;
}
