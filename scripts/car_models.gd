## Selectable car bodies: the procedural white jeep plus the cars from
## "PS2 car pack" (https://skfb.ly/pHUTV) by the soppy prisma models .- , CC BY 4.0
## (http://creativecommons.org/licenses/by/4.0/). Changes: re-scaled, re-centred, re-shaded.
extends RefCounted

const PS2 := preload("res://scripts/ps2.gd")
const PACK_PATH := "res://assets/models/ps2_car_pack.glb"
const SCALE := 0.14          # pack units -> metres
const GROUND_Y := -0.83      # car-local height of the ground at rest suspension

const CREDIT := "\"PS2 car pack\" (https://skfb.ly/pHUTV) by the soppy prisma models .- is licensed under Creative Commons Attribution (http://creativecommons.org/licenses/by/4.0/). Models re-scaled and re-shaded."

## "glow": optional neon underglow colour (or "police" for flashing red/blue).
const LIST := [
	{"name": "WHITE JEEP", "ar": "جيب أبيض", "mesh": ""},
	{"name": "RED WAGON", "ar": "ستيشن أحمر", "mesh": "Object_2"},
	{"name": "NAVY SEDAN", "ar": "سيدان كحلي", "mesh": "Object_3", "glow": Color(0.1, 0.9, 1.0)},
	{"name": "MAROON SEDAN", "ar": "سيدان عنابي", "mesh": "Object_4", "glow": Color(1.0, 0.2, 0.85)},
	{"name": "SILVER WAGON", "ar": "ستيشن فضي", "mesh": "Object_5"},
	{"name": "GREEN HATCH", "ar": "هاتشباك أخضر", "mesh": "Object_6", "glow": Color(0.5, 1.0, 0.2)},
	{"name": "BLUE WAGON", "ar": "ستيشن أزرق", "mesh": "Object_7"},
	{"name": "BLUE VAN", "ar": "فان أزرق", "mesh": "Object_8"},
	{"name": "CLASSIC SEDAN", "ar": "سيدان كلاسيكي", "mesh": "Object_9", "glow": Color(0.6, 0.25, 1.0)},
	{"name": "POLICE CRUISER", "ar": "دورية شرطة", "mesh": "Object_10", "glow": "police"},
	{"name": "YELLOW TAXI", "ar": "تاكسي أصفر", "mesh": "Object_11"},
	{"name": "RUST BUCKET", "ar": "خردة صدئة", "mesh": "Object_12"},
	{"name": "TEAL WRECK", "ar": "حطام فيروزي", "mesh": "Object_13"},
	{"name": "PURPLE WRECK", "ar": "حطام بنفسجي", "mesh": "Object_14"},
]

static var _meshes := {}


static func _load_pack() -> void:
	if not _meshes.is_empty():
		return
	var root: Node = load(PACK_PATH).instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		_meshes[String(mi.name)] = mi.mesh
	root.free()


## Returns {"node": MeshInstance3D, "size": Vector3 (w, h, l) in metres} for a pack car,
## positioned in car space with its wheels on the ground and its nose toward -Z.
static func build(index: int) -> Dictionary:
	_load_pack()
	var mesh: Mesh = _meshes[LIST[index]["mesh"]]
	var aabb := mesh.get_aabb()
	# Pack is Z-up: raw (x, y, z) -> car space (x, z, -y).
	var b := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)).scaled(Vector3.ONE * SCALE)
	var c := aabb.get_center()
	var bottom_centre := Vector3(c.x, c.y, aabb.position.z)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(b, Vector3(0, GROUND_Y, 0) - b * bottom_centre)
	var src := mesh.surface_get_material(0) as BaseMaterial3D
	mi.material_override = PS2.material(Color.WHITE, src.albedo_texture if src else null, false, 1.0, 0.7)
	return {"node": mi, "size": Vector3(aabb.size.x, aabb.size.z, aabb.size.y) * SCALE}
