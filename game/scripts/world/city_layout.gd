class_name CityLayout
extends RefCounted
## Deterministisches Stadtlayout ("Vespera Bay"). Alles wird aus dem Raster
## und einem Seed berechnet -> Chunks können jederzeit identisch neu erzeugt
## werden (Streaming ohne gespeicherte Weltdaten).
##
## Raster: Straßenmittellinien bei x = i*CELL und z = j*CELL.
## Chunk (cx, cz) deckt [cx*CELL, (cx+1)*CELL] ab; der Block liegt in der Mitte.

const CELL := 80.0
const ROAD_HALF := 7.0
const LANE_OFFSET := 2.0
const PARK_LANE := 5.5
const SIDEWALK_OUT := 11.0
const SIDEWALK_MID := 9.0
const STOP_DIST := 12.5
const CITY_SEED := 7331

enum BlockType { PARK, TOWER, DOWNTOWN, RESIDENTIAL }

## Ampelphasen (Sekunden): NS grün, NS gelb, alle rot, OW grün, OW gelb, alle rot
const PHASES := [10.0, 2.5, 1.0, 10.0, 2.5, 1.0]
const PHASE_CYCLE := 27.0


static func hash_i(x: int, z: int, salt: int = 0) -> int:
	var h: int = (x * 73856093) ^ (z * 19349663) ^ (salt * 83492791) ^ CITY_SEED
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	h = (h ^ (h >> 16)) & 0x7fffffff
	return h


static func rand01(x: int, z: int, salt: int = 0) -> float:
	return float(hash_i(x, z, salt) % 100000) / 100000.0


static func chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))


static func chunk_origin(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL, 0.0, c.y * CELL)


static func block_type(c: Vector2i) -> int:
	var center := Vector2(c.x + 0.5, c.y + 0.5) * CELL
	var dist := center.length()
	var r := rand01(c.x, c.y, 1)
	if c == Vector2i(0, 0):
		return BlockType.DOWNTOWN
	if r < 0.12:
		return BlockType.PARK
	if dist < 320.0 and r < 0.32:
		return BlockType.TOWER
	if dist < 480.0:
		return BlockType.DOWNTOWN
	return BlockType.RESIDENTIAL


# --- Fahrspuren ----------------------------------------------------------------

static func dir_vec(d: Vector2i) -> Vector3:
	return Vector3(d.x, 0.0, d.y)


## Rechte Seite einer Fahrtrichtung (Rechtsverkehr).
static func right_of(d: Vector2i) -> Vector3:
	return dir_vec(d).cross(Vector3.UP)


static func node_pos(n: Vector2i) -> Vector3:
	return Vector3(n.x * CELL, 0.0, n.y * CELL)


## Punkt auf der Fahrspur, die von Knoten n in Richtung d führt.
static func lane_point(n: Vector2i, d: Vector2i, along: float) -> Vector3:
	return node_pos(n) + dir_vec(d) * along + right_of(d) * LANE_OFFSET


## Achse einer Fahrtrichtung: 0 = Nord-Süd (entlang Z), 1 = Ost-West (entlang X).
static func axis_of(d: Vector2i) -> int:
	return 1 if d.x != 0 else 0


static func phase_code(t: float) -> int:
	var x := fposmod(t, PHASE_CYCLE)
	for i in PHASES.size():
		x -= PHASES[i]
		if x < 0.0:
			return i
	return 0


## 0 = grün, 1 = gelb, 2 = rot
static func light_state(axis: int, code: int) -> int:
	if axis == 0:
		return 0 if code == 0 else (1 if code == 1 else 2)
	return 0 if code == 3 else (1 if code == 4 else 2)


# --- Gehwege (Passanten-Rundwege um den Block) --------------------------------

const RING_SIDE := CELL - 2.0 * SIDEWALK_MID
const RING_LENGTH := RING_SIDE * 4.0


static func ring_point(c: Vector2i, s: float) -> Vector3:
	var o := chunk_origin(c)
	var t := fposmod(s, RING_LENGTH)
	var lo := SIDEWALK_MID
	var hi := CELL - SIDEWALK_MID
	if t < RING_SIDE:
		return o + Vector3(lo + t, 0.0, lo)
	t -= RING_SIDE
	if t < RING_SIDE:
		return o + Vector3(hi, 0.0, lo + t)
	t -= RING_SIDE
	if t < RING_SIDE:
		return o + Vector3(hi - t, 0.0, hi)
	t -= RING_SIDE
	return o + Vector3(lo, 0.0, hi - t)


## Projektion einer Position auf den Rundweg -> Bogenlänge s.
static func ring_param(c: Vector2i, pos: Vector3) -> float:
	var o := chunk_origin(c)
	var lx := clampf(pos.x - o.x, SIDEWALK_MID, CELL - SIDEWALK_MID) - SIDEWALK_MID
	var lz := clampf(pos.z - o.z, SIDEWALK_MID, CELL - SIDEWALK_MID) - SIDEWALK_MID
	var d_south := lz
	var d_east := RING_SIDE - lx
	var d_north := RING_SIDE - lz
	var d_west := lx
	var m := minf(minf(d_south, d_east), minf(d_north, d_west))
	if m == d_south:
		return lx
	if m == d_east:
		return RING_SIDE + lz
	if m == d_north:
		return RING_SIDE * 2.0 + (RING_SIDE - lx)
	return RING_SIDE * 3.0 + (RING_SIDE - lz)


## Ist der Punkt auf einer Fahrbahn (inkl. Kreuzung)?
static func is_on_road(pos: Vector3) -> bool:
	var cx := absf(pos.x - roundf(pos.x / CELL) * CELL)
	var cz := absf(pos.z - roundf(pos.z / CELL) * CELL)
	return cx < ROAD_HALF or cz < ROAD_HALF
