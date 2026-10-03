extends Node
## 标题画面测试：godot --path . -- --titletest[=截图目录]
## 鼠标点击能开始、菜单项不和标题叠在一起、鼠标能点菜单项

var fails: Array[String] = []
var out_dir := ""

func check(cond: bool, msg: String) -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + msg)
	if not cond:
		fails.append(msg)

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout

func _click(p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = p
	e.global_position = p
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := e.duplicate() as InputEventMouseButton
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame
	await get_tree().process_frame

func _move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	Input.parse_input_event(e)
	await get_tree().process_frame

func _shot(n: String) -> void:
	if out_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--titletest="):
			out_dir = a.substr(12)
			DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _run() -> void:
	print("===== 标题画面 =====")
	await _wait(3.5)
	var t := get_tree().current_scene
	var vp := get_viewport().get_visible_rect().size
	check(t._state == "press", "开场结束，等待开始（%s）" % t._state)
	await _click(vp * 0.5)
	await _wait(0.8)
	check(t._state == "menu", "鼠标左键点击画面 → 进入主菜单（%s）" % t._state)
	await _wait(0.8)
	await _shot("t1_menu")
	# 菜单项和标题文字不重叠
	var logo: Control = t._logo
	var lr := Rect2(logo.global_position, Vector2(900, 270) * logo.scale)
	var overlap := 0
	var target: Button
	for b in t._menu.get_children():
		var br := (b as Control).get_global_rect()
		if br.intersects(lr):
			overlap += 1
		if br.end.y > vp.y - 60:
			overlap += 1
		if (b as Button).text == "设置":
			target = b
	check(overlap == 0, "菜单项不和标题/底部提示叠在一起（%d 项菜单）" % t._menu.get_child_count())
	# 鼠标点“设置”
	if target:
		var c := target.get_global_rect().get_center()
		await _move(c)
		print("  target rect ", target.get_global_rect(), " hovered=", get_viewport().gui_get_hovered_control(), " win=", DisplayServer.window_get_size())
		await _click(c)
		await _wait(0.5)
		check(t._state == "settings", "鼠标点击菜单项“设置”有效（%s）" % t._state)
	if "--title-windtrace" in OS.get_cmdline_user_args():
		await _windtrace(t)
	if fails.is_empty():
		print("===== 全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
	Music.stop()
	for node: Node in Sfx.get_children() + Music.get_children():
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			node.call("stop")
			node.set("stream", null)
	await _wait(0.15)
	get_tree().quit(1 if not fails.is_empty() else 0)

func _windtrace(title: Node) -> void:
	var save_before := SaveGame.data.duplicate(true)
	title._settings.closed.emit()
	await _wait(0.4)
	var entry: Button
	for child in title._menu.get_children():
		if child is Button and child.text == "风痕 · 相伴而生":
			entry = child
	check(entry != null, "主菜单提供风痕样章入口")
	if entry == null:
		return
	await _move(entry.get_global_rect().get_center())
	await _click(entry.get_global_rect().get_center())
	await _wait(2.0)
	var game := get_tree().current_scene
	check(game.scene_file_path == "res://scenes/surge_preview.tscn", "实际鼠标点击进入风痕原生场景")
	if game.scene_file_path != "res://scenes/surge_preview.tscn":
		return
	check(game.player.ecology_mode and game.level is AreaWindtrace, "样章启用 Vex 与小群岛")
	var pause := (game.get_node("Hud") as Hud)._pause
	pause.open()
	await _wait(0.4)
	var back: Button
	for child in pause._list.get_children():
		if child is Button and child.text == "返回标题":
			back = child
	check(back != null, "样章提供返回标题操作")
	if back == null:
		pause.close()
		return
	await _move(back.get_global_rect().get_center())
	await _click(back.get_global_rect().get_center())
	await _wait(3.0)
	check(get_tree().current_scene.scene_file_path == "res://scenes/title.tscn" and not get_tree().paused, "实际鼠标操作从暂停返回标题并解除暂停")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "返回标题释放游戏鼠标捕获")
	check(GameState.player == null and GameState.camera == null, "退出游戏清理全局角色与镜头引用")
	check(SaveGame.data == save_before, "样章进入与返回保持原存档不变")
