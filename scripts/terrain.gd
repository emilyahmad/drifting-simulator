## Procedural red-sand dunes around a flat compacted-sand drift pad.
extends Node3D

const PS2 := preload("res://scripts/ps2.gd")

const GRID := 161          # vertices per side
const STEP := 4.0          # meters between vertices (coarse = PS2 poly budget)
const HALF := (GRID - 1) * STEP * 0.5   # 320 m (640 m square map)
const PAD_RADIUS := 55.0
# Landmark sites (flattened ground), all within ~150-190 m of spawn. See landmarks.gd.
const OASIS := Vector2(150, -20)
const OASIS_R := 75.0
const OASIS_H := 2.5
const POND_R := 22.0
const POND_DEPTH := 2.2
const WATER_LEVEL := OASIS_H - 0.7
const RUINS := Vector2(-150, 40)          # Najdi mud-brick compound
const COLONNADE := Vector2(-30, -150)     # Palmyra-style lost city of pillars
const TEMPLE := Vector2(110, 130)         # small temple of columns
const LONE_ARCH := Vector2(-120, 150)
const SCALLOP_GATE := Vector2(150, -165)
const CHAPEL := Vector2(0, 190)         # sandstone cliff chapel (facade faces spawn, -Z)
## [centre, flatten radius, ground height]
const SITES := [
	[RUINS, 85.0, 4.0],
	[COLONNADE, 110.0, 3.0],
	[TEMPLE, 45.0, 3.5],
	[LONE_ARCH, 40.0, 2.0],
	[SCALLOP_GATE, 40.0, 3.0],
	[CHAPEL, 75.0, 3.0],
]

var _ridge := FastNoiseLite.new()
var _swell := FastNoiseLite.new()
var _heights := PackedFloat32Array()


func _ready() -> void:
	_ridge.seed = 1932
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 3
	_ridge.frequency = 0.0055
	_swell.seed = 77
	_swell.frequency = 0.0018
	_build()


func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var mask := smoothstep(PAD_RADIUS, PAD_RADIUS + 90.0, d)
	# Stretch along x so crests form long transverse dunes.
	var ridge := _ridge.get_noise_2d(x * 0.55, z) * 0.5 + 0.5
	var swell := _swell.get_noise_2d(x, z) * 0.5 + 0.5
	var dunes := ridge * ridge * 16.0 + swell * 10.0
	var edge := maxf(absf(x), absf(z))
	var border := smoothstep(HALF - 100.0, HALF - 6.0, edge) * 9.0
	var h := dunes * mask + border
	var p := Vector2(x, z)
	h = lerpf(h, OASIS_H, 1.0 - smoothstep(OASIS_R * 0.55, OASIS_R, p.distance_to(OASIS)))
	for site in SITES:
		h = lerpf(h, site[2], 1.0 - smoothstep(site[1] * 0.72, site[1], p.distance_to(site[0])))
	# Pond bowl in the middle of the oasis
	h -= POND_DEPTH * (1.0 - smoothstep(POND_R * 0.3, POND_R + 6.0, p.distance_to(OASIS)))
	return h


func _build() -> void:
	_heights.resize(GRID * GRID)
	for j in GRID:
		for i in GRID:
			_heights[j * GRID + i] = height_at(i * STEP - HALF, j * STEP - HALF)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize(GRID * GRID)
	normals.resize(GRID * GRID)
	colors.resize(GRID * GRID)
	uvs.resize(GRID * GRID)

	var low := Color(0.60, 0.29, 0.15)
	var crest := Color(0.90, 0.57, 0.33)
	var pad := Color(0.74, 0.56, 0.42)
	for j in GRID:
		for i in GRID:
			var k := j * GRID + i
			var x := i * STEP - HALF
			var z := j * STEP - HALF
			var h := _heights[k]
			verts[k] = Vector3(x, h, z)
			var hl := _h(i - 1, j)
			var hr := _h(i + 1, j)
			var hd := _h(i, j - 1)
			var hu := _h(i, j + 1)
			normals[k] = Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			var t := clampf(h / 22.0, 0.0, 1.0)
			var c := low.lerp(crest, t)
			var pad_t := 1.0 - smoothstep(PAD_RADIUS - 10.0, PAD_RADIUS + 20.0, Vector2(x, z).length())
			c = c.lerp(pad, pad_t)
			# Oasis: damp dark sand at the water, green grass ring around it
			var od := Vector2(x, z).distance_to(OASIS)
			c = c.lerp(Color(0.4, 0.5, 0.2), (1.0 - smoothstep(30.0, 52.0, od)) * 0.85)
			c = c.lerp(Color(0.36, 0.26, 0.16), 1.0 - smoothstep(POND_R - 2.0, POND_R + 5.0, od))
			# Ruin sites: packed pale earth
			for site in SITES:
				var rd := Vector2(x, z).distance_to(site[0])
				c = c.lerp(Color(0.8, 0.64, 0.46), (1.0 - smoothstep(site[1] * 0.45, site[1] * 0.85, rd)) * 0.6)
			colors[k] = c.srgb_to_linear()
			uvs[k] = Vector2(x, z)

	for j in GRID - 1:
		for i in GRID - 1:
			var a := j * GRID + i
			var b := a + 1
			var c := a + GRID
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = PS2.material(Color.WHITE, PS2.sand_texture(), true, 0.125, 0.6)
	add_child(mi)

	# Collision: uniform scale keeps the heightmap happy in Jolt.
	var body := StaticBody3D.new()
	add_child(body)
	var shape := HeightMapShape3D.new()
	shape.map_width = GRID
	shape.map_depth = GRID
	var scaled := PackedFloat32Array()
	scaled.resize(_heights.size())
	for k in _heights.size():
		scaled[k] = _heights[k] / STEP
	shape.map_data = scaled
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * STEP
	body.add_child(cs)

	# Invisible walls at the map edge.
	for w in [[Vector3(HALF + 2, 50, 0), Vector3(4, 100, HALF * 2)],
			[Vector3(-HALF - 2, 50, 0), Vector3(4, 100, HALF * 2)],
			[Vector3(0, 50, HALF + 2), Vector3(HALF * 2, 100, 4)],
			[Vector3(0, 50, -HALF - 2), Vector3(HALF * 2, 100, 4)]]:
		var box := BoxShape3D.new()
		box.size = w[1]
		var wcs := CollisionShape3D.new()
		wcs.shape = box
		wcs.position = w[0]
		body.add_child(wcs)

	# Endless flat desert beyond the playable area (visual only, swallowed by fog).
	# Four subdivided strips around the map, never under it: one huge plane z-fought with the dunes.
	var far_mat := PS2.material(Color(0.66, 0.36, 0.2), null, false, 1.0, 0.0)
	var r := HALF - 12.0
	const OUT := 4500.0
	for strip in [[Vector2(0, -(r + OUT) * 0.5), Vector2(OUT * 2, OUT - r)],
			[Vector2(0, (r + OUT) * 0.5), Vector2(OUT * 2, OUT - r)],
			[Vector2(-(r + OUT) * 0.5, 0), Vector2(OUT - r, r * 2)],
			[Vector2((r + OUT) * 0.5, 0), Vector2(OUT - r, r * 2)]]:
		var pm := PlaneMesh.new()
		pm.size = strip[1]
		pm.subdivide_width = 16
		pm.subdivide_depth = 16
		var far := MeshInstance3D.new()
		far.mesh = pm
		far.position = Vector3(strip[0].x, -0.3, strip[0].y)
		far.material_override = far_mat
		add_child(far)


func _h(i: int, j: int) -> float:
	i = clampi(i, 0, GRID - 1)
	j = clampi(j, 0, GRID - 1)
	return _heights[j * GRID + i]
