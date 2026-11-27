## Tire smoke and skid marks for the car's rear wheels.
extends Node3D

const PS2 := preload("res://scripts/ps2.gd")
const REAR := [2, 3]
const SEGMENT := 0.35      # meters between skid points
const MAX_POINTS := 700    # per wheel
const SLIP_THRESHOLD := 3.5

var car: RigidBody3D
var _smoke: Array[CPUParticles3D] = []
var _trails := [[], []]
var _last := [null, null]
var _mesh := ImmediateMesh.new()
var _skid_mat := StandardMaterial3D.new()


func _ready() -> void:
	_skid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_skid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_skid_mat.vertex_color_use_as_albedo = true
	_skid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for k in 2:
		_smoke.append(_make_smoke())


## Clear, smoky haze: big, faint, soft puffs that billow out slowly and linger.
func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 90
	p.lifetime = 3.2
	p.emitting = false
	p.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = PS2.smoke_texture(32)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Don't let puffs right at the lens (or inside the cockpit) wash out the view.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 1.0
	m.distance_fade_max_distance = 4.0
	quad.material = m
	p.mesh = quad
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.direction = Vector3.UP
	p.spread = 85.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, 0.25, 0)
	p.damping_min = 0.4
	p.damping_max = 1.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.0
	var curve := Curve.new()
	curve.max_value = 6.0
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.4, 3.2))
	curve.add_point(Vector2(1, 5.5))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.9, 0.84, 0.78, 0.0), Color(0.88, 0.82, 0.76, 0.26),
			Color(0.84, 0.74, 0.64, 0.14), Color(0.8, 0.68, 0.56, 0.0)])
	p.color_ramp = g
	add_child(p)
	return p


func _physics_process(_delta: float) -> void:
	if car == null:
		return
	var speed := car.linear_velocity.length()
	var dirty := false
	for k in 2:
		var wi: int = REAR[k]
		var skidding: bool = car.wheel_contact[wi] and speed > 3.0 and (
				car.wheel_slip[wi] > SLIP_THRESHOLD or car.handbrake)
		var n: Vector3 = car.wheel_normal[wi]
		var p: Vector3 = car.wheel_point[wi] + n * 0.04
		_smoke[k].emitting = skidding
		if skidding:
			_smoke[k].global_position = p + Vector3.UP * 0.2
			if _last[k] == null or p.distance_to(_last[k]) > SEGMENT:
				var side: Vector3 = car.global_transform.basis.x
				side = (side - n * side.dot(n)).normalized() * 0.13
				var strength := clampf(car.wheel_slip[wi] / 10.0, 0.45, 1.0)
				_trails[k].append([p - side, p + side, strength])
				_last[k] = p
				dirty = true
		elif _last[k] != null:
			_trails[k].append(null)   # break the strip
			_last[k] = null
		while _trails[k].size() > MAX_POINTS:
			_trails[k].pop_front()
	if dirty:
		_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var quads := 0
	for t in _trails:
		for idx in range(1, t.size()):
			if t[idx - 1] != null and t[idx] != null:
				quads += 1
	if quads == 0:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _skid_mat)
	for t in _trails:
		var count: int = t.size()
		for idx in range(1, count):
			var a = t[idx - 1]
			var b = t[idx]
			if a == null or b == null:
				continue
			var age := float(idx) / count   # 0 = oldest
			var col := Color(0.14, 0.08, 0.05, 0.6 * minf(1.0, age * 3.0) * b[2])
			for v in [a[0], b[0], a[1], a[1], b[0], b[1]]:
				_mesh.surface_set_color(col)
				_mesh.surface_add_vertex(v)
	_mesh.surface_end()
