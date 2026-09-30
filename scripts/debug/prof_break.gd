extends Node
## 性能剖析：大量破坏 / 打怪之后每帧耗时。
## godot --headless --path . res://scenes/main.tscn -- --chapter=N --debugscript=res://scripts/debug/prof_break.gd

var P: MorphBall
var W: VoxelWorld
var _times: Array[float] = []
var _last := 0
var _gpu: Array[float] = []
var _draws: Array[float] = []
var _reports: Array[Dictionary] = []
var _out := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var main := get_parent()
	P = main.player
	W = main.world
	P.debug_override = true
	Flow.mode = "debug"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-out="):
			_out = arg.trim_prefix("--bench-out=")
		elif arg == "--economy":
			Settings.values.performance = true
			Settings.apply()
	_run()

func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last > 0:
		_times.append((now - _last) / 1000.0)
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_last = now

func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout

func _report(tag: String) -> void:
	var a := _times.duplicate()
	_times.clear()
	if a.is_empty():
		return
	a.sort()
	var s := 0.0
	for x in a:
		s += x
	print("%-18s frames=%4d avg=%6.2fms p95=%6.2fms max=%7.2fms nodes=%d chunks=%d ts=%.2f" % [tag, a.size(), s / a.size(), a[int(a.size() * 0.95)], a[-1], get_tree().get_node_count(), _count_chunks(), Engine.time_scale])
	_gpu.sort()
	_draws.sort()
	var row := {"phase": tag, "frames": a.size(), "mean_ms": s / a.size(), "p95_ms": a[int(a.size() * 0.95)], "max_ms": a[-1], "gpu_p95_ms": _gpu[int(_gpu.size() * 0.95)], "draw_calls_p95": _draws[int(_draws.size() * 0.95)]}
	_reports.append(row)
	print(JSON.stringify(row))
	_gpu.clear()
	_draws.clear()

func _count_chunks() -> int:
	var n := 0
	for c in W.get_children():
		if c is VoxelChunk:
			n += 1
	return n

func _run() -> void:
	await wait(6.0)
	if get_tree().paused:
		get_parent().hud._pause.close()
	if OS.has_feature("mobile"):
		print("MOBILE_IDLE: 45 seconds before benchmark")
		await wait(45.0)
	W._rng.seed = 730
	_times.clear()
	_gpu.clear()
	_draws.clear()
	await wait(3.0)
	_report("baseline")
	# 大量破坏：以玩家为中心一圈一圈砸
	var c := P.global_position
	var t0 := Time.get_ticks_usec()
	for i in 24:
		var a := i * 0.7
		var p := c + Vector3(cos(a), 0, sin(a)) * (2.0 + i * 0.35) + Vector3.DOWN * 0.6
		W.break_sphere(p, 1.7, "impact", 16.0, Vector3.DOWN)
		GameState.hitstop(0.05)
		await get_tree().process_frame
	print("break loop took %.1fms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	_report("during breaks")
	await wait(1.0)
	_report("0-1s after")
	await wait(2.0)
	_report("1-3s after")
	# 打怪
	var es := get_tree().get_nodes_in_group("enemy")
	var k := 0
	for e in es:
		if e.has_method("defeat") and k < 10:
			e.defeat(true)
			k += 1
			await get_tree().process_frame
	print("defeated ", k)
	await wait(1.0)
	_report("kills 0-1s")
	await wait(3.0)
	_report("kills 1-4s")
	await wait(5.0)
	_report("later 4-9s")
	if _out != "":
		var file := FileAccess.open(_out, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"device": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(get_viewport().get_visible_rect().size), "chapter": GameState.chapter, "phases": _reports}, "\t"))
	get_tree().quit()

func _sample(tag: String) -> void:
	await wait(2.0)
	_times.clear()
	_gpu.clear()
	_draws.clear()
	await wait(3.0)
	_report(tag)

func _diagnose_only() -> void:
	await wait(8.0)
	if get_tree().paused:
		get_parent().hud._pause.close()
	await _sample("diag baseline")
	var sun := get_parent().get_node("Sun") as DirectionalLight3D
	sun.shadow_enabled = false
	await _sample("diag no shadows")
	for n in get_parent().level.find_children("*", "Node3D", true, false):
		if n is SkyWorld or n is Vista:
			n.visible = false
	await _sample("diag no backdrop")
	get_viewport().scaling_3d_scale = 0.5
	await _sample("diag half pixels")
	var simple := Shader.new()
	simple.code = "shader_type spatial; void vertex(){ COLOR=COLOR; } void fragment(){ ALBEDO=COLOR.rgb*COLOR.a; ROUGHNESS=0.92; }"
	for material in W._materials:
		if material is ShaderMaterial:
			(material as ShaderMaterial).shader = simple
	await _sample("diag simple world")
	var env := get_parent().get_node("WorldEnvironment").environment as Environment
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.7)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	await _sample("diag no sky IBL")
	get_tree().quit()
