class_name TouchControls
extends Control
## Multi-Touch-Router + Zeichnung aller HUD-Bedienelemente.
##
## Architektur: EIN Eingabe-Handler mit "Finger-Besitz" (finger index ->
## Widget/Stick/Kamera). Ein Finger gehört ab dem Aufsetzen genau einem
## Element -> keine Doppelbelegung, kein "Klau" durch andere Controls.
## Pedale erlauben Daumen-Gleiten (Gas <-> Bremse ohne Absetzen).
## Alle Elemente skalieren mit HUD-Skalierung und respektieren Safe-Areas.

enum Mode { FOOT, VEHICLE }

class Widget:
	var id: StringName
	var center := Vector2.ZERO
	var radius := 50.0
	var rect := Rect2()
	var label := ""
	var visible := true
	var pressed := false
	var finger := -1
	var pulse := false
	var mode := 0

	func is_pill() -> bool:
		return rect.size.x > 0.0

	func hit(p: Vector2) -> bool:
		if not visible:
			return false
		if is_pill():
			return rect.grow(14.0).has_point(p)
		return p.distance_to(center) <= radius * 1.18


var mode: int = Mode.FOOT
var widgets: Array[Widget] = []
var by_id := {}
var enter_available := false

# Stick
var stick_finger := -1
var stick_base := Vector2.ZERO
var stick_knob := Vector2.ZERO
var stick_radius := 95.0
var stick_home := Vector2.ZERO
var stick_value := Vector2.ZERO
# Kamera
var look_finger := -1
var look_last := Vector2.ZERO

var _gas := 0.0
var _brake := 0.0
var _btn_steer := 0.0
var _scale := 1.0
var _safe := Rect2()
var _font: Font
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_create_widgets()
	resized.connect(_layout)
	Events.settings_changed.connect(_layout)
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_release_all()


func _add(id: StringName, label: String, m: int) -> Widget:
	var w := Widget.new()
	w.id = id
	w.label = label
	w.mode = m
	widgets.append(w)
	by_id[id] = w
	return w


func _create_widgets() -> void:
	_add(&"punch", "Schlag", Mode.FOOT)
	_add(&"jump", "Sprung", Mode.FOOT)
	_add(&"sprint", "Sprint", Mode.FOOT)
	var enter := _add(&"enter", "Einsteigen", Mode.FOOT)
	enter.pulse = true
	_add(&"gas", "GAS", Mode.VEHICLE)
	_add(&"brake", "BREMSE", Mode.VEHICLE)
	_add(&"handbrake", "Handbremse", Mode.VEHICLE)
	_add(&"exit", "Aussteigen", Mode.VEHICLE)
	_add(&"camera", "Kamera", Mode.VEHICLE)
	_add(&"radio", "Radio", Mode.VEHICLE)
	_add(&"left", "", Mode.VEHICLE)
	_add(&"right", "", Mode.VEHICLE)
	_add(&"pause", "", -1)


func _safe_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var r := Rect2(Vector2.ZERO, vs)
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return r
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0:
		return r
	var k := vs / Vector2(win)
	var left := maxf(safe.position.x * k.x, 0.0)
	var top := maxf(safe.position.y * k.y, 0.0)
	var right := maxf((win.x - safe.end.x) * k.x, 0.0)
	var bottom := maxf((win.y - safe.end.y) * k.y, 0.0)
	return Rect2(Vector2(left, top), vs - Vector2(left + right, top + bottom))


func _layout() -> void:
	_scale = clampf(GameConfig.hud_scale, 0.7, 1.4)
	_safe = _safe_rect()
	var S := _scale
	var r := _safe
	var R := r.end.x
	var B := r.end.y
	var T := r.position.y
	var L := r.position.x
	# Zu Fuß: rechter Daumen-Bogen
	_place(&"punch", Vector2(R - 108 * S, B - 118 * S), 68 * S)
	_place(&"jump", Vector2(R - 258 * S, B - 92 * S), 48 * S)
	_place(&"sprint", Vector2(R - 250 * S, B - 238 * S), 46 * S)
	_place(&"enter", Vector2(R - 112 * S, B - 292 * S), 56 * S)
	# Fahrzeug: Pedale unten rechts
	var gas: Widget = by_id[&"gas"]
	gas.rect = Rect2(Vector2(R - (28 + 130) * S, B - (24 + 190) * S), Vector2(130, 190) * S)
	var brake: Widget = by_id[&"brake"]
	brake.rect = Rect2(Vector2(gas.rect.position.x - (22 + 120) * S, B - (24 + 150) * S), Vector2(120, 150) * S)
	_place(&"handbrake", Vector2(gas.rect.position.x - 11 * S, gas.rect.position.y - 72 * S), 52 * S)
	_place(&"exit", Vector2(R - 140 * S, T + 62 * S), 42 * S)
	_place(&"camera", Vector2(R - 235 * S, T + 56 * S), 34 * S)
	_place(&"radio", Vector2(R - 318 * S, T + 56 * S), 34 * S)
	_place(&"left", Vector2(L + 105 * S, B - 115 * S), 70 * S)
	_place(&"right", Vector2(L + 265 * S, B - 115 * S), 70 * S)
	_place(&"pause", Vector2(R - 48 * S, T + 44 * S), 30 * S)
	stick_radius = 95.0 * S
	stick_home = Vector2(L + 175 * S, B - 165 * S)
	if stick_finger < 0:
		stick_base = stick_home
		stick_knob = stick_home
	queue_redraw()


func _place(id: StringName, c: Vector2, rad: float) -> void:
	var w: Widget = by_id[id]
	w.center = c
	w.radius = rad


func set_mode(m: int) -> void:
	if m == mode:
		return
	mode = m
	_release_all()


func _release_all() -> void:
	for w in widgets:
		w.pressed = false
		w.finger = -1
	stick_finger = -1
	stick_value = Vector2.ZERO
	stick_base = stick_home
	stick_knob = stick_home
	look_finger = -1


func _widget_active(w: Widget) -> bool:
	if w.mode != -1 and w.mode != mode:
		return false
	if w.id == &"enter":
		return enter_available
	if w.id == &"left" or w.id == &"right":
		return GameConfig.steering_mode == GameConfig.Steering.BUTTONS
	return true


func _stick_used() -> bool:
	if mode == Mode.FOOT:
		return true
	return GameConfig.steering_mode == GameConfig.Steering.STICK


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null and not touch.pressed:
		# Loslassen IMMER verarbeiten (auch wenn ausgeblendet), sonst bleiben
		# Buttons/Pedale nach Sequenzen oder Menüs "hängen".
		_on_up(touch.index)
		return
	if not is_visible_in_tree():
		return
	if touch != null:
		_on_down(touch.index, touch.position)
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		_on_drag(drag.index, drag.position, drag.relative)


func _on_down(i: int, p: Vector2) -> void:
	for w in widgets:
		w.visible = _widget_active(w)
		if w.finger == -1 and w.hit(p):
			w.finger = i
			w.pressed = true
			_on_press(w)
			queue_redraw()
			return
	var vs := get_viewport_rect().size
	if _stick_used() and stick_finger == -1 and p.x < vs.x * 0.42 and p.y > vs.y * 0.28:
		stick_finger = i
		if GameConfig.dynamic_stick:
			stick_base = p
		else:
			stick_base = stick_home
		stick_knob = p
		_update_stick()
		queue_redraw()
		return
	if look_finger == -1 and p.x >= vs.x * 0.42:
		look_finger = i
		look_last = p


func _on_drag(i: int, p: Vector2, rel: Vector2) -> void:
	if i == stick_finger:
		stick_knob = p
		_update_stick()
		queue_redraw()
		return
	if i == look_finger:
		InputHub.add_look(rel)
		look_last = p
		return
	for w in widgets:
		if w.finger != i:
			continue
		# Daumen-Gleiten zwischen den Pedalen
		if w.id == &"gas" or w.id == &"brake":
			var other: Widget = by_id[&"brake" if w.id == &"gas" else &"gas"]
			if not w.hit(p) and other.hit(p) and other.finger == -1:
				w.finger = -1
				w.pressed = false
				other.finger = i
				other.pressed = true
				GameConfig.vibrate(8)
				queue_redraw()
		return


func _on_up(i: int) -> void:
	if i == stick_finger:
		stick_finger = -1
		stick_value = Vector2.ZERO
		stick_base = stick_home
		stick_knob = stick_home
		queue_redraw()
	if i == look_finger:
		look_finger = -1
	for w in widgets:
		if w.finger == i:
			w.finger = -1
			w.pressed = false
			queue_redraw()


func _update_stick() -> void:
	var d := stick_knob - stick_base
	if d.length() > stick_radius:
		if GameConfig.dynamic_stick:
			# Basis folgt dem Daumen ("Floating Stick")
			stick_base = stick_knob - d.normalized() * stick_radius
		d = d.limit_length(stick_radius)
	var v := d / stick_radius
	var dz := 0.12 if mode == Mode.FOOT else 0.07
	var m := v.length()
	if m < dz:
		stick_value = Vector2.ZERO
		return
	var remapped := (m - dz) / (1.0 - dz)
	if mode == Mode.VEHICLE:
		remapped = pow(remapped, 1.35)
	stick_value = v.normalized() * clampf(remapped, 0.0, 1.0)


func _on_press(w: Widget) -> void:
	GameConfig.vibrate(12)
	match w.id:
		&"punch":
			InputHub.press(&"punch")
		&"jump":
			InputHub.press(&"jump")
		&"enter", &"exit":
			InputHub.press(&"enter")
		&"camera":
			InputHub.press(&"camera")
		&"radio":
			InputHub.press(&"radio")
		&"pause":
			InputHub.press(&"pause")


func _process(delta: float) -> void:
	_time += delta
	for w in widgets:
		w.visible = _widget_active(w)
	if mode == Mode.FOOT:
		InputHub.touch_move = Vector2(stick_value.x, -stick_value.y)
		InputHub.touch_sprint = (by_id[&"sprint"] as Widget).pressed
		InputHub.touch_steer = 0.0
		InputHub.touch_throttle = 0.0
		InputHub.touch_brake = 0.0
		InputHub.touch_handbrake = false
	else:
		InputHub.touch_move = Vector2.ZERO
		InputHub.touch_sprint = false
		var gas_on := (by_id[&"gas"] as Widget).pressed
		var brake_on := (by_id[&"brake"] as Widget).pressed
		# Rampen: digitale Touch-Pedale fühlen sich analog an
		_gas = move_toward(_gas, 1.0 if gas_on else 0.0, delta / (0.15 if gas_on else 0.08))
		_brake = move_toward(_brake, 1.0 if brake_on else 0.0, delta / (0.1 if brake_on else 0.06))
		InputHub.touch_throttle = _gas
		InputHub.touch_brake = _brake
		InputHub.touch_handbrake = (by_id[&"handbrake"] as Widget).pressed
		if GameConfig.steering_mode == GameConfig.Steering.STICK:
			InputHub.touch_steer = stick_value.x
		elif GameConfig.steering_mode == GameConfig.Steering.BUTTONS:
			var target := 0.0
			if (by_id[&"left"] as Widget).pressed:
				target -= 1.0
			if (by_id[&"right"] as Widget).pressed:
				target += 1.0
			var rate := 3.2 if absf(target) > 0.0 else 6.0
			_btn_steer = move_toward(_btn_steer, target, rate * delta)
			InputHub.touch_steer = _btn_steer
		else:
			InputHub.touch_steer = 0.0
	if enter_available and mode == Mode.FOOT:
		queue_redraw()


# --- Zeichnen ------------------------------------------------------------------

func _draw() -> void:
	for w in widgets:
		if not _widget_active(w):
			continue
		_draw_widget(w)
	if _stick_used():
		var active := stick_finger >= 0
		var a := 0.32 if active else 0.14
		draw_circle(stick_base, stick_radius, Color(0, 0, 0, a * 0.8))
		draw_arc(stick_base, stick_radius, 0.0, TAU, 48, Color(1, 1, 1, a + 0.1), 2.5 * _scale, true)
		draw_circle(stick_knob if active else stick_base, 40.0 * _scale, Color(1, 1, 1, 0.55 if active else 0.22))
		if mode == Mode.VEHICLE:
			_tri(stick_base + Vector2(-stick_radius - 22 * _scale, 0), -1.0, 14 * _scale, Color(1, 1, 1, a + 0.2))
			_tri(stick_base + Vector2(stick_radius + 22 * _scale, 0), 1.0, 14 * _scale, Color(1, 1, 1, a + 0.2))


func _draw_widget(w: Widget) -> void:
	var white := Color(1, 1, 1, 0.92)
	var bg := Color(0, 0, 0, 0.38)
	if w.pressed:
		bg = Color(1, 1, 1, 0.32)
	if w.is_pill():
		var rr := w.rect
		if w.pressed:
			rr = rr.grow(-4.0 * _scale)
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg if w.id != &"gas" else Color(0.05, 0.35, 0.12, 0.5 if not w.pressed else 0.75)
		if w.id == &"brake":
			sb.bg_color = Color(0.4, 0.05, 0.05, 0.5 if not w.pressed else 0.75)
		sb.set_corner_radius_all(int(22 * _scale))
		sb.border_color = Color(1, 1, 1, 0.55)
		sb.set_border_width_all(int(maxf(2.0 * _scale, 1.0)))
		draw_style_box(sb, rr)
		_text(rr.get_center() + Vector2(0, 8 * _scale), w.label, int(24 * _scale), white)
		if w.id == &"brake":
			_text(rr.get_center() + Vector2(0, 34 * _scale), "/ R", int(16 * _scale), Color(1, 1, 1, 0.7))
		return
	var rad := w.radius * (0.94 if w.pressed else 1.0)
	if w.pulse:
		var k := 0.5 + 0.5 * sin(_time * 6.0)
		draw_circle(w.center, rad + 8 * _scale * k, Color(1.0, 0.8, 0.2, 0.25 * k))
	draw_circle(w.center, rad, bg)
	draw_arc(w.center, rad, 0.0, TAU, 40, Color(1, 1, 1, 0.55), maxf(2.0 * _scale, 1.0), true)
	_icon(w, rad, white)


func _text(center: Vector2, text: String, size: int, col: Color) -> void:
	if text.is_empty():
		return
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, Vector2(center.x - width * 0.5, center.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _tri(c: Vector2, dir: float, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(dir * s, 0), c + Vector2(-dir * s * 0.6, -s), c + Vector2(-dir * s * 0.6, s)]), col)


func _icon(w: Widget, rad: float, col: Color) -> void:
	var c := w.center
	var s := rad * 0.42
	var lw := maxf(3.0 * _scale, 1.5)
	match w.id:
		&"punch":
			draw_rect(Rect2(c - Vector2(s * 0.8, s * 0.6), Vector2(s * 1.6, s * 1.2)), col, false, lw)
			for k in 3:
				var x := c.x - s * 0.8 + s * 0.53 * float(k + 1)
				draw_line(Vector2(x, c.y - s * 0.6), Vector2(x, c.y - s * 0.1), col, lw * 0.7)
			draw_line(c + Vector2(-s * 0.8, s * 0.6), c + Vector2(-s * 0.8, s * 1.1), col, lw)
		&"jump":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(-s * 0.8, 0), c + Vector2(s * 0.8, 0)]), col)
			draw_line(c, c + Vector2(0, s), col, lw * 1.4)
		&"sprint":
			for k in 2:
				var o := Vector2(s * 0.55 * float(k) - s * 0.3, 0)
				draw_polyline(PackedVector2Array([c + o + Vector2(-s * 0.35, -s * 0.6), c + o + Vector2(s * 0.25, 0), c + o + Vector2(-s * 0.35, s * 0.6)]), col, lw)
		&"enter", &"exit":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 1.1, s * 0.4), c + Vector2(-s * 0.6, -s * 0.2), c + Vector2(s * 0.5, -s * 0.2),
				c + Vector2(s * 1.1, s * 0.4)]), Color(col.r, col.g, col.b, 0.35))
			draw_rect(Rect2(c + Vector2(-s * 1.15, s * 0.35), Vector2(s * 2.3, s * 0.45)), col, false, lw * 0.8)
			var dir := 1.0 if w.id == &"exit" else -1.0
			draw_line(c + Vector2(0, -s * 0.9), c + Vector2(dir * s * 0.9, -s * 0.9), col, lw)
			_tri(c + Vector2(dir * s * 0.9, -s * 0.9), dir, s * 0.3, col)
			_text(c + Vector2(0, rad + 20 * _scale), w.label, int(15 * _scale), col)
		&"handbrake":
			_text(c + Vector2(0, s * 0.45), "H", int(rad * 0.9), col)
			draw_arc(c, s * 1.45, deg_to_rad(200), deg_to_rad(340), 16, col, lw * 0.7)
		&"camera":
			draw_rect(Rect2(c - Vector2(s * 0.9, s * 0.55), Vector2(s * 1.8, s * 1.1)), col, false, lw * 0.8)
			draw_arc(c, s * 0.35, 0.0, TAU, 16, col, lw * 0.8)
		&"radio":
			draw_line(c + Vector2(-s * 0.3, s * 0.6), c + Vector2(-s * 0.3, -s * 0.7), col, lw * 0.8)
			draw_line(c + Vector2(s * 0.6, s * 0.4), c + Vector2(s * 0.6, -s * 0.9), col, lw * 0.8)
			draw_line(c + Vector2(-s * 0.3, -s * 0.7), c + Vector2(s * 0.6, -s * 0.9), col, lw * 0.8)
			draw_circle(c + Vector2(-s * 0.5, s * 0.6), s * 0.28, col)
			draw_circle(c + Vector2(s * 0.4, s * 0.4), s * 0.28, col)
		&"left":
			_tri(c, -1.0, s * 1.2, col)
		&"right":
			_tri(c, 1.0, s * 1.2, col)
		&"pause":
			draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.8), Vector2(s * 0.45, s * 1.6)), col)
			draw_rect(Rect2(c + Vector2(s * 0.25, -s * 0.8), Vector2(s * 0.45, s * 1.6)), col)
