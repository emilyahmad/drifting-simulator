## Riyadh Desert Drift: builds the world, car, cameras, menu/HUD and PS2 post-process,
## and runs the menu -> play state plus drift scoring.
extends Node3D

const Terrain := preload("res://scripts/terrain.gd")
const Skyline := preload("res://scripts/skyline.gd")
const Landmarks := preload("res://scripts/landmarks.gd")
const Creatures := preload("res://scripts/creatures.gd")
const Car := preload("res://scripts/car.gd")
const CarModels := preload("res://scripts/car_models.gd")
const DriftFx := preload("res://scripts/drift_fx.gd")
const ChaseCam := preload("res://scripts/chase_camera.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Menu := preload("res://scripts/ui/menu.gd")
const POST_SHADER := preload("res://shaders/ps2_post.gdshader")
const SAVE_PATH := "user://riyadh_drift.cfg"
const SPAWN := Vector3(0, 0, 0)
const LANDMARKS := [
	{"id": "oasis", "name": "THE HIDDEN OASIS", "ar": "الواحة المخفية", "pos": Terrain.OASIS, "r": 55.0},
	{"id": "ruins", "name": "NAJDI RUINS", "ar": "الأطلال النجدية", "pos": Terrain.RUINS, "r": 55.0},
	{"id": "pillars", "name": "LOST CITY OF PILLARS", "ar": "مدينة الأعمدة المفقودة", "pos": Terrain.COLONNADE, "r": 75.0},
	{"id": "temple", "name": "TEMPLE OF COLUMNS", "ar": "معبد الأعمدة", "pos": Terrain.TEMPLE, "r": 35.0},
	{"id": "arch", "name": "THE LONE ARCH", "ar": "القوس الوحيد", "pos": Terrain.LONE_ARCH, "r": 32.0},
	{"id": "gate", "name": "THE SCALLOPED GATE", "ar": "البوابة المزخرفة", "pos": Terrain.SCALLOP_GATE, "r": 32.0},
	{"id": "chapel", "name": "THE SANDSTONE CHAPEL", "ar": "كنيسة الصخر الرملي", "pos": Terrain.CHAPEL, "r": 55.0},
]

enum State { MENU, PLAYING, CINEMATIC }

const CINE_TIME := 6.0         # drone shot length (s)
const CINE_BLEND := 1.2        # blend-in from the player camera (s)
const CINE_SWEEP := deg_to_rad(200.0)

var terrain
var car
var chase_cam: Camera3D
var menu_cam: Camera3D
var hud
var menu
var state := State.MENU
var _in_cockpit := false
var _orbit := 0.0
# Scoring
var score := 0
var best := 0
var total := 0
var _live := 0.0
var _grace := 0.0
var _saved_model := 0
var discovered := {}      # landmark id -> true (saved)
var _inside := {}         # landmark id -> currently inside its area
# Discovery drone shot
var _cine_t := 0.0
var _cine_centre := Vector3.ZERO
var _cine_radius := 40.0
var _cine_a0 := 0.0
var _cine_dir := 1.0
var _cine_from := Transform3D()


func _ready() -> void:
	_setup_input()
	_setup_environment()
	_load_save()

	terrain = Terrain.new()
	add_child(terrain)
	add_child(Skyline.new())
	var landmarks = Landmarks.new()
	landmarks.terrain = terrain
	add_child(landmarks)

	car = Car.new()
	car.model_index = clampi(_saved_model, 0, CarModels.LIST.size() - 1)
	add_child(car)
	car.global_position = SPAWN + Vector3(0, terrain.height_at(SPAWN.x, SPAWN.z) + 1.2, 0)

	var creatures = Creatures.new()
	creatures.terrain = terrain
	creatures.car = car
	add_child(creatures)

	var fx = DriftFx.new()
	fx.car = car
	add_child(fx)

	chase_cam = ChaseCam.new()
	chase_cam.target = car
	chase_cam.terrain = terrain
	add_child(chase_cam)

	menu_cam = Camera3D.new()
	menu_cam.fov = 55.0
	menu_cam.far = 5000.0
	menu_cam.h_offset = -2.4     # car sits on the right, menu on the left
	menu_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(menu_cam)

	_setup_ui()
	_enter_menu(false)


# --- State -------------------------------------------------------------------

func _enter_menu(paused: bool) -> void:
	state = State.MENU
	car.input_enabled = false
	car.set_cockpit_view(false)
	hud.visible = false
	menu.best = best
	menu.total = total
	menu.found = discovered.size()
	menu.found_max = LANDMARKS.size()
	menu.car_index = car.model_index
	menu.camera_name = "COCKPIT" if _in_cockpit else "CHASE"
	menu.open(paused)
	menu_cam.h_offset = -2.4
	menu_cam.fov = 55.0
	menu_cam.make_current()


func _start_playing() -> void:
	state = State.PLAYING
	menu.visible = false
	hud.visible = true
	hud.show_hints()
	car.input_enabled = true
	_apply_view()


func _apply_view() -> void:
	car.set_cockpit_view(_in_cockpit)
	if not _in_cockpit:
		chase_cam.make_current()


func toggle_view() -> void:
	_in_cockpit = not _in_cockpit
	menu.camera_name = "COCKPIT" if _in_cockpit else "CHASE"
	if state == State.PLAYING:
		_apply_view()


func _on_menu_chosen(id: String) -> void:
	match id:
		"start", "resume":
			_start_playing()
		"restart":
			score = 0
			_live = 0.0
			car.request_reset(SPAWN + Vector3(0, terrain.height_at(SPAWN.x, SPAWN.z) + 1.2, 0))
			_start_playing()
		"car_next", "car_prev":
			var n: int = CarModels.LIST.size()
			car.set_model(wrapi(car.model_index + (1 if id == "car_next" else -1), 0, n))
			menu.car_index = car.model_index
			_save()
		"camera":
			toggle_view()
		"quit":
			get_tree().quit()


# --- Loop --------------------------------------------------------------------

func _process(delta: float) -> void:
	if state == State.MENU:
		_orbit += delta * 0.25
		var c: Vector3 = car.global_position
		menu_cam.global_position = c + Vector3(sin(_orbit) * 7.5, 1.6, cos(_orbit) * 7.5)
		menu_cam.look_at(c + Vector3.UP * 0.4, Vector3.UP)
	elif state == State.CINEMATIC:
		_update_cinematic(delta)
	else:
		hud.score = score
		hud.live = _live
		hud.speed = car.speed_kmh
		hud.angle = absf(rad_to_deg(car.body_slip))
		hud.drifting = car.is_drifting
		var fwd: float = -(car.global_transform.basis.transposed() * car.linear_velocity).z
		_check_landmarks()
		hud.gear = "R" if fwd < -0.5 else ("D" if fwd > 0.5 or Input.is_action_pressed("throttle") else "N")
	if car.global_position.y < -40.0:
		_reset_car()


## Points flow in while drifting (angle x speed); a drift banks after a short grace period.
func _physics_process(delta: float) -> void:
	if state != State.PLAYING:
		return
	if car.is_drifting:
		_live += absf(rad_to_deg(car.body_slip)) * car.speed_kmh * 0.05 * delta
		_grace = 0.7
	elif _live > 0.0:
		_grace -= delta
		if _grace <= 0.0:
			var pts := int(_live)
			score += pts
			total += pts
			best = maxi(best, pts)
			hud.flash = pts
			hud.flash_t = 2.0
			_live = 0.0
			_save()


## Banner the first time the player reaches a landmark; a smaller name toast on later visits.
func _check_landmarks() -> void:
	var p := Vector2(car.global_position.x, car.global_position.z)
	for lm in LANDMARKS:
		var d := p.distance_to(lm["pos"])
		var was: bool = _inside.get(lm["id"], false)
		if not was and d < lm["r"]:
			_inside[lm["id"]] = true
			var is_new: bool = not discovered.has(lm["id"])
			if is_new:
				discovered[lm["id"]] = true
				_save()
			hud.discover(lm["name"], lm["ar"], is_new)
			if is_new:
				_start_cinematic(lm)
				return
		elif was and d > lm["r"] + 20.0:
			_inside[lm["id"]] = false


# --- Discovery drone shot ------------------------------------------------------

## Blend from the player's camera into an orbit around the landmark, rising and pushing in.
func _start_cinematic(lm: Dictionary) -> void:
	state = State.CINEMATIC
	car.input_enabled = false     # car brakes to a stop while the shot plays
	var cur := get_viewport().get_camera_3d()
	_cine_from = cur.global_transform
	var c: Vector2 = lm["pos"]
	_cine_centre = Vector3(c.x, terrain.height_at(c.x, c.y), c.y)
	_cine_radius = clampf(lm["r"] * 0.9, 30.0, 70.0)
	var rel := _cine_from.origin - _cine_centre
	_cine_a0 = atan2(rel.z, rel.x)
	_cine_dir = 1.0 if randf() < 0.5 else -1.0
	_cine_t = 0.0
	menu_cam.h_offset = 0.0
	menu_cam.fov = 60.0
	car.set_cockpit_view(false)
	menu_cam.global_transform = _cine_from
	menu_cam.make_current()
	hud.cinematic = true


func _update_cinematic(delta: float) -> void:
	_cine_t += delta
	var k := clampf(_cine_t / CINE_TIME, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)      # ease in/out
	var a := _cine_a0 + _cine_dir * CINE_SWEEP * e
	var r := lerpf(_cine_radius * 1.15, _cine_radius * 0.8, e)
	var pos := _cine_centre + Vector3(cos(a) * r, lerpf(7.0, 20.0, e), sin(a) * r)
	pos.y = maxf(pos.y, terrain.height_at(pos.x, pos.z) + 3.0)
	var orbit := Transform3D(Basis.IDENTITY, pos).looking_at(_cine_centre + Vector3.UP * 4.0, Vector3.UP)
	var blend := smoothstep(0.0, CINE_BLEND, _cine_t)
	menu_cam.global_transform = _cine_from.interpolate_with(orbit, blend)
	if _cine_t >= CINE_TIME:
		_end_cinematic()


func _end_cinematic() -> void:
	hud.cinematic = false
	state = State.PLAYING
	car.input_enabled = true
	_apply_view()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.CINEMATIC:
		if event.is_action_pressed("handbrake") or event.is_action_pressed("ui_accept") or event.is_action_pressed("quit"):
			_end_cinematic()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_view"):
		toggle_view()
	elif state == State.PLAYING and event.is_action_pressed("reset_car"):
		_live = 0.0
		_reset_car()
	elif event.is_action_pressed("quit"):
		if state == State.PLAYING:
			_enter_menu(true)
		elif menu.paused:
			_start_playing()


func _reset_car() -> void:
	var p: Vector3 = car.global_position
	var lim := Terrain.HALF - 30.0
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)
	p.y = terrain.height_at(p.x, p.z) + 1.5
	car.request_reset(p)


# --- Save --------------------------------------------------------------------

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = cfg.get_value("score", "best", 0)
		total = cfg.get_value("score", "total", 0)
		_saved_model = cfg.get_value("car", "model", 0)
		for id in cfg.get_value("explore", "discovered", []):
			discovered[id] = true


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best)
	cfg.set_value("score", "total", total)
	cfg.set_value("car", "model", car.model_index)
	cfg.set_value("explore", "discovered", discovered.keys())
	cfg.save(SAVE_PATH)


# --- Setup -------------------------------------------------------------------

func _setup_input() -> void:
	var map := {
		"throttle": [KEY_W],
		"brake": [KEY_S],
		"steer_left": [KEY_A],
		"steer_right": [KEY_D],
		"cam_left": [KEY_LEFT],
		"cam_right": [KEY_RIGHT],
		"cam_up": [KEY_UP],
		"cam_down": [KEY_DOWN],
		"handbrake": [KEY_SPACE],
		"reset_car": [KEY_R],
		"toggle_view": [KEY_C],
		"quit": [KEY_ESCAPE],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in map[action]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)


func _setup_environment() -> void:
	# Sunset: dusky purple overhead fading to orange-red at the horizon.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.17, 0.36)
	sky_mat.sky_horizon_color = Color(1.0, 0.5, 0.3)
	sky_mat.sky_curve = 0.22
	sky_mat.ground_horizon_color = Color(0.95, 0.52, 0.34)
	sky_mat.ground_bottom_color = Color(0.4, 0.2, 0.16)
	sky_mat.sun_angle_max = 16.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.42, 0.46)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.95, 0.6, 0.42)
	env.fog_density = 1.0
	env.fog_depth_begin = 0.0
	env.fog_depth_end = 2100.0
	env.fog_depth_curve = 0.85
	env.fog_sun_scatter = 0.35          # dust glows toward the sun
	env.fog_height = 3.0                # extra dust hugging the ground
	env.fog_height_density = 0.022
	# Thick volumetric dust: hazes nearby dunes and ruins, glows toward the sun.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.003
	env.volumetric_fog_albedo = Color(0.95, 0.68, 0.48)
	env.volumetric_fog_emission = Color(0.22, 0.12, 0.07)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 260.0
	env.volumetric_fog_sky_affect = 0.0
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Setting sun just above the skyline (north-west, ~9 deg up).
	var to_sun := Vector3(-0.5, 0.16, -0.85).normalized()
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.62, 0.46)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	# Sky-only light that draws a big, soft, faded-red sun disc.
	var sun_disc := DirectionalLight3D.new()
	sun_disc.light_color = Color(0.95, 0.38, 0.32)
	sun_disc.light_energy = 1.0
	sun_disc.light_angular_distance = 3.5   # big soft disc
	sun_disc.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	add_child(sun_disc)
	sun_disc.basis = sun.basis


func _setup_ui() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 50
	add_child(hud_layer)
	hud = Hud.new()
	hud_layer.add_child(hud)

	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 60
	add_child(menu_layer)
	menu = Menu.new()
	menu.chosen.connect(_on_menu_chosen)
	menu_layer.add_child(menu)

	var post_layer := CanvasLayer.new()
	post_layer.layer = 100
	add_child(post_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = POST_SHADER
	rect.material = pm
	post_layer.add_child(rect)
