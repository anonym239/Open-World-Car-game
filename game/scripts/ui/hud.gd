class_name Hud
extends CanvasLayer
## HUD-Wurzel: Touch-Controls, Minimap, Tacho, Gesundheit, Hinweise, Uhrzeit/
## Wetter, FPS, Ladebildschirm. Liest Zustand, schreibt nichts ins Gameplay.

var player: Player
var weather: WeatherSystem
var quality: QualityManager
var touch: TouchControls
var minimap: Minimap
var speedo: Speedometer
var toast_label: Label
var prompt_label: Label
var info_label: Label
var fps_label: Label
var health_bar: ProgressBar
var loading: ColorRect
var loading_label: Label

var _toast_t := 0.0


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	minimap = Minimap.new()
	minimap.position = Vector2(20, 20)
	minimap.size = Vector2(190, 190)
	root.add_child(minimap)

	health_bar = ProgressBar.new()
	health_bar.position = Vector2(20, 216)
	health_bar.size = Vector2(190, 12)
	health_bar.max_value = 100.0
	health_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.85, 0.4)
	fill.set_corner_radius_all(6)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0, 0, 0, 0.5)
	bgs.set_corner_radius_all(6)
	health_bar.add_theme_stylebox_override("fill", fill)
	health_bar.add_theme_stylebox_override("background", bgs)
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(health_bar)

	speedo = Speedometer.new()
	_anchor(speedo, Control.PRESET_CENTER_BOTTOM, -85, -185, 85, -15)
	speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speedo.visible = false
	root.add_child(speedo)

	info_label = _label(root, 18, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(info_label, Control.PRESET_CENTER_TOP, -200, 14, 200, 42)

	toast_label = _label(root, 26, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(toast_label, Control.PRESET_CENTER_TOP, -320, 70, 320, 110)

	prompt_label = _label(root, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(prompt_label, Control.PRESET_CENTER_BOTTOM, -260, -60, 260, -28)

	fps_label = _label(root, 14, HORIZONTAL_ALIGNMENT_LEFT)
	fps_label.position = Vector2(20, 236)
	fps_label.size = Vector2(300, 60)

	touch = TouchControls.new()
	touch.name = "TouchControls"
	root.add_child(touch)

	loading = ColorRect.new()
	loading.color = Color(0.03, 0.035, 0.05, 1.0)
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(loading)
	loading_label = _label(loading, 30, HORIZONTAL_ALIGNMENT_CENTER)
	loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_label.text = "PROJECT V-MOBILE\nStadt wird generiert …"

	Events.toast.connect(_on_toast)
	Events.radio_changed.connect(func(n: String) -> void: _on_toast("Radio: " + n, 1.6))


func _anchor(c: Control, preset: Control.LayoutPreset, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func _label(parent: Control, font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func set_loading(on: bool, text: String = "") -> void:
	loading.visible = on
	if not text.is_empty():
		loading_label.text = text


func _on_toast(text: String, seconds: float) -> void:
	toast_label.text = text
	_toast_t = seconds


func _process(delta: float) -> void:
	_toast_t -= delta
	toast_label.visible = _toast_t > 0.0
	if player == null:
		return
	var cj := player.carjack
	var driving := cj.state == CarJackController.State.DRIVING
	touch.set_mode(TouchControls.Mode.VEHICLE if driving else TouchControls.Mode.FOOT)
	touch.enter_available = cj.state == CarJackController.State.ON_FOOT and cj.candidate != null
	touch.visible = cj.state == CarJackController.State.ON_FOOT or driving
	speedo.visible = driving
	speedo.vehicle = cj.vehicle if driving else null
	health_bar.value = player.health

	if touch.enter_available:
		var v := cj.candidate
		var what := "Fahrzeug klauen" if v.has_npc_driver() else ("Einsteigen (verschlossen)" if v.locked else "Einsteigen")
		prompt_label.text = what + "  [F]" if not GameConfig.is_mobile() else what
	else:
		prompt_label.text = ""

	var h := int(WorldState.hour)
	var m := int((WorldState.hour - float(h)) * 60.0)
	var wname := weather.kind_name() if weather != null else ""
	info_label.text = "%02d:%02d  ·  %s" % [h, m, wname]

	fps_label.visible = GameConfig.show_fps
	if fps_label.visible and quality != null:
		fps_label.text = "%d FPS  ·  %.1f ms\nRender %.0f%%  ·  Stufe %s\n%s" % [
			Engine.get_frames_per_second(), quality.avg_ms, quality.render_scale * 100.0,
			GameConfig.TIER_NAMES[quality.tier], GameConfig.adapter_name]
