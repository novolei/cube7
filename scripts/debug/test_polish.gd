extends Node
## Real-scene check, safe for saves. Run at --polish-fps=30 and 144.
## godot --path . res://scenes/main.tscn -- --chapter=1 --debugscript=res://scripts/debug/test_polish.gd --polish-out=<directory>
var _fails: Array[String] = []
var _out := ""
var _player: MorphBall

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Flow.mode = "debug"
	_player = get_parent().player
	GameState.camera.yaw = get_parent().level.call("spawn_yaw")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--polish-out="):
			_out = arg.trim_prefix("--polish-out=")
		if arg.begins_with("--polish-fps="):
			Engine.max_fps = int(arg.trim_prefix("--polish-fps="))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("[PASS] " if ok else "[FAIL] ") + message)
	if not ok:
		_fails.append(message)

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events() # Synthetic events can arrive between two physics steps at 30Hz.

func tap(name: String) -> void:
	action(name, true)
	await wait(0.06)
	action(name, false)
	await wait(0.06)

func shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_out)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))

func solid_box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	get_parent().add_child(body)
	body.position = at
	return body

func _run() -> void:
	await wait(6.0)
	await shot("01_world")
	await tap("pause")
	await wait(0.5)
	var menu: PauseMenu = get_parent().hud._pause
	check(get_tree().paused and menu._panel.visible, "Real pause input opens the menu")
	await shot("02_pause")
	for i in 4:
		await tap("ui_down")
	await tap("ui_accept")
	await wait(0.6)
	check(menu._settings.is_visible_in_tree(), "Controller navigation opens shared settings")
	await shot("03_settings")
	await tap("ui_cancel")
	await tap("pause")
	check(not get_tree().paused, "Return path restores gameplay")
	if get_tree().paused:
		menu.close()
	var b := Button.new()
	get_parent().hud._root.add_child(b)
	for i in 100:
		UIKit.motion_scale(b, 0.978 if i % 2 == 0 else 1.012, 0.22)
	check(b.get_child_count() == 1, "Rapid UI retargets reuse one spring")
	var a := Vector2(0.978, 0)
	var c := a
	for i in 30:
		a = UISpring.step(a.x, a.y, 1.012, 0.22, 1.0 / 30)
	for i in 144:
		c = UISpring.step(c.x, c.y, 1.012, 0.22, 1.0 / 144)
	check(absf(a.x - c.x) < 0.0002 and absf(a.x - 1.012) < 0.0002, "Spring settles identically at 30/144 Hz")
	var old_reduced: bool = Settings.get_v("reduce_motion")
	Settings.values.reduce_motion = true
	UIKit.motion_scale(b, 0.5, 0.22)
	await wait(0.05)
	check(b.scale.is_equal_approx(Vector2.ONE), "Reduced motion removes UI zoom")
	Settings.values.reduce_motion = old_reduced
	b.queue_free()
	var nodes := Sfx.get_child_count()
	for i in 100:
		Sfx._last.clear()
		Sfx.play("break_soft", _player.global_position)
	check(Sfx.get_child_count() == nodes, "A 100-sound burst creates no audio nodes")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Movement")) == "SFX" and AudioServer.get_bus_send(AudioServer.get_bus_index("World")) == "SFX", "Movement and world have separate mix buses")
	check(AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter, "Master peak limiter is active")
	# Isolated physical platform above the existing level, without touching its voxel data.
	var floor_body := solid_box(Vector3(16, 70, 16), Vector3(8, 0.5, 8))
	_player.debug_override = false
	_player.allow_step = false
	_player.apply_form(MorphBall.BALL, false)
	_player.teleport(Vector3(16, 70.8, 16))
	await wait(0.5)
	check(_player.grounded, "Nova rests on a real physics platform")
	var camera: CameraRig = GameState.camera
	check(camera._pivot.distance_to(_player.global_position + Vector3.UP * 0.6) < 1.0, "Camera snaps cleanly after a long teleport")
	await _journey_feedback_check()
	# Roll off the edge, then press jump after leaving it.
	_player.teleport(Vector3(19.9, 70.65, 16))
	await wait(0.15)
	_player.linear_velocity = Vector3(5, 0, 0)
	for i in 45:
		await get_tree().physics_frame
		if not _player.grounded:
			break
	await get_tree().physics_frame
	action("jump", true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(_player.linear_velocity.y > 2.0, "Coyote jump works after rolling off an edge")
	action("jump", false)
	# Buffered landing: press before collision and keep held.
	_player.teleport(Vector3(16, 71.1, 16))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.linear_velocity = Vector3(0, -4, 0)
	_player._ground_timer = 0.0
	action("jump", true)
	var jumped := false
	for i in 12:
		await get_tree().physics_frame
		if _player.linear_velocity.y > 2.0:
			jumped = true
			break
	check(jumped, "Buffered input jumps on physical landing")
	action("jump", false)
	var before_cut := _player.linear_velocity.y
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(_player.linear_velocity.y < before_cut * 0.8, "Releasing jump shortens the rising arc")
	# The bubble retains its authored air-jump identity; a roll does not bypass gates.
	check(MorphBall.FORMS[MorphBall.BUBBLE].air_jumps == 2 and MorphBall.FORMS[MorphBall.BALL].air_jumps == 0, "Form-specific air jumps preserve level gates")
	_player.debug_override = true
	var speeds: Array[float] = []
	var strength := _player.countersteer_strength
	for damping in [0.0, strength]:
		_player.countersteer_strength = damping
		_player.debug_input = Vector2.ZERO
		_player.teleport(Vector3(16, 70.8, 16))
		await wait(0.4)
		_player.debug_input = Vector2(0, 1)
		var forward := _player._camera_dir(_player.debug_input).normalized()
		_player.linear_velocity = -forward * 6
		_player.angular_velocity = Vector3.ZERO
		for i in 6:
			await get_tree().physics_frame
		speeds.append(_player.linear_velocity.dot(-forward))
	_player.countersteer_strength = strength
	_player.debug_input = Vector2.ZERO
	check(speeds[1] < speeds[0] - 0.4, "Deliberate countersteering brakes actual rolling momentum")
	await _pc_control_check()
	for i in 6:
		_player.apply_form(i % 3, true)
		await get_tree().process_frame
	await wait(0.4)
	check(_player._visual_root.scale.is_equal_approx(Vector3.ONE * MorphBall.BODY), "Rapid form changes settle at the correct visual size")
	var life := Ambient.new()
	life.count = 1
	life.area_lo = _player.global_position
	life.area_hi = life.area_lo
	get_parent().add_child(life)
	await wait(0.4)
	check(life._flies[0].offset.length() > 0.02, "Nearby butterflies respond gently to the player")
	life.queue_free()
	await _touch_check()
	await _voxel_check()
	await _completion_check()
	print("POLISH CHECK: %d failures" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)

func _completion_check() -> void:
	_player.debug_override = false
	_player.apply_form(MorphBall.BALL, false)
	_player.teleport(Vector3(16, 70.8, 16))
	await wait(0.3)
	Flow.mode = "playtest" # Exercise the actual clear overlay, normally suppressed by debug mode.
	var goal := Goal.new()
	get_parent().add_child(goal)
	goal.global_position = _player.global_position
	action("move_right", true)
	await wait(0.15)
	var stopped_at := _player.global_position
	await wait(0.2)
	check(goal._done and get_tree().paused and stopped_at.distance_to(_player.global_position) < 0.01, "A real goal immediately pauses movement in its clear overlay before an overshoot")
	var hud: Hud = get_parent().hud
	check(not hud._coins.is_visible_in_tree() and not hud._forms_row.is_visible_in_tree() and not hud._prompts.is_visible_in_tree(), "The clear composition removes gameplay HUD and action hints")
	await wait(1.2)
	await shot("05_chapter_clear")
	action("move_right", false)
	await tap("ui_right")
	await tap("ui_accept")
	check(not get_tree().paused and hud._coins.is_visible_in_tree() and hud._forms_row.is_visible_in_tree(), "Controller continue-exploring restores gameplay and its HUD")

func _pc_control_check() -> void:
	var braking := _player.release_brake_strength
	var releases: Array[float] = []
	for strength in [0.0, braking]:
		_player.release_brake_strength = strength
		_player.teleport(Vector3(16, 70.8, 16))
		await wait(0.4)
		_player.linear_velocity = Vector3(5, 0, 0)
		_player.angular_velocity = Vector3.ZERO
		for i in 21:
			await get_tree().physics_frame
		releases.append(Vector2(_player.linear_velocity.x, _player.linear_velocity.z).length())
	_player.release_brake_strength = braking
	check(releases[1] < releases[0] - 0.5, "Releasing movement reduces actual ground overshoot")
	_player.teleport(Vector3(16, 70.8, 16))
	await wait(0.4)
	_player.linear_velocity = Vector3(5, 0, 0)
	_player._dash_t = 0.9
	for i in 21:
		await get_tree().physics_frame
	check(_player.linear_velocity.x > releases[1] + 0.5, "A committed dash keeps its momentum on release")
	_player._dash_t = 0.0
	var analog: Array[float] = []
	for strength in [0.25, 1.0]:
		_player.debug_input = Vector2.ZERO
		_player.teleport(Vector3(16, 70.8, 16))
		await wait(0.4)
		_player.debug_input = Vector2(0, -strength)
		for i in 45:
			await get_tree().physics_frame
		analog.append(Vector2(_player.linear_velocity.x, _player.linear_velocity.z).length())
	_player.debug_input = Vector2.ZERO
	check(analog[0] < analog[1] * 0.75, "A quarter stick movement stays slower than a full movement")
	var wall := solid_box(Vector3(18, 74, 16), Vector3(1, 8, 8))
	_player.teleport(Vector3(16, 70.8, 16))
	await wait(0.4)
	_player.debug_input = Vector2(0, -1)
	var highest := _player.global_position.y
	for i in 276:
		await get_tree().physics_frame
		highest = maxf(highest, _player.global_position.y)
	check(highest < 71.1, "Pushing a tall wall for 4.6 seconds cannot create an unrequested jump or teleport")
	_player.debug_input = Vector2.ZERO
	wall.queue_free()
	_player._charging = true
	_player._pounding = true
	_player._dash_t = 0.5
	_player.charged_ram = true
	_player._jump_buffer = 0.1
	_player._jump_rising = true
	_player.respawn_at(Vector3(17, 70.8, 16), -1, false)
	check(not _player._charging and not _player._pounding and not _player.charged_ram and _player._dash_t == 0.0 and _player._jump_buffer == 0.0 and not _player._jump_rising, "Respawn clears charged attacks and jump state")
	await wait(0.06)
	var camera: CameraRig = GameState.camera
	check(camera._pivot.distance_to(_player.global_position + Vector3.UP * 0.6) < 0.5, "A short respawn immediately restores a steady camera")
	await _camera_check()

func _camera_check() -> void:
	var camera: CameraRig = GameState.camera
	var old_distance := camera.distance
	var old_mouse_mode := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Desktop pointer movement must not steer the synthetic orbit check.
	var old_motion: bool = Settings.get_v("reduce_motion")
	var old_forms := GameState.unlocked_forms.duplicate()
	Settings.values.reduce_motion = false
	GameState.unlocked_forms = [true, true, true] as Array[bool]
	_player.teleport(Vector3(16, 70.8, 16))
	await wait(0.4)
	_player.freeze = true
	_player._move_dir = Vector3.RIGHT
	camera.yaw = 0.8
	camera.pitch = -0.9
	await tap("view_recenter")
	await wait(0.7)
	check(absf(angle_difference(camera.yaw, -PI / 2)) < 0.02 and absf(camera.pitch + 0.5) < 0.02, "Recenter input gently brings the view behind the rolling direction")
	camera.yaw = 0.8
	await tap("view_recenter")
	action("cam_left", true)
	await wait(0.08)
	action("cam_left", false)
	check(not camera._recenter_active and absf(angle_difference(camera.yaw, -PI / 2)) > 0.2, "Manual orbit immediately takes over a recenter transition")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.ctrl_pressed = true
	_player.apply_form(MorphBall.BALL, false)
	Input.parse_input_event(wheel)
	Input.flush_buffered_events()
	await wait(0.06)
	check(camera.distance < old_distance and _player.form == MorphBall.BALL, "Ctrl plus wheel adjusts the camera without switching forms")
	var zoomed := camera.distance
	wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	Input.parse_input_event(wheel)
	Input.flush_buffered_events()
	await wait(0.06)
	check(camera.distance == zoomed and _player.form != MorphBall.BALL, "The ordinary wheel retains its form-switching input")
	_player.apply_form(MorphBall.BALL, false)
	camera.distance = old_distance
	camera.yaw = -PI / 2
	camera.pitch = -0.5
	camera.reset_follow(_player.global_position)
	var wall := solid_box(Vector3(13, 74, 16), Vector3(0.4, 10, 8))
	await wait(0.5)
	var near_distance := camera._cur_dist
	check(camera._cam.global_position.x > 13.25 and near_distance < old_distance - 1.0, "A physical obstruction keeps the camera in front of a tall wall")
	wall.queue_free()
	await wait(0.12)
	check(camera._cur_dist > near_distance and camera._cur_dist < old_distance - 0.4, "Removing an obstruction reopens the view without an instant distance jump")
	await wait(1.2)
	check(camera._cur_dist > old_distance * 0.9, "The unobstructed view returns to its configured framing")
	_player.freeze = false
	Settings.values.reduce_motion = old_motion
	GameState.unlocked_forms = old_forms
	Input.mouse_mode = old_mouse_mode

func _journey_feedback_check() -> void:
	var cp := Checkpoint.new()
	cp.box_size = Vector3(2, 2, 2)
	get_parent().add_child(cp)
	cp.global_position = Vector3(16, 71.25, 16)
	await wait(0.1)
	check(cp._active and absf(GameState.checkpoint.y - 70.75) < 0.01, "A physical checkpoint records its floor instead of its trigger center")
	_player.respawn_at(GameState.checkpoint, -1, false)
	await wait(0.2)
	check(_player.grounded, "Checkpoint respawn restores ground control within 200 ms")
	cp.queue_free()
	var hud: Hud = get_parent().hud
	SaveGame.saved.emit()
	await wait(0.3)
	check(hud._save_toast.modulate.a > 0.9 and get_viewport().get_visible_rect().encloses(hud._save_toast.get_global_rect()), "Save feedback appears inside the viewport below the current objective")
	hud._queue.clear()
	hud._nova_time = 20.0
	var hint := TalkTrigger.new()
	hint.lines = PackedStringArray(["当前区域提示一", "当前区域提示二"])
	hint.box_size = Vector3(2, 2, 2)
	get_parent().add_child(hint)
	hint.global_position = _player.global_position
	await wait(0.1)
	hud._nova_time = 0.0
	await wait(0.07)
	check(hud._nova_text.get_parsed_text() == "当前区域提示一", "Entering a real area delivers its contextual hint")
	var active_text := hud._nova_text.get_parsed_text()
	_player.teleport(Vector3(19, 70.8, 16))
	await wait(0.1)
	check(hud._nova_text.get_parsed_text() == active_text and hud._nova_time > 0.0, "Leaving an area lets the current sentence finish")
	GameState.say("保留的旅程叙事")
	hud._nova_time = 0.0
	await wait(0.08)
	check(hud._nova_text.get_parsed_text() == "保留的旅程叙事" and hud._queue.is_empty(), "Stale area hints are skipped while narrative dialogue survives")
	GameState.say("已释放区域提示", hint)
	hint.queue_free()
	await get_tree().process_frame
	hud._nova_time = 0.0
	await wait(0.08)
	check(hud._queue.is_empty(), "Freed dialogue areas cannot leave dangling queued hints")
	await _guidance_check()
	hud._nova.hide()
	var marker: ObjectiveMarker = get_parent().level.get_node("ObjectiveMarker")
	var previous_reduced: bool = Settings.get_v("reduce_motion")
	Settings.values.reduce_motion = true
	var gem_pos := marker._gem.position
	var gem_rot := marker._gem.rotation
	await wait(0.15)
	check(marker._gem.position.is_equal_approx(gem_pos) and marker._gem.rotation.is_equal_approx(gem_rot), "Reduced motion freezes the world objective ornament")
	Settings.values.reduce_motion = previous_reduced
	var previous_complete := GameState.level_complete
	GameState.level_complete = true
	await wait(0.05)
	check(not marker.visible, "Completing the chapter removes the world objective beam")
	GameState.level_complete = previous_complete
	marker._on_objective(GameState.objective_index, GameState.objective_text, GameState.objective_pos)
	var foliage: Decor = get_parent().level.decor
	var material := (foliage._mm["grass"] as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var rendered_at := _player.get_global_transform_interpolated().origin
	check((material.get_shader_parameter("player_position") as Vector3).distance_to(rendered_at) < 0.1, "Batched foliage follows the interpolated player pose")
	_player.teleport(Vector3(16, 70.8, 16))
	await wait(0.3)
	var item := UsableItem.new()
	get_parent().add_child(item)
	item.global_position = Vector3(19.8, 70.6, 16)
	hud._grab_t = 0.0
	await wait(0.25)
	check(hud._grab_hint == "抓取", "Grab feedback covers the full reachable traction range")
	await tap("grab")
	check(_player.is_holding() and item.held and item.collision_layer == 0, "Real grab input picks up a hinted item outside the old 2.8m prompt range")
	await tap("grab")
	check(not _player.is_holding() and not item.held and item.linear_velocity.length() > 1.0, "The same input releases and physically throws the held item")
	item.queue_free()

func _guidance_check() -> void:
	var hud: Hud = get_parent().hud
	var previous := {"index": GameState.objective_index, "text": GameState.objective_text, "pos": GameState.objective_pos}
	_player.freeze = true
	_player.teleport(Vector3(16, 70.8, 16))
	hud._queue.clear()
	hud._nova_time = 20.0
	var hint := TalkTrigger.new()
	hint.lines = PackedStringArray(["延迟观察线索"])
	hint.delay_seconds = 0.5
	hint.until_objective = previous.index
	get_parent().add_child(hint)
	hint.global_position = _player.global_position
	await wait(0.12)
	check(not hint._done and hud._queue.is_empty(), "Puzzle hints leave time for independent observation")
	_player.teleport(Vector3(19, 70.8, 16))
	await wait(0.15)
	_player.teleport(Vector3(16, 70.8, 16))
	await wait(0.28)
	check(not hint._done and hud._queue.is_empty(), "Leaving and returning cannot reuse an earlier hint timer")
	await wait(0.3)
	check(hint._done and hud._queue.size() == 1, "A sustained visit delivers one delayed clue")
	_player.teleport(Vector3(19, 70.8, 16))
	await wait(0.1)
	_player.teleport(Vector3(16, 70.8, 16))
	await wait(0.6)
	check(hud._queue.size() == 1, "Revisiting a delivered hint does not repeat it")
	GameState.set_objective(previous.index + 1, "下一段旅程")
	hud._nova_time = 0.0
	await wait(0.1)
	check(hud._queue.is_empty() and hud._nova_text.get_parsed_text() != "延迟观察线索", "Advancing the objective discards queued puzzle advice")
	hint.queue_free()
	var waiting := TalkTrigger.new()
	waiting.delay_seconds = 0.4
	waiting.until_objective = previous.index + 1
	waiting.lines = PackedStringArray(["过时的谜题线索"])
	get_parent().add_child(waiting)
	waiting.global_position = _player.global_position
	await wait(0.12)
	GameState.set_objective(previous.index + 2, "已完成谜题")
	await wait(0.5)
	check(not waiting._done and hud._queue.is_empty(), "Solving the stage while waiting cancels its delayed hint")
	waiting.queue_free()
	var paused_hint := TalkTrigger.new()
	paused_hint.delay_seconds = 0.5
	paused_hint.lines = PackedStringArray(["暂停不计入停留时间"])
	get_parent().add_child(paused_hint)
	paused_hint.global_position = _player.global_position
	hud._nova_time = 20.0
	await wait(0.12)
	get_tree().paused = true
	await wait(0.6)
	check(not paused_hint._done, "Puzzle hint timers stop while gameplay is paused")
	get_tree().paused = false
	await wait(0.5)
	check(paused_hint._done and hud._queue.size() == 1, "The remaining hint delay resumes after returning to play")
	paused_hint.queue_free()
	GameState.set_objective(previous.index + 2, "同阶段已恢复供电")
	GameState.set_objective(previous.index + 1, "旧区域目标")
	check(GameState.objective_text == "同阶段已恢复供电" and GameState.objective_index == previous.index + 2, "A stage can refresh its instructions without regressing to an old objective")
	GameState.objective_index = previous.index
	GameState.objective_text = previous.text
	GameState.objective_pos = previous.pos
	GameState.objective_changed.emit(previous.index, previous.text, previous.pos)
	hud._queue.clear()
	hud._nova_time = 0.0
	_player.freeze = false

func touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame

func _touch_check() -> void:
	_player.debug_override = true
	var emulation := Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = false
	var controls := TouchControls.new()
	get_parent().hud._root.add_child(controls)
	controls.offset_left = 40 # Simulated display cutout.
	await get_tree().process_frame
	var origin := controls.global_position
	await touch(10, origin + controls._origin + Vector2(50, 0), true)
	await touch(11, origin + controls._buttons.jump[0], true)
	check(Input.get_action_strength("move_right") > 0.5 and Input.is_action_pressed("jump"), "Two touch fingers move and jump inside the safe area")
	await touch(12, origin + controls._buttons.jump[0], true)
	await touch(11, origin + controls._buttons.jump[0], false)
	check(Input.is_action_pressed("jump"), "Releasing one duplicate touch preserves the other finger")
	await touch(12, origin + controls._buttons.jump[0], false)
	check(not Input.is_action_pressed("jump") and Input.is_action_pressed("move_right"), "Jump release does not cancel the movement finger")
	controls.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not Input.is_action_pressed("move_right") and controls._held.is_empty(), "Losing focus releases all touch actions")
	await touch(13, origin + controls._buttons.jump[0], true)
	get_tree().paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(not controls.visible and not Input.is_action_pressed("jump"), "Any paused overlay hides touch controls and releases held buttons")
	get_tree().paused = false
	await get_tree().process_frame
	await shot("04_touch_layout")
	controls.queue_free()
	await get_tree().process_frame
	Input.emulate_mouse_from_touch = emulation

func _voxel_check() -> void:
	var cells := {Vector3i(-2, 0, 0): true, Vector3i(-1, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(1, 0, 1): true, Vector3i(2, 0, 1): true, Vector3i(1, 1, 1): true}
	var covered := {}
	var runs := VoxelChunk.collision_runs(cells)
	for box in runs:
		for x in range(int(box.position.x), int(box.end.x)):
			covered[Vector3i(x, int(box.position.y), int(box.position.z))] = true
	check(runs.size() == 4 and covered == cells and VoxelChunk.collision_runs({}).is_empty(), "Falling chunk collision merges adjacent cells without filling holes")
	var falling := VoxelChunk.new()
	for cell: Vector3i in cells:
		falling.blocks.append([(Vector3(cell) + Vector3.ONE * 0.5) * VoxelWorld.CELL_M, Blocks.DIRT])
	falling.freeze = true
	get_parent().add_child(falling)
	falling.global_position = Vector3(310, 20, 0)
	falling.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = (get_parent() as Node3D).get_world_3d().direct_space_state
	var solid := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(310.75, 22, 0.25), Vector3(310.75, 19, 0.25), 32))
	var hole := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(310.25, 22, 0.25), Vector3(310.25, 19, 0.25), 32))
	check(solid.get("collider") == falling and hole.is_empty(), "Merged native collision remains solid on cells and open through a gap")
	falling.queue_free()
	var world := VoxelWorld.new()
	world.render_group = 4 # Exercise phone-sized batches on the desktop too.
	world.size = Vector3i(32, 16, 32)
	get_parent().add_child(world)
	world.position = Vector3(300, 0, 0)
	world.setup(Vector3i(16, 8, 16))
	var foliage := Decor.new()
	world.add_child(foliage)
	foliage.setup(world)
	var grass_cell := Vector3i(2, 4, 2)
	world.set_block(grass_cell, Blocks.GRASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	foliage.add("grass", grass_cell, rng)
	foliage.commit()
	var grass_mesh := (foliage._mm["grass"] as MultiMeshInstance3D).multimesh
	var rooted := grass_mesh.get_instance_transform(0)
	world.set_block(grass_cell, Blocks.AIR)
	var hidden := grass_mesh.get_instance_transform(0).basis.x.length() == 0.0
	world.set_block(grass_cell, Blocks.GRASS)
	check(hidden and grass_mesh.get_instance_transform(0).is_equal_approx(rooted) and grass_mesh.instance_count == 1, "Destroyed foliage returns to its original batch slot when the ground is rebuilt")
	world.vfill(Vector3i(0, 0, 0), Vector3i(31, 0, 31), Blocks.BEDROCK)
	world.vfill(Vector3i(4, 1, 4), Vector3i(8, 2, 8), Blocks.DIRT)
	world.vset(Vector3i(6, 3, 6), Blocks.BEDROCK)
	world._rng.seed = 42
	var broken := world.break_sphere(world.vcenter(Vector3i(6, 2, 6)), 1.0, "impact", 16, Vector3.DOWN, false, 0.5)
	check(broken > 0 and world.vget(Vector3i(6, 1, 6)) == Blocks.DIRT and world.vget(Vector3i(6, 3, 6)) == Blocks.BEDROCK, "Sphere destruction respects its lower limit and indestructible materials")
	world.vfill(Vector3i(20, 8, 20), Vector3i(22, 8, 22), Blocks.DIRT)
	check(world._component(Vector3i(21, 8, 21), {}).size() == 9, "A small disconnected component can detach")
	world.vfill(Vector3i(20, 7, 20), Vector3i(22, 7, 22), Blocks.BEDROCK)
	check(world._component(Vector3i(21, 8, 21), {}).is_empty(), "An anchored component remains supported")
	# A dirt foundation is drillable, but forward tunneling must leave the route underfoot.
	world.vfill(Vector3i(12, 1, 16), Vector3i(27, 1, 23), Blocks.DIRT)
	world.vfill(Vector3i(20, 2, 16), Vector3i(21, 7, 23), Blocks.DIRT)
	world.flush_dirty()
	_player.world = world
	_player.apply_form(MorphBall.DRILL, false)
	for seed_value in [1, 2, 3]:
		world._rng.seed = seed_value
		_player.freeze = true
		_player.teleport(world.vcenter(Vector3i(19, 3, 19)))
		_player._move_dir = Vector3.RIGHT
		_player._drill(Vector3.RIGHT)
	check(world.vget(Vector3i(20, 1, 19)) == Blocks.DIRT and world.vget(Vector3i(20, 3, 19)) == Blocks.AIR, "Forward drilling opens the wall while preserving a drillable foundation")
	_player.world = get_parent().world
	var rb := VoxelRebuilder.new()
	rb.world = world
	get_parent().add_child(rb)
	var cell := Vector3i(7, 4, 7)
	var destination := world.voxel_center(cell)
	_player.freeze = true
	_player.teleport(destination)
	rb.add_cell(cell, Blocks.PAVING, 0, destination, destination + Vector3.UP, 0.0, 0.1)
	await wait(0.25)
	check(rb.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and world.get_block(cell) == Blocks.AIR, "Render-rate reconstruction waits instead of building into the player")
	_player.teleport(destination + Vector3.UP * 3.0)
	await wait(0.3)
	check(world.get_block(cell) == Blocks.PAVING and not is_instance_valid(rb), "Reconstruction commits its voxel and completes after the player moves clear")
	_player.freeze = false
	for i in 120:
		await get_tree().process_frame
		if world._dirty.is_empty():
			break
	await get_tree().physics_frame
	check(world._dirty.is_empty() and world._gdirty.is_empty(), "Budgeted partial rebuilds drain and commit every dirty group")
	var query := PhysicsRayQueryParameters3D.create(world.vcenter(Vector3i(6, 6, 6)), world.vcenter(Vector3i(6, 0, 6)), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty(), "Surviving terrain retains physical collision after a partial rebuild")
	world.queue_free()
