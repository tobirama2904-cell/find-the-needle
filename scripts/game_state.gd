extends Node
# ============================================================
#  GameState — экономика, апгрейды, сохранение.
#  Числа подобраны как в оригинале: 6 000 000 стеблей,
#  $0.00022 за стебель, магазин с уровнями.
# ============================================================
signal changed
signal needle_found(n, total)
signal toast(text, color)

const BASE_PRICE := 0.00022
const NEEDLES_TOTAL := 24

var money := 0.0
var carried := 0.0
var sold_total := 0.0
var dug_total := 0.0
var needles_found := 0
var stamina := 100.0
var sell_mult := 1.0
var prestige := 0
var pile_strands := 6_000_000.0
var upg := {}
var started := false
var no_save := false
var machines: Array = []

# id: [название, описание, база, рост, макс, иконка]
const ITEMS := [
	{"id": "shovel",  "name": "Лопата",        "desc": "+49 силы копания",          "base": 0.25, "grow": 4.2, "max": 9},
	{"id": "fork",    "name": "Вилы",          "desc": "+120 силы копания",         "base": 1.5,  "grow": 4.6, "max": 9},
	{"id": "bucket",  "name": "Ведро",         "desc": "+50 вместимости",           "base": 0.5,  "grow": 4.0, "max": 9},
	{"id": "barrow",  "name": "Тачка",         "desc": "+500 вместимости",          "base": 5.0,  "grow": 5.0, "max": 9},
	{"id": "vacuum",  "name": "Пылесос",       "desc": "+800 силы, +6000 вместимости","base": 60.0, "grow": 6.0, "max": 7},
	{"id": "detector","name": "Детектор+",     "desc": "+5 м к чутью иголок",       "base": 2.0,  "grow": 3.6, "max": 9},
	{"id": "robot",   "name": "Робо-рука",     "desc": "сама копает и продаёт сено","base": 25.0, "grow": 6.0, "max": 6},
	{"id": "strength","name": "Сила",          "desc": "+25 к запасу сил",          "base": 1.0,  "grow": 3.0, "max": 10},
	{"id": "endurance","name": "Выносливость", "desc": "+50% к восстановлению",     "base": 1.0,  "grow": 3.0, "max": 10},
	{"id": "speed",   "name": "Скорость рук",  "desc": "замах быстрее на 14%",      "base": 1.0,  "grow": 3.2, "max": 8},
	{"id": "boots",   "name": "Кроссовки",     "desc": "+8% скорости ходьбы",       "base": 2.0,  "grow": 3.0, "max": 8},
	{"id": "pill",    "name": "Таблетка",      "desc": "мгновенно все силы",        "base": 0.3,  "grow": 1.0, "max": 9999},
]

func _ready() -> void:
	load_game()

func item(id: String) -> Dictionary:
	for it in ITEMS:
		if it.id == id:
			return it
	return {}

func lvl(id: String) -> int:
	return int(upg.get(id, 0))

func price(id: String) -> float:
	var it := item(id)
	if it.is_empty():
		return 0.0
	return it.base * pow(it.grow, lvl(id))

func can_buy(id: String) -> bool:
	return lvl(id) < int(item(id).max) and money + 1e-9 >= price(id)

func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	money -= price(id)
	if id == "pill":
		stamina = stamina_max()
	else:
		upg[id] = lvl(id) + 1
		if id == "strength":
			stamina = min(stamina_max(), stamina + 25.0)
	emit_signal("changed")
	save_game_soon()
	return true

# ---------- производные величины ----------
func dig_power() -> float:
	return 12.0 + lvl("shovel") * 60.0 + lvl("fork") * 150.0 + lvl("vacuum") * 900.0

func capacity() -> float:
	return 25.0 + lvl("bucket") * 90.0 + lvl("barrow") * 600.0 + lvl("vacuum") * 6000.0

func swing_time() -> float:
	return 0.46 * pow(0.86, lvl("speed"))

func walk_speed() -> float:
	return 4.0 * (1.0 + lvl("boots") * 0.08)

func stamina_max() -> float:
	return 100.0 + lvl("strength") * 25.0

func regen() -> float:
	return 11.0 * (1.0 + lvl("endurance") * 0.5)

func detector_range() -> float:
	return 10.0 + lvl("detector") * 5.0

func robot_rate() -> float:
	return lvl("robot") * 120.0     # стеблей/сек автоматически

func strand_price() -> float:
	return BASE_PRICE * sell_mult

# ---------- действия ----------
func dig_gain(n: float) -> float:
	# сколько реально унесём в руках (остальное осыпается)
	var room: float = max(0.0, capacity() - carried)
	var take: float = min(n, room)
	carried += take
	dug_total += n
	emit_signal("changed")
	return take

func sell_all() -> float:
	if carried <= 0.0:
		return 0.0
	var gain: float = carried * strand_price()
	money += gain
	sold_total += carried
	carried = 0.0
	emit_signal("changed")
	save_game_soon()
	return gain

func give(n: float) -> void:
	money += n
	emit_signal("changed")

func use_stamina(cost: float) -> bool:
	if stamina >= cost:
		stamina -= cost
		return true
	return false

func _process(delta: float) -> void:
	if not started:
		return
	if stamina < stamina_max():
		stamina = min(stamina_max(), stamina + regen() * delta)

# ---------- сохранение ----------
var _save_t := 0.0
func save_game_soon() -> void:
	_save_t = 1.0

func _physics_process(delta: float) -> void:
	if _save_t > 0.0:
		_save_t -= delta
		if _save_t <= 0.0:
			save_game()

func save_game() -> void:
	if no_save:
		return
	var d := {
		"money": money, "sold_total": sold_total, "dug_total": dug_total,
		"needles_found": needles_found, "sell_mult": sell_mult, "prestige": prestige,
		"pile_strands": pile_strands, "upg": upg, "started": started, "stamina": stamina,
		"machines": machines,
	}
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists("user://save.json"):
		return
	var f := FileAccess.open("user://save.json", FileAccess.READ)
	if not f:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return
	money = float(d.get("money", 0.0))
	sold_total = float(d.get("sold_total", 0.0))
	dug_total = float(d.get("dug_total", 0.0))
	needles_found = int(d.get("needles_found", 0))
	sell_mult = float(d.get("sell_mult", 1.0))
	prestige = int(d.get("prestige", 0))
	pile_strands = float(d.get("pile_strands", 6_000_000.0))
	upg = d.get("upg", {})
	started = bool(d.get("started", false))
	stamina = float(d.get("stamina", stamina_max()))
	machines = d.get("machines", [])

func reset_prestige() -> void:
	needles_found = 0
	machines = []
	carried = 0.0
	prestige += 1
	sell_mult *= 1.25
	pile_strands = 6_000_000.0 * pow(1.6, prestige)
	save_game()

func money_str_pre(v: float) -> String:
	var save := money
	money = v
	var r := money_str()
	money = save
	return r

func money_str() -> String:
	if money >= 1000.0:
		return "$%s" % fmt(money)
	if money >= 1.0:
		return "$%.2f" % money
	return "$%.5f" % money

func fmt(v: float) -> String:
	var s := "%.0f" % v
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = " " + out
	return out
