class_name SporeSwarm
extends Node3D
## 有边界的路径记忆 + 惯性跟随；孢丝摆动使用同一个批次材质。
signal settled(at: Vector3, spores: int)

const CAPACITY := 12
const TRAIL_LIMIT := 80
var leader: MorphBall
var wind := Vector3(0.055, 0.0, 0.025)
var gathering := false
var deposited := false
var elapsed := 0.0
var settle_time := 0.0
var _bed := Vector3.ZERO
var _trail: Array[Vector3] = []
var _spores: Array[Dictionary] = []
var _batch: MultiMesh
var _material: ShaderMaterial
var _ground_clock := 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_batch = MultiMesh.new()
	_batch.transform_format = MultiMesh.TRANSFORM_3D
	_batch.use_custom_data = true
	_batch.mesh = SporeVisual.mesh(0, true)
	_batch.instance_count = CAPACITY
	_batch.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _batch
	_material = SporeVisual.material()
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func count() -> int:
	return 0 if deposited else _spores.size()

func positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for s in _spores:
		result.append(s.position)
	return result

func wake(at: Vector3, amount := 1) -> int:
	if deposited and settle_time > 4.2:
		_spores.clear()
		_trail.clear()
		gathering = false
		deposited = false
		settle_time = 0.0
		set_process(true)
		set_physics_process(true)
	if gathering or deposited:
		return 0
	var added := mini(amount, CAPACITY - count())
	for i in added:
		var index := _spores.size()
		_spores.append({"position": at + Vector3(i * 0.09, 0.12, 0), "velocity": Vector3.ZERO, "target": at, "born": elapsed, "phase": index * 2.39996, "yaw": 0.0})
		_batch.set_instance_custom_data(index, Color(index * 0.47, 0, 0, 0))
	_batch.visible_instance_count = _spores.size()
	return added

func gather(at: Vector3, required := 3) -> bool:
	if gathering or deposited or count() < required or leader.global_position.distance_to(at) > 2.0:
		return false
	gathering = true
	_bed = at
	settle_time = 0.0
	return true

func _physics_process(delta: float) -> void:
	if not is_instance_valid(leader):
		return
	var p := leader.global_position
	if _trail.is_empty() or _trail[0].distance_to(p) > 12.0:
		_trail.clear()
		_trail.append(p)
	if _trail[0].distance_to(p) > 0.16:
		_trail.push_front(p)
		if _trail.size() > TRAIL_LIMIT:
			_trail.pop_back()
	_ground_clock -= delta
	if _ground_clock > 0.0 or gathering:
		return
	_ground_clock = 1.0 / 6.0
	for i in _spores.size():
		var s := _spores[i]
		var target := _path_point(0.72 + i * 0.56)
		var side := Vector3(leader._move_dir.z, 0, -leader._move_dir.x)
		target += side * (0.14 if i % 2 == 0 else -0.14)
		var ray := PhysicsRayQueryParameters3D.create(target + Vector3.UP, target + Vector3.DOWN * 3.0, 1, [leader.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			target.y = maxf(target.y - 0.06, (hit.position as Vector3).y + 0.26)
		s.target = target

func _path_point(distance: float) -> Vector3:
	var previous := leader.global_position
	for point in _trail:
		var length := previous.distance_to(point)
		if length >= distance and length > 0.001:
			return previous.lerp(point, distance / length)
		distance -= length
		previous = point
	return previous

func _process(delta: float) -> void:
	elapsed += delta
	_material.set_shader_parameter("elapsed", elapsed)
	_material.set_shader_parameter("wind", wind)
	var reduced := bool(Settings.get_v("reduce_motion"))
	_material.set_shader_parameter("motion_amount", 0.0 if reduced else 1.0)
	if gathering:
		settle_time += delta
	var all_at_rest := true
	for i in _spores.size():
		var s := _spores[i]
		var target: Vector3 = s.target
		if gathering:
			# 每枚孢子略晚加入，螺旋由游动收拢为落地，不瞬移、不同时缩成一点。
			var local_time := maxf(settle_time - i * 0.13, 0.0)
			var radius := maxf(0.07, 0.82 * exp(-local_time * 1.5))
			var angle: float = s.phase + local_time * 1.6
			target = _bed + Vector3(cos(angle) * radius, 0.06 + 0.28 * exp(-local_time), sin(angle) * radius)
			all_at_rest = all_at_rest and local_time > 2.0 and (s.position as Vector3).distance_to(_bed) < 0.18
		elif not reduced:
			target += wind * 0.5 + Vector3(0, sin(elapsed * 2.0 + float(s.phase)) * 0.055, 0)
		var omega := 7.0 if gathering else 5.2 - i * 0.12
		var offset: Vector3 = s.position - target
		var temp: Vector3 = (s.velocity + offset * omega) * delta
		var decay := exp(-omega * delta)
		s.position = target + (offset + temp) * decay
		s.velocity = (s.velocity - temp * omega) * decay
		var v: Vector3 = s.velocity
		if Vector2(v.x, v.z).length() > 0.04:
			s.yaw = lerp_angle(s.yaw, atan2(-v.x, -v.z), 1.0 - exp(-6.0 * delta))
		var born_scale := smoothstep(0.0, 0.55, elapsed - float(s.born))
		var fade := 1.0 - smoothstep(2.8, 4.2, settle_time) if deposited else 1.0
		var size := maxf(0.0001, (0.31 + (i % 3) * 0.03) * born_scale * fade)
		var bank := clampf(v.dot(Vector3.RIGHT.rotated(Vector3.UP, s.yaw)) * -0.08, -0.20, 0.20) if not reduced else 0.0
		var basis := Basis(Vector3.UP, s.yaw) * Basis(Vector3.FORWARD, bank)
		_batch.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * size), s.position))
	if gathering and not deposited and all_at_rest:
		deposited = true
		settled.emit(_bed, _spores.size())
	if deposited and settle_time > 4.2:
		_batch.visible_instance_count = 0
		set_process(false)
		set_physics_process(false)
