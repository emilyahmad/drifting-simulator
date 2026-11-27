## Helpers for building PS2-style materials and tiny procedural textures.
extends RefCounted

const SHADER := preload("res://shaders/ps2.gdshader")


static func material(tint: Color, tex: Texture2D = null, vertex_color := false, uv_scale := 1.0, affine := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("use_vertex_color", vertex_color)
	m.set_shader_parameter("uv_scale", uv_scale)
	m.set_shader_parameter("affine_strength", affine)
	if tex:
		m.set_shader_parameter("albedo_tex", tex)
		m.set_shader_parameter("use_texture", true)
	return m


## Tileable 64x64 sand grain texture with faint wind ripples, posterized.
static func sand_texture(size := 64) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.09
	var src := noise.get_seamless_image(size, size)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := src.get_pixel(x, y).r
			var ripple := sin((float(y) / size) * TAU * 6.0 + v * 3.0) * 0.5 + 0.5
			var b := 0.80 + v * 0.14 + ripple * 0.08
			b = floor(b * 12.0) / 12.0
			img.set_pixel(x, y, Color(b, b * 0.97, b * 0.94, 1.0))
	return ImageTexture.create_from_image(img)


## Soft round blob (for smoke and the car's ground shadow), stepped for a low-fi look.
static func blob_texture(size := 16) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = floor(a * 4.0) / 4.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Abstract mosaic (no figures): jewel-toned tiles with a gold border, for the chapel panel.
static func mosaic_texture(w := 24, h := 32) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var pal := [Color(0.15, 0.3, 0.65), Color(0.1, 0.5, 0.6), Color(0.85, 0.65, 0.2), Color(0.75, 0.2, 0.18),
			Color(0.95, 0.9, 0.75), Color(0.25, 0.45, 0.25)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for y in h:
		for x in w:
			var c: Color = pal[rng.randi() % pal.size()]
			# Concentric bands around a centre "sun" give it structure.
			var d := Vector2(x - w * 0.5, (y - h * 0.4) * 0.8).length()
			if int(d) % 5 == 0:
				c = pal[2]
			if d < 3.0:
				c = pal[4]
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				c = pal[2]
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Soft, wispy puff for drift smoke: smooth falloff broken up by noise (no hard steps).
static func smoke_texture(size := 32) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.18
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			a *= 0.65 + 0.35 * (noise.get_noise_2d(x, y) * 0.5 + 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
