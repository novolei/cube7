class_name UISpring
extends Node
## Retargetable spring, following mini-tanks' velocity-preserving motion.
## Sleeps when settled; the clock ignores gameplay hit-stop and pause.
var value := 1.0
var velocity := 0.0
var target := 1.0
var duration := 0.22
var _last := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func retarget(to: float, seconds: float) -> void:
	target = to
	duration = maxf(seconds, 0.08)
	if not is_processing():
		value = (get_parent() as Control).scale.x
		_last = Time.get_ticks_usec()
	set_process(true)

static func step(x: float, v: float, to: float, seconds: float, delta: float) -> Vector2:
	# Small fixed substeps keep the response consistent at 30/60/144 Hz.
	var omega := 4.0 / maxf(seconds, 0.08)
	var remaining := minf(delta, 0.25)
	while remaining > 0.0:
		var dt := minf(remaining, 1.0 / 240.0)
		v += ((to - x) * omega * omega - v * 1.64 * omega) * dt
		x += v * dt
		remaining -= dt
	return Vector2(x, v)

func _process(_delta: float) -> void:
	var c := get_parent() as Control
	var now := Time.get_ticks_usec()
	var next := step(value, velocity, target, duration, (now - _last) / 1000000.0)
	_last = now
	value = next.x
	velocity = next.y
	var reduced := bool(Settings.get_v("reduce_motion"))
	if reduced or (absf(value - target) < 0.0001 and absf(velocity) < 0.001):
		value = 1.0 if reduced else target
		velocity = 0.0
		set_process(false)
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * value
