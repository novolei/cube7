class_name AreaWindtrace
extends Node3D
## 风痕群岛：沿用 Cube7 的体素地形与美术，只改变关卡和生命连接玩法。
signal stage_changed
var player: MorphBall
var world: VoxelWorld
var decor: Decor
const BASE := Vector3(21, 8, 24)
const SIZE := Vector3i(84, 48, 96)
# 每座岛各自独立；负空间和高差用于读路，不把关卡铺成一片大地形。
const ISLANDS := [
	{"center": Vector2(0, 0), "radius": Vector2(6.2, 6.2), "height": 0.0},
	{"center": Vector2(0, -11), "radius": Vector2(3.4, 2.9), "height": 2.5, "terrace": true},
	{"center": Vector2(9.6, -2.5), "radius": Vector2(2.8, 3.0), "height": 0.5},
	{"center": Vector2(-9.8, -8.8), "radius": Vector2(1.8, 1.6), "height": 2.0},
	{"center": Vector2(-10.4, 4.8), "radius": Vector2(1.8, 3.8), "height": -0.5, "yaw": 0.5, "terrace": true},
	{"center": Vector2(10.8, 8), "radius": Vector2(2.8, 2.5), "height": -1.0, "cut": Vector3(0.75, 0.25, 0.58)},
]
var swarm: SporeSwarm
var garden: MyceliumGarden
var bed := Vector3.ZERO
var wind_column: Fan
var stage := 0
var completed := false
var plants_open := 0
var _pods: Array[Dictionary] = []
var _plants: Array[Dictionary] = []
var _elapsed := 0.0
var _hint_clock := 0.0
var _bed_petals: Array[MeshInstance3D] = []
var _trees: Array[Dictionary] = []
var _sprouting: Dictionary = {}
var _crown_clock := 0.0
var crown_restored := 0
var landing_garden: MyceliumGarden
var branch_garden: MyceliumGarden
var _satellite_gardens: Array[MyceliumGarden] = []
var _carriers: MultiMesh
var _carrier_material: ShaderMaterial
var _wind_birth := -1.0
var _launch_saved := false
const WIND_FOOT := Vector2(0, -3.7)

func terrain_height(x: float, z: float) -> float:
	for island: Dictionary in ISLANDS:
		if _island_distance(Vector2(x, z), island) <= 1.0:
			return _island_height(Vector2(x, z), island)
	return 0.0

func _island_distance(point: Vector2, island: Dictionary) -> float:
	var d := (point - (island.center as Vector2)).rotated(-float(island.get("yaw", 0.0))) / (island.radius as Vector2)
	if island.has("cut"):
		var cut: Vector3 = island.cut
		if d.distance_to(Vector2(cut.x, cut.y)) < cut.z:
			return 1.1
	var angle := atan2(d.y, d.x)
	return d.length() / (0.97 + sin(angle * 3.0 + 0.8) * 0.035 + sin(angle * 5.0) * 0.025)

func _island_height(point: Vector2, island: Dictionary) -> float:
	var offset := point - (island.center as Vector2)
	return float(island.height) + (0.5 if bool(island.get("terrace", false)) and offset.y < -0.7 else 0.0)

func ground_point(x: float, z: float) -> Vector3:
	return BASE + Vector3(x, terrain_height(x, z), z)

func spawn_position() -> Vector3:
	return ground_point(0, 4.4) + Vector3.UP * 0.6

func build(p: MorphBall, w: VoxelWorld) -> void:
	player = p
	world = w
	world.setup(SIZE)
	_build_terrain()
	_build_landmarks()
	bed = ground_point(0, 0) + Vector3.UP * 0.03
	_build_bed()
	for pos in [Vector2(-1.7, 3), Vector2(2.2, 1.8), Vector2(-3, -0.3)]:
		_build_pod(ground_point(pos.x, pos.y))
	for pos in [Vector2(-2.7, -0.3), Vector2(2.9, -0.5), Vector2(0, -3.6)]:
		_build_plant(ground_point(pos.x, pos.y))
	swarm = SporeSwarm.new()
	swarm.name = "Companions"
	swarm.leader = player
	add_child(swarm)
	garden = MyceliumGarden.new()
	garden.world = world
	garden.name = "LivingCarpet"
	add_child(garden)
	garden.soil_restored.connect(_on_soil_restored)
	landing_garden = MyceliumGarden.new()
	landing_garden.world = world
	landing_garden.capacity = 200
	landing_garden.name = "FarIslandCarpet"
	add_child(landing_garden)
	landing_garden.soil_restored.connect(_on_soil_restored)
	branch_garden = MyceliumGarden.new()
	branch_garden.world = world
	branch_garden.capacity = 160
	branch_garden.name = "QuietIslandCarpet"
	add_child(branch_garden)
	branch_garden.soil_restored.connect(_on_soil_restored)
	_build_wind_seeds()
	swarm.settled.connect(func(at: Vector3, count: int) -> void:
		garden.begin(at, count)
		stage = maxi(stage, 2)
		_hint_clock = 0.0
		if stage < 3:
			Music.set_default("puzzle")
		stage_changed.emit()
		Sfx.play("rebuild", at, -15.0, 0.0, 0.88)
		GameState.rumble(0.12, 0.06, 0.08))
	garden.pulse_sent.connect(func() -> void:
		Sfx.play("rebuild", player.global_position, -19.0, 0.025, 0.82)
		GameState.rumble(0.10, 0.035, 0.09))
	wind_column = Fan.new()
	wind_column.name = "BreathingReed"
	wind_column.position = ground_point(WIND_FOOT.x, WIND_FOOT.y) + Vector3.UP * 4.5
	wind_column.box_size = Vector3(5.5, 9.0, 4.8)
	wind_column.strength = 6.0
	wind_column.max_rise_speed = 3.0
	wind_column.is_powered = false
	add_child(wind_column)
	# 风从植物的叶脉间升起；沿用既有物理气流，去掉工厂蓝光的外观。
	wind_column._ps.mesh = SporeVisual.mesh(0)
	wind_column._ps.scale_amount_min = 0.035
	wind_column._ps.scale_amount_max = 0.06
	wind_column._ps.material_override = SporeVisual.material()
	wind_column._ps.amount = 16
	wind_column._ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sky := SkyWorld.new()
	sky.name = "CloudSea"
	sky.center = Vector3(BASE.x, 0, BASE.z)
	sky.sea_height = -30.0
	add_child(sky)
	GameState.set_objective(0, "循着风，寻找仍在沉睡的生命")

func interact() -> bool:
	if get_tree().paused:
		return false
	for pod in _pods:
		if not pod.awake and player.global_position.distance_to(pod.position) <= 2.0:
			if swarm.wake(pod.position + Vector3.UP * 0.25, 2) == 0:
				return false
			pod.awake = true
			var root: Node3D = pod.node
			var tween := create_tween()
			tween.tween_property(root, "scale", Vector3(1.2, 0.3, 1.2), 0.65).set_trans(Tween.TRANS_SINE)
			Sfx.play("checkpoint", pod.position, -15.0, 0.15, 1.06)
			player.set_mood("happy", 0.7)
			GameState.rumble(0.08, 0.025, 0.06)
			stage = maxi(stage, 1)
			GameState.set_objective(1, "让相伴的孢子找到可以扎根的地方")
			stage_changed.emit()
			return true
	if swarm.gather(bed, 1 if garden.growing else 3):
		Sfx.play("rebuild", bed, -16.0, 0.0, 1.05)
		GameState.set_objective(2, "生命落地后，试着与它一同呼吸")
		return true
	return false

func context_hint() -> String:
	for pod in _pods:
		if not pod.awake and player.global_position.distance_to(pod.position) <= 2.0:
			return "唤醒沉睡的孢子"
	if player.global_position.distance_to(bed) <= 2.0 and not swarm.gathering:
		if garden.growing:
			return "把新的同行者送入菌床" if swarm.count() > 0 else ""
		return "让孢子汇入菌床" if swarm.count() >= 3 else "菌床还需要几位同行者"
	return ""

func _physics_process(delta: float) -> void:
	if garden == null:
		return
	garden.resonate(player.global_position, player.rooting, delta)
	if stage == 3 and not _launch_saved and player.grounded and player.global_position.distance_to(ground_point(WIND_FOOT.x, WIND_FOOT.y)) < 1.5:
		_launch_saved = true
		GameState.set_checkpoint(ground_point(WIND_FOOT.x, WIND_FOOT.y) + Vector3.UP * 0.6, -1)
	_hint_clock += delta
	if stage == 2 and _hint_clock > 18.0 and garden.credits == 0:
		GameState.set_objective(2, "菌丝停在干燥处 · 根息能把脉动送得更远")
		stage_changed.emit()
		_hint_clock = 0.0
	if not completed and stage == 3 and player.grounded and _on_island(player.global_position, 1):
		completed = true
		GameState.set_checkpoint(player.global_position, -1)
		landing_garden.begin(ground_point(0, -11) + Vector3.UP * 0.03, 20)
		_trees[3].awake = true
		Music.set_default("bright")
		GameState.set_objective(4, "风痕已苏醒 · 生命从这座岛走向下一座岛")
		stage_changed.emit()
		Sfx.play("rebuild_done", Vector3.INF, -14.0, 0.0, 0.94)
	if completed and not branch_garden.growing and player.grounded and _on_island(player.global_position, 2):
		branch_garden.begin(ground_point(9.6, -2.5) + Vector3.UP * 0.03, 16)
		_trees[4].awake = true
		Sfx.play("checkpoint", player.global_position, -17.0, 0.0, 1.10)
	_crown_clock -= delta
	if _crown_clock <= 0.0:
		_crown_clock = 0.12
		_grow_crowns()

func _on_island(at: Vector3, index: int) -> bool:
	var island: Dictionary = ISLANDS[index]
	return _island_distance(Vector2(at.x - BASE.x, at.z - BASE.z), island) < 0.92 and absf(at.y - BASE.y - float(island.height) - 0.5) < 0.9

func _process(delta: float) -> void:
	_elapsed += delta
	if garden == null:
		return
	for n in _plants.size():
		var plant: Dictionary = _plants[n]
		if not plant.awake and garden.contains(plant.position + Vector3.UP * 0.3):
			plant.awake = true
			_trees[n].awake = true
			plants_open += 1
			Sfx.play("checkpoint", plant.position, -19.0, 0.3, 0.85 + plants_open * 0.08)
		plant.open = move_toward(plant.open, 1.0 if plant.awake else 0.0, delta * 0.55)
		for i in (plant.leaves as Array).size():
			var leaf: Node3D = plant.leaves[i]
			var a := i * TAU / 7.0
			leaf.rotation = Vector3(lerpf(-0.08, -1.02, plant.open), a, 0)
			if not bool(Settings.get_v("reduce_motion")):
				leaf.rotation.x += sin(_elapsed * 1.5 + i * 0.7) * 0.025 * float(plant.open)
	if plants_open == _plants.size() and stage < 3:
		stage = 3
		_wind_birth = _elapsed
		_carriers.visible_instance_count = 12
		wind_column.set_powered(true)
		GameState.unlock_form(MorphBall.BUBBLE)
		# 叶片恢复后能维持本岛的生长，扎根不是无限按住的重复劳动。
		garden.credits = MyceliumGarden.CAPACITY
		GameState.set_objective(3, "舒展伞息 · 随苏醒的风抵达对岸")
		stage_changed.emit()
	_carry_wind_seeds()
	for i in _bed_petals.size():
		_bed_petals[i].scale = Vector3.ONE * (1.0 + (0.10 * sin(_elapsed * 1.3 - i * 0.55) if swarm.count() > 0 and not bool(Settings.get_v("reduce_motion")) else 0.0))
	for cell: Vector3i in _sprouting.keys():
		var age := _elapsed - float(_sprouting[cell])
		var slot: Array = decor._slots[cell]
		var mm: MultiMesh = (decor._mm[slot[0]] as MultiMeshInstance3D).multimesh
		var original: Transform3D = slot[2]
		var growth := smoothstep(0.0, 0.65, age)
		mm.set_instance_transform(slot[1], Transform3D(original.basis.scaled(Vector3.ONE * maxf(0.0001, growth)), original.origin))
		if growth >= 1.0:
			_sprouting.erase(cell)

func _on_soil_restored(cell: Vector3i) -> void:
	if decor._slots.has(cell):
		_sprouting[cell] = _elapsed
		var slot: Array = decor._slots[cell]
		var original: Transform3D = slot[2]
		(decor._mm[slot[0]] as MultiMeshInstance3D).multimesh.set_instance_transform(slot[1], Transform3D(original.basis.scaled(Vector3.ONE * 0.0001), original.origin))

func _grow_crowns() -> void:
	# 一次只长八个体素，沿用世界的重建预算，树冠从下往上展开。
	var budget := 8
	for tree in _trees:
		if not tree.awake:
			continue
		while tree.next < (tree.crown as Array).size() and budget > 0:
			var point: Vector3i = tree.crown[tree.next]
			var at := world.vcenter(point)
			if player.global_position.distance_to(at) < 0.85:
				break
			tree.next += 1
			if world.vget(point) == Blocks.AIR:
				world.vset(point, Blocks.PINE)
				crown_restored += 1
			budget -= 1

func _build_sleeping_tree(at: Vector3, height: int, radius: float, rng: RandomNumberGenerator) -> void:
	var root := world.to_v(at)
	world.put_tree(root, height, radius, "pine", rng)
	var crown: Array[Vector3i] = []
	var extent := ceili(radius / VoxelWorld.VOXEL) + 4
	for y in range(root.y, root.y + height + extent):
		for z in range(root.z - extent, root.z + extent + 1):
			for x in range(root.x - extent, root.x + extent + 1):
				var point := Vector3i(x, y, z)
				if world.vget(point) == Blocks.PINE:
					crown.append(point)
					world.vset_raw(point, Blocks.AIR)
	_trees.append({"crown": crown, "awake": false, "next": 0})

func _build_terrain() -> void:
	# 岩层仍是原生 Cube7 数据与材质。参考图用于复苏后的生命密度。
	var rng := RandomNumberGenerator.new()
	rng.seed = 1003
	decor = Decor.new()
	add_child(decor)
	decor.setup(world)
	for x in range(8, SIZE.x - 8):
		for z in range(8, SIZE.z - 8):
			var point := Vector2(x * 0.5 + 0.25 - BASE.x, z * 0.5 + 0.25 - BASE.z)
			for island: Dictionary in ISLANDS:
				var radial := _island_distance(point, island)
				if radial > 1.0:
					continue
				var height := roundi((BASE.y + _island_height(point, island)) * 2.0)
				var bottom := height - 12 + roundi(radial * radial * 8.0)
				world.fill_column(x, z, bottom, height - 5, Blocks.CLIFF_B)
				world.fill_column(x, z, maxi(bottom, height - 4), height - 3, Blocks.CLIFF)
				world.fill_column(x, z, height - 2, height - 1, Blocks.DIRT)
				if rng.randf() < 0.72:
					var kind := "grass"
					if rng.randf() < 0.12:
						kind = "flower_white" if rng.randf() < 0.7 else "flower_yellow"
					decor.add(kind, Vector3i(x, height - 1, z), rng)
				break
	# 石块也使用同一套体素材质和实体碰撞。
	_voxel_box(Vector3(1.25, 0.35, -2.0), Vector3(1.0, 0.7, 1.5), Blocks.ROCK)
	_voxel_box(Vector3(-1.5, 0.3, 0.5), Vector3(0.5, 0.6, 1.0), Blocks.ROCK)
	for pos in [Vector2(-4.4, -2.4), Vector2(4.3, -2.8), Vector2(-3.6, 3.4), Vector2(-1.7, -12.3), Vector2(10.8, -3.6), Vector2(-9.8, -8.8), Vector2(-10.4, 4.8), Vector2(10.0, 8)]:
		_build_sleeping_tree(ground_point(pos.x, pos.y), 9 + _trees.size() % 3, 0.75 + (_trees.size() % 2) * 0.15, rng)

func _build_wind_seeds() -> void:
	for i in 3:
		var patch := MyceliumGarden.new()
		patch.world = world
		patch.capacity = 64
		patch.name = "WindGarden%d" % i
		add_child(patch)
		patch.soil_restored.connect(_on_soil_restored)
		_satellite_gardens.append(patch)
	_carriers = MultiMesh.new()
	_carriers.transform_format = MultiMesh.TRANSFORM_3D
	_carriers.use_custom_data = true
	_carriers.mesh = SporeVisual.mesh(0, true)
	_carriers.instance_count = 12
	for i in 12:
		_carriers.set_instance_custom_data(i, Color(i * 0.47, 0, 0, 0))
	_carriers.visible_instance_count = 0
	_carrier_material = SporeVisual.material()
	var batch := MultiMeshInstance3D.new()
	batch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	batch.multimesh = _carriers
	batch.material_override = _carrier_material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)

func _carry_wind_seeds() -> void:
	if _wind_birth < 0.0:
		return
	_carrier_material.set_shader_parameter("elapsed", _elapsed)
	var motion := not bool(Settings.get_v("reduce_motion"))
	_carrier_material.set_shader_parameter("motion_amount", 1.0 if motion else 0.0)
	var all_arrived := true
	for i in 3:
		var island: Dictionary = ISLANDS[i + 3]
		var center: Vector2 = island.center
		# 菌床落在树旁的土壤上；树干和半月岛的缺口都不是着陆点。
		center += Vector2(0.8, 0.4) if i == 0 else Vector2(0.9, -0.4)
		if i == 2:
			center = (island.center as Vector2) + Vector2(-1.0, 0.7)
		var destination := ground_point(center.x, center.y) + Vector3.UP * 0.10
		var arrived := true
		for n in 4:
			var t := clampf((_elapsed - _wind_birth - n * 0.22) / (5.0 + i * 2.0), 0.0, 1.0)
			arrived = arrived and t >= 1.0
			var at := (ground_point(0, -3.6) + Vector3.UP * 1.2).lerp(destination, smoothstep(0.0, 1.0, t))
			at.y += sin(t * PI) * (1.0 + i * 0.2)
			if motion:
				at.x += sin(t * TAU + n * 0.9) * 0.18 * sin(t * PI)
			var size := maxf(0.0001, 0.16 * (1.0 - smoothstep(0.92, 1.0, t)))
			_carriers.set_instance_transform(i * 4 + n, Transform3D(Basis().scaled(Vector3.ONE * size), at))
		if arrived and not _satellite_gardens[i].growing:
			_satellite_gardens[i].begin(destination, [1, 3, 2][i])
			_trees[5 + i].awake = true
		all_arrived = all_arrived and arrived
	if all_arrived:
		_carriers.visible_instance_count = 0
		_wind_birth = -1.0

func _build_landmarks() -> void:
	# 对岸的小菌床和一截断碑构成地标，给岛屿留足呼吸的空间。
	_voxel_box(Vector3(1.9, 3.0, -12.3), Vector3(0.5, 1.0, 0.5), Blocks.CLIFF_C)
	for i in 5:
		var a := i * TAU / 5.0
		_box(ground_point(0, -11) + Vector3(sin(a) * 0.6, 0.05, cos(a) * 0.6), Vector3(0.13, 0.065, 0.48), Color("8c9877"), false).rotation.y = a
	world.rebuild_all()
	decor.commit()
	# 出生时是沉睡的土岛。恢复同一格土壤后才让原有草花长出来。
	for cell: Vector3i in decor._slots:
		var slot: Array = decor._slots[cell]
		var original: Transform3D = slot[2]
		(decor._mm[slot[0]] as MultiMeshInstance3D).multimesh.set_instance_transform(slot[1], Transform3D(original.basis.scaled(Vector3.ONE * 0.0001), original.origin))
	# 小片露水是菌床的可读线索，避免地面发光箭头。
	_voxel_box(Vector3(-3.1, -0.12, -1.3), Vector3(1.0, 0.25, 1.0), Blocks.MOSS)
	_box(ground_point(-3.1, -1.3) + Vector3.UP * 0.012, Vector3(0.9, 0.015, 0.9), Color("789fa0"), false)

func _voxel_box(at: Vector3, size: Vector3, type: int) -> void:
	var low := Vector3i((BASE + at - size * 0.5) / VoxelWorld.CELL_M)
	var high := Vector3i((BASE + at + size * 0.5 - Vector3.ONE * 0.01) / VoxelWorld.CELL_M)
	world.fill_box(low, high, type)

func _build_pod(at: Vector3) -> void:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var seed := SporeVisual.make(1)
	seed.scale = Vector3(0.6, 0.45, 0.6)
	seed.position.y = 0.2
	root.add_child(seed)
	_pods.append({"position": at, "node": root, "awake": false})

func _build_bed() -> void:
	for i in 5:
		var a := i * TAU / 5.0
		var p := _box(bed + Vector3(sin(a) * 0.6, 0.03, cos(a) * 0.6), Vector3(0.13, 0.065, 0.48), Color("8c9877"), false)
		p.rotation.y = a
		_bed_petals.append(p)

func _build_plant(at: Vector3) -> void:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var leaves: Array[Node3D] = []
	for i in 7:
		var pivot := Node3D.new()
		root.add_child(pivot)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in 4:
			SporeVisual.cube(st, Vector3(0, 0.20 + j * 0.34, j * 0.04), Vector3(0.14 + sin(j * 0.9) * 0.10, 0.34, 0.12), Color("8ea478"))
		st.generate_normals()
		var blade := MeshInstance3D.new()
		blade.mesh = st.commit()
		blade.material_override = SporeVisual.material()
		pivot.add_child(blade)
		leaves.append(pivot)
	_plants.append({"position": at, "leaves": leaves, "awake": false, "open": 0.0})

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _box(at: Vector3, size: Vector3, color: Color, collision: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = at
	add_child(mi)
	if collision:
		mi.create_trimesh_collision()
	return mi
