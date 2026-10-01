extends Node3D
# ============================================================
#  Belt — сегмент конвейера. Везёт «куски» сена (кол-во стеблей)
#  от робо-руки до станции продажи, упаковщика или сканера.
# ============================================================
const LEN := 1.0
const LUMPS := 4                # сколько кусков видно одновременно
const PER_LUMP := 140.0         # стеблей в одном куске

var dir := 2                    # 0=+x, 1=+z, 2=-x, 3=-z
var cell := Vector2i.ZERO
var speed := 1.5                # м/с
var items: Array[float] = []    # прогресс 0..1
var amounts: Array[float] = []  # стеблей в куске
var values: Array[float] = []   # «стебель-эквиваленты» (упаковщик повышает)
var mat: StandardMaterial3D
var lumps: MultiMesh
var _uv := 0.0

func dir_vec() -> Vector2i:
	match dir:
		0: return Vector2i(1, 0)
		1: return Vector2i(0, 1)
		2: return Vector2i(-1, 0)
	return Vector2i(0, -1)

func yaw() -> float:
	return dir * PI * 0.5

func setup(d: int) -> void:
	dir = d
	var frame := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.92, 0.07, 0.92)
	frame.mesh = bm
	mat = StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/tex/metal.png")
	mat.uv1_scale = Vector3(2.4, 1, 1)
	mat.roughness = 0.5
	mat.metallic = 0.5
	frame.material_override = mat
	frame.position = Vector3(0, 0.34, 0)
	add_child(frame)
	# борта
	for sx in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.06, 0.16, 0.92)
		rail.mesh = rm
		rail.material_override = mat
		rail.position = Vector3(sx * 0.46, 0.44, 0)
		add_child(rail)
	# ножки
	for sz in [-0.32, 0.32]:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.035
		lm.bottom_radius = 0.045
		lm.height = 0.34
		leg.mesh = lm
		leg.material_override = mat
		leg.position = Vector3(0, 0.17, sz)
		add_child(leg)
	rotation.y = yaw()
	# куски сена на ленте
	lumps = MultiMesh.new()
	lumps.transform_format = MultiMesh.TRANSFORM_3D
	var lb := BoxMesh.new()
	lb.size = Vector3(0.3, 0.16, 0.26)
	lumps.mesh = lb
	lumps.instance_count = LUMPS
	var lmat := StandardMaterial3D.new()
	lmat.albedo_texture = load("res://assets/tex/hay.png")
	lmat.roughness = 0.95
	var lm_node := MultiMeshInstance3D.new()
	lm_node.multimesh = lumps
	lm_node.material_override = lmat
	add_child(lm_node)
	for i in range(LUMPS):
		lumps.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO)))

func add_item(amount: float, value := -1.0) -> bool:
	if items.size() >= LUMPS * 2:
		return false
	items.append(-0.02)
	amounts.append(amount)
	values.append(value if value >= 0.0 else amount)
	return true

func take_item() -> Dictionary:
	if items.is_empty():
		return {"a": 0.0, "v": 0.0}
	items.pop_front()
	return {"a": amounts.pop_front(), "v": values.pop_front()}

func is_full() -> bool:
	return items.size() >= LUMPS * 2

func _process(delta: float) -> void:
	_uv += delta * speed * 0.8
	if mat:
		mat.uv1_offset = Vector3(_uv, 0, 0)
	for i in range(items.size()):
		items[i] += delta * speed / LEN
	for i in range(LUMPS):
		if i < items.size():
			var p: float = clamp(items[i], 0.0, 1.0)
			var t := Transform3D()
			t = t.rotated(Vector3.UP, yaw())
			var f := Vector3(0, 0, -LEN) * 0.5
			var back := Vector3(0, 0, LEN) * 0.5
			t.origin = f.lerp(back, p) + Vector3(0, 0.5, 0)
			lumps.set_instance_transform(i, t)
		else:
			lumps.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO)))
