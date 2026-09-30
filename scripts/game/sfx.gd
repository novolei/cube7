extends Node
## 音效（自动加载为 Sfx）：Sfx.play("coin") 或 Sfx.play("break_hard", 位置)

const MIN_GAP := 0.045            ## 同一个音效的最短间隔（防止一次破坏几十块时叠爆）
var _cache := {}
var _last := {}
var _pools := {}

func _pool(bus: String, spatial: bool, count: int) -> void:
	var players: Array[Node] = []
	for i in count:
		var p: Node = AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS if bus == "UI" else Node.PROCESS_MODE_PAUSABLE
		p.set("bus", bus)
		if spatial:
			p.set("unit_size", 7.0)
			p.set("max_distance", 45.0)
		add_child(p)
		players.append(p)
	_pools[bus + ("3D" if spatial else "2D")] = players

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停菜单里也要有音效
	for bus in {"UI": 4, "Voice": 2, "Movement": 4, "World": 8}:
		_pool(bus, false, {"UI": 4, "Voice": 2, "Movement": 4, "World": 8}[bus])
	for bus in {"Voice": 2, "Movement": 6, "World": 12}:
		_pool(bus, true, {"Voice": 2, "Movement": 6, "World": 12}[bus])
	# 启动时把所有音效预先载入（以前第一次播放某个音效时才从磁盘读，会卡一下）
	for f in DirAccess.get_files_at("res://audio/sfx"):
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if n.ends_with(".ogg") and not _cache.has(n.get_basename()):
			_cache[n.get_basename()] = load("res://audio/sfx/" + n)

func _stream(n: String) -> AudioStream:
	if not _cache.has(n):
		_cache[n] = load("res://audio/sfx/%s.ogg" % n)
	return _cache[n]

func play(n: String, pos := Vector3.INF, volume_db := 0.0, pitch_var := 0.08, pitch := 1.0) -> void:
	var bus := "World"
	if n.begins_with("ui_"):
		bus = "UI"
		pos = Vector3.INF
	elif n.begins_with("voice_") or n.begins_with("pix_"):
		bus = "Voice"
	elif n.begins_with("jump_") or n.begins_with("land_") or n in ["thud", "morph", "dash", "drill"]:
		bus = "Movement"
	if get_tree().paused and bus != "UI":
		return
	var now := Time.get_ticks_msec() / 1000.0
	var gap := 0.075 if n == "ui_move" else (0.16 if bus == "Voice" else MIN_GAP)
	var key := "Voice" if bus == "Voice" else n
	if now - float(_last.get(key, -10.0)) < gap:
		return
	_last[key] = now
	var s := _stream(n)
	if s == null:
		return
	var pool: Array = _pools[bus + ("2D" if pos == Vector3.INF else "3D")]
	var p: Node = pool[0]
	for candidate: Node in pool:
		if not candidate.get("playing"):
			p = candidate
			break
		if float(candidate.get_meta(&"started", 0.0)) < float(p.get_meta(&"started", 0.0)):
			p = candidate
	p.call("stop")
	p.set("stream", s)
	p.set("volume_db", volume_db)
	p.set("pitch_scale", clampf(pitch + randf_range(-pitch_var, pitch_var), 0.1, 4.0))
	if p is AudioStreamPlayer3D:
		(p as AudioStreamPlayer3D).global_position = pos
	p.set_meta(&"started", now)
	p.call("play")
	if bus == "Voice":
		Music.duck(minf(s.get_length() + 0.12, 2.0), 0.76)

## 方块破坏音效按材质分类
func break_sound(t: int, pos: Vector3) -> void:
	var n := "break_soft"
	match t:
		Blocks.GLASS:
			n = "break_glass"
		Blocks.CRATE, Blocks.CRATE_ITEM, Blocks.SUPPORT, Blocks.WOOD, Blocks.LEAVES:
			n = "break_wood"
		Blocks.ROCK, Blocks.ORE, Blocks.GEODE, Blocks.METAL:
			n = "break_hard"
	play(n, pos, -2.0, 0.15)
