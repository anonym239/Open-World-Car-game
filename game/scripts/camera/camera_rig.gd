class_name CameraRig
extends Node3D
## Third-Person-Kamera mit SpringArm-Kollision (kein Clipping in Gebäude),
## nahtlosem Überblenden zwischen Zu-Fuß- und Fahrzeug-Modus,
## Fahrzeug-Kameramodi (Nah / Weit / Cinematic), automatischer
## Rückführung hinter das Fahrzeug, FOV-Zunahme mit Tempo, Aufprall-Shake.

enum VehicleCam { NEAR, FAR, CINEMATIC }
const MODE_NAMES := ["Nah", "Weit", "Cinematic"]

var player: Player
var arm: SpringArm3D
var cam: Camera3D
var vehicle_cam: int = VehicleCam.NEAR
var yaw := 0.0
var pitch := -0.22
var shake := 0.0

var _blend := 0.0
var _focus := Vector3.ZERO
var _idle_look := 10.0
var _cine_t := 0.0
var _excluded: RID = RID()
var _length := 3.8


func _ready() -> void:
	arm = SpringArm3D.new()
	arm.collision_mask = 1
	arm.margin = 0.2
	var sphere := SphereShape3D.new()
	sphere.radius = 0.22
	arm.shape = sphere
	arm.spring_length = 3.8
	add_child(arm)
	cam = Camera3D.new()
	cam.near = 0.08
	cam.far = 650.0
	cam.fov = 68.0
	arm.add_child(cam)
	cam.current = true
	WorldState.camera = cam
	Events.vehicle_entered.connect(_on_vehicle_entered)
	Events.vehicle_exited.connect(_on_vehicle_exited)


func attach(p: Player) -> void:
	player = p
	arm.add_excluded_object(p.get_rid())
	_focus = p.global_position + Vector3.UP * 1.55
	yaw = p.rotation.y


func cycle_vehicle_cam() -> void:
	vehicle_cam = (vehicle_cam + 1) % 3
	Events.toast.emit("Kamera: " + MODE_NAMES[vehicle_cam], 1.0)


func _on_vehicle_entered(v: Node) -> void:
	var veh := v as Vehicle
	if veh == null:
		return
	if _excluded.is_valid():
		arm.remove_excluded_object(_excluded)
	_excluded = veh.get_rid()
	arm.add_excluded_object(_excluded)
	veh.impact.connect(_on_impact)


func _on_vehicle_exited(v: Node) -> void:
	var veh := v as Vehicle
	if veh != null and veh.impact.is_connected(_on_impact):
		veh.impact.disconnect(_on_impact)


func _on_impact(strength: float) -> void:
	shake = clampf(strength / 20.0, 0.1, 0.8)
	GameConfig.vibrate(int(clampf(strength * 6.0, 20.0, 120.0)))


func _process(delta: float) -> void:
	if player == null:
		return
	var look := InputHub.consume_look()
	var sens := 0.0042 * GameConfig.camera_sensitivity
	var inv := -1.0 if GameConfig.invert_y else 1.0
	if look.length() > 0.0:
		_idle_look = 0.0
	else:
		_idle_look += delta
	yaw -= look.x * sens
	pitch = clampf(pitch - look.y * sens * inv, -1.25, 0.6)

	var cj := player.carjack
	var on_vehicle := cj.camera_on_vehicle() and cj.vehicle != null and is_instance_valid(cj.vehicle)
	_blend = move_toward(_blend, 1.0 if on_vehicle else 0.0, delta / 0.6)
	var b := smoothstep(0.0, 1.0, _blend)

	var target_focus := player.global_position + Vector3.UP * 1.55
	var target_len := 3.8
	var target_fov := 68.0
	if on_vehicle:
		var v := cj.vehicle
		var vel := v.linear_velocity
		var vfocus := v.global_position + Vector3.UP * 1.15
		target_focus = target_focus.lerp(vfocus, b)
		var spd := absf(v.forward_speed)
		target_fov = lerpf(68.0, 82.0, clampf(spd / 40.0, 0.0, 1.0))
		match vehicle_cam:
			VehicleCam.NEAR:
				target_len = 6.2
			VehicleCam.FAR:
				target_len = 9.5
			VehicleCam.CINEMATIC:
				target_len = 8.0
		target_len = lerpf(3.8, target_len, b)
		# Hinter das Fahrzeug zurückführen, wenn der Spieler nicht selbst schaut
		var heading := -v.global_transform.basis.z
		if spd > 3.0:
			var flat := Vector3(vel.x, 0, vel.z)
			if flat.length() > 2.0 and v.forward_speed > 0.0:
				heading = flat.normalized()
		var behind_yaw := atan2(-heading.x, -heading.z)
		if vehicle_cam == VehicleCam.CINEMATIC:
			_cine_t += delta
			yaw = lerp_angle(yaw, behind_yaw + 0.9 + sin(_cine_t * 0.2) * 0.9, 1.0 - exp(-delta * 1.5))
			pitch = lerpf(pitch, -0.08, 1.0 - exp(-delta * 2.0))
			target_fov = 52.0
		elif _idle_look > 1.0:
			var k := 1.0 - exp(-delta * (1.5 + spd * 0.08))
			yaw = lerp_angle(yaw, behind_yaw, k)
			pitch = lerpf(pitch, -0.2, k)

	_focus = _focus.lerp(target_focus, 1.0 - exp(-delta * 18.0))
	_length = lerpf(_length, target_len, 1.0 - exp(-delta * 5.0))
	global_position = _focus
	var sx := 0.0
	var sy := 0.0
	if shake > 0.0:
		shake = maxf(shake - delta * 2.0, 0.0)
		sx = (randf() - 0.5) * shake * 0.06
		sy = (randf() - 0.5) * shake * 0.06
	arm.rotation = Vector3(pitch + sy, yaw + sx, 0.0)
	arm.spring_length = _length
	cam.fov = lerpf(cam.fov, target_fov, 1.0 - exp(-delta * 3.0))
	if InputHub.take(&"camera"):
		cycle_vehicle_cam()
