shader_type canvas_item;
render_mode unshaded;
// One alpha pass, no screen copy or texture sampling. UI is on a higher layer.
uniform float grain_strength = 0.012;
uniform bool animate_grain = true;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.85);
	float edge = smoothstep(0.26, 0.68, length(p)) * 0.12;
	float grain = 0.0;
	if (grain_strength > 0.0) {
		float phase = animate_grain ? floor(TIME * 24.0) : 0.0;
		vec3 h = fract(vec3(FRAGCOORD.xy, phase) * 0.1031);
		h += dot(h, h.yzx + 33.33);
		grain = (fract((h.x + h.y) * h.z) - 0.5) * grain_strength;
	}
	float alpha = edge + abs(grain);
	vec3 tint = (vec3(0.055, 0.11, 0.10) * edge + vec3(step(0.0, grain)) * abs(grain)) / max(alpha, 0.00001);
	COLOR = vec4(tint, alpha);
}
