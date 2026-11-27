// Full-screen PS2 post: reduced color depth with 4x4 ordered dither + soft vignette.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float color_levels = 32.0;
uniform float dither_strength = 1.0;
uniform float vignette = 0.28;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	float threshold = (BAYER[p.y * 4 + p.x] + 0.5) / 16.0 - 0.5;
	c += threshold * dither_strength / color_levels;
	c = floor(c * (color_levels - 1.0) + 0.5) / (color_levels - 1.0);
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - dot(d, d) * vignette * 2.0;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
