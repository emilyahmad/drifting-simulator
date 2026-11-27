## Low-poly Riyadh skyline on the northern horizon, after assets/design-references/saudi-skyline*.jpg:
## Kingdom Centre, Al Faisaliah, the TV tower, blade-shaped towers, and a hazy low-rise city.
extends Node3D

const PS2 := preload("res://scripts/ps2.gd")

const GLASS := [Color(0.5, 0.6, 0.72), Color(0.42, 0.52, 0.66), Color(0.6, 0.66, 0.74)]
const CONCRETE := [Color(0.7, 0.7, 0.72), Color(0.66, 0.63, 0.6), Color(0.58, 0.6, 0.64)]
const LOWRISE := [Color(0.8, 0.74, 0.64), Color(0.86, 0.85, 0.82), Color(0.72, 0.66, 0.58), Color(0.62, 0.64, 0.68)]

var _mats := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 966
	_lowrise_city()
	_towers()
	_kingdom_centre(Vector3(120, 0, -1450))
	_faisaliah(Vector3(420, 0, -1320))
	_tv_tower(Vector3(-560, 0, -1380))


# --- Landmarks ---------------------------------------------------------------

## Tall tapering slab whose top third splits around a parabolic opening, crossed by a skybridge.
func _kingdom_centre(base: Vector3) -> void:
	const H := 302.0
	const W := 64.0
	const D := 32.0
	const Y_OPEN := H * 0.62
	var outer := func(y: float) -> float: return W * 0.5 * (1.0 - 0.3 * y / H)
	var depth := func(y: float) -> float: return D * 0.5 * (1.0 - 0.25 * y / H)
	var opening := func(y: float) -> float:
		if y <= Y_OPEN:
			return 0.0
		return outer.call(y) * 0.82 * sqrt((y - Y_OPEN) / (H - Y_OPEN))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_slab(st, -outer.call(0.0), outer.call(0.0), 0.0, depth.call(0.0),
			-outer.call(Y_OPEN), outer.call(Y_OPEN), Y_OPEN, depth.call(Y_OPEN), false)
	const BANDS := 16
	for i in BANDS:
		var y0 := lerpf(Y_OPEN, H, float(i) / BANDS)
		var y1 := lerpf(Y_OPEN, H, float(i + 1) / BANDS)
		var top := i == BANDS - 1
		for s in [-1.0, 1.0]:
			var a0: float = s * opening.call(y0)
			var b0: float = s * outer.call(y0)
			var a1: float = s * opening.call(y1)
			var b1: float = s * outer.call(y1)
			_slab(st, minf(a0, b0), maxf(a0, b0), y0, depth.call(y0),
					minf(a1, b1), maxf(a1, b1), y1, depth.call(y1), top)
	st.generate_normals()
	_place(st.commit(), base, Color(0.46, 0.58, 0.72))

	var by := H * 0.86
	_box(Vector3(opening.call(by) * 2.0 + 2.0, 6.0, D * 0.4), base + Vector3(0, by, 0), Color(0.3, 0.34, 0.4))


## Four-sided tapering spire with a golden sphere and a needle on top.
func _faisaliah(base: Vector3) -> void:
	var pyr := CylinderMesh.new()
	pyr.top_radius = 2.0
	pyr.bottom_radius = 30.0
	pyr.height = 240.0
	pyr.radial_segments = 4
	pyr.rings = 1
	_place(pyr, base + Vector3(0, 120, 0), Color(0.66, 0.66, 0.68)).rotation.y = PI * 0.25
	var ball := SphereMesh.new()
	ball.radius = 12.0
	ball.height = 24.0
	ball.radial_segments = 8
	ball.rings = 5
	_place(ball, base + Vector3(0, 200, 0), Color(0.95, 0.72, 0.32))
	var needle := CylinderMesh.new()
	needle.top_radius = 0.3
	needle.bottom_radius = 2.0
	needle.height = 45.0
	needle.radial_segments = 4
	needle.rings = 1
	_place(needle, base + Vector3(0, 262, 0), Color(0.75, 0.75, 0.75))


## Thin concrete shaft with a saucer-shaped pod and a red/white antenna.
func _tv_tower(base: Vector3) -> void:
	_cyl(4.5, 3.5, 165.0, base + Vector3(0, 82.5, 0), Color(0.78, 0.76, 0.72), 8)
	_cyl(10.0, 15.0, 7.0, base + Vector3(0, 145, 0), Color(0.35, 0.36, 0.4), 10)
	_cyl(17.0, 17.0, 9.0, base + Vector3(0, 153, 0), Color(0.3, 0.32, 0.36), 10)
	_cyl(12.0, 16.0, 6.0, base + Vector3(0, 160.5, 0), Color(0.55, 0.55, 0.58), 10)
	for k in 5:
		var col := Color(0.85, 0.15, 0.12) if k % 2 == 0 else Color(0.92, 0.92, 0.9)
		_cyl(1.6 - k * 0.2, 1.8 - k * 0.2, 14.0, base + Vector3(0, 170 + k * 14.0, 0), col, 6)


# --- City fabric -------------------------------------------------------------

func _towers() -> void:
	for i in 46:
		var a := _rng.randf_range(-0.6, 0.55)
		var dist := _rng.randf_range(1350.0, 1900.0)
		var pos := _arc(a, dist)
		var h := _rng.randf_range(50.0, 120.0)
		if _rng.randf() < 0.25:
			h = _rng.randf_range(140.0, 230.0)
		var w := _rng.randf_range(16.0, 36.0)
		var col: Color = GLASS[_rng.randi() % GLASS.size()] if _rng.randf() < 0.6 else CONCRETE[_rng.randi() % CONCRETE.size()]
		match _rng.randi() % 5:
			0, 1:
				_box(Vector3(w, h, w * _rng.randf_range(0.6, 1.1)), pos + Vector3(0, h * 0.5, 0), col).rotation.y = _rng.randf() * PI
			2:
				_cyl(w * 0.45, w * 0.5, h, pos + Vector3(0, h * 0.5, 0), col, 8)
			3:
				# Blade / shard tower with a sloped top
				var pm := PrismMesh.new()
				pm.size = Vector3(w, h, w * 0.8)
				pm.left_to_right = 1.0 if _rng.randf() < 0.5 else 0.0
				var mi := _place(pm, pos + Vector3(0, h * 0.5, 0), col)
				mi.rotation.y = _rng.randf_range(-0.6, 0.6)
			4:
				_box(Vector3(w, h, w), pos + Vector3(0, h * 0.5, 0), col)
				_box(Vector3(w * 0.6, h * 0.2, w * 0.6), pos + Vector3(0, h * 1.1, 0), col)
				if _rng.randf() < 0.5:
					_box(Vector3(1.2, 35, 1.2), pos + Vector3(0, h * 1.2 + 17, 0), Color(0.5, 0.5, 0.52))


func _lowrise_city() -> void:
	for i in 150:
		var a := _rng.randf_range(-0.85, 0.8)
		var dist := _rng.randf_range(1150.0, 1600.0)
		var h := _rng.randf_range(8.0, 30.0)
		var size := Vector3(_rng.randf_range(25, 70), h, _rng.randf_range(20, 50))
		var col: Color = LOWRISE[_rng.randi() % LOWRISE.size()]
		_box(size, _arc(a, dist) + Vector3(0, h * 0.5, 0), col).rotation.y = a + _rng.randf_range(-0.1, 0.1)


# --- Helpers -----------------------------------------------------------------

func _arc(angle: float, dist: float) -> Vector3:
	return Vector3(sin(angle) * dist, 0.0, -cos(angle) * dist)


## Adds a tapered block spanning [l0,r0] at y0 to [l1,r1] at y1, with half-depths d0/d1.
func _slab(st: SurfaceTool, l0: float, r0: float, y0: float, d0: float,
		l1: float, r1: float, y1: float, d1: float, cap_top: bool) -> void:
	var f00 := Vector3(l0, y0, d0)
	var f01 := Vector3(r0, y0, d0)
	var f11 := Vector3(r1, y1, d1)
	var f10 := Vector3(l1, y1, d1)
	var b00 := Vector3(l0, y0, -d0)
	var b01 := Vector3(r0, y0, -d0)
	var b11 := Vector3(r1, y1, -d1)
	var b10 := Vector3(l1, y1, -d1)
	_quad(st, f00, f01, f11, f10)
	_quad(st, b00, b01, b11, b10)
	_quad(st, b00, f00, f10, b10)
	_quad(st, f01, b01, b11, f11)
	if cap_top:
		_quad(st, f10, f11, b11, b10)


## Double-sided quad: whichever winding faces the camera survives back-face culling.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d, a, c, b, a, d, c]:
		st.add_vertex(v)


func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _place(b, pos, col)


func _cyl(top: float, bottom: float, h: float, pos: Vector3, col: Color, segments: int) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segments
	c.rings = 1
	return _place(c, pos, col)


func _place(m: Mesh, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	if not _mats.has(col):
		_mats[col] = PS2.material(col, null, false, 1.0, 0.0)
	mi.material_override = _mats[col]
	add_child(mi)
	return mi
