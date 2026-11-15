class_name Vehicle
extends RigidBody3D
## Raycast-Fahrzeug (Arcade-Simulation, mobil-tauglich).
##
## Pro Rad: Federbein als Raycast (Feder + Dämpfer + Stabilisator), Reifen-
## kräfte über Geschwindigkeits-Constraint (lateral) + Antrieb/Bremse
## (longitudinal), begrenzt durch den Reibungskreis (mu * Radlast).
## Touch-Assists: geschwindigkeitsabhängiger Lenkwinkel, Lenkraten-Limit,
## Gegenlenk-Assistent, Selbstaufrichtung.
## Alles läuft in _integrate_forces -> schlafende (geparkte) Autos kosten 0 CPU.

enum Drive { NONE, PLAYER, AI }

const WHEEL_MASK := 1 | 2
const STATIC_COMP := 0.085

signal impact(strength: float)

## Registry aller Fahrzeuge (schneller als Gruppen-Abfragen pro Frame).
static var all: Array[Vehicle] = []

var spec: Dictionary = {}
var drive_mode: int = Drive.NONE
var parked := true

# --- Eingaben (normiert) ---
var steer_input := 0.0
var throttle_input := 0.0
var brake_input := 0.0
var handbrake_input := false

# --- Parameter (aus spec) ---
var wheel_radius := 0.34
var rest_length := 0.30
var spring_k := 40000.0
var damper_c := 4000.0
var anti_roll := 9000.0
var engine_force := 8000.0
var reverse_force := 4200.0
var brake_force := 12000.0
var max_speed := 50.0
var grip := 1.25
var drive_front := 0.0
var max_steer := deg_to_rad(36.0)
var wheelbase := 2.7
var half_width := 0.9
var half_length := 2.25
var wheel_mounts: Array[Vector3] = []

# --- Zustand ---
var steer_angle := 0.0
var forward_speed := 0.0
var speed := 0.0
var wheel_contact: Array[bool] = [false, false, false, false]
var wheel_dist := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var wheel_spin := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var wheel_spin_rate := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var wheel_slip := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var grounded_wheels := 0
var is_braking := false
var gear := 1
var rpm := 900.0

# --- Komposition ---
var visual_root: Node3D
var wheel_nodes: Array[Node3D] = []
var door_pivot: Node3D
var paint_material: ShaderMaterial
var driver_rig: Node3D = null
var driver_aggressive := false
var occupant: Node3D = null
var ai: TrafficDriver = null
var locked := false
var alarm_timer := 0.0
var door_open_amount := 0.0
var door_auto_close := true
var seat_local := Vector3(-0.38, -0.55, 0.1)
var door_local := Vector3(-1.5, 0.0, -0.2)

var _ray := PhysicsRayQueryParameters3D.new()
var _upside_timer := 0.0
var _reset_requested := false
var _brake_state := -1.0
var _engine_state := -1.0
var _alarm_state := -1.0
var _headlights: Array[SpotLight3D] = []
var _impact_cooldown := 0.0
var _sleep_timer := 0.0


func apply_spec(s: Dictionary) -> void:
	spec = s
	wheel_radius = s["wheel_r"]
	rest_length = s["rest"]
	mass = s["mass"]
	engine_force = s["engine"]
	max_speed = s["max_speed"]
	grip = s["grip"]
	drive_front = s["drive_front"]
	half_width = s["hw"]
	half_length = s["hl"]
	var af: float = s["axle_f"]
	var ar: float = s["axle_r"]
	var tr: float = s["track"]
	wheelbase = ar - af
	wheel_mounts = [Vector3(-tr, 0, af), Vector3(tr, 0, af), Vector3(-tr, 0, ar), Vector3(tr, 0, ar)]
	spring_k = mass * 9.81 * 0.25 / STATIC_COMP
	damper_c = 2.0 * 0.42 * sqrt(spring_k * mass * 0.25)
	anti_roll = spring_k * 0.35
	brake_force = mass * 9.0
	reverse_force = engine_force * 0.5
	for i in 4:
		wheel_dist[i] = rest_length + wheel_radius - STATIC_COMP
	var hood_h: float = s["hood_h"]
	var cowl_z: float = s["cowl_z"]
	seat_local = Vector3(-0.37, hood_h - 0.88, cowl_z + 0.85)
	door_local = Vector3(-(half_width + 0.62), 0.0, cowl_z + 0.5)


## Fahrhöhe des Chassis-Ursprungs über dem Boden im Gleichgewicht.
func ride_height() -> float:
	return rest_length + wheel_radius - STATIC_COMP


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 2
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.22, 0.05)
	angular_damp = 0.6
	_ray.collision_mask = WHEEL_MASK
	_ray.exclude = [get_rid()]
	add_to_group("vehicles")
	all.append(self)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.5
	pm.bounce = 0.05
	physics_material_override = pm


func _exit_tree() -> void:
	all.erase(self)


# --- Steuerung von außen ------------------------------------------------------

func set_player_control(on: bool) -> void:
	if on:
		drive_mode = Drive.PLAYER
		parked = false
		can_sleep = false
		sleeping = false
		ai = null
		_create_headlights()
	else:
		drive_mode = Drive.NONE
		can_sleep = true
		throttle_input = 0.0
		brake_input = 0.0
		steer_input = 0.0
		handbrake_input = false
		_remove_headlights()


func set_ai(driver: TrafficDriver) -> void:
	ai = driver
	drive_mode = Drive.AI
	parked = false
	can_sleep = false
	sleeping = false


func has_npc_driver() -> bool:
	return driver_rig != null and is_instance_valid(driver_rig)


func is_player_vehicle() -> bool:
	return drive_mode == Drive.PLAYER


func seat_transform() -> Transform3D:
	return global_transform * Transform3D(Basis(), seat_local)


func door_point() -> Vector3:
	var p := global_transform * door_local
	p.y = 0.0
	return p


func side_dir() -> Vector3:
	## Richtung von der Fahrertür nach außen (links)
	return -global_transform.basis.x


func is_upright() -> bool:
	return global_transform.basis.y.y > 0.6


func trigger_alarm(seconds: float) -> void:
	alarm_timer = seconds


# --- Physik ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)
	match drive_mode:
		Drive.AI:
			if ai != null:
				ai.update(delta)
		Drive.NONE:
			throttle_input = 0.0
			steer_input = move_toward(steer_input, 0.0, delta * 2.0)
			brake_input = 0.0
			handbrake_input = parked
	_update_lights(delta)
	# Selbstaufrichtung nach Überschlag
	if global_transform.basis.y.y < 0.35 and linear_velocity.length() < 2.0:
		_upside_timer += delta
		if _upside_timer > 2.5:
			_upside_timer = 0.0
			_reset_requested = true
			if drive_mode == Drive.PLAYER:
				Events.toast.emit("Fahrzeug aufgerichtet", 1.5)
	else:
		_upside_timer = 0.0
	# Verlassene Autos wieder schlafen legen (spart CPU)
	if drive_mode == Drive.NONE and not sleeping:
		if linear_velocity.length() < 0.15 and angular_velocity.length() < 0.15:
			_sleep_timer += delta
			if _sleep_timer > 1.5:
				parked = true
				sleeping = true
				_sleep_timer = 0.0
		else:
			_sleep_timer = 0.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var xf := state.transform
	if _reset_requested:
		_reset_requested = false
		var f := -xf.basis.z
		f.y = 0.0
		if f.length() < 0.1:
			f = Vector3.FORWARD
		var yaw := atan2(-f.x, -f.z)
		state.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(xf.origin.x, ride_height() + 0.6, xf.origin.z))
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return

	var b := xf.basis
	var up := b.y
	var fwd := -b.z
	var v := state.linear_velocity
	forward_speed = v.dot(fwd)
	speed = v.length()
	_update_steering(dt, v, b)

	# Fahrlogik: Gas / Bremse / Rückwärts (Bremse im Stand = Rückwärtsgang)
	var drive := 0.0
	var braking := 0.0
	var want_fwd := throttle_input > 0.05
	var want_back := brake_input > 0.05
	if want_fwd and not want_back:
		if forward_speed < -1.0:
			braking = throttle_input
		else:
			drive = throttle_input
	elif want_back and not want_fwd:
		if forward_speed > 1.0:
			braking = brake_input
		else:
			drive = -brake_input
	elif want_fwd and want_back:
		braking = brake_input
	is_braking = braking > 0.05 or (handbrake_input and drive_mode != Drive.NONE)
	_update_gearbox(drive)

	var space := state.get_space_state()
	var ray_len := rest_length + wheel_radius
	var comp := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var hit_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var hit_nrm: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
	grounded_wheels = 0
	for i in 4:
		var mount := xf * wheel_mounts[i]
		_ray.from = mount
		_ray.to = mount - up * (ray_len + 0.05)
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			wheel_contact[i] = false
			wheel_dist[i] = ray_len
			continue
		var hp: Vector3 = hit["position"]
		var dist := mount.distance_to(hp)
		if dist > ray_len:
			wheel_contact[i] = false
			wheel_dist[i] = ray_len
			continue
		wheel_contact[i] = true
		wheel_dist[i] = dist
		comp[i] = ray_len - dist
		hit_pos[i] = hp
		hit_nrm[i] = hit["normal"]
		grounded_wheels += 1

	var m_wheel := mass * 0.25
	for i in 4:
		if not wheel_contact[i]:
			wheel_spin_rate[i] = lerpf(wheel_spin_rate[i], 0.0, dt * 0.5)
			continue
		var mount := xf * wheel_mounts[i]
		var rel_mount := mount - xf.origin
		var pv := state.get_velocity_at_local_position(rel_mount)
		var comp_vel := -pv.dot(up)
		var fz := spring_k * comp[i] + damper_c * comp_vel
		var other := i ^ 1
		if wheel_contact[other]:
			fz += (comp[i] - comp[other]) * anti_roll
		fz = clampf(fz, 0.0, mass * 9.81 * 2.5)
		state.apply_force(up * fz, rel_mount)

		var n := hit_nrm[i]
		var wf := fwd
		if i < 2:
			wf = fwd.rotated(up, -steer_angle)
		wf = (wf - n * wf.dot(n)).normalized()
		var wr := wf.cross(n)
		var rel_c := hit_pos[i] - xf.origin
		var cv := state.get_velocity_at_local_position(rel_c)
		var v_long := cv.dot(wf)
		var v_lat := cv.dot(wr)
		var max_f := grip * fz

		# Lateral: Geschwindigkeits-Constraint (stabil, kein Pacejka-Jitter bei 0 km/h)
		var gf := 0.9 if i < 2 else 0.82
		if i >= 2 and handbrake_input and drive_mode != Drive.NONE and absf(forward_speed) > 3.0:
			gf = 0.1
			max_f *= 0.6
		var lat := -v_lat * gf * m_wheel / dt

		# Longitudinal: Antrieb, Bremse, Rollwiderstand, Motorbremse
		var share := drive_front * 0.5 if i < 2 else (1.0 - drive_front) * 0.5
		var lon := 0.0
		if drive > 0.0:
			lon = drive * _engine_curve(forward_speed) * share
		elif drive < 0.0:
			lon = drive * reverse_force * clampf(1.0 - absf(forward_speed) / 11.0, 0.0, 1.0) * share
		var bf := braking * brake_force * 0.25
		if handbrake_input and i >= 2:
			bf = maxf(bf, brake_force * 0.35)
		var stop_cap := absf(v_long) * m_wheel / dt
		lon -= signf(v_long) * minf(bf, stop_cap)
		lon -= v_long * 6.0
		if drive == 0.0 and braking == 0.0:
			lon -= v_long * 12.0

		var f2 := Vector2(lon, lat)
		var flen := f2.length()
		if flen > max_f and flen > 0.0:
			wheel_slip[i] = clampf((flen - max_f) / maxf(max_f, 1.0), 0.0, 1.0)
			f2 *= max_f / flen
		else:
			wheel_slip[i] = 0.0
		var force := wf * f2.x + wr * f2.y
		state.apply_force(force, rel_c + up * (wheel_radius * 0.8))

		if i >= 2 and handbrake_input and absf(forward_speed) > 1.0:
			wheel_spin_rate[i] = 0.0
		else:
			wheel_spin_rate[i] = v_long / wheel_radius

	# Aerodynamik + Abtrieb
	state.apply_central_force(-v * speed * 0.42)
	if grounded_wheels > 0:
		state.apply_central_force(-up * speed * speed * 1.1)
	else:
		# Luftstabilisierung: sanft Richtung aufrecht drehen
		var corr := up.cross(Vector3.UP)
		state.apply_torque(corr * mass * 2.5)
	# Geschwindigkeitsbegrenzung (Sicherheitsnetz gegen Physik-Explosionen)
	if speed > max_speed * 1.25:
		state.linear_velocity = v * (max_speed * 1.25 / speed)


func _engine_curve(v: float) -> float:
	var x := clampf(absf(v) / max_speed, 0.0, 1.0)
	return engine_force * (1.0 - x * x * x)


func _update_steering(dt: float, v: Vector3, b: Basis) -> void:
	var limit := max_steer
	if drive_mode == Drive.PLAYER:
		# geschwindigkeitsabhängiger Lenkeinschlag (Touch-freundlich)
		limit = lerpf(max_steer, max_steer * 0.3, clampf(absf(forward_speed) / 38.0, 0.0, 1.0))
	var target := steer_input * limit
	if drive_mode == Drive.PLAYER and forward_speed > 4.0 and not handbrake_input:
		# Gegenlenk-Assistent: lenkt in Richtung der tatsächlichen Bewegung
		var lv := b.inverse() * v
		var beta := atan2(lv.x, maxf(-lv.z, 0.1))
		target += clampf(beta * 0.55, -0.3, 0.3)
	var rate := 2.4 if absf(target) > absf(steer_angle) else 4.5
	if drive_mode == Drive.AI:
		rate = 3.0
	steer_angle = move_toward(steer_angle, target, rate * dt)


func _update_gearbox(drive: float) -> void:
	var ratios := [0.0, 11.0, 20.0, 30.0, 41.0, 53.0, 70.0]
	var s := absf(forward_speed)
	if drive < 0.0 and forward_speed < 0.5:
		gear = -1
		rpm = 1000.0 + s / 11.0 * 4500.0
		return
	var g := 1
	while g < ratios.size() - 1 and s > float(ratios[g]):
		g += 1
	gear = g
	var lo: float = ratios[g - 1]
	var hi: float = ratios[g]
	var t := clampf((s - lo) / maxf(hi - lo, 0.1), 0.0, 1.0)
	var idle := 850.0 + drive * 400.0
	rpm = lerpf(rpm, maxf(idle, 1600.0 + t * 4800.0 if s > 0.5 else idle), 0.25)


func _process(delta: float) -> void:
	for i in wheel_nodes.size():
		var w := wheel_nodes[i]
		var mount := wheel_mounts[i]
		w.position = Vector3(mount.x, -(wheel_dist[i] - wheel_radius), mount.z)
		if i < 2:
			w.rotation.y = -steer_angle
		wheel_spin[i] = wrapf(wheel_spin[i] + wheel_spin_rate[i] * delta, -PI, PI)
		if w.get_child_count() > 0:
			(w.get_child(0) as Node3D).rotation.x = -wheel_spin[i]
	if door_auto_close and door_open_amount > 0.0:
		door_open_amount = move_toward(door_open_amount, 0.0, delta * 1.2)
	if door_pivot != null:
		door_pivot.rotation.y = -deg_to_rad(68.0) * door_open_amount
	if alarm_timer > 0.0:
		alarm_timer -= delta


func _update_lights(_delta: float) -> void:
	if paint_material == null:
		return
	var engine := 1.0 if drive_mode != Drive.NONE else 0.0
	if engine != _engine_state:
		_engine_state = engine
		paint_material.set_shader_parameter("engine_on", engine)
	var br := 1.0 if (is_braking and drive_mode != Drive.NONE) else 0.0
	if br != _brake_state:
		_brake_state = br
		paint_material.set_shader_parameter("brake_lights", br)
	var al := 1.0 if alarm_timer > 0.0 else 0.0
	if al != _alarm_state:
		_alarm_state = al
		paint_material.set_shader_parameter("alarm", al)
	for l in _headlights:
		l.light_energy = 3.0 * clampf(WorldState.night_factor * 1.5, 0.0, 1.0)
		l.visible = WorldState.night_factor > 0.05


func _create_headlights() -> void:
	if not _headlights.is_empty():
		return
	var hood_h: float = spec.get("hood_h", 0.3)
	for sx in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.position = Vector3(sx * half_width * 0.62, hood_h - 0.12, -half_length - 0.05)
		l.rotation = Vector3(-0.07, 0.0, 0.0)
		l.spot_range = 40.0
		l.spot_angle = 30.0
		l.spot_attenuation = 0.8
		l.light_color = Color(1.0, 0.95, 0.85)
		l.shadow_enabled = false
		l.light_energy = 0.0
		add_child(l)
		_headlights.append(l)


func _remove_headlights() -> void:
	for l in _headlights:
		l.queue_free()
	_headlights.clear()


func _on_body_entered(body: Node) -> void:
	if _impact_cooldown > 0.0:
		return
	var other_v := Vector3.ZERO
	if body is RigidBody3D:
		other_v = (body as RigidBody3D).linear_velocity
	var strength := (linear_velocity - other_v).length()
	if strength < 3.0:
		return
	_impact_cooldown = 0.4
	impact.emit(strength)
	if ai != null and body is Vehicle and (body as Vehicle).is_player_vehicle():
		ai.panic()
	if strength > 8.0 and drive_mode == Drive.NONE and not locked:
		trigger_alarm(6.0)
	if strength > 6.0:
		Events.panic.emit(global_position, 18.0)
