class_name AudioSynth
extends Node
## Prozedurales Audio ohne Asset-Dateien:
##  - Motor (Sägezahn + Subharmonische, Tonhöhe = Drehzahl, Last = Gas)
##  - Regen-Rauschen (gefiltert, Lautstärke = Regenintensität)
##  - Radio: 2 generative Sender (Synthwave / Lo-Fi), Sequencer in GDScript
## Ein AudioStreamGenerator bei 16 kHz (mono -> stereo dupliziert).

const RATE := 16000.0
const STATIONS := ["Aus", "Vespera FM · Synthwave", "Bay Lo-Fi"]

var station := 0
var player: Player

var _gen: AudioStreamGenerator
var _asp: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _eng_phase := 0.0
var _eng_phase2 := 0.0
var _rpm_smooth := 900.0
var _load := 0.0
var _noise_lp := 0.0
var _t := 0.0
var _arp_phase := 0.0
var _bass_phase := 0.0
var _pad_phase := PackedFloat32Array([0.0, 0.0, 0.0])
var _rng := RandomNumberGenerator.new()
var _seed := 1


func _ready() -> void:
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = RATE
	_gen.buffer_length = 0.12
	_asp = AudioStreamPlayer.new()
	_asp.stream = _gen
	_asp.volume_db = -6.0
	add_child(_asp)
	_asp.play()
	var pb := _asp.get_stream_playback()
	if pb is AudioStreamGeneratorPlayback:
		_pb = pb
	_rng.seed = 99


func next_station() -> void:
	station = (station + 1) % STATIONS.size()
	Events.radio_changed.emit(STATIONS[station])


func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


func _noise() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / float(0x7fffffff) * 2.0 - 1.0


func _process(_delta: float) -> void:
	if InputHub.take(&"radio"):
		next_station()
	if _pb == null:
		return
	var frames := _pb.get_frames_available()
	if frames <= 0:
		return
	frames = mini(frames, 2048)

	var driving := player != null and player.carjack.is_driving()
	var v: Vehicle = player.carjack.vehicle if driving else null
	var target_rpm := v.rpm if v != null else 0.0
	var target_load := v.throttle_input if v != null else 0.0
	var engine_vol := 0.22 if v != null else 0.0
	var rain_vol := WorldState.rain * (0.12 if driving else 0.2)
	var radio_on := driving and station > 0

	var buf := PackedVector2Array()
	buf.resize(frames)
	var dt := 1.0 / RATE
	var bpm := 104.0 if station == 1 else 78.0
	var step_len := 60.0 / bpm / 4.0
	var chords := [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
	for i in frames:
		_rpm_smooth += (target_rpm - _rpm_smooth) * 0.0015
		_load += (target_load - _load) * 0.001
		var s := 0.0
		# Motor
		if engine_vol > 0.0:
			var f := maxf(_rpm_smooth, 700.0) / 60.0 * 2.0
			_eng_phase = fmod(_eng_phase + f * dt, 1.0)
			_eng_phase2 = fmod(_eng_phase2 + f * 0.5 * dt, 1.0)
			var saw := _eng_phase * 2.0 - 1.0
			var sub := sin(_eng_phase2 * TAU)
			s += (saw * (0.25 + _load * 0.35) + sub * 0.5) * engine_vol
		# Regen
		if rain_vol > 0.001:
			_noise_lp += (_noise() - _noise_lp) * 0.35
			s += _noise_lp * rain_vol
		# Radio
		if radio_on:
			_t += dt
			var step := int(_t / step_len)
			var bar := (step / 16) % 4
			var chord: Array = chords[bar]
			var in_step := fmod(_t, step_len) / step_len
			var m := 0.0
			if station == 1:
				var note: int = chord[step % 3] + (12 if (step / 3) % 2 == 1 else 0) + 12
				_arp_phase = fmod(_arp_phase + _midi(note) * dt, 1.0)
				var sq := 1.0 if _arp_phase < 0.5 else -1.0
				m += sq * 0.06 * exp(-in_step * 3.0)
				_bass_phase = fmod(_bass_phase + _midi(chord[0] - 24) * dt, 1.0)
				m += (_bass_phase * 2.0 - 1.0) * 0.1 * (0.6 + 0.4 * exp(-fmod(_t, step_len * 2.0) * 8.0))
				var beat_t := fmod(_t, step_len * 4.0)
				m += sin(TAU * (50.0 + 90.0 * exp(-beat_t * 30.0)) * beat_t) * exp(-beat_t * 9.0) * 0.35
				if step % 8 == 4:
					m += _noise() * exp(-in_step * 6.0) * 0.12
			else:
				for k in 3:
					_pad_phase[k] = fmod(_pad_phase[k] + _midi(chord[k]) * dt, 1.0)
					m += sin(_pad_phase[k] * TAU) * 0.05
				var beat_t2 := fmod(_t, step_len * 4.0)
				m += sin(TAU * 55.0 * beat_t2) * exp(-beat_t2 * 7.0) * 0.25 * (1.0 if (step / 4) % 2 == 0 else 0.6)
				if step % 2 == 1:
					m += _noise() * exp(-in_step * 14.0) * 0.04
			s += m
		s = clampf(s, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)
