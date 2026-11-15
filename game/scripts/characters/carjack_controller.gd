class_name CarJackController
extends Node
## Car-Jacking State Machine (Ein-/Aussteigen, Fahrer herausziehen).
##
##  ON_FOOT ─(Enter, Kandidat)─> APPROACH ─(an Tür)─> [SMASH_WINDOW] ─> OPEN_DOOR
##     OPEN_DOOR ─(Fahrer?)─> PULL_OUT ─> ENTER ─> CLOSE_DOOR ─> DRIVING
##     DRIVING ─(Exit, langsam)─> EXIT_OPEN ─> EXIT_STEP ─> EXIT_CLOSE ─> ON_FOOT
##     DRIVING ─(Exit, schnell)─> BAIL_OUT ─> ON_FOOT (Abrollen)
##  Abbruch in APPROACH, wenn das Ziel wegfährt / zu weit weg / Timeout.
## Jeder Zustand ist zeitgesteuert und interpoliert Transformationen relativ
## zum (evtl. rollenden) Fahrzeug -> kein Clipping, kein "Teleport-Pop".

enum State { ON_FOOT, APPROACH, SMASH_WINDOW, OPEN_DOOR, PULL_OUT, ENTER, CLOSE_DOOR, DRIVING, EXIT_OPEN, EXIT_STEP, EXIT_CLOSE }

const ENTER_RANGE := 4.5
const MAX_JACK_SPEED := 4.0
const BAIL_SPEED := 7.5
const T_SMASH := 0.9
const T_OPEN := 0.38
const T_PULL := 0.95
const T_ENTER := 0.6
const T_CLOSE := 0.3
const T_EXIT_OPEN := 0.35
const T_EXIT_STEP := 0.5
const T_EXIT_CLOSE := 0.3

signal state_changed(new_state: int)
signal driver_ejected(rig: HumanoidRig, position: Vector3, aggressive: bool)

var player: Player
var state: int = State.ON_FOOT
var vehicle: Vehicle = null
var candidate: Vehicle = null
var t := 0.0

var _from := Transform3D()
var _victim: HumanoidRig = null
var _victim_from := Transform3D()
var _victim_released := false
var _smashed := false


func controls_player() -> bool:
	return state != State.ON_FOOT


func is_driving() -> bool:
	return state == State.DRIVING


## Kamera soll dem Fahrzeug folgen?
func camera_on_vehicle() -> bool:
	return state in [State.ENTER, State.CLOSE_DOOR, State.DRIVING, State.EXIT_OPEN]


func _set_state(s: int) -> void:
	state = s
	t = 0.0
	state_changed.emit(s)


func _physics_process(delta: float) -> void:
	t += delta
	if state != State.ON_FOOT and (vehicle == null or not is_instance_valid(vehicle)):
		_force_on_foot()
		return
	match state:
		State.ON_FOOT:
			candidate = _find_candidate()
			if InputHub.take(&"enter") and candidate != null and player.knocked <= 0.0:
				_begin(candidate)
		State.APPROACH:
			_approach(delta)
		State.SMASH_WINDOW:
			_face_door(delta)
			player.rig.pose = HumanoidRig.Pose.SMASH
			if t > T_SMASH * 0.5 and not _smashed:
				_smashed = true
				vehicle.locked = false
				vehicle.trigger_alarm(8.0)
				_glass_burst(vehicle.door_point() + Vector3.UP * 1.1 + vehicle.side_dir() * 0.4)
				Events.panic.emit(vehicle.global_position, 22.0)
				GameConfig.vibrate(40)
			if t >= T_SMASH:
				_set_state(State.OPEN_DOOR)
		State.OPEN_DOOR:
			_face_door(delta)
			player.rig.pose = HumanoidRig.Pose.REACH
			vehicle.door_open_amount = _ease(t / T_OPEN)
			if t >= T_OPEN:
				if vehicle.has_npc_driver():
					_start_pull_out()
				else:
					_start_enter()
		State.PULL_OUT:
			_face_door(delta)
			player.rig.pose = HumanoidRig.Pose.REACH
			_update_pull_out()
			if t >= T_PULL:
				_start_enter()
		State.ENTER:
			var k := _ease(t / T_ENTER)
			var seat := vehicle.seat_transform()
			var xf := _from.interpolate_with(seat, k)
			xf.origin.y += sin(k * PI) * 0.25
			player.global_transform = xf
			player.rig.pose = HumanoidRig.Pose.SIT if k > 0.45 else HumanoidRig.Pose.STAND
			player.rig.move_speed = 0.0
			if t >= T_ENTER:
				_set_state(State.CLOSE_DOOR)
		State.CLOSE_DOOR:
			player.global_transform = vehicle.seat_transform()
			vehicle.door_open_amount = 1.0 - _ease(t / T_CLOSE)
			if t >= T_CLOSE:
				vehicle.door_open_amount = 0.0
				vehicle.door_auto_close = true
				vehicle.set_player_control(true)
				vehicle.occupant = player
				player.rig.visible = false
				_set_state(State.DRIVING)
				Events.vehicle_entered.emit(vehicle)
		State.DRIVING:
			_drive()
		State.EXIT_OPEN:
			player.global_transform = vehicle.seat_transform()
			vehicle.throttle_input = 0.0
			vehicle.brake_input = 0.0
			vehicle.handbrake_input = true
			vehicle.door_open_amount = _ease(t / T_EXIT_OPEN)
			if t >= T_EXIT_OPEN:
				_from = vehicle.seat_transform()
				player.rig.visible = true
				_set_state(State.EXIT_STEP)
		State.EXIT_STEP:
			var k2 := _ease(t / T_EXIT_STEP)
			var stand := _door_stand_transform()
			var xf2 := _from.interpolate_with(stand, k2)
			xf2.origin.y += sin(k2 * PI) * 0.2
			player.global_transform = xf2
			player.rig.pose = HumanoidRig.Pose.STAND if k2 > 0.4 else HumanoidRig.Pose.SIT
			if t >= T_EXIT_STEP:
				_set_state(State.EXIT_CLOSE)
		State.EXIT_CLOSE:
			vehicle.door_open_amount = 1.0 - _ease(t / T_EXIT_CLOSE)
			if t >= T_EXIT_CLOSE:
				_finish_exit()


# --- Zustandslogik --------------------------------------------------------------

func _find_candidate() -> Vehicle:
	var best: Vehicle = null
	var best_d := ENTER_RANGE
	for v in Vehicle.all:
		if not v.is_upright():
			continue
		var d := player.global_position.distance_to(v.door_point())
		var d2 := player.global_position.distance_to(v.global_position) - v.half_length * 0.5
		var dist := minf(d, d2)
		if dist < best_d and v.speed < MAX_JACK_SPEED + 6.0:
			best_d = dist
			best = v
	return best


func _begin(v: Vehicle) -> void:
	vehicle = v
	_smashed = false
	_victim = null
	_victim_released = false
	vehicle.door_auto_close = false
	if v.ai != null:
		v.ai.request_stop()
	Events.carjack_started.emit(v)
	_set_state(State.APPROACH)


func _approach(delta: float) -> void:
	var door := vehicle.door_point()
	var to := door - player.global_position
	to.y = 0.0
	if vehicle.speed > MAX_JACK_SPEED + 4.0 or to.length() > 9.0 or t > 4.0:
		_abort("Zu weit weg")
		return
	if to.length() < 0.35 and vehicle.speed < MAX_JACK_SPEED:
		player.velocity = Vector3.ZERO
		player.rig.move_speed = 0.0
		if vehicle.locked and not vehicle.has_npc_driver():
			Events.toast.emit("Verschlossen – Scheibe wird eingeschlagen", 1.5)
			_set_state(State.SMASH_WINDOW)
		else:
			_set_state(State.OPEN_DOOR)
		return
	var spd := minf(JOG_SPEED, to.length() * 4.0 + 1.0)
	player.velocity = to.normalized() * spd
	player.velocity.y = -1.0
	player.move_and_slide()
	var yaw := atan2(-to.x, -to.z)
	player.rotation.y = lerp_angle(player.rotation.y, yaw, 1.0 - exp(-delta * 14.0))
	player.rig.pose = HumanoidRig.Pose.STAND
	player.rig.move_speed = spd


const JOG_SPEED := 4.6


func _face_door(delta: float) -> void:
	var to_car := -vehicle.side_dir()
	var yaw := atan2(-to_car.x, -to_car.z)
	player.rotation.y = lerp_angle(player.rotation.y, yaw, 1.0 - exp(-delta * 16.0))
	var p := vehicle.door_point()
	player.global_position = player.global_position.lerp(Vector3(p.x, player.global_position.y, p.z), 1.0 - exp(-delta * 10.0))
	player.rig.move_speed = 0.0


func _start_pull_out() -> void:
	_victim = vehicle.driver_rig as HumanoidRig
	vehicle.driver_rig = null
	if _victim == null:
		_start_enter()
		return
	var g := _victim.global_transform
	_victim.get_parent().remove_child(_victim)
	player.get_parent().add_child(_victim)
	_victim.global_transform = g
	_victim.visible = true
	_victim_from = g
	_victim_released = false
	Events.panic.emit(vehicle.global_position, 30.0)
	GameConfig.vibrate(35)
	_set_state(State.PULL_OUT)


func _update_pull_out() -> void:
	if _victim == null or not is_instance_valid(_victim):
		return
	var k := _ease(clampf(t / (T_PULL * 0.7), 0.0, 1.0))
	var out := vehicle.door_point() + vehicle.side_dir() * 1.4
	var face := Basis(Vector3.UP, atan2(-vehicle.side_dir().x, -vehicle.side_dir().z))
	var target := Transform3D(face, out)
	var xf := _victim_from.interpolate_with(target, k)
	xf.origin.y += sin(k * PI) * 0.35
	_victim.global_transform = xf
	_victim.pose = HumanoidRig.Pose.SIT if k < 0.5 else HumanoidRig.Pose.FALLEN
	if k > 0.5:
		_victim.set_fall_direction(false)
	if t >= T_PULL * 0.75 and not _victim_released:
		_victim_released = true
		var pos := Vector3(out.x, 0.0, out.z)
		driver_ejected.emit(_victim, pos, vehicle.driver_aggressive)
		_victim = null


func _start_enter() -> void:
	if _victim != null and not _victim_released and is_instance_valid(_victim):
		_victim_released = true
		driver_ejected.emit(_victim, vehicle.door_point() + vehicle.side_dir() * 1.4, vehicle.driver_aggressive)
		_victim = null
	player.set_collision_enabled(false)
	_from = player.global_transform
	_set_state(State.ENTER)


func _drive() -> void:
	player.global_transform = vehicle.seat_transform()
	vehicle.steer_input = InputHub.steer
	vehicle.throttle_input = InputHub.throttle
	vehicle.brake_input = InputHub.brake
	vehicle.handbrake_input = InputHub.handbrake
	if InputHub.take(&"enter"):
		if absf(vehicle.forward_speed) < BAIL_SPEED:
			vehicle.door_auto_close = false
			_set_state(State.EXIT_OPEN)
		else:
			_bail_out()


func _door_stand_transform() -> Transform3D:
	var p := vehicle.door_point()
	var away := vehicle.side_dir()
	var yaw := atan2(-away.x, -away.z)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.02, p.z))


func _finish_exit() -> void:
	vehicle.door_open_amount = 0.0
	vehicle.door_auto_close = true
	vehicle.set_player_control(false)
	vehicle.occupant = null
	player.global_transform = _door_stand_transform()
	player.set_collision_enabled(true)
	player.rig.visible = true
	player.rig.pose = HumanoidRig.Pose.STAND
	var v := vehicle
	vehicle = null
	_set_state(State.ON_FOOT)
	Events.vehicle_exited.emit(v)


func _bail_out() -> void:
	var v := vehicle
	var side := v.side_dir()
	var vel := v.linear_velocity
	v.set_player_control(false)
	v.parked = false
	v.occupant = null
	v.door_open_amount = 1.0
	v.door_auto_close = true
	var p := v.door_point() + side * 0.4
	player.global_transform = Transform3D(Basis(Vector3.UP, atan2(-vel.x, -vel.z)), Vector3(p.x, 0.3, p.z))
	player.set_collision_enabled(true)
	player.rig.visible = true
	vehicle = null
	_set_state(State.ON_FOOT)
	player.knock_down(vel * 0.55 + side * 3.0 + Vector3.UP * 2.5, 1.5)
	player.take_damage(8.0)
	Events.vehicle_exited.emit(v)
	Events.toast.emit("Abgesprungen!", 1.2)


func _abort(reason: String) -> void:
	if vehicle != null and is_instance_valid(vehicle):
		vehicle.door_auto_close = true
		if vehicle.ai != null:
			vehicle.ai.stop_requested = false
	vehicle = null
	player.set_collision_enabled(true)
	player.rig.pose = HumanoidRig.Pose.STAND
	Events.toast.emit(reason, 1.2)
	_set_state(State.ON_FOOT)


func _force_on_foot() -> void:
	vehicle = null
	player.set_collision_enabled(true)
	player.rig.visible = true
	player.rig.pose = HumanoidRig.Pose.STAND
	var p := player.global_position
	player.global_position = Vector3(p.x, 0.1, p.z)
	_set_state(State.ON_FOOT)


func _ease(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


func _glass_burst(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.04, 0.01)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.85, 0.95)
	mat.roughness = 0.1
	mat.metallic = 0.3
	mesh.material = mat
	p.mesh = mesh
	p.amount = 28
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 1.2
	p.direction = Vector3(0, 0.5, 0)
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -9.8, 0)
	player.get_parent().add_child(p)
	p.global_position = pos
	p.emitting = true
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(p.queue_free)
