extends Node3D
# ============================================================
#  HayPile — гора сена. 48x48 колонн по 0.5 м, ~6 млн стеблей.
#  Копание уменьшает высоту колонн, они оседают, солома разлетается.
#  Внутри спрятаны иголки — металлоискатель чует их по расстоянию.
#
#  Оптимизация: солома рисуется MultiMesh'ом, раскладка соломинок
#  посчитана заранее, при копании пересчитываются ТОЛЬКО задетые
#  колонны. Поэтому копание дешёвое даже на телефоне.
# ============================================================
const GRID := 56
const CELL := 0.5
const RADIUS := 13.0
const HEIGHT := 7.6
const DENSITY := 4400.0
const STRAW_BUDGET := 48000

var h := PackedFloat32Array()
var h0 := PackedFloat32Array()
var needles := []

var lump_mm: MultiMesh
var straw_mm: MultiMesh
var lump_idx := PackedInt32Array()      # колонна -> индекс инстанса колоба (или -1)
var straw_off := PackedInt32Array()     # колонна -> первая соломинка
var straw_cnt := PackedInt32Array()     # колонна -> сколько соломинок
var straw_base := PackedFloat32Array()  # 7 чисел на соломинку
var straw_total := 0
var _cell_dirty := PackedByteArray()
var _dirty := false
var _last_coll := 0.0

var col: CollisionShape3D
var body: StaticBody3D
var _auto_order: Array[int] = []

signal dug(amount: float, point: Vector3)
signal needle_exposed(pos: Vector3)
signal needle_taken(n: int, total: int)

func _ready() -> void:
	h0.resize(GRID * GRID)
	h.resize(GRID * GRID)
	_cell_dirty.resize(GRID * GRID)
	_build_profile()
	_build_multimeshes()
	_plant_needles()
	_build_collision()

func idx(i: int, j: int) -> int:
	return j * GRID + i

func cell_of(p: Vector3) -> Vector2i:
	var i := int(floor((p.x - global_position.x) / CELL + GRID * 0.5))
	var j := int(floor((p.z - global_position.z) / CELL + GRID * 0.5))
	return Vector2i(clampi(i, 0, GRID - 1), clampi(j, 0, GRID - 1))

func height_at(p: Vector3) -> float:
	var c := cell_of(p)
	return h[idx(c.x, c.y)]

func inside_pile(p: Vector3) -> bool:
	return p.y < height_at(p) + 0.02

func strands_left() -> float:
	var s := 0.0
	for v in h:
		s += v
	return s * CELL * CELL * DENSITY

# ---------------------------------------------------------- профиль кучи
func _build_profile() -> void:
	var total := 0.0
	for j in range(GRID):
		for i in range(GRID):
			var dx := (i - GRID * 0.5 + 0.5) * CELL
			var dz := (j - GRID * 0.5 + 0.5) * CELL
			var d := sqrt(dx * dx + dz * dz)
			var v := 0.0
			if d < RADIUS:
				var t: float = clamp(1.0 - d / RADIUS, 0.0, 1.0)
				v = HEIGHT * pow(t, 1.12)
				v *= 1.0 + 0.06 * sin(dx * 1.7) * cos(dz * 1.3)
			h0[idx(i, j)] = max(0.0, v)
			total += max(0.0, v)
	var scale_to: float = GameState.pile_strands / max(1.0, total * CELL * CELL * DENSITY)
	for k in range(h0.size()):
		h0[k] *= scale_to
	h = h0.duplicate()

# ---------------------------------------------------------- мультимеши
func _build_multimeshes() -> void:
	var hay_mat := StandardMaterial3D.new()
	hay_mat.albedo_texture = load("res://assets/tex/hay.png")
	hay_mat.uv1_scale = Vector3(2, 2, 2)
	hay_mat.roughness = 0.97

	# --- колобы сена
	lump_mm = MultiMesh.new()
	lump_mm.transform_format = MultiMesh.TRANSFORM_3D
	var cm := SphereMesh.new()
	cm.radius = 0.5
	cm.height = 1.0
	cm.radial_segments = 9
	cm.rings = 5
	lump_mm.mesh = cm
	lump_idx.resize(GRID * GRID)
	var count := 0
	for k in range(GRID * GRID):
		if h0[k] > 0.12:
			lump_idx[k] = count
			count += 1
		else:
			lump_idx[k] = -1
	lump_mm.instance_count = max(count, 1)
	var lump_node := MultiMeshInstance3D.new()
	lump_node.multimesh = lump_mm
	lump_node.material_override = hay_mat
	add_child(lump_node)

	# --- соломинки: раскладка считается один раз
	straw_off.resize(GRID * GRID)
	straw_cnt.resize(GRID * GRID)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260901
	var acc := 0
	var layout := PackedFloat32Array()
	# считаем веса, потом нормируем под бюджет инстансов
	var want := PackedFloat32Array()
	var total_want := 0.0
	for k in range(GRID * GRID):
		var v := h0[k]
		var w: float = 0.0 if v <= 0.2 else clamp(16.0 + v * 8.0, 12.0, 58.0)
		want.append(w)
		total_want += w
	var k_scale: float = min(1.0, STRAW_BUDGET / max(1.0, total_want))
	for k in range(GRID * GRID):
		var v := h0[k]
		if v <= 0.2:
			straw_off[k] = -1
			straw_cnt[k] = 0
			continue
		var n: int = max(3, int(want[k] * k_scale))
		straw_off[k] = acc
		straw_cnt[k] = n
		acc += n
		for s in range(n):
			var u := rng.randf() * TAU
			var cv: float = pow(rng.randf(), 0.7) * 0.92
			var si := sin(acos(1.0 - cv))
			layout.append(cos(u) * si)                       # ux
			layout.append(sin(u) * si)                       # uz
			layout.append(cv)                                # uy (0..0.92)
			layout.append(rng.randf() * TAU)                 # yaw
			layout.append((rng.randf() - 0.5) * 0.85)        # pitch
			layout.append((rng.randf() - 0.5) * 0.6)         # roll
			layout.append(0.8 + rng.randf() * 0.4)           # яркость
	straw_base = layout
	straw_total = acc
	straw_mm = MultiMesh.new()
	straw_mm.transform_format = MultiMesh.TRANSFORM_3D
	straw_mm.use_colors = true
	var smesh := BoxMesh.new()
	smesh.size = Vector3(0.5, 0.02, 0.02)
	straw_mm.mesh = smesh
	straw_mm.instance_count = max(straw_total, 1)
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.roughness = 0.85
	smat.metallic = 0.05
	var straw_node := MultiMeshInstance3D.new()
	straw_node.multimesh = straw_mm
	straw_node.material_override = smat
	add_child(straw_node)

	refresh_visuals(true)

func _set_lump(k: int) -> void:
	var li := lump_idx[k]
	if li < 0:
		return
	var v := h[k]
	if v <= 0.12:
		lump_mm.set_instance_transform(li, Transform3D(Basis().scaled(Vector3.ZERO)))
		return
	var i := k % GRID
	var j := k / GRID
	var x := (i - GRID * 0.5 + 0.5) * CELL
	var z := (j - GRID * 0.5 + 0.5) * CELL
	var t := Transform3D()
	t = t.rotated(Vector3.UP, float((i * 7 + j * 13) % 31) * 0.1)
	t = t.scaled(Vector3(1.16 + 0.05 * sin(i), v * 1.06, 1.16 + 0.05 * cos(j)))
	t.origin = Vector3(x + 0.03 * sin(j * 2.1), v * 0.5, z + 0.03 * cos(i * 1.7))
	lump_mm.set_instance_transform(li, t)

func _set_straws(k: int) -> void:
	var off := straw_off[k]
	if off < 0:
		return
	var n := straw_cnt[k]
	var v := h[k]
	var i := k % GRID
	var j := k / GRID
	var x := (i - GRID * 0.5 + 0.5) * CELL
	var z := (j - GRID * 0.5 + 0.5) * CELL
	if v <= 0.2:
		var zero := Transform3D(Basis().scaled(Vector3.ZERO))
		for s in range(n):
			straw_mm.set_instance_transform(off + s, zero)
		return
	for s in range(n):
		var b := (off + s) * 7
		var ux := straw_base[b]
		var uz := straw_base[b + 1]
		var uy := straw_base[b + 2]
		var yaw := straw_base[b + 3]
		var pitch := straw_base[b + 4]
		var roll := straw_base[b + 5]
		var bright := straw_base[b + 6]
		var pos := Vector3(x + ux * 0.62, max(0.02, v * (0.66 + 0.34 * uy)), z + uz * 0.62)
		var t := Transform3D()
		t = t.rotated(Vector3.UP, yaw)
		t = t.rotated(Vector3.RIGHT, pitch)
		t = t.rotated(Vector3.FORWARD, roll)
		t.origin = pos
		straw_mm.set_instance_transform(off + s, t)
		straw_mm.set_instance_color(off + s, Color(min(1.0, bright * 1.08), bright * 0.92, bright * 0.5))

func refresh_visuals(full := false) -> void:
	if full:
		for k in range(GRID * GRID):
			_set_lump(k)
			_set_straws(k)
	else:
		for k in range(GRID * GRID):
			if _cell_dirty[k] == 1:
				_cell_dirty[k] = 0
				_set_lump(k)
				_set_straws(k)

# ---------------------------------------------------------- столкновения
func _build_collision() -> void:
	body = StaticBody3D.new()
	add_child(body)
	col = CollisionShape3D.new()
	col.shape = _make_heightmap()
	col.scale = Vector3(CELL, 1.0, CELL)
	body.add_child(col)

func _make_heightmap() -> HeightMapShape3D:
	var hm := HeightMapShape3D.new()
	hm.map_width = GRID
	hm.map_depth = GRID
	var data := PackedFloat32Array()
	data.resize(GRID * GRID)
	for j in range(GRID):
		for i in range(GRID):
			data[j * GRID + i] = h[idx(i, j)]
	hm.map_data = data
	return hm

func _push_collision() -> void:
	var hm := col.shape as HeightMapShape3D
	var data := PackedFloat32Array()
	data.resize(GRID * GRID)
	for j in range(GRID):
		for i in range(GRID):
			data[j * GRID + i] = h[idx(i, j)]
	hm.map_data = data

# ---------------------------------------------------------- иголки
func _plant_needles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777 + GameState.prestige * 31
	var placed: Array[Vector3] = []
	var tries := 0
	while needles.size() < GameState.NEEDLES_TOTAL and tries < 60000:
		tries += 1
		var i := rng.randi_range(0, GRID - 1)
		var j := rng.randi_range(0, GRID - 1)
		var k := idx(i, j)
		var v := h0[k]
		if v < 1.6:
			continue
		var x := (i - GRID * 0.5 + 0.5) * CELL
		var z := (j - GRID * 0.5 + 0.5) * CELL
		var p := Vector3(x, 0, z)
		var ok := true
		for q in placed:
			if q.distance_to(p) < 2.2:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var y := v * rng.randf_range(0.25, 0.92)
		needles.append({"cell": k, "pos": p, "y": y, "taken": false, "node": null})
	for n in needles:
		var nd := _make_needle_mesh()
		nd.position = Vector3(n.pos.x, n.y, n.pos.z)
		nd.visible = false
		add_child(nd)
		n.node = nd

func _make_needle_mesh() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/tex/needle.png")
	mat.metallic = 1.0
	mat.roughness = 0.15
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 0.6
	cyl.radial_segments = 8
	shaft.mesh = cyl
	shaft.material_override = mat
	shaft.rotation_degrees = Vector3(0, 0, 78)
	root.add_child(shaft)
	var eye := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.02
	tor.outer_radius = 0.035
	eye.mesh = tor
	eye.material_override = mat
	eye.position = Vector3(0.28, 0.13, 0)
	eye.rotation_degrees = Vector3(0, 0, 78)
	root.add_child(eye)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.95, 0.7)
	glow.light_energy = 0.8
	glow.omni_range = 2.4
	root.add_child(glow)
	return root

func nearest_needle(p: Vector3) -> float:
	var best := 1e9
	for n in needles:
		if n.taken:
			continue
		var tgt := Vector3(n.pos.x, n.node.global_position.y, n.pos.z)
		best = min(best, p.distance_to(tgt))
	return best

func needles_left() -> int:
	var c := 0
	for n in needles:
		if not n.taken:
			c += 1
	return c

# ---------------------------------------------------------- копание
func dig(point: Vector3, radius: float, power: float) -> float:
	var lp := to_local(point)            # работаем в локальных координатах кучи
	var c := cell_of(point)
	var ri := int(ceil(radius / CELL))
	var cands := []
	for dj in range(-ri, ri + 1):
		for di in range(-ri, ri + 1):
			var i := c.x + di
			var j := c.y + dj
			if i < 0 or j < 0 or i >= GRID or j >= GRID:
				continue
			var k := idx(i, j)
			if h[k] <= 0.02:
				continue
			var x := (i - GRID * 0.5 + 0.5) * CELL
			var z := (j - GRID * 0.5 + 0.5) * CELL
			var d := Vector2(x - lp.x, z - lp.z).length()
			if d <= radius:
				cands.append([d, k])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var removed := 0.0
	var per_cell := CELL * CELL * DENSITY
	for e in cands:
		if removed >= power:
			break
		var k: int = e[1]
		var avail: float = h[k] * per_cell
		var take: float = min(avail, power - removed)
		h[k] = max(0.0, h[k] - take / per_cell)
		_cell_dirty[k] = 1
		removed += take
	if removed > 0.0:
		_dirty = true
		emit_signal("dug", removed, point)
		_update_needles_visibility()
	return removed

func dig_auto_near(point: Vector3, radius: float, amount: float) -> float:
	var lp := to_local(point)
	var c := cell_of(point)
	var ri := int(ceil(radius / CELL))
	var removed := 0.0
	var per := CELL * CELL * DENSITY
	for dj in range(-ri, ri + 1):
		for di in range(-ri, ri + 1):
			if removed >= amount:
				break
			var i := c.x + di
			var j := c.y + dj
			if i < 0 or j < 0 or i >= GRID or j >= GRID:
				continue
			var k := idx(i, j)
			if h[k] <= 0.25:
				continue
			var x := (i - GRID * 0.5 + 0.5) * CELL
			var z := (j - GRID * 0.5 + 0.5) * CELL
			if Vector2(x - lp.x, z - lp.z).length() > radius:
				continue
			var take: float = min(h[k] * per * 0.5, amount - removed)
			if take <= 0.0:
				continue
			h[k] = max(0.0, h[k] - take / per)
			_cell_dirty[k] = 1
			removed += take
	if removed > 0.0:
		_dirty = true
		_update_needles_visibility()
	return removed

func dig_auto(amount: float) -> float:
	if _auto_order.is_empty():
		for k in range(GRID * GRID):
			_auto_order.append(k)
		_auto_order.shuffle()
	var per := CELL * CELL * DENSITY
	var removed := 0.0
	for k in _auto_order:
		if removed >= amount:
			break
		if h[k] <= 0.25:
			continue
		var take: float = min(h[k] * per * 0.25, amount - removed)
		if take <= 0.0:
			continue
		h[k] = max(0.0, h[k] - take / per)
		_cell_dirty[k] = 1
		removed += take
	if removed > 0.0:
		_dirty = true
		_update_needles_visibility()
	return removed

func _update_needles_visibility() -> void:
	for n in needles:
		if n.taken or not n.node:
			continue
		var cur := h[n.cell]
		if cur <= n.y and not n.node.visible:
			n.node.visible = true
			emit_signal("needle_exposed", n.node.global_position)
		if n.node.visible:
			n.node.position = Vector3(n.pos.x, max(0.08, cur + 0.07), n.pos.z)

func try_pickup(p: Vector3) -> bool:
	for n in needles:
		if n.taken or not n.node or not n.node.visible:
			continue
		if p.distance_to(n.node.global_position) < 1.9:
			n.taken = true
			n.node.queue_free()
			GameState.needles_found += 1
			GameState.give(25.0 * (1.0 + GameState.prestige))
			emit_signal("needle_taken", GameState.needles_found, GameState.NEEDLES_TOTAL)
			return true
	return false

func _physics_process(delta: float) -> void:
	if _dirty:
		_last_coll += delta
		if _last_coll > 0.18:
			_last_coll = 0.0
			_dirty = false
			_push_collision()
			refresh_visuals(false)
