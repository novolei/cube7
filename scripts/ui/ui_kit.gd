class_name UIKit
extends RefCounted
## 统一的界面风格：配色、字体、面板、按钮、手柄按键图标。所有界面都从这里取样式。

## 山谷序曲：深青、雾白、苔绿与极少量日光金。
const BG := Color(0.045, 0.145, 0.155, 0.78)
const BG_SOLID := Color(0.055, 0.16, 0.17, 0.96)
const LINE := Color(0.64, 0.77, 0.72, 0.43)
const ACCENT := Color("a9c9ac")
const ACCENT2 := Color("e3bd84")
const TEXT := Color("f6f5e9")
const DIM := Color("c2d2c8")
const DANGER := Color("ee9c86")
const GOOD := Color("b9d3aa")

const FONT_CJK := "res://assets/fonts/TsangerYuMo-W02.ttf"
const FONT_CJK_BOLD := "res://assets/fonts/TsangerYuMo-W03.ttf"
const FONT_CJK_DISPLAY := "res://assets/fonts/TsangerYuMo-W01.ttf"
const FONT_FALLBACK := "res://assets/fonts/NotoSansSC-UI.ttf"
const FONT_LATIN := "res://assets/fonts/Raleway-UI.ttf"

static var _font: Font
static var _font_bold: Font
static var _font_display: Font
static var _font_latin: Font
static var _theme: Theme

static func font(bold := false) -> Font:
	if _font == null:
		var cjk := load(FONT_CJK) as FontFile
		var bold_v := load(FONT_CJK_BOLD) as FontFile
		var display := load(FONT_CJK_DISPLAY) as FontFile
		var fallback := load(FONT_FALLBACK) as FontFile
		for face in [cjk, bold_v, display]:
			face.fallbacks = [fallback]
		var latin := FontVariation.new()
		latin.base_font = load(FONT_LATIN) as FontFile
		latin.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 260}
		_font = cjk
		_font_bold = bold_v
		_font_display = display
		_font_latin = latin
	return _font_bold if bold else _font

static func display_font() -> Font:
	font()
	return _font_display

static func latin_font() -> Font:
	font()
	return _font_latin

static func panel(bg := BG, border := LINE, radius := 6, pad := 18, border_w := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0.01, 0.04, 0.05, 0.16)
	s.shadow_size = 4
	s.anti_aliasing = true
	return s

## 全局主题：按钮、滑条、复选框统一风格（手柄焦点清晰可见）
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	# 按钮
	var normal := panel(Color.TRANSPARENT, Color(ACCENT2, 0.12), 2, 14)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.shadow_size = 0
	var hover := panel(Color(ACCENT2, 0.12), ACCENT2, 2, 14, 1)
	hover.content_margin_left = 24
	hover.content_margin_right = 24
	hover.shadow_color = Color(ACCENT2, 0.15)
	hover.shadow_size = 0
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ACCENT2, 0.22)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(1, 1, 1, 0.02)
	for st in [["normal", normal], ["hover", hover], ["focus", hover], ["pressed", pressed], ["disabled", disabled], ["hover_pressed", pressed]]:
		t.set_stylebox(st[0], "Button", st[1])
	t.set_font("font", "Button", font(true))
	t.set_font_size("font_size", "Button", 24)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(TEXT, 0.38))
	t.set_constant("h_separation", "Button", 12)
	# 滑条
	var track := panel(Color(ACCENT, 0.16), Color(0, 0, 0, 0), 4, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := panel(ACCENT, Color(0, 0, 0, 0), 4, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	knob.fill(Color(0, 0, 0, 0))
	for y in 22:
		for x in 22:
			var d := Vector2(x - 10.5, y - 10.5).length()
			if d < 10.5:
				knob.set_pixel(x, y, Color(0.61, 0.44, 0.22, clampf(10.5 - d, 0, 1)))
	var ktex := ImageTexture.create_from_image(knob)
	t.set_icon("grabber", "HSlider", ktex)
	t.set_icon("grabber_highlight", "HSlider", ktex)
	t.set_stylebox("focus", "HSlider", panel(Color(0, 0, 0, 0), ACCENT, 8, 0, 2))
	# 复选
	t.set_font("font", "CheckButton", font(true))
	t.set_stylebox("focus", "CheckButton", panel(Color(ACCENT2, 0.12), ACCENT2, 4, 8, 1))
	t.set_color("font_color", "CheckButton", TEXT)
	_theme = t
	return t

static func label(text: String, size := 22, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func display_label(text: String, size := 48, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", display_font())
	return l

static func latin_label(text: String, size := 24, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", latin_font())
	return l

static func outline(l: Label, size := 4, color := Color(0.02, 0.09, 0.1, 0.72)) -> Label:
	l.add_theme_constant_override("outline_size", mini(size, 5))
	l.add_theme_color_override("font_outline_color", color)
	return l

## 锚点 + 偏移一次设好（anchors / offsets 都是 左, 上, 右, 下）
static func place(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w

## 手柄 / 键盘按键图标：用 Kenney Input Prompts 的真实按键图（PS5 / Xbox / 键鼠自动切换）
const PROMPTS := {
	"ps": {"jump": ["color_cross"], "ability": ["color_square"], "grab": ["color_circle"], "view_toggle": ["color_triangle"],
		"boost": ["r2"], "form": ["l1", "r1"], "form_direct": ["dpad"], "respawn": ["create"], "pause": ["options"],
		"move": ["stick_l"], "camera": ["stick_r"], "ui_accept": ["color_cross"], "ui_cancel": ["color_circle"]},
	"xbox": {"jump": ["color_a"], "ability": ["color_x"], "grab": ["color_b"], "view_toggle": ["color_y"],
		"boost": ["rt"], "form": ["lb", "rb"], "form_direct": ["dpad_all"], "respawn": ["view"], "pause": ["menu"],
		"move": ["stick_l"], "camera": ["stick_r"], "ui_accept": ["color_a"], "ui_cancel": ["color_b"]},
	"kbm": {"jump": ["keyboard_space"], "ability": ["mouse_left"], "grab": ["keyboard_e"], "view_toggle": ["keyboard_v"],
		"boost": ["keyboard_shift"], "form": ["mouse_scroll"], "form_direct": ["keyboard_1", "keyboard_2", "keyboard_3"],
		"respawn": ["keyboard_r"], "pause": ["keyboard_escape"], "move": ["keyboard_w", "keyboard_a", "keyboard_s", "keyboard_d"],
		"camera": ["mouse_move"], "ui_accept": ["keyboard_enter"], "ui_cancel": ["keyboard_escape"]},
}

## 某个动作在当前设备上的图标路径（可能有多个，比如 L1 + R1）
static func prompt_paths(action: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dev := GameState.device
	for n in (PROMPTS[dev] as Dictionary).get(action, []):
		out.append("res://assets/prompts/%s/%s.png" % [dev, n])
	return out

static func glyph(action: String, size := 20) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var paths := prompt_paths(action)
	if paths.is_empty():
		var l := label(GameState.glyph(action), size - 2, TEXT, true)
		h.add_child(l)
		return h
	for p in paths:
		var t := TextureRect.new()
		t.texture = load(p)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 键盘图标的按键本体只占画布中间一小块，放大一些才和手柄图标一样醒目
		var k := 1.9 if p.contains("/kbm/") else 1.35
		t.custom_minimum_size = Vector2(size, size) * k
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(t)
	return h

## 富文本里内嵌的按键图标（NOVA 对话用）
static func glyph_bbcode(action: String, size := 30) -> String:
	var paths := prompt_paths(action)
	if paths.is_empty():
		return "【%s】" % GameState.glyph(action)
	var s := ""
	for p in paths:
		s += "[img=%d]%s[/img]" % [int(size * (1.6 if p.contains("/kbm/") else 1.0)), p]
	return s

static func make_spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = w
	return c

## “按钮 + 说明”的一行提示
static func prompt(action: String, desc: String, size := 20) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(glyph(action, size))
	var l := label(desc, size - 2, TEXT)
	outline(l, 6)
	h.add_child(l)
	return h

## 给按钮加上焦点动效与音效
static func juice(b: Button) -> void:
	b.focus_entered.connect(func() -> void:
		motion_scale(b, 1.015, 0.14)
		Sfx.play("ui_move", Vector3.INF, -12.0, 0.03))
	b.focus_exited.connect(func() -> void: motion_scale(b, 1.0, 0.14))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	press_feedback(b)
	b.pressed.connect(func() -> void: Sfx.play("ui_confirm", Vector3.INF, -8.0, 0.0))

static func press_feedback(b: Button) -> void:
	b.button_down.connect(func() -> void: motion_scale(b, 0.965, 0.08))
	b.button_up.connect(func() -> void: motion_scale(b, 1.015 if b.has_focus() else 1.0, 0.22, true))

static func motion_scale(c: Control, target: float, seconds: float, spring := false) -> void:
	var previous: Tween = c.get_meta(&"motion_tween") as Tween if c.has_meta(&"motion_tween") else null
	if previous and previous.is_valid():
		previous.kill()
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(c, "scale", Vector2.ONE * target, 0.05 if bool(Settings.get_v("reduce_motion")) else seconds).set_trans(Tween.TRANS_BACK if spring else Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c.set_meta(&"motion_tween", tw)
