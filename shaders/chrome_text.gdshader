// Chrome gradient for logo text: bright top, dark "horizon" band, light bottom.
// Only bright pixels (the glyph fill) get the chrome; the dark outline is left alone.
shader_type canvas_item;

uniform float top = 6.0;
uniform float height = 40.0;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	float t = clamp((local_y - top) / height, 0.0, 1.0);
	vec3 chrome = t < 0.52
		? mix(vec3(1.0), vec3(0.62, 0.67, 0.75), t / 0.52)
		: mix(vec3(0.22, 0.25, 0.3), vec3(0.88, 0.9, 0.94), (t - 0.52) / 0.48);
	float lum = dot(COLOR.rgb, vec3(0.333));
	COLOR.rgb = mix(COLOR.rgb, chrome, step(0.5, lum));
}
