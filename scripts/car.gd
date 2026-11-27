## Arcade drift car: RigidBody3D with raycast suspension and simple tire forces.
## Rear tires lose grip on handbrake / power-over, with assists to keep slides controllable.
extends RigidBody3D

const PS2 := preload("res://scripts/ps2.gd")
const CarModels := preload("res://scripts/car_models.gd")
const Horn := preload("res://scripts/horn.gd")
const Rocket := preload("res://scripts/rocket.gd")
const Windshield := preload("res://scripts/windshield.gd")
const Terrain := preload("res://scripts/terrain.gd")

# Suspension
const WHEEL_RADIUS := 0.42
const REST_LENGTH := 0.5
const SPRING := 20000.0          # softer = more body roll / pitch
const DAMPER := 1700.0
# Body roll ("floppiness"): a higher centre of mass and tyre forces acting lower down give
# more leverage to tip the car, so hard turns lift the inside wheels onto two.
const COM_HEIGHT := 0.05         # car-local; was -0.35 (very planted)
const TIRE_FORCE_HEIGHT := -0.05 # m above the contact patch while cornering (floppy); was 0.35
const DRIFT_FORCE_HEIGHT := 0.4  # while drifting: planted, so body roll doesn't trip the slide
const ROLL_RESCUE_STRENGTH := 80000.0
const ROLL_RESCUE_DEG := 28.0    # past this lean a righting torque stops a full roll-over
# Drive / brakes
const ENGINE_FORCE := 13000.0
const MAX_SPEED := 52.0          # m/s (~187 km/h)
const REVERSE_SPEED := 12.0
const BRAKE_FORCE := 4500.0
const HANDBRAKE_FORCE := 2200.0
const ROLLING_RESIST := 30.0
const AIR_DRAG := 0.45
# Tires
const LAT_STIFFNESS := 9000.0    # N per m/s of sideways slip
const FRONT_MU := 1.35
const REAR_MU := 1.25
const DRIFT_GRIP := 0.4          # rear grip multiplier while power-sliding
const HANDBRAKE_GRIP := 0.22
const POWER_OVER_GRIP := 0.5     # full steer + full throttle at speed breaks the rear loose
const POWER_OVER_SPEED := 8.0    # m/s (~30 km/h) before power-over kicks in
# Drift assists
const DRIFT_SLIP_ANGLE := 0.15   # rad of body slip that counts as drifting
const COUNTERSTEER_ASSIST := 0.7
const SPIN_LIMIT := 1.1          # rad (~63°); past this a stabilizer pulls the nose back
# Angle hold: in a slide, the steering picks the drift angle and the car settles there.
# Steering into the slide = deep angle, neutral = medium, countersteer = straighten out.
const ANGLE_NEUTRAL := 0.5       # rad (~29°)
const ANGLE_MAX := 0.9           # rad (~52°)
const ANGLE_HOLD_TORQUE := 7000.0
const ANGLE_HOLD_DAMP := 1100.0
const HANDBRAKE_KICK := 3000.0   # yaw torque when you pull the handbrake while steering
const DRIFT_PUSH := 3200.0       # N along the travel direction so slides don't bleed speed

const WHEEL_OFFSETS := [
	Vector3(-0.86, 0.0, -1.38), Vector3(0.86, 0.0, -1.38),   # front L/R
	Vector3(-0.86, 0.0, 1.28), Vector3(0.86, 0.0, 1.28),     # rear L/R
]

# Read by effects / HUD
var wheel_contact := [false, false, false, false]
var wheel_point := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var wheel_normal := [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
var wheel_slip := [0.0, 0.0, 0.0, 0.0]
var is_drifting := false
var handbrake := false
var body_slip := 0.0
var speed_kmh := 0.0

var _wheel_len := [REST_LENGTH, REST_LENGTH, REST_LENGTH, REST_LENGTH]
var _wheel_spin_speed := [0.0, 0.0, 0.0, 0.0]
var _steer := 0.0
var _rear_grip := 1.0
var _force_h := TIRE_FORCE_HEIGHT
var _pivots: Array[Node3D] = []
var _spinners: Array[Node3D] = []
var _shadow: MeshInstance3D
# LED underglow (every car, in its paint colour): additive glow decal on the ground + LED strips.
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _led_root: Node3D
var _led_mat: StandardMaterial3D
var _glow_kind = null      # null, a Color, or "police"
var _glow_t := 0.0
# Cockpit (first-person) view
var cockpit_camera: Camera3D
var horn: Horn
var rocket: Rocket
var terrain                      # set by main; the rocket uses it for its altitude ceiling
# Low invisible "plow" that shoves loose props (rubble, rocks, drums) out of the way. The car's
# own collision box starts 0.68 m up (the wheels are raycasts), so low props would slip under it.
var _plow: AnimatableBody3D
var _plow_shape: BoxShape3D
var _cockpit_fov := 72.0
var _cockpit: Node3D
var windshield: Windshield
# Working rear-view mirror: a second camera renders the view behind into the mirror glass.
const MIRROR_POS := Vector3(0, 1.24, -0.725)      # cockpit-local centre of the mirror glass
const MIRROR_SIZE := Vector2(0.24, 0.055)
const MIRROR_HIDDEN_LAYER := 2                    # render layer the mirror camera skips (front seat backs)
var _mirror: Node3D
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _wheel_spin: Node3D
var _speedo_needle: Node3D
var _rpm_needle: Node3D
var _beads: Node3D
var _hands: Node3D
# Honk animation: the right hand leaves the rim to press the horn pad, which sinks and lights up.
var _right_hand: Node3D
var _horn_pad: Node3D
var _horn_icon_mat: ShaderMaterial
var _honk := 0.0                 # 0 = hand on the rim, 1 = pressing the pad
# Idle fidgets: now and then (one at a time, with long gaps of just driving in between) the
# right hand leaves the wheel to do ONE small thing: shift gear, press a dash button, adjust
# the mirror or flick the prayer beads. Never the same one twice in a row.
const FIDGETS := ["gear", "buttons", "mirror", "beads"]
const FIDGET_REACH := 0.35       # s to move the hand from the wheel to the target (and back)
var _gear_stick: Node3D
var _gear_knob: MeshInstance3D
var _buttons: Array[MeshInstance3D] = []
var _mirror_base: Basis
var _fidget := ""                # current fidget, "" when the hand is on the wheel
var _fidget_t := 0.0
var _fidget_len := 0.0
var _fidget_wait := 10.0         # s until the next one
var _fidget_last := ""
var _fidget_btn := 0             # which button gets pressed this time
const FIDGET_GAP := Vector2(12.0, 30.0)    # s of normal driving between fidgets
var _exterior_glass: Array[MeshInstance3D] = []
var _bead_swing := 0.0
var _lat_vel_prev := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _reset_to = null
# Body / model selection
var input_enabled := true
var model_index := 0
var _jeep_body: Node3D
var _wheels_root: Node3D
var _model_body: MeshInstance3D
var _collision: CollisionShape3D
var _box: BoxShape3D


func _ready() -> void:
	mass = 1200.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, COM_HEIGHT, 0.05)
	can_sleep = false
	angular_damp = 1.2
	continuous_cd = true
	_collision = CollisionShape3D.new()
	_box = BoxShape3D.new()
	_collision.shape = _box
	add_child(_collision)
	_jeep_body = Node3D.new()
	add_child(_jeep_body)
	_wheels_root = Node3D.new()
	add_child(_wheels_root)
	_build_visuals()
	_build_cockpit()
	horn = Horn.new()
	horn.position = Vector3(0, 0.6, -1.8)   # front bumper
	add_child(horn)
	rocket = Rocket.new()
	add_child(rocket)
	_plow = AnimatableBody3D.new()
	_plow.sync_to_physics = true
	_plow.collision_layer = 4          # layer 3: only props scan it
	_plow.collision_mask = 0
	_plow_shape = BoxShape3D.new()
	var pcs := CollisionShape3D.new()
	pcs.shape = _plow_shape
	_plow.add_child(pcs)
	add_child(_plow)
	set_model(model_index)


## 0 = the white jeep; 1+ = cars from the PS2 car pack (their wheels are part of the mesh).
func set_model(index: int) -> void:
	model_index = index
	if _model_body:
		_model_body.queue_free()
		_model_body = null
	var size := Vector3(1.9, 2.25, 4.5)   # jeep: width, height above ground, length
	var is_jeep := index == 0
	_jeep_body.visible = is_jeep
	_wheels_root.visible = is_jeep
	if not is_jeep:
		var built := CarModels.build(index)
		_model_body = built["node"]
		add_child(_model_body)
		_model_body.visible = not _cockpit.visible
		size = built["size"]
	_build_underglow(size)
	rocket.fit(size, CarModels.GROUND_Y)
	# Plow: covers the car's footprint from just above the ground up to the main collision box.
	_plow_shape.size = Vector3(size.x * 0.95, 0.62, size.z * 0.98)
	_plow.position = Vector3(0, CarModels.GROUND_Y + 0.12 + 0.31, 0)
	# Collision: from 0.68 m above the ground up to the roof.
	var top := CarModels.GROUND_Y + size.y
	var bottom := CarModels.GROUND_Y + 0.68
	_box.size = Vector3(size.x * 0.95, maxf(top - bottom, 0.4), size.z * 0.95)
	_collision.position.y = (top + bottom) * 0.5
	# Sit the cockpit (and driver's eye) just under this car's roof.
	var offset := (top - 0.22) - (DRIVER_EYE.y + 0.0)
	offset = minf(offset, 0.0)
	_cockpit.position.y = offset
	cockpit_camera.position = DRIVER_EYE + Vector3(0, offset, 0)


func request_reset(pos: Vector3) -> void:
	_reset_to = pos


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _reset_to != null:
		var yaw := global_rotation.y
		state.transform = Transform3D(Basis(Vector3.UP, yaw), _reset_to)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_reset_to = null
		reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	var throttle := Input.get_action_strength("throttle")
	var brake := Input.get_action_strength("brake")
	var steer_in := Input.get_axis("steer_right", "steer_left")
	handbrake = Input.is_action_pressed("handbrake")
	horn.enabled = input_enabled
	rocket.enabled = input_enabled
	if not input_enabled:
		throttle = 0.0
		brake = 0.0
		steer_in = 0.0
		handbrake = true

	var b := global_transform.basis
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var vel_local := b.transposed() * linear_velocity
	var fwd_speed := -vel_local.z
	var speed := linear_velocity.length()
	speed_kmh = speed * 3.6

	body_slip = 0.0
	if fwd_speed > 2.0:
		body_slip = atan2(-vel_local.x, fwd_speed)
	is_drifting = fwd_speed > 5.0 and absf(body_slip) > DRIFT_SLIP_ANGLE

	# Steering: less lock at speed, full lock + auto countersteer while sliding.
	var max_steer := lerpf(0.62, 0.22, clampf(fwd_speed / 40.0, 0.0, 1.0))
	var target := steer_in * max_steer
	if is_drifting:
		target = clampf(steer_in * 0.62 + body_slip * COUNTERSTEER_ASSIST, -0.8, 0.8)
	_steer = move_toward(_steer, target, delta * 3.5)

	# Rear grip: drops fast, recovers gently.
	var grip_target := 1.0
	if handbrake:
		grip_target = HANDBRAKE_GRIP
	elif is_drifting and throttle > 0.3:
		grip_target = DRIFT_GRIP
	elif throttle > 0.7 and absf(steer_in) > 0.7 and fwd_speed > POWER_OVER_SPEED:
		grip_target = POWER_OVER_GRIP
	elif is_drifting:
		grip_target = 0.7
	# Countersteering hard (or having just straightened out) means "exit": grip comes back fast
	# so the tail doesn't swing through into a slide the other way.
	var exiting := not handbrake and (steer_in * body_slip > 0.0 and absf(steer_in) > 0.5 and is_drifting
			or not is_drifting and absf(body_slip) < DRIFT_SLIP_ANGLE and _rear_grip < 0.9 and grip_target == 1.0)
	if exiting:
		grip_target = 1.0
	var rate := 6.0 if grip_target < _rear_grip else (5.0 if exiting else 1.5)
	_rear_grip = move_toward(_rear_grip, grip_target, delta * rate)

	# Floppy body roll when cornering on grip; planted while sliding (blends over ~0.3 s).
	var power_over := throttle > 0.7 and absf(steer_in) > 0.7 and fwd_speed > POWER_OVER_SPEED
	var planted := is_drifting or handbrake or power_over
	_force_h = move_toward(_force_h, DRIFT_FORCE_HEIGHT if planted else TIRE_FORCE_HEIGHT, delta * 1.2)
	var space := get_world_3d().direct_space_state
	var com := global_transform * center_of_mass
	var grounded := 0
	for i in 4:
		var origin: Vector3 = global_transform * WHEEL_OFFSETS[i]
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * (REST_LENGTH + WHEEL_RADIUS))
		q.exclude = [get_rid()]
		q.collision_mask = 1           # ground and buildings only: drive through/shove loose props
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			wheel_contact[i] = false
			wheel_slip[i] = 0.0
			_wheel_len[i] = REST_LENGTH
			continue
		grounded += 1
		var p: Vector3 = hit.position
		var n: Vector3 = hit.normal
		var dist := origin.distance_to(p) - WHEEL_RADIUS
		_wheel_len[i] = maxf(dist, 0.0)
		var pv := linear_velocity + angular_velocity.cross(origin - com)

		var susp := maxf((REST_LENGTH - dist) * SPRING - up.dot(pv) * DAMPER, 0.0)
		apply_force(up * susp, origin - global_position)

		var is_front := i < 2
		var wf := fwd
		var wr := right
		if is_front:
			wf = fwd.rotated(up, _steer)
			wr = right.rotated(up, _steer)
		wf = (wf - n * wf.dot(n)).normalized()
		wr = (wr - n * wr.dot(n)).normalized()
		var v_long := wf.dot(pv)
		var v_lat := wr.dot(pv)

		var mu := FRONT_MU if is_front else REAR_MU * _rear_grip
		var max_f := susp * mu
		var f_lat := clampf(-v_lat * LAT_STIFFNESS, -max_f, max_f)

		var f_long := -v_long * ROLLING_RESIST
		if not is_front:
			if throttle > 0.0:
				f_long += throttle * ENGINE_FORCE * 0.5 * clampf(1.0 - fwd_speed / MAX_SPEED, 0.0, 1.0)
			if handbrake:
				f_long -= clampf(v_long * 600.0, -HANDBRAKE_FORCE, HANDBRAKE_FORCE)
		if brake > 0.0:
			if fwd_speed > 1.0:
				f_long -= clampf(v_long * 2000.0, -BRAKE_FORCE, BRAKE_FORCE) * brake
			elif not is_front:
				f_long -= brake * ENGINE_FORCE * 0.5 * 0.45 * clampf(1.0 + fwd_speed / REVERSE_SPEED, 0.0, 1.0)

		# Tyre forces act near the contact patch, below the centre of mass, so cornering rolls the body.
		apply_force(wf * f_long + wr * f_lat, (p + up * _force_h) - global_position)

		wheel_contact[i] = true
		wheel_point[i] = p
		wheel_normal[i] = n
		wheel_slip[i] = absf(v_lat)
		_wheel_spin_speed[i] = v_long / WHEEL_RADIUS
		if not is_front and handbrake:
			_wheel_spin_speed[i] = 0.0

	if grounded < 2:
		is_drifting = false
	elif handbrake and input_enabled and not is_drifting and fwd_speed > 6.0:
		# Handbrake + steer swings the tail out so even a quick tap starts a slide.
		apply_torque(up * steer_in * HANDBRAKE_KICK * clampf(speed / 15.0, 0.0, 1.0))
	if is_drifting:
		# Angle hold: steering sets a target drift angle and a spring yaws the car toward it.
		# `into` = how hard the player steers into the slide (+1) or against it (-1).
		var dir := -signf(body_slip)                 # yaw direction that deepens the slide
		var into := clampf(steer_in * dir, -1.0, 1.0)
		var angle_target := ANGLE_NEUTRAL + (ANGLE_MAX - ANGLE_NEUTRAL) * into if into >= 0.0 else ANGLE_NEUTRAL * (1.0 + into)
		if throttle < 0.2 and not handbrake:
			angle_target = minf(angle_target, absf(body_slip))   # off the throttle: never pull it deeper
		var yaw_rate := angular_velocity.dot(up)
		var err := angle_target - absf(body_slip)
		var k := clampf(speed / 12.0, 0.0, 1.0)
		# Countersteering adds extra yaw damping so the car settles straight instead of
		# swinging through into a slide the other way.
		var damp := ANGLE_HOLD_DAMP * (1.0 + 3.0 * maxf(0.0, -into))
		apply_torque(up * (dir * err * ANGLE_HOLD_TORQUE - yaw_rate * damp) * k)
		# Keep momentum through the slide while on the throttle.
		var flat_v := linear_velocity - up * linear_velocity.dot(up)
		if flat_v.length() > 1.0:
			apply_central_force(flat_v.normalized() * DRIFT_PUSH * throttle * clampf(absf(body_slip) / 0.6, 0.0, 1.0))
		# Stabilizer: pull the nose back toward the direction of travel at big angles,
		# and damp yaw rate so the car doesn't swap ends.
		var excess := smoothstep(SPIN_LIMIT * 0.6, SPIN_LIMIT * 1.3, absf(body_slip))
		apply_torque(up * body_slip * 9000.0 * excess)
		apply_torque(up * -angular_velocity.dot(up) * 2500.0 * excess)

	# Roll rescue: let the car balance on two wheels, but past ROLL_RESCUE_DEG push it back
	# down onto four so it doesn't flip onto its roof.
	var roll := asin(clampf(right.y, -1.0, 1.0))
	var over := absf(roll) - deg_to_rad(ROLL_RESCUE_DEG)
	if over > 0.0 and grounded > 0:
		var roll_rate := angular_velocity.dot(fwd)
		apply_torque(fwd * (signf(roll) * over * ROLL_RESCUE_STRENGTH - roll_rate * 4000.0))
	var gp := global_position
	var ground_h: float = terrain.height_at(gp.x, gp.z) if terrain else gp.y - 1.0
	rocket.step(delta, grounded, steer_in, throttle, ground_h)
	apply_central_force(-linear_velocity * speed * AIR_DRAG)
	_update_shadow()


func set_cockpit_view(on: bool) -> void:
	_cockpit.visible = on
	# The LED strips sit under the floor pan; on low cars the lowered cabin floor would end up
	# below them and they'd glow inside the car.
	if _led_root:
		_led_root.visible = not on
	for g in _exterior_glass:
		g.visible = not on
	if _model_body:
		# From inside, the pack model's own windows/roof would block the view.
		_model_body.visible = not on
	if on:
		cockpit_camera.make_current()


func _process(delta: float) -> void:
	if _cockpit.visible:
		_update_cockpit(delta)
	_update_glass(delta)
	_update_mirror()
	if _glow_kind != null:
		_glow_t += delta
		var c: Color
		if _glow_kind is String:
			c = Color(0.15, 0.35, 1.0) if fmod(_glow_t, 0.5) < 0.25 else Color(0.9, 0.95, 1.0)
		else:
			c = _glow_kind
		_led_mat.albedo_color = c
		# Additive glow: red/orange barely shows on the red sunset sand, so warm colours get a boost.
		var boost := 1.0 + 0.6 * clampf(c.r - maxf(c.g, c.b), 0.0, 1.0)
		_glow_mat.albedo_color = Color(c.r * boost, c.g * boost, c.b * boost, 0.85 + 0.12 * sin(_glow_t * 3.0))
	for i in 4:
		_pivots[i].position = WHEEL_OFFSETS[i] + Vector3(0, -_wheel_len[i], 0)
		if i < 2:
			_pivots[i].rotation.y = _steer
		_spinners[i].rotation.x -= _wheel_spin_speed[i] * delta


func _update_shadow() -> void:
	var sum := Vector3.ZERO
	var nsum := Vector3.ZERO
	var count := 0
	for i in 4:
		if wheel_contact[i]:
			sum += wheel_point[i]
			nsum += wheel_normal[i]
			count += 1
	_shadow.visible = count > 0
	# Hidden from the cockpit: on low cars the lowered cabin floor sits just above the ground
	# glow and it would bleed through the floor.
	_glow.visible = count > 0 and _glow_kind != null and not _cockpit.visible
	if count == 0:
		return
	var n := (nsum / count).normalized()
	var f := -global_transform.basis.z
	f = (f - n * f.dot(n)).normalized()
	_shadow.global_transform = Transform3D(Basis.looking_at(f, n), sum / count + n * 0.06)
	if _glow_kind != null:
		_glow.global_transform = Transform3D(Basis.looking_at(f, n), sum / count + n * 0.09)


func _build_visuals() -> void:
	# Boxy white desert 4x4, after assets/design-references/white-jeep.png
	var paint := Color(0.96, 0.96, 0.95)
	var glass := Color(0.07, 0.09, 0.12)
	var dark := Color(0.08, 0.08, 0.09)
	var chrome := Color(0.72, 0.73, 0.75)
	_part(Vector3(1.9, 0.86, 4.4), Vector3(0, 0.3, 0), paint)              # main body
	_part(Vector3(1.84, 0.64, 3.05), Vector3(0, 1.05, 0.65), paint)        # cabin (wagon roof)
	_part(Vector3(1.76, 0.05, 2.9), Vector3(0, 1.39, 0.65), Color(0.85, 0.84, 0.8))  # roof panel
	_exterior_glass.append(_part(Vector3(1.62, 0.48, 0.06), Vector3(0, 1.05, -0.86), glass))   # windshield
	_exterior_glass.append(_part(Vector3(1.4, 0.4, 0.04), Vector3(0, 1.07, 2.19), glass))      # rear window
	for z in [-0.35, 0.65, 1.65]:
		_exterior_glass.append(_part(Vector3(1.87, 0.42, 0.82), Vector3(0, 1.07, z), glass))   # side windows
	_part(Vector3(1.86, 0.06, 1.25), Vector3(0, 0.76, -1.55), Color(0.88, 0.87, 0.83))  # hood crease
	# Front end: vertical-bar grille, round lamps in square bezels, corner indicators
	_part(Vector3(0.86, 0.36, 0.06), Vector3(0, 0.45, -2.21), dark)
	for k in 7:
		_part(Vector3(0.04, 0.34, 0.04), Vector3(-0.36 + k * 0.12, 0.45, -2.24), chrome)
	for s in [-1.0, 1.0]:
		_part(Vector3(0.34, 0.32, 0.05), Vector3(s * 0.64, 0.46, -2.22), chrome)
		_cyl(0.12, 0.04, Vector3(s * 0.64, 0.46, -2.25), Color(1.0, 0.96, 0.8), Vector3(PI * 0.5, 0, 0), 8)
		_part(Vector3(0.12, 0.12, 0.05), Vector3(s * 0.88, 0.62, -2.21), Color(1.0, 0.55, 0.1))   # indicator
		_part(Vector3(0.1, 0.34, 0.05), Vector3(s * 0.86, 0.55, 2.21), Color(0.85, 0.08, 0.05))   # taillight
		_part(Vector3(0.1, 0.12, 0.16), Vector3(s * 1.0, 0.98, -0.72), dark)                     # mirror
		_part(Vector3(0.12, 0.06, 1.7), Vector3(s * 0.98, -0.1, -0.05), dark)                     # side step
		for wz in [WHEEL_OFFSETS[0].z, WHEEL_OFFSETS[2].z]:
			_part(Vector3(0.1, 0.12, 1.05), Vector3(s * 0.97, 0.36, wz), Color(0.8, 0.79, 0.76))   # fender lip
	_part(Vector3(2.0, 0.2, 0.22), Vector3(0, 0.0, -2.28), chrome)        # front bumper
	_part(Vector3(2.0, 0.2, 0.2), Vector3(0, 0.0, 2.26), chrome)          # rear bumper
	# Spare wheel on the rear door
	_cyl(0.4, 0.26, Vector3(0, 0.55, 2.34), dark, Vector3(PI * 0.5, 0, 0), 10)
	_cyl(0.22, 0.28, Vector3(0, 0.55, 2.34), paint, Vector3(PI * 0.5, 0, 0), 6)

	var tire := CylinderMesh.new()
	tire.top_radius = WHEEL_RADIUS
	tire.bottom_radius = WHEEL_RADIUS
	tire.height = 0.32
	tire.radial_segments = 10
	tire.rings = 1
	var rim := CylinderMesh.new()
	rim.top_radius = 0.24
	rim.bottom_radius = 0.24
	rim.height = 0.34
	rim.radial_segments = 6
	rim.rings = 1
	var tire_mat := PS2.material(dark)
	var rim_mat := PS2.material(Color(0.9, 0.9, 0.88))   # white steel wheels
	for i in 4:
		var pivot := Node3D.new()
		pivot.position = WHEEL_OFFSETS[i] + Vector3(0, -REST_LENGTH, 0)
		_wheels_root.add_child(pivot)
		var spinner := Node3D.new()
		pivot.add_child(spinner)
		for pair in [[tire, tire_mat], [rim, rim_mat]]:
			var mi := MeshInstance3D.new()
			mi.mesh = pair[0]
			mi.material_override = pair[1]
			mi.rotation.z = PI * 0.5
			spinner.add_child(mi)
		_pivots.append(pivot)
		_spinners.append(spinner)

	_shadow = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.6, 5.0)
	_shadow.mesh = plane
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0, 0, 0, 0.55)
	sm.albedo_texture = PS2.blob_texture(16)
	sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_shadow.material_override = sm
	_shadow.top_level = true
	add_child(_shadow)


func _part(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = PS2.material(col)
	_jeep_body.add_child(mi)
	return mi


func _cyl(radius: float, length: float, pos: Vector3, col: Color, rot: Vector3, segments: int) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = PS2.material(col)
	_jeep_body.add_child(mi)


# --- Cockpit ------------------------------------------------------------------
# Left-hand drive. From inside, the body boxes' faces are back-face culled, so the
# glass "disappears" and only this interior shell is drawn.

const DRIVER_EYE := Vector3(-0.42, 1.2, 0.22)


func _build_cockpit() -> void:
	_cockpit = Node3D.new()
	_cockpit.visible = false
	add_child(_cockpit)
	var trim := Color(0.14, 0.14, 0.15)
	var dash := Color(0.2, 0.19, 0.18)
	var liner := Color(0.62, 0.6, 0.55)

	_ipart(Vector3(1.76, 0.2, 0.42), Vector3(0, 0.79, -0.64), dash)          # dashboard
	_ipart(Vector3(1.76, 0.03, 0.12), Vector3(0, 0.9, -0.8), trim)            # dash top / defrost strip
	_ipart(Vector3(0.46, 0.08, 0.2), Vector3(-0.42, 0.93, -0.58), trim)         # gauge hood
	_ipart(Vector3(0.36, 0.3, 0.1), Vector3(0.08, 0.72, -0.48), trim)         # centre stack
	for k in 3:
		_buttons.append(_ipart(Vector3(0.06, 0.03, 0.02), Vector3(-0.02 + k * 0.1, 0.8, -0.425), Color(0.9, 0.5, 0.15)))  # buttons
	_ipart(Vector3(0.24, 0.1, 0.02), Vector3(0.08, 0.67, -0.425), Color(0.25, 0.55, 0.45))               # radio screen
	_ipart(Vector3(0.6, 0.12, 0.3), Vector3(0.45, 0.76, -0.52), dash)          # glovebox
	_ipart(Vector3(1.8, 0.04, 1.3), Vector3(0, 1.36, -0.15), liner)            # headliner
	_ipart(Vector3(1.8, 0.1, 0.1), Vector3(0, 1.31, -0.86), trim)              # windshield header
	for sx in [-1.0, 1.0]:
		var pillar := _ipart(Vector3(0.09, 0.56, 0.09), Vector3(sx * 0.86, 1.06, -0.84), trim)  # A-pillar
		pillar.rotation.z = sx * 0.12
		_ipart(Vector3(0.05, 0.28, 1.6), Vector3(sx * 0.9, 0.8, -0.05), dash)   # door panel
		_ipart(Vector3(0.06, 0.04, 1.6), Vector3(sx * 0.9, 0.95, -0.05), trim)  # window sill
	# Rear-view mirror + prayer beads hanging from it
	_ipart(Vector3(0.03, 0.06, 0.03), Vector3(0, 1.3, -0.74), trim)
	_build_mirror(trim)
	_beads = Node3D.new()
	_beads.position = Vector3(0, 1.2, -0.73)
	_cockpit.add_child(_beads)
	for k in 7:
		var bead := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.016
		bead.mesh = bm
		bead.position = Vector3(0, -0.02 - k * 0.02, 0)
		bead.material_override = PS2.material(Color(0.1, 0.45, 0.35) if k < 6 else Color(0.85, 0.7, 0.3))
		_beads.add_child(bead)

	# Gauges
	for g in [[-0.52, true], [-0.32, false]]:
		_icyl(0.075, 0.02, Vector3(g[0], 0.87, -0.49), Color(0.08, 0.08, 0.09), Vector3(PI * 0.5, 0, 0), 10)
		_icyl(0.068, 0.022, Vector3(g[0], 0.87, -0.488), Color(0.85, 0.83, 0.78), Vector3(PI * 0.5, 0, 0), 10)
		var needle_pivot := Node3D.new()
		needle_pivot.position = Vector3(g[0], 0.87, -0.475)
		_cockpit.add_child(needle_pivot)
		var needle := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(0.008, 0.06, 0.004)
		needle.mesh = nm
		needle.position.y = 0.025
		needle.material_override = PS2.material(Color(0.9, 0.12, 0.08))
		needle_pivot.add_child(needle)
		if g[1]:
			_speedo_needle = needle_pivot
		else:
			_rpm_needle = needle_pivot

	# Steering wheel (tilted toward the driver), with hands in white thobe sleeves.
	var column := Node3D.new()
	column.position = Vector3(-0.42, 0.86, -0.34)
	column.rotation.x = deg_to_rad(-22)
	_cockpit.add_child(column)
	var col_mesh := _icyl(0.035, 0.18, Vector3(0, 0, -0.1), trim, Vector3(PI * 0.5, 0, 0), 6)
	col_mesh.reparent(column, false)
	_wheel_spin = Node3D.new()
	column.add_child(_wheel_spin)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.155
	torus.outer_radius = 0.19
	torus.rings = 14
	torus.ring_segments = 4
	rim.mesh = torus
	rim.rotation.x = PI * 0.5
	rim.material_override = PS2.material(Color(0.07, 0.07, 0.08))
	_wheel_spin.add_child(rim)
	for spoke in [[Vector3(0.3, 0.035, 0.02), Vector3(0, 0, 0)], [Vector3(0.035, 0.16, 0.02), Vector3(0, -0.08, 0)]]:
		var sp := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = spoke[0]
		sp.mesh = sb
		sp.position = spoke[1]
		sp.material_override = PS2.material(Color(0.12, 0.12, 0.13))
		_wheel_spin.add_child(sp)
	var hub := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.06
	hc.bottom_radius = 0.06
	hc.height = 0.04
	hc.radial_segments = 6
	hub.mesh = hc
	hub.rotation.x = PI * 0.5
	hub.material_override = PS2.material(Color(0.16, 0.16, 0.17))
	# Horn pad on the hub: a raised cap with a little trumpet icon that lights when honking.
	_horn_pad = Node3D.new()
	_wheel_spin.add_child(_horn_pad)
	_horn_pad.add_child(hub)
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.1, 0.075, 0.02)
	cap.mesh = cap_mesh
	cap.position = Vector3(0, 0, 0.025)
	cap.material_override = PS2.material(Color(0.1, 0.1, 0.11))
	_horn_pad.add_child(cap)
	_horn_icon_mat = PS2.material(Color(0.35, 0.3, 0.2))
	for part in [[Vector3(0.02, 0.022, 0.006), Vector3(-0.022, 0, 0.037)],    # trumpet body
			[Vector3(0.014, 0.04, 0.006), Vector3(0.0, 0, 0.037)],           # flared bell
			[Vector3(0.006, 0.05, 0.006), Vector3(0.018, 0, 0.037)]]:        # sound line
		var icon := MeshInstance3D.new()
		var ib := BoxMesh.new()
		ib.size = part[0]
		icon.mesh = ib
		icon.position = part[1]
		icon.material_override = _horn_icon_mat
		_horn_pad.add_child(icon)
	var skin := PS2.material(Color(0.72, 0.5, 0.36))
	var thobe := PS2.material(Color(0.95, 0.95, 0.93))
	# Hands follow the wheel only partly so the arms don't swing through the cabin.
	_hands = Node3D.new()
	column.add_child(_hands)
	for sx in [-1.0, 1.0]:
		var hand := Node3D.new()
		hand.position = Vector3(sx * 0.165, 0.05, 0.03)
		hand.rotation.z = sx * -0.5
		_hands.add_child(hand)
		if sx > 0.0:
			_right_hand = hand
		for part in [[Vector3(0.06, 0.085, 0.05), Vector3.ZERO, skin],
				[Vector3(0.055, 0.055, 0.16), Vector3(sx * 0.01, -0.04, 0.1), skin],
				[Vector3(0.085, 0.085, 0.2), Vector3(sx * 0.02, -0.07, 0.26), thobe]]:
			var m := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = part[0]
			m.mesh = b
			m.position = part[1]
			m.rotation.x = 0.35
			m.material_override = part[2]
			hand.add_child(m)

	_build_cabin(trim, dash, liner)
	windshield = Windshield.new()
	_cockpit.add_child(windshield)

	cockpit_camera = Camera3D.new()
	cockpit_camera.position = DRIVER_EYE
	cockpit_camera.rotation.x = deg_to_rad(-6)
	cockpit_camera.fov = 72.0
	cockpit_camera.near = 0.04
	cockpit_camera.far = 5000.0
	add_child(cockpit_camera)


## Honk: the right hand slides from the rim to the middle of the wheel and thumps the horn pad,
## which sinks a little and lights its horn icon; it goes back to the rim when you let go.
func _animate_honk(delta: float) -> void:
	var honking := horn.is_honking()
	# Quick to reach for the horn, a bit slower to settle back on the rim.
	_honk = move_toward(_honk, 1.0 if honking else 0.0, delta * (9.0 if honking else 5.0))
	var t := _honk * _honk * (3.0 - 2.0 * _honk)          # smoothstep
	# Rim pose (from _build_cockpit) -> palm flat on the pad, pushing in toward the wheel.
	var push := 0.012 if honking and _honk > 0.95 else 0.0
	var rim_pos := Vector3(0.165, 0.05, 0.03)
	var pad_pos := Vector3(0.03, -0.005, 0.07 - push)
	_right_hand.position = rim_pos.lerp(pad_pos, t) + Vector3(0, 0.03 * sin(t * PI), 0.04 * sin(t * PI))
	_right_hand.rotation.z = lerpf(-0.5, 0.15, t)
	_right_hand.rotation.x = lerpf(0.0, 0.7, t)     # forearm angles down, out of the way
	_horn_pad.position.z = -0.012 * t if honking else -0.012 * t * 0.5
	_horn_icon_mat.set_shader_parameter("tint", Color(0.35, 0.3, 0.2).lerp(Color(1.0, 0.75, 0.2), t))


## Desert dust settles on the windows while driving on sand: a little all the time, a lot
## while sliding (your own tyres throw it up) or blasting the rockets near the ground.
## X wipes it off. Runs in every view so the glass is dusty when you climb back in.
const DUST_CRUISE := 0.006       # per second at ~70 km/h on the sand
const DUST_SLIDE := 0.06         # per second while drifting / handbraking
const DUST_ROCKET := 0.05        # per second firing the rockets close to the ground


func _update_glass(delta: float) -> void:
	if input_enabled and Input.is_action_just_pressed("wipe"):
		windshield.wipe()
	var gp := global_position
	var grounded: bool = wheel_contact[2] or wheel_contact[3]
	var in_pond := Vector2(gp.x, gp.z).distance_to(Terrain.OASIS) < Terrain.POND_R + 4.0
	var rate := 0.0
	if grounded and not in_pond:
		rate += DUST_CRUISE * clampf(speed_kmh / 70.0, 0.0, 1.5)
		if is_drifting or (handbrake and speed_kmh > 15.0):
			rate += DUST_SLIDE
	if rocket.firing and terrain and gp.y - terrain.height_at(gp.x, gp.z) < 4.0 and not in_pond:
		rate += DUST_ROCKET
	windshield.tick(delta, rate, _cockpit.visible)


## Idle fidgets for the in-car view. Runs after _animate_honk (which puts the hand on the rim
## or the horn pad) and, while a fidget plays, takes the right hand off the wheel instead.
func _animate_fidget(delta: float) -> void:
	var busy := horn.is_honking() or _honk > 0.01 or absf(_steer) > 0.25 or is_drifting or not input_enabled
	if _fidget == "":
		_fidget_wait -= delta
		if _fidget_wait <= 0.0 and not busy:
			var choices := FIDGETS.filter(func(x): return x != _fidget_last)
			_fidget = choices[randi() % choices.size()]
			_fidget_last = _fidget
			_fidget_t = 0.0
			_fidget_len = {"gear": 1.6, "buttons": 1.4, "mirror": 1.8, "beads": 1.3}[_fidget]
			_fidget_btn = randi() % 3
		elif _fidget_wait <= 0.0:
			_fidget_wait = 1.0                       # busy: try again shortly
		return
	_fidget_t += delta
	# Cut the fidget short (hand back to the wheel) if the player needs it.
	if busy and _fidget_t < _fidget_len - FIDGET_REACH:
		_fidget_t = _fidget_len - FIDGET_REACH
	var t := _fidget_t
	var hold := t - FIDGET_REACH                      # time spent at the target
	var act_len := _fidget_len - 2.0 * FIDGET_REACH
	var reach := smoothstep(0.0, FIDGET_REACH, t) * (1.0 - smoothstep(_fidget_len - FIDGET_REACH, _fidget_len, t))
	var target := Vector3.ZERO                        # cockpit-local point for the palm
	var press := 0.0
	match _fidget:
		"gear":
			# One shift: knock the stick forward into the next gear.
			var k := clampf(hold / act_len, 0.0, 1.0)
			var throw := -0.32 if k > 0.3 else 0.0
			_gear_stick.rotation.x = lerp_angle(_gear_stick.rotation.x, throw * reach, 1.0 - exp(-18.0 * delta))
			target = _gear_stick.position + _gear_stick.basis * Vector3(0, 0.2, 0) + Vector3(0, 0.02, 0.03)
		"buttons":
			# One press of one button.
			var k := clampf(hold / act_len, 0.0, 1.0)
			var which: int = _fidget_btn
			var b := _buttons[which]
			press = smoothstep(0.25, 0.4, k) * (1.0 - smoothstep(0.65, 0.8, k)) * reach
			target = b.position + Vector3(0, 0.01, 0.05 - 0.035 * press)
			for i in _buttons.size():
				var lit := press if i == which else 0.0
				_buttons[i].position.z = -0.425 - 0.008 * lit
				(_buttons[i].material_override as ShaderMaterial).set_shader_parameter("tint",
						Color(0.9, 0.5, 0.15).lerp(Color(1.0, 0.95, 0.6), lit))
		"mirror":
			var k := clampf(hold / act_len, 0.0, 1.0)
			# One adjustment: nudge it over and settle it back (a single smooth push).
			var wiggle := sin(k * PI) * 0.06 * reach
			_mirror.basis = _mirror_base.rotated(Vector3.UP, wiggle).rotated(Vector3.RIGHT, wiggle * 0.4)
			target = MIRROR_POS + Vector3(0.1, -0.02, 0.06)
		"beads":
			target = _beads.position + Vector3(0.04, -0.08, 0.06)
			if hold > 0.0 and hold < delta * 1.5:
				_bead_swing = 0.7                         # flick!
	# Blend the hand from wherever _animate_honk left it (on the rim) to the target.
	var target_local := _hands.to_local(_cockpit.to_global(target))
	_right_hand.position = _right_hand.position.lerp(target_local, reach)
	_right_hand.rotation.z = lerpf(_right_hand.rotation.z, 0.2, reach)
	_right_hand.rotation.x = lerpf(_right_hand.rotation.x, 0.9, reach)
	if _fidget_t >= _fidget_len:
		_fidget = ""
		_fidget_wait = randf_range(FIDGET_GAP.x, FIDGET_GAP.y)
		_gear_stick.rotation.x = 0.0
		_mirror.basis = _mirror_base


## Rear-view mirror: housing + glass, angled toward the driver. The glass shows a SubViewport
## rendered by a camera placed where the driver's line of sight bounces off the mirror.
func _build_mirror(trim: Color) -> void:
	_mirror = Node3D.new()
	_mirror.position = MIRROR_POS
	# Angle it like a real mirror: its normal bisects "toward the driver's eye" and "out the
	# rear window", so the driver's line of sight bounces straight back through the car.
	var to_eye := (DRIVER_EYE - MIRROR_POS).normalized()
	var to_back := Vector3(0, 0.03, 1).normalized()
	var n := (to_eye + to_back).normalized()
	_mirror.basis = Basis.looking_at(-n, Vector3.UP)      # looking_at points -Z at the target: +Z = n
	_mirror_base = _mirror.basis
	_cockpit.add_child(_mirror)
	var housing := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.27, 0.075, 0.03)
	housing.mesh = hb
	housing.position.z = -0.016
	housing.material_override = PS2.material(trim)
	_mirror.add_child(housing)
	# Low-res, like everything else on a PS2.
	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(176, 40)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mirror_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_mirror_vp)
	_mirror_cam = Camera3D.new()
	_mirror_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_mirror_cam.fov = 17.0
	_mirror_cam.near = 0.05
	_mirror_cam.far = 3000.0
	_mirror_cam.cull_mask = 0xFFFFF & ~MIRROR_HIDDEN_LAYER
	_mirror_vp.add_child(_mirror_cam)
	var glass := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = MIRROR_SIZE
	glass.mesh = q
	glass.position.z = 0.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _mirror_vp.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_color = Color(0.92, 0.95, 1.0)     # a touch of cool mirror tint
	# Mirror image: flip left-right.
	m.uv1_scale = Vector3(-1, 1, 1)
	m.uv1_offset = Vector3(1, 0, 0)
	glass.material_override = m
	_mirror.add_child(glass)


## Aim the mirror camera: reflect the driver's view ray off the mirror plane.
func _update_mirror() -> void:
	var live := _cockpit.visible
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	if not live:
		return
	var mx := _mirror.global_transform
	var n := mx.basis.z.normalized()                       # glass normal, toward the driver
	var eye := cockpit_camera.global_position
	var incoming := (mx.origin - eye).normalized()
	var out := incoming - 2.0 * incoming.dot(n) * n         # bounce off the glass
	var up := global_transform.basis.y
	_mirror_cam.global_transform = Transform3D(Basis.looking_at(out, up), mx.origin - n * 0.02)


## The rest of the cabin around the driver: floor, seats, console, full-length doors,
## pillars, headliner and rear shelf, so looking around from inside shows a whole car.
func _build_cabin(trim: Color, dash: Color, liner: Color) -> void:
	var carpet := Color(0.16, 0.13, 0.11)
	var seat := Color(0.36, 0.27, 0.2)
	var seat_insert := Color(0.46, 0.36, 0.26)
	var chrome := Color(0.7, 0.72, 0.75)
	# Floor, footwell wall under the dash, transmission tunnel
	_ipart(Vector3(1.76, 0.04, 2.95), Vector3(0, 0.44, 0.62), carpet)
	_ipart(Vector3(1.76, 0.3, 0.05), Vector3(0, 0.6, -0.84), dash)
	_ipart(Vector3(0.3, 0.12, 2.4), Vector3(0, 0.5, 0.6), carpet.darkened(0.15))
	# Front seats: cushion, reclined backrest with a fabric insert, headrest on posts
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.42
		_ipart(Vector3(0.52, 0.14, 0.52), Vector3(x, 0.58, 0.4), seat)
		_ipart(Vector3(0.34, 0.02, 0.4), Vector3(x, 0.655, 0.4), seat_insert)
		var back := _ipart(Vector3(0.52, 0.6, 0.12), Vector3(x, 0.94, 0.76), seat)
		back.rotation.x = 0.13
		var insert := _ipart(Vector3(0.34, 0.44, 0.02), Vector3(x, 0.93, 0.695), seat_insert)
		insert.rotation.x = 0.13
		var headrest := _ipart(Vector3(0.28, 0.16, 0.1), Vector3(x, 1.34, 0.84), seat)
		var posts: Array[MeshInstance3D] = []
		for px in [-0.08, 0.08]:
			posts.append(_ipart(Vector3(0.015, 0.08, 0.015), Vector3(x + px, 1.24, 0.83), chrome))
		# The front seat backs sit right in the mirror's line of sight in this compact cabin;
		# keep them out of the mirror so it shows the rear window (see MIRROR_HIDDEN_LAYER).
		for mi in [back, insert, headrest] + posts:
			mi.layers = MIRROR_HIDDEN_LAYER
		_ipart(Vector3(0.56, 0.06, 0.56), Vector3(x, 0.49, 0.4), trim)   # seat base
	# Centre console: gear lever with a wooden knob, handbrake, cup holders
	_ipart(Vector3(0.22, 0.2, 0.62), Vector3(0, 0.56, 0.12), trim)
	# Gear stick on a pivot at its base so the driver can knock it through the gears.
	_gear_stick = Node3D.new()
	_gear_stick.position = Vector3(0, 0.65, -0.04)
	_cockpit.add_child(_gear_stick)
	_ipart(Vector3(0.03, 0.18, 0.03), Vector3(0, 0.09, 0), trim).reparent(_gear_stick, false)
	_gear_knob = _ipart(Vector3(0.06, 0.06, 0.06), Vector3(0, 0.19, 0), Color(0.4, 0.24, 0.12))
	_gear_knob.reparent(_gear_stick, false)
	var hb := _ipart(Vector3(0.04, 0.04, 0.28), Vector3(0.05, 0.7, 0.3), trim)
	hb.rotation.x = -0.35
	for cz in [0.18, 0.3]:
		_icyl(0.035, 0.02, Vector3(-0.05, 0.665, cz), Color(0.05, 0.05, 0.05), Vector3.ZERO, 8)
	# Rear bench seat with two headrests and a folding armrest
	_ipart(Vector3(1.62, 0.16, 0.55), Vector3(0, 0.58, 1.55), seat)
	_ipart(Vector3(1.4, 0.02, 0.45), Vector3(0, 0.665, 1.55), seat_insert)
	# Lower backrest so the rear window (and the rear-view mirror's view through it) stays open.
	var rback := _ipart(Vector3(1.62, 0.44, 0.14), Vector3(0, 0.87, 1.92), seat)
	rback.rotation.x = 0.16
	for x in [-0.48, 0.48]:
		_ipart(Vector3(0.38, 0.3, 0.02), Vector3(x, 0.87, 1.85), seat_insert).rotation.x = 0.16
		_ipart(Vector3(0.24, 0.11, 0.08), Vector3(x, 1.15, 1.98), seat)
	_ipart(Vector3(0.2, 0.1, 0.4), Vector3(0, 0.72, 1.7), seat_insert)
	# Doors along the whole cabin: lower panel, rear-door upper panel and sill, armrests,
	# chrome handles, speaker grilles
	for sx in [-1.0, 1.0]:
		var dx: float = sx * 0.9
		_ipart(Vector3(0.05, 0.34, 2.9), Vector3(dx, 0.5, 0.6), dash.darkened(0.1))
		_ipart(Vector3(0.05, 0.28, 1.2), Vector3(dx, 0.8, 1.4), dash)
		_ipart(Vector3(0.06, 0.04, 1.2), Vector3(dx, 0.95, 1.4), trim)
		_ipart(Vector3(0.02, 0.02, 2.95), Vector3(dx - sx * 0.03, 0.66, 0.62), trim)   # door seam strip
		for az in [0.12, 1.4]:
			_ipart(Vector3(0.09, 0.05, 0.42), Vector3(sx * 0.85, 0.85, az), seat)
			_ipart(Vector3(0.02, 0.03, 0.1), Vector3(sx * 0.87, 0.9, az - 0.32), chrome)
		for sz in [-0.45, 1.15]:
			_icyl(0.07, 0.02, Vector3(sx * 0.87, 0.52, sz), Color(0.06, 0.06, 0.06), Vector3(0, 0, PI * 0.5), 8)
		# B-pillar, C-pillar and roof rail framing the side windows
		_ipart(Vector3(0.09, 0.42, 0.12), Vector3(sx * 0.88, 1.14, 0.78), trim)
		_ipart(Vector3(0.09, 0.42, 0.26), Vector3(sx * 0.87, 1.14, 2.0), trim)
		_ipart(Vector3(0.07, 0.06, 2.95), Vector3(sx * 0.88, 1.33, 0.62), trim)
		# Sun visors
		var visor := _ipart(Vector3(0.42, 0.02, 0.18), Vector3(sx * 0.42, 1.32, -0.72), liner.darkened(0.08))
		visor.rotation.x = 0.15
	# Headliner over the back seats, dome light, rear window frame, parcel shelf
	_ipart(Vector3(1.8, 0.04, 1.6), Vector3(0, 1.36, 1.3), liner)
	_ipart(Vector3(0.16, 0.02, 0.08), Vector3(0, 1.335, 0.55), Color(0.95, 0.88, 0.7))
	_ipart(Vector3(1.8, 0.08, 0.08), Vector3(0, 1.32, 2.12), trim)
	_ipart(Vector3(1.72, 0.04, 0.32), Vector3(0, 0.95, 2.14), trim)
	_ipart(Vector3(1.76, 0.52, 0.05), Vector3(0, 0.7, 2.28), dash)
	# A box of tissues on the rear shelf (every desert road trip has one)
	_ipart(Vector3(0.22, 0.09, 0.12), Vector3(0.45, 1.015, 2.12), Color(0.92, 0.9, 0.86))
	_ipart(Vector3(0.1, 0.03, 0.06), Vector3(0.45, 1.07, 2.12), Color(0.98, 0.98, 0.98))


func _update_cockpit(delta: float) -> void:
	_wheel_spin.rotation.z = _steer * 2.0
	_hands.rotation.z = _steer * 0.6
	_animate_honk(delta)
	_animate_fidget(delta)
	_speedo_needle.rotation.z = deg_to_rad(120.0) - clampf(speed_kmh / 200.0, 0.0, 1.0) * deg_to_rad(240.0)
	var rpm := clampf(0.15 + fmod(absf(_wheel_spin_speed[2]) * 0.012, 0.85), 0.0, 1.0)
	_rpm_needle.rotation.z = lerp_angle(_rpm_needle.rotation.z, deg_to_rad(120.0) - rpm * deg_to_rad(240.0), 1.0 - exp(-10.0 * delta))
	# Beads swing with sideways acceleration.
	var lat := (global_transform.basis.transposed() * linear_velocity).x
	var accel := (lat - _lat_vel_prev) / maxf(delta, 0.001)
	_lat_vel_prev = lat
	_bead_swing = lerpf(_bead_swing, clampf(accel * 0.04, -0.7, 0.7), 1.0 - exp(-5.0 * delta))
	_beads.rotation.z = _bead_swing
	# Look slightly into the slide, like a driver checking where they're going.
	# Arrow keys look around the cabin.
	_look_yaw = clampf(_look_yaw + Input.get_axis("cam_right", "cam_left") * 1.8 * delta, -1.9, 1.9)
	_look_pitch = clampf(_look_pitch + Input.get_axis("cam_down", "cam_up") * 1.2 * delta, -0.5, 0.6)
	cockpit_camera.rotation.y = lerp_angle(cockpit_camera.rotation.y, body_slip * 0.45 + _look_yaw, 1.0 - exp(-6.0 * delta))
	cockpit_camera.rotation.x = deg_to_rad(-6) + _look_pitch
	# +/- zooms the driver's view (narrower FOV = zoomed in).
	_cockpit_fov = clampf(_cockpit_fov + Input.get_axis("zoom_in", "zoom_out") * 35.0 * delta, 15.0, 110.0)
	cockpit_camera.fov = lerpf(cockpit_camera.fov, _cockpit_fov, 1.0 - exp(-10.0 * delta))


## Two-finger swipe look-around in the cockpit (radians), same limits as the arrow keys.
func add_look(d_yaw: float, d_pitch: float) -> void:
	_look_yaw = clampf(_look_yaw + d_yaw, -1.9, 1.9)
	_look_pitch = clampf(_look_pitch + d_pitch, -0.5, 0.6)


func _ipart(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = PS2.material(col)
	_cockpit.add_child(mi)
	return mi


func _icyl(radius: float, length: float, pos: Vector3, col: Color, rot: Vector3, segments: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = PS2.material(col)
	_cockpit.add_child(mi)
	return mi


# --- Underglow -------------------------------------------------------------------

func _build_underglow(size: Vector3) -> void:
	if _glow == null:
		_glow = MeshInstance3D.new()
		_glow.top_level = true
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow_mat.albedo_texture = PS2.smoke_texture(32)
		_glow_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_glow.material_override = _glow_mat
		add_child(_glow)
		_led_mat = StandardMaterial3D.new()
		_led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_led_root = Node3D.new()
		add_child(_led_root)
	for child in _led_root.get_children():
		child.queue_free()
	_glow_kind = CarModels.LIST[model_index].get("glow")
	_glow.visible = _glow_kind != null
	if _glow_kind == null:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x + 2.8, size.z + 2.6)
	_glow.mesh = plane
	# LED strips hidden under the floor pan: flat, downward-facing strips set in from the
	# body edges, so only the glow on the ground shows from outside. (Back-face culling
	# hides them from above; they're only seen if the camera is under the car.)
	var y := CarModels.GROUND_Y + 0.42
	var sx := size.x * 0.5 - 0.4
	var sz := size.z * 0.5 - 0.75
	var strips := [
		[Vector2(0.06, sz * 2.0), Vector3(-sx, y, 0)],
		[Vector2(0.06, sz * 2.0), Vector3(sx, y, 0)],
		[Vector2(sx * 2.0, 0.06), Vector3(0, y, -sz)],
		[Vector2(sx * 2.0, 0.06), Vector3(0, y, sz)],
	]
	for st in strips:
		var mi := MeshInstance3D.new()
		var p := PlaneMesh.new()
		p.size = st[0]
		p.orientation = PlaneMesh.FACE_Y
		p.flip_faces = true        # face the ground
		mi.mesh = p
		mi.position = st[1]
		mi.material_override = _led_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_led_root.add_child(mi)
