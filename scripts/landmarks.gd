## Desert landmarks: a palm oasis, Najdi mud-brick ruins, a Palmyra-style "Lost City of
## Pillars", three small ruin sites (temple of columns, lone arch, scalloped gate) and a
## chapel set into a sandstone cliff.
## Only walls, piers, columns and towers collide; rubble and foundations are drive-through,
## and every ruin has wide openings so it's easy to drift inside.
extends Node3D

const PS2 := preload("res://scripts/ps2.gd")
const Terrain := preload("res://scripts/terrain.gd")
const WATER_SHADER := preload("res://shaders/water.gdshader")

const MUD := Color(0.76, 0.58, 0.4)
const MUD_DARK := Color(0.62, 0.45, 0.3)
const MUD_LIGHT := Color(0.86, 0.72, 0.54)
const VENT := Color(0.18, 0.12, 0.08)
const STONE := Color(0.88, 0.72, 0.54)
const STONE_2 := Color(0.8, 0.63, 0.46)
const STONE_DARK := Color(0.66, 0.5, 0.36)

var terrain
var _rng := RandomNumberGenerator.new()
var _mats := {}
var _sand_tex: Texture2D
var _body: StaticBody3D


func _ready() -> void:
	_rng.seed = 1446
	_sand_tex = PS2.sand_texture()
	_body = StaticBody3D.new()
	add_child(_body)
	_build_oasis()
	_build_najdi_ruins()
	_build_lost_city()
	_build_temple_of_columns()
	_build_lone_arch()
	_build_scalloped_gate()
	_build_chapel()


# --- Oasis -------------------------------------------------------------------

func _build_oasis() -> void:
	var c := Terrain.OASIS
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = Terrain.POND_R + 2.0
	disc.bottom_radius = Terrain.POND_R + 2.0
	disc.height = 0.05
	disc.radial_segments = 20
	disc.rings = 1
	water.mesh = disc
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	water.material_override = wm
	water.position = Vector3(c.x, Terrain.WATER_LEVEL, c.y)
	add_child(water)

	for i in 16:
		var a := TAU * i / 16.0 + _rng.randf_range(-0.15, 0.15)
		var d := _rng.randf_range(Terrain.POND_R + 4.0, Terrain.POND_R + 22.0)
		_palm(c + Vector2(cos(a), sin(a)) * d, _rng.randf_range(6.5, 11.0), Vector3(cos(a), 0, sin(a)))
	for i in 26:
		var a := _rng.randf() * TAU
		_bush(c + Vector2(cos(a), sin(a)) * _rng.randf_range(Terrain.POND_R + 2.0, Terrain.POND_R + 30.0))
	for i in 40:
		var a := _rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * _rng.randf_range(Terrain.POND_R - 1.0, Terrain.POND_R + 2.5)
		var h := _rng.randf_range(0.8, 1.6)
		var reed := _box(Vector3(0.06, h, 0.06), _ground(p) + Vector3(0, h * 0.5, 0), Color(0.5, 0.56, 0.22))
		reed.rotation = Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2))
	for i in 10:
		var a := _rng.randf() * TAU
		_rock(c + Vector2(cos(a), sin(a)) * _rng.randf_range(Terrain.POND_R + 5.0, Terrain.POND_R + 35.0))


func _palm(p: Vector2, height: float, lean: Vector3) -> void:
	var base := _ground(p) - Vector3(0, 0.2, 0)
	const SEGS := 7
	var pts: Array[Vector3] = []
	var bend := _rng.randf_range(0.8, 2.2)
	for i in SEGS + 1:
		var t := float(i) / SEGS
		pts.append(base + Vector3.UP * height * t + lean * bend * t * t)
	for i in SEGS:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := CylinderMesh.new()
		seg.top_radius = lerpf(0.24, 0.17, float(i + 1) / SEGS)
		seg.bottom_radius = lerpf(0.26, 0.19, float(i) / SEGS)
		seg.height = a.distance_to(b) + 0.05
		seg.radial_segments = 6
		seg.rings = 1
		var mi := _place(seg, (a + b) * 0.5, Color(0.42, 0.3, 0.18) if i % 2 == 0 else Color(0.5, 0.37, 0.22))
		mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	var top := pts[SEGS]
	var fronds := _rng.randi_range(8, 10)
	for k in fronds:
		var yaw := TAU * k / fronds + _rng.randf_range(-0.2, 0.2)
		var green := Color(0.22, 0.42, 0.14).lerp(Color(0.4, 0.55, 0.18), _rng.randf())
		var inner := Node3D.new()
		inner.position = top
		inner.rotation = Vector3(_rng.randf_range(0.05, 0.35), yaw, 0)
		add_child(inner)
		var leaf1 := _leaf(Vector3(0.55, 0.05, 1.8), green)
		leaf1.position.z = -0.9
		inner.add_child(leaf1)
		var outer := Node3D.new()
		outer.position.z = -1.8
		outer.rotation.x = -_rng.randf_range(0.6, 1.0)
		inner.add_child(outer)
		var leaf2 := _leaf(Vector3(0.38, 0.04, 1.9), green.darkened(0.1))
		leaf2.position.z = -0.95
		outer.add_child(leaf2)
	for k in 3:
		var a := TAU * k / 3.0
		var ball := SphereMesh.new()
		ball.radius = 0.28
		ball.height = 0.5
		ball.radial_segments = 6
		ball.rings = 3
		_place(ball, top + Vector3(cos(a) * 0.35, -0.45, sin(a) * 0.35), Color(0.85, 0.5, 0.15))
	_collider_cylinder(base + Vector3.UP * 2.0, 0.3, 4.0)


func _leaf(size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(col)
	return mi


func _bush(p: Vector2) -> void:
	var s := SphereMesh.new()
	var r := _rng.randf_range(0.7, 1.5)
	s.radius = r
	s.height = r * 1.3
	s.radial_segments = 6
	s.rings = 3
	_place(s, _ground(p) + Vector3(0, r * 0.35, 0), Color(0.3, 0.45, 0.16).lerp(Color(0.45, 0.5, 0.2), _rng.randf()))


func _rock(p: Vector2) -> void:
	var s := Vector3(_rng.randf_range(0.8, 2.2), _rng.randf_range(0.5, 1.4), _rng.randf_range(0.8, 2.0))
	var r := _box(s, _ground(p) + Vector3(0, s.y * 0.3, 0), Color(0.55, 0.42, 0.32))
	r.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))


# --- Najdi mud-brick compound ---------------------------------------------------

func _build_najdi_ruins() -> void:
	var c := Terrain.RUINS
	var o := _ground(c)
	const HALF := 28.0
	const SEG := 4.0
	# Perimeter walls in 4 m segments, with a 16 m opening in the middle of every side.
	for side in 4:
		var count := int(HALF * 2.0 / SEG)
		for i in count:
			var t := -HALF + SEG * (i + 0.5)
			if absf(t) < 7.0:
				continue
			var along_x := side < 2
			var sgn := -1.0 if side % 2 == 0 else 1.0
			var local := Vector3(t, 0, sgn * HALF) if along_x else Vector3(sgn * HALF, 0, t)
			var roll := _rng.randf()
			if roll < 0.2:
				_rubble(o + local, 5, MUD_DARK)
				continue
			var h := _rng.randf_range(3.2, 5.5) if roll > 0.45 else _rng.randf_range(1.0, 2.4)
			var size := Vector3(SEG + 0.05, h, 0.9) if along_x else Vector3(0.9, h, SEG + 0.05)
			_najdi_wall(o + local + Vector3(0, h * 0.5, 0), size, along_x, h > 3.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_najdi_tower(o + Vector3(sx * HALF, 0, sz * HALF), _rng.randf_range(8.0, 11.0))
	_najdi_gate(o + Vector3(HALF, 0, 0))
	# Two small collapsed houses tucked into corners, leaving the courtyard open.
	for spot in [Vector3(-17, 0, -17), Vector3(16, 0, -18)]:
		var h := _rng.randf_range(3.0, 4.5)
		var size := Vector3(_rng.randf_range(5, 7), h, _rng.randf_range(4, 5))
		_najdi_wall(o + spot + Vector3(0, h * 0.5, 0), size, true, true)
		_rubble(o + spot + Vector3(size.x * 0.6, 0, 2), 4, MUD_DARK)
	# Well (off to one side) and courtyard palms
	var w := o + Vector3(12, 0, 14)
	var well := CylinderMesh.new()
	well.top_radius = 1.3
	well.bottom_radius = 1.4
	well.height = 1.0
	well.radial_segments = 10
	_place(well, w + Vector3(0, 0.5, 0), MUD_DARK)
	var water := CylinderMesh.new()
	water.top_radius = 1.0
	water.bottom_radius = 1.0
	water.height = 0.02
	water.radial_segments = 10
	_place(water, w + Vector3(0, 0.98, 0), Color(0.1, 0.25, 0.28))
	for beam in [-1.0, 1.0]:
		_box(Vector3(0.15, 2.2, 0.15), w + Vector3(beam * 1.0, 1.1, 0), Color(0.4, 0.28, 0.16))
	_box(Vector3(2.4, 0.15, 0.15), w + Vector3(0, 2.2, 0), Color(0.4, 0.28, 0.16))
	_collider_cylinder(w + Vector3(0, 0.5, 0), 1.4, 1.0)
	for spot in [Vector2(-20, 6), Vector2(20, 20), Vector2(-6, -22)]:
		_palm(c + spot, _rng.randf_range(6.0, 8.5), Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized())
	for i in 10:
		_rubble(o + Vector3(_rng.randf_range(-40, 40), 0, _rng.randf_range(-40, 40)), 3, MUD_DARK)


func _najdi_wall(center: Vector3, size: Vector3, along_x: bool, crenellate: bool) -> void:
	_box(size, center, MUD, true)
	_collider_box(center, size)
	var top := center.y + size.y * 0.5
	_box(Vector3(size.x + 0.04, 0.25, size.z + 0.04), Vector3(center.x, top - 0.5, center.z), MUD_LIGHT)
	var length := size.x if along_x else size.z
	if crenellate:
		for k in int(length / 0.9):
			var off := -length * 0.5 + 0.45 + k * 0.9
			var pm := PrismMesh.new()
			pm.size = Vector3(0.6, 0.7, 0.5)
			var mi := _place(pm, Vector3(center.x + (off if along_x else 0.0), top + 0.35, center.z + (0.0 if along_x else off)), MUD)
			if not along_x:
				mi.rotation.y = PI * 0.5
	if size.y > 2.6:
		for k in int(length / 1.6):
			var off := -length * 0.5 + 0.8 + k * 1.6
			for face in [-1.0, 1.0]:
				var pm := PrismMesh.new()
				pm.size = Vector3(0.35, 0.35, 0.05)
				var fp := Vector3(off, 0, face * (size.z * 0.5 + 0.01)) if along_x else Vector3(face * (size.x * 0.5 + 0.01), 0, off)
				var mi := _place(pm, Vector3(center.x + fp.x, top - 1.1, center.z + fp.z), VENT)
				if not along_x:
					mi.rotation.y = PI * 0.5


func _najdi_tower(base: Vector3, h: float) -> void:
	var body := CylinderMesh.new()
	body.top_radius = 2.0
	body.bottom_radius = 2.8
	body.height = h
	body.radial_segments = 10
	body.rings = 1
	_place(body, base + Vector3(0, h * 0.5, 0), MUD, true)
	_collider_cylinder(base + Vector3(0, h * 0.5, 0), 2.6, h)
	for band in [h * 0.45, h - 0.6]:
		var ring := CylinderMesh.new()
		ring.top_radius = 2.0 + (h - band) / h * 0.8 + 0.06
		ring.bottom_radius = ring.top_radius + 0.02
		ring.height = 0.25
		ring.radial_segments = 10
		ring.rings = 1
		_place(ring, base + Vector3(0, band, 0), MUD_LIGHT)
	for k in 10:
		var a := TAU * k / 10.0
		var pm := PrismMesh.new()
		pm.size = Vector3(0.7, 0.8, 0.4)
		var mi := _place(pm, base + Vector3(cos(a) * 1.85, h + 0.4, sin(a) * 1.85), MUD)
		mi.rotation.y = -a + PI * 0.5
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		var slit := _box(Vector3(0.18, 0.9, 0.05), base + Vector3(cos(a) * 2.35, h * 0.7, sin(a) * 2.35), VENT)
		slit.rotation.y = -a + PI * 0.5


## Wide flat-lintel gate (Najdi doorways are square-topped), 16 m clear opening.
func _najdi_gate(at: Vector3) -> void:
	for s in [-1.0, 1.0]:
		var pc := at + Vector3(0, 3.8, s * 8.8)
		_box(Vector3(1.8, 7.6, 1.8), pc, MUD_DARK, true)
		_collider_box(pc, Vector3(1.8, 7.6, 1.8))
		for k in 3:
			var pm := PrismMesh.new()
			pm.size = Vector3(0.6, 0.7, 0.6)
			_place(pm, at + Vector3(0, 8.0, s * 8.8 + (k - 1) * 0.6), MUD)
	_box(Vector3(1.4, 0.9, 19.4), at + Vector3(0, 7.1, 0), MUD, true)
	_box(Vector3(1.5, 0.25, 19.4), at + Vector3(0, 6.6, 0), MUD_LIGHT)
	for k in 11:
		var pm := PrismMesh.new()
		pm.size = Vector3(0.5, 0.7, 0.6)
		var mi := _place(pm, at + Vector3(0, 7.9, -8.0 + k * 1.6), MUD)
		mi.rotation.y = PI * 0.5


# --- Lost City of Pillars (Palmyra-style) --------------------------------------
# A colonnaded avenue along X, a triple monumental arch across it, and a temple at
# the east end whose cella you can drive straight through.

func _build_lost_city() -> void:
	var c := Terrain.COLONNADE
	var o := _ground(c)
	const AV_HALF := 8.0
	const ARCH_X := -14.0
	# Colonnade: columns every 6 m on both sides; some full with lintels, some broken.
	for side in [-1.0, 1.0]:
		var prev_full := false
		var prev_top := Vector3.ZERO
		for i in 17:
			var x := -48.0 + i * 6.0
			if absf(x - ARCH_X) < 4.0:
				prev_full = false
				continue
			var base := o + Vector3(x, 0, side * AV_HALF)
			var roll := _rng.randf()
			if roll < 0.62:
				var top := _column(base, 8.5, true, -side)
				if prev_full and _rng.randf() < 0.75:
					_box(Vector3(6.3, 0.9, 1.5), (top + prev_top) * 0.5 + Vector3(0, 0.45, 0), STONE_2, true)
				prev_full = true
				prev_top = top
			elif roll < 0.85:
				_column(base, _rng.randf_range(1.5, 5.5), false, -side)
				_fallen_column(base + Vector3(_rng.randf_range(-2, 2), 0, side * 3.5), _rng.randi_range(2, 4))
				prev_full = false
			else:
				_plinth(base)
				prev_full = false
	_monumental_arch(o + Vector3(ARCH_X, 0, 0))
	_lost_city_temple(o + Vector3(70, 0, 0))
	# Avenue paving hints, house foundations, rubble and palms
	for i in 10:
		_box(Vector3(_rng.randf_range(2, 5), 0.08, _rng.randf_range(1.5, 3)), o + Vector3(_rng.randf_range(-48, 50), 0.04, _rng.randf_range(-6, 6)), STONE_DARK)
	for i in 8:
		var fx := _rng.randf_range(-45, 45)
		var fz := (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(14, 34)
		_foundation(o + Vector3(fx, 0, fz), Vector2(_rng.randf_range(6, 12), _rng.randf_range(5, 9)))
	for i in 30:
		_rubble(o + Vector3(_rng.randf_range(-55, 90), 0, _rng.randf_range(-35, 35)), 2, STONE_2)
	for i in 6:
		_fallen_column(o + Vector3(_rng.randf_range(-50, 50), 0, (1.0 if i % 2 == 0 else -1.0) * _rng.randf_range(11, 20)), _rng.randi_range(3, 5))
	for i in 9:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(40, 80)
		var p := c + Vector2(cos(a) * r * 1.2, sin(a) * r * 0.55)
		if absf(p.y - c.y) > 14.0:
			_palm(p, _rng.randf_range(7.0, 10.5), Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized())


## Three openings: a big central arch (9 m clear) flanked by two small ones.
func _monumental_arch(at: Vector3) -> void:
	const CR := 4.5        # central arch radius
	const SPRING := 8.0
	const PIER := Vector3(3.6, 0.0, 2.6)
	for s in [-1.0, 1.0]:
		# Central piers rise to the attic; outer piers carry the side arches.
		var inner_z: float = s * (CR + PIER.z * 0.5)
		var outer_z: float = s * (CR + PIER.z + 2.8 + PIER.z * 0.5)
		_pier(at + Vector3(0, 0, inner_z), Vector3(PIER.x, 14.0, PIER.z))
		_pier(at + Vector3(0, 0, outer_z), Vector3(PIER.x, 9.5 - _rng.randf_range(0, 2.5), PIER.z))
		# Side arch between them
		_arch(at + Vector3(0, 0, s * (CR + PIER.z + 1.4)), Vector3(0, 0, 1), 1.4, 5.0, 0.7, PIER.x * 0.9, STONE_2, 5)
		_box(Vector3(PIER.x * 0.9, 1.6, 2.8), at + Vector3(0, 7.9, s * (CR + PIER.z + 1.4)), STONE, true)
		# Spandrels over the central arch's haunches
		_box(Vector3(PIER.x * 0.92, 2.6, 2.2), at + Vector3(0, 12.7, s * (CR - 1.1)), STONE, true)
		# Niches on the pier faces
		for face in [-1.0, 1.0]:
			_box(Vector3(0.1, 1.8, 0.9), at + Vector3(face * (PIER.x * 0.5 + 0.02), 4.0, inner_z), STONE_DARK)
	_arch(at, Vector3(0, 0, 1), CR, SPRING, 1.1, PIER.x * 0.9, STONE_2, 9)
	# Attic with a broken, stepped top
	_box(Vector3(PIER.x, 1.6, (CR + PIER.z) * 2.0), at + Vector3(0, 14.8, 0), STONE, true)
	_box(Vector3(PIER.x + 0.3, 0.3, (CR + PIER.z) * 2.0 + 0.3), at + Vector3(0, 14.0, 0), STONE_DARK)
	for k in 6:
		var w := _rng.randf_range(1.0, 2.2)
		var h := _rng.randf_range(0.6, 1.8)
		_box(Vector3(PIER.x * 0.9, h, w), at + Vector3(0, 15.6 + h * 0.5, _rng.randf_range(-6, 6)), STONE_2, true)


func _pier(base: Vector3, size: Vector3) -> void:
	_box(size, base + Vector3(0, size.y * 0.5, 0), STONE, true)
	_box(Vector3(size.x + 0.4, 0.6, size.z + 0.4), base + Vector3(0, 0.3, 0), STONE_DARK)
	_box(Vector3(size.x + 0.3, 0.35, size.z + 0.3), base + Vector3(0, size.y - 0.2, 0), STONE_DARK)
	_collider_box(base + Vector3(0, size.y * 0.5, 0), size)


func _lost_city_temple(at: Vector3) -> void:
	# Cella: 22 x 12 m, doorways 8 m wide on both short ends so the avenue runs through.
	const LX := 11.0
	const LZ := 6.0
	const T := 1.2
	for s in [-1.0, 1.0]:
		var x := -LX + 1.25
		while x < LX:
			var h := _rng.randf_range(5.5, 10.0)
			_stone_wall(at + Vector3(x, h * 0.5, s * LZ), Vector3(2.5, h, T))
			x += 2.5
		for zs in [-1.0, 1.0]:
			var h := _rng.randf_range(7.0, 10.0)
			_stone_wall(at + Vector3(s * LX, h * 0.5, zs * 5.0), Vector3(T, h, 2.0))
		# Door frame lintel (trilithon) over each 8 m doorway
		_box(Vector3(T + 0.3, 1.2, 10.4), at + Vector3(s * LX, 10.4, 0), STONE_2, true)
	# Peristyle: a ring of columns 4.5 m outside the cella, gaps wide enough to drive through.
	var px := LX + 4.5
	var pz := LZ + 4.5
	var x := -px
	while x <= px + 0.1:
		for zs in [-1.0, 1.0]:
			_peristyle_column(at + Vector3(x, 0, zs * pz))
		x += 6.5
	var z := -pz + 6.5
	while z < pz - 0.1:
		for xs in [-1.0, 1.0]:
			if absf(z) > 4.5:
				_peristyle_column(at + Vector3(xs * px, 0, z))
		z += 6.5


func _peristyle_column(base: Vector3) -> void:
	if _rng.randf() < 0.7:
		_column(base, 10.0, true, 0.0)
	else:
		_column(base, _rng.randf_range(1.0, 4.0), false, 0.0)
		_fallen_column(base + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)), 3)


func _stone_wall(center: Vector3, size: Vector3) -> void:
	_box(size, center, STONE if _rng.randf() < 0.6 else STONE_2, true)
	_collider_box(center, size)
	# Coursing lines
	var y := center.y - size.y * 0.5 + 1.2
	while y < center.y + size.y * 0.5 - 0.3:
		_box(Vector3(size.x + 0.03, 0.06, size.z + 0.03), Vector3(center.x, y, center.z), STONE_DARK)
		y += 1.2


# --- Small ruin sites ----------------------------------------------------------

## Stepped platform with a few columns, one pair still carrying its lintel.
func _build_temple_of_columns() -> void:
	var o := _ground(Terrain.TEMPLE)
	# Two low steps (drive-up-able: the car clears 0.6 m)
	_box(Vector3(20, 0.3, 12), o + Vector3(0, 0.15, 0), STONE_DARK, true)
	_box(Vector3(17, 0.3, 9.5), o + Vector3(0, 0.45, 0), STONE_2, true)
	_collider_box(o + Vector3(0, 0.3, 0), Vector3(17, 0.6, 9.5))
	var floor_y := o + Vector3(0, 0.6, 0)
	var t1 := _column(floor_y + Vector3(4, 0, -3), 10.0, true, 0.0)
	var t2 := _column(floor_y + Vector3(7.5, 0, -3), 10.0, true, 0.0)
	_box(Vector3(4.6, 1.0, 1.6), (t1 + t2) * 0.5 + Vector3(0, 0.5, 0), STONE_2, true)
	_column(floor_y + Vector3(-6, 0, -3), 7.0, false, 0.0)
	_column(floor_y + Vector3(-2, 0, -3), 4.0, false, 0.0)
	_column(floor_y + Vector3(-6, 0, 3), 2.2, false, 0.0)
	_plinth(floor_y + Vector3(1, 0, 3))
	_fallen_column(o + Vector3(-4, 0, 9), 5)
	_fallen_column(o + Vector3(6, 0, 10), 3)
	for i in 8:
		_rubble(o + Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-10, 12)), 2, STONE_2)


## A single arch flanked by column pairs carrying entablature, broken at the top.
func _build_lone_arch() -> void:
	var o := _ground(Terrain.LONE_ARCH)
	const R := 3.2
	for s in [-1.0, 1.0]:
		_pier(o + Vector3(0, 0, s * (R + 0.9)), Vector3(1.8, 8.5, 1.8))
		var a := _column(o + Vector3(0, 0, s * 7.0), 8.5, true, 0.0)
		var b := _column(o + Vector3(0, 0, s * 10.0), 8.5 if s > 0 else 5.0, s > 0, 0.0)
		_box(Vector3(1.5, 0.9, 3.4), o + Vector3(0, a.y - o.y + 0.45, s * 5.55), STONE_2, true)
		if s > 0:
			_box(Vector3(1.5, 0.9, 3.4), (a + b) * 0.5 + Vector3(0, 0.45, 0), STONE_2, true)
	_arch(o, Vector3(0, 0, 1), R, 8.5, 1.0, 1.7, STONE_2, 7)
	# Broken block attic
	for k in 7:
		var h := _rng.randf_range(0.7, 2.0)
		_box(Vector3(1.6, h, _rng.randf_range(0.9, 1.6)), o + Vector3(0, 13.0 + h * 0.5, -3.5 + k * 1.1), STONE, true)
	_column(o + Vector3(6, 0, 3), 3.2, false, 0.0)
	_column(o + Vector3(7, 0, -6), 2.0, false, 0.0)
	for i in 10:
		_rubble(o + Vector3(_rng.randf_range(-10, 12), 0, _rng.randf_range(-12, 12)), 3, STONE_DARK)


## Wall fragment with a scalloped (multifoil) arch big enough to drive through, and a clay jar.
func _build_scalloped_gate() -> void:
	var o := _ground(Terrain.SCALLOP_GATE)
	const R := 4.0
	const SPRING := 6.0
	const DEPTH := 2.2
	const WALL_TOP := 12.5
	var sand := Color(0.84, 0.66, 0.46)
	for s in [-1.0, 1.0]:
		var c := o + Vector3(0, WALL_TOP * 0.5, s * (R + 3.5))
		_box(Vector3(DEPTH, WALL_TOP, 7.0), c, sand, true)
		_collider_box(c, Vector3(DEPTH, WALL_TOP, 7.0))
		_box(Vector3(DEPTH + 0.3, 0.5, 1.2), o + Vector3(0, SPRING - 0.2, s * (R + 0.6)), STONE_DARK)  # impost
	_arch(o, Vector3(0, 0, 1), R, SPRING, 2.6, DEPTH, sand, 11)
	_box(Vector3(DEPTH, WALL_TOP - SPRING - R - 1.6, R * 2.0), o + Vector3(0, (WALL_TOP + SPRING + R + 1.6) * 0.5, 0), sand, true)
	# Cusps: lobes along the arch edge give the scalloped outline.
	for k in 7:
		var th := PI * (k + 0.5) / 7.0
		var lobe := CylinderMesh.new()
		lobe.top_radius = 0.75
		lobe.bottom_radius = 0.75
		lobe.height = DEPTH + 0.1
		lobe.radial_segments = 8
		lobe.rings = 1
		var mi := _place(lobe, o + Vector3(0, SPRING + sin(th) * (R - 0.15), cos(th) * (R - 0.15)), Color(0.9, 0.72, 0.48))
		mi.rotation.z = PI * 0.5
	_box(Vector3(DEPTH + 0.2, 0.4, 15.0), o + Vector3(0, WALL_TOP + 0.2, 0), STONE_DARK)
	# Big clay jar beside the arch
	var jar := o + Vector3(-3.0, 0, R + 1.5)
	var body := SphereMesh.new()
	body.radius = 0.85
	body.height = 1.9
	body.radial_segments = 10
	body.rings = 5
	_place(body, jar + Vector3(0, 0.95, 0), Color(0.55, 0.3, 0.18))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.45
	neck.bottom_radius = 0.35
	neck.height = 0.5
	neck.radial_segments = 10
	neck.rings = 1
	_place(neck, jar + Vector3(0, 2.0, 0), Color(0.5, 0.27, 0.16))
	_collider_cylinder(jar + Vector3(0, 1.0, 0), 0.85, 2.0)
	for i in 12:
		_rubble(o + Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-14, 14)), 2, STONE_DARK)
	_foundation(o + Vector3(-12, 0, 0), Vector2(8, 14))


# --- Sandstone chapel -----------------------------------------------------------
# A chapel built into a striped sandstone cliff (after church-in-mountain.jpg): the cliff
# opens around the chapel and overhangs it like a cave. The facade faces -Z (toward spawn).

func _build_chapel() -> void:
	var o := _ground(Terrain.CHAPEL)
	var strata := [Color(0.86, 0.72, 0.52), Color(0.8, 0.64, 0.45), Color(0.9, 0.78, 0.6), Color(0.74, 0.58, 0.4)]
	const GAP := 11.0            # half-width of the opening the chapel sits in
	const OVERHANG_Y := 22.0
	var y := 0.0
	var layer := 0
	while y < 44.0:
		var h := _rng.randf_range(3.0, 4.6)
		var col: Color = strata[layer % strata.size()]
		if y >= OVERHANG_Y:
			# Full-width layers that jut out over the chapel; the crest narrows and steps back.
			var crest := maxf(0.0, (y - 32.0) * 1.6)
			var front := -9.0 + (y - OVERHANG_Y) * 0.35 + crest * 0.4 + _rng.randf_range(-1.2, 1.2)
			_rock_layer(o, Vector3(-44.0 + crest + _rng.randf_range(0, 3), y, front), Vector3(44.0 - crest - _rng.randf_range(0, 3), y + h, 30.0), col)
		else:
			for side in [-1.0, 1.0]:
				var inner := GAP + _rng.randf_range(0.0, 1.5)
				var front := _rng.randf_range(-2.0, 1.5)
				var a := Vector3(side * inner, y, front)
				var b := Vector3(side * 44.0, y + h, 30.0)
				_rock_layer(o, Vector3(minf(a.x, b.x), y, front), Vector3(maxf(a.x, b.x), y + h, 30.0), col)
			_rock_layer(o, Vector3(-GAP - 1.0, y, 7.0), Vector3(GAP + 1.0, y + h, 30.0), col)
		y += h
		layer += 1
	# Carved niches and relief panels on the cliff face
	for i in 8:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * _rng.randf_range(15.0, 38.0)
		var ny := _rng.randf_range(2.5, 16.0)
		if _rng.randf() < 0.5:
			_box(Vector3(2.0, 3.0, 0.5), o + Vector3(x, ny, -2.3), Color(0.35, 0.26, 0.18))
			_disc(o + Vector3(x, ny + 1.5, -2.3), 1.0, 0.5, Color(0.35, 0.26, 0.18))
		else:
			_box(Vector3(_rng.randf_range(3, 6), _rng.randf_range(3, 5), 0.6), o + Vector3(x, ny, -2.4), Color(0.94, 0.84, 0.66), true)

	# Chapel
	var cream := Color(0.93, 0.83, 0.66)
	var trim := Color(0.8, 0.66, 0.46)
	var glass := Color(0.25, 0.45, 0.75)
	var dark := Color(0.18, 0.12, 0.08)
	const CZ := 1.0
	const FACE := CZ - 5.0
	_box(Vector3(11.0, 14.0, 10.0), o + Vector3(0, 7.0, CZ), cream, true)
	_collider_box(o + Vector3(0, 7.0, CZ), Vector3(11.0, 14.0, 10.0))
	_box(Vector3(11.6, 0.5, 10.4), o + Vector3(0, 14.1, CZ), trim)
	# Arched mosaic panel with a stone frame
	var mosaic := PS2.material(Color.WHITE, PS2.mosaic_texture(), false, 1.0, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(6.4, 6.0)
	var panel := MeshInstance3D.new()
	panel.mesh = quad
	panel.material_override = mosaic
	panel.position = o + Vector3(0, 8.0, FACE - 0.06)
	panel.rotation.y = PI
	add_child(panel)
	var top := _disc(o + Vector3(0, 11.0, FACE - 0.05), 3.2, 0.08, Color.WHITE)
	top.material_override = mosaic
	_arch(o + Vector3(0, 0, FACE - 0.15), Vector3(1, 0, 0), 3.2, 11.0, 0.5, 0.4, trim, 9)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.5, 6.0, 0.4), o + Vector3(sx * 3.45, 8.0, FACE - 0.15), trim)
	# Doorway, windows, steps
	_box(Vector3(2.6, 3.4, 0.1), o + Vector3(0, 1.7, FACE - 0.05), dark)
	_disc(o + Vector3(0, 3.4, FACE - 0.05), 1.3, 0.1, dark)
	for wx in [-3.4, 3.4]:
		_box(Vector3(0.9, 1.5, 0.08), o + Vector3(wx, 2.6, FACE - 0.05), glass)
		_disc(o + Vector3(wx, 3.35, FACE - 0.05), 0.45, 0.08, glass)
	for k in 3:
		_box(Vector3(8.0 - k * 1.2, 0.22 * (3 - k), 1.2), o + Vector3(0, 0.11 * (3 - k), FACE - 0.6 - (2 - k) * 1.2), trim, true)
	# Bell towers with domes and crosses
	for sx in [-1.0, 1.0]:
		var t := o + Vector3(sx * 7.3, 0, CZ - 2.5)
		_box(Vector3(3.8, 17.0, 3.8), t + Vector3(0, 8.5, 0), cream, true)
		_collider_box(t + Vector3(0, 8.5, 0), Vector3(3.8, 17.0, 3.8))
		for band in [6.0, 12.0, 17.0]:
			_box(Vector3(4.0, 0.3, 4.0), t + Vector3(0, band, 0), trim)
		for wy in [8.5, 14.0]:
			_box(Vector3(0.9, 2.4, 0.08), t + Vector3(0, wy, -1.95), glass)
			_disc(t + Vector3(0, wy + 1.2, -1.95), 0.45, 0.08, glass)
		var drum := CylinderMesh.new()
		drum.top_radius = 1.7
		drum.bottom_radius = 1.75
		drum.height = 1.4
		drum.radial_segments = 10
		drum.rings = 1
		_place(drum, t + Vector3(0, 17.85, 0), cream)
		var dome := SphereMesh.new()
		dome.radius = 1.9
		dome.height = 1.9
		dome.is_hemisphere = true
		dome.radial_segments = 10
		dome.rings = 4
		_place(dome, t + Vector3(0, 18.55, 0), Color(0.96, 0.9, 0.78))
		var white := Color(0.96, 0.94, 0.9)
		_box(Vector3(0.16, 1.5, 0.16), t + Vector3(0, 21.1, 0), white)
		_box(Vector3(0.8, 0.16, 0.16), t + Vector3(0, 21.4, 0), white)
	# Plaza: low wall outline, rocks, leafy trees
	_foundation(o + Vector3(0, 0, -20), Vector2(32, 18))
	for p in [Vector2(-9, -12), Vector2(9, -13), Vector2(-16, -8), Vector2(15, -7), Vector2(-4, -24), Vector2(20, -22)]:
		_tree(Terrain.CHAPEL + p)
	for i in 6:
		_rock(Terrain.CHAPEL + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, -10)))


func _rock_layer(o: Vector3, a: Vector3, b: Vector3, col: Color) -> void:
	var size := b - a
	var centre := o + (a + b) * 0.5
	_box(size, centre, col, true)
	_collider_box(centre, size)


func _disc(pos: Vector3, radius: float, thickness: float, col: Color) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = thickness
	c.radial_segments = 10
	c.rings = 1
	var mi := _place(c, pos, col)
	mi.rotation.x = PI * 0.5
	return mi


func _tree(p: Vector2) -> void:
	var base := _ground(p)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.3
	trunk.height = 3.2
	trunk.radial_segments = 6
	trunk.rings = 1
	_place(trunk, base + Vector3(0, 1.6, 0), Color(0.38, 0.27, 0.18))
	for k in 3:
		var leaves := SphereMesh.new()
		var r := _rng.randf_range(1.5, 2.2)
		leaves.radius = r
		leaves.height = r * 1.6
		leaves.radial_segments = 7
		leaves.rings = 4
		_place(leaves, base + Vector3(_rng.randf_range(-1, 1), 3.6 + k * 0.6, _rng.randf_range(-1, 1)),
				Color(0.24, 0.42, 0.18).lerp(Color(0.36, 0.52, 0.2), _rng.randf()))
	_collider_cylinder(base + Vector3(0, 1.6, 0), 0.35, 3.2)


# --- Stone building blocks -------------------------------------------------------

## Classical column (plinth, drums, flared capital). Returns the top centre.
## bracket_dir: +1/-1 adds a Palmyra-style console facing +Z/-Z, 0 for none.
func _column(base: Vector3, height: float, capital: bool, bracket_dir: float) -> Vector3:
	_plinth(base)
	var y := 0.55
	var shaft := height - (0.75 if capital else 0.0)
	var k := 0
	while y < shaft:
		var h := minf(1.5, shaft - y)
		var drum := CylinderMesh.new()
		drum.top_radius = 0.46
		drum.bottom_radius = 0.48
		drum.height = h - 0.03
		drum.radial_segments = 8
		drum.rings = 1
		var mi := _place(drum, base + Vector3(0, y + h * 0.5, 0), STONE if k % 2 == 0 else STONE_2)
		if not capital and y + h >= shaft:
			mi.rotation = Vector3(_rng.randf_range(-0.12, 0.12), 0, _rng.randf_range(-0.12, 0.12))
		y += h
		k += 1
	if capital:
		var cap := CylinderMesh.new()
		cap.top_radius = 0.85
		cap.bottom_radius = 0.48
		cap.height = 0.5
		cap.radial_segments = 4
		cap.rings = 1
		_place(cap, base + Vector3(0, y + 0.25, 0), STONE).rotation.y = PI * 0.25
		_box(Vector3(1.45, 0.25, 1.45), base + Vector3(0, y + 0.62, 0), STONE_2)
		y += 0.75
	if bracket_dir != 0.0 and height > 6.0:
		_box(Vector3(0.45, 0.3, 0.5), base + Vector3(0, height * 0.62, bracket_dir * 0.6), STONE_2)
	_collider_cylinder(base + Vector3(0, y * 0.5, 0), 0.55, y)
	return base + Vector3(0, y, 0)


func _plinth(base: Vector3) -> void:
	_box(Vector3(1.4, 0.55, 1.4), base + Vector3(0, 0.27, 0), STONE_DARK, true)


## Column drums lying in a row on the sand (drive-through).
func _fallen_column(at: Vector3, drums: int) -> void:
	var yaw := _rng.randf() * TAU
	var dir := Vector3(cos(yaw), 0, sin(yaw))
	for i in drums:
		var drum := CylinderMesh.new()
		drum.top_radius = 0.47
		drum.bottom_radius = 0.47
		drum.height = 1.4
		drum.radial_segments = 8
		drum.rings = 1
		var p := at + dir * (i * 1.6 + _rng.randf_range(-0.2, 0.3)) + Vector3(0, 0.4, 0)
		var mi := _place(drum, p, STONE if i % 2 == 0 else STONE_2)
		mi.basis = Basis(Quaternion(Vector3.UP, dir))


## Semicircular arch of voussoir blocks. `across` spans the opening horizontally.
func _arch(base_centre: Vector3, across: Vector3, radius: float, spring: float, ring: float,
		depth: float, col: Color, segs: int) -> void:
	var up := Vector3.UP
	var centre := base_centre + up * spring
	var depth_dir := up.cross(across).normalized()
	var r_mid := radius + ring * 0.5
	for k in segs:
		var th := PI * (k + 0.5) / segs
		var radial := across * cos(th) + up * sin(th)
		var tangent := -across * sin(th) + up * cos(th)
		var b := BoxMesh.new()
		b.size = Vector3(PI * r_mid / segs * 1.08, ring, depth)
		var mi := _place(b, centre + radial * r_mid, col if k % 2 == 0 else col.darkened(0.06), true)
		mi.basis = Basis(tangent, radial, depth_dir)


## Low outline of an old building's walls (drive-over height, no collision).
func _foundation(centre: Vector3, size: Vector2) -> void:
	for s in [-1.0, 1.0]:
		_box(Vector3(size.x, 0.45, 0.7), centre + Vector3(0, 0.22, s * size.y * 0.5), STONE_DARK)
		_box(Vector3(0.7, 0.45, size.y), centre + Vector3(s * size.x * 0.5, 0.22, 0), STONE_DARK)


func _rubble(at: Vector3, n: int, col: Color) -> void:
	for i in n:
		var s := Vector3(_rng.randf_range(0.4, 1.2), _rng.randf_range(0.3, 0.6), _rng.randf_range(0.4, 1.1))
		var b := _box(s, at + Vector3(_rng.randf_range(-1.8, 1.8), s.y * 0.4, _rng.randf_range(-1.8, 1.8)), col)
		b.rotation = Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4))


# --- Helpers -----------------------------------------------------------------

func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.y), p.y)


func _collider_box(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = center
	_body.add_child(cs)


func _collider_cylinder(center: Vector3, radius: float, height: float) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	cs.shape = c
	cs.position = center
	_body.add_child(cs)


func _box(size: Vector3, pos: Vector3, col: Color, textured := false) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _place(b, pos, col, textured)


func _place(m: Mesh, pos: Vector3, col: Color, textured := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = _mat(col, textured)
	add_child(mi)
	return mi


func _mat(col: Color, textured := false) -> ShaderMaterial:
	var key := "%s|%s" % [col.to_html(), textured]
	if not _mats.has(key):
		_mats[key] = PS2.material(col, _sand_tex if textured else null, false, 1.0, 0.5)
	return _mats[key]
