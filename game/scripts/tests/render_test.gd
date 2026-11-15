extends Node
## Render-Test (CI mit Software-GPU): rendert definierte Szenen und speichert
## Screenshots. Gibt Bildstatistiken aus, damit schwarze/leere Frames und
## Shader-Fehler im Log sichtbar werden.

var main


func _ready() -> void:
	_run.call_deferred()


func _out_dir() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			return a.substr(8)
	return OS.get_user_data_dir()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _out_dir().path_join(name + ".png")
	img.save_png(path)
	var lum := 0.0
	var lum2 := 0.0
	var n := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			lum += l
			lum2 += l * l
			n += 1
	var mean := lum / maxf(float(n), 1.0)
	var stdev := sqrt(maxf(lum2 / maxf(float(n), 1.0) - mean * mean, 0.0))
	print("[RENDER] %s -> %s  mean=%.3f stdev=%.3f size=%dx%d" % [name, path, mean, stdev, img.get_width(), img.get_height()])
	# Kompakte Vorschau ins Log (CI-Sichtprüfung ohne Artefakt-Download)
	var thumb := img.duplicate() as Image
	thumb.resize(480, 270, Image.INTERPOLATE_BILINEAR)
	var jpg := thumb.save_jpg_to_buffer(0.7)
	print("[THUMB] %s %s" % [name, Marshalls.raw_to_base64(jpg)])


func _run() -> void:
	InputHub.override_active = true
	var player: Player = main.player
	var cam: CameraRig = main.cam_rig
	GameConfig.time_cycle = false

	main.env_ctrl.set_hour(13.0)
	GameConfig.fixed_hour = 13.0
	main.weather.set_kind(WeatherSystem.Kind.CLEAR, true)
	cam.yaw = 0.6
	cam.pitch = -0.18
	await _frames(90)
	await _shot("01_day_clear_on_foot")

	main.env_ctrl.set_hour(19.3)
	GameConfig.fixed_hour = 19.3
	main.weather.set_kind(WeatherSystem.Kind.RAIN, true)
	await _frames(90)
	await _shot("02_dusk_rain_wet_streets")

	var car: Vehicle = main.starter_car
	if car != null:
		player.global_position = car.door_point() + car.side_dir() * 1.0
		await _frames(3)
		InputHub.press(&"enter")
		for i in 400:
			if player.carjack.is_driving():
				break
			await get_tree().process_frame
		InputHub.throttle = 0.6
		await _frames(90)
		InputHub.throttle = 0.0
	main.env_ctrl.set_hour(23.0)
	GameConfig.fixed_hour = 23.0
	main.weather.set_kind(WeatherSystem.Kind.STORM, true)
	await _frames(90)
	await _shot("03_night_storm_driving")

	cam.vehicle_cam = CameraRig.VehicleCam.CINEMATIC
	main.env_ctrl.set_hour(7.2)
	GameConfig.fixed_hour = 7.2
	main.weather.set_kind(WeatherSystem.Kind.CLOUDY, true)
	await _frames(120)
	await _shot("04_morning_cinematic")

	# Nahaufnahme: aussteigen, Auto von der Seite (3/4-Ansicht) bei Mittag
	if car != null and player.carjack.is_driving():
		InputHub.press(&"enter")
		for i in 300:
			if player.is_on_foot():
				break
			await get_tree().process_frame
		main.env_ctrl.set_hour(12.0)
		GameConfig.fixed_hour = 12.0
		main.weather.set_kind(WeatherSystem.Kind.CLEAR, true)
		cam.yaw = car.global_rotation.y - PI * 0.5 + 0.55
		cam.pitch = -0.28
		await _frames(60)
		await _shot("05_car_closeup_noon")
	print("RENDER TEST DONE")
	get_tree().quit(0)
