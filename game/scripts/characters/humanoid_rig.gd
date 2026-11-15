class_name HumanoidRig
extends Node3D
## Prozeduraler Humanoid (10 Teile, ein geteiltes Vertex-Color-Material) mit
## prozeduralen Animationen: Gehen/Laufen, Sitzen, Schlagen, Greifen,
## Fallen/Liegen, Ducken (Panik), Kampfhaltung.
## Posen werden pro Frame weich überblendet (keine harten Pose-Sprünge).

enum Pose { STAND, SIT, FALLEN, COWER, FIGHT, REACH, SMASH }

const HIP_H := 0.95
const SIT_HIP_H := 0.48

const SKIN := [Color(0.62, 0.42, 0.3), Color(0.45, 0.28, 0.18), Color(0.25, 0.15, 0.09), Color(0.7, 0.52, 0.4), Color(0.55, 0.37, 0.24)]
const SHIRTS := [Color(0.6, 0.05, 0.05), Color(0.05, 0.15, 0.45), Color(0.8, 0.8, 0.78), Color(0.1, 0.1, 0.1), Color(0.1, 0.4, 0.2), Color(0.75, 0.5, 0.05), Color(0.35, 0.1, 0.45), Color(0.2, 0.45, 0.6)]
const PANTS := [Color(0.05, 0.07, 0.15), Color(0.12, 0.12, 0.12), Color(0.3, 0.25, 0.18), Color(0.04, 0.04, 0.04), Color(0.2, 0.25, 0.32)]
const HAIR := [Color(0.03, 0.02, 0.015), Color(0.2, 0.12, 0.05), Color(0.55, 0.4, 0.2), Color(0.3, 0.3, 0.3)]

var pose: int = Pose.STAND
var move_speed := 0.0
var lean := 0.0

var hips: Node3D
var _pivot: Node3D
var torso: MeshInstance3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D

var _phase := 0.0
var _punch_t := -1.0
var _fall_dir := 1.0
var _cur := {}


func setup(seed_value: int, shirt_override: Color = Color(-1, 0, 0)) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var skin: Color = SKIN[rng.randi_range(0, SKIN.size() - 1)]
	var shirt: Color = SHIRTS[rng.randi_range(0, SHIRTS.size() - 1)]
	if shirt_override.r >= 0.0:
		shirt = shirt_override
	var pants: Color = PANTS[rng.randi_range(0, PANTS.size() - 1)]
	var hair: Color = HAIR[rng.randi_range(0, HAIR.size() - 1)]
	var build := rng.randf_range(0.92, 1.1)
	skin.a = 1.0
	shirt.a = 1.0
	pants.a = 1.0
	hair.a = 1.0
	var shoe := Color(0.03, 0.03, 0.03, 1.0)
	var mat := WorldMaterials.vc_wet(1.0)

	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	hips = Node3D.new()
	hips.position = Vector3(0, HIP_H, 0)
	_pivot.add_child(hips)

	var mb := MeshBuilder.new()
	mb.color = shirt
	mb.cylinder(Transform3D(Basis().scaled(Vector3(build, 1, 0.75)), Vector3(0, 0.28, 0)), 0.17, 0.56, 10, true, 0.2)
	mb.sphere(Transform3D(Basis().scaled(Vector3(build * 1.15, 0.5, 0.8)), Vector3(0, 0.55, 0)), 0.2, 4, 10)
	mb.color = pants
	mb.cylinder(Transform3D(Basis().scaled(Vector3(build, 1, 0.75)), Vector3(0, 0.0, 0)), 0.165, 0.12, 10, true)
	mb.color = skin
	mb.cylinder(Transform3D(Basis(), Vector3(0, 0.64, 0)), 0.05, 0.12, 6, false)
	mb.sphere(Transform3D(Basis().scaled(Vector3(0.9, 1.05, 0.95)), Vector3(0, 0.78, 0)), 0.115, 6, 10)
	mb.color = hair
	mb.sphere(Transform3D(Basis().scaled(Vector3(0.95, 0.8, 1.0)), Vector3(0, 0.825, 0.018)), 0.115, 5, 10)
	torso = _mesh_node(mb.commit(), mat, hips)

	shoulder_l = _limb(hips, Vector3(-0.22 * build, 0.5, 0), 0.055, 0.3, shirt, mat)
	shoulder_r = _limb(hips, Vector3(0.22 * build, 0.5, 0), 0.055, 0.3, shirt, mat)
	elbow_l = _limb(shoulder_l, Vector3(0, -0.3, 0), 0.045, 0.27, skin, mat, true)
	elbow_r = _limb(shoulder_r, Vector3(0, -0.3, 0), 0.045, 0.27, skin, mat, true)
	hip_l = _limb(hips, Vector3(-0.1, 0, 0), 0.078, 0.46, pants, mat)
	hip_r = _limb(hips, Vector3(0.1, 0, 0), 0.078, 0.46, pants, mat)
	knee_l = _shin(hip_l, pants, shoe, mat)
	knee_r = _shin(hip_r, pants, shoe, mat)


func _mesh_node(mesh: Mesh, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.layers = 2
	mi.visibility_range_end = 110.0
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, offset: Vector3, radius: float, length: float, col: Color, mat: Material, hand: bool = false) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = offset
	parent.add_child(pivot)
	var mb := MeshBuilder.new()
	mb.color = col
	mb.cylinder(Transform3D(Basis(), Vector3(0, -length * 0.5, 0)), radius, length, 7, true, radius * 0.95)
	if hand:
		mb.color = col
		mb.sphere(Transform3D(Basis().scaled(Vector3(0.8, 1.1, 0.6)), Vector3(0, -length - 0.04, 0)), 0.05, 4, 6)
	_mesh_node(mb.commit(), mat, pivot)
	return pivot


func _shin(parent: Node3D, pants: Color, shoe: Color, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0, -0.46, 0)
	parent.add_child(pivot)
	var mb := MeshBuilder.new()
	mb.color = pants
	mb.cylinder(Transform3D(Basis(), Vector3(0, -0.21, 0)), 0.062, 0.42, 7, true, 0.055)
	mb.color = shoe
	mb.box(Vector3(0, -0.45, -0.05), Vector3(0.11, 0.08, 0.26))
	_mesh_node(mb.commit(), mat, pivot)
	return pivot


func punch() -> void:
	_punch_t = 0.0


func is_punching() -> bool:
	return _punch_t >= 0.0 and _punch_t < 0.32


func set_fall_direction(forward: bool) -> void:
	_fall_dir = -1.0 if forward else 1.0


func _process(delta: float) -> void:
	if hips == null:
		return
	var t := {}
	var hip_y := HIP_H
	var root_rot_x := 0.0
	var root_y := 0.0
	var spine := 0.0
	var s := clampf(move_speed, 0.0, 8.0)

	if _punch_t >= 0.0:
		_punch_t += delta
		if _punch_t > 0.42:
			_punch_t = -1.0

	match pose:
		Pose.SIT:
			hip_y = SIT_HIP_H
			t = {"sl": 1.0, "sr": 1.0, "el": 0.5, "er": 0.5, "hl": 1.45, "hr": 1.45, "kl": -1.35, "kr": -1.35}
		Pose.FALLEN:
			root_y = 0.17
			root_rot_x = _fall_dir * PI * 0.5
			t = {"sl": 0.3, "sr": -0.2, "el": 0.4, "er": 0.6, "hl": 0.15, "hr": -0.1, "kl": -0.3, "kr": -0.1}
		Pose.COWER:
			hip_y = 0.75
			spine = -0.35
			t = {"sl": 2.4, "sr": 2.4, "el": 1.2, "er": 1.2, "hl": 0.9, "hr": 0.6, "kl": -1.4, "kr": -1.1}
		Pose.FIGHT:
			spine = -0.1
			var bob := sin(Time.get_ticks_msec() * 0.008) * 0.05
			hip_y = HIP_H - 0.05 + bob
			t = {"sl": 0.9, "sr": 0.7, "el": 1.9, "er": 2.0, "hl": 0.25, "hr": -0.15, "kl": -0.3, "kr": -0.2}
		Pose.REACH:
			t = {"sl": 0.1, "sr": 1.35, "el": 0.2, "er": 0.15, "hl": 0.0, "hr": 0.0, "kl": 0.0, "kr": 0.0}
		Pose.SMASH:
			var k := sin(Time.get_ticks_msec() * 0.02)
			t = {"sl": 0.2, "sr": 1.2 + k * 0.5, "el": 0.3, "er": 0.6 - k * 0.5, "hl": 0.1, "hr": -0.1, "kl": -0.1, "kr": 0.0}
		_:
			# Lokomotion (Gehen -> Laufen)
			var run := clampf((s - 2.2) / 3.0, 0.0, 1.0)
			_phase += delta * (s * lerpf(2.6, 1.85, run) + 0.001)
			var amp := clampf(s / 2.0, 0.0, 1.0) * lerpf(0.45, 0.8, run)
			var sw := sin(_phase)
			hip_y = HIP_H - absf(cos(_phase)) * 0.04 * clampf(s / 2.0, 0.0, 1.0) - run * 0.03
			spine = -0.08 * run - lean
			var elb := lerpf(0.25, 1.4, run)
			t = {
				"sl": -sw * amp * 0.8, "sr": sw * amp * 0.8,
				"el": elb, "er": elb,
				"hl": sw * amp, "hr": -sw * amp,
				"kl": -maxf(0.0, -cos(_phase)) * amp * 1.3 - 0.05, "kr": -maxf(0.0, cos(_phase)) * amp * 1.3 - 0.05,
			}
			if s < 0.1:
				var breathe := sin(Time.get_ticks_msec() * 0.002) * 0.02
				t["sl"] = 0.05 + breathe
				t["sr"] = 0.05 - breathe
				t["el"] = 0.15
				t["er"] = 0.15

	if _punch_t >= 0.0:
		var p := _punch_t / 0.42
		var ext := sin(clampf(p, 0.0, 1.0) * PI)
		t["sr"] = lerpf(0.9, 1.6, ext)
		t["er"] = lerpf(1.9, 0.05, ext)
		spine -= 0.1 * ext

	var k_blend := 1.0 - exp(-delta * 14.0)
	for key in t.keys():
		var cur: float = _cur.get(key, 0.0)
		_cur[key] = lerpf(cur, float(t[key]), k_blend)
	var cur_hip: float = _cur.get("hip_y", HIP_H)
	_cur["hip_y"] = lerpf(cur_hip, hip_y, k_blend)
	var cur_rx: float = _cur.get("root_x", 0.0)
	_cur["root_x"] = lerpf(cur_rx, root_rot_x, 1.0 - exp(-delta * 9.0))
	var cur_ry: float = _cur.get("root_y", 0.0)
	_cur["root_y"] = lerpf(cur_ry, root_y, 1.0 - exp(-delta * 9.0))
	var cur_sp: float = _cur.get("spine", 0.0)
	_cur["spine"] = lerpf(cur_sp, spine, k_blend)

	hips.position.y = _cur["hip_y"]
	hips.rotation.x = _cur["spine"]
	_pivot.rotation.x = _cur["root_x"]
	_pivot.position.y = _cur["root_y"]
	shoulder_l.rotation.x = _cur.get("sl", 0.0)
	shoulder_r.rotation.x = _cur.get("sr", 0.0)
	elbow_l.rotation.x = _cur.get("el", 0.0)
	elbow_r.rotation.x = _cur.get("er", 0.0)
	hip_l.rotation.x = _cur.get("hl", 0.0)
	hip_r.rotation.x = _cur.get("hr", 0.0)
	knee_l.rotation.x = _cur.get("kl", 0.0)
	knee_r.rotation.x = _cur.get("kr", 0.0)
	shoulder_l.rotation.z = -0.08
	shoulder_r.rotation.z = 0.08
