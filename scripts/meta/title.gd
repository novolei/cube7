extends Node3D
## 开始界面。
## 画面：浮岛全景留给世界，左侧像一页薄纸承载标题与操作。
## 流程：黑场淡入 → 标志依次浮现 → 按任意键 → 主菜单（继续 / 新游戏 / 读取 / 设置 / 赞赏作者 / 退出）

@onready var world: VoxelWorld = $VoxelWorld

var _cam: Camera3D
var _angle := 0.0
var _ui: Control
var _black: ColorRect
var _dim: ColorRect
var _logo: Control
var _title_label: Label
var _rule: ColorRect
var _fragments: Array[Control] = []
var _press: HBoxContainer
var _menu: VBoxContainer
var _hints: HBoxContainer
var _slots: PanelContainer
var _settings: SettingsPanel
var _confirm: PanelContainer
var _donate: PanelContainer
var _state := "intro"
var _t := 0.0
var _slot_mode := "new"
var _hero: Node3D
var _hero_ring: Node3D
var _hero_eyes: Array[MeshInstance3D] = []
var _logo_y := 72.0

const CENTER := Vector3(32, 10, 25)
const MENU_W := 420.0
const ANGLE0 := 0.15     ## 镜头构图的基准角度：只在附近缓慢摆动，不整圈环绕

func _ready() -> void:
	# 命令行测试直接进游戏
	var args := Array(OS.get_cmdline_user_args())
	if args.any(func(a: String) -> bool: return a.begins_with("--autotest") or a.begins_with("--level") or a.begins_with("--shots") or a == "--probe"):
		Flow.mode = "debug"
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	if args.any(func(a: String) -> bool: return a.begins_with("--uishots")):
		var shots := Node.new()
		shots.set_script(load("res://scripts/debug/ui_shots.gd"))
		get_tree().root.add_child.call_deferred(shots)
	if args.any(func(a: String) -> bool: return a.begins_with("--titletest")):
		var tt := Node.new()
		tt.set_script(load("res://scripts/debug/test_title.gd"))
		get_tree().root.add_child.call_deferred(tt)
	var level := AreaGreenhouse.new()
	level.backdrop = true
	level.world_path = NodePath("../VoxelWorld")
	add_child(level)
	_golden_hour()
	level.build()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.current = true
	add_child(_cam)
	_build_hero()
	_build_ui()
	GameState.device_changed.connect(func(_k: String) -> void: _refresh_glyphs())
	Music.set_override("title")
	Music.play_area("title")
	_intro()

# ================================================================ 画面

## 黄昏配色：深蓝天顶、暖橙地平线、低角度暖光。只影响标题画面。
func _golden_hour() -> void:
	Atmosphere.apply(self, "title")
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		# 光从镜头一侧斜照过来（侧逆光太暗），偏暖
		sun.rotation_degrees = Vector3(-32, 90.0 - rad_to_deg(ANGLE0) + 35.0, 0)

func _process(delta: float) -> void:
	if _cam == null:
		return
	if not bool(Settings.get_v("reduce_motion")):
		_t += delta
	_angle = ANGLE0 + sin(_t * 0.045) * 0.22
	var p := CENTER + Vector3(cos(_angle) * 60.0, 19.0 + sin(_angle * 0.7) * 2.5, sin(_angle) * 60.0)
	_cam.global_position = p
	_cam.look_at(CENTER + Vector3(0, 17.0, 0))
	if _press and _state == "press":
		_press.modulate.a = 1.0 if bool(Settings.get_v("reduce_motion")) else 0.65 + 0.35 * (0.5 + 0.5 * sin(_t * 1.8))
	if _logo:
		_logo.position.y = _logo_y + sin(_t * 1.1) * 3.0
	if _hero:
		_hero.position = Vector3(2.7, -1.05 + sin(_t * 1.6) * 0.07, -6.4)
		_hero.rotation = Vector3(sin(_t * 0.9) * 0.1, sin(_t * 0.5) * 0.35, sin(_t * 0.7) * 0.08)
		_hero_ring.rotation.x = _t * 1.6
		var blink := 0.12 if fmod(_t, 3.7) < 0.12 else 1.0
		for e in _hero_eyes:
			e.scale.y = blink

## 主角特写：和经典作品的标题画面一样，主角就在镜头前
func _build_hero() -> void:
	_hero = Node3D.new()
	_cam.add_child(_hero)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color("f6f2e6")
	shell.roughness = 0.72
	shell.metallic = 0.08
	shell.rim_enabled = true
	shell.rim = 0.6
	shell.rim_tint = 0.4
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("8ed8d3")
	glow.emission_enabled = true
	glow.emission = Color("8ed8d3")
	glow.emission_energy_multiplier = 1.6
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.48
	sm.height = 0.96
	ball.mesh = sm
	ball.material_override = shell
	_hero.add_child(ball)
	_hero_ring = Node3D.new()
	_hero.add_child(_hero_ring)
	for rx in [0.0, 90.0]:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.455
		t.outer_radius = 0.525
		ring.mesh = t
		ring.material_override = glow
		ring.rotation_degrees.x = rx
		_hero_ring.add_child(ring)
	# 屏幕脸：深色面罩 + 两只发光的眼睛（朝着镜头）
	var face := Node3D.new()
	_hero.add_child(face)
	face.rotation_degrees.y = 157.0
	var visor := MeshInstance3D.new()
	var vm := SphereMesh.new()
	vm.radius = 0.2
	vm.height = 0.24
	visor.mesh = vm
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color("1b1f3b")
	vmat.roughness = 0.58
	visor.material_override = vmat
	visor.scale = Vector3(1.35, 0.95, 0.35)
	visor.position = Vector3(0, 0.1, -0.43)
	visor.rotation_degrees.x = -12.0
	face.add_child(visor)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color("9ff0ff")
	for x in [-0.085, 0.085]:
		var e := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.034
		cm.height = 0.13
		e.mesh = cm
		e.material_override = em
		e.position = Vector3(x, 0.115, -0.505)
		e.rotation_degrees.x = -12.0
		face.add_child(e)
		_hero_eyes.append(e)
	var light := OmniLight3D.new()
	light.light_color = Color("8ed8d3")
	light.light_energy = 0.45
	light.omni_range = 2.5
	_hero.add_child(light)
	# 暖色轮廓光，让主角从黄昏背景里跳出来
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.75, 0.5)
	rim.light_energy = 1.1
	rim.omni_range = 3.0
	rim.position = Vector3(1.2, 0.8, -1.0)
	_hero.add_child(rim)

# ================================================================ 界面搭建

func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	return gt

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.theme = UIKit.theme()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 根节点不拦鼠标：否则“按任意键开始”时鼠标点击被它吃掉，传不到 _unhandled_input
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	# 天空保留标题的负空间；菜单一侧有轻微暗部以维持可读性。
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	vg.colors = PackedColorArray([Color(0.02, 0.09, 0.10, 0.0), Color(0.02, 0.09, 0.10, 0.0), Color(0.02, 0.09, 0.10, 0.18)])
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.55, 0.45)
	vt.fill_to = Vector2(1.25, 1.05)
	var vign := TextureRect.new()
	vign.texture = vt
	vign.stretch_mode = TextureRect.STRETCH_SCALE
	vign.set_anchors_preset(Control.PRESET_FULL_RECT)
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(vign)
	# 左侧深青渐隐，只托住菜单，不形成实体卡片。
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	sg.colors = PackedColorArray([Color(0.02, 0.11, 0.12, 0.64), Color(0.02, 0.11, 0.12, 0.36), Color(0.02, 0.11, 0.12, 0.0)])
	var st := GradientTexture2D.new()
	st.gradient = sg
	st.fill = GradientTexture2D.FILL_RADIAL
	st.fill_from = Vector2(0, 1)
	st.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = st
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	UIKit.place(shade, Vector4(0, 0.45, 0.47, 1), Vector4.ZERO)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	# 空气中漂浮的光尘
	var motes := CPUParticles2D.new()
	motes.amount = 22
	motes.lifetime = 12.0
	motes.preprocess = 12.0
	motes.texture = _soft_dot()
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(1100, 620)
	motes.position = Vector2(960, 600)
	motes.direction = Vector2(0.3, -1)
	motes.spread = 25.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 6.0
	motes.initial_velocity_max = 18.0
	motes.scale_amount_min = 0.08
	motes.scale_amount_max = 0.32
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.9, 0.75, 0), Color(1, 0.9, 0.75, 0.55), Color(1, 0.9, 0.75, 0.55), Color(1, 0.9, 0.75, 0)])
	motes.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = add
	_ui.add_child(motes)
	motes.visible = not bool(Settings.get_v("reduce_motion"))
	Settings.changed.connect(func() -> void: motes.visible = not bool(Settings.get_v("reduce_motion")))

	_build_logo()

	# 按任意键
	_press = HBoxContainer.new()
	_press.add_theme_constant_override("separation", 10)
	UIKit.place(_press, Vector4(0, 1, 0, 1), Vector4(144, -190, 700, -140))
	_press.modulate.a = 0.0
	_press.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_press)
	# 主菜单
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 6)
	# 菜单占标题下方到底部提示之间的区域；打开菜单时标题会缩小上移，给菜单让位
	UIKit.place(_menu, Vector4(0, 0, 0, 1), Vector4(132, 390, 132 + MENU_W, -105))
	_menu.alignment = BoxContainer.ALIGNMENT_END
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.visible = false
	_ui.add_child(_menu)
	# 底部按键提示
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 26)
	UIKit.place(_hints, Vector4(0, 1, 0, 1), Vector4(144, -72, 700, -34))
	_hints.modulate.a = 0.0
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_hints)
	_refresh_glyphs()
	# 版本号
	var ver := UIKit.label("VOXEL ARK   /   v1.1", 16, UIKit.DIM)
	UIKit.place(ver, Vector4(1, 1, 1, 1), Vector4(-280, -52, -40, -26))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(ver)
	# 弹出面板时的压暗层
	_dim = ColorRect.new()
	_dim.color = Color(0.19, 0.22, 0.21, 0.38)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.modulate.a = 0.0
	_ui.add_child(_dim)
	# 设置
	_settings = SettingsPanel.new()
	UIKit.place(_settings, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-350, -280, 350, 280))
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
		_show_menu())
	_ui.add_child(_settings)
	# 开场黑场
	_black = ColorRect.new()
	_black.color = Color(0.0, 0.0, 0.02, 1.0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_black)

func _build_logo() -> void:
	_logo = Control.new()
	_logo_y = 28.0
	UIKit.place(_logo, Vector4(0.5, 0, 0.5, 0), Vector4(-480, _logo_y, 480, _logo_y + 330))
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_logo)
	var face := UIKit.latin_font()
	var line := "VOXEL ARK"
	var tracking := 19.0
	var width := face.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 90).x + (line.length() - 1) * tracking
	var x := (960.0 - width) * 0.5
	for i in line.length():
		var ch := line.substr(i, 1)
		var advance := face.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 90).x + tracking
		if ch != " ":
			for strip in 3:
				var clip := Control.new()
				clip.clip_contents = true
				clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				clip.size = Vector2(advance + 8.0, 44.0)
				var target := Vector2(x, 40.0 + strip * 44.0)
				clip.set_meta(&"rest", target)
				var n := (i * 37 + strip * 19) % 11
				clip.position = target + Vector2((n - 5) * 10.0, ((n * 7) % 9 - 4) * 5.0)
				clip.modulate.a = 0.0
				var glyph := UIKit.latin_label(ch, 90)
				glyph.position = Vector2(0, -strip * 44.0)
				clip.add_child(glyph)
				_logo.add_child(clip)
				_fragments.append(clip)
		x += advance
	_title_label = UIKit.display_label("方舟星球", 78)
	_title_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.09, 0.10, 0.4))
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.position = Vector2(0, 175)
	_title_label.size = Vector2(960, 96)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.add_child(_title_label)
	_rule = ColorRect.new()
	_rule.color = Color(UIKit.TEXT, 0.65)
	_rule.position = Vector2(390, 278)
	_rule.size = Vector2(180, 1)
	_logo.add_child(_rule)
	var sub := UIKit.latin_label("A  W O R L D  T O  R E B U I L D", 22, UIKit.TEXT)
	sub.position = Vector2(0, 294)
	sub.size = Vector2(960, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.add_child(sub)
	_title_label.modulate.a = 0.0
	_rule.modulate.a = 0.0
	sub.modulate.a = 0.0

## 字形碎片归位 → 中文标题、细线和副标题跟入。
func _intro() -> void:
	if bool(Settings.get_v("reduce_motion")):
		for clip in _fragments:
			clip.position = clip.get_meta(&"rest")
		for child in _logo.get_children():
			(child as CanvasItem).modulate.a = 1.0
		create_tween().tween_property(_black, "color:a", 0.0, 0.35)
		_state = "press"
		return
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	for i in _fragments.size():
		var clip := _fragments[i]
		var anim := create_tween().set_parallel()
		anim.tween_property(clip, "position", clip.get_meta(&"rest"), 1.05).set_delay(0.24 + (i % 3) * 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		anim.tween_property(clip, "modulate:a", 1.0, 0.3).set_delay(0.16)
	_title_label.position.y += 10.0
	create_tween().tween_property(_title_label, "position:y", 175.0, 0.7).set_delay(0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	create_tween().tween_property(_title_label, "modulate:a", 1.0, 0.6).set_delay(0.85)
	create_tween().tween_property(_rule, "modulate:a", 1.0, 0.45).set_delay(1.15)
	create_tween().tween_property(_logo.get_child(_logo.get_child_count() - 1), "modulate:a", 1.0, 0.55).set_delay(1.30)
	await get_tree().create_timer(2.1).timeout
	if _state == "intro":
		_state = "press"

func _skip_intro() -> void:
	for tw in get_tree().get_processed_tweens():
		tw.custom_step(10.0)
	_black.color.a = 0.0
	for c in _fragments:
		c.position = c.get_meta(&"rest")
	for c in _logo.get_children():
		(c as CanvasItem).modulate.a = 1.0

func _refresh_glyphs() -> void:
	for c in _press.get_children():
		c.queue_free()
	if GameState.device == "kbm":
		_press.add_child(UIKit.label("按任意键开始", 25, UIKit.TEXT))
	else:
		_press.add_child(UIKit.label("按", 25, UIKit.TEXT))
		_press.add_child(UIKit.glyph("ui_accept", 28))
		_press.add_child(UIKit.label("开始", 25, UIKit.TEXT))
	for c in _hints.get_children():
		c.queue_free()
	_hints.add_child(UIKit.prompt("ui_accept", "确认", 18))
	_hints.add_child(UIKit.prompt("ui_cancel", "返回", 18))

# ================================================================ 输入

func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if _state == "intro" and pressed:
		get_viewport().set_input_as_handled()
		_skip_intro()
		_state = "press"
		return
	if _state == "press":
		if pressed:
			get_viewport().set_input_as_handled()
			Sfx.play("ui_confirm", Vector3.INF, -4.0, 0.0)
			Sfx.play("pix_happy", Vector3.INF, -10.0, 0.05)
			var tw := create_tween()
			tw.tween_property(_press, "modulate:a", 0.0, 0.2)
			tw.tween_callback(func() -> void: _press.visible = false)
			_show_menu()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	match _state:
		"slots":
			get_viewport().set_input_as_handled()
			Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
			_close_panel(_slots)
			_show_menu()
		"confirm":
			get_viewport().set_input_as_handled()
			Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
			_close_panel(_confirm)
			_open_slots(_slot_mode)
		"donate":
			get_viewport().set_input_as_handled()
			Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
			_close_panel(_donate)
			_show_menu()
		"settings":
			get_viewport().set_input_as_handled()
			_settings.closed.emit()
		"more":
			get_viewport().set_input_as_handled()
			_show_menu()

# ================================================================ 主菜单

func _clear_menu() -> void:
	for c in _menu.get_children():
		c.queue_free()

## 纸页上的文字菜单：薄金边保留明确的手柄焦点，其他状态尽量安静。
func _item(text: String, cb: Callable, sub := "", accent := UIKit.ACCENT2) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(MENU_W, 76 if sub != "" else 62)
	UIKit.quiet_button(b, 30, accent)
	b.add_theme_color_override("font_color", UIKit.TEXT)
	b.add_theme_color_override("font_hover_color", UIKit.TEXT)
	b.add_theme_color_override("font_focus_color", UIKit.TEXT)
	b.add_theme_color_override("font_pressed_color", UIKit.TEXT)
	if sub != "":
		var sl := UIKit.label(sub, 17, UIKit.DIM)
		UIKit.place(sl, Vector4(0, 1, 1, 1), Vector4(22, -31, -8, -6))
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sl)
	UIKit.juice(b)
	b.pressed.connect(cb)
	_menu.add_child(b)
	return b

func _show_menu() -> void:
	_state = "menu"
	_logo_show(true)
	_dim_show(false)
	_clear_menu()
	_menu.visible = true
	var latest := SaveGame.latest_slot()
	var first: Button
	if latest >= 0:
		first = _item("继续探索", func() -> void: _continue(latest))
	var ng := _item("开始旅程", func() -> void: _open_slots("new"))
	if first == null:
		first = ng
	var reached := 0
	var best_up := {}
	for i in SaveGame.SLOTS:
		var sd := SaveGame.read(i)
		if sd.is_empty():
			continue
		var ch := int(sd.get("chapter", 1))
		if bool((sd.get("flags", {}) as Dictionary).get("game_clear", false)):
			ch = Chapters.count()
		if ch > reached:
			reached = ch
			best_up = sd.get("upgrades", {})
	_item("设置", func() -> void:
		_state = "settings"
		_menu.visible = false
		_logo_show(false)
		_dim_show(true)
		_settings.open())
	_item("更多", func() -> void: _show_more_menu(latest, reached, best_up))
	first.grab_focus.call_deferred()
	# 菜单项依次滑入
	var i := 0
	for c in _menu.get_children():
		var ci := c as Control
		ci.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(ci, "modulate:a", 1.0, 0.25).set_delay(0.04 * i)
		i += 1
	create_tween().tween_property(_hints, "modulate:a", 1.0, 0.4)

func _show_more_menu(latest: int, reached: int, best_up: Dictionary) -> void:
	_state = "more"
	_clear_menu()
	var first: Button
	if latest >= 0:
		first = _item("读取存档", func() -> void: _open_slots("load"))
	if reached >= 2:
		var chapters := _item("章节选择", func() -> void: _open_chapters(reached, best_up))
		if first == null:
			first = chapters
	var editor := _item("关卡编辑器", func() -> void:
		Music.stop()
		Flow.goto_game("editor"))
	if first == null:
		first = editor
	_item("赞赏作者", _open_donate, "", UIKit.ACCENT2)
	_item("退出游戏", func() -> void: get_tree().quit())
	_item("返回", _show_menu)
	first.grab_focus.call_deferred()

func _open_chapters(reached: int, ups: Dictionary) -> void:
	_state = "slots"
	_menu.visible = false
	_logo_show(false)
	_dim_show(true)
	_slots = _panel(700, 600)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_slots.add_child(v)
	v.add_child(UIKit.label("章节选择", 32, UIKit.TEXT, true))
	var first: Button
	for i in reached:
		var info := Chapters.info(i + 1)
		var b := Button.new()
		b.text = "%s   %s" % [info.num, info.title]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(620, 60)
		UIKit.juice(b)
		var n := i + 1
		b.pressed.connect(func() -> void:
			SaveGame.data = {}
			Upgrades._mem = ups.duplicate()
			Flow.chapter = n
			Music.stop()
			Flow.goto_game("replay"))
		v.add_child(b)
		if first == null:
			first = b
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 26)
	hint.add_child(UIKit.prompt("ui_accept", "选择", 18))
	hint.add_child(UIKit.prompt("ui_cancel", "返回", 18))
	v.add_child(hint)
	if first:
		first.grab_focus.call_deferred()

func _logo_show(on: bool) -> void:
	create_tween().tween_property(_logo, "modulate:a", 1.0 if on else 0.0, 0.25)

func _dim_show(on: bool) -> void:
	create_tween().tween_property(_dim, "modulate:a", 1.0 if on else 0.0, 0.25)

func _panel(w: float, h: float, _border := UIKit.LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = UIKit.theme()
	p.add_theme_stylebox_override("panel", UIKit.paper(30))
	UIKit.place(p, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-w * 0.5, -h * 0.5, w * 0.5, h * 0.5))
	_ui.add_child(p)
	# 弹出动画
	UIKit.reveal(p)
	return p

func _close_panel(p: Control) -> void:
	if is_instance_valid(p):
		p.queue_free()

func _continue(i: int) -> void:
	if SaveGame.load_slot(i):
		Music.stop()
		Flow.goto_game("continue")

# ================================================================ 存档位

func _open_slots(mode: String) -> void:
	_slot_mode = mode
	_state = "slots"
	_menu.visible = false
	_logo_show(false)
	_dim_show(true)
	_slots = _panel(780, 560)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_slots.add_child(v)
	v.add_child(UIKit.label("选择存档位" if mode == "new" else "读取存档", 32, UIKit.TEXT, true))
	var first: Button
	for i in SaveGame.SLOTS:
		var d := SaveGame.read(i)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(700, 104)
		b.add_theme_font_size_override("font_size", 22)
		if d.is_empty():
			b.text = "存档 %d\n空" % (i + 1)
			b.disabled = mode == "load"
		else:
			var when := Time.get_datetime_string_from_unix_time(int(float(d.get("saved_at", 0))) + 8 * 3600, true)
			var chi := Chapters.info(int(d.get("chapter", 1)))
			var cleared := bool((d.get("flags", {}) as Dictionary).get("gh_clear" if int(d.get("chapter", 1)) == 1 else "ch%d_clear" % int(d.get("chapter", 1)), false))
			var tot := Chapters.count() * 3
			b.text = "存档 %d   ·   %s %s%s\n游戏时间 %s   ·   救出噗噗 %d/%d   ·   记忆碎片 %d/%d   ·   %s" % [
				i + 1, chi.num, chi.title, "   ·   已通关" if cleared else "", SaveGame.format_time(float(d.get("play_time", 0))),
				(d.get("seeds", []) as Array).size(), tot, (d.get("fragments", []) as Array).size(), tot, when.substr(5, 11)]
		UIKit.juice(b)
		b.pressed.connect(func() -> void: _pick_slot(i, d.is_empty()))
		v.add_child(b)
		if first == null and not b.disabled:
			first = b
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 26)
	hint.add_child(UIKit.prompt("ui_accept", "选择", 18))
	hint.add_child(UIKit.prompt("ui_cancel", "返回", 18))
	v.add_child(hint)
	if first:
		first.grab_focus.call_deferred()

func _pick_slot(i: int, empty: bool) -> void:
	if _slot_mode == "load":
		_close_panel(_slots)
		_continue(i)
		return
	if empty:
		_start_new(i)
		return
	# 覆盖确认
	_close_panel(_slots)
	_state = "confirm"
	_confirm = _panel(600, 260, UIKit.DANGER)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	_confirm.add_child(v)
	v.add_child(UIKit.label("覆盖存档 %d？" % (i + 1), 30, UIKit.TEXT, true))
	v.add_child(UIKit.label("原来的进度会被清除，无法恢复。", 20, UIKit.DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	var no := Button.new()
	no.text = "取消"
	UIKit.juice(no)
	no.pressed.connect(func() -> void:
		_close_panel(_confirm)
		_open_slots("new"))
	var yes := Button.new()
	yes.text = "覆盖并开始"
	UIKit.juice(yes)
	yes.pressed.connect(func() -> void: _start_new(i))
	h.add_child(no)
	h.add_child(yes)
	no.grab_focus.call_deferred()

func _start_new(i: int) -> void:
	SaveGame.new_game(i)
	Music.stop()
	Flow.goto_game("new")

# ================================================================ 赞赏（通关后出现）

func _open_donate() -> void:
	_state = "donate"
	_menu.visible = false
	_logo_show(false)
	_dim_show(true)
	_donate = _panel(540, 760, UIKit.ACCENT2)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_donate.add_child(v)
	var t := UIKit.label("喜欢《方舟星球》吗？", 32, UIKit.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var body := UIKit.label("游戏完全免费。如果它让你开心，\n可以请作者喝一杯咖啡，支持继续开发～", 19, UIKit.DIM)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(body)
	var qr := TextureRect.new()
	qr.texture = load("res://ui/donate_qr.png")
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr.custom_minimum_size = Vector2(0, 480)
	v.add_child(qr)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(220, 0)
	UIKit.juice(back)
	back.pressed.connect(func() -> void:
		_close_panel(_donate)
		_show_menu())
	h.add_child(back)
	back.grab_focus.call_deferred()
	Sfx.play("pix_happy", Vector3.INF, -8.0, 0.05)
