extends Node
## godot --headless --path . res://scenes/main.tscn -- --chapter=1 --debugscript=res://scripts/debug/test_foundations.gd

func _ready() -> void:
	var p: MorphBall = get_parent().player
	p.debug_override = true
	p.set_physics_process(false)
	p._air_jumps = 0
	p._ground_timer = 0.0
	p.debug_jump_pressed = true
	p._update_jump(0.016, MorphBall.FORMS[p.form])
	var buffered := p._jump_buffer > 0.1 and p.linear_velocity.y <= 0.0
	p._ground_timer = 0.12
	p._update_jump(0.016, MorphBall.FORMS[p.form])
	var landed_jump := p._jump_buffer == 0.0 and p.linear_velocity.y > 0.0
	p._jump_buffer = 0.08
	p.respawn_at(p.global_position, -1, false)
	var cleared := p._jump_buffer == 0.0
	var ui := AudioServer.get_bus_index("UI")
	var voice := AudioServer.get_bus_index("Voice")
	var sfx := AudioServer.get_bus_index("SFX")
	var routed := ui >= 0 and voice >= 0 and sfx >= 0
	if routed:
		routed = AudioServer.get_bus_send(voice) == "SFX" and AudioServer.get_bus_send(ui) == "Master"
	for result in [["落地前输入被缓冲", buffered], ["落地后立即起跳", landed_jump], ["复活清除缓冲", cleared], ["界面与语音音频总线分层", routed]]:
		print(("[PASS] " if result[1] else "[FAIL] ") + result[0])
	get_tree().quit(0 if buffered and landed_jump and cleared and routed else 1)
