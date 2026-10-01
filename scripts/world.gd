extends Node3D
# ============================================================
#  World — склад: пол, рифлёные стены, крыша с щелями,
#  солнечные снопы, пыль в воздухе, станция продажи, магазин,
#  запертая дверь с загадкой. Плюс эффекты (солома, деньги).
# ============================================================
const W := 46.0   # ширина (x)
const D := 34.0   # глубина (z)
const H := 9.0    # высота

var sun: DirectionalLight3D
var station_pos := Vector3(0, 0, 12.0)
var shop_pos := Vector3(-15.5, 0, 9.0)
var door_pos := Vector3(0, 0, D * 0.5 - 1.1)
var wheel: Node3D
var wheel_speed := 0.6
var needle_label: Label3D
var ray_nodes: Array[Node3D] = []
var bursts: Array[GPUParticles3D] = []
var burst_i := 0
var hum: AudioStreamPlayer

var mat_conc: StandardMaterial3D
var mat_wood: StandardMaterial3D
var mat_metal: StandardMaterial3D

func _ready() -> void:
	_materials()
	_build_shell()
	_lighting()
	_rays()
	_dust()
	_build_sell_station()
	_build_shop()
	_build_door()
	_audio()

func _materials() -> void:
	mat_conc = StandardMaterial3D.new()
	mat_conc.albedo_texture = load("res://assets/tex/concrete.png")
	mat_conc.uv1_scale = Vector3(7, 7, 7)
	mat_conc.roughness = 0.95
	mat_wood = StandardMaterial3D.new()
	mat_wood.albedo_texture = load("res://assets/tex/wood.png")
	mat_wood.uv1_scale = Vector3(3, 3, 3)
	mat_wood.roughness = 0.85
	mat_metal = StandardMaterial3D.new()
	mat_metal.albedo_texture = load("res://assets/tex/metal.png")
	mat_metal.uv1_scale = Vector3(10, 4, 1)
	mat_metal.roughness = 0.55
	mat_metal.metallic = 0.55

func _box(pos: Vector3, size: Vector3, mat: Material, collide := true, uv_scale := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := mat
	if uv_scale > 0.0:
		m = mat.duplicate()
		m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		body.position = pos
		add_child(body)
	return mi

func _build_shell() -> void:
	_box(Vector3(0, -0.1, 0), Vector3(W, 0.2, D), mat_conc)                     # пол
	_box(Vector3(-W * 0.5, H * 0.5, 0), Vector3(0.3, H, D), mat_metal)          # стены
	_box(Vector3(W * 0.5, H * 0.5, 0), Vector3(0.3, H, D), mat_metal)
	_box(Vector3(0, H * 0.5, -D * 0.5), Vector3(W, H, 0.3), mat_metal)
	_box(Vector3(0, H * 0.5, D * 0.5), Vector3(W, H, 0.3), mat_metal)
	# балки под потолком
	for i in range(-3, 4):
		_box(Vector3(i * 6.5, H - 0.35, 0), Vector3(0.35, 0.7, D), mat_wood)
	# крыша: полосы железа с щелями — через них бьёт солнце
	var z := -D * 0.5
	var gap := 0.62
	var strip := 2.6
	while z < D * 0.5:
		_box(Vector3(0, H + 0.15, z + strip * 0.5), Vector3(W, 0.3, strip), mat_metal)
		z += strip + gap
	# рёбра жёсткости крыши
	for i in range(-3, 4):
		_box(Vector3(i * 6.5, H + 0.45, 0), Vector3(0.3, 0.3, D), mat_metal, false)

func _lighting() -> void:
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.rotation_degrees = Vector3(-62, 28, 0)
	add_child(sun)

	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.6, 0.85)
	sky_mat.sky_horizon_color = Color(0.85, 0.82, 0.7)
	sky_mat.ground_bottom_color = Color(0.35, 0.3, 0.24)
	sky_mat.sun_angle_max = 12.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_color = Color(1.0, 0.95, 0.86)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.35
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.8, 0.68)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.1
	env.adjustment_brightness = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _rays() -> void:
	var shader := load("res://shaders/godray.gdshader")
	var dir := -(sun.global_transform.basis * Vector3(0, 0, -1)).normalized()  # вниз по солнцу
	var z := -D * 0.5 + 2.0
	var n := 0
	while z < D * 0.5 - 1.0 and n < 9:
		n += 1
		var from := Vector3(0, H - 0.05, z)
		var length := 9.5
		for roll in range(2):
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(2.6, length)
			q.mesh = qm
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter("strength", 0.13 if roll == 0 else 0.09)
			q.material_override = m
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# ставим вдоль луча солнца
			var mid := from + dir * (length * 0.5)
			var up := -dir
			var right := Vector3(1, 0, 0)
			if roll == 1:
				right = up.cross(Vector3(1, 0, 0)).normalized()
			var fwd := right.cross(up).normalized()
			var b := Basis(right, up, fwd)
			q.global_transform = Transform3D(b, mid)
			add_child(q)
			ray_nodes.append(q)
		z += 3.3

func _dust() -> void:
	var tex := load("res://assets/tex/dot.png")
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.93, 0.78, 0.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = mat
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 26.0
	p.preprocess = 26.0
	p.draw_pass_1 = quad
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(W * 0.45, 4.5, D * 0.45)
	pm.gravity = Vector3(0, -0.012, 0)
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.07
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	pm.color = Color(1, 0.95, 0.8, 0.5)
	p.process_material = pm
	p.position = Vector3(0, 4.5, 0)
	add_child(p)

# ---------- станция продажи сена ----------
func _build_sell_station() -> void:
	var base := station_pos
	_box(base + Vector3(0, 0.55, 0), Vector3(4.6, 1.1, 1.4), mat_wood)
	_box(base + Vector3(0, 1.5, -0.55), Vector3(4.6, 1.9, 0.18), mat_metal, false)
	# вывеска SELL HAY
	var sign_mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.4, 1.28)
	sign_mi.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = load("res://assets/tex/sign_sell.png")
	sign_mi.material_override = sm
	sign_mi.position = base + Vector3(0, 2.75, -0.5)
	add_child(sign_mi)
	# приёмный лоток
	_box(base + Vector3(0, 0.9, 0.75), Vector3(2.6, 0.5, 1.1), mat_metal, false)
	# колесо-мельница
	wheel = Node3D.new()
	wheel.position = base + Vector3(-2.9, 1.7, 0.2)
	add_child(wheel)
	for k in range(6):
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 1.1, 0.5)
		blade.mesh = bm
		blade.material_override = mat_wood
		blade.position = Vector3(0, 0.55, 0).rotated(Vector3.BACK, k * PI / 3.0)
		blade.rotation.z = k * PI / 3.0
		wheel.add_child(blade)
	# лампа над станцией
	var lamp := OmniLight3D.new()
	lamp.position = base + Vector3(0, 3.6, -0.4)
	lamp.light_color = Color(1.0, 0.92, 0.72)
	lamp.light_energy = 1.4
	lamp.omni_range = 9.0
	add_child(lamp)

func _build_shop() -> void:
	var p := shop_pos
	_box(p + Vector3(0, 0.5, 0), Vector3(3.0, 1.0, 1.0), mat_wood)
	_box(p + Vector3(0, 1.6, -0.42), Vector3(3.0, 2.2, 0.16), mat_wood, false)
	var sign_mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.2, 1.1)
	sign_mi.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = load("res://assets/tex/sign_shop.png")
	sign_mi.material_override = sm
	sign_mi.position = p + Vector3(0, 3.05, -0.36)
	add_child(sign_mi)
	# пара инструментов у прилавка
	var shovel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.035
	cm.height = 1.4
	shovel.mesh = cm
	shovel.material_override = mat_wood
	shovel.position = p + Vector3(-1.7, 0.7, 0.25)
	shovel.rotation_degrees = Vector3(0, 0, 14)
	add_child(shovel)

func _build_door() -> void:
	var p := door_pos
	_box(p + Vector3(0, 2.2, 0), Vector3(5.4, 4.4, 0.35), mat_metal)
	var sign_mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.6, 1.6)
	sign_mi.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = load("res://assets/tex/sign_mystery.png")
	sm.emission_enabled = true
	sm.emission_texture = load("res://assets/tex/sign_mystery.png")
	sm.emission_energy_multiplier = 0.35
	sign_mi.material_override = sm
	sign_mi.position = p + Vector3(0, 3.2, -0.3)
	add_child(sign_mi)
	# рама и ручки, чтобы читалось как дверь
	_box(p + Vector3(-2.9, 2.2, 0.0), Vector3(0.45, 4.9, 0.6), mat_wood)
	_box(p + Vector3(2.9, 2.2, 0.0), Vector3(0.45, 4.9, 0.6), mat_wood)
	_box(p + Vector3(0, 4.55, 0.0), Vector3(6.3, 0.45, 0.6), mat_wood)
	for hx in [-1.6, 1.6]:
		var h6 := MeshInstance3D.new()
		var hm6 := CylinderMesh.new()
		hm6.top_radius = 0.05
		hm6.bottom_radius = 0.05
		hm6.height = 0.8
		h6.mesh = hm6
		h6.material_override = mat_metal
		h6.position = p + Vector3(hx, 2.0, -0.28)
		add_child(h6)
	var lock := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.7, 0.9, 0.25)
	lock.mesh = lm
	lock.material_override = mat_metal
	lock.position = p + Vector3(0, 2.0, -0.28)
	add_child(lock)
	needle_label = Label3D.new()
	needle_label.position = p + Vector3(0, 1.7, -0.34)
	needle_label.font_size = 130
	needle_label.pixel_size = 0.006
	needle_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	needle_label.rotation_degrees = Vector3(0, 180, 0)
	needle_label.modulate = Color(0.95, 0.9, 0.7)
	add_child(needle_label)
	_refresh_needle_label()

func _refresh_needle_label() -> void:
	if needle_label:
		needle_label.text = "ИГОЛКИ %d / %d" % [GameState.needles_found, GameState.NEEDLES_TOTAL]

func _audio() -> void:
	hum = AudioStreamPlayer.new()
	var st := load("res://assets/sfx/hum.wav")
	if st is AudioStreamWAV:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = st.data.size() / 2
	hum.stream = st
	hum.volume_db = -14.0
	add_child(hum)
	hum.play()

# ---------- эффекты ----------
func straw_burst(point: Vector3, count: int) -> void:
	if bursts.size() < 6:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.16, 0.03)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load("res://assets/tex/hay.png")
		mat.albedo_color = Color(1, 0.92, 0.62)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material = mat
		var p := GPUParticles3D.new()
		p.amount = 36
		p.lifetime = 1.5
		p.one_shot = true
		p.explosiveness = 0.95
		p.draw_pass_1 = quad
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 68.0
		pm.initial_velocity_min = 1.6
		pm.initial_velocity_max = 4.6
		pm.gravity = Vector3(0, -7.5, 0)
		pm.angular_velocity_min = -420.0
		pm.angular_velocity_max = 420.0
		pm.scale_min = 0.7
		pm.scale_max = 1.5
		p.process_material = pm
		add_child(p)
		bursts.append(p)
	var b := bursts[burst_i % bursts.size()]
	burst_i += 1
	b.global_position = point
	b.amount = max(8, count * 3)
	b.restart()
	b.emitting = true

func float_text(pos: Vector3, text: String, color: Color) -> void:
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = 130
	lab.pixel_size = 0.005
	lab.modulate = color
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.outline_size = 20
	lab.no_depth_test = false
	add_child(lab)
	lab.global_position = pos + Vector3(0, 0.4, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "global_position", lab.global_position + Vector3(0, 1.6, 0), 1.1)
	tw.tween_property(lab, "modulate:a", 0.0, 1.1).set_delay(0.35)
	tw.chain().tween_callback(lab.queue_free)

func _process(delta: float) -> void:
	if wheel:
		wheel.rotate_z(delta * wheel_speed)
		wheel_speed = lerp(wheel_speed, 0.6, delta * 1.5)

func door_distance(p: Vector3) -> float:
	return p.distance_to(door_pos)
