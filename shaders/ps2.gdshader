// PS2-style surface: vertex jitter, affine texture warp, per-vertex (Gouraud) lighting.
shader_type spatial;
render_mode vertex_lighting, cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform bool use_texture = false;
uniform bool use_vertex_color = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 1.0;
uniform float affine_strength = 1.0;
// Lower = chunkier vertex snapping (bigger wobble).
uniform vec2 snap_resolution = vec2(320.0, 224.0);

varying vec3 affine_uv;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	affine_uv = vec3(UV * uv_scale * clip.w, clip.w);
	if (clip.w > 0.0) {
		vec2 ndc = clip.xy / clip.w;
		ndc = round(ndc * snap_resolution * 0.5) / (snap_resolution * 0.5);
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec2 perspective_uv = UV * uv_scale;
	vec2 warped_uv = affine_uv.xy / affine_uv.z;
	vec2 uv = mix(perspective_uv, warped_uv, affine_strength);
	vec4 c = tint;
	if (use_texture) {
		c *= texture(albedo_tex, uv);
	}
	if (use_vertex_color) {
		c *= COLOR;
	}
	ALBEDO = c.rgb;
}
