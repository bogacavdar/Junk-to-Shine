extends Node3D
## Temizlik prototipi — tüm sahne kodla kurulur, dışarıdan model gerekmez.
## Döngü: yıka / yaprak temizle / çöp topla -> konteynerde sat -> 1/2/3 ile yükselt.

const PlayerScript := preload("res://scripts/player.gd")
const DirtShader := preload("res://shaders/dirt.gdshader")

const AREA_SIZE := 40.0          # temizlenecek alanın kenarı (metre)
const MASK_RES := 256            # kir maskesi çözünürlüğü
const CLEAN_THRESHOLD := 40      # bu değerin altındaki piksel "temiz" sayılır (0-255)
const PIXELS_PER_COIN := 25      # kaç temiz piksel = 1 para
const REACH := 5.0               # aletin oyuncudan en uzak erişimi
const TRASH_COUNT := 70
const LEAF_COUNT := 1400
const COMPLETE_PCT := 95.0
const COMPLETE_BONUS := 250

# --- Yükseltme fiyatları (bir sonraki seviyenin fiyatı) ---
const BRUSH_PRICES := [40, 120, 300, 700]     # seviye 2..5
const BAG_PRICES := [30, 90, 250, 600]        # seviye 2..5
const VACUUM_PRICES := [60, 180, 450]         # seviye 1..3

var brush_level := 1
var bag_level := 1
var vacuum_level := 0

# --- Ekonomi ---
var money := 0
var shown_money := 0.0
var bag := 0
var bag_value := 0

# --- Kir maskesi ---
var mask_data := PackedByteArray()
var mask_image: Image
var mask_texture: ImageTexture
var ground_material: ShaderMaterial
var dirty_pixel_total := 0
var clean_pixel_count := 0
var cleaned_since_payout := 0
var clean_pct := 0.0
var next_milestone := 25
var completed := false

# --- Sahne parçaları ---
var player: PlayerScript
var camera: Camera3D
var cam_offset := Vector3(0, 17, 11)
var env: Environment
var sun: DirectionalLight3D
var aim_ring: MeshInstance3D
var spray: CPUParticles3D
var container_pos := Vector3(-AREA_SIZE * 0.5 + 3.5, 0, AREA_SIZE * 0.5 - 3.5)
var trash_bodies: Array[RigidBody3D] = []
var tree_positions: Array[Vector3] = []

# --- Yapraklar (binlerce, fizik yok) ---
var leaf_mm: MultiMeshInstance3D
var leaf_positions := PackedVector3Array()
var leaf_alive := PackedByteArray()
var leaves_left := 0

# --- Ses ---
var blip_stream: AudioStreamWAV
var coin_stream: AudioStreamWAV
var blip_players: Array[AudioStreamPlayer] = []
var blip_index := 0
var spray_player: AudioStreamPlayer
var combo := 0
var combo_timer := 0.0
var tick_cooldown := 0.0

# --- Arayüz ---
var money_label: Label
var bag_label: Label
var pct_label: Label
var progress_bar: ProgressBar
var shop_label: Label
var info_label: Label
var banner_label: Label


func _ready() -> void:
	randomize()
	_setup_input()
	_build_environment()
	_build_ground()
	_build_props()
	_build_container()
	_build_player()
	_spawn_all_trash()
	_build_leaves()
	_build_tool_visuals()
	_build_audio()
	_build_hud()
	_update_hud()


# =====================================================================
# KURULUM
# =====================================================================

func _setup_input() -> void:
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("move_up", [KEY_W, KEY_UP])
	_add_key_action("move_down", [KEY_S, KEY_DOWN])


func _add_key_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.55   # alan temizlendikçe artar
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.92, 0.82)
	add_child(sun)


func _build_ground() -> void:
	# Çevredeki çimen (temizlenmez)
	var grass := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(140, 140)
	gm.material = _mat(Color(0.36, 0.55, 0.28))
	grass.mesh = gm
	grass.position.y = -0.02
	add_child(grass)

	# Kir maskesi: gürültüyle farklı yoğunlukta kir
	mask_data.resize(MASK_RES * MASK_RES)
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.025
	for y in MASK_RES:
		for x in MASK_RES:
			var n := noise.get_noise_2d(x, y)
			var v := int(clampf(205.0 + n * 100.0, 130.0, 255.0))
			mask_data[y * MASK_RES + x] = v
			if v >= CLEAN_THRESHOLD:
				dirty_pixel_total += 1
	mask_image = Image.create_from_data(MASK_RES, MASK_RES, false, Image.FORMAT_L8, mask_data)
	mask_texture = ImageTexture.create_from_image(mask_image)

	ground_material = ShaderMaterial.new()
	ground_material.shader = DirtShader
	ground_material.set_shader_parameter("dirt_mask", mask_texture)
	ground_material.set_shader_parameter("area_size", AREA_SIZE)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(AREA_SIZE, AREA_SIZE)
	pm.material = ground_material
	ground.mesh = pm
	add_child(ground)

	# Zemin çarpışması
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(140, 1, 140)
	cs.shape = bs
	cs.position.y = -0.5
	floor_body.add_child(cs)
	add_child(floor_body)


func _build_props() -> void:
	var half := AREA_SIZE * 0.5
	var wood := Color(0.55, 0.38, 0.22)
	# Çit (alanın sınırı)
	_add_static_box(Vector3(0, 0.45, -half), Vector3(AREA_SIZE, 0.9, 0.3), wood)
	_add_static_box(Vector3(0, 0.45, half), Vector3(AREA_SIZE, 0.9, 0.3), wood)
	_add_static_box(Vector3(-half, 0.45, 0), Vector3(0.3, 0.9, AREA_SIZE), wood)
	_add_static_box(Vector3(half, 0.45, 0), Vector3(0.3, 0.9, AREA_SIZE), wood)

	# Ev (alanın dışında, arkada)
	_add_static_box(Vector3(-6, 2.0, -half - 5), Vector3(9, 4, 6), Color(0.85, 0.78, 0.65))
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(10, 2.6, 7)
	prism.material = _mat(Color(0.65, 0.25, 0.2))
	roof.mesh = prism
	roof.position = Vector3(-6, 5.3, -half - 5)
	add_child(roof)

	# Ağaçlar (alanın içinde)
	for p in [Vector3(9, 0, -8), Vector3(-11, 0, -4), Vector3(13, 0, 10)]:
		_add_tree(p)
	for p in [Vector3(-26, 0, 6), Vector3(26, 0, -10), Vector3(24, 0, 16), Vector3(8, 0, -28)]:
		_add_tree(p)


func _add_tree(pos: Vector3) -> void:
	tree_positions.append(pos)
	var body := StaticBody3D.new()
	body.position = pos
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.22
	trunk.height = 1.4
	trunk.radial_segments = 6
	trunk.material = _mat(Color(0.42, 0.28, 0.16))
	_add_child_mesh(body, trunk, Vector3(0, 0.7, 0))
	var leaf_mat := _mat(Color(0.25, 0.5, 0.22))
	var cone1 := CylinderMesh.new()
	cone1.top_radius = 0.0
	cone1.bottom_radius = 1.4
	cone1.height = 2.0
	cone1.radial_segments = 6
	cone1.material = leaf_mat
	_add_child_mesh(body, cone1, Vector3(0, 2.2, 0))
	var cone2 := CylinderMesh.new()
	cone2.top_radius = 0.0
	cone2.bottom_radius = 1.05
	cone2.height = 1.6
	cone2.radial_segments = 6
	cone2.material = leaf_mat
	_add_child_mesh(body, cone2, Vector3(0, 3.2, 0))
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 2.0
	cs.shape = shape
	cs.position.y = 1.0
	body.add_child(cs)
	add_child(body)


func _build_container() -> void:
	_add_static_box(container_pos + Vector3(0, 0.7, 0), Vector3(2.6, 1.4, 1.7), Color(0.15, 0.55, 0.3))
	var lbl := Label3D.new()
	lbl.text = "SAT"
	lbl.font_size = 96
	lbl.outline_size = 16
	lbl.pixel_size = 0.01
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = container_pos + Vector3(0, 2.4, 0)
	add_child(lbl)


func _build_player() -> void:
	player = PlayerScript.new()
	player.position = Vector3(0, 0.1, AREA_SIZE * 0.5 - 5)
	add_child(player)

	camera = Camera3D.new()
	camera.fov = 50
	add_child(camera)
	camera.global_position = player.global_position + cam_offset
	camera.look_at(player.global_position + Vector3(0, 0.5, 0), Vector3.UP)


func _spawn_all_trash() -> void:
	var half := AREA_SIZE * 0.5 - 1.5
	var placed := 0
	var tries := 0
	while placed < TRASH_COUNT and tries < 2000:
		tries += 1
		var p := Vector3(randf_range(-half, half), 0.6, randf_range(-half, half))
		if p.distance_to(container_pos) < 5.0:
			continue
		var near_tree := false
		for t in tree_positions:
			if Vector2(p.x - t.x, p.z - t.z).length() < 1.2:
				near_tree = true
				break
		if near_tree:
			continue
		_spawn_trash(p)
		placed += 1


func _spawn_trash(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1 | 2
	body.mass = 0.5
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var shape_size := Vector3(0.4, 0.4, 0.4)
	var value := 3
	var roll := randf()
	if roll < 0.3:
		var can := CylinderMesh.new()
		can.top_radius = 0.13
		can.bottom_radius = 0.13
		can.height = 0.32
		can.radial_segments = 8
		can.material = _mat(Color(0.8, 0.15, 0.15), 0.35)
		mi.mesh = can
		shape_size = Vector3(0.26, 0.32, 0.26)
		value = 3
	elif roll < 0.55:
		var bottle := CylinderMesh.new()
		bottle.top_radius = 0.06
		bottle.bottom_radius = 0.12
		bottle.height = 0.5
		bottle.radial_segments = 8
		bottle.material = _mat(Color(0.2, 0.6, 0.35), 0.2)
		mi.mesh = bottle
		shape_size = Vector3(0.24, 0.5, 0.24)
		value = 4
	elif roll < 0.8:
		var box := BoxMesh.new()
		box.size = Vector3(0.55, 0.4, 0.45)
		box.material = _mat(Color(0.7, 0.55, 0.35))
		mi.mesh = box
		shape_size = box.size
		value = 5
	elif roll < 0.95:
		var sack := SphereMesh.new()
		sack.radius = 0.32
		sack.height = 0.55
		sack.radial_segments = 6
		sack.rings = 3
		sack.material = _mat(Color(0.12, 0.12, 0.14), 0.4)
		mi.mesh = sack
		shape_size = Vector3(0.6, 0.5, 0.6)
		value = 6
	else:
		var tire := TorusMesh.new()
		tire.inner_radius = 0.22
		tire.outer_radius = 0.45
		tire.rings = 10
		tire.ring_segments = 6
		tire.material = _mat(Color(0.1, 0.1, 0.1))
		mi.mesh = tire
		shape_size = Vector3(0.9, 0.25, 0.9)
		value = 12
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = shape_size
	cs.shape = bs
	body.add_child(mi)
	body.add_child(cs)
	body.set_meta("value", value)
	body.position = pos
	body.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	add_child(body)
	trash_bodies.append(body)


func _build_leaves() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var leaf := BoxMesh.new()
	leaf.size = Vector3(0.22, 0.02, 0.16)
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.roughness = 0.9
	leaf.material = lm
	mm.mesh = leaf
	mm.instance_count = LEAF_COUNT

	# Yapraklar ağaçların çevresinde ve rüzgârla savrulmuş öbeklerde toplanır
	var centers: Array[Vector3] = []
	for t in tree_positions:
		if absf(t.x) < AREA_SIZE * 0.5 and absf(t.z) < AREA_SIZE * 0.5:
			centers.append(t)
	for i in 5:
		centers.append(Vector3(randf_range(-15, 15), 0, randf_range(-15, 15)))

	var half := AREA_SIZE * 0.5 - 0.6
	var palette := [Color(0.85, 0.45, 0.12), Color(0.75, 0.25, 0.1), Color(0.9, 0.7, 0.2), Color(0.55, 0.35, 0.15)]
	leaf_positions.resize(LEAF_COUNT)
	leaf_alive.resize(LEAF_COUNT)
	for i in LEAF_COUNT:
		var c: Vector3 = centers[randi() % centers.size()]
		var ang := randf() * TAU
		var r := sqrt(randf()) * 4.5
		var p := Vector3(clampf(c.x + cos(ang) * r, -half, half), 0.02, clampf(c.z + sin(ang) * r, -half, half))
		leaf_positions[i] = p
		leaf_alive[i] = 1
		var basis := Basis(Vector3.UP, randf() * TAU)
		mm.set_instance_transform(i, Transform3D(basis, p))
		var col: Color = palette[randi() % palette.size()]
		mm.set_instance_color(i, col)
	leaves_left = LEAF_COUNT

	leaf_mm = MultiMeshInstance3D.new()
	leaf_mm.multimesh = mm
	add_child(leaf_mm)


func _build_tool_visuals() -> void:
	# Hedef halkası
	aim_ring = MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 1.0
	disk.bottom_radius = 1.0
	disk.height = 0.02
	disk.radial_segments = 24
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.6, 0.9, 1.0, 0.25)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disk.material = rm
	aim_ring.mesh = disk
	add_child(aim_ring)

	# Su sıçraması
	spray = CPUParticles3D.new()
	spray.emitting = false
	spray.amount = 60
	spray.lifetime = 0.45
	var drop := SphereMesh.new()
	drop.radius = 0.05
	drop.height = 0.1
	drop.radial_segments = 4
	drop.rings = 2
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.7, 0.9, 1.0)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = dm
	spray.mesh = drop
	spray.direction = Vector3.UP
	spray.spread = 55.0
	spray.initial_velocity_min = 2.0
	spray.initial_velocity_max = 4.5
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spray.emission_sphere_radius = 0.5
	add_child(spray)


func _build_audio() -> void:
	blip_stream = _make_blip(880.0, 0.07)
	coin_stream = _make_blip(1320.0, 0.12)
	for i in 6:
		var ap := AudioStreamPlayer.new()
		ap.volume_db = -8.0
		add_child(ap)
		blip_players.append(ap)
	spray_player = AudioStreamPlayer.new()
	spray_player.stream = _make_noise_loop(1.0)
	spray_player.volume_db = -18.0
	add_child(spray_player)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	money_label = _make_label(layer, Vector2(24, 14), 36, Color(1.0, 0.86, 0.3))
	bag_label = _make_label(layer, Vector2(24, 62), 24, Color.WHITE)

	progress_bar = ProgressBar.new()
	progress_bar.position = Vector2(440, 22)
	progress_bar.size = Vector2(400, 26)
	progress_bar.max_value = 100.0
	progress_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.8, 0.55)
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(6)
	progress_bar.add_theme_stylebox_override("fill", fill)
	progress_bar.add_theme_stylebox_override("background", bg)
	layer.add_child(progress_bar)
	pct_label = _make_label(layer, Vector2(440, 50), 20, Color.WHITE)
	pct_label.size = Vector2(400, 30)
	pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	shop_label = _make_label(layer, Vector2(930, 14), 20, Color.WHITE)
	info_label = _make_label(layer, Vector2(24, 676), 18, Color(1, 1, 1, 0.85))
	info_label.text = "WASD: yürü   ·   Sol tık basılı: yıka   ·   Çöplerin üstünden geç: topla   ·   Konteyner: sat   ·   1 / 2 / 3: yükselt"

	banner_label = _make_label(layer, Vector2(0, 250), 64, Color(0.6, 1.0, 0.75))
	banner_label.size = Vector2(1280, 100)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.visible = false


# =====================================================================
# OYUN DÖNGÜSÜ
# =====================================================================

func _process(delta: float) -> void:
	# Kamera takibi
	var target := player.global_position + cam_offset
	camera.global_position = camera.global_position.lerp(target, clampf(5.0 * delta, 0.0, 1.0))

	# Nişan noktası
	var aim := player.global_position
	var hit: Variant = _mouse_ground_point()
	if hit != null:
		var h: Vector3 = hit
		var off := Vector3(h.x - player.global_position.x, 0, h.z - player.global_position.z)
		if off.length() > REACH:
			off = off.normalized() * REACH
		aim = player.global_position + off
		var lim := AREA_SIZE * 0.5 - 0.3
		aim.x = clampf(aim.x, -lim, lim)
		aim.z = clampf(aim.z, -lim, lim)
		aim.y = 0.0
	player.face(aim)

	var r := brush_radius()
	aim_ring.global_position = aim + Vector3(0, 0.03, 0)
	aim_ring.scale = Vector3(r, 1, r)

	var cleaning := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not completed
	spray.global_position = aim + Vector3(0, 0.1, 0)
	spray.emission_sphere_radius = r * 0.6
	spray.emitting = cleaning
	if cleaning:
		_clean_at(aim, delta)
		_clean_leaves(aim)
		if not spray_player.playing:
			spray_player.play()
	elif spray_player.playing:
		spray_player.stop()

	# Temizlikten gelen para
	tick_cooldown -= delta
	while cleaned_since_payout >= PIXELS_PER_COIN:
		cleaned_since_payout -= PIXELS_PER_COIN
		money += 1
		if tick_cooldown <= 0.0:
			_play_blip(blip_stream, 1.4 + randf() * 0.3, -14.0)
			tick_cooldown = 0.09

	combo_timer -= delta
	if combo_timer <= 0.0:
		combo = 0

	# Satış
	if bag > 0 and Vector2(player.global_position.x - container_pos.x, player.global_position.z - container_pos.z).length() < 3.2:
		_sell()

	_update_progress()
	shown_money = move_toward(shown_money, float(money), maxf(1.0, absf(money - shown_money)) * delta * 6.0)
	_update_hud()


func _physics_process(_delta: float) -> void:
	var ppos := player.global_position
	var full := bag >= bag_capacity()
	for body in trash_bodies.duplicate():
		if not is_instance_valid(body):
			trash_bodies.erase(body)
			continue
		if full:
			continue
		var to_player := ppos - body.global_position
		to_player.y = 0.0
		var dist := to_player.length()
		if dist < pickup_radius():
			_collect_trash(body)
			full = bag >= bag_capacity()
		elif vacuum_level > 0 and dist < vacuum_radius():
			body.sleeping = false
			body.apply_central_force(to_player.normalized() * (10.0 + 8.0 * vacuum_level) * body.mass)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				_buy_brush()
			KEY_2:
				_buy_bag()
			KEY_3:
				_buy_vacuum()


# =====================================================================
# TEMİZLİK
# =====================================================================

func _clean_at(world_pos: Vector3, delta: float) -> void:
	var u := (world_pos.x + AREA_SIZE * 0.5) / AREA_SIZE
	var v := (world_pos.z + AREA_SIZE * 0.5) / AREA_SIZE
	var cx := int(u * MASK_RES)
	var cy := int(v * MASK_RES)
	var r_px := maxi(1, int(ceil(brush_radius() / AREA_SIZE * MASK_RES)))
	var amount := brush_strength() * delta
	var changed := false
	for y in range(maxi(cy - r_px, 0), mini(cy + r_px + 1, MASK_RES)):
		for x in range(maxi(cx - r_px, 0), mini(cx + r_px + 1, MASK_RES)):
			var dx: int = x - cx
			var dy: int = y - cy
			var dist := sqrt(float(dx * dx + dy * dy)) / float(r_px)
			if dist > 1.0:
				continue
			var idx: int = y * MASK_RES + x
			var old: int = mask_data[idx]
			if old == 0:
				continue
			var falloff := 1.0 - dist * dist
			var nv := int(maxf(0.0, float(old) - amount * falloff))
			mask_data[idx] = nv
			changed = true
			if old >= CLEAN_THRESHOLD and nv < CLEAN_THRESHOLD:
				clean_pixel_count += 1
				cleaned_since_payout += 1
	if changed:
		mask_image.set_data(MASK_RES, MASK_RES, false, Image.FORMAT_L8, mask_data)
		mask_texture.update(mask_image)


func _clean_leaves(p: Vector3) -> void:
	var r := brush_radius() * 1.15
	var r2 := r * r
	for i in LEAF_COUNT:
		if leaf_alive[i] == 0:
			continue
		var lp: Vector3 = leaf_positions[i]
		var dx := lp.x - p.x
		var dz := lp.z - p.z
		if dx * dx + dz * dz < r2:
			leaf_alive[i] = 0
			leaves_left -= 1
			leaf_mm.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -2, 0)))
			cleaned_since_payout += 6


func _collect_trash(body: RigidBody3D) -> void:
	trash_bodies.erase(body)
	var value: int = body.get_meta("value", 3)
	bag += 1
	bag_value += value
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	var mesh_node: Node3D = body.get_node("Mesh")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(body, "global_position", player.global_position + Vector3(0, 1.3, 0.3), 0.22)
	tw.tween_property(mesh_node, "scale", Vector3.ZERO, 0.22)
	tw.chain().tween_callback(body.queue_free)
	combo += 1
	combo_timer = 1.0
	_play_blip(blip_stream, 1.0 + minf(combo, 12) * 0.06 + randf() * 0.05, -6.0)
	_float_text(body.global_position + Vector3(0, 1.0, 0), "+%d" % value, Color(1.0, 0.85, 0.3))


func _sell() -> void:
	var earned := bag_value
	money += earned
	_float_text(container_pos + Vector3(0, 3.2, 0), "+%d SATILDI" % earned, Color(0.5, 1.0, 0.6))
	for i in mini(bag, 6):
		get_tree().create_timer(0.06 * i).timeout.connect(_play_blip.bind(coin_stream, 1.0 + i * 0.08, -6.0))
	bag = 0
	bag_value = 0


func _update_progress() -> void:
	clean_pct = 100.0 * float(clean_pixel_count) / float(maxi(1, dirty_pixel_total))
	var t := clampf(clean_pct / 100.0, 0.0, 1.0)
	env.adjustment_saturation = lerpf(0.55, 1.15, t)
	sun.light_energy = lerpf(0.85, 1.15, t)

	if clean_pct >= float(next_milestone) and next_milestone < 100:
		_float_text(player.global_position + Vector3(0, 2.6, 0), "%%%d temiz!" % next_milestone, Color(0.6, 1.0, 0.8))
		_play_blip(coin_stream, 0.8, -4.0)
		next_milestone += 25

	# %85'ten sonra kalan lekeler hafifçe parlar
	ground_material.set_shader_parameter("hint", 1.0 if clean_pct >= 85.0 and not completed else 0.0)

	if not completed and clean_pct >= COMPLETE_PCT and trash_bodies.is_empty():
		completed = true
		money += COMPLETE_BONUS
		banner_label.text = "ALAN TERTEMİZ!  +%d" % COMPLETE_BONUS
		banner_label.visible = true
		spray.emitting = false
		for i in 8:
			get_tree().create_timer(0.08 * i).timeout.connect(_play_blip.bind(coin_stream, 0.8 + i * 0.1, -4.0))


# =====================================================================
# YÜKSELTMELER
# =====================================================================

func brush_radius() -> float:
	return 0.9 + 0.35 * (brush_level - 1)

func brush_strength() -> float:
	return 350.0 + 150.0 * (brush_level - 1)

func bag_capacity() -> int:
	return 6 + 6 * (bag_level - 1)

func pickup_radius() -> float:
	return 1.3 + 0.4 * vacuum_level

func vacuum_radius() -> float:
	return 2.5 + 1.5 * vacuum_level


func _buy_brush() -> void:
	if brush_level - 1 >= BRUSH_PRICES.size():
		return
	var price: int = BRUSH_PRICES[brush_level - 1]
	if _try_pay(price):
		brush_level += 1
		_float_text(player.global_position + Vector3(0, 2.6, 0), "Fırça Sv %d" % brush_level, Color(0.6, 0.9, 1.0))


func _buy_bag() -> void:
	if bag_level - 1 >= BAG_PRICES.size():
		return
	var price: int = BAG_PRICES[bag_level - 1]
	if _try_pay(price):
		bag_level += 1
		_float_text(player.global_position + Vector3(0, 2.6, 0), "Çanta %d" % bag_capacity(), Color(0.6, 0.9, 1.0))


func _buy_vacuum() -> void:
	if vacuum_level >= VACUUM_PRICES.size():
		return
	var price: int = VACUUM_PRICES[vacuum_level]
	if _try_pay(price):
		vacuum_level += 1
		_float_text(player.global_position + Vector3(0, 2.6, 0), "Vakum Sv %d" % vacuum_level, Color(0.6, 0.9, 1.0))


func _try_pay(price: int) -> bool:
	if money < price:
		_float_text(player.global_position + Vector3(0, 2.6, 0), "Para yetmiyor", Color(1.0, 0.5, 0.5))
		_play_blip(blip_stream, 0.5, -8.0)
		return false
	money -= price
	shown_money = float(money)
	for i in 3:
		get_tree().create_timer(0.07 * i).timeout.connect(_play_blip.bind(coin_stream, 1.2 + i * 0.15, -6.0))
	return true


func _price_text(prices: Array, level_index: int) -> String:
	if level_index >= prices.size():
		return "MAKS"
	return str(prices[level_index])


func _update_hud() -> void:
	money_label.text = "Para: %d" % int(round(shown_money))
	var cap := bag_capacity()
	var bag_text := "Çanta: %d / %d   (değeri %d)" % [bag, cap, bag_value]
	if bag >= cap:
		bag_text += "   ·  DOLU! Konteynere götür"
	bag_label.text = bag_text
	progress_bar.value = clean_pct
	pct_label.text = "Zemin %%%d temiz   ·   Kalan çöp: %d   ·   Kalan yaprak: %d" % [int(clean_pct), trash_bodies.size(), leaves_left]
	shop_label.text = "YÜKSELTMELER\n[1] Fırça  Sv %d  →  %s\n[2] Çanta  %d  →  %s\n[3] Vakum  Sv %d  →  %s" % [
		brush_level, _price_text(BRUSH_PRICES, brush_level - 1),
		cap, _price_text(BAG_PRICES, bag_level - 1),
		vacuum_level, _price_text(VACUUM_PRICES, vacuum_level),
	]


# =====================================================================
# YARDIMCILAR
# =====================================================================

func _mouse_ground_point() -> Variant:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var plane := Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(from, dir)


func _float_text(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 14
	l.pixel_size = 0.008
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", pos + Vector3(0, 1.2, 0), 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func _play_blip(stream: AudioStreamWAV, pitch: float, volume: float) -> void:
	var ap: AudioStreamPlayer = blip_players[blip_index]
	blip_index = (blip_index + 1) % blip_players.size()
	ap.stream = stream
	ap.pitch_scale = maxf(0.1, pitch)
	ap.volume_db = volume
	ap.play()


func _make_blip(freq: float, dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env_amt := 1.0 - float(i) / n
		var s := sin(TAU * freq * t) * env_amt * env_amt * 0.5
		data.encode_s16(i * 2, int(s * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _make_noise_loop(dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var last := 0.0
	for i in n:
		last = lerpf(last, randf_range(-1.0, 1.0), 0.35)   # yumuşatılmış beyaz gürültü = su sesi
		data.encode_s16(i * 2, int(last * 0.6 * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


func _make_label(parent: Node, pos: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	parent.add_child(l)
	return l


func _mat(c: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _add_static_box(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(color)
	_add_child_mesh(body, bm, Vector3.ZERO)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	return body


func _add_child_mesh(parent: Node3D, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi
