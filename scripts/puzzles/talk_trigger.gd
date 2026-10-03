class_name TalkTrigger
extends Zone
## 区域对白；延迟提示只在本次停留足够久且目标尚未推进时出现。

@export_multiline var lines: PackedStringArray = []
@export var delay_seconds := 0.0
@export var until_objective := -1
var _done := false
var _timer: Timer

func _build() -> void:
	body_exited.connect(func(body: Node3D) -> void:
		if body == GameState.player and _timer:
			_timer.stop())
	if delay_seconds > 0.0:
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.wait_time = delay_seconds
		_timer.timeout.connect(_deliver)
		add_child(_timer)

func _on_player_entered() -> void:
	if _done:
		return
	if _timer:
		_timer.start()
	else:
		_deliver()

func _deliver() -> void:
	if _done or not overlaps_body(GameState.player):
		return
	if until_objective >= 0 and GameState.objective_index > until_objective:
		return
	_done = true
	for l in lines:
		GameState.say(l, self)
