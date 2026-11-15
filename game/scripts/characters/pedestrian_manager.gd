class_name PedestrianManager
extends Node3D
## Spawnt Passanten außerhalb des Sichtfelds um den Spieler und entfernt
## weit entfernte. Dichte skaliert mit dem Geräte-Tier.

var chunk_manager: ChunkManager
var target_count := 16
var spawn_min := 28.0
var spawn_max := 110.0
var despawn_dist := 150.0

var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _serial := 0


func configure(tier: int) -> void:
	target_count = [8, 14, 22][clampi(tier, 0, 2)]
	_rng.seed = 4711


func count() -> int:
	return get_tree().get_nodes_in_group("npc").size()


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.35
	var player := WorldState.player
	if player == null:
		return
	var origin := player.global_position
	var cam := WorldState.camera
	for n in get_tree().get_nodes_in_group("npc"):
		var p := n as Pedestrian
		if p == null or p.is_queued_for_deletion():
			continue
		var d := p.global_position.distance_to(origin)
		if d > despawn_dist and (cam == null or not cam.is_position_in_frustum(p.global_position)):
			p.queue_free()
		elif d > despawn_dist * 1.6:
			p.queue_free()
	if count() < target_count:
		_try_spawn(origin, cam)


func _try_spawn(origin: Vector3, cam: Camera3D) -> void:
	for attempt in 6:
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(spawn_min, spawn_max)
		var guess := origin + Vector3(cos(ang), 0.0, sin(ang)) * r
		var c := CityLayout.chunk_of(guess)
		if chunk_manager != null and not chunk_manager.chunks.has(c):
			continue
		var s0 := CityLayout.ring_param(c, guess)
		var pos := CityLayout.ring_point(c, s0)
		var d := pos.distance_to(origin)
		if d < spawn_min:
			continue
		if cam != null and d < 70.0 and cam.is_position_in_frustum(pos + Vector3.UP):
			continue
		_serial += 1
		var ped := Pedestrian.new()
		ped.name = "Ped_%d" % _serial
		ped.setup(_rng.randi())
		ped.place_on_ring(c, s0)
		add_child(ped)
		return


## Herausgezerrter Fahrer wird zum Passanten (Flucht oder Angriff).
func adopt_ejected(rig: HumanoidRig, pos: Vector3, aggressive: bool) -> void:
	_serial += 1
	var ped := Pedestrian.new()
	ped.name = "Ejected_%d" % _serial
	ped.position = pos + Vector3.UP * 0.05
	add_child(ped)
	ped.setup(_rng.randi(), rig)
	ped.start_ejected(aggressive)
