class_name QualityManager
extends Node
## Geräte-Tiering + dynamische Auflösung.
## Ziel: stabile 60 FPS (High/Medium) bzw. 30 FPS (Low). Die 3D-Renderskala
## wird anhand der gemittelten Frame-Zeit nachgeregelt (FSR 1.0 Upscaling),
## HUD bleibt immer nativ scharf.

signal tier_changed(tier: int)

const SCALE_MIN := 0.55

var tier := 2
var target_fps := 60.0
var max_scale := 1.0
var render_scale := 1.0
var avg_ms := 16.6
var _acc := 0.0
var _frames := 0
var _cooldown := 2.0


func apply(p_tier: int) -> void:
	tier = p_tier
	var vp := get_viewport()
	match tier:
		0:
			target_fps = 30.0
			max_scale = 0.7
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		1:
			target_fps = 60.0
			max_scale = 0.8
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		_:
			target_fps = 60.0
			max_scale = 1.0 if not GameConfig.is_mobile() else 0.9
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if GameConfig.is_mobile():
		Engine.max_fps = int(target_fps)
	render_scale = max_scale
	_apply_scale()
	tier_changed.emit(tier)


func _apply_scale() -> void:
	var vp := get_viewport()
	vp.scaling_3d_scale = render_scale
	if render_scale < 0.99:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.fsr_sharpness = 0.35
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR


func _process(delta: float) -> void:
	_acc += delta
	_frames += 1
	_cooldown -= delta
	if _acc < 1.0:
		return
	avg_ms = _acc / float(_frames) * 1000.0
	_acc = 0.0
	_frames = 0
	if _cooldown > 0.0 or GameConfig.render_test or GameConfig.smoke_test:
		return
	var budget := 1000.0 / target_fps
	if avg_ms > budget * 1.12 and render_scale > SCALE_MIN:
		render_scale = maxf(render_scale - 0.05, SCALE_MIN)
		_apply_scale()
		_cooldown = 1.5
	elif avg_ms < budget * 0.82 and render_scale < max_scale:
		render_scale = minf(render_scale + 0.05, max_scale)
		_apply_scale()
		_cooldown = 4.0
