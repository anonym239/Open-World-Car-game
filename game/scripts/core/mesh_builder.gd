class_name MeshBuilder
extends RefCounted
## Prozedurale Geometrie (SurfaceTool-Wrapper).
##
## Anti-Bug-Maßnahme: Jedes Dreieck wird gegen die beabsichtigte Normale
## geprüft und bei Bedarf umsortiert (Godot: Vorderseiten = im Uhrzeigersinn).
## Damit kann ein Winding-Fehler nie zu unsichtbaren Flächen führen.

var st := SurfaceTool.new()
var color := Color.WHITE
var uv2 := Vector2.ZERO
var use_uv2 := false
var vertex_count := 0


func _init(with_uv2: bool = false) -> void:
	use_uv2 = with_uv2
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func _emit(p: Vector3, n: Vector3, uv: Vector2) -> void:
	st.set_color(color)
	st.set_normal(n)
	st.set_uv(uv)
	if use_uv2:
		st.set_uv2(uv2)
	st.add_vertex(p)
	vertex_count += 1


func tri_smooth(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		uva: Vector2 = Vector2.ZERO, uvb: Vector2 = Vector2.ZERO, uvc: Vector2 = Vector2.ZERO) -> void:
	var avg := na + nb + nc
	if (b - a).cross(c - a).dot(avg) > 0.0:
		_emit(a, na, uva)
		_emit(c, nc, uvc)
		_emit(b, nb, uvb)
	else:
		_emit(a, na, uva)
		_emit(b, nb, uvb)
		_emit(c, nc, uvc)


func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		uva: Vector2 = Vector2.ZERO, uvb: Vector2 = Vector2.ZERO, uvc: Vector2 = Vector2.ZERO) -> void:
	tri_smooth(a, b, c, n, n, n, uva, uvb, uvc)


## Viereck a-b-c-d (Umfangsreihenfolge, Orientierung egal).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		uva: Vector2 = Vector2(0, 0), uvb: Vector2 = Vector2(1, 0),
		uvc: Vector2 = Vector2(1, 1), uvd: Vector2 = Vector2(0, 1)) -> void:
	tri(a, b, c, n, uva, uvb, uvc)
	tri(a, c, d, n, uva, uvc, uvd)


## Quader. metric_uv: UV in Metern (u entlang der Fassade, v = Welthöhe),
## damit Fensterraster über gestapelte Gebäudestufen hinweg durchlaufen.
func box(center: Vector3, size: Vector3, xf: Transform3D = Transform3D.IDENTITY, metric_uv: bool = false) -> void:
	var h := size * 0.5
	var nb := xf.basis.inverse().transposed()
	var dirs: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for n in dirs:
		var u: Vector3
		var v: Vector3
		if absf(n.y) > 0.5:
			u = Vector3.RIGHT
			v = Vector3.BACK
		else:
			v = Vector3.UP
			u = n.cross(v)
		var fc := center + n * h
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var p0 := fc - u * hu - v * hv
		var p1 := fc + u * hu - v * hv
		var p2 := fc + u * hu + v * hv
		var p3 := fc - u * hu + v * hv
		var uv0 := Vector2(0, 0)
		var uv1 := Vector2(1, 0)
		var uv2_ := Vector2(1, 1)
		var uv3 := Vector2(0, 1)
		if metric_uv:
			if absf(n.y) > 0.5:
				uv0 = Vector2(p0.x, p0.z)
				uv1 = Vector2(p1.x, p1.z)
				uv2_ = Vector2(p2.x, p2.z)
				uv3 = Vector2(p3.x, p3.z)
			else:
				uv0 = Vector2(0.0, p0.y)
				uv1 = Vector2(hu * 2.0, p1.y)
				uv2_ = Vector2(hu * 2.0, p2.y)
				uv3 = Vector2(0.0, p3.y)
		var wn := (nb * n).normalized()
		quad(xf * p0, xf * p1, xf * p2, xf * p3, wn, uv0, uv1, uv2_, uv3)


## Zylinder entlang lokaler Y-Achse, zentriert. radius_top < 0 => = radius.
func cylinder(xf: Transform3D, radius: float, height: float, segments: int = 10,
		caps: bool = true, radius_top: float = -1.0) -> void:
	var rt := radius if radius_top < 0.0 else radius_top
	var hh := height * 0.5
	var nb := xf.basis.inverse().transposed()
	var slope := (radius - rt) / maxf(height, 0.0001)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var n0 := (nb * (d0 + Vector3(0, slope, 0))).normalized()
		var n1 := (nb * (d1 + Vector3(0, slope, 0))).normalized()
		var b0 := xf * (d0 * radius + Vector3(0, -hh, 0))
		var b1 := xf * (d1 * radius + Vector3(0, -hh, 0))
		var t0 := xf * (d0 * rt + Vector3(0, hh, 0))
		var t1 := xf * (d1 * rt + Vector3(0, hh, 0))
		var u0 := float(i) / float(segments)
		var u1 := float(i + 1) / float(segments)
		tri_smooth(b0, b1, t1, n0, n1, n1, Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0))
		tri_smooth(b0, t1, t0, n0, n1, n0, Vector2(u0, 1), Vector2(u1, 0), Vector2(u0, 0))
		if caps:
			var up := (nb * Vector3.UP).normalized()
			tri(xf * Vector3(0, hh, 0), t0, t1, up)
			tri(xf * Vector3(0, -hh, 0), b1, b0, -up)


## Kugel / Ellipsoid (über nicht-uniforme Skalierung in xf).
func sphere(xf: Transform3D, radius: float, rings: int = 6, segments: int = 10) -> void:
	var nb := xf.basis.inverse().transposed()
	for r in rings:
		var t0 := PI * float(r) / float(rings)
		var t1 := PI * float(r + 1) / float(rings)
		for s in segments:
			var p0 := TAU * float(s) / float(segments)
			var p1 := TAU * float(s + 1) / float(segments)
			var a := _sph(t0, p0)
			var b := _sph(t0, p1)
			var c := _sph(t1, p1)
			var d := _sph(t1, p0)
			var na := (nb * a).normalized()
			var nbv := (nb * b).normalized()
			var nc := (nb * c).normalized()
			var nd := (nb * d).normalized()
			if r > 0:
				tri_smooth(xf * (a * radius), xf * (b * radius), xf * (c * radius), na, nbv, nc)
			if r < rings - 1:
				tri_smooth(xf * (a * radius), xf * (c * radius), xf * (d * radius), na, nc, nd)


func _sph(theta: float, phi: float) -> Vector3:
	return Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))


## Extrudiert ein Seitenprofil (Punkte in (z, y)) entlang X.
## insets[i] verringert die halbe Breite am jeweiligen Punkt (z.B. Dach-Einzug).
func extrude_profile(profile: PackedVector2Array, half_width: float, insets: PackedFloat32Array, x_offset: float = 0.0) -> void:
	var count := profile.size()
	if count < 3:
		return
	var centroid := Vector3.ZERO
	for p in profile:
		centroid += Vector3(x_offset, p.y, p.x)
	centroid /= float(count)
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in count:
		var w := half_width - (insets[i] if i < insets.size() else 0.0)
		left.append(Vector3(x_offset - w, profile[i].y, profile[i].x))
		right.append(Vector3(x_offset + w, profile[i].y, profile[i].x))
	# Mantelflächen
	for i in count:
		var j := (i + 1) % count
		var n := (right[j] - left[i]).cross(left[j] - left[i])
		if n.length_squared() < 1e-10:
			n = (right[i] - left[i]).cross(right[j] - left[i])
		n = n.normalized()
		var mid := (left[i] + left[j] + right[i] + right[j]) * 0.25
		if n.dot(mid - centroid) < 0.0:
			n = -n
		quad(left[i], left[j], right[j], right[i], n)
	# Seitendeckel
	var idx := Geometry2D.triangulate_polygon(profile)
	for k in range(0, idx.size(), 3):
		var a := idx[k]
		var b := idx[k + 1]
		var c := idx[k + 2]
		tri(left[a], left[b], left[c], Vector3.LEFT)
		tri(right[a], right[b], right[c], Vector3.RIGHT)


func commit() -> ArrayMesh:
	if vertex_count == 0:
		return ArrayMesh.new()
	st.index()
	return st.commit()
