class_name ChunkManager
extends Node3D
## Sektor-Streaming: Nur der aktuelle Chunk und ein Radius darum sind geladen.
## - Zeitscheiben: max. 1 Chunk-Aufbau pro Frame (kein Hitch beim Fahren)
## - Priorität nach Distanz, Vorlade-Richtung = Bewegungsrichtung
## - Hysterese beim Entladen (radius + 1) gegen Lade/Entlade-Flattern
## - Boden-Kollision ist eine globale Ebene -> nie "durch die Welt fallen",
##   auch wenn ein Chunk verspätet lädt.

signal chunk_loaded(chunk: CityChunk)
signal chunk_unloading(chunk: CityChunk)

var load_radius := 2
var chunks := {} ## Vector2i -> CityChunk
var focus := Vector3.ZERO
var focus_velocity := Vector3.ZERO
var tier := 2

var _queue: Array[Vector2i] = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.name = "GroundPlane"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	add_child(ground)


func configure(p_tier: int) -> void:
	tier = p_tier
	load_radius = 3 if p_tier == GameConfig.Tier.HIGH else 2


## Synchron laden (Ladebildschirm).
func load_immediately(center: Vector3) -> void:
	focus = center
	_refresh_queue()
	while not _queue.is_empty():
		_build_next()


func _physics_process(_delta: float) -> void:
	_refresh_queue()
	if not _queue.is_empty():
		_build_next()


func _refresh_queue() -> void:
	var look_ahead := focus + focus_velocity * 2.5
	var center := CityLayout.chunk_of(look_ahead)
	var wanted := {}
	for dx in range(-load_radius, load_radius + 1):
		for dz in range(-load_radius, load_radius + 1):
			var c := center + Vector2i(dx, dz)
			wanted[c] = true
			if not chunks.has(c) and not _queue.has(c):
				_queue.append(c)
	# Entladen mit Hysterese
	var unload_r := load_radius + 1
	for key in chunks.keys():
		var c: Vector2i = key
		if absi(c.x - center.x) > unload_r or absi(c.y - center.y) > unload_r:
			var ch: CityChunk = chunks[c]
			chunk_unloading.emit(ch)
			chunks.erase(c)
			ch.queue_free()
	# Nicht mehr benötigte Einträge aus der Warteschlange
	var filtered: Array[Vector2i] = []
	for c in _queue:
		if wanted.has(c):
			filtered.append(c)
	_queue = filtered
	# Nächste zuerst
	var fc := Vector2(look_ahead.x, look_ahead.z) / CityLayout.CELL
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(fc) < (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(fc)
	)


func _build_next() -> void:
	var c: Vector2i = _queue.pop_front()
	if chunks.has(c):
		return
	var ch := CityChunk.new()
	ch.build(c, tier)
	add_child(ch)
	chunks[c] = ch
	chunk_loaded.emit(ch)


func is_loaded(pos: Vector3) -> bool:
	return chunks.has(CityLayout.chunk_of(pos))


func all_lamp_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for ch in chunks.values():
		out.append_array((ch as CityChunk).lamp_positions)
	return out


func pending_count() -> int:
	return _queue.size()
