extends "res://scripts/debug/test_surge.gd"
## 沿真实游玩循环采样；不录屏、不关阴影、不替换材质。
var _frames: Dictionary = {}
var _last := 0
var _warm := 0.0
var _bench_out := ""

func _ready() -> void:
	# 采样器在暂停时仍运行并丢弃间隔，不能把暂停的 300ms 当成慢帧。
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-out="):
			_bench_out = arg.trim_prefix("--bench-out=")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	super._ready()
	Engine.max_fps = 0

func _process(delta: float) -> void:
	_warm += delta
	var now := Time.get_ticks_usec()
	if _warm < 2.0 or get_tree().paused or map == null:
		_last = 0
		return
	var tag := "dormant"
	if map.completed:
		var front_stopped := map.landing_garden._frontier.is_empty() or map.landing_garden.cells.size() >= map.landing_garden.capacity
		tag = "revived" if front_stopped and map.world._dirty.is_empty() else "far_island_growth"
	elif map.stage == 3:
		tag = "wind_and_growth"
	elif map.stage == 2:
		tag = "root_growth" if p.rooting else "first_growth"
	elif map.stage == 1:
		tag = "companions"
	if not _frames.has(tag):
		_frames[tag] = {"time": [], "gpu": [], "draws": []}
	if _last > 0:
		_frames[tag].time.append((now - _last) / 1000.0)
		_frames[tag].gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		_frames[tag].draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_last = now

func finish() -> void:
	set_process(false)
	var report: Array[Dictionary] = []
	for tag: String in _frames:
		var row: Dictionary = _frames[tag]
		if (row.time as Array).is_empty():
			continue
		row.time.sort()
		row.gpu.sort()
		row.draws.sort()
		var total := 0.0
		for value: float in row.time:
			total += value
		var count := (row.time as Array).size()
		var at := int(count * 0.95)
		var over_budget := 0
		for value: float in row.time:
			if value > 10.0:
				over_budget += 1
		var result := {"phase": tag, "frames": count, "mean_ms": total / count, "p95_ms": row.time[at], "max_ms": row.time[-1], "over_10ms_frames": over_budget, "gpu_p95_ms": row.gpu[at], "draw_calls_p95": row.draws[at]}
		report.append(result)
		print("BENCH ", JSON.stringify(result))
	if _bench_out != "":
		var file := FileAccess.open(_bench_out, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"device": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(get_viewport().get_visible_rect().size), "vsync": "disabled", "fps_cap": 0, "save_isolated": true, "phases": report}, "\t"))
	await super.finish()
