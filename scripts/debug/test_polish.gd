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
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 0.5, 8)
	shape.shape = box
	floor_body.add_child(shape)
	get_parent().add_child(floor_body)
	floor_body.position = Vector3(16, 70, 16)
	_player.debug_override = false
	_player.allow_step = false
	_player.apply_form(MorphBall.BALL, false)
	_player.teleport(Vector3(16, 70.8, 16))
	await wait(0.5)
	check(_player.grounded, "Nova rests on a real physics platform")
	var camera: CameraRig = GameState.camera
	check(camera._pivot.distance_to(_player.global_position + Vector3.UP * 0.6) < 1.0, "Camera snaps cleanly after a long teleport")
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
	print("POLISH CHECK: %d failures" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)

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
	var world := VoxelWorld.new()
	world.render_group = 4 # Exercise phone-sized batches on the desktop too.
	world.size = Vector3i(32, 16, 32)
	get_parent().add_child(world)
	world.position = Vector3(300, 0, 0)
	world.setup(Vector3i(16, 8, 16))
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
