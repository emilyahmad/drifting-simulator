// PS2-style water: vertex jitter + gentle bob, scrolling posterized ripples.
shader_type spatial;
render_mode vertex_lighting, cull_disabled, specular_disabled;

uniform vec4 deep : source_color = vec4(0.1, 0.38, 0.42, 1.0);
uniform vec4 shallow : source_color = vec4(0.35, 0.65, 0.6, 1.0);
uniform vec2 snap_resolution = vec2(320.0, 224.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.3 + world_pos.x * 0.4) * 0.04;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip.w > 0.0) {
		clip.xy = round(clip.xy / clip.w * snap_resolution * 0.5) / (snap_resolution * 0.5) * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec2 p = world_pos.xz * 0.35;
	float r = sin(p.x * 2.0 + TIME * 1.1) * sin(p.y * 2.3 - TIME * 0.8) + sin((p.x + p.y) * 1.3 + TIME * 0.6);
	r = floor((r * 0.25 + 0.5) * 4.0) / 4.0;
	ALBEDO = mix(deep.rgb, shallow.rgb, r);
}
