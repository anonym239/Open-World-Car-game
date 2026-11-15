class_name WorldMaterials
extends RefCounted
## Zentraler Material-/Mesh-Cache. Geteilte Materialien = weniger
## Pipeline-Wechsel und keine doppelten Shader-Kompilierungen (PSO-Hitches).

static var _cache := {}


static func _shader(path: String) -> Shader:
	var key := "shader:" + path
	if not _cache.has(key):
		_cache[key] = load(path)
	return _cache[key]


static func ground(park: bool) -> ShaderMaterial:
	var key := "ground_park" if park else "ground_plaza"
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("res://shaders/ground.gdshader")
		m.set_shader_parameter("park", park)
		_cache[key] = m
	return _cache[key]


static func building() -> ShaderMaterial:
	if not _cache.has("building"):
		var m := ShaderMaterial.new()
		m.shader = _shader("res://shaders/building.gdshader")
		_cache["building"] = m
	return _cache["building"]


static func vc_wet(exposure: float = 1.0) -> ShaderMaterial:
	var key := "vc_wet_%.2f" % exposure
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("res://shaders/vc_wet.gdshader")
		m.set_shader_parameter("wet_exposure", exposure)
		_cache[key] = m
	return _cache[key]


static func traffic_light() -> ShaderMaterial:
	if not _cache.has("traffic_light"):
		var m := ShaderMaterial.new()
		m.shader = _shader("res://shaders/traffic_light.gdshader")
		_cache["traffic_light"] = m
	return _cache["traffic_light"]


static func car_paint(color: Color, metallic: float = 0.45, roughness: float = 0.3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/car.gdshader")
	m.set_shader_parameter("paint_color", color)
	m.set_shader_parameter("paint_metallic", metallic)
	m.set_shader_parameter("paint_roughness", roughness)
	return m


static func rain() -> ShaderMaterial:
	if not _cache.has("rain"):
		var m := ShaderMaterial.new()
		m.shader = _shader("res://shaders/rain.gdshader")
		_cache["rain"] = m
	return _cache["rain"]


## Weicher, runder Kontaktschatten (Decal-Textur).
static func blob_texture() -> Texture2D:
	if not _cache.has("blob"):
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.85))
		g.set_color(1, Color(0, 0, 0, 0.0))
		g.add_point(0.45, Color(0, 0, 0, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_cache["blob"] = t
	return _cache["blob"]


## Kontaktschatten als Decal (projiziert nur auf Sichtbarkeits-Layer 1 =
## Welt, nicht auf Figuren/Fahrzeuge selbst).
static func make_blob_shadow(size: Vector3) -> Decal:
	var d := Decal.new()
	d.texture_albedo = blob_texture()
	d.size = size
	d.cull_mask = 1
	d.normal_fade = 0.5
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.albedo_mix = 1.0
	return d


## Alle Shader einmal "anfassen", damit sie beim Laden (Ladebildschirm) statt
## im Spiel kompiliert werden (Shader-Prewarm gegen Ruckler).
static func prewarm() -> void:
	ground(true)
	ground(false)
	building()
	vc_wet(1.0)
	vc_wet(0.0)
	traffic_light()
	rain()
	car_paint(Color.WHITE)
	blob_texture()
