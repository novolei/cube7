shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://shaders/voxel_common.gdshaderinc"

// Matte terrain: retain baked AO, sunlight, shadows and camera cutout.
// Avoid the desktop normal bevel and pixel noise on tile-based GPUs.
void fragment() {
	if (occluder_cut(v_wpos, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) discard;
	vec3 col = COLOR.rgb * COLOR.a;
	float cat = voxel_category();
	bool natural = v_type > 1.5 && v_type < 4.5 || v_type > 20.5 && v_type < 35.5;
	if (!natural && cat > 0.5 && cat < 1.5) {
		col *= 1.0 + 0.16 * (1.0 - smoothstep(0.02, 0.08, exposed_edge_dist(UV)));
	}
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
