extends "res://scripts/game/main.gd"
## 独立的新世界样章；复用已打磨的物理与镜头，旧章节和存档仍可回看。

func _enter_tree() -> void:
	Flow.mode = "debug"

func _ready() -> void:
	GameState.reset_for_level([true, true, false], true, 1.0, 0)
	player.world = world
	player.enable_ecology()
	level = AreaWindtrace.new()
	level.name = "Windtrace"
	add_child(level)
	(level as AreaWindtrace).build(player, world)
	var spawn := (level as AreaWindtrace).spawn_position()
	GameState.set_checkpoint(spawn, -1)
	player.respawn_at(spawn, MorphBall.BALL, false)
	var camera := $CameraRig as CameraRig
	camera.yaw = 0.0
	camera.reset_follow(spawn)
	_style_world()
	hud.show_area_title("风痕", "相伴而生", "V E X")
	hud._pause._list.get_child(5).hide()
	(hud._pause._list.get_child(7) as Button).text = "返回标题"
	Music.play_area("gh")
	Music.set_default("explore")
	Music.set_override("")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--debugscript="):
			_attach(arg.substr(14))
			return
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("grab") and not event.is_echo():
		if (level as AreaWindtrace).interact():
			get_viewport().set_input_as_handled()

func _style_world() -> void:
	Atmosphere.apply(self, "greenhouse")
