class_name WorldState
extends RefCounted
## Leichtgewichtiger, globaler Laufzeit-Zustand (statisch, ohne Node-Lookups).
## Wird von Environment/Wetter/Verkehr geschrieben und von Gameplay gelesen.

static var night_factor := 0.0
static var wetness := 0.0
static var rain := 0.0
static var hour := 14.0
static var traffic_code := 0
static var player: Node3D = null
static var camera: Camera3D = null


static func reset() -> void:
	night_factor = 0.0
	wetness = 0.0
	rain = 0.0
	hour = 14.0
	traffic_code = 0
	player = null
	camera = null
