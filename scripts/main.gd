extends Node3D
# ============================================================
#  Main — собирает склад, кучу, игрока, HUD; продажа, магазин,
#  робо-рука, победа/престиж, режимы отладки (скриншоты, симуляция).
# ============================================================
var world: Node3D
var pile: Node3D
var factory: Node3D
var building := false
var player: Node
var hud: CanvasLayer
var _robot_acc := 0.0
var _robot_txt := 0.0

func _ready() -> void:
	randomize()
	_apply_cli_flags()
	world = load("res://scripts/world.gd").new()
	world.name = "World"
	add_child(world)

	pile = load("res://scripts/hay_pile.gd").new()
	pile.name = "HayPile"
	pile.position = Vector3(0, 0, -5.0)
	add_child(pile)

	factory = load("res://scripts/factory.gd").new()
	factory.name = "Factory"
	factory.pile = pile
	factory.world = world
	add_child(factory)
	factory.needle_by_scanner.connect(_on_needle_scanner)

	player = load("res://scripts/player.gd").new()
	player.name = "Player"
	player.position = Vector3(0, 1.0, 10.0)
	player.pile = pile
	player.world = world
	add_child(player)

	hud = load("res://scripts/hud.gd").new()
	hud.name = "HUD"
	hud.main = self
	hud.player = player
	add_child(hud)

	pile.needle_taken.connect(_on_needle)
	factory.built.connect(func(t): hud.show_toast(t); GameState.save_game_soon())
	player.hint.connect(func(t): hud.show_toast(t))

	var args := OS.get_cmdline_user_args()
	if "--fabshots" in args:
		_fabshots(args[args.find("--fabshots") + 1] if args.find("--fabshots") + 1 < args.size() else "/tmp/fab")
		return
	if "--fabsim" in args:
		_fabsim()
		return
	if "--demo" in args:
		_demo(args[args.find("--demo") + 1] if args.find("--demo") + 1 < args.size() else "/tmp/demo")
		return
	if "--shots" in args:
		_shots(args[args.find("--shots") + 1] if args.find("--shots") + 1 < args.size() else "/tmp/shots")
		return
	if "--sim" in args:
		_sim()
		return
	if GameState.started:
		hud.overlay_intro.visible = false

# ======================================================= отладка: кадры фабрики
func _fabshots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	GameState.no_save = true
	hud.overlay_intro.visible = false
	GameState.money = 250.0
	GameState.upg = {"robot": 2, "shovel": 3, "bucket": 3, "boots": 1}
	GameState.started = true
	GameState.emit_signal("changed")
	# строим фабрику: рука у кучи, линия до станции, сканер и упаковщик
	var arm_cell: Vector2i = factory.cell_of(pile.global_position + Vector3(-2.0, 0, 9.0))
	factory._build("arm", arm_cell, 1, 2)
	var c: Vector2i = arm_cell + Vector2i(0, 1)
	var line: Array[Vector2i] = []
	while c.y < factory.cell_of(world.station_pos).y - 1:
		line.append(c)
		c += Vector2i(0, 1)
	var mid: int = line.size() / 2
	for i in range(line.size()):
		var t := "belt"
		if i == mid:
			t = "packer"
		if i == mid + 2:
			t = "scanner"
		factory._build(t, line[i], 1, 1)
	# второй дрон, чтобы видно было поиск
	factory._build("drone", Vector2i(8, -8), 0, 1)
	var cam := Camera3D.new()
	cam.fov = 72.0
	add_child(cam)
	cam.make_current()
	var spots := [
		["f01_рука_копает", Vector3(-5.5, 2.4, 7.0), Vector3(-1.0, 1.2, 3.0), 60.0],
		["f02_линия_конвейеров", Vector3(4.5, 3.4, 5.0), Vector3(-1.5, 0.6, 8.5), 62.0],
		["f03_упаковщик", Vector3(-3.4, 1.6, 9.0), Vector3(-2.0, 0.8, 7.0), 54.0],
		["f04_сканер", Vector3(-2.6, 1.8, 11.2), Vector3(-2.0, 1.0, 8.6), 54.0],
		["f05_дрон_над_стогом", Vector3(9.0, 6.4, 3.0), Vector3(0.0, 6.0, -6.0), 62.0],
		["f06_фабрика_общий_план", Vector3(11.0, 8.5, 12.0), Vector3(-1.0, 1.0, 4.0), 62.0],
	]
	for i in range(spots.size()):
		hud.visible = (i == 0)
		var sp: Array = spots[i]
		cam.global_position = sp[1]
		cam.look_at(sp[2], Vector3.UP)
		cam.fov = sp[3]
		# даём фабрике поработать, чтобы лента была заполнена
		for k in range(30):
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [dir, sp[0]])
		print("shot: ", dir, "/", sp[0])
	get_tree().quit()

# ======================================================= отладка: фабрика
func _fabsim() -> void:
	print("симуляция фабрики: рука -> конвейеры -> сканер -> упаковщик -> продажа")
	GameState.no_save = true
	hud.visible = false
	GameState.money = 400.0
	GameState.upg["robot"] = 2
	var arm_cell: Vector2i = factory.cell_of(pile.global_position + Vector3(-1.5, 0, 8.0))
	factory._build("arm", arm_cell, 1, 2)
	print("рука в клетке ", arm_cell, " копает ", 60.0 * 2, " стеблей/с")
	var c: Vector2i = arm_cell + Vector2i(0, 1)
	var line: Array[Vector2i] = []
	while c.y < factory.cell_of(world.station_pos).y - 1:
		line.append(c)
		c += Vector2i(0, 1)
	var mid: int = line.size() / 2
	for i in range(line.size()):
		var t := "belt"
		if i == mid:
			t = "packer"
		if i == mid + 2:
			t = "scanner"
		factory._build(t, line[i], 1, 1)
	print("линия: ", line.size(), " клеток, упаковщик в ", mid, ", сканер в ", mid + 2)
	var m0: float = GameState.money
	var t0 := 0.0
	while t0 < 120.0:
		t0 += 0.1
		await get_tree().physics_frame
	print("за 120 с: денег ", GameState.money_str_pre(m0), " -> ", GameState.money_str(),
		", продано ", GameState.fmt(GameState.sold_total), " стеблей, иголок сканером: ", GameState.needles_found)
	print("фабрика: ", factory.totals())
	get_tree().quit()

# ======================================================= отладка: демо-видео
func _demo(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	GameState.no_save = true
	hud.overlay_intro.visible = false
	var cam := Camera3D.new()
	cam.fov = 76.0
	add_child(cam)
	cam.make_current()
	GameState.money = 23.47
	GameState.upg = {"shovel": 2, "bucket": 1, "boots": 1}
	GameState.started = true
	GameState.emit_signal("changed")
	var fps := 10
	var dt := 1.0 / fps
	Engine.time_scale = 0.35          # замедляем мир, чтобы копание успевало
	var shot := 0
	# --- фаза 1: облёт кучи
	for i in range(int(1.8 * fps)):
		var k := i / float(int(1.8 * fps))
		cam.global_position = Vector3(lerp(-14.5, -8.5, k), lerp(7.5, 3.0, k), lerp(11.0, 6.6, k))
		cam.look_at(pile.global_position + Vector3(0, 2.4, 0), Vector3.UP)
		await _frame(dir, shot, fps); shot += 1
	# --- фаза 2: копаем, стоя на склоне (камера снаружи кучи)
	var stand := Vector3(8.6, 0, 3.4)
	stand.y = pile.height_at(stand) + 1.6
	var p2 := Vector3(6.2, 0, 1.6)
	p2.y = pile.height_at(p2) * 0.995 + 0.03
	cam.global_position = stand
	for i in range(int(3.6 * fps)):
		cam.look_at(p2 + Vector3(0, 0.1, 0), Vector3.UP)
		if i % 3 == 0:
			p2.y = pile.height_at(p2) * 0.995 + 0.03
			var removed: float = pile.dig(p2, 1.35, GameState.dig_power() * 0.5)
			GameState.dig_gain(removed)
			world.straw_burst(p2, 9)
			GameState.emit_signal("changed")
		await _frame(dir, shot, fps); shot += 1
	# --- фаза 3: тащим сено на станцию и продаём
	GameState.carried = 1400.0
	cam.global_position = Vector3(-1.6, 1.7, 6.4)
	for i in range(int(3.0 * fps)):
		cam.look_at(world.station_pos + Vector3(0, 1.6, 0), Vector3.UP)
		if i == int(1.2 * fps):
			var gain: float = GameState.sell_all()
			world.float_text(world.station_pos + Vector3(0, 1.4, 0), "+$%.4f" % gain, Color(1, 0.88, 0.4))
			world.wheel_speed = 9.0
			played_coin()
		await _frame(dir, shot, fps); shot += 1
	# --- фаза 4: магазин
	hud._toggle_shop(true)
	cam.global_position = Vector3(-11.9, 1.9, 7.6)
	for i in range(int(2.8 * fps)):
		cam.look_at(world.shop_pos + Vector3(0, 1.3, 0), Vector3.UP)
		if i == int(1.0 * fps):
			GameState.buy("shovel")
			hud._rebuild_shop()
		await _frame(dir, shot, fps); shot += 1
	hud._toggle_shop(false)
	# --- ФАЗА: фабрика (рука, конвейеры, упаковщик, сканер, дрон)
	GameState.money = 300.0
	GameState.upg["robot"] = 2
	GameState.emit_signal("changed")
	GameState.no_save = true
	var arm_cell: Vector2i = factory.cell_of(pile.global_position + Vector3(-2.0, 0, 9.0))
	factory._build("arm", arm_cell, 1, 2)
	var cc: Vector2i = arm_cell + Vector2i(0, 1)
	var line: Array[Vector2i] = []
	while cc.y < factory.cell_of(world.station_pos).y - 1:
		line.append(cc)
		cc += Vector2i(0, 1)
	var mid: int = line.size() / 2
	for i in range(line.size()):
		var tt := "belt"
		if i == mid:
			tt = "packer"
		if i == mid + 2:
			tt = "scanner"
		factory._build(tt, line[i], 1, 1)
	factory._build("drone", Vector2i(9, -9), 0, 1)
	hud.show_toast("фабрика построена: рука + конвейеры + упаковщик + сканер + дрон")
	for i in range(int(5.5 * fps)):
		var k3 := i / float(int(5.5 * fps))
		if k3 < 0.45:
			cam.global_position = Vector3(lerp(-8.0, -5.0, k3 / 0.45), lerp(2.6, 1.7, k3 / 0.45), lerp(7.6, 8.6, k3 / 0.45))
			cam.look_at(Vector3(-1.6, 1.0, 3.6), Vector3.UP)
		else:
			var k4 := (k3 - 0.45) / 0.55
			cam.global_position = Vector3(lerp(-5.0, 8.0, k4), lerp(1.7, 5.2, k4), lerp(8.6, 9.5, k4))
			cam.look_at(Vector3(-1.5, 1.2, 5.5), Vector3.UP)
		await _frame(dir, shot, fps); shot += 1
	# --- фаза 5: общий план
	for i in range(int(2.4 * fps)):
		var k2 := i / float(int(2.4 * fps))
		cam.global_position = Vector3(lerp(10.0, 2.0, k2), lerp(9.0, 4.2, k2), lerp(12.0, 10.0, k2))
		cam.look_at(pile.global_position + Vector3(0, 1.5, 0), Vector3.UP)
		await _frame(dir, shot, fps); shot += 1
	print("кадров демо: ", shot)
	get_tree().quit()

func _frame(dir: String, i: int, fps: int) -> void:
	await get_tree().create_timer(1.0 / fps).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/f%04d.png" % [dir, i])

func _apply_cli_flags() -> void:
	var args := OS.get_cmdline_user_args()
	if "--fresh" in args:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
		GameState.money = 0.0
		GameState.upg = {}
		GameState.needles_found = 0
		GameState.sold_total = 0.0
		GameState.dug_total = 0.0
		GameState.carried = 0.0
		GameState.stamina = 100.0
		GameState.prestige = 0
		GameState.started = false
		GameState._save_t = 0.0

func played_coin() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/sfx/coin.wav")
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() < r

func enter_build(t: String) -> void:
	if building:
		exit_build()
	if t == "arm":
		# робо-рука покупается как апгрейд, ставится рядом со стогом
		if GameState.lvl("robot") >= int(GameState.item("robot").max):
			hud.show_toast("все робо-руки уже куплены")
			return
		if not GameState.can_buy("robot"):
			hud.show_toast("робо-рука стоит $%.2f — не хватает" % GameState.price("robot"))
			return
		GameState.buy("robot")
		_place_arm()
		return
	building = true
	hud.set_build_mode(true, "постройка: " + factory._label(t))
	factory.enter_build(t)

func exit_build() -> void:
	building = false
	hud.set_build_mode(false)
	factory.exit_build()

func place_current() -> void:
	if not building:
		return
	if factory.place_ghost():
		hud.show_toast("поставлено: " + factory._label(factory.ghost_type))
		played_coin()
		# остаёмся в режиме постройки, чтобы ставить линию конвейеров подряд
	else:
		hud.show_toast("сюда нельзя или не хватает денег")

func rotate_current() -> void:
	factory.rotate_ghost()

func _place_arm() -> void:
	# ищем свободную клетку у края кучи
	for r in range(9, 16):
		for a in range(24):
			var ang := a * TAU / 24.0
			var p := pile.global_position + Vector3(cos(ang) * r, 0, sin(ang) * r)
			var c: Vector2i = factory.cell_of(p)
			if factory.is_free(c):
				factory._build("arm", c, 3, GameState.lvl("robot"))
				hud.show_toast("робо-рука %d поставлена и копает" % GameState.lvl("robot"))
				played_coin()
				return
	hud.show_toast("нет места под робо-руку — освободи площадку")

func try_interact() -> void:
	var pp: Vector3 = player.global_position
	var m = factory.machine_at_world(pp)
	if m and m.type != "belt" and m.type != "drone" and m.lvl < 5:
		if m.node.global_position.distance_to(pp) < 3.2:
			if factory.upgrade_at(factory.cell_of(pp)):
				played_coin()
			else:
				hud.show_toast("не хватает денег на апгрейд")
			return
	if _near(pp, world.station_pos, 3.6):
		if GameState.carried > 0.0:
			var n := GameState.carried
			var gain: float = GameState.sell_all()
			world.float_text(world.station_pos + Vector3(0, 1.4, 0), "+$%.5f" % gain if gain < 1.0 else "+$%.2f" % gain, Color(1, 0.88, 0.4))
			world.float_text(world.station_pos + Vector3(0.9, 0.9, 0), "%s стеблей" % GameState.fmt(n), Color(0.85, 0.95, 0.8))
			played_coin()
			world.wheel_speed = 7.0
		else:
			hud.show_toast("в руках пусто — накопай сена лопатой (зажми ЛКМ / КОПАТЬ)")
		return
	if _near(pp, world.shop_pos, 3.4):
		hud._toggle_shop(true)
		return
	if world.door_distance(pp) < 4.0:
		hud.show_toast("Двери заперты. Найди все иголки (%d / %d)" % [GameState.needles_found, GameState.NEEDLES_TOTAL])
		return

func _on_needle_scanner(where: Vector3) -> void:
	var hud2: CanvasLayer = hud
	hud2.show_popup("СКАНЕР НАШЁЛ ИГОЛКУ!")
	world.float_text(where + Vector3(0, 1.0, 0), "иголка!", Color(0.5, 1.0, 0.6))
	if GameState.needles_found >= GameState.NEEDLES_TOTAL:
		hud.show_win()

func _on_needle(n: int, total: int) -> void:
	var au := AudioStreamPlayer.new()
	au.stream = load("res://assets/sfx/needle.wav")
	add_child(au)
	au.finished.connect(au.queue_free)
	au.play()
	world.refresh_needle_label()
	hud.show_popup("ИГОЛКА!  %d / %d" % [n, total])
	if n >= total:
		hud.show_win()

func prestige() -> void:
	GameState.reset_prestige()
	get_tree().reload_current_scene()

func _process(delta: float) -> void:
	# режим постройки: призрак едет за взглядом
	if building and factory:
		var aim: Vector3 = player.aim_point()
		factory.move_ghost(aim)
	# подсказки
	var pp: Vector3 = player.global_position
	if _near(pp, world.station_pos, 3.6):
		if GameState.carried > 0.0:
			hud.set_hint("E — продать сено (%s стеблей ≈ %s)" % [GameState.fmt(GameState.carried), _price_str(GameState.carried * GameState.strand_price())])
		else:
			hud.set_hint("станция продажи: сначала накопай сена")
	elif _near(pp, world.shop_pos, 3.4):
		hud.set_hint("E — магазин и апгрейды")
	elif world.door_distance(pp) < 4.0:
		hud.set_hint("дверь заперта… загадка склада")
	else:
		var m = factory.machine_at_world(pp)
		if m and m.type != "belt" and m.type != "drone" and m.lvl < 5:
			hud.set_hint("E — улучшить %s до уровня %d ($%.2f)" % [factory._label(m.type), m.lvl + 1, factory.cost_of(m.type, m.lvl + 1)])
		else:
			hud.set_hint("")

func _price_str(v: float) -> String:
	if v >= 1.0:
		return "$%.2f" % v
	return "$%.5f" % v

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		GameState.save_game()

# ======================================================= отладка: скриншоты
func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var cam := Camera3D.new()
	cam.fov = 72.0
	add_child(cam)
	cam.make_current()
	var spots := [
		["01_обзор_склада", Vector3(-16, 7.5, 16), Vector3(0, 3.2, -4), 60.0],
		["02_куча_сена_вблизи", Vector3(6.5, 2.2, 4.5), Vector3(-2.5, 2.2, -6.5), 62.0],
		["03_станция_продажи", Vector3(-3.5, 2.2, 7.2), Vector3(0.2, 1.8, 12.0), 58.0],
		["04_магазин", Vector3(-11.5, 2.1, 7.4), Vector3(-15.5, 1.9, 9.2), 58.0],
		["05_дверь_загадка", Vector3(0, 2.3, 11.5), Vector3(0, 2.3, 16.9), 55.0],
		["06_от_первого_лица", Vector3(0, 1.55, 10.0), Vector3(0, 1.35, -8.0), 78.0],
		["07_солнечные_снопы", Vector3(-9.0, 1.6, -13.0), Vector3(7.0, 6.7, 6.0), 66.0],
		["08_вид_сверху", Vector3(-1.0, 13.5, 9.0), Vector3(0, 2.0, -5.0), 62.0],
		["09_солома_вблизи", Vector3(3.0, 1.1, -1.0), Vector3(-1.0, 1.6, -6.0), 70.0],
	]
	# в первом кадре спрячем HUD, в последнем — вернём (первое лицо)
	for i in range(spots.size()):
		hud.visible = (i == spots.size() - 1)
		var s: Array = spots[i]
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		cam.fov = s[3]
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [dir, s[0]]
		img.save_png(path)
		print("shot: ", path)
	get_tree().quit()

# ======================================================= отладка: симуляция
func _sim() -> void:
	print("симуляция копания/экономики (без графики)")
	hud.visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var t := 0.0
	var next_buy := 2.0
	var exposed := 0
	for n in pile.needles:
		pass
	while t < 240.0:
		t += 0.1
		# точка на поверхности кучи
		var ang := rng.randf() * TAU
		var r := rng.randf() * 10.0
		var p := pile.global_position + Vector3(cos(ang) * r, 0, sin(ang) * r)
		p.y = pile.height_at(p) * 0.985 + 0.03
		var removed: float = pile.dig(p, 1.3, GameState.dig_power())
		GameState.dig_gain(removed)
		if GameState.carried >= GameState.capacity() * 0.92:
			GameState.sell_all()
		if t >= next_buy:
			next_buy = t + 3.0
			for it in GameState.ITEMS:
				if it.id == "pill":
					continue
				if GameState.can_buy(it.id):
					GameState.buy(it.id)
					break
		if fmod(t, 60.0) < 0.1:
			print("t=%5.0fs денег=%s в руках=%.0f продано=%.0f сила=%.0f вместимость=%.0f осталось=%s" % [
				t, GameState.money_str(), GameState.carried, GameState.sold_total,
				GameState.dig_power(), GameState.capacity(), GameState.fmt(pile.strands_left())])
	# точечная проверка: докопаться до первой иголки
	if pile.needles.size() > 0:
		var tgt: Dictionary = pile.needles[0]
		var tp := pile.global_position + Vector3(tgt.pos.x, 0, tgt.pos.z)
		var guard := 0
		while pile.h[tgt.cell] > tgt.y and guard < 4000:
			guard += 1
			tp.y = pile.height_at(tp) * 0.99 + 0.02
			pile.dig(tp, 0.9, 3000.0)
		while pile.h[tgt.cell] > 0.05 and guard < 6000:
			guard += 1
			tp.y = pile.height_at(tp) * 0.99 + 0.02
			pile.dig(tp, 0.9, 3000.0)
		var got: bool = pile.try_pickup(pile.global_position + Vector3(tgt.pos.x, 0.5, tgt.pos.z))
		print("проверка иголки: видима=%s, подобрана=%s, найдено=%d/%d" % [pile.needles[0].node != null, got, GameState.needles_found, GameState.NEEDLES_TOTAL])
	exposed = 0
	for nd in pile.needles:
		if nd.node and nd.node.visible and not nd.taken:
			exposed += 1
	print("итог: денег=%s, выкопано=%s, продано=%s, видимых иголок=%d, осталось=%s" % [
		GameState.money_str(), GameState.fmt(GameState.dug_total), GameState.fmt(GameState.sold_total),
		exposed, GameState.fmt(pile.strands_left())])
	get_tree().quit()
