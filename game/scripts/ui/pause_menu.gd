class_name PauseMenu
extends CanvasLayer
## Pause- und Einstellungsmenü (läuft auch bei pausiertem Baum).
## Steuerungsmodus (Stick / Tasten / Neigung), Stick-Typ, Qualität,
## Kamera-Empfindlichkeit, Y-Invertierung, HUD-Größe, Vibration, FPS,
## Wetter- und Tageszeit-Vorgaben.

var panel: PanelContainer
var _quality_cb: Callable


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_CENTER)
	scroll.offset_left = -320
	scroll.offset_right = 320
	scroll.offset_top = -330
	scroll.offset_bottom = 330
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dim.add_child(scroll)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	scroll.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSE · EINSTELLUNGEN"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_option(box, "Lenkung", ["Virtueller Stick", "Links/Rechts-Tasten", "Neigung (Gyro)"], GameConfig.steering_mode,
		func(i: int) -> void: GameConfig.steering_mode = i)
	_option(box, "Stick", ["Dynamisch (folgt Daumen)", "Fest"], 0 if GameConfig.dynamic_stick else 1,
		func(i: int) -> void: GameConfig.dynamic_stick = i == 0)
	_option(box, "Grafikqualität", ["Automatisch", "Niedrig (30 FPS)", "Mittel", "Hoch"], GameConfig.quality_override + 1,
		func(i: int) -> void: GameConfig.quality_override = i - 1)
	_option(box, "Wetter", ["Automatisch", "Klar", "Regen", "Gewitter"], GameConfig.weather_mode,
		func(i: int) -> void: GameConfig.weather_mode = i)
	_option(box, "Tageszeit", ["Zyklus (24 min)", "Morgen", "Mittag", "Abend", "Nacht"], _time_index(),
		func(i: int) -> void: _set_time(i))
	_slider(box, "Kamera-Empfindlichkeit", 0.3, 2.5, GameConfig.camera_sensitivity,
		func(v: float) -> void: GameConfig.camera_sensitivity = v)
	_slider(box, "HUD-Größe", 0.7, 1.4, GameConfig.hud_scale,
		func(v: float) -> void: GameConfig.hud_scale = v)
	_check(box, "Kamera Y invertieren", GameConfig.invert_y, func(b: bool) -> void: GameConfig.invert_y = b)
	_check(box, "Neigung invertieren", GameConfig.tilt_invert, func(b: bool) -> void: GameConfig.tilt_invert = b)
	_check(box, "Vibration", GameConfig.haptics, func(b: bool) -> void: GameConfig.haptics = b)
	_check(box, "FPS / Debug anzeigen", GameConfig.show_fps, func(b: bool) -> void: GameConfig.show_fps = b)

	var calib := _button(box, "Neigung kalibrieren (Gerät neutral halten)")
	calib.pressed.connect(func() -> void:
		InputHub.calibrate_tilt()
		GameConfig.apply_and_save()
		Events.toast.emit("Neigung kalibriert", 1.2)
	)
	var resume := _button(box, "▶  Weiter")
	resume.pressed.connect(close)

	var help := Label.new()
	help.text = "Tastatur: WASD/Pfeile · Shift Sprint · Leertaste Springen/Handbremse · F Ein-/Aussteigen · E Schlag · C Kamera · R Radio · Esc Pause"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 14)
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)


func _time_index() -> int:
	if GameConfig.time_cycle:
		return 0
	var h := GameConfig.fixed_hour
	if h < 9.0:
		return 1
	if h < 15.0:
		return 2
	if h < 21.0:
		return 3
	return 4


func _set_time(i: int) -> void:
	GameConfig.time_cycle = i == 0
	var hours := [12.0, 7.5, 13.0, 19.4, 23.5]
	GameConfig.fixed_hour = hours[i]


func _row(box: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(230, 0)
	l.add_theme_font_size_override("font_size", 18)
	row.add_child(l)
	box.add_child(row)
	return row


func _option(box: VBoxContainer, text: String, items: Array, selected: int, cb: Callable) -> void:
	var row := _row(box, text)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(320, 52)
	ob.add_theme_font_size_override("font_size", 18)
	for it in items:
		ob.add_item(str(it))
	ob.selected = clampi(selected, 0, items.size() - 1)
	ob.item_selected.connect(func(i: int) -> void:
		cb.call(i)
		GameConfig.apply_and_save()
	)
	row.add_child(ob)


func _slider(box: VBoxContainer, text: String, lo: float, hi: float, value: float, cb: Callable) -> void:
	var row := _row(box, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(320, 52)
	s.value_changed.connect(func(v: float) -> void:
		cb.call(v)
		GameConfig.apply_and_save()
	)
	row.add_child(s)


func _check(box: VBoxContainer, text: String, value: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.custom_minimum_size = Vector2(0, 48)
	c.add_theme_font_size_override("font_size", 18)
	c.toggled.connect(func(b: bool) -> void:
		cb.call(b)
		GameConfig.apply_and_save()
	)
	box.add_child(c)


func _button(box: VBoxContainer, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 58)
	b.add_theme_font_size_override("font_size", 20)
	box.add_child(b)
	return b


func open() -> void:
	visible = true
	get_tree().paused = true
	InputHub.clear_presses()


func close() -> void:
	visible = false
	get_tree().paused = false
	InputHub.clear_presses()


func _process(_delta: float) -> void:
	if InputHub.take(&"pause"):
		if visible:
			close()
		else:
			open()
