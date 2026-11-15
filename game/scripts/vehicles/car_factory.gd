class_name CarFactory
extends RefCounted
## Erzeugt Fahrzeuge (Physik + prozedurale Karosserie). Karosserie-Meshes sind
## pro Typ gecacht und werden geteilt; nur das Lackmaterial ist pro Auto.

enum Type { SEDAN, SPORT, SUV, COMPACT, TAXI }

const SPECS := {
	Type.SEDAN: {"name": "Limousine", "hl": 2.25, "hw": 0.9, "bottom": -0.35, "nose_h": 0.08, "hood_h": 0.33,
		"cowl_z": -0.72, "roof_front": -0.18, "roof_rear": 0.82, "roof_h": 0.86, "deck_z": 1.42, "deck_h": 0.38,
		"tail_h": 0.3, "wheel_r": 0.34, "rest": 0.30, "axle_f": -1.38, "axle_r": 1.38, "track": 0.8,
		"mass": 1400.0, "engine": 8800.0, "max_speed": 52.0, "grip": 1.25, "drive_front": 0.0},
	Type.SPORT: {"name": "Sportwagen", "hl": 2.2, "hw": 0.95, "bottom": -0.3, "nose_h": 0.04, "hood_h": 0.3,
		"cowl_z": -0.55, "roof_front": -0.05, "roof_rear": 0.65, "roof_h": 0.66, "deck_z": 1.45, "deck_h": 0.36,
		"tail_h": 0.3, "wheel_r": 0.35, "rest": 0.26, "axle_f": -1.35, "axle_r": 1.35, "track": 0.84,
		"mass": 1300.0, "engine": 12500.0, "max_speed": 66.0, "grip": 1.42, "drive_front": 0.0},
	Type.SUV: {"name": "SUV", "hl": 2.35, "hw": 0.97, "bottom": -0.38, "nose_h": 0.2, "hood_h": 0.45,
		"cowl_z": -0.85, "roof_front": -0.35, "roof_rear": 1.55, "roof_h": 1.05, "deck_z": 2.05, "deck_h": 0.55,
		"tail_h": 0.45, "wheel_r": 0.4, "rest": 0.35, "axle_f": -1.45, "axle_r": 1.45, "track": 0.84,
		"mass": 1950.0, "engine": 12000.0, "max_speed": 50.0, "grip": 1.18, "drive_front": 0.45},
	Type.COMPACT: {"name": "Kleinwagen", "hl": 1.95, "hw": 0.86, "bottom": -0.33, "nose_h": 0.08, "hood_h": 0.33,
		"cowl_z": -0.85, "roof_front": -0.35, "roof_rear": 1.15, "roof_h": 0.88, "deck_z": 1.75, "deck_h": 0.42,
		"tail_h": 0.35, "wheel_r": 0.31, "rest": 0.30, "axle_f": -1.25, "axle_r": 1.25, "track": 0.76,
		"mass": 1100.0, "engine": 7000.0, "max_speed": 46.0, "grip": 1.22, "drive_front": 1.0},
}

const PAINTS := [
	Color(0.75, 0.08, 0.06), Color(0.08, 0.2, 0.55), Color(0.92, 0.92, 0.9), Color(0.05, 0.05, 0.055),
	Color(0.55, 0.57, 0.6), Color(0.1, 0.35, 0.18), Color(0.95, 0.55, 0.05), Color(0.35, 0.05, 0.3),
	Color(0.2, 0.22, 0.25), Color(0.6, 0.45, 0.25),
]

const ID_PAINT := 1.0
const ID_TRIM := 0.8
const ID_GLASS := 0.6
const ID_HEAD := 0.4
const ID_TAIL := 0.2
const ID_CHROME := 0.0

static var _body_cache := {}
static var _door_cache := {}
static var _wheel_cache := {}
static var _script: GDScript = null


static func random_type(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.36:
		return Type.SEDAN
	if r < 0.56:
		return Type.COMPACT
	if r < 0.76:
		return Type.SUV
	if r < 0.88:
		return Type.TAXI
	return Type.SPORT


static func create(type: int, seed_value: int) -> Vehicle:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var base_type: int = Type.SEDAN if type == Type.TAXI else type
	var spec: Dictionary = SPECS[base_type]
	var v := Vehicle.new()
	v.name = "Vehicle"
	v.apply_spec(spec)

	var paint: Color = PAINTS[rng.randi_range(0, PAINTS.size() - 1)]
	var metallic := 0.5
	if type == Type.TAXI:
		paint = Color(0.95, 0.72, 0.05)
		metallic = 0.2
	v.paint_material = WorldMaterials.car_paint(paint, metallic, 0.28)

	# Kollision: Unterbau + Fahrgastzelle
	var hw: float = spec["hw"]
	var hl: float = spec["hl"]
	var bottom: float = spec["bottom"]
	var hood_h: float = spec["hood_h"]
	var roof_h: float = spec["roof_h"]
	var cowl_z: float = spec["cowl_z"]
	var deck_z: float = spec["deck_z"]
	var lower := CollisionShape3D.new()
	var lb := BoxShape3D.new()
	lb.size = Vector3(hw * 2.0, hood_h - bottom, hl * 2.0)
	lower.shape = lb
	lower.position = Vector3(0, (hood_h + bottom) * 0.5, 0)
	v.add_child(lower)
	var cabin := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3((hw - 0.15) * 2.0, roof_h - hood_h, deck_z - cowl_z)
	cabin.shape = cb
	cabin.position = Vector3(0, (roof_h + hood_h) * 0.5, (deck_z + cowl_z) * 0.5)
	v.add_child(cabin)

	# Visuals
	var root := Node3D.new()
	root.name = "Visual"
	v.add_child(root)
	v.visual_root = root
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh(base_type, type == Type.TAXI)
	body.material_override = v.paint_material
	body.layers = 2
	body.visibility_range_end = 160.0
	body.visibility_range_end_margin = 15.0
	body.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(body)

	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	pivot.position = Vector3(-(hw + 0.015), 0.0, cowl_z - 0.02)
	var door := MeshInstance3D.new()
	door.mesh = _door_mesh(base_type)
	door.material_override = v.paint_material
	door.layers = 2
	door.visibility_range_end = 90.0
	pivot.add_child(door)
	root.add_child(pivot)
	v.door_pivot = pivot

	var wr: float = spec["wheel_r"]
	var wmesh := _wheel_mesh(wr)
	for i in 4:
		var wp := Node3D.new()
		var wm := MeshInstance3D.new()
		wm.mesh = wmesh
		wm.material_override = WorldMaterials.vc_wet(0.6)
		wm.layers = 2
		wm.visibility_range_end = 90.0
		wp.add_child(wm)
		root.add_child(wp)
		v.wheel_nodes.append(wp)

	var blob := WorldMaterials.make_blob_shadow(Vector3(hw * 2.6, 2.0, hl * 2.4))
	blob.position = Vector3(0, -0.2, 0)
	root.add_child(blob)

	v.locked = rng.randf() < 0.3
	return v


# --- Karosserie ---------------------------------------------------------------

static func _arch(zc: float, yc: float, ra: float, bottom: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var s := clampf((bottom - yc) / ra, -0.99, 0.0)
	var a0 := asin(s)
	var a1 := PI - a0
	var steps := 9
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / float(steps))
		points.append(Vector2(zc + ra * cos(a), yc + ra * sin(a)))
	return points


## Seitenprofil des Unterbaus (z, y) inkl. Radhäuser.
static func body_profile(type: int) -> PackedVector2Array:
	var s: Dictionary = SPECS[type]
	var hl: float = s["hl"]
	var bottom: float = s["bottom"]
	var yc := Vehicle.STATIC_COMP - float(s["rest"])
	var ra := float(s["wheel_r"]) + 0.05
	var p := PackedVector2Array()
	p.append(Vector2(-hl, bottom + 0.08))
	p.append(Vector2(-hl - 0.02, s["nose_h"]))
	p.append(Vector2(-hl + 0.22, float(s["hood_h"]) - 0.04))
	p.append(Vector2(s["cowl_z"], s["hood_h"]))
	p.append(Vector2(s["deck_z"], s["deck_h"]))
	p.append(Vector2(hl - 0.18, float(s["deck_h"]) - 0.03))
	p.append(Vector2(hl, s["tail_h"]))
	p.append(Vector2(hl, bottom + 0.08))
	p.append(Vector2(hl - 0.12, bottom))
	p.append_array(_arch(s["axle_r"], yc, ra, bottom))
	p.append_array(_arch(s["axle_f"], yc, ra, bottom))
	p.append(Vector2(-hl + 0.12, bottom))
	return p


## Prüft alle Karosserieprofile (CI): Triangulierbarkeit + Radhaus unter der Haube.
static func validate_profiles() -> Array[String]:
	var errors: Array[String] = []
	for type in SPECS.keys():
		var p := body_profile(type)
		if Geometry2D.triangulate_polygon(p).is_empty():
			errors.append("Profil %s nicht triangulierbar (Selbstüberschneidung?)" % SPECS[type]["name"])
		var s: Dictionary = SPECS[type]
		var arch_top := Vehicle.STATIC_COMP - float(s["rest"]) + float(s["wheel_r"]) + 0.05
		# Oberkante = Profilpunkte 1..6 (Nase -> Heck); Höhe über beiden Achsen interpolieren
		for axle in [float(s["axle_f"]), float(s["axle_r"])]:
			var top_y := _top_height(p, axle)
			if arch_top + 0.03 > top_y:
				errors.append("Radhaus von %s zu hoch bei z=%.2f (%.3f + 0.03 > %.3f)" % [s["name"], axle, arch_top, top_y])
	return errors


static func _top_height(p: PackedVector2Array, z: float) -> float:
	for i in range(1, 6):
		var a := p[i]
		var b := p[i + 1]
		if (z >= a.x and z <= b.x) or (z >= b.x and z <= a.x):
			if is_equal_approx(a.x, b.x):
				return maxf(a.y, b.y)
			return lerpf(a.y, b.y, clampf((z - a.x) / (b.x - a.x), 0.0, 1.0))
	return -INF


static func _body_mesh(type: int, taxi: bool) -> ArrayMesh:
	var key := type * 10 + (1 if taxi else 0)
	if _body_cache.has(key):
		return _body_cache[key]
	var s: Dictionary = SPECS[type]
	var hl: float = s["hl"]
	var hw: float = s["hw"]
	var bottom: float = s["bottom"]
	var nose_h: float = s["nose_h"]
	var hood_h: float = s["hood_h"]
	var cowl_z: float = s["cowl_z"]
	var roof_front: float = s["roof_front"]
	var roof_rear: float = s["roof_rear"]
	var roof_h: float = s["roof_h"]
	var deck_z: float = s["deck_z"]
	var deck_h: float = s["deck_h"]
	var tail_h: float = s["tail_h"]

	var mb := MeshBuilder.new()
	# Unterbau mit Radhäusern (konkaves Profil)
	var p := body_profile(type)
	var ins := PackedFloat32Array()
	for i in p.size():
		var y := p[i].y
		ins.append(0.04 if y < bottom + 0.05 else 0.0)
	mb.color = Color(1, 1, 1, ID_PAINT)
	mb.extrude_profile(p, hw, ins)

	# Glaskabine mit Dach-Einzug (Tumblehome)
	var g := PackedVector2Array([
		Vector2(cowl_z + 0.02, hood_h - 0.01), Vector2(roof_front, roof_h),
		Vector2(roof_rear, roof_h), Vector2(deck_z - 0.02, deck_h - 0.01)])
	mb.color = Color(1, 1, 1, ID_GLASS)
	mb.extrude_profile(g, hw - 0.02, PackedFloat32Array([0.05, 0.22, 0.22, 0.05]))

	# Dach + B-Säulen in Wagenfarbe
	mb.color = Color(1, 1, 1, ID_PAINT)
	var roof_w := (hw - 0.22) * 2.0 + 0.04
	mb.box(Vector3(0, roof_h + 0.018, (roof_front + roof_rear) * 0.5), Vector3(roof_w, 0.036, roof_rear - roof_front + 0.04))
	var bz := (roof_front + roof_rear) * 0.5 - 0.05
	var belt_h := lerpf(hood_h, deck_h, (bz - cowl_z) / maxf(deck_z - cowl_z, 0.01))
	for sx in [-1.0, 1.0]:
		var xb: float = sx * (hw - 0.07 + 0.012)
		var xt: float = sx * (hw - 0.22 + 0.012)
		var n := Vector3(sx * (roof_h - belt_h), 0.15, 0.0).normalized()
		mb.quad(Vector3(xb, belt_h, bz - 0.07), Vector3(xb, belt_h, bz + 0.07),
			Vector3(xt, roof_h, bz + 0.07), Vector3(xt, roof_h, bz - 0.07), n)

	# Anbauteile
	mb.color = Color(0.02, 0.02, 0.022, ID_TRIM)
	mb.box(Vector3(0, nose_h - 0.02, -hl + 0.02), Vector3(hw * 0.9, 0.13, 0.1))
	mb.box(Vector3(0, bottom + 0.12, -hl + 0.05), Vector3(hw * 1.9, 0.14, 0.16))
	mb.box(Vector3(0, bottom + 0.12, hl - 0.05), Vector3(hw * 1.9, 0.14, 0.16))
	mb.color = Color(0.85, 0.85, 0.8, ID_TRIM)
	mb.box(Vector3(0, tail_h - 0.12, hl + 0.005), Vector3(0.42, 0.11, 0.03))
	mb.color = Color(1, 1, 1, ID_HEAD)
	var head_y := (nose_h + hood_h) * 0.5 + 0.02
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(sx * (hw - 0.26), head_y, -hl + 0.12), Vector3(0.36, 0.1, 0.26))
	mb.color = Color(1, 1, 1, ID_TAIL)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(sx * (hw - 0.24), tail_h - 0.05, hl - 0.04), Vector3(0.42, 0.1, 0.12))
	mb.color = Color(1, 1, 1, ID_PAINT)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(sx * (hw + 0.07), hood_h + 0.1, cowl_z + 0.18), Vector3(0.14, 0.09, 0.07))
	if taxi:
		mb.color = Color(0.9, 0.85, 0.6, ID_HEAD)
		mb.box(Vector3(0, roof_h + 0.1, (roof_front + roof_rear) * 0.5), Vector3(0.55, 0.14, 0.2))
	var m := mb.commit()
	_body_cache[key] = m
	return m


static func _door_mesh(type: int) -> ArrayMesh:
	if _door_cache.has(type):
		return _door_cache[type]
	var s: Dictionary = SPECS[type]
	var hood_h: float = s["hood_h"]
	var deck_h: float = s["deck_h"]
	var cowl_z: float = s["cowl_z"]
	var deck_z: float = s["deck_z"]
	var bottom: float = s["bottom"]
	var length := 1.1
	var top_rear := lerpf(hood_h, deck_h, (length) / maxf(deck_z - cowl_z, 0.01))
	var mb := MeshBuilder.new()
	mb.color = Color(1, 1, 1, ID_PAINT)
	var y0 := bottom + 0.1
	var o := 0.0
	var i_ := 0.03
	# Außenhaut (Trapez), Innenseite, Kanten
	var a := Vector3(-o, y0, 0.0)
	var b := Vector3(-o, y0, length)
	var c := Vector3(-o, top_rear - 0.02, length)
	var d := Vector3(-o, hood_h - 0.02, 0.0)
	mb.quad(a, b, c, d, Vector3.LEFT)
	mb.color = Color(0.05, 0.05, 0.055, ID_TRIM)
	mb.quad(a + Vector3(i_, 0, 0), b + Vector3(i_, 0, 0), c + Vector3(i_, 0, 0), d + Vector3(i_, 0, 0), Vector3.RIGHT)
	mb.quad(d, c, c + Vector3(i_, 0, 0), d + Vector3(i_, 0, 0), Vector3.UP)
	mb.quad(a, b, b + Vector3(i_, 0, 0), a + Vector3(i_, 0, 0), Vector3.DOWN)
	mb.quad(b, c, c + Vector3(i_, 0, 0), b + Vector3(i_, 0, 0), Vector3.BACK)
	mb.quad(a, d, d + Vector3(i_, 0, 0), a + Vector3(i_, 0, 0), Vector3.FORWARD)
	mb.color = Color(0.6, 0.6, 0.62, ID_CHROME)
	mb.box(Vector3(-0.012, hood_h - 0.12, length - 0.25), Vector3(0.02, 0.03, 0.16))
	var m := mb.commit()
	_door_cache[type] = m
	return m


static func _wheel_mesh(r: float) -> ArrayMesh:
	var key := int(r * 1000.0)
	if _wheel_cache.has(key):
		return _wheel_cache[key]
	var mb := MeshBuilder.new()
	var rot := Basis(Vector3.BACK, PI * 0.5)
	mb.color = Color(0.025, 0.025, 0.028, 1.0)
	mb.cylinder(Transform3D(rot, Vector3.ZERO), r, 0.24, 16, true)
	mb.color = Color(0.7, 0.7, 0.72, 0.66)
	mb.cylinder(Transform3D(rot, Vector3.ZERO), r * 0.62, 0.27, 10, true)
	mb.color = Color(0.15, 0.15, 0.16, 0.66)
	mb.cylinder(Transform3D(rot, Vector3.ZERO), r * 0.18, 0.29, 6, true)
	var m := mb.commit()
	_wheel_cache[key] = m
	return m
