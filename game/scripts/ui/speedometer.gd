class_name Speedometer
extends Control
## Tacho (km/h), Gang und Drehzahl-Bogen.

var vehicle: Vehicle


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	draw_circle(c, r + 6.0, Color(0.04, 0.05, 0.08, 0.6))
	var start := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	draw_arc(c, r, start, start + sweep, 48, Color(1, 1, 1, 0.2), 8.0, true)
	var rpm_t := clampf((vehicle.rpm - 800.0) / 6200.0, 0.0, 1.0)
	var col := Color(0.3, 0.85, 1.0).lerp(Color(1.0, 0.25, 0.2), smoothstep(0.75, 1.0, rpm_t))
	draw_arc(c, r, start, start + sweep * rpm_t, 48, col, 8.0, true)
	var kmh := int(roundf(absf(vehicle.forward_speed) * 3.6))
	var font := ThemeDB.fallback_font
	var txt := str(kmh)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(font, c + Vector2(-w * 0.5, 10), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)
	draw_string(font, c + Vector2(-16, 34), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	var g := "R" if vehicle.gear < 0 else str(vehicle.gear)
	draw_string(font, c + Vector2(-6, -24), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.85, 0.3))
