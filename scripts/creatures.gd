## Low-poly desert wildlife: camel herds, Arabian oryx, red foxes, spiny-tailed lizards
## and circling falcons. Ground animals wander around a home area and flee from the car.
extends Node3D

const PS2 := preload("res://scripts/ps2.gd")
const Terrain := preload("res://scripts/terrain.gd")

var terrain
var car: Node3D

var _rng := RandomNumberGenerator.new()
var _mats := {}
var _animals: Array[Dictionary] = []
var _birds: Array[Dictionary] = []
var _t := 0.0

# Per-species tuning: walk/run speed (m/s), flee radius (m), leg swing amount.
const SPECIES := {
	"camel": {"walk": 1.3, "run": 6.5, "flee": 16.0, "swing": 0.45, "stride": 1.6},
	"oryx": {"walk": 1.6, "run": 11.0, "flee": 32.0, "swing": 0.6, "stride": 3.0},
	"fox": {"walk": 1.8, "run": 9.0, "flee": 18.0, "swing": 0.8, "stride": 9.0},
	"lizard": {"walk": 0.6, "run": 5.0, "flee": 9.0, "swing": 0.0, "stride": 0.0},
}


func _ready() -> void:
	_rng.seed = 2030
	# Small groups scattered across the whole desert, each wandering its own patch.
	for g in 8:
		_herd("camel", _scatter_spot(), 60.0, _rng.randi_range(1, 3))
	for g in 5:
		_herd("oryx", _scatter_spot(), 80.0, _rng.randi_range(2, 4))
	for g in 7:
		_herd("fox", _scatter_spot(), 50.0, 1)
	for g in 10:
		_herd("lizard", _scatter_spot(), 30.0, 1)
	# A few lizards sunning themselves at each ruin site
	for site in Terrain.SITES:
		_herd("lizard", site[0], 25.0, 2)
	_resting_camel(Terrain.OASIS + Vector2(-Terrain.POND_R - 7, 4), 1.2)
	_resting_camel(Terrain.OASIS + Vector2(-Terrain.POND_R - 9, -3), 2.4)
	# Falcons circling over the landmarks and open desert
	_falcon(Terrain.COLONNADE, 40.0, 30.0, 0.22)
	_falcon(Terrain.RUINS, 32.0, 26.0, -0.25)
	_falcon(Terrain.OASIS, 40.0, 30.0, -0.2)
	for f in 3:
		_falcon(_scatter_spot(), _rng.randf_range(30, 60), _rng.randf_range(25, 45), _rng.randf_range(0.15, 0.3) * (1.0 if f % 2 == 0 else -1.0))


## Random spot in the open desert, away from the spawn pad and the pond.
func _scatter_spot() -> Vector2:
	for attempt in 30:
		var lim := Terrain.HALF - 40.0
		var p := Vector2(_rng.randf_range(-lim, lim), _rng.randf_range(-lim, lim))
		if p.length() > 70.0 and p.distance_to(Terrain.OASIS) > Terrain.POND_R + 10.0:
			return p
	return Vector2(200, 200)


# --- Spawning ----------------------------------------------------------------

func _herd(kind: String, home: Vector2, radius: float, count: int) -> void:
	for i in count:
		var pos := home + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * radius * 0.4
		var a := {"kind": kind, "home": home, "radius": radius, "pos": pos, "target": pos,
				"heading": _rng.randf() * TAU, "speed": 0.0, "timer": _rng.randf_range(0.5, 4.0),
				"idle": true, "phase": _rng.randf() * TAU, "legs": []}
		a["node"] = call("_build_" + kind, a["legs"])
		add_child(a["node"])
		_animals.append(a)


func _resting_camel(p: Vector2, yaw: float) -> void:
	var legs: Array = []
	var n := _build_camel(legs)
	for leg in legs:
		leg.visible = false           # legs folded under the body
	n.get_child(0).position.y -= 1.15  # lower the whole body group
	add_child(n)
	n.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
	n.rotation.y = yaw


func _falcon(centre: Vector2, radius: float, height: float, speed: float) -> void:
	var n := Node3D.new()
	var brown := Color(0.45, 0.35, 0.27)
	_part(n, Vector3(0.22, 0.18, 0.62), Vector3.ZERO, brown)
	_part(n, Vector3(0.16, 0.14, 0.18), Vector3(0, 0.04, -0.38), Color(0.6, 0.52, 0.42))
	_part(n, Vector3(0.18, 0.04, 0.3), Vector3(0, 0, 0.42), brown.darkened(0.2))
	var wings: Array = []
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(s * 0.1, 0.02, -0.02)
		n.add_child(pivot)
		_part(pivot, Vector3(0.75, 0.03, 0.34), Vector3(s * 0.38, 0, 0), brown)
		_part(pivot, Vector3(0.4, 0.03, 0.22), Vector3(s * 0.9, 0, 0.06), brown.darkened(0.25))
		wings.append(pivot)
	add_child(n)
	_birds.append({"node": n, "wings": wings, "centre": centre, "radius": radius,
			"height": height, "speed": speed, "angle": _rng.randf() * TAU})


# --- Models (all face -Z, origin on the ground) --------------------------------

func _build_camel(legs: Array) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()      # child 0: everything above the legs
	root.add_child(body)
	var fur := Color(0.78, 0.6, 0.4).lerp(Color(0.66, 0.48, 0.3), _rng.randf())
	_part(body, Vector3(0.85, 0.8, 1.9), Vector3(0, 1.75, 0), fur)
	var hump := SphereMesh.new()
	hump.radius = 0.5
	hump.height = 0.8
	hump.radial_segments = 6
	hump.rings = 3
	_mesh(body, hump, Vector3(0, 2.2, 0.1), fur)
	_part(body, Vector3(0.3, 1.15, 0.36), Vector3(0, 2.2, -1.1), fur, Vector3(-0.65, 0, 0))
	_part(body, Vector3(0.3, 0.32, 0.62), Vector3(0, 2.72, -1.55), fur)
	_part(body, Vector3(0.22, 0.2, 0.12), Vector3(0, 2.66, -1.88), fur.darkened(0.2))
	for s in [-1.0, 1.0]:
		_part(body, Vector3(0.06, 0.14, 0.06), Vector3(s * 0.12, 2.94, -1.4), fur.darkened(0.15))
	_part(body, Vector3(0.08, 0.6, 0.08), Vector3(0, 1.55, 0.98), fur.darkened(0.2), Vector3(0.3, 0, 0))
	_legs(root, legs, [Vector3(-0.3, 1.45, -0.7), Vector3(0.3, 1.45, -0.7), Vector3(-0.3, 1.45, 0.7), Vector3(0.3, 1.45, 0.7)],
			Vector3(0.17, 1.45, 0.17), fur)
	return root


func _build_oryx(legs: Array) -> Node3D:
	var root := Node3D.new()
	var white := Color(0.93, 0.91, 0.86)
	var dark := Color(0.15, 0.12, 0.1)
	_part(root, Vector3(0.55, 0.55, 1.35), Vector3(0, 1.05, 0), white)
	_part(root, Vector3(0.24, 0.6, 0.3), Vector3(0, 1.4, -0.68), white, Vector3(-0.5, 0, 0))
	_part(root, Vector3(0.22, 0.25, 0.46), Vector3(0, 1.72, -0.92), white)
	_part(root, Vector3(0.23, 0.08, 0.4), Vector3(0, 1.72, -0.94), dark)     # face stripe
	_part(root, Vector3(0.57, 0.12, 0.9), Vector3(0, 0.82, 0.05), Color(0.6, 0.5, 0.4))  # flank band
	for s in [-1.0, 1.0]:
		_part(root, Vector3(0.035, 1.0, 0.035), Vector3(s * 0.07, 2.2, -0.65), dark, Vector3(0.55, 0, s * 0.05))  # horn
	_part(root, Vector3(0.06, 0.45, 0.06), Vector3(0, 1.0, 0.72), dark, Vector3(0.3, 0, 0))
	_legs(root, legs, [Vector3(-0.18, 0.8, -0.5), Vector3(0.18, 0.8, -0.5), Vector3(-0.18, 0.8, 0.5), Vector3(0.18, 0.8, 0.5)],
			Vector3(0.09, 0.8, 0.09), white, dark)
	return root


func _build_fox(legs: Array) -> Node3D:
	var root := Node3D.new()
	var red := Color(0.82, 0.45, 0.22)
	_part(root, Vector3(0.24, 0.24, 0.62), Vector3(0, 0.38, 0), red)
	_part(root, Vector3(0.2, 0.18, 0.26), Vector3(0, 0.48, -0.38), red)
	_part(root, Vector3(0.08, 0.07, 0.12), Vector3(0, 0.45, -0.55), Color(0.2, 0.15, 0.12))
	for s in [-1.0, 1.0]:
		var ear := PrismMesh.new()
		ear.size = Vector3(0.12, 0.2, 0.04)
		_mesh(root, ear, Vector3(s * 0.07, 0.66, -0.36), red.darkened(0.1))
	_part(root, Vector3(0.14, 0.14, 0.5), Vector3(0, 0.42, 0.48), red, Vector3(0.45, 0, 0))
	_part(root, Vector3(0.1, 0.1, 0.12), Vector3(0, 0.3, 0.7), Color(0.95, 0.92, 0.88))   # white tail tip
	_legs(root, legs, [Vector3(-0.08, 0.28, -0.2), Vector3(0.08, 0.28, -0.2), Vector3(-0.08, 0.28, 0.2), Vector3(0.08, 0.28, 0.2)],
			Vector3(0.06, 0.28, 0.06), red.darkened(0.3))
	return root


func _build_lizard(_legs_out: Array) -> Node3D:
	var root := Node3D.new()
	var skin := Color(0.72, 0.66, 0.4)
	_part(root, Vector3(0.24, 0.1, 0.42), Vector3(0, 0.07, 0), skin)
	_part(root, Vector3(0.14, 0.08, 0.16), Vector3(0, 0.07, -0.28), skin.darkened(0.1))
	_part(root, Vector3(0.12, 0.07, 0.45), Vector3(0, 0.05, 0.42), skin.darkened(0.15))
	for x in [-0.15, 0.15]:
		for z in [-0.12, 0.14]:
			_part(root, Vector3(0.1, 0.04, 0.05), Vector3(x, 0.03, z), skin.darkened(0.2))
	return root


func _legs(root: Node3D, legs: Array, hips: Array, size: Vector3, col: Color, hoof := Color(0, 0, 0, 0)) -> void:
	for hip in hips:
		var pivot := Node3D.new()
		pivot.position = hip
		root.add_child(pivot)
		_part(pivot, size, Vector3(0, -size.y * 0.5, 0), col)
		if hoof.a > 0.0:
			_part(pivot, Vector3(size.x * 1.1, size.y * 0.15, size.z * 1.1), Vector3(0, -size.y * 0.92, 0), hoof)
		legs.append(pivot)


# --- Behaviour -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	var car_p := Vector2(car.global_position.x, car.global_position.z) if car else Vector2(1e6, 1e6)
	for a in _animals:
		var sp: Dictionary = SPECIES[a["kind"]]
		var pos: Vector2 = a["pos"]
		var away := pos - car_p
		var target_speed := 0.0
		var desired := Vector2.ZERO
		if away.length() < sp["flee"]:
			desired = away.normalized()
			target_speed = sp["run"]
			a["timer"] = 1.5
		else:
			a["timer"] -= delta
			if a["timer"] <= 0.0 or (not a["idle"] and pos.distance_to(a["target"]) < 1.5):
				a["idle"] = _rng.randf() < 0.35
				var ang := _rng.randf() * TAU
				a["target"] = a["home"] + Vector2(cos(ang), sin(ang)) * _rng.randf() * a["radius"]
				a["timer"] = _rng.randf_range(4.0, 12.0)
			if not a["idle"]:
				desired = (a["target"] - pos).normalized()
				target_speed = sp["walk"]
		a["speed"] = move_toward(a["speed"], target_speed, delta * (8.0 if target_speed > sp["walk"] else 2.0))
		if desired != Vector2.ZERO:
			var want := atan2(-desired.x, -desired.y)
			a["heading"] = rotate_toward(a["heading"], want, delta * 3.0)
		var h: float = a["heading"]
		pos += Vector2(-sin(h), -cos(h)) * a["speed"] * delta
		# Stay out of the pond and inside the map.
		var from_pond := pos - Terrain.OASIS
		if from_pond.length() < Terrain.POND_R + 3.0:
			pos = Terrain.OASIS + from_pond.normalized() * (Terrain.POND_R + 3.0)
		var edge := Terrain.HALF - 20.0
		pos = pos.clamp(Vector2(-edge, -edge), Vector2(edge, edge))
		a["pos"] = pos
		var node: Node3D = a["node"]
		node.position = Vector3(pos.x, terrain.height_at(pos.x, pos.y), pos.y)
		node.rotation.y = h
		# Leg swing (diagonal pairs) or a lizard's body wiggle.
		a["phase"] += a["speed"] * sp["stride"] * delta
		var amount: float = clampf(a["speed"] / sp["walk"], 0.0, 1.6) * sp["swing"]
		var legs: Array = a["legs"]
		for i in legs.size():
			legs[i].rotation.x = sin(a["phase"] + (PI if i == 1 or i == 2 else 0.0)) * amount
		if a["kind"] == "lizard":
			node.rotation.y += sin(_t * 30.0) * 0.15 * clampf(a["speed"], 0.0, 1.0)

	for b in _birds:
		b["angle"] += b["speed"] * delta
		var ang: float = b["angle"]
		var c: Vector2 = b["centre"]
		var p: Vector2 = c + Vector2(cos(ang), sin(ang)) * float(b["radius"])
		var node: Node3D = b["node"]
		node.position = Vector3(p.x, terrain.height_at(c.x, c.y) + b["height"] + sin(ang * 3.0) * 2.0, p.y)
		# Face along the circle and bank into the turn.
		var tangent: Vector2 = Vector2(-sin(ang), cos(ang)) * signf(b["speed"])
		node.rotation = Vector3(0, atan2(-tangent.x, -tangent.y), -0.35 * signf(b["speed"]))
		# Flap for a bit, then glide.
		var flap := sin(_t * 9.0) * 0.5 if fmod(_t + ang, 4.0) < 1.4 else 0.08
		var wings: Array = b["wings"]
		wings[0].rotation.z = flap
		wings[1].rotation.z = -flap


# --- Helpers -----------------------------------------------------------------

func _part(parent: Node3D, size: Vector3, pos: Vector3, col: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := _mesh(parent, b, pos, col)
	mi.rotation = rot
	return mi


func _mesh(parent: Node3D, m: Mesh, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	var key := col.to_html()
	if not _mats.has(key):
		_mats[key] = PS2.material(col)
	mi.material_override = _mats[key]
	parent.add_child(mi)
	return mi
