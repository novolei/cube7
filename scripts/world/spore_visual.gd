class_name SporeVisual
extends RefCounted
## Vex 的原生低面数造型。颜色、褶皱与柔软孢丝共用一个表面，无外部贴图。

static var _meshes: Dictionary = {}

static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/spore_silk.gdshader")
	return m

static func make(form: int) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh(form)
	n.material_override = material()
	return n

static func mesh(form: int = 0, follower := false) -> ArrayMesh:
	var key := form + (10 if follower else 0)
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_seed(st, form)
	if form == 1:
		for i in 7:
			var a := i * TAU / 7.0
			_ribbon(st, Vector3(sin(a) * 0.22, -0.24, cos(a) * 0.22), Vector3(sin(a) * 0.48, -0.38, cos(a) * 0.48), Vector3(sin(a) * 0.60, -0.39, cos(a) * 0.60), 0.09, Color("8f9f72"))
	elif form == 2:
		for i in 12:
			var a := i * TAU / 12.0
			var b := a + TAU / 12.0
			_tri(st, Vector3(0, 0.59, 0), Vector3(sin(a) * 0.76, 0.24, cos(a) * 0.76), Vector3(sin(b) * 0.76, 0.24, cos(b) * 0.76), Color("bac6a0"), 0.0, 0.85, 0.85)
	if follower:
		_sphere(st, Vector3(-0.10, 0.12, -0.43), Vector3(0.027, 0.044, 0.022), Color("35463a"), 4, 6)
		_sphere(st, Vector3(0.10, 0.12, -0.43), Vector3(0.027, 0.044, 0.022), Color("35463a"), 4, 6)
		_crown(st)
	st.generate_normals()
	var result := st.commit()
	_meshes[key] = result
	return result

static func crown() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_crown(st)
	st.generate_normals()
	var n := MeshInstance3D.new()
	n.mesh = st.commit()
	n.material_override = material()
	return n

static func _crown(st: SurfaceTool) -> void:
	# 孢丝从生长点抽出，逐渐变窄；不是围巾或机械天线。
	_ribbon(st, Vector3(-0.12, 0.39, 0.06), Vector3(-0.30, 0.74, 0.18), Vector3(-0.48, 0.58, 0.67), 0.055, Color("acb98f"))
	_ribbon(st, Vector3(0.03, 0.43, 0.04), Vector3(0.10, 0.83, 0.14), Vector3(0.25, 0.66, 0.90), 0.043, Color("ddd6a7"))
	_ribbon(st, Vector3(0.14, 0.39, 0.06), Vector3(0.36, 0.69, 0.22), Vector3(0.51, 0.49, 0.62), 0.048, Color("93a77d"))

static func _seed(st: SurfaceTool, form: int) -> void:
	for x in range(-3, 4):
		for y in range(-3, 4):
			for z in range(-3, 4):
				var cell := Vector3i(x, y, z)
				if Vector3(cell).length_squared() > 10.5:
					continue
				var color := Color("e6dfba") if posmod(x + z, 4) != 0 else Color("c8bb8a")
				for d in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
					if Vector3(cell + d).length_squared() <= 10.5:
						continue
					_face(st, Vector3(cell) * 0.135, Vector3.ONE * 0.135, Vector3(d), color)

static func cube(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		_face(st, center, size, d, color)

static func _face(st: SurfaceTool, center: Vector3, size: Vector3, normal: Vector3, color: Color) -> void:
	var u := Vector3.UP if absf(normal.y) < 0.5 else Vector3.RIGHT
	var v := normal.cross(u)
	var o := center + normal * size * 0.5
	u *= size * 0.5
	v *= size * 0.5
	_tri(st, o - u - v, o + u - v, o + u + v, color)
	_tri(st, o - u - v, o + u + v, o - u + v, color)

static func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, width: float, color: Color) -> void:
	for i in 8:
		var t0 := i / 8.0
		var t1 := (i + 1) / 8.0
		var p := a * pow(1.0 - t0, 2) + b * 2.0 * (1.0 - t0) * t0 + c * t0 * t0
		var q := a * pow(1.0 - t1, 2) + b * 2.0 * (1.0 - t1) * t1 + c * t1 * t1
		var u := Vector3.RIGHT * width * (1.0 - t0 * 0.9)
		var v := Vector3.RIGHT * width * (1.0 - t1 * 0.9)
		_tri(st, p - u, q - v, q + v, color, t0, t1, t1)
		_tri(st, p - u, q + v, p + u, color, t0, t1, t0)

static func _sphere(st: SurfaceTool, center: Vector3, radius: Vector3, color: Color, rings: int, segments: int, folds := false) -> void:
	for y in rings:
		for x in segments:
			var a := _point(y, x, rings, segments, center, radius, folds)
			var b := _point(y + 1, x, rings, segments, center, radius, folds)
			var c := _point(y + 1, x + 1, rings, segments, center, radius, folds)
			var d := _point(y, x + 1, rings, segments, center, radius, folds)
			_tri(st, a, b, c, color)
			_tri(st, a, c, d, color)

static func _point(y: int, x: int, rings: int, segments: int, center: Vector3, radius: Vector3, folds: bool) -> Vector3:
	var lat := y * PI / rings
	var lon := x * TAU / segments
	var fold := 1.0 - (0.055 * pow(sin(lon * 5.0), 2) * sin(lat) if folds else 0.0)
	return center + Vector3(sin(lat) * sin(lon), cos(lat), sin(lat) * cos(lon)) * radius * fold

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, wa := 0.0, wb := 0.0, wc := 0.0) -> void:
	for entry in [[a, wa], [b, wb], [c, wc]]:
		st.set_color(Color(color.srgb_to_linear(), entry[1]))
		st.set_smooth_group(-1)
		st.add_vertex(entry[0])
