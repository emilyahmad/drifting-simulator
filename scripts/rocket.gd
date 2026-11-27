## Rocket boosters: hold SHIFT to lift off and fly for a few seconds on a recharging fuel tank.
## Lives under the car (a RigidBody3D) and pushes it with forces each physics tick. While
## airborne, A/D yaws the car and it self-levels so it comes down on its wheels.
## Draws the exhaust flames + glow and plays a synthesized rocket roar.
extends Node3D

const BURN_TIME := 3.5          # s of full burn on a full tank
const RECHARGE_TIME := 6.0      # s to refill an empty tank
const RECHARGE_DELAY := 0.8     # s after landing / letting go before it starts refilling
const GLIDE_FALL := 10.0        # m/s max fall speed after a rocket flight (soft landings)
const RELOCK_FUEL := 0.3        # after running dry, rockets stay off until refilled to this
const LIFT := 15.5              # m/s² upward (gravity is 9.8, so it climbs)
const PUSH := 9.0               # m/s² forward (more with W held)
const MAX_CLIMB := 13.0         # m/s vertical speed cap
const MAX_ALT := 90.0           # m above the ground: thrust fades out near this ceiling
const AIR_YAW_RATE := 1.8       # rad/s turn rate in the air at full steer
const LEVEL_TORQUE := 9000.0
const VOLUME_DB := -6.0

var fuel := 1.0                 # 0..1, read by the HUD
var locked := false             # ran dry: waiting for RELOCK_FUEL
var firing := false
var enabled := true             # car turns this off in menus / cinematics

var _car: RigidBody3D
var _idle_t := 0.0
var _flew := false              # in the air because of the rockets: glide down gently
var _flames: Array[Node3D] = []     # pivots at each nozzle; the flame cone hangs off -Y
var _flame_mat: StandardMaterial3D
var _light: OmniLight3D
var _sfx: AudioStreamPlayer3D
var _sfx_level := 0.0
var _t := 0.0


func _ready() -> void:
	_car = get_parent() as RigidBody3D
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	for i in 2:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.22        # nozzle end
		cone.bottom_radius = 0.02     # flame tip
		cone.height = 1.6
		cone.radial_segments = 8
		cone.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = _flame_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = -cone.height * 0.5   # wide (top) end sits at the pivot = nozzle
		var pivot := Node3D.new()
		pivot.visible = false
		pivot.add_child(mi)
		add_child(pivot)
		_flames.append(pivot)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 9.0
	_light.light_energy = 0.0
	add_child(_light)
	_sfx = AudioStreamPlayer3D.new()
	_sfx.stream = _roar()
	_sfx.unit_size = 14.0
	_sfx.max_db = 0.0
	_sfx.volume_db = -80.0
	add_child(_sfx)


## Place the nozzles at the back of a car of this size (w, h, l), car-local.
func fit(size: Vector3, ground_y: float) -> void:
	var z := size.z * 0.5 + 0.1
	var y := ground_y + clampf(size.y * 0.3, 0.55, 0.9)
	for i in 2:
		var x := (-1.0 if i == 0 else 1.0) * size.x * 0.25
		# Pivot's -Y is the flame direction: tip it to point back (+Z) and a little down.
		_flames[i].position = Vector3(x, y, z)
		_flames[i].rotation = Vector3(-PI * 0.5 + 0.35, 0, 0)
	_light.position = Vector3(0, y, z + 1.2)


## Called from the car's _physics_process. `grounded` = wheels touching, `steer` = -1..1,
## `throttle` = 0..1, `ground_h` = terrain height below the car.
func step(delta: float, grounded: int, steer: float, throttle: float, ground_h: float) -> void:
	var want := enabled and Input.is_action_pressed("rocket")
	if locked and fuel >= RELOCK_FUEL:
		locked = false
	firing = want and not locked and fuel > 0.0
	if firing:
		fuel = maxf(fuel - delta / BURN_TIME, 0.0)
		_idle_t = 0.0
		if fuel <= 0.0:
			locked = true
		var m := _car.mass
		var v := _car.linear_velocity
		var alt := _car.global_position.y - ground_h
		var ceiling := 1.0 - smoothstep(MAX_ALT - 15.0, MAX_ALT, alt)
		var climb := clampf((MAX_CLIMB - v.y) / 4.0, 0.0, 1.0)
		_car.apply_central_force(Vector3.UP * m * LIFT * maxf(climb * ceiling, 9.8 / LIFT * ceiling))
		var fwd := -_car.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() > 0.1:
			_car.apply_central_force(fwd.normalized() * m * PUSH * (0.5 + 0.5 * throttle))
	elif grounded > 0:
		# Refuels only on the ground, so flights stay short hops rather than endless hovering.
		_idle_t += delta
		if _idle_t > RECHARGE_DELAY:
			fuel = minf(fuel + delta / RECHARGE_TIME, 1.0)
	else:
		_idle_t = 0.0

	if firing:
		_flew = true
	elif grounded >= 3:
		_flew = false
	if grounded == 0:
		_air_control(steer)
		# After a flight, cap the fall speed so the landing doesn't kill all your speed.
		if _flew and not firing and _car.linear_velocity.y < -GLIDE_FALL:
			var excess := -GLIDE_FALL - _car.linear_velocity.y
			_car.apply_central_force(Vector3.UP * _car.mass * minf(excess * 6.0, 25.0))


## In the air: turn with A/D and keep the car upright so it lands on its wheels.
func _air_control(steer: float) -> void:
	var up := _car.global_transform.basis.y
	var w := _car.angular_velocity
	var k := 1.0 if firing else 0.5
	# Level: rotate the car's up toward world up, with damping on the tilt rate.
	var level := up.cross(Vector3.UP) * LEVEL_TORQUE * k
	var tilt_w := w - Vector3.UP * w.dot(Vector3.UP)
	_car.apply_torque(level - tilt_w * LEVEL_TORQUE * 0.25 * k)
	# Yaw toward the requested turn rate.
	var yaw_err := steer * AIR_YAW_RATE - w.dot(Vector3.UP)
	_car.apply_torque(Vector3.UP * yaw_err * 2500.0 * k)


func _process(delta: float) -> void:
	_t += delta
	var target := 1.0 if firing else 0.0
	_sfx_level = move_toward(_sfx_level, target, delta * (8.0 if firing else 4.0))
	for f in _flames:
		f.visible = _sfx_level > 0.02
		var flick := 0.85 + 0.3 * sin(_t * 47.0 + f.position.x * 9.0) * sin(_t * 31.0)
		f.scale = Vector3(1.0, maxf(_sfx_level * flick, 0.05), 1.0)
	_flame_mat.albedo_color = Color(1.0, 0.5 + 0.15 * sin(_t * 23.0), 0.15, 0.9 * _sfx_level)
	_light.light_energy = 3.0 * _sfx_level
	if _sfx_level > 0.01:
		if not _sfx.playing:
			_sfx.play()
		_sfx.volume_db = VOLUME_DB + linear_to_db(_sfx_level)
	elif _sfx.playing:
		_sfx.stop()


## A 2 s seamless loop of rumbling noise: brown-ish noise with some crackle on top.
static func _roar() -> AudioStreamWAV:
	const RATE := 22050
	var n := RATE * 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var raw := PackedFloat32Array()
	raw.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	# Run the filters over the buffer twice so the loop point has settled filter state.
	for pass_i in 2:
		for i in n:
			var white := rng.randf_range(-1.0, 1.0)
			lp += (white - lp) * 0.08
			lp2 += (lp - lp2) * 0.25
			var crackle := white * 0.25 if rng.randf() < 0.02 else 0.0
			raw[i] = lp2 * 3.2 + lp * 0.6 + crackle
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(tanh(raw[i] * 1.4) * 0.7, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav
