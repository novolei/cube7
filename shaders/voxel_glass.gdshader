shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	if (occluder_cut(v_wpos, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) discard;
	float e = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float frame = 1.0 - smoothstep(0.015, 0.04, e);
	ALBEDO = mix(COLOR.rgb * COLOR.a, vec3(0.72, 0.82, 0.73), frame * 0.35);
	ALPHA = mix(0.20, 0.48, frame);
	ROUGHNESS = 0.3;
	SPECULAR = 0.35;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = COLOR.rgb * rim * 0.12;
}
