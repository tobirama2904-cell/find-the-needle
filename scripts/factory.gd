extends Node3D
# ============================================================
#  Factory — фабрика поверх оригинала:
#   робо-рука копает сено → конвейеры везут → сканер ищет иголки →
#   упаковщик делает тюки (дороже) → станция продажи платит.
#   Дрон летает над стогом и подсвечивает спрятанные иголки.
# ============================================================
signal built(text: String)
signal needle_by_scanner(pos: Vector3)

const CELL := 1.0
const COST := {"belt": 3.0, "packer": 40.0, "scanner": 75.0, "drone": 120.0}
const UPGRADE_MULT := 2.3

var pile: Node3D
var world: Node3D

var belts := {}        # Vector2i -> Belt
var machines := {}     # Vector2i -> Dictionary
var drones: Array[Node3D] = []
var _arm_phase := 0.0
var _arm_buf := 0.0
var _drone_t := 0.0
var _scanner_flash := 0.0

# режим постройки
var ghost: Node3D
var ghost_type := ""
var ghost_rot := 0
var ghost_cell := Vector2i.ZERO
var ghost_ok := false
var building := false

var _belt_script: GDScript

func _ready() -> void:
	_belt_script = load("res://scripts/belt.gd")
	_load_saved()

func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))

func cell_pos(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL + CELL * 0.5, 0.0, c.y * CELL + CELL * 0.5)

func is_free(c: Vector2i) -> bool:
	if belts.has(c) or machines.has(c):
		return false
	# не ставим внутрь кучи
	var p := cell_pos(c)
	if pile and pile.height_at(p) > 0.25:
		return false
	# и не в станцию продажи
	if world and Vector2(p.x - world.station_pos.x, p.z - world.station_pos.z).length() < 2.2:
		return false
	return true

# ---------------------------------------------------------- постройка
func can_afford(t: String, lvl := 1) -> bool:
	return GameState.money >= cost_of(t, lvl)

func cost_of(t: String, lvl := 1) -> float:
	var base: float = COST.get(t, 10.0)
	return base * pow(UPGRADE_MULT, lvl - 1)

func enter_build(t: String) -> void:
	ghost_type = t
	building = true
	ghost_rot = 0
	if ghost:
		ghost.queue_free()
	ghost = _make_mesh(t, 1)
	ghost.set_meta("ghost", true)
	_set_ghost_transparent(ghost)
	add_child(ghost)

func exit_build() -> void:
	building = false
	ghost_type = ""
	if ghost:
		ghost.queue_free()
		ghost = null

func rotate_ghost() -> void:
	ghost_rot = (ghost_rot + 1) % 4
	if ghost:
		ghost.rotation.y = ghost_rot * PI * 0.5

func move_ghost(to: Vector3) -> void:
	ghost_cell = cell_of(to)
	if ghost:
		ghost.position = cell_pos(ghost_cell)
	ghost_ok = is_free(ghost_cell) and can_afford(ghost_type, 1)

func place_ghost() -> bool:
	if not building or not ghost_ok:
		return false
	var t := ghost_type
	var c := ghost_cell
	var r := ghost_rot
	if not spend(t, 1):
		return false
	_build(t, c, r, 1)
	return true

func spend(t: String, lvl: int) -> bool:
	var cost := cost_of(t, lvl)
	if GameState.money < cost:
		return false
	GameState.money -= cost
	GameState.emit_signal("changed")
	return true

func _build(t: String, c: Vector2i, r: int, lvl: int) -> void:
	var node := _make_mesh(t, lvl)
	node.position = cell_pos(c)
	node.rotation.y = r * PI * 0.5
	add_child(node)
	if t == "belt":
		belts[c] = node
		node.set("dir", r)
	elif t == "drone":
		drones.append(node)
	else:
		machines[c] = {"type": t, "rot": r, "lvl": lvl, "node": node}
	GameState.machines.append({"t": t, "x": c.x, "z": c.y, "r": r, "l": lvl})
	GameState.changed.emit()
	emit_signal("built", _label(t) + " поставлен")

func _label(t: String) -> String:
	match t:
		"belt": return "Конвейер"
		"packer": return "Упаковщик"
		"scanner": return "Сканер"
		"drone": return "Дрон"
		"arm": return "Робо-рука"
	return t

# ---------------------------------------------------------- модели машин
func _make_mesh(t: String, lvl: int) -> Node3D:
	var root := Node3D.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_texture = load("res://assets/tex/metal.png")
	metal.uv1_scale = Vector3(2, 2, 2)
	metal.metallic = 0.55
	metal.roughness = 0.5
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://assets/tex/wood.png")
	wood.uv1_scale = Vector3(2, 2, 2)
	wood.roughness = 0.9

	match t:
		"belt":
			root.set_script(_belt_script)
			root.set("dir", 0)
			root.call("setup", 0)
		"arm":
			var base := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.7, 0.5, 0.7)
			base.mesh = bm
			base.material_override = metal
			base.position = Vector3(0, 0.25, 0)
			root.add_child(base)
			var col := Node3D.new()
			col.position = Vector3(0, 0.5, 0)
			col.name = "Column"
			root.add_child(col)
			var seg1 := MeshInstance3D.new()
			var c1 := CylinderMesh.new()
			c1.top_radius = 0.09
			c1.bottom_radius = 0.11
			c1.height = 1.1
			seg1.mesh = c1
			seg1.material_override = metal
			seg1.position = Vector3(0, 0.55, 0)
			col.add_child(seg1)
			var top := Node3D.new()
			top.name = "Top"
			top.position = Vector3(0, 1.1, 0)
			col.add_child(top)
			var seg2 := MeshInstance3D.new()
			var c2 := CylinderMesh.new()
			c2.top_radius = 0.06
			c2.bottom_radius = 0.08
			c2.height = 0.9
			seg2.mesh = c2
			seg2.material_override = metal
			seg2.rotation_degrees = Vector3(0, 0, 90)
			seg2.position = Vector3(0.45, 0, 0)
			top.add_child(seg2)
			var claw := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.22, 0.12, 0.3)
			claw.mesh = cm
			claw.material_override = metal
			claw.position = Vector3(0.9, 0, 0)
			top.add_child(claw)
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1, 0.8, 0.4)
			lamp.light_energy = 0.5
			lamp.omni_range = 3.0
			lamp.position = Vector3(0.9, 0, 0)
			top.add_child(lamp)
		"packer":
			var body := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(1.1, 1.0, 1.1)
			body.mesh = bb
			body.material_override = metal
			body.position = Vector3(0, 0.5, 0)
			root.add_child(body)
			var piston := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.9, 0.25, 0.9)
			piston.mesh = pm
			piston.material_override = metal
			piston.position = Vector3(0, 1.15, 0)
			piston.name = "Piston"
			root.add_child(piston)
			var bale := MeshInstance3D.new()
			var bmm := BoxMesh.new()
			bmm.size = Vector3(0.6, 0.4, 0.6)
			bale.mesh = bmm
			var bmat := StandardMaterial3D.new()
			bmat.albedo_texture = load("res://assets/tex/hay.png")
			bale.material_override = bmat
			bale.position = Vector3(0.85, 0.2, 0.0)
			bale.name = "Bale"
			root.add_child(bale)
		"scanner":
			for sx in [-1.0, 1.0]:
				var post := MeshInstance3D.new()
				var pmm := BoxMesh.new()
				pmm.size = Vector3(0.16, 1.5, 0.16)
				post.mesh = pmm
				post.material_override = metal
				post.position = Vector3(sx * 0.45, 0.75, 0)
				root.add_child(post)
			var top := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(1.06, 0.16, 0.2)
			top.mesh = tm
			top.material_override = metal
			top.position = Vector3(0, 1.55, 0)
			root.add_child(top)
			var beam := MeshInstance3D.new()
			var bqm := QuadMesh.new()
			bqm.size = Vector2(0.8, 1.3)
			beam.mesh = bqm
			var bmat := StandardMaterial3D.new()
			bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bmat.albedo_color = Color(0.4, 1.0, 0.6, 0.16)
			bmat.emission_enabled = true
			bmat.emission = Color(0.3, 1.0, 0.5)
			bmat.emission_energy_multiplier = 1.2
			bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			beam.material_override = bmat
			beam.position = Vector3(0, 0.8, 0)
			beam.name = "Beam"
			root.add_child(beam)
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(0.4, 1.0, 0.6)
			lamp.light_energy = 0.6
			lamp.omni_range = 3.5
			lamp.position = Vector3(0, 1.5, 0)
			root.add_child(lamp)
		"drone":
			var body := MeshInstance3D.new()
			var db := BoxMesh.new()
			db.size = Vector3(0.4, 0.12, 0.4)
			body.mesh = db
			body.material_override = metal
			root.add_child(body)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var rotor := MeshInstance3D.new()
					var rm := CylinderMesh.new()
					rm.top_radius = 0.16
					rm.bottom_radius = 0.16
					rm.height = 0.02
					rotor.mesh = rm
					var rmat := StandardMaterial3D.new()
					rmat.albedo_color = Color(0.1, 0.1, 0.12)
					rotor.material_override = rmat
					rotor.position = Vector3(sx * 0.28, 0.06, sz * 0.28)
					rotor.name = "Rotor%s%s" % [int(sx), int(sz)]
					root.add_child(rotor)
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(0.6, 0.85, 1.0)
			lamp.light_energy = 0.7
			lamp.omni_range = 4.0
			lamp.position = Vector3(0, -0.1, 0)
			root.add_child(lamp)
	return root

func _set_ghost_transparent(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.4, 1.0, 0.5, 0.45)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			c.material_override = m
		_set_ghost_transparent(c)

# ---------------------------------------------------------- апгрейды машин
func upgrade_at(c: Vector2i) -> bool:
	if not machines.has(c):
		return false
	var m: Dictionary = machines[c]
	if m.type == "drone":
		return false
	var lvl: int = m.lvl + 1
	if lvl > 5 or not spend(m.type, lvl):
		return false
	m.lvl = lvl
	var node: Node3D = m.node
	node.scale = Vector3.ONE * (1.0 + 0.06 * (lvl - 1))
	GameState.changed.emit()
	emit_signal("built", "%s → уровень %d" % [_label(m.type), lvl])
	# отметка в сохранении
	for rec in GameState.machines:
		if rec.x == c.x and rec.z == c.y and rec.t == m.type:
			rec.l = lvl
	_save()
	return true

func machine_at_world(p: Vector3):
	var c := cell_of(p)
	if machines.has(c):
		return machines[c]
	if belts.has(c):
		return {"type": "belt", "lvl": 1, "node": belts[c], "cell": c}
	return null

# ---------------------------------------------------------- фабричный цикл
func _machines_of(t: String) -> Array:
	var out := []
	for c in machines:
		if machines[c].type == t:
			out.append(machines[c])
	return out

func _process(delta: float) -> void:
	# --- робо-руки копают
	var arms := _machines_of("arm")
	_arm_phase += delta
	for m in arms:
		var node: Node3D = m.node
		var top := node.get_node_or_null("Column/Top")
		if top:
			top.rotation.y = sin(_arm_phase * 1.7) * 0.9
			top.rotation.z = -0.35 + abs(sin(_arm_phase * 1.7)) * 0.35
		var rate: float = 60.0 * float(m.lvl)
		var c: Vector2i = _cell_of_machine(m)
		# рука реально копает стог вокруг себя
		var removed: float = pile.dig_auto_near(node.global_position + Vector3(3.5, 0, 0), 5.0, rate * delta)
		_arm_buf += removed
		if _arm_buf < 140.0:
			continue
		var lumps := int(_arm_buf / 140.0)
		_arm_buf -= lumps * 140.0
		for li in range(lumps):
			var out_cell: Vector2i = c + _rot_vec(m.rot)
			if belts.has(out_cell) and not belts[out_cell].is_full():
				belts[out_cell].add_item(140.0)
			else:
				_sell_direct(140.0 * 0.35)

	# --- конвейеры передают куски дальше
	for c in belts.keys():
		var belt = belts[c]
		var finished := 0
		while not belt.items.is_empty() and belt.items[0] >= 1.0:
			var next: Vector2i = c + belt.dir_vec()
			var it: Dictionary = belt.take_item()
			var amount: float = it.a
			var value: float = it.v
			if belts.has(next) and not belts[next].is_full():
				belts[next].add_item(amount, value)
			elif machines.has(next):
				var m2: Dictionary = machines[next]
				var out_c: Vector2i = next + _rot_vec(m2.rot)
				if m2.type == "packer":
					value *= 1.6 + 0.4 * float(m2.lvl)      # тюк дороже
					if belts.has(out_c) and not belts[out_c].is_full():
						belts[out_c].add_item(amount, value)
					else:
						_sell_direct(amount, value)
				elif m2.type == "scanner":
					_scan(amount, m2)
					if belts.has(out_c) and not belts[out_c].is_full():
						belts[out_c].add_item(amount, value)
					else:
						_sell_direct(amount, value)
				else:
					_sell_direct(amount, value * 0.35)
			else:
				_sell_direct(amount, value)                     # конец линии — платим полностью
			finished += 1
			if finished > 6:
				break

	# --- упаковщики: анимация поршня и пачки
	for c in machines:
		var m: Dictionary = machines[c]
		var node: Node3D = m.node
		if m.type == "packer":
			var piston := node.get_node_or_null("Piston")
			if piston:
				piston.position.y = 1.15 - abs(sin(_arm_phase * 2.2)) * 0.22
			var bale := node.get_node_or_null("Bale")
			if bale:
				bale.position.y = 0.2 + abs(sin(_arm_phase * 1.1)) * 0.06
		elif m.type == "scanner":
			var beam := node.get_node_or_null("Beam")
			if beam:
				var bm := beam.material_override as StandardMaterial3D
				if bm:
					bm.albedo_color.a = 0.12 + 0.08 * sin(_arm_phase * 3.0)

	# --- дроны
	_drone_t += delta
	for i in range(drones.size()):
		var d: Node3D = drones[i]
		var ang: float = _arm_phase * 0.35 + i * TAU / max(1.0, float(drones.size()))
		var r := 9.0 + 2.5 * sin(_arm_phase * 0.2 + i)
		var pos := Vector3(cos(ang) * r, 9.2 + 0.5 * sin(_arm_phase * 1.3 + i), sin(ang) * r) + pile.global_position
		d.global_position = pos
		d.rotation.y = -ang
		for rn in d.get_children():
			if rn.name.begins_with("Rotor"):
				rn.rotation.y += delta * 40.0
		if _drone_t > 6.0 and i == 0:
			_drone_t = 0.0
			_scan_visual()

	# --- призрак в режиме постройки
	if building and ghost:
		ghost.scale = Vector3.ONE * (1.0 + 0.02 * sin(_arm_phase * 6.0))

func _cell_of_machine(m: Dictionary) -> Vector2i:
	for c in machines:
		if machines[c] == m:
			return c
	return Vector2i.ZERO

func _rot_vec(r: int) -> Vector2i:
	match r:
		0: return Vector2i(1, 0)
		1: return Vector2i(0, 1)
		2: return Vector2i(-1, 0)
	return Vector2i(0, -1)

func _sell_direct(amount: float, value := -1.0) -> void:
	if amount <= 0.0:
		return
	var v: float = value if value >= 0.0 else amount
	GameState.money += v * GameState.strand_price()
	GameState.sold_total += amount
	GameState.dug_total += amount

# --------------------------------------------------- сканер и дрон
func _scan(amount: float, m: Dictionary) -> bool:
	var chance: float = 3.2e-6 * float(m.lvl)
	if OS.get_cmdline_user_args().has("--fastscan"):
		chance *= 400.0
	if randf() >= amount * chance:
		return false
	for n in pile.needles:
		if n.taken:
			continue
		var where: Vector3 = n.node.global_position if n.node else pile.global_position
		n.taken = true
		if n.node:
			n.node.queue_free()
			n.node = null
		GameState.needles_found += 1
		GameState.give(25.0)
		emit_signal("needle_by_scanner", where)
		if world:
			world.float_text(m.node.global_position + Vector3(0, 1.9, 0), "СКАНЕР: ИГОЛКА!", Color(0.5, 1.0, 0.6))
		GameState.emit_signal("needle_found", GameState.needles_found, GameState.NEEDLES_TOTAL)
		GameState.emit_signal("changed")
		return true
	return false

var _marked: Node3D
func _scan_visual() -> void:
	# дрон подсвечивает ближайшую спрятанную иголку вертикальным лучом
	var best = null
	var bd := 1e9
	var p := drones[0].global_position if drones.size() > 0 else Vector3.ZERO
	for n in pile.needles:
		if n.taken or (n.node and n.node.visible):
			continue
		var tgt := pile.global_position + Vector3(n.pos.x, 0, n.pos.z)
		var d: float = Vector2(tgt.x - p.x, tgt.z - p.z).length()
		if d < bd:
			bd = d
			best = n
	if best == null:
		return
	if _marked and is_instance_valid(_marked):
		_marked.queue_free()
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.16
	cyl.height = 9.0
	beam.mesh = cyl
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.45, 1.0, 0.7, 0.28)
	m.emission_enabled = true
	m.emission = Color(0.4, 1.0, 0.6)
	m.emission_energy_multiplier = 1.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = m
	add_child(beam)
	var tgt2 := pile.global_position + Vector3(best.pos.x, best.y * 0.5 + 4.5, best.pos.z)
	beam.global_position = tgt2
	_marked = beam
	var tw := create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 5.0)
	tw.tween_callback(func():
		if is_instance_valid(beam):
			beam.queue_free())

# ---------------------------------------------------------- сохранение
func _save() -> void:
	GameState.save_game_soon()

func _load_saved() -> void:
	for rec in GameState.machines:
		var c := Vector2i(int(rec.x), int(rec.z))
		if not is_free(c) and rec.t != "belt":
			continue
		_build_silent(rec.t, c, int(rec.r), int(rec.l))

func _build_silent(t: String, c: Vector2i, r: int, lvl: int) -> void:
	var node := _make_mesh(t, lvl)
	node.position = cell_pos(c)
	node.rotation.y = r * PI * 0.5
	add_child(node)
	if t == "belt":
		belts[c] = node
		node.set("dir", r)
		if node.has_method("setup"):
			node.rotation.y = r * PI * 0.5
	elif t == "drone":
		drones.append(node)
	else:
		machines[c] = {"type": t, "rot": r, "lvl": lvl, "node": node}

func totals() -> Dictionary:
	var out := {"belts": belts.size(), "arms": 0, "packers": 0, "scanners": 0, "drones": drones.size(),
		"rate": 0.0}
	for c in machines:
		var m: Dictionary = machines[c]
		match m.type:
			"arm":
				out.arms += 1
				out.rate += 60.0 * m.lvl
			"packer": out.packers += 1
			"scanner": out.scanners += 1
	return out
