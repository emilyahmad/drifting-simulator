## Cockpit glass: tinted windshield, door windows and rear window you see through from the
## driver's seat. Desert dust settles on all of them while you drive (faster when sliding),
## pond splashes leave water drops, and pressing the wipe key (X) cleans them: the front
## wipers and rear wiper sweep arcs through the dust while washer fluid rinses the rest, so
## the whole windshield and rear window end up clean, and a rag swipes the side windows.
## Lives under the car's cockpit node, in car-local coordinates.
extends Node3D

const WIPE_TIME := 0.75          # s for one out-and-back sweep of the wipers
const SWEEPS := 2
const RAG_TIME := 0.7            # s for the rag to cross a side window
const TEX_HZ := 15.0             # how often dust textures are re-uploaded
const DUST_ALPHA := 0.85         # opacity of fully caked glass
const DUST_COL := Color(0.8, 0.64, 0.46)
# Front wipers: pivots along the bottom of the windshield.
const FRONT_PIVOTS := [Vector3(-0.55, 0.92, -0.82), Vector3(0.05, 0.92, -0.82)]
const FRONT_ARM := 0.4
const FRONT_REST := -PI * 0.5 + 0.06    # lying flat along the bottom edge, pointing right
const FRONT_UP := 0.5                   # past upright, leaning left: a wide fan per blade
# Rear wiper: one arm pivoting at the bottom middle of the rear window.
const REAR_PIVOT := Vector3(0.0, 0.98, 2.115)
const REAR_ARM := 0.3
const REAR_REST := PI * 0.5 - 0.1       # flat, pointing left (as seen from inside)
const REAR_UP := -PI * 0.5 + 0.1        # flat, pointing right: a full half-circle sweep

var wet := 0.0                   # 0..1, uniform water drops on the windshield
var _panes: Array[Dictionary] = []      # {name, center, yaw, size, w, h, dust, noise, img, tex, mat, dirty}
var _front_arms: Array[Node3D] = []
var _rear_arm: Node3D
var _rags: Array[Node3D] = []
var _wipe_t := -1.0              # < 0 = wipers parked
var _rag_t := -1.0
var _prev_front := FRONT_REST
var _prev_rear := REAR_REST
var _tex_t := 0.0
var _pending_dust := 0.0         # dust is added in batches (10 Hz) to keep the per-frame cost low
var _dust_t := 0.0
var _drops_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 99
	var tint := _glass_mat(Color(0.55, 0.72, 0.8, 0.1))
	# name, centre, yaw, size, dust texture resolution
	var defs := [
		["front", Vector3(0, 1.11, -0.84), 0.0, Vector2(1.66, 0.4), Vector2i(100, 24)],
		["rear", Vector3(0, 1.14, 2.12), PI, Vector2(1.66, 0.34), Vector2i(100, 20)],
	]
	for sx in [-1.0, 1.0]:
		defs.append(["side", Vector3(sx * 0.9, 1.14, -0.05), sx * PI * 0.5, Vector2(1.54, 0.34), Vector2i(90, 20)])
		defs.append(["side", Vector3(sx * 0.9, 1.14, 1.4), sx * PI * 0.5, Vector2(1.08, 0.34), Vector2i(64, 20)])
	for d in defs:
		_pane_mesh(d[3], d[1], d[2], tint)
		_panes.append(_dust_pane(d[0], d[1], d[2], d[3], d[4]))
	# Water drops (windshield only), just inside the glass.
	_drops_mat = _glass_mat(Color(0.85, 0.93, 1.0, 0.0))
	_drops_mat.albedo_texture = _speckle_texture(64, 70, 1, 3, 11)
	_drops_mat.uv1_scale = Vector3(4.15, 1.0, 1.0)
	_pane_mesh(Vector2(1.66, 0.4), Vector3(0, 1.11, -0.828), 0.0, _drops_mat)
	# Wipers and the rag
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.06)
	for p in FRONT_PIVOTS:
		_front_arms.append(_wiper(p, FRONT_ARM, FRONT_REST, black, 1.0))
	_rear_arm = _wiper(REAR_PIVOT, REAR_ARM, REAR_REST, black, -1.0)
	var rag_mat := StandardMaterial3D.new()
	rag_mat.albedo_color = Color(0.92, 0.9, 0.84)
	for pane in _panes:
		if pane.name != "side":
			continue
		var rag := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.14, 0.12, 0.03)
		rag.mesh = b
		rag.material_override = rag_mat
		rag.visible = false
		add_child(rag)
		_rags.append(rag)


## Called every frame by the car (in any view, so dust builds up while you're outside too).
## `rate` = dust per second landing on the glass right now.
func tick(delta: float, rate: float, visible_now: bool) -> void:
	_pending_dust += rate * delta
	_dust_t += delta
	if _dust_t >= 0.1 and _pending_dust > 0.0:
		for pane in _panes:
			var k: float = {"front": 1.0, "rear": 1.3, "side": 0.6}[pane.name]
			_add_dust(pane, _pending_dust * k)
		_pending_dust = 0.0
		_dust_t = 0.0
	wet = maxf(wet - delta * 0.03, 0.0)          # water evaporates in the desert heat
	_animate_wipers(delta)
	_animate_rags(delta)
	_drops_mat.albedo_color.a = wet * 0.9
	_tex_t += delta
	if visible_now and _tex_t >= 1.0 / TEX_HZ:
		_tex_t = 0.0
		for pane in _panes:
			if pane.dirty:
				_upload(pane)


## Wipe key: front + rear wipers sweep and the rag cleans the side windows.
func wipe() -> void:
	if _wipe_t < 0.0:
		_wipe_t = 0.0
	if _rag_t < 0.0:
		_rag_t = 0.0


## Splash the windshield (from the pond). Water also rinses some dust off every window.
func splash(amount: float) -> void:
	wet = clampf(maxf(wet, amount), 0.0, 1.0)
	for pane in _panes:
		var d: PackedFloat32Array = pane.dust
		for i in d.size():
			d[i] *= 0.6
		pane.dust = d
		pane.dirty = true


## Average dust over the windshield, 0..1 (for tests / HUD).
func front_dust() -> float:
	var d: PackedFloat32Array = _panes[0].dust
	var s := 0.0
	for v in d:
		s += v
	return s / d.size()


# --- Dust --------------------------------------------------------------------

func _dust_pane(pname: String, center: Vector3, yaw: float, size: Vector2, res: Vector2i) -> Dictionary:
	var n := res.x * res.y
	var dust := PackedFloat32Array()
	dust.resize(n)
	var noise := PackedFloat32Array()
	noise.resize(n)
	for i in n:
		noise[i] = _rng.randf()
	# RGBA bytes: colour is fixed per pixel (grainy tan); only alpha changes as dust builds.
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i in n:
		var shade := 0.85 + 0.3 * noise[i]
		bytes[i * 4] = int(clampf(DUST_COL.r * shade, 0.0, 1.0) * 255.0)
		bytes[i * 4 + 1] = int(clampf(DUST_COL.g * shade, 0.0, 1.0) * 255.0)
		bytes[i * 4 + 2] = int(clampf(DUST_COL.b * shade, 0.0, 1.0) * 255.0)
		bytes[i * 4 + 3] = 0
	var img := Image.create_from_data(res.x, res.y, false, Image.FORMAT_RGBA8, bytes)
	var tex := ImageTexture.create_from_image(img)
	var mat := _glass_mat(Color.WHITE)
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR   # soft grit, not big squares up close
	# Sit the dust layer a few mm inside the glass (toward the middle of the cabin).
	var inward := Vector3(-center.x, 0, 0.6 - center.z)
	inward = inward.normalized() * 0.004 if inward.length() > 0.01 else Vector3.ZERO
	_pane_mesh(size, center + inward, yaw, mat)
	return {"name": pname, "center": center, "yaw": yaw, "size": size, "w": res.x, "h": res.y,
			"dust": dust, "noise": noise, "bytes": bytes, "img": img, "tex": tex, "dirty": false}


## Dust lands unevenly: grainy, and heavier toward the bottom and the edges of the glass.
func _add_dust(pane: Dictionary, amount: float) -> void:
	var d: PackedFloat32Array = pane.dust
	var noise: PackedFloat32Array = pane.noise
	var w: int = pane.w
	var h: int = pane.h
	for j in h:
		var vy := float(j) / (h - 1)                         # 0 top .. 1 bottom
		for i in w:
			var ex := absf(float(i) / (w - 1) * 2.0 - 1.0)   # 0 centre .. 1 edge
			var k := j * w + i
			var bias := 0.6 + 0.5 * vy + 0.4 * ex * ex
			d[k] = minf(d[k] + amount * bias * (0.4 + 1.2 * noise[k]), 1.0)
	pane.dust = d
	pane.dirty = true


func _upload(pane: Dictionary) -> void:
	var d: PackedFloat32Array = pane.dust
	var noise: PackedFloat32Array = pane.noise
	var bytes: PackedByteArray = pane.bytes
	for k in d.size():
		bytes[k * 4 + 3] = int(clampf(d[k], 0.0, 1.0) * DUST_ALPHA * (0.75 + 0.25 * noise[k]) * 255.0)
	pane.bytes = bytes
	var img: Image = pane.img
	img.set_data(pane.w, pane.h, false, Image.FORMAT_RGBA8, bytes)
	(pane.tex as ImageTexture).update(img)
	pane.dirty = false


## Car-space position of a dust pixel's centre.
func _pixel_pos(pane: Dictionary, i: int, j: int) -> Vector3:
	var size: Vector2 = pane.size
	var lx: float = (i + 0.5) / pane.w * size.x - size.x * 0.5
	var ly: float = size.y * 0.5 - (j + 0.5) / pane.h * size.y
	return pane.center + Basis(Vector3.UP, pane.yaw) * Vector3(lx, ly, 0)


## Clear the dust a wiper blade swept over this frame: pixels within reach of the pivot whose
## angle lies between the blade's previous and current angle.
func _sweep(pane: Dictionary, pivot: Vector3, arm: float, a0: float, a1: float, mirror: float) -> void:
	var lo := minf(a0, a1)
	var hi := maxf(a0, a1)
	if hi - lo < 0.0001:
		return
	var d: PackedFloat32Array = pane.dust
	var w: int = pane.w
	for j in pane.h:
		for i in w:
			var p := _pixel_pos(pane, i, j)
			var dx := (p.x - pivot.x) * mirror
			var dy := p.y - pivot.y
			var r := sqrt(dx * dx + dy * dy)
			if r < 0.04 or r > arm + 0.03:
				continue
			var ang := atan2(-dx, dy)        # same convention as the arm's rotation.z
			if ang >= lo - 0.03 and ang <= hi + 0.03:
				d[j * w + i] *= 0.03          # a faint film stays behind
	pane.dust = d
	pane.dirty = true


# --- Wipers + rag --------------------------------------------------------------

## Multiply a pane's dust by `keep` (0 = wash it all off, leaving a faint film).
func _wash(pane: Dictionary, keep: float) -> void:
	var d: PackedFloat32Array = pane.dust
	for i in d.size():
		d[i] = d[i] * keep if keep > 0.0 else minf(d[i], 0.02)
	pane.dust = d
	pane.dirty = true


func _animate_wipers(delta: float) -> void:
	var front := FRONT_REST
	var rear := REAR_REST
	if _wipe_t >= 0.0:
		_wipe_t += delta
		var phase := _wipe_t / WIPE_TIME
		if phase >= SWEEPS:
			_wipe_t = -1.0
			# Finished: the whole windshield and rear window are clean (a faint film stays).
			for pane in [_panes[0], _panes[1]]:
				_wash(pane, 0.0)
		else:
			# Washer fluid: dust the blades don't reach (corners, the strip between them)
			# runs off gradually over the wipe, so it ends fully clean.
			var keep := pow(0.05, delta / (WIPE_TIME * SWEEPS))
			for pane in [_panes[0], _panes[1]]:
				_wash(pane, keep)
			var s := sin(fmod(phase, 1.0) * PI)
			front = lerpf(FRONT_REST, FRONT_UP, s)
			rear = lerpf(REAR_REST, REAR_UP, s)
			wet = maxf(wet - delta / (WIPE_TIME * SWEEPS) * 3.0, 0.0)
	for k in _front_arms.size():
		_front_arms[k].rotation.z = front
		if front != _prev_front:
			_sweep(_panes[0], FRONT_PIVOTS[k], FRONT_ARM, _prev_front, front, 1.0)
	_rear_arm.rotation.z = rear
	if rear != _prev_rear:
		_sweep(_panes[1], REAR_PIVOT, REAR_ARM, _prev_rear, rear, 1.0)
	_prev_front = front
	_prev_rear = rear


## The rag crosses each side window front-to-back in a slight wave, cleaning a band as it goes.
func _animate_rags(delta: float) -> void:
	if _rag_t < 0.0:
		return
	var t0 := _rag_t / RAG_TIME
	_rag_t += delta
	var t1 := minf(_rag_t / RAG_TIME, 1.0)
	var r := 0
	for pane in _panes:
		if pane.name != "side":
			continue
		var rag := _rags[r]
		r += 1
		var size: Vector2 = pane.size
		var basis := Basis(Vector3.UP, pane.yaw)
		var lx := lerpf(-size.x * 0.5, size.x * 0.5, t1)
		var ly := sin(t1 * TAU * 2.0) * size.y * 0.25
		var inward := Vector3(-pane.center.x, 0, 0).normalized() * 0.03
		rag.position = pane.center + basis * Vector3(lx, ly, 0) + inward
		rag.rotation.y = pane.yaw
		rag.visible = t1 < 1.0
		# Clear the band of columns the rag passed this frame (the whole height, it's a big rag).
		var d: PackedFloat32Array = pane.dust
		var w: int = pane.w
		var c0 := int(floor(t0 * w)) - 1
		var c1 := int(ceil(t1 * w)) + 1
		# Texture columns run along the pane's local x, the same axis the rag travels.
		for i in range(maxi(c0, 0), mini(c1, w)):
			for j in pane.h:
				d[j * w + i] *= 0.05
		pane.dust = d
		pane.dirty = true
	if t1 >= 1.0:
		_rag_t = -1.0


func _wiper(pivot_pos: Vector3, arm: float, rest: float, mat: Material, face: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	pivot.rotation.z = rest
	add_child(pivot)
	for part in [[Vector3(0.016, arm, 0.012), Vector3(0, arm * 0.5, 0.004 * face)],
			[Vector3(0.03, arm * 0.92, 0.02), Vector3(0.012, arm * 0.52, 0.01 * face)],
			[Vector3(0.04, 0.04, 0.03), Vector3.ZERO]]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[0]
		mi.mesh = b
		mi.position = part[1]
		mi.material_override = mat
		pivot.add_child(mi)
	return pivot


func _pane_mesh(size: Vector2, pos: Vector3, yaw: float, mat: Material) -> void:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = pos
	mi.rotation.y = yaw
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _glass_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_color = col
	return m


## Transparent texture with `count` random dots (water drops).
static func _speckle_texture(size: int, count: int, r_min: int, r_max: int, seed_val: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in count:
		var c := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		var r := rng.randi_range(r_min, r_max)
		var a := rng.randf_range(0.4, 1.0)
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if x * x + y * y <= r * r:
					var px := Vector2i(posmod(c.x + x, size), posmod(c.y + y, size))
					var hi := 1.0 if (r > 1 and x < 0 and y < 0) else 0.8
					img.set_pixelv(px, Color(hi, hi, hi, maxf(img.get_pixelv(px).a, a)))
	return ImageTexture.create_from_image(img)
