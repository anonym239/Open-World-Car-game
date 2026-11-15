extends Node
## Input Abstraction Layer.
## Touch-HUD, Neigungssensor (Gyro/Gravity), Tastatur und Gamepad schreiben in
## diese Schicht; Gameplay-Code liest ausschließlich die normierten Werte.
## Damit sind Steuerungsmodi austauschbar, ohne Gameplay-Code zu ändern.

# --- normierte Ausgabewerte (pro Frame) -------------------------------------
var move := Vector2.ZERO ## Zu Fuß: x = rechts, y = vorwärts, Länge 0..1
var sprint := false
var steer := 0.0 ## Fahrzeug: -1 links … +1 rechts
var throttle := 0.0 ## 0..1
var brake := 0.0 ## 0..1 (Bremse, bei Stillstand Rückwärtsgang)
var handbrake := false

# --- Rohwerte vom Touch-HUD ---------------------------------------------------
var touch_move := Vector2.ZERO
var touch_sprint := false
var touch_steer := 0.0
var touch_throttle := 0.0
var touch_brake := 0.0
var touch_handbrake := false

## Wenn aktiv (Smoke-Test-Autopilot), werden die Ausgabewerte nicht überschrieben.
var override_active := false

var _look := Vector2.ZERO
var _pressed := {}
var _kb_steer := 0.0
var _tilt_filtered := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func press(action: StringName) -> void:
	_pressed[action] = true


## Flankengesteuerte Aktion abholen (jump, punch, enter, camera, radio, pause).
func take(action: StringName) -> bool:
	if _pressed.has(action):
		_pressed.erase(action)
		return true
	return false


func clear_presses() -> void:
	_pressed.clear()


func add_look(delta: Vector2) -> void:
	_look += delta


func consume_look() -> Vector2:
	var l := _look
	_look = Vector2.ZERO
	return l


func _process(delta: float) -> void:
	if override_active:
		return
	var kb := Vector2(
		_key_axis(KEY_D, KEY_A) + _key_axis(KEY_RIGHT, KEY_LEFT),
		_key_axis(KEY_W, KEY_S) + _key_axis(KEY_UP, KEY_DOWN))
	var pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if pad.length() < 0.15:
		pad = Vector2.ZERO
	move = (touch_move + kb + pad).limit_length(1.0)
	sprint = touch_sprint or Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK)

	# Tastatur-Lenkung mit Rampe (digitale Eingabe -> analoges Verhalten)
	var kb_target := clampf(kb.x, -1.0, 1.0)
	var rate := 3.5 if absf(kb_target) > 0.01 else 6.0
	_kb_steer = move_toward(_kb_steer, kb_target, rate * delta)

	var tilt := 0.0
	if GameConfig.steering_mode == GameConfig.Steering.TILT:
		tilt = _tilt_steer(delta)
	steer = clampf(touch_steer + _kb_steer + tilt + pad.x, -1.0, 1.0)

	var kb_gas := 1.0 if (Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) else 0.0
	var kb_brake := 1.0 if (Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) else 0.0
	var pad_gas := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	var pad_brake := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	throttle = clampf(maxf(maxf(touch_throttle, kb_gas), pad_gas), 0.0, 1.0)
	brake = clampf(maxf(maxf(touch_brake, kb_brake), pad_brake), 0.0, 1.0)
	handbrake = touch_handbrake or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)

	var look_pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look_pad.length() > 0.15:
		_look += look_pad * 900.0 * delta


## Neigungslenkung: Schwerkraftvektor in Bildschirmkoordinaten (Godot
## kompensiert die Display-Rotation). Kalibrierbar, mit Tiefpass + Deadzone.
func _tilt_steer(delta: float) -> float:
	var g := Input.get_gravity()
	if g.length() < 0.5:
		g = Input.get_accelerometer()
	if g.length() < 0.5:
		return 0.0
	var raw := -g.x / g.length() - GameConfig.tilt_neutral
	if GameConfig.tilt_invert:
		raw = -raw
	var v := clampf(raw / sin(deg_to_rad(26.0)), -1.0, 1.0)
	if absf(v) < 0.06:
		v = 0.0
	_tilt_filtered = lerpf(_tilt_filtered, v, 1.0 - exp(-delta * 14.0))
	return _tilt_filtered


## Aktuellen Neigungswinkel als neutrale Lage speichern.
func calibrate_tilt() -> void:
	var g := Input.get_gravity()
	if g.length() < 0.5:
		g = Input.get_accelerometer()
	if g.length() >= 0.5:
		GameConfig.tilt_neutral = -g.x / g.length()


func _key_axis(pos: Key, neg: Key) -> float:
	var v := 0.0
	if Input.is_physical_key_pressed(pos):
		v += 1.0
	if Input.is_physical_key_pressed(neg):
		v -= 1.0
	return v


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_F, KEY_ENTER:
				press(&"enter")
			KEY_SPACE:
				press(&"jump")
			KEY_E, KEY_Q:
				press(&"punch")
			KEY_C:
				press(&"camera")
			KEY_R:
				press(&"radio")
			KEY_ESCAPE, KEY_P:
				press(&"pause")
	var jb := event as InputEventJoypadButton
	if jb != null and jb.pressed:
		match jb.button_index:
			JOY_BUTTON_Y:
				press(&"enter")
			JOY_BUTTON_A:
				press(&"jump")
			JOY_BUTTON_X:
				press(&"punch")
			JOY_BUTTON_RIGHT_SHOULDER:
				press(&"camera")
			JOY_BUTTON_LEFT_SHOULDER:
				press(&"radio")
			JOY_BUTTON_START:
				press(&"pause")
