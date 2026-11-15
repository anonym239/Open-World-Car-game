extends Node
## Automatisierter End-to-End-Smoke-Test (CI, headless, --fixed-fps 60).
## Spielt die Kernmechaniken durch und beendet die Engine mit Exit-Code
## 0 (bestanden) oder 1 (Fehler). Läuft deterministisch in Simulationszeit.

var main
var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _log(msg: String) -> void:
	print("[SMOKE] " + msg)


func _fail(msg: String) -> void:
	_failed = true
	printerr("[SMOKE] FAILED: " + msg)
	print("SMOKE TEST FAILED: " + msg)
	get_tree().quit(1)


func _check(cond: bool, msg: String) -> bool:
	if cond:
		_log("ok   " + msg)
		return true
	_fail(msg)
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return false


func _run() -> void:
	var hub := InputHub
	hub.override_active = true
	await _frames(30)
	var player: Player = main.player
	var chunks: ChunkManager = main.chunks
	if not _check(player != null, "player spawned"):
		return
	if not _check(chunks.chunks.size() >= 9, "initial chunks loaded (%d)" % chunks.chunks.size()):
		return
	if not _check(Vehicle.all.size() > 0, "vehicles present (%d)" % Vehicle.all.size()):
		return
	if not _check(main.starter_car != null, "starter car spawned"):
		return

	# 1) Laufen
	var p0 := player.global_position
	hub.move = Vector2(0, 1)
	await _frames(60)
	hub.move = Vector2.ZERO
	await _frames(10)
	if not _check(player.global_position.distance_to(p0) > 1.5, "on-foot locomotion (%.2f m)" % player.global_position.distance_to(p0)):
		return

	# 2) Einsteigen (Starter-Auto)
	var car: Vehicle = main.starter_car
	player.global_position = car.door_point() + car.side_dir() * 1.2 + Vector3.UP * 0.1
	await _frames(5)
	if not _check(player.carjack.candidate != null, "contextual enter candidate found"):
		return
	hub.press(&"enter")
	var entered: bool = await _wait_until(func() -> bool: return player.carjack.is_driving(), 600)
	if not _check(entered, "enter sequence reached DRIVING"):
		return
	var veh: Vehicle = player.carjack.vehicle

	# 3) Fahren
	hub.throttle = 1.0
	await _frames(240)
	if not _check(veh.forward_speed > 8.0, "acceleration (%.1f m/s)" % veh.forward_speed):
		return
	hub.steer = 1.0
	await _frames(60)
	hub.handbrake = true
	await _frames(40)
	hub.handbrake = false
	hub.steer = 0.0
	hub.throttle = 0.0
	if not _check(_finite(veh.global_position), "vehicle physics stable after drift"):
		return
	hub.brake = 1.0
	var stopped: bool = await _wait_until(func() -> bool: return absf(veh.forward_speed) < 1.0, 600)
	hub.brake = 0.0
	if not _check(stopped, "braking to standstill"):
		return

	# 4) Aussteigen
	hub.press(&"enter")
	var out: bool = await _wait_until(func() -> bool: return player.is_on_foot(), 300)
	if not _check(out, "exit sequence back ON_FOOT"):
		return
	await _frames(10)

	# 5) Car-Jacking eines KI-Autos mit Fahrer
	var n := CityLayout.chunk_of(player.global_position)
	var ai_car: Vehicle = main.traffic.spawn_ai_at(n + Vector2i(0, 0), Vector2i(1, 0), 30.0)
	await _frames(30)
	if ai_car.ai != null:
		ai_car.ai.request_stop()
	var slow: bool = await _wait_until(func() -> bool: return ai_car.speed < 1.0, 600)
	if not _check(slow, "AI car stops on request"):
		return
	if not _check(ai_car.has_npc_driver(), "AI car has NPC driver"):
		return
	player.global_position = ai_car.door_point() + ai_car.side_dir() * 1.0 + Vector3.UP * 0.1
	await _frames(5)
	hub.press(&"enter")
	var jacked: bool = await _wait_until(func() -> bool: return player.carjack.is_driving(), 900)
	if not _check(jacked, "car-jacking sequence reached DRIVING"):
		return
	if not _check(not ai_car.has_npc_driver() and ai_car.drive_mode == Vehicle.Drive.PLAYER, "driver was ejected, player controls car"):
		return
	var ejected := 0
	for node in get_tree().get_nodes_in_group("npc"):
		if String(node.name).begins_with("Ejected"):
			ejected += 1
	if not _check(ejected > 0, "ejected driver became pedestrian"):
		return
	# Absprung bei Tempo
	hub.throttle = 1.0
	await _frames(200)
	hub.throttle = 0.0
	var bail_speed := ai_car.speed
	hub.press(&"enter")
	var bailed: bool = await _wait_until(func() -> bool: return player.is_on_foot(), 120)
	if not _check(bailed, "exit/bail-out while moving (%.1f m/s)" % bail_speed):
		return
	await _frames(120)

	# 6) Wetter + Tag/Nacht
	main.weather.set_kind(WeatherSystem.Kind.STORM, true)
	await _frames(60)
	if not _check(WorldState.wetness > 0.5 and WorldState.rain > 0.5, "rain/wetness globals (wet %.2f)" % WorldState.wetness):
		return
	main.env_ctrl.set_hour(23.5)
	GameConfig.time_cycle = false
	GameConfig.fixed_hour = 23.5
	await _frames(30)
	if not _check(WorldState.night_factor > 0.8, "night factor at 23:30 (%.2f)" % WorldState.night_factor):
		return

	# 7) Streaming
	var far := player.global_position + Vector3(640, 0, 0)
	player.global_position = far + Vector3.UP * 0.2
	var streamed: bool = await _wait_until(func() -> bool: return chunks.pending_count() == 0 and chunks.is_loaded(far), 900)
	if not _check(streamed, "streaming loaded target region (%d chunks)" % chunks.chunks.size()):
		return
	if not _check(not chunks.chunks.has(Vector2i(0, 0)), "old region unloaded"):
		return
	await _frames(240)

	# 8) Passanten + Physik-Integrität
	if not _check(get_tree().get_nodes_in_group("npc").size() > 0, "pedestrians spawned"):
		return
	for v in Vehicle.all:
		if not _finite(v.global_position) or v.global_position.y < -5.0 or v.global_position.y > 60.0:
			_fail("vehicle out of bounds: %s at %s" % [v.name, v.global_position])
			return
	_log("vehicles=%d moving=%d npcs=%d chunks=%d" % [Vehicle.all.size(), main.traffic.moving_count(), get_tree().get_nodes_in_group("npc").size(), chunks.chunks.size()])
	print("SMOKE TEST PASSED")
	get_tree().quit(0)


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
