class_name TrafficDriver
extends RefCounted
## KI-Fahrer: folgt dem impliziten Spurgraphen des Rasters (Rechtsverkehr),
## hält an roten Ampeln, bremst vor Hindernissen (Raycast), biegt zufällig
## ab (Bezier-Kurven). Steuert das Fahrzeug über dieselben normierten Eingaben
## wie der Spieler (Pure-Pursuit-Lenkung + P-Regler für Geschwindigkeit).

const C := CityLayout.CELL
const ENTRY := 12.0
const DETECT_MASK := 2 | 4 | 8

var vehicle: Vehicle
var path := PackedVector3Array()
var stop_axis := PackedInt32Array() ## >0: Haltelinie (Achse + 1)
var curve_flag := PackedInt32Array()
var idx := 0
var node := Vector2i.ZERO ## nächster Knoten am Ende des Pfads
var dir := Vector2i(0, 1) ## Fahrtrichtung beim Erreichen von 'node'
var cruise := 11.0
var stop_requested := false
var stuck_time := 0.0
var _panic := 0.0
var _rng := RandomNumberGenerator.new()
var _obstacle_limit := 99.0
var _obstacle_timer := 0.0
var _ray := PhysicsRayQueryParameters3D.new()


func _init(v: Vehicle, from_node: Vector2i, d: Vector2i, seed_value: int) -> void:
	vehicle = v
	_rng.seed = seed_value
	cruise = _rng.randf_range(9.5, 12.5)
	dir = d
	node = from_node + d
	_ray.collision_mask = DETECT_MASK
	_ray.collide_with_areas = false
	path.append(CityLayout.lane_point(from_node, d, ENTRY))
	stop_axis.append(0)
	curve_flag.append(0)
	_append_entry()


func _lane(n: Vector2i, d: Vector2i, along: float) -> Vector3:
	return CityLayout.lane_point(n, d, along)


func _push(p: Vector3, stop: int, curve: int) -> void:
	path.append(p)
	stop_axis.append(stop)
	curve_flag.append(curve)


## Haltelinie vor 'node' anhängen.
func _append_entry() -> void:
	_push(_lane(node - dir, dir, C - ENTRY), CityLayout.axis_of(dir) + 1, 0)


## Abbiegen an 'node' und bis zur nächsten Haltelinie verlängern.
func _extend() -> void:
	var options: Array[Vector2i] = [dir, dir, dir, Vector2i(-dir.y, dir.x), Vector2i(dir.y, -dir.x)]
	var d2: Vector2i = options[_rng.randi_range(0, options.size() - 1)]
	var np := CityLayout.node_pos(node)
	var entry := _lane(node - dir, dir, C - ENTRY)
	var exit_p := _lane(node, d2, ENTRY)
	if d2 != dir:
		var corner := np + CityLayout.right_of(dir) * CityLayout.LANE_OFFSET + CityLayout.right_of(d2) * CityLayout.LANE_OFFSET
		for k in range(1, 5):
			var t := float(k) / 5.0
			var q := entry.lerp(corner, t).lerp(corner.lerp(exit_p, t), t)
			_push(q, 0, 1)
	_push(exit_p, 0, 1 if d2 != dir else 0)
	dir = d2
	node = node + d2
	_append_entry()


func request_stop() -> void:
	stop_requested = true


func panic() -> void:
	_panic = 8.0
	stop_requested = false


func update(delta: float) -> void:
	if vehicle == null:
		return
	_panic = maxf(_panic - delta, 0.0)
	var pos := vehicle.global_position
	pos.y = 0.0
	# Pfad nachladen
	while path.size() - idx < 8:
		_extend()
	# Erreichte Punkte überspringen
	while idx < path.size() - 1:
		var seg := path[idx + 1] - path[idx]
		var to_next := path[idx] - pos
		# Haltelinien nie per Nähe überspringen, nur wenn wirklich überfahren
		var close := to_next.length() < 3.0 and stop_axis[idx] == 0
		if close or (seg.length() > 0.01 and to_next.dot(seg) < 0.0):
			idx += 1
		else:
			break
	# Speicher begrenzen
	if idx > 32:
		path = path.slice(idx)
		stop_axis = stop_axis.slice(idx)
		curve_flag = curve_flag.slice(idx)
		idx = 0

	var spd := vehicle.forward_speed
	var lookahead := 5.0 + absf(spd) * 0.45
	var target := _point_ahead(pos, lookahead)
	_steer_to(target)

	# Zielgeschwindigkeit
	var v_target := cruise if _panic <= 0.0 else 17.0
	var dist := pos.distance_to(path[idx])
	for k in range(idx, mini(idx + 10, path.size())):
		if k > idx:
			dist += path[k].distance_to(path[k - 1])
		if dist > 45.0:
			break
		if curve_flag[k] == 1 and dist < 20.0:
			v_target = minf(v_target, 6.5)
		if stop_axis[k] > 0 and _panic <= 0.0:
			var state := CityLayout.light_state(stop_axis[k] - 1, WorldState.traffic_code)
			var must_stop := state == 2 or (state == 1 and dist > 9.0)
			if must_stop:
				v_target = minf(v_target, sqrt(2.0 * 3.2 * maxf(dist - 1.5, 0.0)))
			break

	_obstacle_timer -= delta
	if _obstacle_timer <= 0.0:
		_obstacle_timer = 0.1
		_obstacle_limit = _scan_obstacles()
	v_target = minf(v_target, _obstacle_limit)
	if stop_requested:
		v_target = 0.0

	# Längsregelung
	var err := v_target - spd
	if v_target < 0.3:
		vehicle.throttle_input = 0.0
		if spd > 1.0:
			vehicle.brake_input = 1.0
			vehicle.handbrake_input = false
		else:
			vehicle.brake_input = 0.0
			vehicle.handbrake_input = true
	elif err > 0.0:
		vehicle.throttle_input = clampf(err * 0.4, 0.0, 1.0)
		vehicle.brake_input = 0.0
		vehicle.handbrake_input = false
	else:
		vehicle.throttle_input = 0.0
		vehicle.brake_input = clampf(-err * 0.35, 0.0, 1.0) if spd > 1.0 else 0.0
		vehicle.handbrake_input = false

	if v_target > 3.0 and absf(spd) < 0.5:
		stuck_time += delta
	else:
		stuck_time = 0.0


func _point_ahead(pos: Vector3, lookahead: float) -> Vector3:
	var remaining := lookahead
	var prev := pos
	for k in range(idx, path.size()):
		var d := prev.distance_to(path[k])
		if d >= remaining:
			return prev.lerp(path[k], remaining / maxf(d, 0.001))
		remaining -= d
		prev = path[k]
	return path[path.size() - 1]


func _steer_to(target: Vector3) -> void:
	var local := vehicle.global_transform.affine_inverse() * target
	var fwd := -local.z
	var lat := local.x
	var alpha := atan2(lat, maxf(fwd, 0.1))
	var ld := maxf(Vector2(lat, fwd).length(), 1.0)
	var angle := atan(2.0 * vehicle.wheelbase * sin(alpha) / ld)
	vehicle.steer_input = clampf(angle / vehicle.max_steer, -1.0, 1.0)


func _scan_obstacles() -> float:
	var space := vehicle.get_world_3d().direct_space_state
	var xf := vehicle.global_transform
	var fwd := -xf.basis.z
	var spd := maxf(vehicle.forward_speed, 0.0)
	var from := xf.origin + fwd * (vehicle.half_length + 0.2) + Vector3.UP * 0.25
	var length := 4.0 + spd * 1.4
	var best := 99.0
	for side in [-0.6, 0.6]:
		var o: Vector3 = xf.basis.x * float(side)
		_ray.from = from + o
		_ray.to = from + o + fwd.rotated(Vector3.UP, -vehicle.steer_angle * 0.6) * length
		_ray.exclude = [vehicle.get_rid()]
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			var d := (from + o).distance_to(hit["position"])
			best = minf(best, maxf(d - 2.5, 0.0) * 1.1)
	return best
