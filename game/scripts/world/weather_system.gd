class_name WeatherSystem
extends Node3D
## Dynamisches Wetter: CLEAR -> CLOUDY -> RAIN -> STORM mit stufenlosen
## Übergängen. Physikalisch motivierte Zustandsgrößen:
##   rain_intensity  (folgt dem Zielwert in ~20 s)
##   wetness         (steigt mit Regen schnell, trocknet langsam: ~2-3 min)
##   puddle_level    (füllt sich langsamer als wetness, verdunstet am langsamsten)
## Werte gehen als Shader-Globals an ALLE Materialien (ein Update pro Frame).

enum Kind { CLEAR, CLOUDY, RAIN, STORM }

const TARGETS := {
	Kind.CLEAR: {"rain": 0.0, "cloud": 0.15, "storm": 0.0, "fog": 0.0},
	Kind.CLOUDY: {"rain": 0.0, "cloud": 0.65, "storm": 0.0, "fog": 0.002},
	Kind.RAIN: {"rain": 0.65, "cloud": 0.85, "storm": 0.2, "fog": 0.006},
	Kind.STORM: {"rain": 1.0, "cloud": 1.0, "storm": 1.0, "fog": 0.011},
}

var kind: int = Kind.CLEAR
var rain_intensity := 0.0
var wetness := 0.0
var puddle_level := 0.0
var cloud_cover := 0.15
var storm := 0.0
var fog_extra := 0.0
var wind := Vector2(0.3, 0.1)
var flash := 0.0

var rain_particles: GPUParticles3D
var screen_drops: ColorRect
var follow: Node3D

var _timer := 90.0
var _rng := RandomNumberGenerator.new()
var _lightning := 6.0
var _flash_t := 0.0
var _max_particles := 6000


func _ready() -> void:
	_rng.seed = 2024
	_build_rain()


func configure(tier: int) -> void:
	_max_particles = [2000, 4000, 7000][clampi(tier, 0, 2)]
	rain_particles.amount = _max_particles
	if screen_drops != null:
		screen_drops.visible = false


func _build_rain() -> void:
	rain_particles = GPUParticles3D.new()
	rain_particles.name = "Rain"
	rain_particles.amount = _max_particles
	rain_particles.lifetime = 0.9
	rain_particles.preprocess = 0.5
	rain_particles.local_coords = false
	rain_particles.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	rain_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0, -12, 0)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	rain_particles.process_material = pm
	rain_particles.draw_pass_1 = _streak_mesh()
	rain_particles.material_override = WorldMaterials.rain()
	rain_particles.emitting = false
	add_child(rain_particles)


func _streak_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	mb.color = Color(1, 1, 1, 1)
	var w := 0.012
	var h := 0.55
	mb.quad(Vector3(-w, -h, 0), Vector3(w, -h, 0), Vector3(w, h, 0), Vector3(-w, h, 0), Vector3.BACK,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	mb.quad(Vector3(0, -h, -w), Vector3(0, -h, w), Vector3(0, h, w), Vector3(0, h, -w), Vector3.RIGHT,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	return mb.commit()


func schedule_change(seconds: float) -> void:
	_timer = seconds


func set_kind(k: int, instant: bool = false) -> void:
	kind = k
	_timer = _rng.randf_range(100.0, 200.0)
	if instant:
		var t: Dictionary = TARGETS[k]
		rain_intensity = t["rain"]
		cloud_cover = t["cloud"]
		storm = t["storm"]
		fog_extra = t["fog"]
		wetness = clampf(rain_intensity * 1.2, 0.0, 1.0)
		puddle_level = clampf(rain_intensity, 0.0, 1.0)


func _process(delta: float) -> void:
	# Zielzustand aus Einstellungen oder automatischem Zyklus
	var forced := GameConfig.weather_mode
	if forced == GameConfig.WeatherMode.CLEAR:
		kind = Kind.CLEAR
	elif forced == GameConfig.WeatherMode.RAIN:
		kind = Kind.RAIN
	elif forced == GameConfig.WeatherMode.STORM:
		kind = Kind.STORM
	elif not GameConfig.render_test and not GameConfig.smoke_test:
		_timer -= delta
		if _timer <= 0.0:
			_advance()

	var t: Dictionary = TARGETS[kind]
	var k := 1.0 - exp(-delta / 18.0)
	rain_intensity = lerpf(rain_intensity, t["rain"], k)
	cloud_cover = lerpf(cloud_cover, t["cloud"], k)
	storm = lerpf(storm, t["storm"], k)
	fog_extra = lerpf(fog_extra, t["fog"], k)
	if rain_intensity > 0.05:
		wetness = minf(wetness + delta * (0.02 + rain_intensity * 0.06), 1.0)
		puddle_level = minf(puddle_level + delta * rain_intensity * 0.012, 1.0)
	else:
		wetness = maxf(wetness - delta * 0.008, 0.0)
		puddle_level = maxf(puddle_level - delta * 0.004, 0.0)

	var ang := Time.get_ticks_msec() * 0.00005
	wind = Vector2(cos(ang), sin(ang)) * lerpf(0.6, 3.5, storm)

	# Blitze im Sturm
	flash = 0.0
	if storm > 0.6 and not GameConfig.render_test:
		_lightning -= delta
		if _lightning <= 0.0:
			_lightning = _rng.randf_range(5.0, 14.0)
			_flash_t = 0.35
		if _flash_t > 0.0:
			_flash_t -= delta
			flash = clampf(_flash_t / 0.35, 0.0, 1.0) * (0.6 + 0.4 * sin(_flash_t * 60.0))

	WorldState.wetness = wetness
	WorldState.rain = rain_intensity
	RenderingServer.global_shader_parameter_set(&"wetness", wetness)
	RenderingServer.global_shader_parameter_set(&"puddle_level", puddle_level)
	RenderingServer.global_shader_parameter_set(&"rain_intensity", rain_intensity)
	RenderingServer.global_shader_parameter_set(&"wind_dir", wind)

	# Partikel folgen der Kamera (Regen-Volumen um den Spieler)
	var cam := WorldState.camera
	if cam != null:
		var p := cam.global_position
		var vel := Vector3.ZERO
		if follow != null and follow is Vehicle:
			vel = (follow as Vehicle).linear_velocity
		rain_particles.global_position = p + Vector3(vel.x, 0, vel.z) * 0.5 + Vector3(0, 14, 0)
	rain_particles.emitting = rain_intensity > 0.03
	rain_particles.amount_ratio = clampf(rain_intensity, 0.05, 1.0)
	var pm := rain_particles.process_material as ParticleProcessMaterial
	pm.direction = Vector3(wind.x * 0.12, -1.0, wind.y * 0.12).normalized()

	if screen_drops != null:
		var tier_ok := GameConfig.get_tier() != GameConfig.Tier.LOW
		var looking_up := 0.6
		if cam != null:
			looking_up = clampf(0.55 - cam.global_transform.basis.z.y * 0.8, 0.2, 1.0)
		var intensity := rain_intensity * looking_up
		screen_drops.visible = tier_ok and intensity > 0.03
		(screen_drops.material as ShaderMaterial).set_shader_parameter("intensity", intensity)


func _advance() -> void:
	var next := Kind.CLEAR
	match kind:
		Kind.CLEAR:
			next = Kind.CLOUDY
		Kind.CLOUDY:
			next = Kind.RAIN if _rng.randf() < 0.65 else Kind.CLEAR
		Kind.RAIN:
			next = Kind.STORM if _rng.randf() < 0.35 else Kind.CLOUDY
		Kind.STORM:
			next = Kind.RAIN
	set_kind(next)


func kind_name() -> String:
	return ["Klar", "Bewölkt", "Regen", "Gewitter"][kind]
