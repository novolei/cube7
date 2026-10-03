class_name Hud
extends CanvasLayer
## 游戏界面（统一风格见 UIKit）
##   左上：金币 / 能源条 / 护盾 / 记忆碎片
##   右上：当前目标，直接排在世界的留白里
##   下方中间：NOVA 对话（雾色衬底 + 名牌 + 打字机 + 语音拟声）
##   左下：已解锁的形态  右下：只显示当前有用的按键提示
##   中央：区域标题卡；目标下方：自动保存提示

var _root: Control
var _coins: Label
var _matter: Label
var _energy_bar: ProgressBar
var _shields: Array[UIIcon] = []
var _shield_row: HBoxContainer
var _frag_row: HBoxContainer
var _frag: Label
var _seeds: Label
var _obj_card: PanelContainer
var _obj_text: Label
var _nova: PanelContainer
var _nova_text: RichTextLabel
var _nova_name: Label
var _forms_row: HBoxContainer
var _form_badges: Array[PanelContainer] = []
var _form_name: Label
var _prompts: VBoxContainer
var _title_card: VBoxContainer
var _save_toast: HBoxContainer
var _queue: Array[Dictionary] = []
var _nova_time := 0.0
var _chars := 0.0
var _last_char := 0
var _pause: PauseMenu
var _grab_hint := ""
var _grab_t := 0.0
var _stats_dirty := false
var _stats_pop := false
var _pending_combo := 0
var _title_tween: Tween
var _combo_tween: Tween
var _nova_tween: Tween
var _save_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = UIKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	UIKit.edge_wash(_root)
	UIKit.edge_wash(_root, true)
	_build_stats()
	_root.add_child(ObjectivePointer.new())
	_build_objective()
	_build_nova()
	_build_forms()
	_build_prompts()
	_build_title_card()
	_build_save_toast()
	if OS.has_feature("mobile"):
		var touch := TouchControls.new()
		_root.add_child(touch)
		_prompts.hide()
		var forms := _forms_row.get_parent() as Control
		forms.offset_top = -435
		forms.offset_bottom = -330
		get_viewport().size_changed.connect(_safe_area)
		_safe_area.call_deferred()
	GameState.level_cleared.connect(_show_clear)
	_build_combo()
	GameState.combo_changed.connect(_on_combo)
	_challenge = UIKit.outline(UIKit.label("", 22, UIKit.ACCENT), 2)
	UIKit.place(_challenge, Vector4(0.5, 0, 0.5, 0), Vector4(-220, 26, 220, 70))
	_challenge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge.visible = false
	_root.add_child(_challenge)
	GameState.challenge_changed.connect(func(active: bool, left: float, got: int, total: int) -> void:
		_challenge.visible = active
		_challenge.text = "限时 %.1f 秒  ·  蓝币 %d / %d" % [maxf(left, 0.0), got, total]
		_challenge.add_theme_color_override("font_color", UIKit.DANGER if left < 5.0 else UIKit.ACCENT))
	GameState.combo_finished.connect(_on_combo_end)
	_pause = PauseMenu.new()
	add_child(_pause)
	GameState.coins_changed.connect(func(_v: int) -> void: _queue_stats(true))
	GameState.energy_changed.connect(func(_v: int) -> void: _queue_stats())
	GameState.upgrades_changed.connect(_rebuild_shields)
	GameState.matter_changed.connect(func(v: int) -> void: _matter.text = str(v))
	GameState.shield_changed.connect(func(_v: int) -> void: _queue_stats())
	GameState.fragments_changed.connect(func(_v: int) -> void: _queue_stats())
	GameState.seeds_changed.connect(func(_v: int) -> void: _queue_stats(true))
	GameState.form_changed.connect(func(_i: int) -> void: _refresh_forms())
	GameState.form_unlocked.connect(_on_form_unlocked)
	GameState.device_changed.connect(func(_k: String) -> void: _refresh_prompts())
	GameState.nova_say.connect(func(t: String, context: Area3D) -> void: _queue.append({"text": t, "context": context}))
	GameState.objective_changed.connect(_on_objective)
	SaveGame.saved.connect(_on_saved)
	_refresh_stats()
	_refresh_forms()
	_refresh_prompts()
	if GameState.objective_index >= 0:
		_on_objective(GameState.objective_index, GameState.objective_text, GameState.objective_pos)

# ================================================================ 连拆

func _safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var window := Vector2(DisplayServer.window_get_size())
	if safe.size == Vector2i.ZERO or window.x <= 0 or window.y <= 0:
		return
	var ratio := get_viewport().get_visible_rect().size / window
	_root.offset_left = maxf(0, safe.position.x) * ratio.x
	_root.offset_top = maxf(0, safe.position.y) * ratio.y
	_root.offset_right = -maxf(0, window.x - safe.end.x) * ratio.x
	_root.offset_bottom = -maxf(0, window.y - safe.end.y) * ratio.y

var _combo_box: VBoxContainer
var _challenge: Label
var _combo_num: Label
var _combo_word: Label

func _build_combo() -> void:
	_combo_box = VBoxContainer.new()
	_combo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	UIKit.place(_combo_box, Vector4(0.5, 0, 0.5, 0), Vector4(-160, 90, 160, 200))
	_combo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_box.modulate.a = 0.0
	_root.add_child(_combo_box)
	_combo_word = UIKit.outline(UIKit.display_label("连拆", 22, UIKit.ACCENT2), 2)
	_combo_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_box.add_child(_combo_word)
	_combo_num = UIKit.outline(UIKit.latin_label("×0", 40), 2)
	_combo_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_box.add_child(_combo_num)

func _on_combo(n: int) -> void:
	_pending_combo = n

func _show_combo(n: int) -> void:
	if n < 3:
		return
	if _combo_tween and _combo_tween.is_valid():
		_combo_tween.kill()
	_combo_word.text = "连拆"
	_combo_box.modulate.a = 1.0
	_combo_num.text = "×%d" % n
	var hot := clampf(n / 40.0, 0.0, 1.0)
	_combo_num.add_theme_color_override("font_color", UIKit.TEXT.lerp(UIKit.ACCENT2, hot))
	UIKit.pulse(_combo_num)
	Sfx.play("coin", Vector3.INF, -16.0, 0.0, 1.0 + minf(n, 40) * 0.025)

func _on_combo_end(n: int, bonus: int) -> void:
	if n < 3:
		return
	var word := "连拆完成"
	if n >= 60:
		word = "完美连锁"
	elif n >= 30:
		word = "连续突破"
	elif n >= 15:
		word = "精彩连拆"
	_combo_word.text = word + ("  +%d 金币" % bonus if bonus > 0 else "")
	if bonus > 0:
		Sfx.play("success", Vector3.INF, -8.0, 0.0)
	var tw := create_tween()
	tw.tween_interval(1.2)
	_combo_tween = tw
	tw.tween_property(_combo_box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: _combo_word.text = "连拆")

# ================================================================ 通关结算

func _show_clear() -> void:
	if Flow.mode == "debug" or get_tree().paused:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var visible_controls: Array[CanvasItem] = []
	for child in _root.get_children():
		if child is CanvasItem and child.visible:
			visible_controls.append(child)
			child.hide()
	var dim := ColorRect.new()
	dim.color = Color(0.13, 0.17, 0.17, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.paper(36))
	UIKit.place(p, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-380, -240, 380, 240))
	_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var info := Chapters.info(GameState.chapter)
	var small := UIKit.label("%s  ·  %s" % [info.num, info.title], 20, UIKit.ACCENT, true)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(small)
	var big := UIKit.display_label("重构塔 %d / 5 点亮" % int(info.tower), 48)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	SaveGame.write()
	var rows := [
		["coin", UIKit.ACCENT2, "金币", str(GameState.coins)],
		["pupu", UIKit.GOOD, "救出噗噗", "%d / %d" % [GameState.seeds, GameState.seeds_total]],
		["fragment", UIKit.ACCENT2, "记忆碎片", "%d / %d" % [GameState.fragments, GameState.fragments_total]],
		["save", UIKit.ACCENT, "游戏时间", SaveGame.format_time(float(SaveGame.data.get("play_time", 0.0)))],
	]
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		h.add_child(UIKit.make_spacer(80))
		h.add_child(UIIcon.make(r[0], r[1], 28))
		var l := UIKit.label(r[2], 24, UIKit.DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UIKit.label(r[3], 26, UIKit.TEXT, true))
		h.add_child(UIKit.make_spacer(80))
		v.add_child(h)
		h.modulate.a = 0.0
		create_tween().tween_property(h, "modulate:a", 1.0, 0.3).set_delay(0.4 + rows.find(r) * 0.25)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	v.add_child(btns)
	var stay := Button.new()
	stay.text = "继续探索"
	UIKit.juice(stay)
	stay.pressed.connect(func() -> void:
		dim.queue_free()
		p.queue_free()
		for child in visible_controls:
			child.show()
		get_tree().paused = false
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	var home := Button.new()
	home.text = "返回标题"
	UIKit.juice(home)
	home.pressed.connect(func() -> void:
		SaveGame.write()
		Flow.goto_title())
	var has_next := GameState.chapter < Chapters.count()
	if has_next:
		var nxt := Button.new()
		nxt.text = "前往%s" % Chapters.info(GameState.chapter + 1).num
		UIKit.juice(nxt)
		nxt.pressed.connect(func() -> void:
			SaveGame.start_chapter(GameState.chapter + 1)
			Flow.chapter = GameState.chapter + 1
			Flow.goto_game("next"))
		btns.add_child(nxt)
		nxt.grab_focus.call_deferred()
	btns.add_child(stay)
	btns.add_child(home)
	if not has_next:
		home.grab_focus.call_deferred()
	UIKit.reveal(p)

# ================================================================ 构建

func _build_stats() -> void:
	var p := PanelContainer.new()
	var style := UIKit.panel(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0)
	style.shadow_size = 0
	p.add_theme_stylebox_override("panel", style)
	UIKit.place(p, Vector4(0, 0, 0, 0), Vector4(38, 32, 310, 32))
	_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 10)
	coin_row.add_child(UIIcon.make("coin", UIKit.ACCENT2, 24))
	_coins = UIKit.outline(UIKit.label("0", 24), 2)
	coin_row.add_child(_coins)
	coin_row.add_child(UIKit.make_spacer(10))
	coin_row.add_child(UIIcon.make("matter", UIKit.ACCENT, 22))
	_matter = UIKit.outline(UIKit.label("0", 22), 2)
	coin_row.add_child(_matter)
	v.add_child(coin_row)
	var e_row := HBoxContainer.new()
	e_row.add_theme_constant_override("separation", 10)
	e_row.add_child(UIIcon.make("energy", UIKit.ACCENT, 22))
	_energy_bar = ProgressBar.new()
	_energy_bar.show_percentage = false
	_energy_bar.max_value = GameState.energy_per_shield
	_energy_bar.custom_minimum_size = Vector2(110, 3)
	_energy_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := UIKit.panel(Color(UIKit.ACCENT, 0.16), Color.TRANSPARENT, 5, 0)
	var fg := UIKit.panel(UIKit.ACCENT, Color(0, 0, 0, 0), 5, 0)
	bg.shadow_size = 0
	fg.shadow_size = 0
	_energy_bar.add_theme_stylebox_override("background", bg)
	_energy_bar.add_theme_stylebox_override("fill", fg)
	e_row.add_child(_energy_bar)
	_shield_row = e_row
	_rebuild_shields()
	v.add_child(e_row)
	_frag_row = HBoxContainer.new()
	_frag_row.add_theme_constant_override("separation", 10)
	_frag_row.add_child(UIIcon.make("fragment", UIKit.ACCENT2, 22))
	_frag = UIKit.outline(UIKit.label("0 / 3", 18), 2)
	_frag_row.add_child(_frag)
	_frag_row.add_child(UIKit.make_spacer(8))
	_frag_row.add_child(UIIcon.make("pupu", UIKit.GOOD, 22))
	_seeds = UIKit.outline(UIKit.label("0 / 3", 18), 2)
	_frag_row.add_child(_seeds)
	v.add_child(_frag_row)

func _rebuild_shields() -> void:
	for sh in _shields:
		sh.queue_free()
	_shields.clear()
	for i in GameState.max_shield:
		var sh := UIIcon.make("shield", UIKit.GOOD, 16)
		_shields.append(sh)
		_shield_row.add_child(sh)
	if _energy_bar:
		_energy_bar.max_value = GameState.energy_per_shield
	if _seeds:
		_refresh_stats()

func _build_objective() -> void:
	_obj_card = PanelContainer.new()
	var st := UIKit.panel(Color.TRANSPARENT, Color(UIKit.ACCENT2, 0.65), 0, 12, 0)
	st.border_width_top = 1
	st.shadow_size = 0
	_obj_card.add_theme_stylebox_override("panel", st)
	UIKit.place(_obj_card, Vector4(1, 0, 1, 0), Vector4(-420, 32, -38, 32))
	_obj_card.visible = false
	_root.add_child(_obj_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_obj_card.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UIIcon.make("objective", UIKit.ACCENT2, 18))
	h.add_child(UIKit.outline(UIKit.label("此行", 16, UIKit.ACCENT2), 2))
	v.add_child(h)
	_obj_text = UIKit.outline(UIKit.label("", 22), 2)
	_obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_obj_text)

func _build_nova() -> void:
	_nova = PanelContainer.new()
	_nova.add_theme_stylebox_override("panel", UIKit.paper(22))
	UIKit.place(_nova, Vector4(0.5, 1, 0.5, 1), Vector4(-330, -202, 330, -202))
	_nova.visible = false
	_root.add_child(_nova)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	_nova.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_nova_name = UIKit.latin_label("N O V A", 15, UIKit.ACCENT2)
	v.add_child(_nova_name)
	# 富文本：台词里的按键直接显示成手柄 / 键盘图标
	_nova_text = RichTextLabel.new()
	_nova_text.bbcode_enabled = true
	_nova_text.fit_content = true
	_nova_text.scroll_active = false
	_nova_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_nova_text.add_theme_font_override("normal_font", UIKit.font())
	_nova_text.add_theme_font_size_override("normal_font_size", 21)
	_nova_text.add_theme_color_override("default_color", UIKit.TEXT)
	_nova_text.custom_minimum_size = Vector2(560, 0)
	_nova_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_nova_text)

func _build_forms() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	UIKit.place(v, Vector4(0, 1, 0, 1), Vector4(28, -150, 520, -28))
	v.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(v)
	_form_name = UIKit.outline(UIKit.display_label("", 26), 2)
	v.add_child(_form_name)
	_forms_row = HBoxContainer.new()
	_forms_row.add_theme_constant_override("separation", 10)
	v.add_child(_forms_row)
	for i in MorphBall.FORMS.size():
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(52, 52)
		var c := CenterContainer.new()
		pc.add_child(c)
		_forms_row.add_child(pc)
		_form_badges.append(pc)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 6)
	hint.name = "Hint"
	v.add_child(hint)

func _build_prompts() -> void:
	_prompts = VBoxContainer.new()
	_prompts.alignment = BoxContainer.ALIGNMENT_END
	_prompts.add_theme_constant_override("separation", 8)
	UIKit.place(_prompts, Vector4(1, 1, 1, 1), Vector4(-300, -220, -28, -28))
	_root.add_child(_prompts)

func _build_title_card() -> void:
	_title_card = VBoxContainer.new()
	_title_card.alignment = BoxContainer.ALIGNMENT_CENTER
	UIKit.place(_title_card, Vector4(0.5, 0.35, 0.5, 0.35), Vector4(-500, -90, 500, 90))
	_title_card.modulate.a = 0.0
	_title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_title_card)

func _build_save_toast() -> void:
	_save_toast = HBoxContainer.new()
	_save_toast.add_theme_constant_override("separation", 8)
	UIKit.place(_save_toast, Vector4(1, 0, 1, 0), Vector4(-240, 158, -38, 188))
	_save_toast.alignment = BoxContainer.ALIGNMENT_END
	_save_toast.add_child(UIIcon.make("save", UIKit.ACCENT, 16))
	_save_toast.add_child(UIKit.outline(UIKit.label("旅程已记录", 18, UIKit.TEXT), 2))
	_save_toast.modulate.a = 0.0
	_root.add_child(_save_toast)

# ================================================================ 刷新

func _queue_stats(pop := false) -> void:
	_stats_dirty = true
	_stats_pop = _stats_pop or pop

func _refresh_stats(pop := false) -> void:
	_coins.text = str(GameState.coins)
	if pop:
		UIKit.pulse(_coins)
	_energy_bar.value = GameState.energy if GameState.shield < GameState.max_shield else GameState.energy_per_shield
	for i in _shields.size():
		_shields[i].filled = i < GameState.shield
		_shields[i].queue_redraw()
	_frag_row.visible = GameState.fragments_total > 0
	_frag.text = "%d / %d" % [GameState.fragments, GameState.fragments_total]
	_seeds.text = "%d / %d" % [GameState.seeds, GameState.seeds_total]

func _refresh_forms() -> void:
	var p := GameState.player as MorphBall
	var cur := p.form if p else 0
	var unlocked_count := 0
	for i in _form_badges.size():
		var f: Dictionary = p.form_info(i) if p else MorphBall.FORMS[i]
		var pc := _form_badges[i]
		var unlocked: bool = GameState.unlocked_forms[i]
		if unlocked:
			unlocked_count += 1
		var active := i == cur
		pc.visible = unlocked
		var ink: Color = UIKit.TEXT if active else UIKit.ACCENT
		var st := UIKit.panel(Color.TRANSPARENT, UIKit.ACCENT2 if active else Color(UIKit.LINE, 0.3), 0, 4, 0)
		st.border_width_bottom = 2 if active else 1
		st.shadow_size = 0
		pc.add_theme_stylebox_override("panel", st)
		pc.custom_minimum_size = Vector2(58, 58) if active else Vector2(50, 50)
		var c := pc.get_child(0)
		for ch in c.get_children():
			ch.queue_free()
		if unlocked:
			c.add_child(UIIcon.make("form_" + f.id, ink if active else Color(ink, 0.75), 30 if active else 22))
		else:
			c.add_child(UIIcon.make("lock", Color(UIKit.DIM, 0.8), 18))
	_form_name.text = p.form_info(cur).name if p else ""
	_nova_name.text = "E C H O" if p and p.ecology_mode else "N O V A"
	var hint: HBoxContainer = _forms_row.get_parent().get_node("Hint")
	for ch in hint.get_children():
		ch.queue_free()
	if unlocked_count > 1:
		hint.add_child(UIKit.glyph("form", 16))
		hint.add_child(UIKit.outline(UIKit.label("切换形态", 16, UIKit.DIM), 6))
	_refresh_prompts()

func _refresh_prompts() -> void:
	if _prompts == null:
		return
	for c in _prompts.get_children():
		c.queue_free()
	var p := GameState.player as MorphBall
	_prompt_idle = 0.0
	if p:
		_prompts.add_child(UIKit.prompt("ability", p.form_info(p.form).ability, 21))
	if GameState.allow_jump and p:
		_prompts.add_child(UIKit.prompt("jump", p.form_info(p.form).jump_name, 21))
	if _grab_hint != "":
		var gp := UIKit.prompt("grab", _grab_hint, 28)
		gp.modulate = UIKit.ACCENT2
		_prompts.add_child(gp)
	if _form_badges.size() > 0:
		pass

func _on_form_unlocked(i: int) -> void:
	_refresh_forms()
	var pc := _form_badges[i]
	UIKit.pulse(pc, 1.08)
	var p := GameState.player as MorphBall
	var info: Dictionary = p.form_info(i) if p else MorphBall.FORMS[i]
	show_area_title("新形态", info.name, info.ability)

func _on_objective(_i: int, text: String, _pos: Vector3) -> void:
	_obj_text.text = text
	_obj_card.visible = text != ""
	# 新目标：卡片从右侧滑入并闪一下
	_obj_card.modulate = Color(1, 1, 1, 0)
	var tw := create_tween().set_parallel()
	tw.tween_property(_obj_card, "modulate", Color.WHITE, 0.35)
	if _i > 0:
		Sfx.play("checkpoint", Vector3.INF, -10.0, 0.0)

func _on_saved() -> void:
	if _save_tween and _save_tween.is_valid():
		_save_tween.kill()
	_save_tween = create_tween()
	_save_tween.tween_property(_save_toast, "modulate:a", 1.0, 0.25)
	_save_tween.tween_interval(1.6)
	_save_tween.tween_property(_save_toast, "modulate:a", 0.0, 0.5)

## 屏幕中央的大标题（进入区域、解锁形态）
func show_area_title(small: String, big: String, sub := "") -> void:
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	for c in _title_card.get_children():
		c.queue_free()
	var a := UIKit.outline(UIKit.label(small, 24, UIKit.ACCENT2, true), 4)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := UIKit.outline(UIKit.display_label(big, 64), 3)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_card.add_child(a)
	_title_card.add_child(b)
	if sub != "":
		var c := UIKit.outline(UIKit.label(_fmt(sub), 23, UIKit.TEXT), 4)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_card.add_child(c)
	var tw := create_tween()
	_title_card.scale = Vector2(0.98, 0.98)
	_title_tween = tw
	_title_card.pivot_offset = _title_card.size * 0.5
	tw.tween_property(_title_card, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(_title_card, "scale", Vector2.ONE, 0.25 if bool(Settings.get_v("reduce_motion")) else 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.2)
	tw.tween_property(_title_card, "modulate:a", 0.0, 0.8)

## 把 {jump} 之类的占位符换成当前设备的按键
func _fmt(t: String) -> String:
	for key in GameState.GLYPHS["kbm"].keys():
		t = t.replace("{%s}" % key, "【%s】" % GameState.glyph(key))
	return t

func _fmt_rich(t: String) -> String:
	for key in GameState.GLYPHS["kbm"].keys():
		t = t.replace("{%s}" % key, " " + UIKit.glyph_bbcode(key, 30) + " ")
	return t

# ================================================================ NOVA 对话

var _prompt_idle := 0.0

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if _stats_dirty:
		_refresh_stats(_stats_pop)
		_stats_dirty = false
		_stats_pop = false
	if _pending_combo > 0:
		_show_combo(_pending_combo)
		_pending_combo = 0
	# 右下角按键提示：一段时间没变化就淡出，别一直挡着画面（换形态、能抓东西时再亮出来）
	_prompt_idle += delta
	if _prompts:
		var want := 1.0 if _prompt_idle < 8.0 or _grab_hint != "" else 0.0
		_prompts.modulate.a = move_toward(_prompts.modulate.a, want, delta * 1.5)
	# 靠近能抓的东西时，右下角亮出“抓取”，抱着东西时变成“投掷”
	_grab_t -= delta
	if _grab_t <= 0.0:
		_grab_t = 0.2
		var hint := ""
		var p := GameState.player as MorphBall
		if p:
			if p.ecology_mode:
				var map := p.get_parent().get("level") as AreaWindtrace
				if map and map.swarm:
					hint = map.context_hint()
			elif p.is_holding():
				hint = "投掷"
			else:
				for n in get_tree().get_nodes_in_group("usable_item"):
					if (n as Node3D).global_position.distance_to(p.global_position) < MorphBall.GRAB_RANGE:
						hint = "抓取"
						break
		if hint != _grab_hint:
			_grab_hint = hint
			_refresh_prompts()
	while _nova_time <= 0.0 and not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		var context = entry.context
		# Finish the spoken line, then discard advice for areas already left behind.
		if typeof(context) == TYPE_OBJECT and (not is_instance_valid(context) or not context.overlaps_body(GameState.player)):
			continue
		if context is TalkTrigger and context.until_objective >= 0 and GameState.objective_index > context.until_objective:
			continue
		var t := _fmt_rich(entry.text)
		_nova_text.text = t
		t = _nova_text.get_parsed_text()
		_nova_text.visible_characters = 0
		_chars = 0.0
		_last_char = 0
		_nova_time = 2.8 + t.length() * 0.065
		Music.duck(_nova_time, 0.55)
		_nova.visible = true
		_nova.modulate.a = 0.0
		if _nova_tween and _nova_tween.is_valid():
			_nova_tween.kill()
		_nova_tween = create_tween()
		_nova_tween.tween_property(_nova, "modulate:a", 1.0, 0.2)
	if _nova_time > 0.0:
		_nova_time -= delta
		_chars += delta * 38.0
		var n := int(_chars)
		_nova_text.visible_characters = n
		# 留出字词间的呼吸，避免语音拟声盖过音乐与环境声
		var plain := _nova_text.get_parsed_text()
		if n != _last_char and n <= plain.length() and n % 5 == 0:
			var ch := plain.substr(n - 1, 1) if n > 0 else ""
			if ch.strip_edges() != "" and not ch in "，。！？、…—「」【】":
				Sfx.play("voice_nova", Vector3.INF, -12.0, 0.18)
		_last_char = n
		if _nova_time <= 0.0:
			if _nova_tween and _nova_tween.is_valid():
				_nova_tween.kill()
			_nova_tween = create_tween()
			_nova_tween.tween_property(_nova, "modulate:a", 0.0, 0.25)
			_nova_tween.tween_callback(func() -> void: _nova.visible = _nova_time > 0.0)
