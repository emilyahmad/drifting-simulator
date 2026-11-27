## Start / pause screen: stats pill, chrome logo, stepped italic menu with car picker,
## "now playing" box, button hints and the CC-BY credit for the car pack.
extends Control

signal chosen(id: String)

const UI := preload("res://scripts/ui/ui_theme.gd")
const CarModels := preload("res://scripts/car_models.gd")
const CHROME := preload("res://shaders/chrome_text.gdshader")
## Live screen size: the render area widens/narrows to fill the window (aspect "expand").
var W: float:
	get:
		return size.x
var H: float:
	get:
		return size.y
const ITEM_Y := 200.0
const ITEM_STEP := 30.0

var best := 0
var total := 0
var found := 0
var found_max := 0
var car_index := 0
var camera_name := "CHASE"
var display_name := "MAXIMIZED"
var paused := false
var _items: Array = []
var _sel := 0
var _t := 0.0
var _show_credits := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var plate := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.24, 0.26, 0.3)
	sb.border_color = Color(0.85, 0.88, 0.92)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.skew = Vector2(0.3, 0)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 6
	plate.add_theme_stylebox_override("panel", sb)
	plate.position = Vector2(34, 58)
	plate.size = Vector2(360, 66)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)

	var logo := Label.new()
	logo.text = "RIYADH DRIFT"
	var ls := LabelSettings.new()
	ls.font = UI.en()
	ls.font_size = 44
	ls.font_color = Color.WHITE
	ls.outline_size = 8
	ls.outline_color = Color(0.06, 0.07, 0.1)
	ls.shadow_color = Color(0, 0, 0, 0.7)
	ls.shadow_offset = Vector2(3, 3)
	logo.label_settings = ls
	var mat := ShaderMaterial.new()
	mat.shader = CHROME
	mat.set_shader_parameter("top", 10.0)
	mat.set_shader_parameter("height", 36.0)
	logo.material = mat
	logo.position = Vector2(46, 62)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)


func open(is_paused: bool) -> void:
	paused = is_paused
	_items = ["resume", "car", "camera", "display", "restart", "credits", "quit"] if paused else ["start", "car", "camera", "display", "credits", "quit"]
	_sel = 0
	_show_credits = false
	visible = true


func _labels(id: String) -> Array:
	match id:
		"start": return ["start drift", "ابدأ التفحيط"]
		"resume": return ["resume", "استئناف"]
		"restart": return ["restart", "من جديد"]
		"quit": return ["quit", "خروج"]
		"credits": return ["credits", "الحقوق"]
		"display": return ["display: " + display_name.to_lower(), "الشاشة"]
		"camera": return ["camera: " + camera_name.to_lower(), "الكاميرا"]
		"car":
			var m: Dictionary = CarModels.LIST[car_index]
			return ["car:  < " + String(m["name"]).to_lower() + " >", m["ar"]]
	return [id, ""]


func _item_pos(i: int) -> Vector2:
	return Vector2(86 - i * 9 + (12 if i == _sel else 0), ITEM_Y + i * ITEM_STEP)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _show_credits:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			_show_credits = false
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("throttle"):
		_sel = wrapi(_sel - 1, 0, _items.size())
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("brake"):
		_sel = wrapi(_sel + 1, 0, _items.size())
	elif _items[_sel] == "car" and (event.is_action_pressed("ui_left") or event.is_action_pressed("steer_left")):
		chosen.emit("car_prev")
	elif _items[_sel] == "car" and (event.is_action_pressed("ui_right") or event.is_action_pressed("steer_right")):
		chosen.emit("car_next")
	elif event.is_action_pressed("ui_accept"):
		_choose(_items[_sel])
	else:
		return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if _show_credits:
		if event is InputEventMouseButton and event.pressed:
			_show_credits = false
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		for i in _items.size():
			var p := _item_pos(i)
			if Rect2(p.x - 20, p.y - 22, 300, 28).has_point(event.position):
				_sel = i
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_choose(_items[i])
				break


func _choose(id: String) -> void:
	if id == "credits":
		_show_credits = true
	elif id == "car":
		chosen.emit("car_next")
	else:
		chosen.emit(id)


func _draw() -> void:
	var en := UI.en()
	var ar := UI.ar()

	# Backdrop: dim, slanted blue panel on the left, letterbox bars with a chrome rule.
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.2))
	var dx := W - 640.0
	var dy := H - 448.0
	draw_polygon(PackedVector2Array([Vector2(0, 44), Vector2(430, 44), Vector2(330, H - 52), Vector2(0, H - 52)]),
			PackedColorArray([Color(UI.NAVY, 0.92), Color(UI.NAVY, 0.0), Color(UI.NAVY, 0.0), Color(UI.NAVY, 0.92)]))
	draw_rect(Rect2(0, 0, W, 40), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(0, 40, W, 2), Color(0.8, 0.83, 0.88))
	draw_rect(Rect2(0, H - 50, W, 50), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(0, H - 52, W, 2), Color(0.8, 0.83, 0.88))

	# Stats pill
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.06, 0.12, 0.36)
	pill.border_color = Color(0.55, 0.7, 1.0)
	pill.set_border_width_all(2)
	pill.set_corner_radius_all(10)
	draw_style_box(pill, Rect2(10, 9, 380, 22))
	var x := 22.0
	for pair in [["Best Drift: ", UI.fmt(best)], ["   Total: ", UI.fmt(total)], ["   Landmarks: ", "%d/%d" % [found, found_max]]]:
		UI.text(self, Vector2(x, 25), pair[0], 11, Color.WHITE, en, "l", 0)
		x += UI.width(pair[0], 11, en)
		UI.text(self, Vector2(x, 25), pair[1], 11, Color(1.0, 0.92, 0.3), en, "l", 0)
		x += UI.width(pair[1], 11, en)
	UI.text(self, Vector2(W - 12, 25), "أفضل تفحيط: " + UI.ar_digits(best), 12, Color.WHITE, ar, "r", 0)

	UI.text(self, Vector2(380, 146), "تفحيط الرياض", 20, UI.AMBER, ar, "r", 4)
	if paused:
		UI.text(self, Vector2(46, 146), "PAUSED", 12, Color(1, 1, 1, 0.8), en)

	# Menu items
	for i in _items.size():
		var p := _item_pos(i)
		var lab: Array = _labels(_items[i])
		var on := i == _sel
		var col := UI.AMBER if on else Color.WHITE
		if on:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-20, -14), p + Vector2(-8, -8), p + Vector2(-20, -2)]), col)
		UI.text(self, p, lab[0], 22, col, en, "l", 5)
		UI.text(self, p + Vector2(UI.width(lab[0], 22, en) + 12, -1), lab[1], 13, Color(col, 0.75), ar, "l", 3)

	# Bottom bar contents (laid out on the 448-high base, shifted to the bottom edge)
	draw_set_transform(Vector2(0, dy))
	# Now playing (with a spinning record)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	box.border_color = Color(0.7, 0.72, 0.76)
	box.set_border_width_all(1)
	draw_style_box(box, Rect2(10, 404, 214, 36))
	UI.text(self, Vector2(16, 418), "Now Playing", 10, Color(1.0, 0.92, 0.3), en, "l", 0)
	UI.text(self, Vector2(16, 433), "♪ Desert FM 92 - Night Ride", 10, Color.WHITE, en, "l", 0)
	var rc := Vector2(204, 422)
	draw_circle(rc, 15, Color(0.04, 0.04, 0.05))
	draw_arc(rc, 11, 0, TAU, 16, Color(0.2, 0.2, 0.22), 1.0)
	draw_circle(rc, 5, Color(0.85, 0.1, 0.1))
	var a := _t * 4.0
	draw_line(rc + Vector2(cos(a), sin(a)) * 6, rc + Vector2(cos(a), sin(a)) * 14, Color(0.5, 0.5, 0.55), 1.0)

	# Button hints
	var hx := 252.0
	for hint in [["↑↓", "navigate"], ["←→", "car"], ["⏎", "select"], ["C", "camera"]]:
		draw_circle(Vector2(hx + 7, 414), 8, Color(1, 1, 1, 0.9))
		UI.text(self, Vector2(hx + 7, 418), hint[0], 9, Color(0.05, 0.05, 0.08), en, "c", 0)
		UI.text(self, Vector2(hx + 18, 418), hint[1], 10, Color.WHITE, en, "l", 0)
		hx += 26 + UI.width(hint[1], 10, en)

	# CC BY credit for the car pack (two lines)
	UI.text(self, Vector2(W * 0.5 + 115, 434), "\"PS2 car pack\" (skfb.ly/pHUTV) by the soppy prisma models .- · CC BY 4.0", 8, Color(1, 1, 1, 0.75), en, "c", 0)
	UI.text(self, Vector2(W * 0.5 + 115, 444), "creativecommons.org/licenses/by/4.0 · models re-scaled & re-shaded", 8, Color(1, 1, 1, 0.6), en, "c", 0)

	draw_set_transform(Vector2.ZERO)

	if _show_credits:
		draw_set_transform(Vector2(dx, dy) * 0.5)
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(0.04, 0.07, 0.18, 0.96)
		panel.border_color = Color(0.55, 0.7, 1.0)
		panel.set_border_width_all(2)
		panel.set_corner_radius_all(6)
		draw_style_box(panel, Rect2(70, 120, 500, 200))
		UI.text(self, Vector2(90, 152), "CREDITS", 20, UI.AMBER, en, "l", 4)
		UI.text(self, Vector2(550, 152), "الحقوق", 18, UI.AMBER, ar, "r", 4)
		draw_multiline_string(ThemeDB.fallback_font, Vector2(90, 182), CarModels.CREDIT,
				HORIZONTAL_ALIGNMENT_LEFT, 460, 12, -1, Color.WHITE)
		UI.text(self, Vector2(320, 306), "press ENTER to close", 10, Color(1, 1, 1, 0.7), en, "c", 0)
		draw_set_transform(Vector2.ZERO)
