## In-game HUD: drift score (top-left), live drift points (top-centre), view/pause icons
## (top-right), drift-angle meter (bottom-left), round speedometer + gear (bottom-right).
extends Control

const UI := preload("res://scripts/ui/ui_theme.gd")
const W := 640.0
const H := 448.0

var score := 0
var live := 0.0
var flash := 0
var flash_t := 0.0
var speed := 0.0
var angle := 0.0
var drifting := false
var gear := "N"
var hint_t := 0.0
var cinematic := false:
	set(v):
		cinematic = v
		_cine_t = 0.0
var _cine_t := 0.0
# Landmark discovery banner
var _toast_name := ""
var _toast_ar := ""
var _toast_new := false
var _toast_t := 0.0
var _toast_len := 0.0


func discover(landmark_name: String, landmark_ar: String, is_new: bool) -> void:
	_toast_name = landmark_name
	_toast_ar = landmark_ar
	_toast_new = is_new
	_toast_len = 5.5 if is_new else 2.6
	_toast_t = _toast_len


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_hints() -> void:
	hint_t = 8.0


func _process(delta: float) -> void:
	flash_t = maxf(flash_t - delta, 0.0)
	hint_t = maxf(hint_t - delta, 0.0)
	_toast_t = maxf(_toast_t - delta, 0.0)
	if cinematic:
		_cine_t += delta
	queue_redraw()


func _draw() -> void:
	var en := UI.en()
	var ar := UI.ar()
	if cinematic:
		_draw_cinematic(en, ar)
		return
	var white := Color.WHITE

	# Score
	UI.text(self, Vector2(14, 22), "DRIFT SCORE", 12, white, en)
	UI.text(self, Vector2(112, 22), "النقاط", 12, Color(1, 1, 1, 0.75), ar)
	UI.text(self, Vector2(14, 54), UI.fmt(score), 32, UI.AMBER, en, "l", 6)

	# Live drift / banked flash
	if live > 0.5:
		UI.text(self, Vector2(W * 0.5 - 4, 20), "DRIFT", 12, white, en, "r")
		UI.text(self, Vector2(W * 0.5 + 4, 20), "تفحيط", 12, UI.AMBER, ar, "l")
		UI.text(self, Vector2(W * 0.5, 54), "+" + UI.fmt(int(live)), 32, white, en, "c", 6)
	elif flash_t > 0.0:
		var a := minf(flash_t, 1.0)
		UI.text(self, Vector2(W * 0.5 - 4, 20), "NICE DRIFT", 12, Color(1, 1, 1, a), en, "r")
		UI.text(self, Vector2(W * 0.5 + 4, 20), "تفحيط رهيب!", 12, Color(UI.AMBER, a), ar, "l")
		UI.text(self, Vector2(W * 0.5, 54), "+" + UI.fmt(flash), 32, Color(UI.AMBER, a), en, "c", 6)

	# Top-right icons: camera (C) and pause (ESC)
	draw_rect(Rect2(584, 12, 17, 13), white)
	draw_colored_polygon(PackedVector2Array([Vector2(601, 16), Vector2(609, 12), Vector2(609, 25), Vector2(601, 21)]), white)
	draw_rect(Rect2(619, 11, 5, 15), white)
	draw_rect(Rect2(627, 11, 5, 15), white)
	UI.text(self, Vector2(596, 38), "C", 9, white, en, "c", 3)
	UI.text(self, Vector2(626, 38), "ESC", 9, white, en, "c", 3)

	# Drift angle meter
	UI.text(self, Vector2(14, 412), "DRIFT ANGLE", 12, white, en)
	UI.text(self, Vector2(116, 412), "زاوية التفحيط", 11, Color(1, 1, 1, 0.75), ar)
	const SEGS := 14
	var filled := int(round(clampf(angle / 60.0, 0.0, 1.0) * SEGS)) if drifting else 0
	for i in SEGS:
		var col := Color(1, 1, 1, 0.22)
		if i < filled:
			col = UI.RED if i >= 11 else UI.AMBER
		draw_rect(Rect2(14 + i * 17, 420, 14, 8), col)

	# Speedometer
	var c := Vector2(578, 392)
	var r := 46.0
	var a0 := deg_to_rad(135.0)
	var a1 := deg_to_rad(405.0)
	var t := clampf(speed / 200.0, 0.0, 1.0)
	draw_arc(c, r, a0, a1, 40, Color(0, 0, 0, 0.45), 9.0)
	draw_arc(c, r, a0, a1, 40, Color(1, 1, 1, 0.3), 3.0)
	if t > 0.005:
		draw_arc(c, r, a0, lerpf(a0, a1, t), 40, UI.RED if t > 0.8 else UI.AMBER, 5.0)
	for i in 11:
		var ang := lerpf(a0, a1, i / 10.0)
		var dir := Vector2(cos(ang), sin(ang))
		var major := i % 2 == 0
		draw_line(c + dir * (r - (7.0 if major else 4.0)), c + dir * (r + 1.0), UI.RED if i >= 9 else white, 2.0)
	UI.text(self, c + Vector2(2, 8), str(int(speed)), 28, white, en, "c", 5)
	UI.text(self, c + Vector2(0, 21), "KM/H", 9, white, en, "c", 3)
	UI.text(self, c + Vector2(0, 34), "كم/س", 10, Color(1, 1, 1, 0.8), ar, "c", 3)
	draw_rect(Rect2(c.x - 50, c.y + 20, 16, 18), UI.AMBER)
	UI.text(self, Vector2(c.x - 42, c.y + 34), gear, 14, Color(0.08, 0.06, 0.04), en, "c", 0)

	if _toast_t > 0.0:
		_draw_toast(en, ar)

	if hint_t > 0.0:
		var a := minf(hint_t, 1.0) * 0.85
		UI.text(self, Vector2(W * 0.5, 372), "WASD DRIVE   ARROWS CAMERA   SPACE HANDBRAKE   C VIEW   R RESET", 9, Color(1, 1, 1, a), en, "c", 3)
		UI.text(self, Vector2(W * 0.5, 388), "قيادة WASD   الكاميرا ←↑↓→   فرامل اليد SPACE   المنظور C   إعادة R", 10, Color(1, 1, 1, a), ar, "c", 3)


## Slanted banner that slides in from the left and fades out.
func _draw_toast(en: Font, ar: Font) -> void:
	var age := _toast_len - _toast_t
	var slide := 1.0 - pow(1.0 - clampf(age / 0.35, 0.0, 1.0), 3.0)
	var a := minf(clampf(age / 0.2, 0.0, 1.0), clampf(_toast_t / 0.6, 0.0, 1.0))
	var cx := W * 0.5 - (1.0 - slide) * 120.0
	var top := 96.0
	var h := 62.0 if _toast_new else 40.0
	var half := 200.0 if _toast_new else 150.0
	var band := PackedVector2Array([
		Vector2(cx - half + 14, top), Vector2(cx + half + 14, top),
		Vector2(cx + half - 14, top + h), Vector2(cx - half - 14, top + h)])
	draw_colored_polygon(band, Color(0.04, 0.05, 0.12, 0.82 * a))
	draw_line(band[0], band[1], Color(UI.AMBER, a), 2.0)
	draw_line(band[3], band[2], Color(UI.AMBER, a), 2.0)
	# Compass-star icon
	var ic := Vector2(cx - half + 30, top + h * 0.5)
	draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -9), ic + Vector2(3, -3), ic + Vector2(9, 0),
			ic + Vector2(3, 3), ic + Vector2(0, 9), ic + Vector2(-3, 3), ic + Vector2(-9, 0), ic + Vector2(-3, -3)]), Color(UI.AMBER, a))
	var white := Color(1, 1, 1, a)
	if _toast_new:
		UI.text(self, Vector2(cx - 6, top + 17), "NEW LANDMARK DISCOVERED", 11, Color(UI.AMBER, a), en, "r", 3)
		UI.text(self, Vector2(cx + 6, top + 17), "اكتشاف جديد!", 12, Color(UI.AMBER, a), ar, "l", 3)
		UI.text(self, Vector2(cx, top + 41), _toast_name, 22, white, en, "c", 5)
		UI.text(self, Vector2(cx, top + 57), _toast_ar, 13, Color(1, 1, 1, 0.85 * a), ar, "c", 3)
	else:
		UI.text(self, Vector2(cx, top + 21), _toast_name, 16, white, en, "c", 4)
		UI.text(self, Vector2(cx, top + 36), _toast_ar, 11, Color(1, 1, 1, 0.85 * a), ar, "c", 3)


## Drone-shot overlay: letterbox bars slide in, banner on top, skip hint.
func _draw_cinematic(en: Font, ar: Font) -> void:
	var bar := 44.0 * smoothstep(0.0, 0.4, _cine_t)
	draw_rect(Rect2(0, 0, W, bar), Color.BLACK)
	draw_rect(Rect2(0, H - bar, W, bar), Color.BLACK)
	if _toast_t > 0.0:
		_draw_toast(en, ar)
	var a := clampf((_cine_t - 0.8) / 0.4, 0.0, 1.0) * 0.85
	UI.text(self, Vector2(W - 14, H - 16), "SPACE  SKIP", 10, Color(1, 1, 1, a), en, "r", 0)
	UI.text(self, Vector2(W - 96, H - 16), "تخطي", 11, Color(1, 1, 1, a), ar, "r", 0)
