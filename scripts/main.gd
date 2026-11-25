extends Node3D
## Temizlik prototipi — tüm sahne kodla kurulur, dışarıdan model gerekmez.
## Döngü: yıka / yaprak temizle / çöp topla -> konteynerde sat -> 1/2/3 ile yükselt.

const PlayerScript := preload("res://scripts/player.gd")
const DirtShader := preload("res://shaders/dirt.gdshader")
const Models := preload("res://scripts/models.gd")

# Çöp türleri: [dosya, boyut (m), değer, sıklık, renk (dokusu eksik olanlar için, yoksa null)]
const TRASH_TYPES := [
	["Lata", 0.5, 3, 3, Color(0.85, 0.15, 0.12)],
	["CrushedBottle", 0.65, 3, 3, Color(0.25, 0.6, 0.35)],
	["EmptyBottle", 0.75, 4, 2, Color(0.55, 0.8, 0.9)],
	["FlatBottle", 0.7, 3, 2, Color(0.55, 0.32, 0.15)],
	["TwistedBottle", 0.75, 4, 2, Color(0.3, 0.5, 0.9)],
	["DwarfBottle", 0.6, 3, 2, Color(0.2, 0.45, 0.25)],
	["NormalRed", 0.7, 3, 2, Color(0.8, 0.2, 0.2)],
	["Platano", 0.6, 2, 2, Color(0.95, 0.8, 0.25)],
	["RottenApple", 0.48, 2, 2, Color(0.55, 0.3, 0.15)],
	["Sandwich", 0.6, 2, 1, Color(0.85, 0.7, 0.45)],
	["Tissue1", 0.5, 1, 2, null],
	["Tissue2", 0.5, 1, 2, null],
	["StripedBox", 0.95, 5, 2, null],
	["BolsaA", 1.2, 6, 1, null],
	["BolsaN1", 1.2, 6, 1, null],
	["BolsaN2", 1.2, 6, 1, null],
	["BolsaNa", 1.2, 6, 1, null],
	["Bag_Box", 1.5, 10, 1, null],
	["Box_Bottles", 1.4, 9, 1, null],
]

const AREA_SIZE := 40.0          # temizlenecek alanın kenarı (metre)
const MASK_RES := 256            # kir maskesi çözünürlüğü
const CLEAN_THRESHOLD := 40      # bu değerin altındaki piksel "temiz" sayılır (0-255)
const PIXELS_PER_COIN := 25      # kaç temiz piksel = 1 para
const REACH := 5.0               # aletin oyuncudan en uzak erişimi
const TRASH_COUNT := 70
const LEAF_COUNT := 1400
const COMPLETE_PCT := 99.0       # bu orandan sonra kalan kırıntılar otomatik temizlenir
const COMPLETE_BONUS := 250

# --- Yükseltme fiyatları (bir sonraki seviyenin fiyatı) ---
const WASHER_PRICES := [40, 120, 300, 700]    # yıkayıcı seviye 2..5
const BROOM_PRICES := [25, 80, 200]           # süpürge seviye 2..4
const VACUUM_PRICES := [80, 200, 500]         # elektrik süpürgesi seviye 1..3 (1 = kilidi açar)
const BAG_PRICES := [30, 90, 250, 600]        # çanta seviye 2..5
const WALK_PICKUP := 1.3                      # üstünden geçince toplama mesafesi

# --- Aletler ---
const TOOL_BROOM := 0
const TOOL_WASHER := 1
const TOOL_VACUUM := 2

var current_tool := TOOL_WASHER
var washer_level := 1
var broom_level := 1
var vacuum_level := 0
var bag_level := 1
var vacuum_active := false
var vacuum_point := Vector3.ZERO

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
var cam_offset := Vector3(0, 12.5, 8.5)
var env: Environment
var sun: DirectionalLight3D
var aim_ring: MeshInstance3D
var spray: CPUParticles3D
var spray_mat: StandardMaterial3D
var ring_mat: StandardMaterial3D
var container_pos := Vector3(-AREA_SIZE * 0.5 + 3.5, 0, AREA_SIZE * 0.5 - 3.5)
var trash_bodies: Array[RigidBody3D] = []
var tree_positions: Array[Vector3] = []
var trash_pool: Array = []
var flower_nodes: Array[Node3D] = []
var find_positions: Array[Vector3] = []
var found_finds: Array[int] = []
var world_seed := 0
var master_volume := 0.8
var paused := false
var pause_panel: PanelContainer
var fullscreen_button: Button
var autosave_timer := 0.0

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
var tool_streams: Array[AudioStreamWAV] = []
var combo := 0
var combo_timer := 0.0
var tick_cooldown := 0.0

# --- Arayüz ---
var money_label: Label
var bag_label: Label
var pct_label: Label
var count_label: Label
var progress_bar: ProgressBar
var shop_label: Label
var info_label: Label
var banner_label: Label
var shop_panel: PanelContainer
var crosshair: Label
var prompt_label: Label
var near_shop := false
var shop_open := false
var water_stream: MeshInstance3D
var shop_buttons: Array[Button] = []


func _ready() -> void:
	# Dünya sabit bir tohumla kurulur ki kayıttan yüklerken her şey aynı yerde olsun
	var save := _load_save()
	randomize()
	world_seed = int(save.get("seed", randi()))
	seed(world_seed)
	_setup_input()
	_build_environment()
	_build_ground()
	_build_props()
	_build_container()
	_build_player()
	_build_leaves()
	_place_finds()
	randomize()
	_build_tool_visuals()
	_build_audio()
	_build_hud()
	_build_pause_menu()
	if save.is_empty():
		_spawn_all_trash()
	else:
		_apply_save(save)
	_set_volume(master_volume)
	_apply_tool_fx()
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
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/textures/sky_garden.hdr")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = Color(0.75, 0.8, 0.85)
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85   # alan temizlendikçe artar
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	sun.light_angular_distance = 1.5
	sun.shadow_blur = 1.5
	sun.light_energy = 1.1
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
	var tex := "res://assets/textures/"
	ground_material.set_shader_parameter("clean_albedo", load(tex + "square_concrete_pavers_diff.jpg"))
	ground_material.set_shader_parameter("clean_normal", load(tex + "square_concrete_pavers_nor.jpg"))
	ground_material.set_shader_parameter("clean_rough", load(tex + "square_concrete_pavers_rough.png"))
	ground_material.set_shader_parameter("mud_albedo", load(tex + "brown_mud_leaves_01_diff.jpg"))
	ground_material.set_shader_parameter("mud_normal", load(tex + "brown_mud_leaves_01_nor.jpg"))
	ground_material.set_shader_parameter("soil_albedo", load(tex + "dirt_floor_diff.jpg"))
	ground_material.set_shader_parameter("soil_normal", load(tex + "dirt_floor_nor.jpg"))
	ground_material.set_shader_parameter("soil_rough", load(tex + "dirt_floor_rough.png"))

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
	# Görünmez sınır duvarları (çarpışma için); görüntü Kenney çitleriyle
	_add_wall(Vector3(0, 0.6, -half), Vector3(AREA_SIZE, 1.2, 0.3))
	_add_wall(Vector3(0, 0.6, half), Vector3(AREA_SIZE, 1.2, 0.3))
	_add_wall(Vector3(-half, 0.6, 0), Vector3(0.3, 1.2, AREA_SIZE))
	_add_wall(Vector3(half, 0.6, 0), Vector3(0.3, 1.2, AREA_SIZE))
	var seg := 2.0
	var count := int(AREA_SIZE / seg)
	for i in count:
		var along := -half + seg * (i + 0.5)
		_add_model("res://assets/nature/fence_planks.glb", seg, Vector3(along, 0, -half), 0.0)
		_add_model("res://assets/nature/fence_planks.glb", seg, Vector3(along, 0, half), 0.0)
		_add_model("res://assets/nature/fence_planks.glb", seg, Vector3(-half, 0, along), 90.0)
		_add_model("res://assets/nature/fence_planks.glb", seg, Vector3(half, 0, along), 90.0)

	# Arkada banliyö evleri
	var houses := ["building-type-a", "building-type-f", "building-type-c", "building-type-k"]
	for i in houses.size():
		var hx := -18.0 + 13.0 * i
		_add_model("res://assets/suburb/%s.glb" % houses[i], 11.0, Vector3(hx, 0, -half - 9.0), 0.0, true)
		_add_wall(Vector3(hx, 2.5, -half - 9.0), Vector3(9, 5, 8))
	_add_model("res://assets/suburb/driveway-long.glb", 6.0, Vector3(-11.5, 0.01, -half - 3.5), 90.0)

	# Alanın içindeki ağaçlar (sonbahar: yaprakların kaynağı)
	for p in [Vector3(9, 0, -8), Vector3(-11, 0, -4), Vector3(13, 0, 10)]:
		_add_tree(p, "res://assets/nature/tree_oak_fall.glb", 6.0)
	# İçeride birkaç kütük ve çalı
	_add_model("res://assets/nature/stump_old.glb", 1.2, Vector3(-4, 0, 9), randf() * 360.0)
	_add_model("res://assets/nature/log.glb", 2.2, Vector3(15, 0, -15), 30.0)
	_add_model("res://assets/nature/plant_bushLarge.glb", 2.0, Vector3(-17, 0, -17), 0.0)
	_add_model("res://assets/nature/plant_bush.glb", 1.6, Vector3(17.5, 0, 3), 0.0)

	# Dışarıdaki doğa: ağaç halkası, çalılar, kayalar, çimen
	var outer_trees := ["res://assets/nature/tree_oak.glb", "res://assets/nature/tree_default.glb", "res://assets/nature/tree_fat.glb", "res://assets/nature/tree_detailed.glb", "res://assets/suburb/tree-large.glb"]
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 400:
		tries += 1
		var p := Vector3(randf_range(-36, 36), 0, randf_range(-20, 36))
		if absf(p.x) < half + 2.5 and absf(p.z) < half + 2.5:
			continue
		if p.z < -half - 2.0:
			continue
		_add_tree(p, outer_trees[randi() % outer_trees.size()], randf_range(5.0, 7.5))
		placed += 1
	var small := ["res://assets/nature/plant_bush.glb", "res://assets/nature/plant_bushDetailed.glb", "res://assets/nature/rock_smallA.glb", "res://assets/nature/rock_smallC.glb", "res://assets/nature/rock_largeA.glb", "res://assets/nature/grass_large.glb", "res://assets/nature/grass.glb", "res://assets/nature/grass_leafs.glb"]
	for i in 140:
		var p := Vector3(randf_range(-45, 45), 0, randf_range(-45, 45))
		if absf(p.x) < half + 0.8 and absf(p.z) < half + 0.8:
			continue
		var path: String = small[randi() % small.size()]
		var size: float = 1.4 if path.contains("bush") else (1.2 if path.contains("large") else 0.7)
		var deco := _add_model(path, size * randf_range(0.8, 1.3), p, randf() * 360.0)
		Models.set_shadows(deco, false)

	# Alan tertemiz olunca açacak çiçekler (başta gizli)
	var flowers := ["res://assets/nature/flower_redA.glb", "res://assets/nature/flower_yellowA.glb", "res://assets/nature/flower_purpleA.glb"]
	for i in 45:
		var p := Vector3(randf_range(-half + 1.5, half - 1.5), 0, randf_range(-half + 1.5, half - 1.5))
		var f := _add_model(flowers[randi() % flowers.size()], randf_range(0.6, 0.9), p, randf() * 360.0)
		f.set_meta("full_scale", f.scale)
		f.scale = Vector3.ZERO
		f.visible = false
		flower_nodes.append(f)


func _add_tree(pos: Vector3, path: String, height: float) -> void:
	if absf(pos.x) < AREA_SIZE * 0.5 and absf(pos.z) < AREA_SIZE * 0.5:
		tree_positions.append(pos)
	var body := StaticBody3D.new()
	body.position = pos
	var model := Models.make(path, height, true)
	model.rotation_degrees.y = randf() * 360.0
	body.add_child(model)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 2.0
	cs.shape = shape
	cs.position.y = 1.0
	body.add_child(cs)
	add_child(body)


func _add_model(path: String, size: float, pos: Vector3, yaw_deg: float, by_height: bool = false) -> Node3D:
	var model := Models.make(path, size, by_height)
	model.position = pos
	model.rotation_degrees.y = yaw_deg
	add_child(model)
	return model


func _add_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)


func _build_container() -> void:
	# Satış noktası: büyük çöp konteyneri
	var dumpster := _add_model("res://assets/trash/Dumpster.fbx", 3.0, container_pos, 0.0)
	var dims: Vector3 = dumpster.get_meta("dims")
	_add_wall(container_pos + Vector3(0, dims.y * 0.5, 0), dims)
	# Yanında renkli geri dönüşüm kovaları (dekor)
	var bins := ["PlasticGreen", "PlasticBlue", "PlasticGray"]
	for i in bins.size():
		var bp := container_pos + Vector3(-0.6 + 1.0 * i, 0, -2.4)
		var b := _add_model("res://assets/trash/%s.fbx" % bins[i], 1.1, bp, 0.0, true)
		var bd: Vector3 = b.get_meta("dims")
		_add_wall(bp + Vector3(0, bd.y * 0.5, 0), bd)
	var lbl := Label3D.new()
	lbl.text = "SAT"
	lbl.font_size = 96
	lbl.outline_size = 16
	lbl.pixel_size = 0.01
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.6, 1.0, 0.7)
	lbl.position = container_pos + Vector3(0, dims.y + 1.0, 0)
	add_child(lbl)


func _build_player() -> void:
	player = PlayerScript.new()
	player.position = Vector3(0, 0.1, AREA_SIZE * 0.5 - 5)
	add_child(player)

	player.rotation.y = 0.0
	camera = player.camera
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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


func _spawn_trash(pos: Vector3, type_index: int = -1, restore_rot = null) -> void:
	if trash_pool.is_empty():
		for ti in TRASH_TYPES.size():
			for k in int(TRASH_TYPES[ti][3]):
				trash_pool.append(ti)
	if type_index < 0:
		type_index = trash_pool[randi() % trash_pool.size()]
	var t: Array = TRASH_TYPES[type_index]
	var size: float = t[1]
	var body := RigidBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1 | 2
	body.mass = 0.5
	var model := Models.make("res://assets/trash/%s.fbx" % t[0], size)
	model.name = "Mesh"
	var dims: Vector3 = model.get_meta("dims")
	model.position.y = -dims.y * 0.5
	if t[4] != null:
		Models.tint(model, t[4])
	Models.set_shadows(model, size >= 0.9)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(dims.x, 0.12), maxf(dims.y, 0.08), maxf(dims.z, 0.12))
	cs.shape = bs
	body.add_child(model)
	body.add_child(cs)
	body.set_meta("value", int(t[2]))
	body.set_meta("type_index", type_index)
	if restore_rot != null:
		body.position = pos
		body.rotation = restore_rot
		add_child(body)
		trash_bodies.append(body)
		return
	body.position = pos + Vector3(0, dims.y * 0.5 + 0.3, 0)
	if size < 0.9:
		body.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	else:
		body.rotation = Vector3(0, randf() * TAU, 0)
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
	# Hedef halkası (rengi alete göre değişir)
	aim_ring = MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 1.0
	disk.bottom_radius = 1.0
	disk.height = 0.02
	disk.radial_segments = 24
	ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.6, 0.9, 1.0, 0.25)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disk.material = ring_mat
	aim_ring.mesh = disk
	add_child(aim_ring)

	# Alet parçacıkları (su, toz ya da emilen kırıntı)
	spray = CPUParticles3D.new()
	spray.emitting = false
	spray.amount = 60
	spray.lifetime = 0.45
	var drop := SphereMesh.new()
	drop.radius = 0.05
	drop.height = 0.1
	drop.radial_segments = 4
	drop.rings = 2
	spray_mat = StandardMaterial3D.new()
	spray_mat.albedo_color = Color(0.7, 0.9, 1.0)
	spray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = spray_mat
	spray.mesh = drop
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
	# Her aletin kendi döngü sesi: süpürge hışırtısı, su, motor uğultusu
	tool_streams.append(_make_noise_loop(1.0, 0.08, 0.0))
	tool_streams.append(_make_noise_loop(1.0, 0.35, 0.0))
	tool_streams.append(_make_noise_loop(1.0, 0.15, 110.0))
	spray_player = AudioStreamPlayer.new()
	add_child(spray_player)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	money_label = _make_label(layer, Vector2(24, 14), 36, Color(1.0, 0.86, 0.3))
	bag_label = _make_label(layer, Vector2(24, 62), 24, Color.WHITE)

	progress_bar = ProgressBar.new()
	progress_bar.position = Vector2(400, 22)
	progress_bar.size = Vector2(440, 26)
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
	pct_label = _make_label(layer, Vector2(400, 50), 20, Color.WHITE)
	pct_label.size = Vector2(440, 30)
	pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label = _make_label(layer, Vector2(400, 76), 17, Color(1, 1, 1, 0.85))
	count_label.size = Vector2(440, 26)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	shop_label = _make_label(layer, Vector2(990, 14), 20, Color.WHITE)
	info_label = _make_label(layer, Vector2(24, 676), 18, Color(1, 1, 1, 0.85))
	info_label.text = "WASD: yürü   ·   Fare: bak   ·   Shift: koş   ·   Sol tık basılı: aleti kullan   ·   1 / 2 / 3 veya tekerlek: alet değiştir   ·   Konteyner: sat, E: dükkân   ·   ESC: menü"

	# Dükkân paneli: konteynerin yanına gelince açılır
	shop_panel = PanelContainer.new()
	shop_panel.position = Vector2(440, 200)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.11, 0.09, 0.9)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	shop_panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	shop_panel.add_child(vb)
	var title := Label.new()
	title.text = "DÜKKÂN"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.75))
	vb.add_child(title)
	for i in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(380, 44)
		b.add_theme_font_size_override("font_size", 18)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_shop_button.bind(i))
		vb.add_child(b)
		shop_buttons.append(b)
	shop_panel.visible = false
	layer.add_child(shop_panel)

	crosshair = _make_label(layer, Vector2(630, 342), 26, Color(1, 1, 1, 0.9))
	crosshair.text = "+"
	crosshair.size = Vector2(20, 36)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label = _make_label(layer, Vector2(0, 430), 26, Color(0.7, 1.0, 0.8))
	prompt_label.size = Vector2(1280, 40)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.text = "E: Dükkânı aç"
	prompt_label.visible = false

	banner_label = _make_label(layer, Vector2(0, 250), 64, Color(0.6, 1.0, 0.75))
	banner_label.size = Vector2(1280, 100)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.visible = false


# =====================================================================
# OYUN DÖNGÜSÜ
# =====================================================================

func _process(delta: float) -> void:
	if paused:
		return
	autosave_timer += delta
	if autosave_timer > 20.0:
		autosave_timer = 0.0
		_save_game()
	# Nişan: ekranın ortasındaki nişangâhın baktığı yer (erişim mesafesi içindeyse)
	var aim := Vector3.ZERO
	var aim_valid := false
	var hit: Variant = _aim_ground_point()
	if hit != null:
		var h: Vector3 = hit
		var lim := AREA_SIZE * 0.5 - 0.2
		if Vector3(h.x - player.global_position.x, 0, h.z - player.global_position.z).length() <= REACH and absf(h.x) < lim and absf(h.z) < lim:
			aim = Vector3(h.x, 0.0, h.z)
			aim_valid = true

	var r := tool_radius()
	aim_ring.visible = aim_valid
	aim_ring.global_position = aim + Vector3(0, 0.03, 0)
	aim_ring.scale = Vector3(r, 1, r)

	# Konteyner: satış + dükkân (E)
	var to_container := Vector2(player.global_position.x - container_pos.x, player.global_position.z - container_pos.z).length()
	if bag > 0 and to_container < 3.2:
		_sell()
	near_shop = to_container < 4.5
	if shop_open and not near_shop:
		_set_shop_open(false)
	shop_panel.visible = shop_open
	prompt_label.visible = near_shop and not shop_open
	crosshair.visible = not shop_open

	var using := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not completed and not shop_open and aim_valid and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	vacuum_active = false
	if using:
		match current_tool:
			TOOL_BROOM:
				_clean_leaves(aim, r)
			TOOL_WASHER:
				_clean_at(aim, delta)
			TOOL_VACUUM:
				vacuum_active = true
				vacuum_point = aim
	spray.global_position = aim + Vector3(0, 0.1, 0)
	spray.emission_sphere_radius = r * (0.9 if current_tool == TOOL_VACUUM else 0.6)
	spray.emitting = using
	_update_water_stream(using and current_tool == TOOL_WASHER, aim)
	if using:
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

	_update_progress()
	shown_money = move_toward(shown_money, float(money), maxf(1.0, absf(money - shown_money)) * delta * 6.0)
	_update_hud()


func _physics_process(_delta: float) -> void:
	if paused:
		return
	var ppos := player.global_position
	var full := bag >= bag_capacity()
	var pull_radius := tool_radius()
	var swallow_radius := 0.6 + 0.15 * vacuum_level
	for body: RigidBody3D in trash_bodies.duplicate():
		if not is_instance_valid(body):
			trash_bodies.erase(body)
			continue
		if full:
			continue
		# Üstünden yürüyerek toplama
		var to_player: Vector3 = ppos - body.global_position
		to_player.y = 0.0
		if to_player.length() < WALK_PICKUP:
			_collect_trash(body)
			full = bag >= bag_capacity()
			continue
		# Elektrik süpürgesi: nozüle çek, yakına gelince yut
		if vacuum_active:
			var to_nozzle: Vector3 = vacuum_point - body.global_position
			to_nozzle.y = 0.0
			var nd: float = to_nozzle.length()
			if nd < swallow_radius:
				_collect_trash(body)
				full = bag >= bag_capacity()
			elif nd < pull_radius:
				body.sleeping = false
				var pull: float = (14.0 + 10.0 * vacuum_level) * (1.0 - nd / pull_radius + 0.3)
				body.apply_central_force((to_nozzle.normalized() * pull + Vector3.UP * 3.0) * body.mass)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if shop_open:
			_set_shop_open(false)
		else:
			_toggle_pause()
		return
	if paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		if shop_open:
			_set_shop_open(false)
		elif near_shop:
			_set_shop_open(true)
		return
	# Fare bırakıldıysa tıklayınca yeniden yakala
	if event is InputEventMouseButton and event.pressed and not shop_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				_select_tool(TOOL_BROOM)
			KEY_2:
				_select_tool(TOOL_WASHER)
			KEY_3:
				_select_tool(TOOL_VACUUM)
	elif event is InputEventMouseButton and event.pressed:
		var step := 0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = 1
		if step != 0:
			var count: int = 3 if vacuum_level > 0 else 2
			_select_tool(posmod(current_tool + step, count))


func _select_tool(t: int) -> void:
	if t == TOOL_VACUUM and vacuum_level == 0:
		_float_text(player.global_position + Vector3(0, 2.6, 0), "Elektrik süpürgesi kilitli, dükkândan al", Color(1.0, 0.6, 0.5))
		_play_blip(blip_stream, 0.5, -8.0)
		return
	if t == current_tool:
		return
	current_tool = t
	spray_player.stop()
	_apply_tool_fx()
	_play_blip(blip_stream, 0.8, -10.0)


func _apply_tool_fx() -> void:
	match current_tool:
		TOOL_BROOM:
			ring_mat.albedo_color = Color(1.0, 0.8, 0.4, 0.25)
			spray_mat.albedo_color = Color(0.72, 0.5, 0.26)
			spray.direction = Vector3.UP
			spray.spread = 80.0
			spray.initial_velocity_min = 1.0
			spray.initial_velocity_max = 2.5
			spray.gravity = Vector3(0, -9.8, 0)
			spray.radial_accel_min = 4.0
			spray.radial_accel_max = 8.0
			spray_player.volume_db = -15.0
		TOOL_WASHER:
			ring_mat.albedo_color = Color(0.6, 0.9, 1.0, 0.25)
			spray_mat.albedo_color = Color(0.7, 0.9, 1.0)
			spray.direction = Vector3.UP
			spray.spread = 55.0
			spray.initial_velocity_min = 2.0
			spray.initial_velocity_max = 4.5
			spray.gravity = Vector3(0, -9.8, 0)
			spray.radial_accel_min = 0.0
			spray.radial_accel_max = 0.0
			spray_player.volume_db = -18.0
		TOOL_VACUUM:
			ring_mat.albedo_color = Color(0.85, 0.6, 1.0, 0.25)
			spray_mat.albedo_color = Color(0.92, 0.9, 0.96)
			spray.direction = Vector3.UP
			spray.spread = 180.0
			spray.initial_velocity_min = 0.0
			spray.initial_velocity_max = 0.3
			spray.gravity = Vector3.ZERO
			spray.radial_accel_min = -16.0
			spray.radial_accel_max = -10.0
			spray_player.volume_db = -16.0
	spray_player.stream = tool_streams[current_tool]
	player.set_tool(current_tool)


# =====================================================================
# TEMİZLİK
# =====================================================================

func _clean_at(world_pos: Vector3, delta: float) -> void:
	var u := (world_pos.x + AREA_SIZE * 0.5) / AREA_SIZE
	var v := (world_pos.z + AREA_SIZE * 0.5) / AREA_SIZE
	var cx := int(u * MASK_RES)
	var cy := int(v * MASK_RES)
	var r_px := maxi(1, int(ceil(washer_radius() / AREA_SIZE * MASK_RES)))
	var amount := washer_strength() * delta
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
		_check_finds()


func _clean_leaves(p: Vector3, radius: float) -> void:
	var r2 := radius * radius
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
	env.adjustment_saturation = lerpf(0.85, 1.08, t)
	sun.light_energy = lerpf(1.0, 1.2, t)

	if clean_pct >= float(next_milestone) and next_milestone < 100:
		_float_text(player.global_position + Vector3(0, 2.6, 0), "%%%d temiz!" % next_milestone, Color(0.6, 1.0, 0.8))
		_play_blip(coin_stream, 0.8, -4.0)
		next_milestone += 25

	# %90'dan sonra kalan lekeler belirgin şekilde parlar
	ground_material.set_shader_parameter("hint", 1.0 if clean_pct >= 90.0 and not completed else 0.0)

	if not completed and clean_pct >= COMPLETE_PCT and trash_bodies.is_empty():
		completed = true
		_sweep_leftovers()
		_bloom_flowers()
		player.cheer()
		money += COMPLETE_BONUS
		banner_label.text = "ALAN TERTEMİZ!  +%d" % COMPLETE_BONUS
		banner_label.visible = true
		spray.emitting = false
		for i in 8:
			get_tree().create_timer(0.08 * i).timeout.connect(_play_blip.bind(coin_stream, 0.8 + i * 0.1, -4.0))


func _sweep_leftovers() -> void:
	# Son kırıntılar: kalan kir 5 adımda parlayarak silinir, kalan yapraklar kaybolur
	for i in LEAF_COUNT:
		if leaf_alive[i] == 1:
			leaf_alive[i] = 0
			leaf_mm.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -2, 0)))
	leaves_left = 0
	for step in 5:
		get_tree().create_timer(0.15 * (step + 1)).timeout.connect(_fade_mask_step.bind(step == 4))


func _bloom_flowers() -> void:
	# Temizlenen alanda çiçekler tek tek açar
	for i in flower_nodes.size():
		var f: Node3D = flower_nodes[i]
		var full: Vector3 = f.get_meta("full_scale")
		var tw := create_tween()
		tw.tween_interval(0.6 + 0.04 * i)
		tw.tween_callback(f.show)
		tw.tween_property(f, "scale", full, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _fade_mask_step(final: bool) -> void:
	for i in mask_data.size():
		var v: int = mask_data[i]
		if v > 0:
			mask_data[i] = 0 if final else v / 2
	mask_image.set_data(MASK_RES, MASK_RES, false, Image.FORMAT_L8, mask_data)
	mask_texture.update(mask_image)
	if final:
		clean_pixel_count = dirty_pixel_total


# =====================================================================
# ALETLER VE YÜKSELTMELER
# =====================================================================

func tool_radius() -> float:
	match current_tool:
		TOOL_BROOM:
			return 1.6 + 0.5 * (broom_level - 1)
		TOOL_VACUUM:
			return 1.8 + 0.6 * vacuum_level
	return washer_radius()

func washer_radius() -> float:
	return 0.9 + 0.35 * (washer_level - 1)

func washer_strength() -> float:
	return 350.0 + 150.0 * (washer_level - 1)

func bag_capacity() -> int:
	return 6 + 6 * (bag_level - 1)


func _on_shop_button(i: int) -> void:
	match i:
		0:
			if washer_level - 1 < WASHER_PRICES.size() and _try_pay(WASHER_PRICES[washer_level - 1]):
				washer_level += 1
				_upgrade_text("Yıkayıcı Sv %d" % washer_level)
		1:
			if broom_level - 1 < BROOM_PRICES.size() and _try_pay(BROOM_PRICES[broom_level - 1]):
				broom_level += 1
				_upgrade_text("Süpürge Sv %d" % broom_level)
		2:
			if vacuum_level < VACUUM_PRICES.size() and _try_pay(VACUUM_PRICES[vacuum_level]):
				vacuum_level += 1
				if vacuum_level == 1:
					_upgrade_text("Elektrik süpürgesi açıldı! [3]")
					_select_tool(TOOL_VACUUM)
				else:
					_upgrade_text("Elektrik süpürgesi Sv %d" % vacuum_level)
		3:
			if bag_level - 1 < BAG_PRICES.size() and _try_pay(BAG_PRICES[bag_level - 1]):
				bag_level += 1
				_upgrade_text("Çanta %d" % bag_capacity())


func _upgrade_text(text: String) -> void:
	_float_text(player.global_position + Vector3(0, 2.6, 0), text, Color(0.6, 0.9, 1.0))


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


func _set_shop_button(i: int, label: String, prices: Array, level_index: int, verb: String) -> void:
	var b: Button = shop_buttons[i]
	if level_index >= prices.size():
		b.text = "%s   ·   MAKS" % label
		b.disabled = true
		return
	var price: int = prices[level_index]
	b.text = "%s   ·   %s: %d" % [label, verb, price]
	b.disabled = money < price


func _update_hud() -> void:
	money_label.text = "Para: %d" % int(round(shown_money))
	var cap := bag_capacity()
	var bag_text := "Çanta: %d / %d   (değeri %d)" % [bag, cap, bag_value]
	if bag >= cap:
		bag_text += "   ·  DOLU! Konteynere götür"
	bag_label.text = bag_text
	progress_bar.value = clean_pct
	pct_label.text = "Zemin %%%d temiz" % int(clean_pct)
	count_label.text = "Kalan çöp: %d   ·   Kalan yaprak: %d   ·   Buluntu: %d / %d" % [trash_bodies.size(), leaves_left, found_finds.size(), FINDS.size()]

	var vac_text: String = ("Sv %d" % vacuum_level) if vacuum_level > 0 else "kilitli"
	shop_label.text = "ALETLER\n%s [1] Süpürge  Sv %d\n%s [2] Yıkayıcı  Sv %d\n%s [3] Elk. süpürgesi  %s" % [
		">" if current_tool == TOOL_BROOM else "  ", broom_level,
		">" if current_tool == TOOL_WASHER else "  ", washer_level,
		">" if current_tool == TOOL_VACUUM else "  ", vac_text,
	]

	if shop_panel.visible:
		_set_shop_button(0, "Yıkayıcı Sv %d" % washer_level, WASHER_PRICES, washer_level - 1, "Yükselt")
		_set_shop_button(1, "Süpürge Sv %d" % broom_level, BROOM_PRICES, broom_level - 1, "Yükselt")
		_set_shop_button(2, "Elektrik süpürgesi " + vac_text, VACUUM_PRICES, vacuum_level, "Satın al" if vacuum_level == 0 else "Yükselt")
		_set_shop_button(3, "Çanta %d" % cap, BAG_PRICES, bag_level - 1, "Yükselt")


# =====================================================================
# YARDIMCILAR
# =====================================================================

func _aim_ground_point() -> Variant:
	var mp := get_viewport().get_visible_rect().size * 0.5
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


func _make_noise_loop(dur: float, smooth: float, hum_freq: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var last := 0.0
	for i in n:
		last = lerpf(last, randf_range(-1.0, 1.0), smooth)   # yumuşatılmış gürültü
		var hum: float = sin(TAU * hum_freq * float(i) / rate) * 0.35 if hum_freq > 0.0 else 0.0
		data.encode_s16(i * 2, int(clampf(last * 0.6 + hum, -1.0, 1.0) * 32767.0))
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


# =====================================================================
# BULUNTULAR (kirin altından çıkan gizli eşyalar)
# =====================================================================

const FINDS := [
	["Eski bozuk para", 15], ["Kayıp yüzük", 60], ["Paslı anahtar", 20], ["Oyuncak araba", 30],
	["Antika cep saati", 80], ["Gümüş kaşık", 35], ["Cam misket", 15], ["Eski fotoğraf", 25],
]

func _place_finds() -> void:
	var half := AREA_SIZE * 0.5 - 3.0
	for i in FINDS.size():
		find_positions.append(Vector3(randf_range(-half, half), 0, randf_range(-half, half)))


func _check_finds() -> void:
	for i in find_positions.size():
		if found_finds.has(i):
			continue
		var p: Vector3 = find_positions[i]
		var px := clampi(int((p.x / AREA_SIZE + 0.5) * MASK_RES), 0, MASK_RES - 1)
		var py := clampi(int((p.z / AREA_SIZE + 0.5) * MASK_RES), 0, MASK_RES - 1)
		var v: int = mask_data[py * MASK_RES + px]
		if v < CLEAN_THRESHOLD:
			_reveal_find(i)


func _reveal_find(i: int) -> void:
	found_finds.append(i)
	var info: Array = FINDS[i]
	var value: int = info[1]
	money += value
	var p: Vector3 = find_positions[i]
	_float_text(p + Vector3(0, 1.4, 0), "Buldun: %s!  +%d" % [info[0], value], Color(1.0, 0.85, 0.3))
	for k in 5:
		get_tree().create_timer(0.07 * k).timeout.connect(_play_blip.bind(coin_stream, 1.0 + k * 0.12, -4.0))
	# Altın parıltı patlaması
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.amount = 40
	burst.lifetime = 1.0
	var spark := SphereMesh.new()
	spark.radius = 0.05
	spark.height = 0.1
	spark.radial_segments = 4
	spark.rings = 2
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1.0, 0.85, 0.3)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.75, 0.2)
	sm.emission_energy_multiplier = 3.0
	spark.material = sm
	burst.mesh = spark
	burst.direction = Vector3.UP
	burst.spread = 60.0
	burst.initial_velocity_min = 3.0
	burst.initial_velocity_max = 6.0
	burst.position = p + Vector3(0, 0.2, 0)
	add_child(burst)
	burst.emitting = true
	get_tree().create_timer(2.0).timeout.connect(burst.queue_free)


# =====================================================================
# KAYIT
# =====================================================================

const SAVE_PATH := "user://kayit.json"

func _load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _save_game() -> void:
	var trash := []
	for b: RigidBody3D in trash_bodies:
		if is_instance_valid(b):
			var bp := b.global_position
			var br := b.rotation
			trash.append([int(b.get_meta("type_index", 0)), bp.x, bp.y, bp.z, br.x, br.y, br.z])
	var data := {
		"version": 1,
		"seed": world_seed,
		"money": money,
		"washer": washer_level, "broom": broom_level, "vacuum": vacuum_level, "bag_level": bag_level,
		"bag": bag, "bag_value": bag_value, "tool": current_tool,
		"completed": completed, "milestone": next_milestone,
		"clean_pixels": clean_pixel_count,
		"mask": Marshalls.raw_to_base64(mask_data.compress(FileAccess.COMPRESSION_DEFLATE)),
		"leaves": Marshalls.raw_to_base64(leaf_alive),
		"trash": trash,
		"finds": found_finds,
		"player": [player.global_position.x, player.global_position.z],
		"yaw": player.rotation.y,
		"volume": master_volume,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


func _apply_save(d: Dictionary) -> void:
	money = int(d.get("money", 0))
	shown_money = float(money)
	washer_level = int(d.get("washer", 1))
	broom_level = int(d.get("broom", 1))
	vacuum_level = int(d.get("vacuum", 0))
	bag_level = int(d.get("bag_level", 1))
	bag = int(d.get("bag", 0))
	bag_value = int(d.get("bag_value", 0))
	current_tool = int(d.get("tool", TOOL_WASHER))
	completed = bool(d.get("completed", false))
	next_milestone = int(d.get("milestone", 25))
	clean_pixel_count = int(d.get("clean_pixels", 0))
	master_volume = float(d.get("volume", 0.8))

	var packed: PackedByteArray = Marshalls.base64_to_raw(str(d.get("mask", "")))
	if packed.size() > 0:
		var raw := packed.decompress(MASK_RES * MASK_RES, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == MASK_RES * MASK_RES:
			mask_data = raw
			mask_image.set_data(MASK_RES, MASK_RES, false, Image.FORMAT_L8, mask_data)
			mask_texture.update(mask_image)

	var leaves: PackedByteArray = Marshalls.base64_to_raw(str(d.get("leaves", "")))
	if leaves.size() == LEAF_COUNT:
		leaves_left = 0
		for i in LEAF_COUNT:
			leaf_alive[i] = leaves[i]
			if leaves[i] == 0:
				leaf_mm.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -2, 0)))
			else:
				leaves_left += 1

	for item in d.get("trash", []):
		var a: Array = item
		_spawn_trash(Vector3(a[1], a[2], a[3]), int(a[0]), Vector3(a[4], a[5], a[6]))

	for i in d.get("finds", []):
		found_finds.append(int(i))

	var pp: Array = d.get("player", [])
	if pp.size() == 2:
		player.position = Vector3(pp[0], 0.1, pp[1])
		player.rotation.y = float(d.get("yaw", 0.0))

	if completed:
		for f: Node3D in flower_nodes:
			f.scale = f.get_meta("full_scale")
			f.visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and player != null:
		_save_game()


# =====================================================================
# DURAKLATMA MENÜSÜ
# =====================================================================

func _build_pause_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	pause_panel = PanelContainer.new()
	pause_panel.position = Vector2(440, 170)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.08, 0.94)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(22)
	pause_panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pause_panel.add_child(vb)
	var title := Label.new()
	title.text = "JUNK TO SHINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.75))
	vb.add_child(title)
	_menu_button(vb, "Devam et", _toggle_pause)
	fullscreen_button = _menu_button(vb, "", _toggle_fullscreen)
	var vol_row := HBoxContainer.new()
	var vol_label := Label.new()
	vol_label.text = "Ses"
	vol_label.custom_minimum_size = Vector2(60, 0)
	vol_label.add_theme_font_size_override("font_size", 20)
	vol_row.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = master_volume
	slider.custom_minimum_size = Vector2(300, 32)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_set_volume)
	vol_row.add_child(slider)
	vb.add_child(vol_row)
	_menu_button(vb, "Yeni oyun (kaydı sil)", _new_game)
	_menu_button(vb, "Kaydet ve çık", _save_and_quit)
	pause_panel.visible = false
	layer.add_child(pause_panel)
	_update_fullscreen_text()


func _menu_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _toggle_pause() -> void:
	paused = not paused
	pause_panel.visible = paused
	player.set_physics_process(not paused)
	player.look_enabled = not paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	_update_water_stream(false, Vector3.ZERO)
	spray.emitting = false
	if spray_player.playing:
		spray_player.stop()
	if paused:
		_save_game()


func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_fullscreen_text()


func _update_fullscreen_text() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_button.text = "Pencere moduna geç" if fs else "Tam ekrana geç"


func _set_volume(v: float) -> void:
	master_volume = v
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))


func _new_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	get_tree().reload_current_scene()


func _save_and_quit() -> void:
	_save_game()
	get_tree().quit()


# =====================================================================
# BİRİNCİ ŞAHIS YARDIMCILARI
# =====================================================================

func _set_shop_open(open: bool) -> void:
	shop_open = open
	shop_panel.visible = open
	player.look_enabled = not open
	player.set_physics_process(not open)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_update_water_stream(false, Vector3.ZERO)


## Yıkama tabancasından nişan noktasına uzanan su hüzmesi
func _update_water_stream(active: bool, target: Vector3) -> void:
	if water_stream == null:
		water_stream = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.035
		cyl.height = 1.0
		cyl.radial_segments = 8
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.8, 0.92, 1.0, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cyl.material = m
		water_stream.mesh = cyl
		water_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water_stream)
	water_stream.visible = active
	if not active:
		return
	var from := player.nozzle_position()
	var to := target + Vector3(0, 0.05, 0)
	var dir := to - from
	var length := dir.length()
	if length < 0.05:
		water_stream.visible = false
		return
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
	var b := Basis.looking_at(dir.normalized(), up) * Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(1, length, 1))
	water_stream.global_transform = Transform3D(b, (from + to) * 0.5)
