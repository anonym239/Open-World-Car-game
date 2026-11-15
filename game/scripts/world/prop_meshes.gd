class_name PropMeshes
extends RefCounted
## Einmalig erzeugte, geteilte Meshes für Straßenmobiliar (MultiMesh-Instanzen).

const MATTE := 1.0
const METAL := 0.66
const NIGHT_GLOW := 0.0

## Lichtpunkt des Laternenkopfs im lokalen Raum (Arm zeigt nach +X).
const LAMP_LIGHT_LOCAL := Vector3(1.7, 6.25, 0.0)

static var _cache := {}


static func lamp() -> ArrayMesh:
	if _cache.has("lamp"):
		return _cache["lamp"]
	var mb := MeshBuilder.new()
	mb.color = Color(0.06, 0.065, 0.07, METAL)
	mb.cylinder(Transform3D(Basis(), Vector3(0, 0.25, 0)), 0.16, 0.5, 8)
	mb.cylinder(Transform3D(Basis(), Vector3(0, 3.4, 0)), 0.085, 6.0, 8, true, 0.065)
	mb.box(Vector3(0.9, 6.4, 0), Vector3(1.9, 0.08, 0.08))
	mb.box(Vector3(1.7, 6.33, 0), Vector3(0.7, 0.12, 0.32))
	mb.color = Color(1.0, 0.78, 0.45, NIGHT_GLOW)
	mb.box(Vector3(1.7, 6.25, 0), Vector3(0.55, 0.05, 0.24))
	var m := mb.commit()
	_cache["lamp"] = m
	return m


static func traffic_light() -> ArrayMesh:
	if _cache.has("traffic_light"):
		return _cache["traffic_light"]
	var mb := MeshBuilder.new()
	mb.color = Color(0.03, 0.032, 0.035, 1.0)
	mb.cylinder(Transform3D(Basis(), Vector3(0, 1.7, 0)), 0.08, 3.4, 8)
	mb.box(Vector3(0, 3.05, 0), Vector3(0.34, 1.0, 0.24))
	mb.box(Vector3(0, 3.05, 0.13), Vector3(0.5, 1.15, 0.02))
	var kinds := [0.0, 0.5, 1.0]
	var heights := [3.37, 3.05, 2.73]
	for i in 3:
		mb.color = Color(kinds[i], 0.0, 0.0, 0.0)
		mb.box(Vector3(0, heights[i], 0.15), Vector3(0.2, 0.2, 0.04))
	var m := mb.commit()
	_cache["traffic_light"] = m
	return m


static func tree() -> ArrayMesh:
	if _cache.has("tree"):
		return _cache["tree"]
	var mb := MeshBuilder.new()
	mb.color = Color(0.07, 0.045, 0.03, MATTE)
	mb.cylinder(Transform3D(Basis(), Vector3(0, 1.4, 0)), 0.17, 2.8, 7, false, 0.12)
	mb.color = Color(0.04, 0.09, 0.03, MATTE)
	mb.sphere(Transform3D(Basis().scaled(Vector3(1.0, 0.85, 1.0)), Vector3(0, 3.6, 0)), 1.6, 5, 8)
	mb.color = Color(0.05, 0.11, 0.035, MATTE)
	mb.sphere(Transform3D(Basis(), Vector3(0.7, 4.3, 0.3)), 1.05, 5, 8)
	mb.sphere(Transform3D(Basis(), Vector3(-0.6, 4.1, -0.4)), 1.0, 5, 8)
	var m := mb.commit()
	_cache["tree"] = m
	return m


static func make_multimesh(mesh: Mesh, transforms: Array[Transform3D]) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	return mm
