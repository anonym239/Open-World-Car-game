extends Node3D
## Bootstrap / Composition Root: erzeugt alle Systeme, verdrahtet Signale,
## lädt die Startregion hinter einem Ladebildschirm und startet ggf. die
## automatisierten Tests (--smoke-test / --render-test).

var quality: QualityManager
var env_ctrl: EnvironmentController
var weather: WeatherSystem
var chunks: ChunkManager
var traffic: TrafficManager
var peds: PedestrianManager
var lights: StreetLightPool
var player: Player
var cam_rig: CameraRig
var hud: Hud
var pause_menu: PauseMenu
var audio: AudioSynth
var starter_car: Vehicle
var ready_done := false
var _tier := -1


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--validate"):
		_validate_scripts()
		return
	WorldState.reset()
	WorldMaterials.prewarm()
	quality = QualityManager.new()
	quality.name = "Quality"
	add_child(quality)
	env_ctrl = EnvironmentController.new()
	env_ctrl.name = "Environment"
	add_child(env_ctrl)
	weather = WeatherSystem.new()
	weather.name = "Weather"
	add_child(weather)
	env_ctrl.weather = weather
	chunks = ChunkManager.new()
	chunks.name = "City"
	add_child(chunks)
	traffic = TrafficManager.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.attach(chunks)
	peds = PedestrianManager.new()
	peds.name = "Pedestrians"
	peds.chunk_manager = chunks
	add_child(peds)
	lights = StreetLightPool.new()
	lights.name = "StreetLights"
	lights.chunk_manager = chunks
	add_child(lights)
	cam_rig = CameraRig.new()
	cam_rig.name = "CameraRig"
	add_child(cam_rig)

	var drops_layer := CanvasLayer.new()
	drops_layer.layer = 1
	add_child(drops_layer)
	var drops := ColorRect.new()
	drops.set_anchors_preset(Control.PRESET_FULL_RECT)
	drops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dm := ShaderMaterial.new()
	dm.shader = load("res://shaders/screen_drops.gdshader")
	drops.material = dm
	drops.visible = false
	drops_layer.add_child(drops)
	weather.screen_drops = drops

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.weather = weather
	hud.quality = quality
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	audio = AudioSynth.new()
	audio.name = "Audio"
	add_child(audio)

	_apply_tier(GameConfig.get_tier())
	Events.settings_changed.connect(_on_settings_changed)
	Events.vehicle_entered.connect(_on_vehicle_entered)
	Events.vehicle_exited.connect(_on_vehicle_exited)
	hud.set_loading(true)
	_bootstrap.call_deferred()


func _bootstrap() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var spawn := CityLayout.ring_point(Vector2i(0, 0), CityLayout.RING_SIDE * 0.5)
	chunks.load_immediately(spawn)

	player = Player.new()
	add_child(player)
	player.global_position = spawn + Vector3.UP * 0.1
	player.rotation.y = 0.0
	cam_rig.attach(player)
	hud.player = player
	audio.player = player
	weather.follow = player
	player.carjack.driver_ejected.connect(peds.adopt_ejected)
	_spawn_starter_car()

	if GameConfig.weather_mode == GameConfig.WeatherMode.AUTO:
		weather.set_kind(WeatherSystem.Kind.CLOUDY, true)
		weather.schedule_change(45.0)
	hud.set_loading(false)
	ready_done = true
	Events.toast.emit("Willkommen in Vespera Bay", 2.5)

	if GameConfig.smoke_test:
		_start_test("res://scripts/tests/smoke_test.gd")
	elif GameConfig.render_test:
		_start_test("res://scripts/tests/render_test.gd")


## CI: jedes Skript mit aktiven Autoloads kompilieren (echte Fehler finden).
func _validate_scripts() -> void:
	var files: Array[String] = []
	_collect("res://scripts", files)
	var failed := 0
	for f in files:
		var s := load(f) as GDScript
		if s == null or not s.can_instantiate():
			failed += 1
			printerr("VALIDATE FAIL " + f)
		else:
			print("VALIDATE ok   " + f)
	for f in ["res://shaders/ground.gdshader", "res://shaders/building.gdshader", "res://shaders/car.gdshader",
			"res://shaders/vc_wet.gdshader", "res://shaders/traffic_light.gdshader", "res://shaders/sky.gdshader",
			"res://shaders/rain.gdshader", "res://shaders/screen_drops.gdshader"]:
		if load(f) == null:
			failed += 1
			printerr("VALIDATE FAIL " + f)
	print("VALIDATION %s (%d Fehler, %d Skripte)" % ["PASSED" if failed == 0 else "FAILED", failed, files.size()])
	get_tree().quit(1 if failed > 0 else 0)


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)


func _start_test(path: String) -> void:
	var script := load(path) as GDScript
	if script == null:
		push_error("Test script missing: " + path)
		get_tree().quit(2)
		return
	var t: Node = script.new()
	t.set("main", self)
	add_child(t)


func _spawn_starter_car() -> void:
	var z := CityLayout.PARK_LANE
	for x in [46.0, 31.0, 54.0, 24.0, 60.0]:
		var pos := Vector3(x, 0.0, z)
		if traffic._free_spot(pos, 5.0):
			starter_car = traffic.spawn_parked_near(pos, -PI * 0.5, CarFactory.Type.SPORT)
			return


func _apply_tier(t: int) -> void:
	_tier = t
	quality.apply(t)
	env_ctrl.configure(t)
	weather.configure(t)
	chunks.configure(t)
	traffic.configure(t)
	peds.configure(t)
	lights.configure(t)


func _on_settings_changed() -> void:
	var t := GameConfig.get_tier()
	if t != _tier:
		_apply_tier(t)


func _on_vehicle_entered(v: Node) -> void:
	weather.follow = v as Node3D


func _on_vehicle_exited(_v: Node) -> void:
	weather.follow = player


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var cj := player.carjack
	if cj.vehicle != null and is_instance_valid(cj.vehicle) and cj.is_driving():
		chunks.focus = cj.vehicle.global_position
		chunks.focus_velocity = cj.vehicle.linear_velocity
	else:
		chunks.focus = player.global_position
		chunks.focus_velocity = player.velocity
