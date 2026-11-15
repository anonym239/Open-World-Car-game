class_name StreetLightPool
extends Node3D
## Licht-Budget: Nachts erhalten nur die N nächsten Laternen eine echte
## OmniLight (Mobile-Renderer: max. 8 Omni-Lichter pro Mesh). Alle anderen
## leuchten nur emissiv. Zuweisungen werden weich ein-/ausgeblendet
## (kein Licht-Popping).

var chunk_manager: ChunkManager
var pool_size := 6
var _lights: Array[OmniLight3D] = []
var _targets: Array[Vector3] = []
var _energy: PackedFloat32Array = PackedFloat32Array()
var _timer := 0.0


func configure(tier: int) -> void:
	pool_size = [3, 5, 7][clampi(tier, 0, 2)]
	for l in _lights:
		l.queue_free()
	_lights.clear()
	_targets.clear()
	_energy.resize(pool_size)
	for i in pool_size:
		var l := OmniLight3D.new()
		l.omni_range = 15.0
		l.omni_attenuation = 1.4
		l.light_color = Color(1.0, 0.78, 0.5)
		l.shadow_enabled = false
		l.light_energy = 0.0
		l.light_specular = 1.0
		l.visible = false
		l.position = Vector3(0, -100, 0)
		add_child(l)
		_lights.append(l)
		_targets.append(Vector3(0, -100, 0))
		_energy[i] = 0.0


func _process(delta: float) -> void:
	var night := WorldState.night_factor
	var cam := WorldState.camera
	if cam == null or chunk_manager == null:
		return
	_timer -= delta
	if _timer <= 0.0 and night > 0.02:
		_timer = 0.3
		_assign(cam.global_position)
	for i in _lights.size():
		var l := _lights[i]
		var want := 2.6 * night if _targets[i].y > -50.0 else 0.0
		if l.global_position.distance_to(_targets[i]) > 0.1:
			_energy[i] = move_toward(_energy[i], 0.0, delta * 8.0)
			if _energy[i] <= 0.01:
				l.global_position = _targets[i]
		else:
			_energy[i] = move_toward(_energy[i], want, delta * 4.0)
		l.light_energy = _energy[i]
		l.visible = _energy[i] > 0.01


func _assign(origin: Vector3) -> void:
	var all := chunk_manager.all_lamp_positions()
	var best: Array[Vector3] = []
	var dists: Array[float] = []
	for p in all:
		var d := p.distance_squared_to(origin)
		if d > 3600.0:
			continue
		var inserted := false
		for k in best.size():
			if d < dists[k]:
				best.insert(k, p)
				dists.insert(k, d)
				inserted = true
				break
		if not inserted:
			best.append(p)
			dists.append(d)
		if best.size() > pool_size:
			best.resize(pool_size)
			dists.resize(pool_size)
	# Stabile Zuordnung: bereits belegte Laternen behalten ihr Licht
	var free_slots: Array[int] = []
	var remaining := best.duplicate()
	for i in _lights.size():
		var idx := -1
		for k in remaining.size():
			if remaining[k].distance_to(_targets[i]) < 0.1:
				idx = k
				break
		if idx >= 0:
			remaining.remove_at(idx)
		else:
			free_slots.append(i)
	for i in free_slots:
		if remaining.is_empty():
			_targets[i] = Vector3(0, -100, 0)
		else:
			_targets[i] = remaining.pop_front()
