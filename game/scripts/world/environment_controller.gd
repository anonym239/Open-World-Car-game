class_name EnvironmentController
extends Node3D
## Tag/Nacht-Zyklus, Sonne/Mond (eine Richtungslichtquelle mit CSM),
## Himmel, Nebel, Tonemapping, Glow. Liest Wetterwerte vom WeatherSystem.
##
## Schatten (Anti-Bug): 4 Kaskaden (High) mit Blend-Splits, stabilisierte
## Kaskaden (Godot: Texel-Snapping), Normal-Bias statt nur Tiefen-Bias
## (kein Peter-Panning, keine Shadow-Acne), Fade am Schattenende.

const DAY_LENGTH := 24.0 * 60.0 ## Sekunden pro Spieltag (24 min)

var hour := 17.5
var weather: WeatherSystem
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var tier := 2

var _cloud_offset := Vector2.ZERO
var _sky_timer := 0.0


func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.004
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.4
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.0
	sun.light_angular_distance = 0.5
	add_child(sun)
	if not GameConfig.time_cycle:
		hour = GameConfig.fixed_hour


func configure(p_tier: int) -> void:
	tier = p_tier
	if p_tier == GameConfig.Tier.LOW:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_split_1 = 0.25
		sun.directional_shadow_max_distance = 60.0
		env.glow_enabled = false
	elif p_tier == GameConfig.Tier.MEDIUM:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 100.0
		env.glow_enabled = true
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 140.0
		env.glow_enabled = true


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)


func _process(delta: float) -> void:
	if GameConfig.time_cycle and not GameConfig.render_test:
		hour = fposmod(hour + delta * 24.0 / DAY_LENGTH, 24.0)
	elif not GameConfig.render_test:
		hour = lerpf(hour, GameConfig.fixed_hour, 1.0 - exp(-delta * 2.0))
	WorldState.hour = hour

	# Sonnenbahn: Aufgang 6 Uhr, Untergang 20 Uhr
	var day_t := (hour - 6.0) / 14.0
	var elev := sin(day_t * PI) * deg_to_rad(62.0)
	if day_t < 0.0 or day_t > 1.0:
		elev = -absf(sin(day_t * PI)) * deg_to_rad(30.0) - 0.05
	var azim := lerpf(deg_to_rad(-100.0), deg_to_rad(100.0), clampf(day_t, 0.0, 1.0)) + deg_to_rad(25.0)
	var sun_dir := Vector3(cos(elev) * sin(azim), sin(elev), cos(elev) * cos(azim)).normalized()
	var moon_dir := Vector3(-sun_dir.x, absf(sun_dir.y) * 0.7 + 0.35, -sun_dir.z).normalized()

	var day := smoothstep(-0.1, 0.18, sun_dir.y)
	var night := 1.0 - smoothstep(-0.15, 0.05, sun_dir.y)
	WorldState.night_factor = night
	RenderingServer.global_shader_parameter_set(&"night_factor", night)

	var cloud := 0.25
	var storm := 0.0
	var fog_extra := 0.0
	if weather != null:
		cloud = weather.cloud_cover
		storm = weather.storm
		fog_extra = weather.fog_extra

	# Licht: Sonne am Tag, Mondlicht nachts (gleiche Lichtquelle => ein Schattenbudget)
	var light_dir := sun_dir if day > 0.02 else moon_dir
	sun.look_at_from_position(Vector3.ZERO, -light_dir, Vector3.UP if absf(light_dir.y) < 0.99 else Vector3.FORWARD)
	var twilight := smoothstep(-0.1, 0.0, sun_dir.y) * (1.0 - smoothstep(0.0, 0.3, sun_dir.y))
	var sun_col := Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.55, 0.3), twilight)
	var moon_col := Color(0.55, 0.65, 0.95)
	sun.light_color = sun_col if day > 0.02 else moon_col
	var overcast := 1.0 - cloud * 0.65
	sun.light_energy = (lerpf(0.0, 1.35, day) * overcast) if day > 0.02 else 0.12 * (1.0 - cloud * 0.7)
	sun.shadow_opacity = clampf(1.0 - cloud * 0.6, 0.25, 1.0)
	if weather != null and weather.flash > 0.0:
		sun.light_energy += weather.flash * 2.0
		sun.light_color = Color(0.85, 0.9, 1.0)

	env.ambient_light_energy = lerpf(0.35, 1.0, day)
	env.background_energy_multiplier = lerpf(0.6, 1.0, day)
	env.tonemap_exposure = lerpf(1.25, 1.0, day)
	env.fog_density = 0.0035 + fog_extra + cloud * 0.0015
	var fog_day := Color(0.55, 0.62, 0.7).lerp(Color(0.45, 0.47, 0.5), cloud)
	var fog_night := Color(0.04, 0.05, 0.08)
	env.fog_light_color = fog_night.lerp(fog_day, day).lerp(Color(0.9, 0.5, 0.3), twilight * 0.35)

	# Himmel (Uniform-Updates gedrosselt -> Radiance nicht jedes Frame neu)
	_sky_timer -= delta
	var wind := Vector2(0.3, 0.1)
	if weather != null:
		wind = weather.wind
	_cloud_offset += wind * delta * 0.004
	if _sky_timer <= 0.0 or (weather != null and weather.flash > 0.0):
		_sky_timer = 0.2
		sky_mat.set_shader_parameter("sun_dir", sun_dir)
		sky_mat.set_shader_parameter("moon_dir", moon_dir)
		sky_mat.set_shader_parameter("cloud_cover", cloud)
		sky_mat.set_shader_parameter("storm", storm)
		sky_mat.set_shader_parameter("cloud_offset", _cloud_offset)
		sky_mat.set_shader_parameter("flash", weather.flash if weather != null else 0.0)
