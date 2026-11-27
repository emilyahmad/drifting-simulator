## Water splashes at the oasis pond: a big burst when the car hits the water, a steady spray
## from every wheel driving through it (stronger with speed), a splash sound, and some drag.
extends Node3D

const PS2 := preload("res://scripts/ps2.gd")
const Terrain := preload("res://scripts/terrain.gd")
const BURST_MIN_SPEED := 4.0     # m/s needed for an entry splash
const SPRAY_MIN_SPEED := 1.5
const WATER_DRAG := 900.0        # N per m/s, scaled by how many wheels are in the water

var car: RigidBody3D
var _spray: Array[CPUParticles3D] = []
var _burst: CPUParticles3D
var _ring: CPUParticles3D
var _sfx: AudioStreamPlayer3D
var _was_wet := false
var _cooldown := 0.0


func _ready() -> void:
	for i in 4:
		var p := _droplets(70, 0.7, 0.8, 1.5)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.3
		p.direction = Vector3.UP
		p.spread = 35.0
		_spray.append(p)
	_burst = _droplets(260, 1.3, 1.0, 2.2)
	_burst.one_shot = true
	_burst.explosiveness = 0.95
	_burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_burst.emission_sphere_radius = 1.4
	_burst.direction = Vector3.UP
	_burst.spread = 55.0
	_burst.initial_velocity_min = 4.0
	_burst.initial_velocity_max = 10.0
	# Low, wide sheet of water thrown outward around the car.
	_ring = _droplets(160, 0.9, 1.0, 2.0)
	_ring.one_shot = true
	_ring.explosiveness = 1.0
	_ring.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_ring.emission_ring_axis = Vector3.UP
	_ring.emission_ring_radius = 1.8
	_ring.emission_ring_inner_radius = 1.2
	_ring.emission_ring_height = 0.1
	_ring.direction = Vector3.UP
	_ring.spread = 70.0
	_ring.initial_velocity_min = 3.0
	_ring.initial_velocity_max = 6.0
	_sfx = AudioStreamPlayer3D.new()
	_sfx.stream = _splash_sound()
	_sfx.unit_size = 14.0
	_sfx.volume_db = -4.0
	add_child(_sfx)


## Small blue-white droplets that arc up and fall back under gravity.
## Sizes are multiples of a 0.16 m droplet.
func _droplets(amount: int, lifetime: float, size_min: float, size_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = PS2.blob_texture(16)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Fade droplets right at the lens so the spray never blinds the camera.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 1.5
	m.distance_fade_max_distance = 4.0
	quad.material = m
	p.mesh = quad
	p.gravity = Vector3(0, -14.0, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(0.6, 0.8))
	curve.add_point(Vector2(1, 0.3))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(0.9, 0.97, 1.0, 0.0), Color(0.78, 0.9, 1.0, 0.9), Color(0.5, 0.72, 0.85, 0.0)])
	p.color_ramp = g
	add_child(p)
	return p


func _physics_process(delta: float) -> void:
	if car == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	var v: Vector3 = car.linear_velocity
	var speed := v.length()
	var wet := 0
	for i in 4:
		var p: Vector3 = car.wheel_point[i]
		var in_water: bool = car.wheel_contact[i] and _in_pond(p) and p.y < Terrain.WATER_LEVEL - 0.05
		var sp := _spray[i]
		if in_water:
			wet += 1
			sp.global_position = Vector3(p.x, Terrain.WATER_LEVEL + 0.05, p.z)
			# Faster = taller, wider spray thrown back from the wheel.
			var k := clampf(speed / 20.0, 0.0, 1.0)
			sp.initial_velocity_min = 1.0 + k * 3.0
			sp.initial_velocity_max = 2.5 + k * 6.0
			var back := -v.normalized() if speed > 0.5 else Vector3.ZERO
			sp.direction = (Vector3.UP + back * 0.6 * k).normalized()
		sp.emitting = in_water and speed > SPRAY_MIN_SPEED
		if in_water and speed > 8.0:
			car.windshield.splash(car.windshield.wet + delta * 0.15)
	# Entry splash (also when slamming down into the water from a jump or the rockets).
	var is_wet := wet > 0
	if is_wet and not _was_wet and _cooldown <= 0.0 and (speed > BURST_MIN_SPEED or v.y < -4.0):
		var c: Vector3 = car.global_position
		var at := Vector3(c.x, Terrain.WATER_LEVEL + 0.1, c.z)
		var power := clampf(maxf(speed, -v.y * 1.5) / 25.0, 0.35, 1.0)
		# Harder hits throw the water higher and wider.
		_burst.initial_velocity_min = 3.0 + 3.0 * power
		_burst.initial_velocity_max = 5.0 + 8.0 * power
		_ring.initial_velocity_min = 2.0 + 2.0 * power
		_ring.initial_velocity_max = 3.5 + 4.0 * power
		for b in [_burst, _ring]:
			b.global_position = at
			b.restart()
		_sfx.global_position = at
		_sfx.volume_db = -10.0 + 10.0 * power
		_sfx.play()
		_cooldown = 0.6
		car.windshield.splash(0.6 + 0.4 * power)
	_was_wet = is_wet
	# Water drag: wading through the pond slows the car down.
	if wet > 0:
		car.apply_central_force(-v * WATER_DRAG * (wet / 4.0))


func _in_pond(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(Terrain.OASIS) < Terrain.POND_R + 2.0


## 0.9 s splash: a noise burst with a quick attack and a falling, darkening tail.
static func _splash_sound() -> AudioStreamWAV:
	const RATE := 22050
	var n := int(RATE * 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.01, 1.0) * exp(-t * 5.0)
		# Cutoff falls over time: a bright "splash" settling into a duller wash.
		var cut := lerpf(0.55, 0.08, minf(t / 0.6, 1.0))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cut
		var bubbles := sin(t * TAU * (300.0 + 200.0 * sin(t * 37.0))) * 0.15 * exp(-t * 9.0)
		data.encode_s16(i * 2, int(clampf((lp * 1.6 + bubbles) * env, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
