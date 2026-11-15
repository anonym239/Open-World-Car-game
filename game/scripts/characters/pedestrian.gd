class_name Pedestrian
extends CharacterBody3D
## Passanten-KI (leichtgewichtig): läuft Gehweg-Rundwege um Blöcke,
## reagiert auf Panik-Events (Flucht / Ducken), Schläge (Gegenwehr / Flucht),
## wird von Fahrzeugen umgestoßen. Herausgezerrte Fahrer starten frei
## (free_roam) und kehren danach auf den nächsten Rundweg zurück.

enum Mode { WALK, IDLE, FLEE, FIGHT, KNOCKED, COWER, OUT }

var rig: HumanoidRig
var mode: int = Mode.WALK
var block := Vector2i.ZERO
var s := 0.0
var dir := 1.0
var walk_speed := 1.3
var health := 100.0
var aggressive := false
var free_roam := false
var timer := 0.0
var panic_origin := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _fight_cd := 0.0
var _pending_hit := -1.0
var _after_knock: int = Mode.FLEE


func setup(seed_value: int, rig_in: HumanoidRig = null) -> void:
	_rng.seed = seed_value
	collision_layer = 8
	collision_mask = 1 | 2
	floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.875, 0)
	add_child(cs)
	if rig_in != null:
		rig = rig_in
		var g := rig.global_transform
		if rig.get_parent() != null:
			rig.get_parent().remove_child(rig)
		add_child(rig)
		rig.transform = Transform3D.IDENTITY
		rotation.y = g.basis.get_euler().y
	else:
		rig = HumanoidRig.new()
		rig.setup(seed_value)
		add_child(rig)
	var blob := WorldMaterials.make_blob_shadow(Vector3(0.9, 2.0, 0.9))
	blob.position = Vector3(0, 0.5, 0)
	add_child(blob)
	walk_speed = _rng.randf_range(1.1, 1.6)
	aggressive = _rng.randf() < 0.15
	dir = 1.0 if _rng.randf() < 0.5 else -1.0
	add_to_group("npc")


func _ready() -> void:
	Events.panic.connect(_on_panic)


func place_on_ring(c: Vector2i, s0: float) -> void:
	block = c
	s = s0
	free_roam = false
	position = CityLayout.ring_point(c, s0) + Vector3.UP * 0.05


func start_ejected(is_aggressive: bool) -> void:
	free_roam = true
	aggressive = is_aggressive
	health = 100.0
	_knock(Vector3.ZERO, 1.3, Mode.FIGHT if is_aggressive else Mode.FLEE)
	panic_origin = WorldState.player.global_position if WorldState.player != null else global_position
	if is_aggressive:
		Events.toast.emit("Der Fahrer will sich wehren!", 1.5)


func _physics_process(delta: float) -> void:
	timer -= delta
	_fight_cd = maxf(_fight_cd - delta, 0.0)
	var hv := Vector3.ZERO
	match mode:
		Mode.WALK:
			hv = _ring_velocity(walk_speed)
			rig.pose = HumanoidRig.Pose.STAND
			if timer <= 0.0:
				timer = _rng.randf_range(6.0, 16.0)
				if _rng.randf() < 0.25:
					mode = Mode.IDLE
					timer = _rng.randf_range(1.5, 4.0)
		Mode.IDLE:
			rig.pose = HumanoidRig.Pose.STAND
			if timer <= 0.0:
				mode = Mode.WALK
				if _rng.randf() < 0.3:
					dir = -dir
				timer = _rng.randf_range(6.0, 16.0)
		Mode.COWER:
			rig.pose = HumanoidRig.Pose.COWER
			if timer <= 0.0:
				_start_flee(panic_origin)
		Mode.FLEE:
			rig.pose = HumanoidRig.Pose.STAND
			if free_roam:
				var away := global_position - panic_origin
				away.y = 0.0
				if away.length() < 0.1:
					away = Vector3.FORWARD
				hv = away.normalized() * 5.2
			else:
				hv = _ring_velocity(5.0)
			if timer <= 0.0:
				_rejoin_ring()
				mode = Mode.WALK
				timer = _rng.randf_range(6.0, 12.0)
		Mode.FIGHT:
			hv = _fight(delta)
		Mode.KNOCKED:
			rig.pose = HumanoidRig.Pose.FALLEN
			velocity.x = move_toward(velocity.x, 0.0, delta * 8.0)
			velocity.z = move_toward(velocity.z, 0.0, delta * 8.0)
			hv = Vector3(velocity.x, 0.0, velocity.z)
			if timer <= 0.0:
				if health <= 0.0:
					mode = Mode.OUT
					timer = 20.0
				else:
					rig.pose = HumanoidRig.Pose.STAND
					if _after_knock == Mode.FIGHT and WorldState.player != null:
						mode = Mode.FIGHT
						timer = 14.0
					else:
						_start_flee(panic_origin)
		Mode.OUT:
			rig.pose = HumanoidRig.Pose.FALLEN
			if timer <= 0.0:
				queue_free()
				return

	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = velocity.y - 16.0 * delta if not is_on_floor() else -0.5
	move_and_slide()
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.2 and mode != Mode.KNOCKED and mode != Mode.OUT:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), 1.0 - exp(-delta * 10.0))
	rig.move_speed = flat.length() if mode != Mode.KNOCKED else 0.0
	if mode != Mode.KNOCKED and mode != Mode.OUT:
		_check_vehicle_hits()


func _ring_velocity(spd: float) -> Vector3:
	s = fposmod(s + dir * spd * get_physics_process_delta_time(), CityLayout.RING_LENGTH)
	var target := CityLayout.ring_point(block, s + dir * 1.0)
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return Vector3.ZERO
	return to.normalized() * spd * clampf(to.length(), 0.3, 1.5)


func _fight(delta: float) -> Vector3:
	var p := WorldState.player as Player
	if p == null or not p.is_on_foot() or timer <= 0.0 or p.health <= 0.0:
		_start_flee(global_position + Vector3(1, 0, 0))
		return Vector3.ZERO
	rig.pose = HumanoidRig.Pose.FIGHT
	var to := p.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if _pending_hit >= 0.0:
		_pending_hit -= delta
		if _pending_hit < 0.0 and d < 1.5:
			p.take_damage(9.0)
			if _rng.randf() < 0.25:
				p.knock_down(to.normalized() * 3.0 + Vector3.UP * 1.5, 1.0)
	if d < 1.1:
		if _fight_cd <= 0.0:
			_fight_cd = 1.0
			_pending_hit = 0.18
			rig.punch()
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-delta * 12.0))
		return Vector3.ZERO
	return to.normalized() * 3.8


func _start_flee(origin: Vector3) -> void:
	panic_origin = origin
	mode = Mode.FLEE
	timer = _rng.randf_range(6.0, 10.0)
	if not free_roam:
		var ahead := CityLayout.ring_point(block, s + 3.0).distance_to(origin)
		var behind := CityLayout.ring_point(block, s - 3.0).distance_to(origin)
		dir = 1.0 if ahead > behind else -1.0


func _rejoin_ring() -> void:
	if free_roam:
		block = CityLayout.chunk_of(global_position)
		s = CityLayout.ring_param(block, global_position)
		free_roam = false


func _on_panic(origin: Vector3, radius: float) -> void:
	if mode in [Mode.KNOCKED, Mode.OUT, Mode.FIGHT]:
		return
	if global_position.distance_to(origin) > radius:
		return
	panic_origin = origin
	if mode != Mode.FLEE:
		mode = Mode.COWER
		timer = _rng.randf_range(0.3, 0.9)


func take_hit(from: Vector3, damage: float) -> void:
	health -= damage
	var away := global_position - from
	away.y = 0.0
	Events.panic.emit(global_position, 14.0)
	if health <= 0.0 or _rng.randf() < 0.35:
		_knock(away.normalized() * 2.5 + Vector3.UP * 1.5, 1.6, Mode.FIGHT if aggressive else Mode.FLEE)
	elif aggressive and mode != Mode.FIGHT:
		mode = Mode.FIGHT
		timer = 14.0
	elif not aggressive:
		_start_flee(from)


func _knock(impulse: Vector3, seconds: float, after: int) -> void:
	velocity = impulse
	mode = Mode.KNOCKED
	timer = seconds
	_after_knock = after
	rig.set_fall_direction(impulse.dot(-global_transform.basis.z) > 0.0)
	rig.pose = HumanoidRig.Pose.FALLEN


func _check_vehicle_hits() -> void:
	for v in Vehicle.all:
		if v.speed < 3.5:
			continue
		if global_position.distance_squared_to(v.global_position) > 16.0:
			continue
		var local := v.global_transform.affine_inverse() * (global_position + Vector3.UP * 0.6)
		if absf(local.x) < v.half_width + 0.3 and absf(local.z) < v.half_length + 0.3 and local.y < 1.5:
			health -= v.speed * 3.0
			_knock(v.linear_velocity * 0.7 + Vector3.UP * 3.5, 2.2, Mode.FLEE)
			Events.panic.emit(global_position, 20.0)
			if v.ai != null:
				v.ai.request_stop()
			return
