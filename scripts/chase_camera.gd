## Smoothed chase cam. Follows a blend of the car's heading and its velocity,
## so it swings out and shows the drift angle while sliding.
extends Camera3D

var target: RigidBody3D
var terrain: Node3D
var distance := 7.5
var height := 2.9
var _dir := Vector3.FORWARD
# Arrow-key orbit around the car (persists until changed).
var orbit_yaw := 0.0
var orbit_pitch := 0.0
const ORBIT_SPEED := 1.8
# +/- zoom: scales the chase distance and height (smaller = closer to the car).
var zoom := 1.0
var _zoom_smooth := 1.0
const ZOOM_MIN := 0.25   # ~2 m: right behind the bumper
const ZOOM_MAX := 5.0    # ~40 m: wide aerial-ish view
const ZOOM_SPEED := 1.2


func _ready() -> void:
	fov = 68.0
	near = 0.1
	far = 5000.0
	if target:
		_dir = -target.global_transform.basis.z
		global_position = target.global_position - _dir * distance + Vector3.UP * height


## Two-finger swipe orbit (radians), same limits as the arrow keys.
func add_orbit(d_yaw: float, d_pitch: float) -> void:
	orbit_yaw = wrapf(orbit_yaw + d_yaw, -PI, PI)
	orbit_pitch = clampf(orbit_pitch + d_pitch, -0.3, 1.1)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var fwd := -target.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var v := target.linear_velocity
	v.y = 0.0
	var dir := fwd
	if v.length() > 4.0 and v.normalized().dot(fwd) > -0.2:
		dir = fwd.lerp(v.normalized(), 0.55).normalized()
	_dir = _dir.lerp(dir, 1.0 - exp(-4.0 * delta)).normalized()

	orbit_yaw = wrapf(orbit_yaw + Input.get_axis("cam_right", "cam_left") * ORBIT_SPEED * delta, -PI, PI)
	orbit_pitch = clampf(orbit_pitch + Input.get_axis("cam_down", "cam_up") * ORBIT_SPEED * 0.6 * delta, -0.3, 1.1)
	# Hold + to zoom in, - to zoom out (exponential so it feels even at every range).
	zoom = clampf(zoom * exp(Input.get_axis("zoom_in", "zoom_out") * ZOOM_SPEED * delta), ZOOM_MIN, ZOOM_MAX)
	_zoom_smooth = lerpf(_zoom_smooth, zoom, 1.0 - exp(-10.0 * delta))
	var view_dir := _dir.rotated(Vector3.UP, orbit_yaw)
	var elev := atan2(height, distance) + orbit_pitch
	var radius := Vector2(distance, height).length() * _zoom_smooth
	var desired := target.global_position + (-view_dir * cos(elev) + Vector3.UP * sin(elev)) * radius
	var pos := global_position.lerp(desired, 1.0 - exp(-8.0 * delta))
	if terrain:
		pos.y = maxf(pos.y, terrain.height_at(pos.x, pos.z) + 1.4)
	# Keep line of sight: if a dune hides the car, raise the camera until it can see it.
	var space := get_world_3d().direct_space_state
	var look_from := target.global_position + Vector3.UP * 0.3
	for _i in 8:
		var q := PhysicsRayQueryParameters3D.create(look_from, pos)
		q.exclude = [target.get_rid()]
		q.collision_mask = 1      # ignore loose props rolling around
		if space.intersect_ray(q).is_empty():
			break
		pos.y += 1.0
	global_position = pos
	look_at(target.global_position + Vector3.UP * 1.2 + view_dir * 2.0 * cos(elev), Vector3.UP)

	var speed := target.linear_velocity.length()
	fov = lerpf(fov, 68.0 + clampf(speed / 50.0, 0.0, 1.0) * 14.0, 1.0 - exp(-3.0 * delta))
