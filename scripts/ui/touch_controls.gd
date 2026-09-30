class_name TouchControls
extends Control
## Two independent fingers: a left thumb stick and free camera drag on the right.
## Buttons emit the same InputMap actions as keyboard/controller input.
var _stick_id := -1
var _look_id := -1
var _stick := Vector2.ZERO
var _held := {}
var _buttons := {}
var _origin := Vector2.ZERO
const RADIUS := 76.0
const MOVE := ["move_left", "move_right", "move_forward", "move_back"]

func _ready() -> void:
	if OS.has_feature("mobile"):
		Input.emulate_mouse_from_touch = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	_origin = Vector2(140, size.y - 135)
	_buttons = {
		"jump": [Vector2(size.x - 125, size.y - 120), "跃", 54.0],
		"ability": [Vector2(size.x - 255, size.y - 165), "力", 48.0],
		"boost": [Vector2(size.x - 125, size.y - 255), "疾", 42.0],
		"grab": [Vector2(size.x - 280, size.y - 285), "拾", 42.0],
		"form_next": [Vector2(140, size.y - 290), "变", 42.0],
		"pause": [Vector2(size.x * 0.5, 58), "Ⅱ", 32.0],
		"view_toggle": [Vector2(size.x * 0.5 + 90, 58), "景", 32.0],
	}
	queue_redraw()

func _action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)

func release_all() -> void:
	for name in _held.values():
		_action(name, false)
	_held.clear()
	_stick_id = -1
	_look_id = -1
	_stick = Vector2.ZERO
	for name in MOVE:
		Input.action_release(name)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()

func _exit_tree() -> void:
	release_all()
	if OS.has_feature("mobile"):
		Input.emulate_mouse_from_touch = true

func _process(_delta: float) -> void:
	var paused := get_tree().paused
	visible = not paused
	if OS.has_feature("mobile"):
		Input.emulate_mouse_from_touch = paused
	if paused and (_stick_id >= 0 or _look_id >= 0 or not _held.is_empty()):
		release_all()

func _input(event: InputEvent) -> void:
	if get_tree().paused or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var at: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not event.pressed:
			if _held.has(event.index):
				var name: String = _held[event.index]
				_held.erase(event.index)
				if name not in _held.values():
					_action(name, false)
			if event.index == _stick_id:
				_stick_id = -1
				_set_stick(_origin)
			if event.index == _look_id:
				_look_id = -1
			queue_redraw()
			return
		for name in _buttons:
			var b: Array = _buttons[name]
			if at.distance_to(b[0]) < float(b[2]) + 12.0:
				_held[event.index] = name
				_action(name, true)
				get_viewport().set_input_as_handled()
				queue_redraw()
				return
		if _stick_id < 0 and at.distance_to(_origin) < RADIUS * 1.6:
			_stick_id = event.index
			_set_stick(at)
		elif _look_id < 0 and at.x > size.x * 0.4:
			_look_id = event.index
	elif event is InputEventScreenDrag:
		if event.index == _stick_id:
			_set_stick(get_global_transform_with_canvas().affine_inverse() * event.position)
		elif event.index == _look_id and is_instance_valid(GameState.camera):
			var camera := GameState.camera as CameraRig
			camera.yaw -= event.relative.x * 0.004 * camera._sens()
			camera.pitch = clampf(camera.pitch - event.relative.y * 0.004 * camera._sens() * camera._inv(), -1.3, 0.35)

func _set_stick(at: Vector2) -> void:
	_stick = ((at - _origin) / RADIUS).limit_length()
	var strengths := [maxf(-_stick.x, 0), maxf(_stick.x, 0), maxf(-_stick.y, 0), maxf(_stick.y, 0)]
	for i in MOVE.size():
		if strengths[i] > 0:
			Input.action_press(MOVE[i], strengths[i])
		else:
			Input.action_release(MOVE[i])
	queue_redraw()

func _draw() -> void:
	draw_circle(_origin, RADIUS, Color(UIKit.BG_SOLID, 0.25))
	draw_arc(_origin, RADIUS, 0, TAU, 64, Color(UIKit.TEXT, 0.35), 1.5, true)
	draw_circle(_origin + _stick * RADIUS * 0.7, 23, Color(UIKit.TEXT, 0.5))
	for name in _buttons:
		var b: Array = _buttons[name]
		var active: bool = name in _held.values()
		draw_circle(b[0], b[2], Color(UIKit.BG_SOLID, 0.38))
		draw_arc(b[0], b[2], 0, TAU, 48, UIKit.ACCENT2 if active else Color(UIKit.TEXT, 0.5), 2.0 if active else 1.2, true)
		var width := UIKit.font().get_string_size(b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x
		draw_string(UIKit.font(), b[0] + Vector2(-width * 0.5, 9), b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 25, UIKit.TEXT)
