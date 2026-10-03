class_name MyceliumGarden
extends Node3D
## 菌毯的逻辑前沿与绘制共享出生时间；暂停时两者一起停，单批次有硬上限。
signal pulse_sent
signal soil_restored(cell: Vector3i)
const CAPACITY := 384
const CELL := 0.5
var world: VoxelWorld
var capacity := CAPACITY
var elapsed := 0.0
var growing := false
var origin := Vector3.ZERO
var credits := 0
var cells: Dictionary = {}
var pulses := 0
var _batch: MultiMesh
var _material: ShaderMaterial
var _frontier: Array[Vector2i] = []
var _seen: Dictionary = {}
var _growth_clock := 0.0
var _root_clock := 0.0
var _ripening: Array[Vector2i] = []
var restored := 0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_batch = MultiMesh.new()
	_batch.transform_format = MultiMesh.TRANSFORM_3D
	_batch.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * CELL * 1.65
	_batch.mesh = quad
	_batch.instance_count = capacity
	_batch.visible_instance_count = 0
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/mycelium.gdshader")
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _batch
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func begin(at: Vector3, spores: int) -> void:
	if growing:
		credits = mini(credits + spores * 10, capacity)
		return
	origin = at
	credits = spores * 10
	growing = true
	_frontier.append(Vector2i.ZERO)
	_seen[Vector2i.ZERO] = true
	_material.set_shader_parameter("pulse_origin", origin)

func contains(at: Vector3, mature := true) -> bool:
	var c := Vector2i(roundi((at.x - origin.x) / CELL), roundi((at.z - origin.z) / CELL))
	if not cells.has(c):
		return false
	var entry: Dictionary = cells[c]
	return absf(at.y - (entry.position as Vector3).y) < 1.0 and (not mature or elapsed - float(entry.born) > 1.2)

func resonate(at: Vector3, active: bool, delta: float) -> void:
	if not active or not contains(at):
		_root_clock = 0.0
		return
	_root_clock += delta
	if _root_clock < 0.85 or cells.size() >= capacity:
		return
	_root_clock -= 0.85
	credits = mini(credits + 12, capacity)
	pulses += 1
	_material.set_shader_parameter("pulse_time", elapsed)
	_material.set_shader_parameter("pulse_origin", Vector3(at.x, origin.y, at.z))
	pulse_sent.emit()

func _physics_process(delta: float) -> void:
	if not growing:
		return
	# 出生演出先展开菌丝，再改变原生土壤；每帧至多成熟两格。
	for i in 2:
		if _ripening.is_empty():
			break
		var entry: Dictionary = cells[_ripening[0]]
		if elapsed - float(entry.born) < 1.2:
			break
		_ripening.pop_front()
		var soil: Vector3i = entry.soil
		if world.get_block(soil) in [Blocks.DIRT, Blocks.LOOSE]:
			world.set_block(soil, Blocks.GRASS)
			restored += 1
			soil_restored.emit(soil)
	_growth_clock -= delta
	if _growth_clock > 0.0 or credits <= 0:
		return
	_growth_clock = 0.15
	# 每步最多两次地表探测。岩石、悬空和不适合的地面会截断前沿。
	for i in 2:
		if _frontier.is_empty() or credits <= 0 or cells.size() >= capacity:
			break
		var c: Vector2i = _frontier.pop_front()
		if Vector2(c).length() * CELL > 6.4:
			continue
		var p := origin + Vector3(c.x * CELL, 0, c.y * CELL)
		# 从低于大部分树冠的位置探测地表，半米台阶仍在范围内。
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.65, p + Vector3.DOWN * 2.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.75:
			continue
		var type := world.vget(world.to_v(hit.position - hit.normal * 0.02))
		if type not in [Blocks.GRASS, Blocks.DIRT, Blocks.LOOSE]:
			continue
		var at: Vector3 = hit.position + hit.normal * 0.012
		var phase := fposmod(c.x * 0.75488 + c.y * 0.56984, 1.0)
		var normal: Vector3 = hit.normal
		var tangent := Vector3.RIGHT.slide(normal).normalized()
		var basis := Basis(tangent, normal.cross(tangent), normal)
		var n := cells.size()
		_batch.set_instance_transform(n, Transform3D(basis, at))
		_batch.set_instance_custom_data(n, Color(elapsed, phase, 0, 0))
		cells[c] = {"born": elapsed, "position": at, "soil": world.world_to_voxel(hit.position - hit.normal * 0.02)}
		_ripening.append(c)
		_batch.visible_instance_count = cells.size()
		credits -= 1
		for d in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = c + d
			if not _seen.has(next):
				_seen[next] = true
				_frontier.append(next)

func _process(delta: float) -> void:
	elapsed += delta
	_material.set_shader_parameter("elapsed", elapsed)
	_material.set_shader_parameter("motion_amount", 0.0 if bool(Settings.get_v("reduce_motion")) else 1.0)
