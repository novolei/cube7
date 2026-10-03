extends Node
## 原生场景中的真实输入与完整生态循环，不直接赋值关卡完成或植物成熟。
var p: MorphBall
var map: AreaWindtrace
var failures: Array[String] = []
var passed := 0
var out := ""
var second_wave := false

func _ready() -> void:
	p = get_parent().player
	map = get_parent().level
	p.debug_override = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--surge-fps="):
			Engine.max_fps = int(arg.substr(12))
		if arg.begins_with("--surge-out="):
			out = arg.substr(12)
		if arg == "--surge-second-wave":
			second_wave = true
	_run()

func check(ok: bool, message: String) -> void:
	print(("[PASS] " if ok else "[FAIL] ") + message)
	if ok:
		passed += 1
	else:
		failures.append(message)

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func tap(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func walk(to: Vector3, seconds := 10.0) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		var d := to - p.global_position
		d.y = 0
		if d.length() < 0.45:
			p.debug_input = Vector2.ZERO
			await wait(0.25)
			return true
		p.debug_input = Vector2(d.z, -d.x).normalized() * clampf(d.length() * 0.6, 0.22, 1.0)
		await get_tree().physics_frame
	p.debug_input = Vector2.ZERO
	return false

func shot(name: String) -> void:
	if out == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(out)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))

func overview(name: String) -> void:
	if out == "" or DisplayServer.get_name() == "headless":
		return
	var previous := get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	get_parent().add_child(camera)
	camera.global_position = AreaWindtrace.BASE + Vector3(20, 21, 24)
	camera.look_at(AreaWindtrace.BASE + Vector3(0, -0.5, -2))
	camera.fov = 50
	camera.make_current()
	get_parent().hud.visible = false
	await shot(name)
	get_parent().hud.visible = true
	previous.make_current()
	camera.queue_free()

func revived_decor() -> int:
	var result := 0
	for cell: Vector3i in map.decor._slots:
		var slot: Array = map.decor._slots[cell]
		var mm: MultiMesh = (map.decor._mm[slot[0]] as MultiMeshInstance3D).multimesh
		if mm.get_instance_transform(slot[1]).basis.determinant() > 0.01:
			result += 1
	return result

func _run() -> void:
	await wait(1.5)
	var save_before := SaveGame.data.duplicate(true)
	print("===== Vex / 风痕生态循环 =====")
	check(p.ecology_mode and p.form_info(1).name == "根息", "Vex 使用孢核、根息、伞息的身份")
	check(p.grounded, "真实地形上的出生落地")
	check(not map.wind_column.is_powered and not GameState.unlocked_forms[2], "风与伞息在植物苏醒前不可用")
	check(map.garden.cells.is_empty() and map.swarm.count() == 0, "初始没有自动生成菌毯或同行者")
	check(map.world.get_block(map.world.world_to_voxel(map.bed - Vector3.UP * 0.05)) == Blocks.DIRT and revived_decor() == 0 and map.crown_restored == 0, "出生时土壤、草花和树冠仍在沉睡")
	check(map.world.vget(map.world.to_v(AreaWindtrace.BASE + Vector3(0, 0, -7))) == Blocks.AIR, "两岛之间是真实空隙，没有连续大地形或隐藏通路")
	await shot("01_windtrace")
	await overview("00_dormant_islands")
	await tap("grab")
	check(map.swarm.count() == 0, "远离孢子时按唤醒键不会隔空获得孢子")
	var sources := 2 if second_wave else map._pods.size()
	for i in sources:
		check(await walk(map._pods[i].position), "实际滚动抵达第 %d 处孢子" % (i + 1))
		await tap("grab")
		await wait(0.45)
		check(map.swarm.count() == (i + 1) * 2, "输入唤醒第 %d 处并生成小孢子" % (i + 1))
	await shot("02_companions")
	check(not map.swarm.gather(map.bed), "离开菌床不能汇聚")
	check(await walk(map.ground_point(3.5, 3.5)), "同行者跟随拐弯路径")
	var before := map.swarm.positions()
	await wait(0.4)
	var after := map.swarm.positions()
	var moved := 0.0
	var spread := 0.0
	for i in after.size():
		moved += before[i].distance_to(after[i])
		spread = maxf(spread, p.global_position.distance_to(after[i]))
	check(moved > 0.01 and spread < 8.0, "停步后仍有轻微收拢，队伍保持有限迟滞")
	check(after[0].distance_to(after[-1]) > 0.2, "孢子错落跟随，没有重叠成一个点")
	var clock := map.swarm.elapsed
	get_tree().paused = true
	await wait(0.3)
	check(is_equal_approx(map.swarm.elapsed, clock), "暂停同时停止孢子位置与摆动时钟")
	get_tree().paused = false
	check(await walk(map.bed), "带着孢子实际抵达菌床")
	var reduced_before := bool(Settings.get_v("reduce_motion"))
	Settings.values.reduce_motion = true
	await wait(0.3)
	check(map.swarm.count() == sources * 2 and map.swarm.positions()[0].distance_to(p.global_position) < 4.0, "减弱动态效果仍保留小孢子的核心跟随机制")
	Settings.values.reduce_motion = reduced_before
	await tap("grab")
	await wait(0.7)
	check(map.swarm.gathering and not map.swarm.deposited and map.garden.cells.is_empty(), "汇聚先有可见游动，不提前生成菌毯")
	await shot("03_gathering")
	await wait(3.6)
	check(map.swarm.deposited and map.garden.cells.size() > 0, "实际落地后才开始菌毯蔓延")
	var young_count := map.garden.cells.size()
	await shot("04_first_growth")
	await wait(5.0)
	check(map.garden.cells.size() > young_count and map.garden.credits == 0, "菌毯逐片展开，并在初始养分用尽时停下")
	check(not map.wind_column.is_powered, "仅汇聚孢子不能跳过扎根共鸣")
	check(map.garden.restored > 0 and revived_decor() > 0, "菌丝成熟后恢复真实草地并让原有草花长出")
	check(not map.garden.contains(AreaWindtrace.BASE + Vector3(1.25, 0.38, -2.0), false), "菌毯前沿不能覆盖真实岩石")
	if second_wave:
		# 先送四枚再唤醒剩余两枚，覆盖真实玩家可能选择的分批路线。
		await walk(map.ground_point(-3, -1.5))
		check(await walk(map._pods[2].position), "首批落地后仍能回到未唤醒的孢子旁")
		await tap("grab")
		await wait(0.6)
		check(map.swarm.count() == 2 and not map.swarm.deposited, "第二批小孢子重新加入跟随")
		await walk(map.ground_point(-3, -1.5))
		check(await walk(map.bed), "带第二批同行者返回同一菌床")
		await tap("grab")
		await wait(4.8)
		check(map.swarm.deposited and map.stage == 2 and map.garden.pulses == 0, "成长中的菌床接受少量新同行者，保留已有生长和关卡阶段")
		await wait(2.5)
	clock = map.garden.elapsed
	var count := map.garden.cells.size()
	get_tree().paused = true
	await wait(0.3)
	check(is_equal_approx(map.garden.elapsed, clock) and map.garden.cells.size() == count, "暂停同时停止菌毯生长与材质演出")
	get_tree().paused = false
	await tap("form_2")
	p.debug_ability = true
	p.debug_input = Vector2(0, -1)
	var anchored := p.global_position
	await wait(0.65)
	check(p.rooting and p.global_position.distance_to(anchored) < 0.2, "扎根时输入移动不会拖走根部")
	check(p.attack == "" and not p._pounding and p._drilling_t <= 0.0, "根息没有钻掘、下砸或钻机攻击")
	p.debug_input = Vector2.ZERO
	await wait(4.0)
	check(map.garden.pulses > 0 and map.garden.cells.size() > count, "在已连通菌毯上扎根才传递脉动并延伸前沿")
	check(map.crown_restored > 0 and map.crown_restored < (map._trees[0].crown as Array).size() + (map._trees[1].crown as Array).size() + (map._trees[2].crown as Array).size(), "枯树逐层长回体素树冠，复苏不是瞬时整体换色")
	await shot("05_root_resonance")
	await wait(5.0)
	p.debug_ability = false
	check(map.plants_open == 3 and map.wind_column.is_powered and GameState.unlocked_forms[2], "覆盖三株植物后舒叶、恢复真实气流并解锁伞息")
	check(map.swarm.count() == 0 and map.garden.cells.size() <= MyceliumGarden.CAPACITY, "同行者已经汇入菌毯，批次数量有硬上限")
	await tap("form_1")
	check(await walk(map.ground_point(4.8, 2.6)), "可以离开菌毯继续探索")
	await tap("form_2")
	p.debug_ability = true
	var pulses := map.garden.pulses
	await wait(1.1)
	check(map.garden.pulses == pulses, "未连通的干燥地面不能凭空传递生命脉动")
	p.debug_ability = false
	await tap("form_1")
	check(await walk(map.ground_point(AreaWindtrace.WIND_FOOT.x, AreaWindtrace.WIND_FOOT.y)), "抵达苏醒植物之间的风道")
	print("WIND entry ", p.global_position, " form=", p.form, " grounded=", p.grounded, " zone=", map.wind_column.get_overlapping_bodies().size())
	check(map._launch_saved, "风道保留安全起飞检查点，跨岛失败可以就近重试")
	await tap("form_3")
	await wait(3.4)
	print("WIND lift ", p.global_position, " form=", p.form, " mass=", p.mass, " v=", p.linear_velocity, " zone=", map.wind_column.get_overlapping_bodies().size())
	check(not p.grounded and p.global_position.y > AreaWindtrace.BASE.y + 3.0, "伞息由真实物理气流托到高于对岸的高度（y=%.2f）" % p.global_position.y)
	p.debug_jump_held = true
	p.debug_jump_pressed = true
	check(await walk(map.ground_point(0, -9.7), 5.0), "借风与滑翔跨过真正的岛间空隙")
	p.debug_jump_held = false
	await wait(3.0)
	check(map.completed and p.global_position.y > AreaWindtrace.BASE.y + 2.5, "实际落到下一座小岛，完成生命连接循环（%s）" % p.global_position)
	await shot("06_awakened_valley")
	await wait(15.0)
	check(map.landing_garden.restored > 40 and map.landing_garden.growing, "Vex 真正抵达后，对岸的菌床才开始恢复草地")
	var all_sown := true
	for patch: MyceliumGarden in map._satellite_gardens:
		all_sown = all_sown and patch.restored > 0 and patch.cells.size() <= patch.capacity
	check(all_sown, "风携带的孢子真实落到三座远岛的土壤，出现稀疏的新生命")
	check(not map.garden.contains(AreaWindtrace.BASE + Vector3(0, 0, -7), false), "菌毯沿地表蔓延，不会把岛间虚空铺成地面")
	check(SaveGame.data == save_before, "新世界样章保持原章节存档不变")
	await overview("07_revived_islands")
	print("===== %d PASS · %d FAIL =====" % [passed, failures.size()])
	await finish()
	get_tree().quit(1 if not failures.is_empty() else 0)

func finish() -> void:
	Music.stop()
	for node: Node in Sfx.get_children() + Music.get_children() + [p._roll_sound]:
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			node.call("stop")
			node.set("stream", null)
	await wait(0.15)
