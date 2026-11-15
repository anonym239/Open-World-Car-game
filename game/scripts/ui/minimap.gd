class_name Minimap
extends Control
## Vektor-Minimap (kein Render-Target -> praktisch kostenlos):
## Straßenraster, Fahrzeuge, Spielerpfeil; rotiert mit der Kamera.

const RANGE := 170.0

var _canvas: Control


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.72)
	sb.set_corner_radius_all(18)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))


func _draw_map() -> void:
	var player := WorldState.player
	var cam := WorldState.camera
	if player == null:
		return
	var center := size * 0.5
	var k := (minf(size.x, size.y) * 0.5) / RANGE
	var origin := player.global_position
	var fwd := Vector3.FORWARD
	if cam != null:
		fwd = -cam.global_transform.basis.z
	var ang := atan2(fwd.x, -fwd.z)
	var to_map := func(p: Vector3) -> Vector2:
		var d := Vector2(p.x - origin.x, p.z - origin.z).rotated(-ang)
		return center + d * k

	var C := CityLayout.CELL
	var road_w := CityLayout.ROAD_HALF * 2.0 * k
	var road_col := Color(0.55, 0.58, 0.62, 0.9)
	var i0 := floori((origin.x - RANGE * 1.5) / C)
	var i1 := ceili((origin.x + RANGE * 1.5) / C)
	var j0 := floori((origin.z - RANGE * 1.5) / C)
	var j1 := ceili((origin.z + RANGE * 1.5) / C)
	for i in range(i0, i1 + 1):
		var a: Vector2 = to_map.call(Vector3(i * C, 0, origin.z - RANGE * 1.5))
		var b: Vector2 = to_map.call(Vector3(i * C, 0, origin.z + RANGE * 1.5))
		_canvas.draw_line(a, b, road_col, road_w)
	for j in range(j0, j1 + 1):
		var a: Vector2 = to_map.call(Vector3(origin.x - RANGE * 1.5, 0, j * C))
		var b: Vector2 = to_map.call(Vector3(origin.x + RANGE * 1.5, 0, j * C))
		_canvas.draw_line(a, b, road_col, road_w)

	for v in Vehicle.all:
		var p: Vector2 = to_map.call(v.global_position)
		if p.distance_to(center) > size.x:
			continue
		var col := Color(0.95, 0.75, 0.2) if v.is_player_vehicle() else Color(0.3, 0.75, 1.0, 0.85)
		_canvas.draw_circle(p, 3.5 if not v.is_player_vehicle() else 5.0, col)

	# Spielerpfeil (zeigt Blickrichtung der Figur relativ zur Kamera)
	var pf := -player.global_transform.basis.z
	var pa := atan2(pf.x, -pf.z) - ang
	var tip := Vector2(0, -11).rotated(pa)
	var l := Vector2(-7, 8).rotated(pa)
	var r := Vector2(7, 8).rotated(pa)
	_canvas.draw_colored_polygon(PackedVector2Array([center + tip, center + l, center + r]), Color(1, 1, 1))
	# Norden
	var n: Vector2 = Vector2(0, -1).rotated(-ang) * (minf(size.x, size.y) * 0.5 - 14.0) + center
	_canvas.draw_string(ThemeDB.fallback_font, n + Vector2(-5, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.4, 0.3))
