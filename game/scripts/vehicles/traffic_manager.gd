class_name TrafficManager
extends Node3D
## Verkehr: fahrende KI-Autos (Spawn außerhalb der Sicht, Despawn auf Distanz),
## parkende Autos pro Chunk (schlafende Rigidbodies = ~0 CPU) und die globale
## Ampelschaltung (ein Shader-Global für alle Ampeln).

var chunk_manager: ChunkManager
var target_moving := 12
var spawn_min := 70.0
var spawn_max := 170.0
var despawn_dist := 230.0
var light_time := 0.0

var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _moving: Array[Vehicle] = []
var _orphans: Array[Vehicle] = []
var _serial := 0
var _last_code := -1


func configure(tier: int) -> void:
	target_moving = [5, 9, 13][clampi(tier, 0, 2)]
	_rng.seed = 8080


func attach(cm: ChunkManager) -> void:
	chunk_manager = cm
	cm.chunk_loaded.connect(_on_chunk_loaded)
	cm.chunk_unloading.connect(_on_chunk_unloading)


func moving_count() -> int:
	return _moving.size()


func _physics_process(delta: float) -> void:
	light_time += delta
	var code := CityLayout.phase_code(light_time)
	WorldState.traffic_code = code
	if code != _last_code:
		_last_code = code
		RenderingServer.global_shader_parameter_set(&"traffic_phase", float(code))
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var player := WorldState.player
	if player == null:
		return
	var origin := player.global_position
	var cam := WorldState.camera
	_cleanup(origin, cam)
	if _moving.size() < target_moving:
		_try_spawn_moving(origin, cam)


func _cleanup(origin: Vector3, cam: Camera3D) -> void:
	var keep: Array[Vehicle] = []
	for v in _moving:
		if not is_instance_valid(v):
			continue
		if v.drive_mode != Vehicle.Drive.AI:
			# vom Spieler übernommen / verlassen -> nicht mehr Teil des Verkehrs
			_orphans.append(v)
			continue
		var d := v.global_position.distance_to(origin)
		var in_view := cam != null and cam.is_position_in_frustum(v.global_position)
		var stuck := v.ai != null and v.ai.stuck_time > 12.0
		if d > despawn_dist or ((stuck or not v.is_upright()) and not in_view and d > 40.0):
			_despawn(v)
		else:
			keep.append(v)
	_moving = keep
	var keep_o: Array[Vehicle] = []
	for v in _orphans:
		if not is_instance_valid(v):
			continue
		if v.is_player_vehicle() or v.global_position.distance_to(origin) < despawn_dist:
			keep_o.append(v)
		else:
			_despawn(v)
	_orphans = keep_o


func _despawn(v: Vehicle) -> void:
	if v.is_player_vehicle():
		return
	v.queue_free()


func _try_spawn_moving(origin: Vector3, cam: Camera3D) -> void:
	for attempt in 8:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(spawn_min, spawn_max)
		var guess := origin + Vector3(cos(ang), 0.0, sin(ang)) * r
		var n := Vector2i(roundi(guess.x / CityLayout.CELL), roundi(guess.z / CityLayout.CELL))
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var d: Vector2i = dirs[_rng.randi_range(0, 3)]
		var along := _rng.randf_range(18.0, CityLayout.CELL - 30.0)
		var pos := CityLayout.lane_point(n, d, along)
		if chunk_manager != null and not chunk_manager.is_loaded(pos):
			continue
		var dist := pos.distance_to(origin)
		if dist < spawn_min * 0.8:
			continue
		if cam != null and dist < 120.0 and cam.is_position_in_frustum(pos + Vector3.UP):
			continue
		if not _free_spot(pos, 10.0):
			continue
		_spawn_ai(n, d, pos)
		return


func _free_spot(pos: Vector3, radius: float) -> bool:
	for v in Vehicle.all:
		if v.global_position.distance_to(pos) < radius:
			return false
	var p := WorldState.player
	if p != null and p.global_position.distance_to(pos) < radius:
		return false
	return true


func _spawn_ai(n: Vector2i, d: Vector2i, pos: Vector3) -> Vehicle:
	_serial += 1
	var seed_value := _rng.randi()
	var r2 := RandomNumberGenerator.new()
	r2.seed = seed_value
	var v := CarFactory.create(CarFactory.random_type(r2), seed_value)
	v.name = "Traffic_%d" % _serial
	var yaw := atan2(-float(d.x), -float(d.y))
	v.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * v.ride_height())
	add_child(v)
	_add_driver(v, seed_value)
	v.set_ai(TrafficDriver.new(v, n, d, seed_value))
	v.linear_velocity = CityLayout.dir_vec(d) * 7.0
	v.locked = false
	_moving.append(v)
	return v


func _add_driver(v: Vehicle, seed_value: int) -> void:
	var rig := HumanoidRig.new()
	rig.name = "Driver"
	rig.setup(seed_value ^ 0x5bd1)
	rig.pose = HumanoidRig.Pose.SIT
	rig.position = v.seat_local
	rig.visible = false
	v.visual_root.add_child(rig)
	v.driver_rig = rig
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	v.driver_aggressive = r.randf() < 0.35


func _on_chunk_loaded(ch: CityChunk) -> void:
	for spot in ch.parked_spawns:
		var pos: Vector3 = spot["pos"]
		if not _free_spot(pos, 4.5):
			continue
		var seed_value: int = spot["seed"]
		var r := RandomNumberGenerator.new()
		r.seed = seed_value
		var type := CarFactory.random_type(r)
		var v := CarFactory.create(type, seed_value)
		v.name = "Parked_%d" % seed_value
		v.transform = Transform3D(Basis(Vector3.UP, float(spot["yaw"])), pos + Vector3.UP * v.ride_height())
		v.parked = true
		v.can_sleep = true
		add_child(v)
		v.sleeping = true
		ch.spawned_vehicles.append(v)


func _on_chunk_unloading(ch: CityChunk) -> void:
	var player := WorldState.player
	for n in ch.spawned_vehicles:
		var v := n as Vehicle
		if v == null or not is_instance_valid(v):
			continue
		var near := player != null and v.global_position.distance_to(player.global_position) < 60.0
		if v.is_player_vehicle() or near or not v.parked:
			if not _orphans.has(v):
				_orphans.append(v)
		else:
			v.queue_free()
	ch.spawned_vehicles.clear()


## Nächstes Fahrzeug für Tests / Spawnpunkt.
func spawn_parked_near(pos: Vector3, yaw: float, type: int) -> Vehicle:
	var v := CarFactory.create(type, 12345)
	v.name = "StarterCar"
	v.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * v.ride_height())
	v.locked = false
	add_child(v)
	v.sleeping = true
	_orphans.append(v)
	return v


func spawn_ai_at(n: Vector2i, d: Vector2i, along: float) -> Vehicle:
	var pos := CityLayout.lane_point(n, d, along)
	return _spawn_ai(n, d, pos)
