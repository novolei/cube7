extends Node
## 设置（自动加载为 Settings）：音量、镜头、震屏，存在 user://settings.cfg

signal changed

var values := {
	"master": 0.9, "music": 0.8, "sfx": 0.9, "ui": 0.8,
	"cam_sens": 1.0, "invert_y": false, "shake": true, "reduce_motion": false, "subtitles_speed": 1.0,
	"cam_dist": 1.0, "rumble": 0.8, "aim_assist": true, "fog": true,
	"cinematic": true, "performance": OS.has_feature("mobile"),
}

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		for k in values.keys():
			values[k] = cf.get_value("settings", k, values[k])
	apply.call_deferred()

func get_v(k: String):
	return values.get(k)

func set_v(k: String, v) -> void:
	values[k] = v
	apply()
	var cf := ConfigFile.new()
	for key in values.keys():
		cf.set_value("settings", key, values[key])
	cf.save("user://settings.cfg")
	changed.emit()

func apply() -> void:
	for pair in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"], ["UI", "ui"]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			var trim := -4.0 if pair[0] == "Music" or pair[0] == "UI" else (-2.0 if pair[0] == "SFX" else 0.0)
			AudioServer.set_bus_mute(i, float(values[pair[1]]) <= 0.0)
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(values[pair[1]]), 0.0001)) + trim)
	# 远景雾开关：直接改当前场景的环境
	var tree := get_tree()
	if tree and tree.current_scene:
		apply_visuals(tree.current_scene)

func apply_visuals(root: Node) -> void:
	var economy := bool(values.performance)
	RenderingServer.global_shader_parameter_set(&"economy_render", economy or OS.has_feature("mobile"))
	var mobile_renderer := RenderingServer.get_current_rendering_method() != "forward_plus"
	var viewport := root.get_viewport()
	viewport.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("mobile") else (Viewport.MSAA_2X if economy else Viewport.MSAA_4X)
	viewport.scaling_3d_scale = (0.65 if OS.has_feature("mobile") else 0.85) if economy else 1.0
	var we := root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we and we.environment:
		var env := we.environment
		env.fog_enabled = bool(values.fog)
		env.ssao_enabled = not economy and not mobile_renderer
		env.ssao_intensity = 0.85
		env.ssao_radius = 0.65
		env.glow_enabled = not economy and not mobile_renderer
		if OS.has_feature("mobile"):
			env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var sun := root.find_child("Sun", true, false) as DirectionalLight3D
	if sun:
		sun.directional_shadow_max_distance = (24.0 if OS.has_feature("mobile") else 38.0) if economy else 70.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if economy else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var veil := root.get_node_or_null("CinematicVeil") as CanvasLayer
	if veil == null and we:
		veil = CanvasLayer.new()
		veil.name = "CinematicVeil"
		veil.layer = 0 # World only: the HUD and menus remain clean.
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/cinematic_veil.gdshader")
		rect.material = material
		veil.add_child(rect)
		root.add_child(veil)
	if veil:
		veil.visible = bool(values.cinematic)
		var material := (veil.get_child(0) as ColorRect).material as ShaderMaterial
		material.set_shader_parameter("grain_strength", 0.0 if economy else 0.012)
		material.set_shader_parameter("animate_grain", not bool(values.reduce_motion))

