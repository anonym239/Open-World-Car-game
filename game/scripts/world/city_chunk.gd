class_name CityChunk
extends Node3D
## Ein Stadtblock (Chunk) inkl. halber Straßen, Gehwegen, Gebäuden,
## Laternen, Ampeln, Bäumen, Kollision und Occludern.
## Draw-Calls pro Chunk: Boden 1, Gebäude 1, Laternen 1, Ampeln 1, Bäume 1.

const C := CityLayout.CELL
const PALETTE := [
	Color(0.30, 0.29, 0.27), Color(0.40, 0.33, 0.24), Color(0.28, 0.12, 0.08),
	Color(0.52, 0.52, 0.49), Color(0.17, 0.21, 0.26), Color(0.11, 0.11, 0.12),
	Color(0.38, 0.19, 0.11), Color(0.45, 0.42, 0.36),
]

static var _ground_mesh: PlaneMesh

var coord := Vector2i.ZERO
var block_type := 0
var lamp_positions := PackedVector3Array()
var parked_spawns: Array[Dictionary] = []
var spawned_vehicles: Array[Node] = []

var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D
var _tier := 2


func build(c: Vector2i, tier: int) -> void:
	coord = c
	_tier = tier
	name = "Chunk_%d_%d" % [c.x, c.y]
	position = CityLayout.chunk_origin(c)
	block_type = CityLayout.block_type(c)
	_rng.seed = CityLayout.hash_i(c.x, c.y, 99)
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_build_ground()
	if block_type == CityLayout.BlockType.PARK:
		_build_park()
	else:
		_build_buildings()
	_build_street_furniture()
	_plan_parking()


func _build_ground() -> void:
	if _ground_mesh == null:
		_ground_mesh = PlaneMesh.new()
		_ground_mesh.size = Vector2(C, C)
	var mi := MeshInstance3D.new()
	mi.mesh = _ground_mesh
	mi.position = Vector3(C * 0.5, 0.0, C * 0.5)
	mi.material_override = WorldMaterials.ground(block_type == CityLayout.BlockType.PARK)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- Gebäude -------------------------------------------------------------------

func _build_buildings() -> void:
	var mb := MeshBuilder.new(true)
	var lo := CityLayout.SIDEWALK_OUT + 1.5
	var hi := C - lo
	var plot := hi - lo
	var center_dist := (CityLayout.chunk_origin(coord) + Vector3(C * 0.5, 0, C * 0.5)).length()
	var height_scale := lerpf(1.0, 0.35, clampf(center_dist / 650.0, 0.0, 1.0))

	if block_type == CityLayout.BlockType.TOWER:
		var fp := _rng.randf_range(24.0, 32.0)
		var h := _rng.randf_range(70.0, 115.0) * maxf(height_scale, 0.6)
		var ctr := Vector2(C * 0.5, C * 0.5)
		_add_building(mb, ctr, Vector2(fp, fp), h, 0)
		var tree_xf: Array[Transform3D] = []
		for corner in [Vector2(lo + 4, lo + 4), Vector2(hi - 4, lo + 4), Vector2(lo + 4, hi - 4), Vector2(hi - 4, hi - 4)]:
			tree_xf.append(Transform3D(Basis().scaled(Vector3.ONE * _rng.randf_range(0.8, 1.15)), Vector3(corner.x, 0, corner.y)))
		_add_multimesh(PropMeshes.tree(), tree_xf, WorldMaterials.vc_wet(1.0), 160.0)
	elif block_type == CityLayout.BlockType.DOWNTOWN:
		var n := 2
		var lot := plot / n
		for ix in n:
			for iz in n:
				var inset := _rng.randf_range(0.5, 3.0)
				var w := lot - 1.5 - inset * 2.0
				var d := lot - 1.5 - _rng.randf_range(0.5, 3.0) * 2.0
				var ctr := Vector2(lo + lot * (ix + 0.5), lo + lot * (iz + 0.5))
				var h := _rng.randf_range(18.0, 58.0) * height_scale + 6.0
				_add_building(mb, ctr, Vector2(w, d), h, _rng.randi_range(0, 2))
	else:
		var nx := 3
		var nz := 2
		var lx := plot / nx
		var lz := plot / nz
		for ix in nx:
			for iz in nz:
				if _rng.randf() < 0.12:
					continue
				var w := lx - 2.0 - _rng.randf_range(0.0, 2.0)
				var d := lz - 4.0 - _rng.randf_range(0.0, 4.0)
				var ctr := Vector2(lo + lx * (ix + 0.5), lo + lz * (iz + 0.5))
				var h := _rng.randf_range(8.0, 22.0) * maxf(height_scale, 0.7)
				_add_building(mb, ctr, Vector2(w, d), h, _rng.randi_range(1, 2))

	var mesh := mb.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = WorldMaterials.building()
	add_child(mi)


func _add_building(mb: MeshBuilder, ctr: Vector2, size: Vector2, height: float, variant: int) -> void:
	var col: Color = PALETTE[_rng.randi_range(0, PALETTE.size() - 1)]
	if variant == 0:
		col = col.lerp(Color(0.2, 0.24, 0.28), 0.5)
	var seed_a := _rng.randf()
	col.a = seed_a
	mb.color = col
	var fractions: Array[float] = [1.0]
	if height > 45.0:
		fractions = [0.5, 0.3, 0.2]
	elif height > 26.0 and _rng.randf() < 0.6:
		fractions = [0.6, 0.4]
	var base_y := 0.0
	var fp := size
	for t in fractions.size():
		var th := height * fractions[t]
		var top := base_y + th
		mb.uv2 = Vector2(top, float(variant))
		mb.box(Vector3(ctr.x, base_y + th * 0.5, ctr.y), Vector3(fp.x, th, fp.y), Transform3D.IDENTITY, true)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(fp.x, th, fp.y)
		cs.shape = shape
		cs.position = Vector3(ctr.x, base_y + th * 0.5, ctr.y)
		_body.add_child(cs)
		if t == 0 and th > 8.0:
			var occ := OccluderInstance3D.new()
			var bo := BoxOccluder3D.new()
			bo.size = Vector3(maxf(fp.x - 0.8, 1.0), th - 0.5, maxf(fp.y - 0.8, 1.0))
			occ.occluder = bo
			occ.position = Vector3(ctr.x, (th - 0.5) * 0.5, ctr.y)
			add_child(occ)
		base_y = top
		fp *= _rng.randf_range(0.7, 0.85)
	# Dachaufbauten (Klima, Wassertank)
	mb.uv2 = Vector2(height, -1.0)
	mb.color = Color(0.22, 0.22, 0.23, seed_a)
	var units := _rng.randi_range(1, 3)
	for u in units:
		var off := Vector2(_rng.randf_range(-0.3, 0.3) * fp.x, _rng.randf_range(-0.3, 0.3) * fp.y)
		var us := Vector3(_rng.randf_range(1.5, 3.0), _rng.randf_range(0.8, 1.8), _rng.randf_range(1.5, 3.0))
		mb.box(Vector3(ctr.x + off.x, height + us.y * 0.5, ctr.y + off.y), us)


func _build_park() -> void:
	var lo := CityLayout.SIDEWALK_OUT + 3.0
	var hi := C - lo
	var xf: Array[Transform3D] = []
	var count := _rng.randi_range(12, 20)
	for i in count:
		var p := Vector3(_rng.randf_range(lo, hi), 0.0, _rng.randf_range(lo, hi))
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.3))
		xf.append(Transform3D(b, p))
	_add_multimesh(PropMeshes.tree(), xf, WorldMaterials.vc_wet(1.0), 170.0)


# --- Straßenmobiliar -----------------------------------------------------------

func _build_street_furniture() -> void:
	var lamps: Array[Transform3D] = []
	var near := CityLayout.ROAD_HALF + 0.7
	var far := C - near
	for t in [22.0, 40.0, 58.0]:
		lamps.append(_lamp_xf(Vector3(near, 0, t), Vector3.LEFT))
		lamps.append(_lamp_xf(Vector3(far, 0, t), Vector3.RIGHT))
		lamps.append(_lamp_xf(Vector3(t, 0, near), Vector3.FORWARD))
		lamps.append(_lamp_xf(Vector3(t, 0, far), Vector3.BACK))
	for xf in lamps:
		lamp_positions.append(to_global_safe(xf * PropMeshes.LAMP_LIGHT_LOCAL))
	_add_multimesh(PropMeshes.lamp(), lamps, WorldMaterials.vc_wet(1.0), 220.0)

	var m := CityLayout.SIDEWALK_MID
	var lights: Array[Transform3D] = [
		Transform3D(Basis(), Vector3(m, 0, m)),
		Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(C - m, 0, m)),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(m, 0, C - m)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(C - m, 0, C - m)),
	]
	_add_multimesh(PropMeshes.traffic_light(), lights, WorldMaterials.traffic_light(), 200.0)


func to_global_safe(local: Vector3) -> Vector3:
	return position + local


func _lamp_xf(p: Vector3, arm_dir: Vector3) -> Transform3D:
	var ang := atan2(-arm_dir.z, arm_dir.x)
	return Transform3D(Basis(Vector3.UP, ang), p)


func _add_multimesh(mesh: Mesh, xf: Array[Transform3D], mat: Material, vis_end: float) -> void:
	if xf.is_empty():
		return
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = PropMeshes.make_multimesh(mesh, xf)
	mmi.material_override = mat
	mmi.visibility_range_end = vis_end
	mmi.visibility_range_end_margin = 20.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)


# --- Parkende Autos ------------------------------------------------------------

const PARK_DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]


func _parking_local(side: int, t: float) -> Vector3:
	var pl := CityLayout.PARK_LANE
	if side == 0:
		return Vector3(pl, 0, t)
	if side == 1:
		return Vector3(C - pl, 0, t)
	if side == 2:
		return Vector3(t, 0, pl)
	return Vector3(t, 0, C - pl)


func _plan_parking() -> void:
	var count := _rng.randi_range(0, 3) if _tier > 0 else _rng.randi_range(0, 1)
	var used := {}
	for i in count:
		var side: int = _rng.randi_range(0, 3)
		var slot: int = _rng.randi_range(0, 5)
		var key := side * 10 + slot
		if used.has(key):
			continue
		used[key] = true
		var t := 20.0 + slot * 7.5
		var d: Vector2i = PARK_DIRS[side]
		parked_spawns.append({
			"pos": position + _parking_local(side, t),
			"yaw": atan2(-float(d.x), -float(d.y)),
			"seed": CityLayout.hash_i(coord.x, coord.y, 500 + key),
		})
