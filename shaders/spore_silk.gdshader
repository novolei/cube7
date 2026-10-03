shader_type spatial;
render_mode cull_disabled;

uniform float elapsed = 0.0;
uniform float motion_amount = 1.0;
uniform vec3 wind = vec3(0.035, 0.0, 0.02);
uniform vec3 inertia = vec3(0.0);
varying vec3 pigment;

void vertex() {
	pigment = COLOR.rgb;
	float weight = COLOR.a * COLOR.a;
	float phase = INSTANCE_CUSTOM.r * 4.1 + VERTEX.x * 3.7;
	vec3 air = wind * (0.65 + 0.35 * sin(elapsed * 1.15 + phase));
	vec3 local_air = (inverse(MODEL_MATRIX) * vec4(air, 0.0)).xyz;
	VERTEX += weight * motion_amount * (local_air + inertia + vec3(sin(elapsed * 2.2 + phase) * 0.055, sin(elapsed * 1.7 + phase) * 0.025, 0.0));
}

void fragment() {
	ALBEDO = pigment;
	ROUGHNESS = 0.91;
	SPECULAR = 0.18;
}
