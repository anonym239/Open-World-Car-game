class_name Player
extends CharacterBody3D
## Spielfigur zu Fuß: kamerarelative Bewegung (Gehen/Joggen/Sprinten),
## Sprung, Schlag, Umfallen (Treffer/Unfall), Gesundheit & Respawn.
## Ein- und Aussteigen übernimmt der CarJackController.

const WALK := 2.0
const JOG := 4.6
const SPRINT := 7.2
const JUMP_V := 5.0
const GRAVITY := 16.0

var rig: HumanoidRig
var carjack: CarJackController
var health := 100.0
var knocked := 0.0
var _shape: CollisionShape3D
var _punch_cd := 0.0
var _pending_hit := -1.0
var _ko_timer := -1.0
var _regen_delay := 0.0


func _ready() -> void:
	name = "Player"
	collision_layer = 4
	collision_mask = 1 | 2
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	_shape.shape = cap
	_shape.position = Vector3(0, 0.9, 0)
	add_child(_shape)
	rig = HumanoidRig.new()
	rig.name = "Rig"
	rig.setup(424242, Color(0.08, 0.1, 0.14))
	add_child(rig)
	var blob := WorldMaterials.make_blob_shadow(Vector3(1.0, 2.0, 1.0))
	blob.position = Vector3(0, 0.5, 0)
	add_child(blob)
	carjack = CarJackController.new()
	carjack.name = "CarJack"
	carjack.player = self
	add_child(carjack)
	WorldState.player = self
	add_to_group("player")


func set_collision_enabled(on: bool) -> void:
	_shape.disabled = not on
	collision_layer = 4 if on else 0


func is_on_foot() -> bool:
	return carjack.state == CarJackController.State.ON_FOOT


func _physics_process(delta: float) -> void:
	_punch_cd = maxf(_punch_cd - delta, 0.0)
	_regen_delay = maxf(_regen_delay - delta, 0.0)
	if _regen_delay <= 0.0 and health < 100.0 and _ko_timer < 0.0:
		health = minf(health + delta * 4.0, 100.0)
	if _ko_timer >= 0.0:
		_ko_timer += delta
		velocity = velocity.move_toward(Vector3.ZERO, delta * 8.0)
		move_and_slide()
		if _ko_timer > 3.5:
			_respawn()
		return
	if carjack.controls_player():
		return
	if knocked > 0.0:
		knocked -= delta
		velocity.y -= GRAVITY * delta
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, delta * 9.0)
			velocity.z = move_toward(velocity.z, 0.0, delta * 9.0)
		move_and_slide()
		rig.pose = HumanoidRig.Pose.FALLEN
		rig.move_speed = 0.0
		if knocked <= 0.0:
			rig.pose = HumanoidRig.Pose.STAND
		InputHub.clear_presses()
		return
	_locomotion(delta)
	_combat(delta)
	_check_vehicle_hits()


func _locomotion(delta: float) -> void:
	var input := InputHub.move
	var cam := WorldState.camera
	var fwd := Vector3.FORWARD
	if cam != null:
		fwd = -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var wish := right * input.x + fwd * input.y
	var mag := clampf(input.length(), 0.0, 1.0)
	var target_speed := 0.0
	if mag > 0.05:
		target_speed = SPRINT * mag if InputHub.sprint else lerpf(WALK * 0.5, JOG, mag)
	var desired := wish.normalized() * target_speed if mag > 0.05 else Vector3.ZERO
	var accel := 24.0 if is_on_floor() else 5.0
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		if InputHub.take(&"jump"):
			velocity.y = JUMP_V
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if hv.length() > 0.3:
		var yaw := atan2(-hv.x, -hv.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-delta * 12.0))
	rig.pose = HumanoidRig.Pose.STAND
	rig.move_speed = hv.length()
	rig.lean = clampf(hv.length() / SPRINT, 0.0, 1.0) * 0.06


func _combat(delta: float) -> void:
	if InputHub.take(&"punch") and _punch_cd <= 0.0:
		_punch_cd = 0.45
		_pending_hit = 0.16
		rig.punch()
	if _pending_hit >= 0.0:
		_pending_hit -= delta
		if _pending_hit < 0.0:
			var fwd := -global_transform.basis.z
			for n in get_tree().get_nodes_in_group("npc"):
				var npc := n as Pedestrian
				if npc == null:
					continue
				var to := npc.global_position - global_position
				to.y = 0.0
				if to.length() < 1.4 and fwd.dot(to.normalized()) > 0.3:
					npc.take_hit(global_position, 34.0)
					GameConfig.vibrate(25)


## Prüft Überfahren werden (Fahrzeuge kollidieren physikalisch nicht mit
## Figuren, damit Autos nicht an Menschen "abprallen").
func _check_vehicle_hits() -> void:
	for v in Vehicle.all:
		if v.speed < 4.0:
			continue
		var local := v.global_transform.affine_inverse() * (global_position + Vector3.UP * 0.6)
		if absf(local.x) < v.half_width + 0.3 and absf(local.z) < v.half_length + 0.3 and local.y < 1.5:
			knock_down(v.linear_velocity * 0.6 + Vector3.UP * 3.0, 1.6)
			take_damage(v.speed * 2.2)
			return


func knock_down(impulse: Vector3, seconds: float) -> void:
	if not is_on_foot():
		return
	velocity = impulse
	knocked = seconds
	rig.set_fall_direction(impulse.dot(-global_transform.basis.z) > 0.0)
	rig.pose = HumanoidRig.Pose.FALLEN
	GameConfig.vibrate(60)


func take_damage(amount: float) -> void:
	if _ko_timer >= 0.0:
		return
	health -= amount
	_regen_delay = 5.0
	if health <= 0.0:
		health = 0.0
		_ko_timer = 0.0
		rig.pose = HumanoidRig.Pose.FALLEN
		Events.player_knocked_out.emit()
		Events.toast.emit("K.O. – du wirst gleich wieder aufgestellt", 3.0)


func _respawn() -> void:
	_ko_timer = -1.0
	health = 100.0
	knocked = 0.0
	var c := CityLayout.chunk_of(global_position)
	var s := CityLayout.ring_param(c, global_position)
	global_position = CityLayout.ring_point(c, s) + Vector3.UP * 0.1
	velocity = Vector3.ZERO
	rig.pose = HumanoidRig.Pose.STAND
