shader_type spatial;
render_mode cull_disabled;
uniform float elapsed = 0.0;
uniform float motion_amount = 1.0;
uniform float pulse_time = -100.0;
uniform vec3 pulse_origin = vec3(0.0);
varying float born;
varying float phase;
varying vec3 world_position;

void vertex() {
	born = INSTANCE_CUSTOM.r;
	phase = INSTANCE_CUSTOM.g;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float a = atan(p.y, p.x);
	float r = length(p);
	float age = max(0.0, elapsed - born);
	float reach = smoothstep(0.0, 1.8, age);
	float edge = 0.88 + sin(a * 5.0 + phase * 6.28) * 0.04;
	float cover = step(r, edge * reach);
	// 连续世界坐标的细脉穿过格子边界，避免一格一个相同的花纹。
	vec2 ground = world_position.xz;
	float branch = abs(sin(ground.x * 6.7 + sin(ground.y * 4.1) * 1.2));
	float cross_branch = abs(sin(ground.y * 8.3 + sin(ground.x * 3.9) * 1.5));
	float veins = (1.0 - smoothstep(0.035, 0.12, branch)) * 0.7 + (1.0 - smoothstep(0.02, 0.065, cross_branch)) * 0.3;
	// 成熟后露出原来的体素草地，只保留细脉，不留下满地圆形贴片。
	float tissue = max(veins, (1.0 - smoothstep(1.5, 5.0, age)) * (1.0 - smoothstep(0.10, 0.85, r)));
	cover *= step(0.2, tissue);
	float age_tone = smoothstep(1.0, 7.0, age);
	vec3 young = vec3(0.24, 0.29, 0.12);
	vec3 mature = vec3(0.10, 0.18, 0.07);
	ALBEDO = mix(young, mature, age_tone) + veins * vec3(0.09, 0.08, 0.03);
	float travel = length(world_position.xz - pulse_origin.xz) / 2.1;
	float beat = max(0.0, 1.0 - abs(elapsed - pulse_time - travel) * 3.0) * motion_amount;
	EMISSION = vec3(0.39, 0.35, 0.16) * beat * veins * 0.35;
	ROUGHNESS = 0.97;
	SPECULAR = 0.1;
	ALPHA = cover;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
