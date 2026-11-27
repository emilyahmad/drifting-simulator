## Shared fonts, colors and text helpers for the HUD and menus.
extends RefCounted

const AMBER := Color(1.0, 0.74, 0.18)
const RED := Color(1.0, 0.32, 0.2)
const NAVY := Color(0.05, 0.12, 0.34)
const OUTLINE := Color(0.03, 0.02, 0.02)

static var _en: Font
static var _ar: Font


## Heavy italic for English. Embolden + slant guarantee the look even without a bold-italic face.
static func en() -> Font:
	if _en == null:
		var base := SystemFont.new()
		base.font_names = PackedStringArray(["Helvetica Neue", "Arial", "DejaVu Sans"])
		base.font_weight = 800
		base.font_italic = true
		base.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		var v := FontVariation.new()
		v.base_font = base
		v.variation_embolden = 0.7
		v.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.22, 1.0), Vector2.ZERO)
		_en = v
	return _en


## Bold upright Arabic (slanted Arabic script reads badly).
static func ar() -> Font:
	if _ar == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Geeza Pro", "Noto Sans Arabic", "Arial", "Tahoma"])
		f.font_weight = 700
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_ar = f
	return _ar


## Draws outlined text. anchor: "l" = pos is left edge, "c" = centre, "r" = right edge.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, font: Font,
		anchor := "l", outline := 4) -> void:
	const BOX := 480.0
	var align := HORIZONTAL_ALIGNMENT_LEFT
	var p := pos
	if anchor == "c":
		align = HORIZONTAL_ALIGNMENT_CENTER
		p.x -= BOX * 0.5
	elif anchor == "r":
		align = HORIZONTAL_ALIGNMENT_RIGHT
		p.x -= BOX
	var w := BOX if anchor != "l" else -1.0
	if outline > 0:
		ci.draw_string_outline(font, p, s, align, w, size, outline, Color(OUTLINE, col.a))
	ci.draw_string(font, p, s, align, w, size, col)


static func width(s: String, size: int, font: Font) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 12345 -> "12,345"
static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## 12345 -> "١٢٬٣٤٥" (Eastern Arabic numerals)
static func ar_digits(n: int) -> String:
	var out := ""
	for ch in fmt(n):
		out += "٬" if ch == "," else (char(0x0660 + int(ch)) if ch.is_valid_int() else ch)
	return out
