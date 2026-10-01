extends CanvasLayer
# ============================================================
#  HUD — деньги, сено в руках, силы, иголки, металлоискатель,
#  магазин/техдерево, всплывающие подсказки, мобильное управление.
# ============================================================
var main: Node
var player: Node

var lbl_money: Label
var lbl_carry: Label
var lbl_sold: Label
var lbl_needles: Label
var lbl_detect: Label
var bar_stamina: ProgressBar
var lbl_hint: Label
var lbl_toast: Label
var crosshair: Control
var panel_shop: PanelContainer
var shop_list: VBoxContainer
var overlay_intro: Control
var overlay_win: Control
var lbl_win: Label
var popup: Label
var buildbar: HBoxContainer
var panel_build: PanelContainer
var lbl_build: Label
var touch_ui: Control
var stick_zone: Control
var knob: Control
var _stick_touch := -1
var _stick_center := Vector2.ZERO
var toast_t := 0.0

func _ready() -> void:
	var theme := Theme.new()
	var f := load("res://assets/fonts/main.ttf")
	theme.default_font = f
	theme.default_font_size = 18
	var fb := load("res://assets/fonts/bold.ttf")
	theme.set_font("font", "Label", fb)
	root_theme(theme)
	_build()
	GameState.changed.connect(_refresh)
	GameState.toast.connect(show_toast)
	_refresh()

func root_theme(th: Theme) -> void:
	var root := get_tree().root
	root.theme = th

func _style(bg: Color, border: Color, radius := 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(radius))
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _panel(pos: Vector2, size: Vector2, bg := Color(0.06, 0.07, 0.09, 0.72), border := Color(0.85, 0.7, 0.3, 0.55)) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.custom_minimum_size = size
	p.add_theme_stylebox_override("panel", _style(bg, border))
	add_child(p)
	return p

func _label(parent: Node, text: String, size := 18, col := Color(0.96, 0.94, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l

func _build() -> void:
	# ---- левый верх: деньги / сено / продано
	var left := _panel(Vector2(16, 14), Vector2(330, 132))
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	left.add_child(lv)
	lbl_money = _label(lv, "$0.00000", 30, Color(1.0, 0.86, 0.42))
	lbl_carry = _label(lv, "в руках: 0 / 1", 17)
	lbl_sold = _label(lv, "продано: 0 стеблей", 15, Color(0.75, 0.78, 0.8))
	var bw := VBoxContainer.new()
	bw.add_theme_constant_override("separation", 2)
	lv.add_child(bw)
	_label(bw, "силы", 13, Color(0.72, 0.75, 0.78))
	bar_stamina = ProgressBar.new()
	bar_stamina.max_value = 100.0
	bar_stamina.value = 100.0
	bar_stamina.custom_minimum_size = Vector2(280, 14)
	bar_stamina.show_percentage = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.9, 0.75, 0.3, 0.95)
	sb.set_corner_radius_all(6)
	bar_stamina.add_theme_stylebox_override("fill", sb)
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(0.15, 0.16, 0.18, 0.9)
	sbg.set_corner_radius_all(6)
	bar_stamina.add_theme_stylebox_override("background", sbg)
	bw.add_child(bar_stamina)

	# ---- правый верх: иголки и детектор
	var right := _panel(Vector2(-386, 14), Vector2(370, 132))
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-386, 14)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 4)
	right.add_child(rv)
	lbl_needles = _label(rv, "ИГОЛКИ 0 / 24", 24, Color(1.0, 0.92, 0.6))
	lbl_detect = _label(rv, "металлоискатель: тихо", 16, Color(0.8, 0.9, 0.85))
	_label(rv, "детектор пищит чаще, когда иголка рядом", 13, Color(0.62, 0.66, 0.7))

	# ---- подсказка снизу
	lbl_hint = _label(self, "", 22, Color(1.0, 0.95, 0.8))
	lbl_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lbl_hint.position = Vector2(-260, -108)
	lbl_hint.custom_minimum_size = Vector2(520, 30)
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.visible = false

	# ---- прицел
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.75)
	dot.size = Vector2(5, 5)
	dot.position = Vector2(-2.5, -2.5)
	crosshair.add_child(dot)
	add_child(crosshair)

	# ---- всплывашка
	lbl_toast = _label(self, "", 24, Color(1.0, 0.95, 0.7))
	lbl_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_toast.position = Vector2(-300, 170)
	lbl_toast.custom_minimum_size = Vector2(600, 30)
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.visible = false

	# ---- попап «ИГОЛКА!»
	popup = _label(self, "", 64, Color(1.0, 0.9, 0.35))
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.position = Vector2(-320, -120)
	popup.custom_minimum_size = Vector2(640, 80)
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.visible = false
	popup.add_theme_constant_override("outline_size", 12)
	popup.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))

	_build_shop()
	_build_buildbar()
	_build_overlays()
	_build_touch()

func _build_shop() -> void:
	panel_shop = PanelContainer.new()
	panel_shop.set_anchors_preset(Control.PRESET_CENTER)
	panel_shop.position = Vector2(-330, -260)
	panel_shop.custom_minimum_size = Vector2(660, 520)
	panel_shop.add_theme_stylebox_override("panel", _style(Color(0.05, 0.06, 0.08, 0.96), Color(0.9, 0.75, 0.35, 0.8), 14))
	add_child(panel_shop)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel_shop.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_label(head, "МАГАЗИН СКЛАДА", 26, Color(1.0, 0.86, 0.45))
	var close := Button.new()
	close.text = "закрыть (TAB)"
	close.pressed.connect(func(): _toggle_shop(false))
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	shop_list = VBoxContainer.new()
	shop_list.add_theme_constant_override("separation", 6)
	shop_list.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(shop_list)
	panel_shop.visible = false
	_rebuild_shop()

func _rebuild_shop() -> void:
	for c in shop_list.get_children():
		c.queue_free()
	for it in GameState.ITEMS:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _style(Color(0.09, 0.1, 0.13, 0.9), Color(0.4, 0.4, 0.45, 0.6), 8))
		shop_list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var lv := VBoxContainer.new()
		lv.custom_minimum_size = Vector2(300, 44)
		h.add_child(lv)
		var lvl := GameState.lvl(it.id)
		_label(lv, "%s  %s" % [it.name, "· ур.%d" % lvl if lvl > 0 else ""], 19, Color(0.96, 0.94, 0.88))
		_label(lv, it.desc, 14, Color(0.68, 0.72, 0.76))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		var btn := Button.new()
		var maxed: bool = lvl >= int(it.max)
		btn.text = "МАКС" if maxed else ("$%.5f" % GameState.price(it.id) if GameState.price(it.id) < 1.0 else "$%.2f" % GameState.price(it.id))
		btn.disabled = maxed
		if it.id == "pill":
			btn.text = "$0.30"
		btn.custom_minimum_size = Vector2(130, 44)
		btn.pressed.connect(func():
			if GameState.buy(it.id):
				main.played_coin()
				show_toast("куплено: %s" % it.name)
				_rebuild_shop()
			else:
				show_toast("не хватает денег — копай и продавай сено")
		)
		h.add_child(btn)

func _build_buildbar() -> void:
	# панель постройки: то, что доступно всегда (внизу экрана)
	buildbar = HBoxContainer.new()
	buildbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	buildbar.position = Vector2(-420, -62)
	buildbar.custom_minimum_size = Vector2(840, 54)
	buildbar.add_theme_constant_override("separation", 8)
	add_child(buildbar)
	var items := [
		["belt", "КОНВЕЙЕР $3"],
		["packer", "УПАКОВЩИК $40"],
		["scanner", "СКАНЕР $75"],
		["drone", "ДРОН $120"],
		["arm", "РОБО-РУКА $25"],
	]
	for it in items:
		var b := Button.new()
		b.text = it[1]
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func(): main.enter_build(it[0]))
		buildbar.add_child(b)

	# оверлей постройки
	panel_build = PanelContainer.new()
	panel_build.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel_build.position = Vector2(16, 160)
	panel_build.custom_minimum_size = Vector2(320, 158)
	panel_build.add_theme_stylebox_override("panel", _style(Color(0.05, 0.07, 0.06, 0.92), Color(0.45, 1.0, 0.6, 0.7), 12))
	add_child(panel_build)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	panel_build.add_child(bv)
	lbl_build = _label(bv, "постройка", 18, Color(0.7, 1.0, 0.8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bv.add_child(row)
	var ok := Button.new(); ok.text = "ПОСТАВИТЬ"; ok.pressed.connect(func(): main.place_current())
	var rot := Button.new(); rot.text = "ПОВЕРНУТЬ"; rot.pressed.connect(func(): main.rotate_current())
	var cancel := Button.new(); cancel.text = "ОТМЕНА"; cancel.pressed.connect(func(): main.exit_build())
	row.add_child(ok); row.add_child(rot); row.add_child(cancel)
	_label(bv, "наведись на пол и ставь · R — повернуть · E — поставить", 12, Color(0.7, 0.78, 0.72))
	panel_build.visible = false

func set_build_mode(on: bool, info := "") -> void:
	panel_build.visible = on
	buildbar.visible = not on
	if on:
		lbl_build.text = info

func _build_overlays() -> void:
	overlay_intro = Control.new()
	overlay_intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 0.86)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_intro.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-420, -200)
	v.custom_minimum_size = Vector2(840, 400)
	overlay_intro.add_child(v)
	_label(v, "НАЙДИ ИГОЛКУ", 76, Color(1.0, 0.86, 0.4))
	_label(v, "Ты заперт на странном складе. Перед тобой гора сена — примерно 6 000 000 стеблей.\nГде-то внутри спрятаны 24 иголки. Ты не помнишь, как попал сюда, и двери не открываются.\n\nКопай, продавай сено, покупай машины — пусть склад работает на тебя.", 22, Color(0.88, 0.88, 0.86))
	var b := Button.new()
	b.text = "НАЧАТЬ КОПАТЬ"
	b.custom_minimum_size = Vector2(320, 64)
	b.pressed.connect(func():
		overlay_intro.visible = false
		GameState.started = true
		GameState.save_game()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	)
	v.add_child(b)
	add_child(overlay_intro)

	overlay_win = Control.new()
	overlay_win.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg2 := ColorRect.new()
	bg2.color = Color(0.03, 0.02, 0.01, 0.9)
	bg2.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_win.add_child(bg2)
	var v2 := VBoxContainer.new()
	v2.set_anchors_preset(Control.PRESET_CENTER)
	v2.position = Vector2(-420, -170)
	v2.custom_minimum_size = Vector2(840, 340)
	overlay_win.add_child(v2)
	lbl_win = _label(v2, "ВСЕ 24 ИГОЛКИ НАЙДЕНЫ", 54, Color(1.0, 0.9, 0.45))
	_label(v2, "Двери склада со скрипом открываются... но за ними ещё один склад.\nСтог больше, цены выше — ты уходишь вглубь.", 22)
	var b2 := Button.new()
	b2.text = "НОВЫЙ СТОГ (+25% к цене)"
	b2.custom_minimum_size = Vector2(420, 64)
	b2.pressed.connect(func(): main.prestige())
	v2.add_child(b2)
	overlay_win.visible = false
	add_child(overlay_win)

func _build_touch() -> void:
	touch_ui = Control.new()
	touch_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(touch_ui)
	var touch := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or "--touch" in OS.get_cmdline_args()
	touch_ui.visible = touch
	if not touch:
		return
	# джойстик
	stick_zone = Control.new()
	stick_zone.position = Vector2(30, -250)
	stick_zone.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stick_zone.custom_minimum_size = Vector2(210, 210)
	stick_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	touch_ui.add_child(stick_zone)
	var ring := Panel.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.add_theme_stylebox_override("panel", _style(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.25), 105))
	stick_zone.add_child(ring)
	knob = Control.new()
	knob.custom_minimum_size = Vector2(78, 78)
	knob.position = Vector2(66, 66)
	var kp := Panel.new()
	kp.set_anchors_preset(Control.PRESET_FULL_RECT)
	kp.add_theme_stylebox_override("panel", _style(Color(1, 1, 1, 0.25), Color(1, 0.9, 0.6, 0.7), 39))
	knob.add_child(kp)
	stick_zone.add_child(knob)
	stick_zone.gui_input.connect(_stick_input)
	# кнопки
	_mk_button("КОПАТЬ", Vector2(-190, -170), Vector2(150, 150), func(p): player.dig_held = p)
	_mk_button("ДЕЙСТВИЕ", Vector2(-360, -150), Vector2(150, 96), func(p):
		if p: main.try_interact())
	_mk_button("ПРЫЖОК", Vector2(-190, -320), Vector2(150, 96), func(p):
		if p: player.touch_jump = true)
	_mk_button("МАГАЗИН", Vector2(-360, -270), Vector2(150, 96), func(p):
		if p: _toggle_shop(not panel_shop.visible))

func _mk_button(text: String, pos: Vector2, size: Vector2, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.keep_pressed_outside = true
	b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	b.position = pos
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", 20)
	b.button_down.connect(func(): cb.call(true))
	b.button_up.connect(func(): cb.call(false))
	b.toggled.connect(func(_x): pass)
	touch_ui.add_child(b)

func _stick_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed and _stick_touch == -1:
			_stick_touch = ev.index
			_stick_center = ev.position
			_knob_to(ev.position)
		elif not ev.pressed and ev.index == _stick_touch:
			_stick_touch = -1
			player.touch_move = Vector2.ZERO
			knob.position = Vector2(66, 66)
	elif ev is InputEventScreenDrag and ev.index == _stick_touch:
		var v: Vector2 = ev.position - _stick_center
		var lim := 66.0
		if v.length() > lim:
			v = v.normalized() * lim
		player.touch_move = v / lim
		knob.position = Vector2(66, 66) + v
	elif ev is InputEventMouseButton:
		# мышь для отладки на ПК
		if ev.pressed:
			_stick_center = ev.position
			_knob_to(ev.position)
		else:
			player.touch_move = Vector2.ZERO
			knob.position = Vector2(66, 66)
	elif ev is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var v2: Vector2 = ev.position - _stick_center
		var lim2 := 66.0
		if v2.length() > lim2:
			v2 = v2.normalized() * lim2
		player.touch_move = v2 / lim2
		knob.position = Vector2(66, 66) + v2

func _knob_to(_p: Vector2) -> void:
	knob.position = Vector2(66, 66)

# ---------- публичное ----------
func _toggle_shop(v: bool) -> void:
	panel_shop.visible = v
	if v:
		_rebuild_shop()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not touch_ui.visible else Input.MOUSE_MODE_VISIBLE

func show_toast(text: String) -> void:
	lbl_toast.text = text
	lbl_toast.visible = true
	toast_t = 2.6

func show_popup(text: String) -> void:
	popup.text = text
	popup.visible = true
	popup.modulate = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.tween_property(popup, "modulate:a", 0.0, 1.8).set_delay(1.6)
	tw.tween_callback(func(): popup.visible = false)

func show_win() -> void:
	overlay_win.visible = true
	lbl_win.text = "ВСЕ %d ИГОЛОК НАЙДЕНЫ" % GameState.NEEDLES_TOTAL
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_hint(text: String) -> void:
	lbl_hint.text = text
	lbl_hint.visible = text != ""

func _process(delta: float) -> void:
	if toast_t > 0.0:
		toast_t -= delta
		if toast_t <= 0.0:
			lbl_toast.visible = false
	var st := GameState.stamina
	bar_stamina.max_value = GameState.stamina_max()
	bar_stamina.value = st
	# детектор
	if player and main and main.pile:
		var d: float = main.pile.nearest_needle(player.global_position)
		var rng: float = GameState.detector_range()
		if d < rng:
			var k: float = clamp(1.0 - d / rng, 0.0, 1.0)
			lbl_detect.text = "металлоискатель: ПИК! %0.1f м" % d if k > 0.45 else "металлоискатель: что-то чуется (%0.1f м)" % d
			lbl_detect.add_theme_color_override("font_color", Color(1.0, 0.9 - 0.4 * (1.0 - k), 0.4))
		else:
			lbl_detect.text = "металлоискатель: тихо"
			lbl_detect.add_theme_color_override("font_color", Color(0.75, 0.82, 0.8))

func _refresh() -> void:
	lbl_money.text = GameState.money_str()
	lbl_carry.text = "в руках: %s / %s" % [GameState.fmt(carried_i()), GameState.fmt(GameState.capacity())]
	lbl_sold.text = "продано: %s стеблей · выкопано %s" % [GameState.fmt(GameState.sold_total), GameState.fmt(GameState.dug_total)]
	lbl_needles.text = "ИГОЛКИ %d / %d" % [GameState.needles_found, GameState.NEEDLES_TOTAL]
	var f: Dictionary = main.factory.totals() if main and main.factory else {}
	if not f.is_empty() and int(f.get("rate", 0.0)) > 0:
		lbl_sold.text += "\nфабрика: рук %d · лент %d · скан %d · скорость %s стеблей/с" % [
			int(f.arms), int(f.belts), int(f.scanners), GameState.fmt(float(f.rate))]

func carried_i() -> float:
	return floor(GameState.carried)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				_toggle_shop(not panel_shop.visible)
			KEY_E:
				if main.building:
					main.place_current()
				else:
					main.try_interact()
			KEY_R:
				if main.building:
					main.rotate_current()
			KEY_ESCAPE:
				if main.building:
					main.exit_build()
