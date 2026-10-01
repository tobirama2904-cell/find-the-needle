extends CharacterBody3D
# ============================================================
#  Player — вид от первого лица, копание, металлоискатель,
#  выносливость, управление с клавиатуры и с телефона.
# ============================================================
signal hint(text: String)
signal stats_changed

const EYE := 1.55
const GRAVITY := 16.0
const JUMP := 4.6

var cam: Camera3D
var pile: Node3D
var world: Node3D

var touch_move := Vector2.ZERO      # джойстик
var touch_jump := false             # кнопка прыжка (телефон)
var touch_look := Vector2.ZERO      # свайп
var dig_held := false
var interact_queued := false

var _swing_t := 0.0
var _stamina_hint_t := 0.0
var _beep_t := 0.0
var _step_t := 0.0
var _bob := 0.0
var _swing_anim := 0.0
var _no_stamina_t := 0.0

var sfx_dig: AudioStreamPlayer
var sfx_beep: AudioStreamPlayer
var sfx_coin: AudioStreamPlayer
var sfx_thud: AudioStreamPlayer

var hands: Node3D
var tool_holder: Node3D
var detector_node: Node3D

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	shape.shape = cap
	shape.position = Vector3(0, 0.85, 0)
	add_child(shape)

	cam = Camera3D.new()
	cam.fov = 78.0
	cam.position = Vector3(0, EYE, 0)
	cam.near = 0.05
	add_child(cam)

	_build_viewmodel()

	sfx_dig = _snd("dig.wav")
	sfx_beep = _snd("beep.wav")
	sfx_coin = _snd("coin.wav")
	sfx_thud = _snd("thud.wav")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _snd(f: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/sfx/" + f)
	var bus_index := AudioServer.get_bus_index("Master")
	p.max_polyphony = 6
	add_child(p)
	return p

# ---------- моделька инструмента в руках ----------
func _build_viewmodel() -> void:
	hands = Node3D.new()
	hands.position = Vector3(0.40, -0.40, -0.62)
	cam.add_child(hands)
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://assets/tex/wood.png")
	wood.uv1_scale = Vector3(2, 2, 2)
	wood.roughness = 0.9
	var steel := StandardMaterial3D.new()
	steel.albedo_texture = load("res://assets/tex/needle.png")
	steel.metallic = 0.9
	steel.roughness = 0.35

	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.024
	hm.bottom_radius = 0.03
	hm.height = 0.72
	hm.radial_segments = 10
	handle.mesh = hm
	handle.material_override = wood
	handle.rotation_degrees = Vector3(-58, 6, 10)
	handle.position = Vector3(0.02, -0.02, 0.02)
	hands.add_child(handle)

	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.025, 0.26)
	blade.mesh = bm
	blade.material_override = steel
	blade.position = Vector3(0.1, -0.34, -0.16)
	blade.rotation_degrees = Vector3(-58, 6, 10)
	hands.add_child(blade)
	# кулак
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.6, 0.47)
	skin.roughness = 0.75
	var fist := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.085
	fm.height = 0.17
	fist.mesh = fm
	fist.material_override = skin
	fist.scale = Vector3(1.0, 0.8, 1.15)
	fist.position = Vector3(0.0, -0.06, 0.02)
	hands.add_child(fist)

	# рука-детектор (вторая рука)
	detector_node = Node3D.new()
	detector_node.position = Vector3(-0.46, -0.34, -0.52)
	cam.add_child(detector_node)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.11
	tm.outer_radius = 0.145
	ring.mesh = tm
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.08, 0.09, 0.11)
	black.roughness = 0.6
	ring.material_override = black
	ring.rotation_degrees = Vector3(78, 0, 0)
	detector_node.add_child(ring)
	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.024
	cm.height = 0.5
	stick.mesh = cm
	stick.material_override = black
	stick.position = Vector3(0, -0.26, 0)
	detector_node.add_child(stick)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.044
	lamp.mesh = sm
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.2, 1.0, 0.4)
	green.emission_enabled = true
	green.emission = Color(0.3, 1.0, 0.45)
	green.emission_energy_multiplier = 2.0
	lamp.material_override = green
	lamp.name = "Lamp"
	lamp.position = Vector3(0, 0.02, 0)
	detector_node.add_child(lamp)
	# кулак на ручке детектора
	var skin2 := StandardMaterial3D.new()
	skin2.albedo_color = Color(0.78, 0.6, 0.47)
	skin2.roughness = 0.75
	var fist2 := MeshInstance3D.new()
	var fm2 := SphereMesh.new()
	fm2.radius = 0.08
	fm2.height = 0.16
	fist2.mesh = fm2
	fist2.material_override = skin2
	fist2.scale = Vector3(1.0, 0.8, 1.15)
	fist2.position = Vector3(0, -0.5, 0)
	detector_node.add_child(fist2)

# ---------- ввод ----------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := 0.0022
		rotate_y(-event.relative.x * s)
		cam.rotation.x = clamp(cam.rotation.x - event.relative.y * s, -1.45, 1.45)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dig_held = true
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dig_held = false
	if event is InputEventScreenDrag:
		touch_look += event.relative
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _desktop_dir() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	return v.normalized()

# ---------- кадр ----------
func _physics_process(delta: float) -> void:
	# обзор (телефон)
	if touch_look.length() > 0.0:
		var s := 0.004
		rotate_y(-touch_look.x * s)
		cam.rotation.x = clamp(cam.rotation.x - touch_look.y * s, -1.45, 1.45)
		touch_look = Vector2.ZERO

	var dir := _desktop_dir()
	if touch_move.length() > 0.05:
		dir = touch_move

	var speed := GameState.walk_speed()
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 1.65

	var wish := Vector3(dir.x, 0, dir.y).rotated(Vector3.UP, rotation.y)
	if wish.length() > 0.001:
		wish = wish.normalized()
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif (Input.is_physical_key_pressed(KEY_SPACE) or touch_jump) and GameState.stamina > 5.0:
		velocity.y = JUMP
		GameState.stamina -= 4.0
	touch_jump = false

	move_and_slide()

	# покачивание камеры
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	if moving and is_on_floor():
		_bob += delta * 9.0
		cam.position.y = EYE + sin(_bob) * 0.035
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.42
			sfx_thud.pitch_scale = randf_range(0.85, 1.15)
			sfx_thud.volume_db = -20.0
			sfx_thud.play()
	else:
		cam.position.y = lerp(cam.position.y, EYE, delta * 6.0)

	# копание
	_swing_t -= delta
	if dig_held and _swing_t <= 0.0:
		_do_swing()
	# анимация замаха
	_swing_anim = max(0.0, _swing_anim - delta * 5.0)
	hands.rotation_degrees.x = -28.0 * sin(_swing_anim * PI)
	hands.position.z = -0.55 - 0.08 * sin(_swing_anim * PI)
	detector_node.rotation_degrees.z = sin(Time.get_ticks_msec() * 0.0016) * 0.05

	_no_stamina_t = max(0.0, _no_stamina_t - delta)
	_detector(delta)
	if pile:
		pile.try_pickup(global_position)

func _do_swing() -> void:
	_swing_t = GameState.swing_time()
	if GameState.carried >= GameState.capacity() - 0.5:
		if _no_stamina_t <= 0.0:
			_no_stamina_t = 2.5
			emit_signal("hint", "руки полны — продай сено на станции (E)")
		return
	if GameState.stamina < 3.0:
		if _no_stamina_t <= 0.0:
			_no_stamina_t = 3.0
			emit_signal("hint", "Сил нет! Купи таблетку в магазине (Tab)")
		return
	if not pile:
		return
	# куда смотрим: ищем точку в куче вдоль луча
	var fwd := -cam.global_transform.basis.z
	var origin := cam.global_position
	var hit := Vector3.ZERO
	var found := false
	var t := 0.6
	while t < 3.4:
		var p := origin + fwd * t
		if pile.inside_pile(p):
			hit = p
			found = true
			break
		t += 0.15
	if not found:
		return
	if global_position.distance_to(hit) > 4.0:
		return
	GameState.stamina -= 3.0
	var removed: float = pile.dig(hit, 1.15, GameState.dig_power())
	if removed <= 0.0:
		return
	GameState.dig_gain(removed)
	_swing_anim = 1.0
	sfx_dig.pitch_scale = randf_range(0.9, 1.12)
	sfx_dig.volume_db = -8.0
	sfx_dig.play()
	if world and world.has_method("straw_burst"):
		world.straw_burst(hit, int(clamp(removed / 40.0, 4.0, 22.0)))
	emit_signal("stats_changed")

# ---------- металлоискатель ----------
func _detector(delta: float) -> void:
	if not pile:
		return
	var d: float = pile.nearest_needle(global_position)
	var rng: float = GameState.detector_range()
	var lamp := detector_node.get_node_or_null("Lamp")
	if lamp:
		var mat := lamp.material_override as StandardMaterial3D
		if d < rng:
			var k: float = clamp(1.0 - d / rng, 0.0, 1.0)
			mat.albedo_color = Color(0.2 + 0.8 * k, 1.0 - 0.7 * k, 0.3 - 0.2 * k)
			mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = 1.5 + 3.0 * k
		else:
			mat.albedo_color = Color(0.15, 0.5, 0.25)
			mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = 1.0
	if d < rng:
		var k: float = clamp(1.0 - d / rng, 0.0, 1.0)
		var interval: float = lerp(1.5, 0.12, k)
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = interval
			sfx_beep.pitch_scale = 0.8 + k * 0.9
			sfx_beep.volume_db = -14.0 + k * 6.0
			sfx_beep.play()
	else:
		_beep_t = 0.0

func aim_point(max_dist := 14.0) -> Vector3:
	# точка, куда смотрит игрок, спроецированная на пол (y=0)
	var fwd := -cam.global_transform.basis.z
	var o := cam.global_position
	if fwd.y >= -0.02:
		return o + fwd * 3.0
	var t: float = min(max_dist, -o.y / fwd.y)
	var p := o + fwd * t
	p.y = 0.0
	return p

func look_dir() -> Vector3:
	return -cam.global_transform.basis.z
