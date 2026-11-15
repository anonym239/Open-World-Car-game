extends Node
## Persistente Spieler-Einstellungen + Geräte-Tiering (Low / Medium / High).
## Das Tiering steuert Renderskalierung, Schatten-Kaskaden, Sichtweite,
## Verkehrs- und Passantendichte (siehe QualityManager).

enum Tier { LOW, MEDIUM, HIGH }
enum Steering { STICK, BUTTONS, TILT }
enum WeatherMode { AUTO, CLEAR, RAIN, STORM }

const SAVE_PATH := "user://settings.cfg"
const TIER_NAMES := ["Niedrig", "Mittel", "Hoch"]

var steering_mode: int = Steering.STICK
var dynamic_stick := true
var quality_override := -1 ## -1 = automatisch
var camera_sensitivity := 1.0
var invert_y := false
var hud_scale := 1.0
var show_fps := false
var haptics := true
var tilt_invert := false
var tilt_neutral := 0.0
var weather_mode: int = WeatherMode.AUTO
var time_cycle := true
var fixed_hour := 14.0

var detected_tier: int = Tier.HIGH
var smoke_test := false
var render_test := false
var adapter_name := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	smoke_test = args.has("--smoke-test")
	render_test = args.has("--render-test")
	adapter_name = RenderingServer.get_video_adapter_name()
	detected_tier = _detect_tier(adapter_name)
	if not smoke_test and not render_test:
		load_settings()


func get_tier() -> int:
	if quality_override >= 0:
		return clampi(quality_override, Tier.LOW, Tier.HIGH)
	return detected_tier


func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS"


## Heuristik anhand des GPU-Namens. Laufzeit-Feinjustierung übernimmt die
## dynamische Auflösung im QualityManager.
func _detect_tier(adapter: String) -> int:
	if not is_mobile():
		return Tier.HIGH
	var a := adapter.to_lower()
	if a.contains("apple") or a.contains("xclipse") or a.contains("immortalis"):
		return Tier.HIGH
	if a.contains("adreno"):
		var n := _extract_number(a, "adreno[^0-9]*([0-9]+)")
		if n >= 730:
			return Tier.HIGH
		if n >= 640:
			return Tier.MEDIUM
		return Tier.LOW
	if a.contains("mali"):
		var m := _extract_number(a, "mali-g([0-9]+)")
		if m >= 710:
			return Tier.HIGH
		if m >= 68:
			return Tier.MEDIUM
		return Tier.LOW
	if OS.get_processor_count() >= 8:
		return Tier.MEDIUM
	return Tier.LOW


func _extract_number(text: String, pattern: String) -> int:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return 0
	var m := re.search(text)
	if m == null:
		return 0
	return m.get_string(1).to_int()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "steering_mode", steering_mode)
	cfg.set_value("controls", "dynamic_stick", dynamic_stick)
	cfg.set_value("controls", "camera_sensitivity", camera_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "haptics", haptics)
	cfg.set_value("controls", "tilt_invert", tilt_invert)
	cfg.set_value("controls", "tilt_neutral", tilt_neutral)
	cfg.set_value("display", "quality_override", quality_override)
	cfg.set_value("display", "hud_scale", hud_scale)
	cfg.set_value("display", "show_fps", show_fps)
	cfg.set_value("world", "weather_mode", weather_mode)
	cfg.set_value("world", "time_cycle", time_cycle)
	cfg.set_value("world", "fixed_hour", fixed_hour)
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	steering_mode = int(cfg.get_value("controls", "steering_mode", steering_mode))
	dynamic_stick = bool(cfg.get_value("controls", "dynamic_stick", dynamic_stick))
	camera_sensitivity = float(cfg.get_value("controls", "camera_sensitivity", camera_sensitivity))
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	haptics = bool(cfg.get_value("controls", "haptics", haptics))
	tilt_invert = bool(cfg.get_value("controls", "tilt_invert", tilt_invert))
	tilt_neutral = float(cfg.get_value("controls", "tilt_neutral", tilt_neutral))
	quality_override = int(cfg.get_value("display", "quality_override", quality_override))
	hud_scale = float(cfg.get_value("display", "hud_scale", hud_scale))
	show_fps = bool(cfg.get_value("display", "show_fps", show_fps))
	weather_mode = int(cfg.get_value("world", "weather_mode", weather_mode))
	time_cycle = bool(cfg.get_value("world", "time_cycle", time_cycle))
	fixed_hour = float(cfg.get_value("world", "fixed_hour", fixed_hour))


func apply_and_save() -> void:
	save_settings()
	Events.settings_changed.emit()


func vibrate(ms: int) -> void:
	if haptics and is_mobile():
		Input.vibrate_handheld(ms)
