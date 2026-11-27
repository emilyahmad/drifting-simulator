## Arcade drift car: RigidBody3D with raycast suspension and simple tire forces.
## Rear tires lose grip on handbrake / power-over, with assists to keep slides controllable.
extends RigidBody3D

const PS2 := preload("res://scripts/ps2.gd")
const CarModels := preload("res://scripts/car_models.gd")

# Suspension
const WHEEL_RADIUS := 0.42
const REST_LENGTH := 0.5
const SPRING := 32000.0
const DAMPER := 3200.0
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
const DRIFT_GRIP := 0.42         # rear grip multiplier while power-sliding
const HANDBRAKE_GRIP := 0.22
# Drift assists
const DRIFT_SLIP_ANGLE := 0.22   # rad of body slip that counts as drifting
const DRIFT_YAW_TORQUE := 2600.0
const COUNTERSTEER_ASSIST := 0.7
const SPIN_LIMIT := 0.95         # rad; past this a stabilizer pulls the nose back

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
var _pivots: Array[Node3D] = []
var _spinners: Array[Node3D] = []
var _shadow: MeshInstance3D
# Neon underglow (some pack cars): additive glow decal on the ground + LED strips.
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _led_root: Node3D
var _led_mat: StandardMaterial3D
var _glow_kind = null      # null, a Color, or "police"
var _glow_t := 0.0
# Cockpit (first-person) view
var cockpit_camera: Camera3D
var _cockpit: Node3D
var _wheel_spin: Node3D
var _speedo_needle: Node3D
var _rpm_needle: Node3D
var _beads: Node3D
var _hands: Node3D
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
	center_of_mass = Vector3(0, -0.35, 0.05)
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
	elif is_drifting:
		grip_target = 0.7
	var rate := 6.0 if grip_target < _rear_grip else 1.5
	_rear_grip = move_toward(_rear_grip, grip_target, delta * rate)

	var space := get_world_3d().direct_space_state
	var com := global_transform * center_of_mass
	var grounded := 0
	for i in 4:
		var origin: Vector3 = global_transform * WHEEL_OFFSETS[i]
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * (REST_LENGTH + WHEEL_RADIUS))
		q.exclude = [get_rid()]
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

		# Apply tire forces a bit above the contact patch to reduce roll-overs.
		apply_force(wf * f_long + wr * f_lat, (p + up * 0.35) - global_position)

		wheel_contact[i] = true
		wheel_point[i] = p
		wheel_normal[i] = n
		wheel_slip[i] = absf(v_lat)
		_wheel_spin_speed[i] = v_long / WHEEL_RADIUS
		if not is_front and handbrake:
			_wheel_spin_speed[i] = 0.0

	if is_drifting and grounded >= 2:
		# Steering adds yaw; steering *into* the slide fades out as the angle approaches the limit.
		var widening := steer_in * body_slip < 0.0
		var room := 1.0 - clampf(absf(body_slip) / SPIN_LIMIT, 0.0, 1.0) if widening else 1.0
		apply_torque(up * steer_in * DRIFT_YAW_TORQUE * room * clampf(speed / 15.0, 0.0, 1.0))
		# Stabilizer: pull the nose back toward the direction of travel at big angles,
		# and damp yaw rate so the car doesn't swap ends.
		var excess := smoothstep(SPIN_LIMIT * 0.6, SPIN_LIMIT * 1.3, absf(body_slip))
		apply_torque(up * body_slip * 9000.0 * excess)
		apply_torque(up * -angular_velocity.dot(up) * 2500.0 * excess)

	apply_central_force(-linear_velocity * speed * AIR_DRAG)
	_update_shadow()


func set_cockpit_view(on: bool) -> void:
	_cockpit.visible = on
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
	if _glow_kind != null:
		_glow_t += delta
		var c: Color
		if _glow_kind is String:
			c = Color(1.0, 0.1, 0.1) if fmod(_glow_t, 0.5) < 0.25 else Color(0.15, 0.3, 1.0)
		else:
			c = _glow_kind
		_led_mat.albedo_color = c
		_glow_mat.albedo_color = Color(c, 0.8 + 0.12 * sin(_glow_t * 3.0))
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
	_glow.visible = count > 0 and _glow_kind != null
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
		_ipart(Vector3(0.06, 0.03, 0.02), Vector3(-0.02 + k * 0.1, 0.8, -0.425), Color(0.9, 0.5, 0.15))  # buttons
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
	_ipart(Vector3(0.27, 0.075, 0.03), Vector3(0, 1.24, -0.73), trim)
	_ipart(Vector3(0.24, 0.055, 0.005), Vector3(0, 1.24, -0.714), Color(0.55, 0.6, 0.66))
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
	_wheel_spin.add_child(hub)
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

	cockpit_camera = Camera3D.new()
	cockpit_camera.position = DRIVER_EYE
	cockpit_camera.rotation.x = deg_to_rad(-6)
	cockpit_camera.fov = 72.0
	cockpit_camera.near = 0.04
	cockpit_camera.far = 5000.0
	add_child(cockpit_camera)


func _update_cockpit(delta: float) -> void:
	_wheel_spin.rotation.z = _steer * 2.0
	_hands.rotation.z = _steer * 0.6
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
	# LED strips tucked under the sills, bumpers.
	var y := CarModels.GROUND_Y + 0.3
	var strips := [
		[Vector3(0.06, 0.05, size.z * 0.72), Vector3(-(size.x * 0.5 - 0.15), y, 0)],
		[Vector3(0.06, 0.05, size.z * 0.72), Vector3(size.x * 0.5 - 0.15, y, 0)],
		[Vector3(size.x * 0.7, 0.05, 0.06), Vector3(0, y, -(size.z * 0.5 - 0.4))],
		[Vector3(size.x * 0.7, 0.05, 0.06), Vector3(0, y, size.z * 0.5 - 0.4)],
	]
	for st in strips:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = st[0]
		mi.mesh = b
		mi.position = st[1]
		mi.material_override = _led_mat
		_led_root.add_child(mi)
