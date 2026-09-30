extends Node
## 自适应背景音乐（自动加载为 Music）。
## 每个区域一首曲子，分三层同步播放：底层 / 旋律层 / 明亮层。
## 状态决定各层音量：探索 = 底层+旋律；解谜 = 旋律淡到很低；明亮 = 三层全开。

const STATES := {
	"explore": {"base": 1.0, "melody": 1.0, "bright": 0.0},
	"puzzle": {"base": 1.0, "melody": 0.18, "bright": 0.0},
	"bright": {"base": 1.0, "melody": 1.0, "bright": 1.0},
	"quiet": {"base": 0.5, "melody": 0.0, "bright": 0.0},
	"title": {"base": 1.0, "melody": 0.0, "bright": 0.0},
}
const LAYERS := ["base", "melody", "bright"]

var default_state := "explore"
var _override := ""
var _players := {}
var _levels := {"base": 0.0, "melody": 0.0, "bright": 0.0}
var _duck := 1.0
var _duck_timer := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music", -4.0)
	_ensure_bus("SFX", -2.0)
	_ensure_bus("UI", -4.0)
	_ensure_bus("Voice", -6.0)
	_ensure_bus("Movement", -3.0)
	_ensure_bus("World", -7.0)
	AudioServer.set_bus_send(AudioServer.get_bus_index("Voice"), "SFX")
	AudioServer.set_bus_send(AudioServer.get_bus_index("Movement"), "SFX")
	AudioServer.set_bus_send(AudioServer.get_bus_index("World"), "SFX")
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, limiter)
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = -12.0
	compressor.ratio = 2.5
	compressor.attack_us = 1800.0
	compressor.release_ms = 150.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("World"), compressor)
	for layer in LAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players[layer] = p

func _ensure_bus(bus_name: String, db: float) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_volume_db(i, db)
	AudioServer.set_bus_send(i, "Master")

## 开始播放某区域的曲子（文件名前缀，例如 "gh"）
func play_area(prefix: String) -> void:
	for layer in LAYERS:
		var path := "res://audio/music/%s_%s.ogg" % [prefix, layer]
		var p: AudioStreamPlayer = _players[layer]
		p.stream = null
		if not ResourceLoader.exists(path):
			continue
		var s := load(path) as AudioStreamOggVorbis
		s.loop = true
		p.stream = s
	for layer in LAYERS:
		var pl := _players[layer] as AudioStreamPlayer
		if pl.stream:
			pl.play()

func stop() -> void:
	for layer in LAYERS:
		(_players[layer] as AudioStreamPlayer).stop()

## 过场用的一次性配乐（不分层、不循环）：会先停掉区域音乐
var _cue: AudioStreamPlayer

func play_cue(name: String) -> void:
	stop()
	if _cue == null:
		_cue = AudioStreamPlayer.new()
		_cue.bus = "Music"
		add_child(_cue)
	var path := "res://audio/music/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return
	var s := load(path) as AudioStreamOggVorbis
	s.loop = false
	_cue.stream = s
	_cue.volume_db = 0.0
	_cue.play()

func stop_cue(fade := 1.0) -> void:
	if _cue == null or not _cue.playing:
		return
	var tw := create_tween()
	tw.tween_property(_cue, "volume_db", -60.0, fade)
	tw.tween_callback(_cue.stop)

func set_default(state: String) -> void:
	default_state = state

func set_override(state: String) -> void:
	_override = state

## 播放音效大事件（解锁、过关）时，把音乐临时压低
func duck(secs: float, amount := 0.25) -> void:
	_duck = minf(_duck, amount) if secs > 0.0 else amount
	_duck_timer = maxf(_duck_timer, secs) if secs > 0.0 else 0.0

func _process(delta: float) -> void:
	var st: Dictionary = STATES.get(_override if _override != "" else default_state, STATES["explore"])
	if _duck_timer > 0.0:
		_duck_timer -= delta
	else:
		_duck = move_toward(_duck, 1.0, delta * 0.8)
	for layer in LAYERS:
		var target: float = st[layer] * _duck * (0.4 if get_tree().paused else 1.0)
		_levels[layer] = move_toward(_levels[layer], target, delta * (2.5 if target < _levels[layer] else 0.6))
		var p: AudioStreamPlayer = _players[layer]
		p.volume_db = linear_to_db(maxf(_levels[layer], 0.0001))
