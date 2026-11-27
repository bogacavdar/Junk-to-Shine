extends Node3D
## Temizlik prototipi — tüm sahne kodla kurulur, dışarıdan model gerekmez.
## Döngü: yıka / yaprak temizle / çöp topla -> konteynerde sat -> 1/2/3 ile yükselt.

const PlayerScript := preload("res://scripts/player.gd")
const IslandScript := preload("res://scripts/island.gd")
const HudScript := preload("res://scripts/hud.gd")
const GrassScript := preload("res://scripts/grass.gd")
const Kayit := preload("res://scripts/kayit.gd")
const PropsScript := preload("res://scripts/props.gd")
const Models := preload("res://scripts/models.gd")
const Gorev := preload("res://scripts/gorevler.gd")

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

const MASK_RES := 256            # kir maskesi çözünürlüğü
const CLEAN_THRESHOLD := 40      # bu değerin altındaki piksel "temiz" sayılır (0-255)
const REACH := 5.0               # aletin oyuncudan en uzak erişimi
const TRASH_COUNT := 70
const COMPLETE_PCT := 99.0       # bu orandan sonra kalan kırıntılar otomatik temizlenir
const COMPLETE_BONUS := 250

# --- Yükseltme fiyatları (bir sonraki seviyenin fiyatı) ---
# Artımlı yükseltmeler: fiyat = taban × artış^seviye. max = -1 ise sınırsız.
# "güç" türü yükseltmeler: seviye başına +%10, her 10 seviyede ×2.
const UPGRADES := [
	{"id": "pressure", "name": "Yıkayıcı basıncı", "base": 15.0, "growth": 1.15, "max": -1},
	{"id": "nozzle", "name": "Geniş başlık", "base": 40.0, "growth": 1.32, "max": 30},
	{"id": "scythe", "name": "Keskin tırpan", "base": 12.0, "growth": 1.15, "max": -1},
	{"id": "scythe_w", "name": "Uzun tırpan", "base": 35.0, "growth": 1.32, "max": 30},
	{"id": "broom", "name": "Sık dişli tırmık", "base": 15.0, "growth": 1.15, "max": -1},
	{"id": "broom_w", "name": "Geniş tırmık", "base": 40.0, "growth": 1.32, "max": 30},
	{"id": "bag", "name": "Büyük çanta", "base": 25.0, "growth": 1.22, "max": 40},
	{"id": "vacuum", "name": "Elektrik süpürgesi", "base": 120.0, "growth": 1.25, "max": 25},
	{"id": "shoes", "name": "Koşu ayakkabısı", "base": 60.0, "growth": 1.45, "max": 15},
	{"id": "bonus", "name": "Geri dönüşüm primi", "base": 80.0, "growth": 1.2, "max": -1},
	{"id": "magnet", "name": "Mıknatıs", "base": 90.0, "growth": 1.4, "max": 20},
	{"id": "cart", "name": "El arabası", "base": 600.0, "growth": 1.6, "max": 10},
	{"id": "detector", "name": "Buluntu dedektörü", "base": 250.0, "growth": 1.5, "max": 10},
]
# Kilometre taşları: sınırsız yükseltmeler bu seviyelere ulaşınca gücü ayrıca ×3 olur
const MILESTONES := [25, 50, 100, 200, 400]
const MONEY_PER_PIXEL := 0.04    # temizlenen her piksel (temel)
const WALK_PICKUP := 1.3                      # üstünden geçince toplama mesafesi

# --- Aletler ---
const TOOL_SCYTHE := 0    # uzun kuru ot
const TOOL_RAKE := 1      # yaprak, dal, deniz yosunu
const TOOL_WASHER := 2    # taş yoldaki çamur
const TOOL_VACUUM := 3    # çöp
const TOOL_NAMES := ["Tırpan", "Tırmık", "Yıkayıcı", "Elk. süpürgesi"]

var current_tool := TOOL_SCYTHE
var levels := {}            # yükseltme id -> seviye
var buy_mode := 1          # dükkânda toplu alım: 1, 10 ya da -1 (maks)
var vacuum_level := 0       # levels["vacuum"] kopyası (sık kullanılıyor)
var vacuum_active := false
var vacuum_point := Vector3.ZERO

# --- Ekonomi ---
var money := 0.0
var shown_money := 0.0
var bag := 0
var bag_value := 0.0

# --- Kir maskesi ---
var island = null   # island.gd
var hud = null      # hud.gd
var grass = null    # grass.gd (yakındaki 3D otlar)
var mist: CPUParticles3D   # yıkayıcı sisi
var income_total := 0.0   # toplam kazanç (arayüzdeki kazanç hızı için)
var shot_dir := ""        # test: ekran görüntülerinin kaydedileceği klasör (komut satırından)
var shot_frame := 0
var tool_names: Array = TOOL_NAMES
var upgrades: Array = UPGRADES
var props = null    # props.gd
var spawn_point := Vector3.ZERO
var sky_mat: ShaderMaterial
var ocean_mat: ShaderMaterial
var local_clean := 0.0
var cleaned_since_payout := 0.0   # bölge çarpanıyla ağırlıklı temiz piksel
var zones_done: Array[int] = []      # tamamlanıp ödülü verilen bölgeler
var zones_spawned: Array[int] = []   # çöpü dağıtılmış bölgeler
var zone_timer := 0.0
var last_ok_pos := Vector3.ZERO
var current_zone := 1
var locked_msg_timer := 0.0
const ZONE_TRASH := [0, 70, 110, 110, 130, 130, 130, 110]
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
var container_pos := Vector3.ZERO
var trash_bodies: Array[RigidBody3D] = []
var tree_positions: Array[Vector3] = []
var trash_pool: Array = []
var flower_nodes: Array[Node3D] = []
var find_positions: Array[Vector3] = []
var found_finds: Array[int] = []
var world_seed := 0
var master_volume := 0.8
var paused := false
var autosave_timer := 0.0
# Görevler (scripts/gorevler.gd)
var quest_index := 0
var quest_base := {}
var quest_timer := 2.5         # yeni oyunda ilk telsiz mesajı biraz sonra gelsin
var quest_announced := false
var stat_trash := 0            # toplam toplanan çöp
var stat_sells := 0            # konteynerde satış sayısı
var journal: Array = []        # okunmuş mesajlar: [kimden, metin]

# --- Yapraklar (binlerce, fizik yok) ---

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
var near_shop := false
var shop_open := false
var is_mobile := OS.has_feature("mobile")
var touch = null   # touch_controls.gd (sadece telefonda)
var water_stream: MeshInstance3D


func _ready() -> void:
	# Dünya sabit bir tohumla kurulur ki kayıttan yüklerken her şey aynı yerde olsun
	Kayit.migrate()
	save_path = Kayit.path(Kayit.current_slot())
	var save := _load_save()
	save_name = str(save.get("name", ""))
	if save_name == "":
		save_name = Kayit.pending_name() if Kayit.pending_name() != "" else "Ada %d" % Kayit.current_slot()
	play_time = float(save.get("play_time", 0.0))
	created_at = int(save.get("created", Time.get_unix_time_from_system()))
	randomize()
	world_seed = int(save.get("seed", randi()))
	seed(world_seed)
	_setup_input()
	_build_environment()
	_build_island()
	_build_props()
	_build_ocean()
	_build_container()
	_build_player()
	grass = GrassScript.new()
	add_child(grass)
	grass.setup(island, player)
	_apply_levels()
	_place_finds()
	randomize()
	_build_tool_visuals()
	_build_audio()
	_build_hud()
	if is_mobile:
		touch = load("res://scripts/touch_controls.gd").new()
		add_child(touch)
		touch.player = player
	if save.is_empty():
		_spawn_all_trash()
	else:
		_apply_save(save)
	hud.apply_settings()
	_apply_tool_fx()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ekran="):
			shot_dir = a.substr(8)
			DirAccess.make_dir_recursive_absolute(shot_dir)
			# Ekran kartı olmayan test makinesinde hızlı çizim için en düşük ayar
			hud.settings["quality"] = 0
			hud.settings["draw"] = 80.0
			hud.settings["fog"] = false
			hud.apply_settings()
			sun.shadow_enabled = false


# =====================================================================
# KURULUM
# =====================================================================

func _setup_input() -> void:
	# Klavye + kontrolcü (Xbox / PlayStation düzeni)
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("move_up", [KEY_W, KEY_UP])
	_add_key_action("move_down", [KEY_S, KEY_DOWN])
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_key_action("run", [KEY_SHIFT])
	_add_joy_button("run", JOY_BUTTON_LEFT_STICK)
	_add_key_action("use_tool", [])
	_add_joy_axis("use_tool", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	if not is_mobile:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("use_tool", mb)
	_add_key_action("tool_next", [])
	_add_joy_button("tool_next", JOY_BUTTON_RIGHT_SHOULDER)
	_add_key_action("tool_prev", [])
	_add_joy_button("tool_prev", JOY_BUTTON_LEFT_SHOULDER)
	_add_key_action("interact", [KEY_E])
	_add_joy_button("interact", JOY_BUTTON_A)
	_add_key_action("pause", [KEY_ESCAPE])
	_add_joy_button("pause", JOY_BUTTON_START)
	_add_key_action("back", [])
	_add_joy_button("back", JOY_BUTTON_B)
	for a in ["move_left", "move_right", "move_up", "move_down", "look_left", "look_right", "look_up", "look_down"]:
		InputMap.action_set_deadzone(a, 0.2)


func _add_joy_axis(action: String, axis: JoyAxis, dir: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = dir
	InputMap.action_add_event(action, ev)


func _add_joy_button(action: String, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


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
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky_blend.gdshader")
	var tex := "res://assets/textures/"
	# Ayrı kasvetli / güneşli HDRI'ler varsa onları kullan, yoksa bahçe gökyüzünü soldurarak kasvetli yap
	var sunny_path := tex + "sky_sunny.hdr" if ResourceLoader.exists(tex + "sky_sunny.hdr") else tex + "sky_garden.hdr"
	var gloomy_path := tex + "sky_gloomy.hdr" if ResourceLoader.exists(tex + "sky_gloomy.hdr") else tex + "sky_garden.hdr"
	sky_mat.set_shader_parameter("sky_sunny", load(sunny_path))
	sky_mat.set_shader_parameter("sky_gloomy", load(gloomy_path))
	sky_mat.set_shader_parameter("gloomy_desaturate", 0.0 if gloomy_path != sunny_path else 0.85)
	sky_mat.set_shader_parameter("gloomy_energy", 0.9 if gloomy_path != sunny_path else 0.55)
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
	env.fog_density = 0.012
	env.fog_light_color = Color(0.55, 0.58, 0.62)
	env.fog_aerial_perspective = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.7
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	sun.light_angular_distance = 1.5
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 120.0
	sun.light_energy = 0.6
	sun.light_color = Color(0.85, 0.88, 0.95)
	add_child(sun)


func _build_island() -> void:
	var tex := "res://assets/textures/"
	var t := {}
	# Zemin dokuları: yeni indirilenler varsa onları, yoksa geçici olarak mevcutları kullan
	var has_sand := ResourceLoader.exists(tex + "sand_03_diff.jpg")
	var has_ground := ResourceLoader.exists(tex + "coast_sand_rocks_02_diff.jpg")
	var has_rock := ResourceLoader.exists(tex + "rocks_ground_02_diff.jpg")
	t["sand_albedo"] = load(tex + ("sand_03" if has_sand else "dirt_floor") + "_diff.jpg")
	t["sand_normal"] = load(tex + ("sand_03" if has_sand else "dirt_floor") + "_nor.jpg")
	t["sand_tint"] = Vector3.ONE if has_sand else Vector3(1.55, 1.35, 1.05)
	t["ground_albedo"] = load(tex + ("coast_sand_rocks_02" if has_ground else "dirt_floor") + "_diff.jpg")
	t["ground_normal"] = load(tex + ("coast_sand_rocks_02" if has_ground else "dirt_floor") + "_nor.jpg")
	t["ground_tint"] = Vector3.ONE if has_ground else Vector3(0.85, 0.95, 0.7)
	t["ground_tile"] = 15.0 if has_ground else 4.0
	t["rock_albedo"] = load(tex + ("rocks_ground_02" if has_rock else "square_concrete_pavers") + "_diff.jpg")
	t["rock_normal"] = load(tex + ("rocks_ground_02" if has_rock else "square_concrete_pavers") + "_nor.jpg")
	# Taş yol ve meydan
	t["pave_albedo"] = load(tex + "square_concrete_pavers_diff.jpg")
	t["pave_normal"] = load(tex + "square_concrete_pavers_nor.jpg")
	# Biçilmiş çim (temiz toprak zemin) ve uzun kuru ot: indirilmişse gerçek dokular, yoksa geçici
	if ResourceLoader.exists(tex + "leafy_grass_diff.jpg"):
		t["ground_albedo"] = load(tex + "leafy_grass_diff.jpg")
		t["ground_normal"] = load(tex + "leafy_grass_nor.jpg")
		t["ground_tint"] = Vector3.ONE
		t["ground_tile"] = 2.5
	if ResourceLoader.exists(tex + "withered_grass_diff.jpg"):
		t["dry_albedo"] = load(tex + "withered_grass_diff.jpg")
		t["dry_normal"] = load(tex + "withered_grass_nor.jpg")
		t["dry_tint"] = Vector3.ONE
		t["dry_tile"] = 2.0
	else:
		t["dry_albedo"] = load(tex + "dirt_floor_diff.jpg")
		t["dry_normal"] = load(tex + "dirt_floor_nor.jpg")
		t["dry_tint"] = Vector3(1.35, 1.15, 0.7)
		t["dry_tile"] = 3.0
	t["mud_albedo"] = load(tex + "brown_mud_leaves_01_diff.jpg")
	t["mud_normal"] = load(tex + "brown_mud_leaves_01_nor.jpg")
	t["leaf_albedo"] = load(tex + "leaves_forest_ground_diff.jpg")
	t["leaf_normal"] = load(tex + "leaves_forest_ground_nor.jpg")
	t["leaf_height"] = load(tex + "leaves_forest_ground_disp.png")
	island = IslandScript.new()
	add_child(island)
	island.setup(world_seed, load("res://shaders/terrain.gdshader"), t)

	spawn_point = island.spawn_point
	container_pos = Vector3(7.0, 0.0, spawn_point.z - 2.0)
	container_pos.y = island.height_at(container_pos.x, container_pos.z)


func _build_props() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.23, 0.24)
	metal.metallic = 0.8
	metal.roughness = 0.45
	var m := {
		"wood": _tex_mat("wooden_gate", 1.2, 0.65, false),
		"concrete": _tex_mat("square_concrete_pavers", 2.0),
		"metal": metal,
	}
	props = PropsScript.new()
	add_child(props)
	props.setup(island, m, world_seed)


func _build_ocean() -> void:
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	pm.subdivide_width = 320
	pm.subdivide_depth = 320
	sea.mesh = pm
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = load("res://shaders/ocean.gdshader")
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	nt.noise = fn
	ocean_mat.set_shader_parameter("detail_normal", nt)
	sea.material_override = ocean_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)


## Dünya koordinatına göre döşenen (triplanar) gerçekçi malzeme
func _tex_mat(tex_name: String, tile_m: float, rough_value: float = 1.0, has_rough: bool = true) -> StandardMaterial3D:
	var dir := "res://assets/textures/"
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + tex_name + "_diff.jpg")
	m.normal_enabled = true
	m.normal_texture = load(dir + tex_name + "_nor.jpg")
	if has_rough:
		m.roughness_texture = load(dir + tex_name + "_rough.png")
		m.roughness = 1.0
	else:
		m.roughness = rough_value
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _add_solid(pos: Vector3, size: Vector3, mat: Material) -> void:
	_add_deco(pos, size, mat)
	_add_wall(pos, size)


func _add_deco(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)


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
	player.position = spawn_point + Vector3(0, 0.3, 0)
	add_child(player)

	player.rotation.y = 0.0
	camera = player.camera
	if not is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn_all_trash() -> void:
	_spawn_zone_trash(1)


## Bir bölgeye çöp dağıt (bölge ilk açıldığında bir kez)
func _spawn_zone_trash(zn: int) -> void:
	if zones_spawned.has(zn):
		return
	zones_spawned.append(zn)
	var want: int = ZONE_TRASH[zn]
	var placed := 0
	var tries := 0
	var r: float = IslandScript.ISLAND_RADIUS
	while placed < want and tries < 30000:
		tries += 1
		var x := randf_range(-r, r)
		var z := randf_range(-r, r)
		if island.zone_at(x, z) != zn:
			continue
		var h: float = island.height_at(x, z)
		if h < 0.4:
			continue
		var p := Vector3(x, h + 0.4, z)
		if p.distance_to(container_pos) < 5.0 or p.distance_to(spawn_point) < 3.0:
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


func _build_tool_visuals() -> void:
	# Hedef halkası (rengi alete göre değişir)
	aim_ring = MeshInstance3D.new()
	var disk := TorusMesh.new()
	disk.inner_radius = 0.95
	disk.outer_radius = 1.0
	disk.rings = 48
	disk.ring_segments = 4
	ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.65, 0.9, 1.0, 0.55)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disk.material = ring_mat
	aim_ring.mesh = disk
	add_child(aim_ring)

	# Alet parçacıkları: yumuşak kenarlı kartlar (su zerresi, ot kırpıntısı, yaprak, toz)
	var soft := GradientTexture2D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 1))
	sg.set_color(1, Color(1, 1, 1, 0))
	sg.add_point(0.55, Color(1, 1, 1, 0.75))
	soft.gradient = sg
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 64
	soft.height = 64

	spray = CPUParticles3D.new()
	spray.emitting = false
	if mist != null:
		mist.emitting = false
	spray.amount = 90
	spray.lifetime = 0.55
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.1)
	spray_mat = StandardMaterial3D.new()
	spray_mat.albedo_texture = soft
	spray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spray_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spray_mat.billboard_keep_scale = true
	spray_mat.vertex_color_use_as_albedo = true
	spray_mat.roughness = 0.6
	quad.material = spray_mat
	spray.mesh = quad
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spray.emission_sphere_radius = 0.45
	spray.angle_min = -180.0
	spray.angle_max = 180.0
	spray.angular_velocity_min = -360.0
	spray.angular_velocity_max = 360.0
	spray.scale_amount_min = 0.6
	spray.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.7, Color(1, 1, 1, 0.85))
	spray.color_ramp = fade
	add_child(spray)

	# Yıkayıcı sisi: büyüyerek kaybolan ince su buharı
	mist = CPUParticles3D.new()
	mist.emitting = false
	mist.amount = 24
	mist.lifetime = 1.3
	var mq := QuadMesh.new()
	mq.size = Vector2(0.5, 0.5)
	var mist_mat := StandardMaterial3D.new()
	mist_mat.albedo_texture = soft
	mist_mat.albedo_color = Color(0.92, 0.96, 1.0, 0.16)
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_mat.vertex_color_use_as_albedo = true
	mq.material = mist_mat
	mist.mesh = mq
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 0.35
	mist.direction = Vector3.UP
	mist.spread = 60.0
	mist.initial_velocity_min = 0.2
	mist.initial_velocity_max = 0.6
	mist.gravity = Vector3(0, 0.15, 0)
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	mist.scale_amount_curve = grow
	mist.color_ramp = fade
	add_child(mist)


func _build_audio() -> void:
	blip_stream = _make_blip(880.0, 0.07)
	coin_stream = _make_blip(1320.0, 0.12)
	for i in 6:
		var ap := AudioStreamPlayer.new()
		ap.volume_db = -8.0
		add_child(ap)
		blip_players.append(ap)
	# Her aletin kendi döngü sesi: süpürge hışırtısı, su, motor uğultusu
	tool_streams.append(_make_noise_loop(1.0, 0.12, 0.0))
	tool_streams.append(_make_noise_loop(1.0, 0.08, 0.0))
	tool_streams.append(_make_noise_loop(1.0, 0.35, 0.0))
	tool_streams.append(_make_noise_loop(1.0, 0.15, 110.0))
	spray_player = AudioStreamPlayer.new()
	add_child(spray_player)


func _build_hud() -> void:
	hud = HudScript.new()
	add_child(hud)
	hud.setup(self)


func _process(delta: float) -> void:
	if not paused:
		play_time += delta
	if shot_dir != "":
		_screenshot_step()
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
		if Vector3(h.x - player.global_position.x, 0, h.z - player.global_position.z).length() <= REACH:
			aim = h
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
	if shop_open and not near_shop and shot_dir == "":
		_set_shop_open(false)

	if touch != null:
		touch.set_interact_visible(near_shop or shop_open)
	var using := Input.is_action_pressed("use_tool") and not completed and not shop_open and aim_valid
	vacuum_active = false
	if using:
		match current_tool:
			TOOL_SCYTHE:
				_clean_layer("grass", aim, r, scythe_strength() * delta)
			TOOL_RAKE:
				_clean_layer("leaf", aim, r, broom_strength() * delta)
			TOOL_WASHER:
				_clean_layer("dirt", aim, r, washer_strength() * delta)
			TOOL_VACUUM:
				vacuum_active = true
				vacuum_point = aim
	spray.global_position = aim + Vector3(0, 0.1, 0)
	spray.emission_sphere_radius = r * (0.9 if current_tool == TOOL_VACUUM else 0.6)
	spray.emitting = using
	mist.global_position = spray.global_position
	mist.emitting = using and current_tool == TOOL_WASHER
	player.set_using(using)
	_update_water_stream(using and current_tool == TOOL_WASHER, aim)
	if using:
		if not spray_player.playing:
			spray_player.play()
	elif spray_player.playing:
		spray_player.stop()

	# Temizlikten gelen para
	tick_cooldown -= delta
	if cleaned_since_payout > 0.0:
		var gain: float = cleaned_since_payout * MONEY_PER_PIXEL * money_mult()
		money += gain
		income_total += gain
		cleaned_since_payout = 0.0
		if tick_cooldown <= 0.0:
			_play_blip(blip_stream, 1.4 + randf() * 0.3, -14.0)
			tick_cooldown = 0.09

	combo_timer -= delta
	if combo_timer <= 0.0:
		combo = 0

	_update_zones(delta)
	_update_progress()
	shown_money = move_toward(shown_money, money, maxf(1.0, absf(money - shown_money)) * delta * 6.0)
	_update_hud()


func _physics_process(_delta: float) -> void:
	if paused:
		return
	# Kapalı bölgeye girilemez: geri it
	var here: int = island.zone_at(player.global_position.x, player.global_position.z)
	if here > 0 and not island.zone_unlocked(here):
		player.global_position = Vector3(last_ok_pos.x, player.global_position.y, last_ok_pos.z)
		player.velocity = Vector3.ZERO
		if locked_msg_timer <= 0.0:
			locked_msg_timer = 2.5
			var prev: int = here - 1
			_float_text(player.global_position + Vector3(0, 2.4, 0) - player.global_transform.basis.z * 2.0,
				"%s kapalı: %s %%%d / %%%d" % [IslandScript.ZONE_NAMES[here], IslandScript.ZONE_NAMES[prev], int(island.zone_fraction(prev) * 100.0), int(IslandScript.ZONE_AUTO * 100.0)],
				Color(1.0, 0.6, 0.3))
	else:
		last_ok_pos = player.global_position
	locked_msg_timer -= _delta
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
		if to_player.length() < pickup_radius():
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
	if event.is_action_pressed("pause"):
		if shop_open:
			_set_shop_open(false)
		else:
			_toggle_pause()
		return
	if event.is_action_pressed("back"):
		if shop_open:
			_set_shop_open(false)
		elif paused:
			_toggle_pause()
		return
	if paused:
		return
	if event.is_action_pressed("interact"):
		if shop_open:
			_set_shop_open(false)
		elif near_shop:
			_set_shop_open(true)
		return
	if event.is_action_pressed("tool_next") or event.is_action_pressed("tool_prev"):
		var count_t: int = 4 if vacuum_level > 0 else 3
		_select_tool(posmod(current_tool + (1 if event.is_action_pressed("tool_next") else -1), count_t))
		return
	# Fare bırakıldıysa tıklayınca yeniden yakala (masaüstü)
	if not is_mobile and event is InputEventMouseButton and event.pressed and not shop_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				_select_tool(TOOL_SCYTHE)
			KEY_2:
				_select_tool(TOOL_RAKE)
			KEY_3:
				_select_tool(TOOL_WASHER)
			KEY_4:
				_select_tool(TOOL_VACUUM)
	elif event is InputEventMouseButton and event.pressed:
		var step := 0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = 1
		if step != 0:
			var count: int = 4 if vacuum_level > 0 else 3
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
		TOOL_SCYTHE:
			ring_mat.albedo_color = Color(0.75, 1.0, 0.45, 0.55)
			_spray_look(Vector2(0.025, 0.13), [Color(0.8, 0.72, 0.42), Color(0.62, 0.6, 0.3), Color(0.55, 0.5, 0.28)], false)
			spray.amount = 70
			spray.lifetime = 0.8
			spray.direction = Vector3.UP
			spray.spread = 70.0
			spray.initial_velocity_min = 1.5
			spray.initial_velocity_max = 3.0
			spray.gravity = Vector3(0, -6.0, 0)
			spray.radial_accel_min = 2.0
			spray.radial_accel_max = 5.0
			spray_player.volume_db = -14.0
		TOOL_RAKE:
			ring_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.55)
			_spray_look(Vector2(0.07, 0.055), [Color(0.72, 0.45, 0.2), Color(0.55, 0.36, 0.18), Color(0.82, 0.6, 0.28)], false)
			spray.amount = 40
			spray.lifetime = 0.9
			spray.direction = Vector3.UP
			spray.spread = 80.0
			spray.initial_velocity_min = 1.0
			spray.initial_velocity_max = 2.5
			spray.gravity = Vector3(0, -9.8, 0)
			spray.radial_accel_min = 4.0
			spray.radial_accel_max = 8.0
			spray_player.volume_db = -15.0
		TOOL_WASHER:
			ring_mat.albedo_color = Color(0.65, 0.9, 1.0, 0.55)
			_spray_look(Vector2(0.022, 0.09), [Color(0.85, 0.93, 1.0, 0.85), Color(0.95, 0.98, 1.0, 0.7)], true)
			spray.amount = 120
			spray.lifetime = 0.5
			spray.direction = Vector3.UP
			spray.spread = 55.0
			spray.initial_velocity_min = 2.0
			spray.initial_velocity_max = 4.5
			spray.gravity = Vector3(0, -9.8, 0)
			spray.radial_accel_min = 0.0
			spray.radial_accel_max = 0.0
			spray_player.volume_db = -18.0
		TOOL_VACUUM:
			ring_mat.albedo_color = Color(0.85, 0.65, 1.0, 0.55)
			_spray_look(Vector2(0.03, 0.03), [Color(0.75, 0.7, 0.62, 0.6), Color(0.6, 0.56, 0.5, 0.5)], true)
			spray.amount = 50
			spray.lifetime = 0.45
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


## Parçacık görünümü: kart boyutu, rastgele renk tonları, gölgeli mi
func _spray_look(size: Vector2, colors: Array, unshaded: bool) -> void:
	(spray.mesh as QuadMesh).size = size
	spray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / maxf(1.0, colors.size() - 1))
		cols.append(colors[i])
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	spray.color_initial_ramp = g


# =====================================================================
# TEMİZLİK
# =====================================================================

func _clean_layer(layer: String, p: Vector3, radius: float, amount: float) -> void:
	var n: float = island.clean(p, radius, amount, layer)
	if layer == "grass" and grass != null:
		grass.refresh_area(p, radius + 0.4)
	if n > 0.0:
		cleaned_since_payout += n
		_check_finds()


func _collect_trash(body: RigidBody3D) -> void:
	trash_bodies.erase(body)
	var value := float(body.get_meta("value", 3)) * money_mult()
	bag += 1
	bag_value += value
	stat_trash += 1
	if bag >= bag_capacity() and cart_rate() > 0.0:
		_auto_sell()
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
	_float_text(body.global_position + Vector3(0, 1.0, 0), "+" + _fmt(value), Color(1.0, 0.85, 0.3))


## El arabası: konteynere gitmeden, düşük oranla sat
func _auto_sell() -> void:
	var earned := bag_value * cart_rate()
	money += earned
	income_total += earned
	_float_text(player.global_position + Vector3(0, 2.2, 0), "El arabası: +%s" % _fmt(earned), Color(0.5, 1.0, 0.6))
	_play_blip(coin_stream, 1.1, -8.0)
	bag = 0
	bag_value = 0.0


func _sell() -> void:
	stat_sells += 1
	var earned := bag_value
	money += earned
	income_total += earned
	_float_text(container_pos + Vector3(0, 3.2, 0), "+%s SATILDI" % _fmt(earned), Color(0.5, 1.0, 0.6))
	for i in mini(bag, 6):
		get_tree().create_timer(0.06 * i).timeout.connect(_play_blip.bind(coin_stream, 1.0 + i * 0.08, -6.0))
	bag = 0
	bag_value = 0.0


func _update_zones(delta: float) -> void:
	var pp := player.global_position
	current_zone = island.zone_at(pp.x, pp.z)
	zone_timer -= delta
	if zone_timer > 0.0:
		return
	zone_timer = 0.5
	_update_quest()
	var n: int = IslandScript.ZONE_NAMES.size()
	# Kendiliğinden açılma: önceki bölge yeterince temizse
	for zn in range(2, n):
		if not island.zone_unlocked(zn) and island.zone_unlocked(zn - 1) and island.zone_fraction(zn - 1) >= IslandScript.ZONE_AUTO:
			_unlock_zone(zn)
	# Tamamlama ödülü
	for zn in range(1, n):
		if island.zone_unlocked(zn) and not zones_done.has(zn) and island.zone_fraction(zn) >= 0.97:
			zones_done.append(zn)
			props.restore(zn, false)
			var reward: float = float(island.zone_total[zn]) * MONEY_PER_PIXEL * IslandScript.ZONE_MULT[zn] * 0.25 * money_mult()
			money += reward
			income_total += reward
			_show_banner("%s TERTEMİZ!  +%s" % [str(IslandScript.ZONE_NAMES[zn]).to_upper(), _fmt(reward)])
			for i in 8:
				get_tree().create_timer(0.08 * i).timeout.connect(_play_blip.bind(coin_stream, 0.8 + i * 0.1, -4.0))


# =====================================================================
# GÖREVLER
# =====================================================================

func current_quest() -> Array:
	return Gorev.get_quest(quest_index)


func _message(who: String, text: String) -> void:
	if journal.is_empty() or journal[-1][1] != text:
		journal.append([who, text])
	if journal.size() > 80:
		journal.pop_front()
	hud.show_message(who, text)


func _update_quest() -> void:
	var q := current_quest()
	if q.is_empty():
		return
	if not quest_announced:
		quest_timer -= 0.5
		if quest_timer > 0.0:
			return
		quest_announced = true
		_message(q[0], q[2])
	if not Gorev.is_done(q, self, quest_base):
		return
	var reward: float = float(q[6]) * IslandScript.ZONE_MULT[int(q[7])] * money_mult()
	money += reward
	income_total += reward
	_show_banner("GÖREV TAMAM: %s  +%s" % [q[1], _fmt(reward)])
	for k in 6:
		get_tree().create_timer(0.09 * k).timeout.connect(_play_blip.bind(coin_stream, 0.9 + k * 0.1, -4.0))
	quest_index += 1
	quest_base = Gorev.make_base(self)
	quest_announced = false
	quest_timer = 4.5     # bir sonraki telsiz mesajı afiş kaybolunca
	if quest_index >= Gorev.count():
		quest_announced = true
		get_tree().create_timer(4.5).timeout.connect(func() -> void: _message(Gorev.SELIN, Gorev.ENDING))
	_save_game()


## Eski kayıtlar için: zaten yapılmış görevleri ödülsüz geç
func _skip_done_quests() -> void:
	while quest_index < Gorev.count() and Gorev.is_done(current_quest(), self, quest_base):
		quest_index += 1
		quest_base = Gorev.make_base(self)


func _unlock_zone(zn: int) -> void:
	if island.zone_unlocked(zn):
		return
	island.set_unlocked(island.unlocked_mask | (1 << zn))
	_spawn_zone_trash(zn)
	_show_banner("YENİ BÖLGE: %s  (kazanç ×%s)" % [IslandScript.ZONE_NAMES[zn], _fmt_mult(IslandScript.ZONE_MULT[zn])])
	for i in 5:
		get_tree().create_timer(0.1 * i).timeout.connect(_play_blip.bind(coin_stream, 0.7 + i * 0.12, -4.0))
	_save_game()


func _show_banner(text: String) -> void:
	hud.show_banner(text)


## Sıradaki kapalı bölge (yoksa -1)
func next_locked_zone() -> int:
	for zn in range(2, IslandScript.ZONE_NAMES.size()):
		if not island.zone_unlocked(zn):
			return zn
	return -1


func _update_progress() -> void:
	clean_pct = 100.0 * island.clean_fraction()
	# Etrafın ne kadar temiz? Çevredeki noktalara bak; temizlendikçe gökyüzü, ışık ve deniz açılır
	var ppos := player.global_position
	var clean_pts := 0
	var total_pts := 0
	for ring in [6.0, 14.0, 24.0]:
		for k in 8:
			var a: float = TAU * k / 8.0
			var p := ppos + Vector3(cos(a) * ring, 0, sin(a) * ring)
			if island.height_at(p.x, p.z) < 0.3:
				continue
			total_pts += 1
			if island.sample_max(p) < CLEAN_THRESHOLD:
				clean_pts += 1
	var target: float = float(clean_pts) / float(maxi(1, total_pts))
	local_clean = lerpf(local_clean, target, clampf(get_process_delta_time() * 0.6, 0.0, 1.0))
	var t := smoothstep(0.15, 0.95, local_clean)
	sky_mat.set_shader_parameter("sunny", t)
	ocean_mat.set_shader_parameter("gloom", 1.0 - t)
	if grass != null:
		grass.set_gloom(1.0 - t)
	env.adjustment_saturation = lerpf(0.7, 1.08, t)
	env.fog_density = lerpf(0.012, 0.002, t)
	env.fog_light_color = Color(0.55, 0.58, 0.62).lerp(Color(0.75, 0.82, 0.9), t)
	sun.light_energy = lerpf(0.6, 1.25, t)
	sun.light_color = Color(0.85, 0.88, 0.95).lerp(Color(1.0, 0.93, 0.82), t)


# =====================================================================
# ALETLER VE YÜKSELTMELER
# =====================================================================

func lvl(id: String) -> int:
	return int(levels.get(id, 0))

## Güç çarpanı: seviye başına +%10, her 10 seviyede ×2, her kilometre taşında ayrıca ×3
func power_mult(l: int) -> float:
	var m := (1.0 + 0.1 * l) * pow(2.0, floori(l / 10.0))
	for ms: int in MILESTONES:
		if l >= ms:
			m *= 3.0
	return m


## Sınırsız yükseltmede bir sonraki kilometre taşı (yoksa -1)
func next_milestone_level(l: int) -> int:
	for ms: int in MILESTONES:
		if l < ms:
			return ms
	return -1


## Dedektör: menzildeki en yakın bulunmamış buluntu -> [mesafe, yön yazısı]; yoksa boş
func nearest_find_info() -> Array:
	var rng := detector_range()
	if rng <= 0.0 or player == null:
		return []
	var pp := player.global_position
	var best := -1
	var bd := rng
	for i in find_positions.size():
		if found_finds.has(i):
			continue
		var d := Vector2(find_positions[i].x - pp.x, find_positions[i].z - pp.z).length()
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return []
	var to := find_positions[best] - pp
	var fwd := -player.global_transform.basis.z
	var ang := rad_to_deg(atan2(fwd.x * to.z - fwd.z * to.x, fwd.x * to.x + fwd.z * to.z))
	var yon := "önünde"
	if absf(ang) > 135.0:
		yon = "arkanda"
	elif ang > 35.0:
		yon = "sağında"
	elif ang < -35.0:
		yon = "solunda"
	return [bd, yon]


func pickup_radius() -> float:
	return WALK_PICKUP + 0.25 * lvl("magnet")


## El arabası: çanta dolunca otomatik satış oranı (0 = yok)
func cart_rate() -> float:
	var l := lvl("cart")
	return 0.0 if l == 0 else minf(1.0, 0.7 + 0.03 * l)


func detector_range() -> float:
	var l := lvl("detector")
	return 0.0 if l == 0 else 15.0 + 6.0 * l

func money_mult() -> float:
	return power_mult(lvl("bonus"))

func tool_radius() -> float:
	match current_tool:
		TOOL_SCYTHE:
			return 0.7 * (1.0 + 0.06 * lvl("scythe_w"))
		TOOL_RAKE:
			return 0.8 * (1.0 + 0.06 * lvl("broom_w"))
		TOOL_VACUUM:
			return 1.4 + 0.12 * vacuum_level
	return washer_radius()

func washer_radius() -> float:
	return 0.5 * (1.0 + 0.06 * lvl("nozzle"))

func washer_strength() -> float:
	return 80.0 * power_mult(lvl("pressure"))

func scythe_strength() -> float:
	return 100.0 * power_mult(lvl("scythe"))

func broom_strength() -> float:
	return 120.0 * power_mult(lvl("broom"))

func bag_capacity() -> int:
	return 6 + 3 * lvl("bag")

func upgrade_price(i: int) -> float:
	var u: Dictionary = UPGRADES[i]
	return float(u["base"]) * pow(float(u["growth"]), lvl(u["id"]))


## Kalan seviye hakkı (sınırsızsa çok büyük)
func upgrade_room(i: int) -> int:
	var u: Dictionary = UPGRADES[i]
	return 1000000 if int(u["max"]) < 0 else maxi(0, int(u["max"]) - lvl(u["id"]))


## n seviyenin toplam fiyatı (geometrik toplam)
func upgrade_price_n(i: int, n: int) -> float:
	if n <= 0:
		return 0.0
	var g: float = UPGRADES[i]["growth"]
	return upgrade_price(i) * (pow(g, n) - 1.0) / (g - 1.0)


## Bu parayla en fazla kaç seviye alınabilir
func upgrade_affordable(i: int, budget: float) -> int:
	var g: float = UPGRADES[i]["growth"]
	var p0 := upgrade_price(i)
	if budget < p0:
		return 0
	var n := int(floor(log(budget * (g - 1.0) / p0 + 1.0) / log(g)))
	n = mini(n, upgrade_room(i))
	while n > 0 and upgrade_price_n(i, n) > budget:
		n -= 1
	return n


## Dükkândaki seçime göre (1, 10 ya da -1 = maks) alınacak seviye sayısı
func buy_count(i: int) -> int:
	var room := upgrade_room(i)
	if buy_mode < 0:
		return maxi(1, upgrade_affordable(i, money))
	return mini(buy_mode, maxi(1, room))

func upgrade_maxed(i: int) -> bool:
	var u: Dictionary = UPGRADES[i]
	return int(u["max"]) >= 0 and lvl(u["id"]) >= int(u["max"])

## Yükseltmenin şu anki etkisi (dükkânda gösterilir)
func upgrade_effect(id: String) -> String:
	match id:
		"pressure":
			return "Çamur sökme ×%s" % _fmt_mult(power_mult(lvl(id)))
		"nozzle":
			return ("Genişlik %.2f m" % (washer_radius() * 2.0)).replace(".", ",")
		"scythe":
			return "Ot biçme ×%s" % _fmt_mult(power_mult(lvl(id)))
		"scythe_w":
			return ("Genişlik %.2f m" % (0.7 * (1.0 + 0.06 * lvl(id)) * 2.0)).replace(".", ",")
		"broom":
			return "Yaprak toplama ×%s" % _fmt_mult(power_mult(lvl(id)))
		"broom_w":
			return ("Genişlik %.2f m" % (0.8 * (1.0 + 0.06 * lvl(id)) * 2.0)).replace(".", ",")
		"bag":
			return "%d çöp" % bag_capacity()
		"vacuum":
			return "Kilitli" if vacuum_level == 0 else "Çekim Sv %d" % vacuum_level
		"shoes":
			return "Hız +%%%d" % (lvl(id) * 5)
		"bonus":
			return "Kazanç ×%s" % _fmt_mult(money_mult())
		"magnet":
			return ("Toplama mesafesi %.2f m" % pickup_radius()).replace(".", ",")
		"cart":
			return "Kilitli" if lvl(id) == 0 else "Dolunca satar · değerin %%%d'i" % int(cart_rate() * 100.0)
		"detector":
			return "Kilitli" if lvl(id) == 0 else "Menzil %d m" % int(detector_range())
	return ""


func _apply_levels() -> void:
	vacuum_level = lvl("vacuum")
	if player != null:
		var k := 1.0 + 0.05 * lvl("shoes")
		player.walk_speed = 4.5 * k
		player.run_speed = 7.5 * k


func _on_shop_button(i: int) -> void:
	if i >= UPGRADES.size():
		var zn := next_locked_zone()
		if zn > 0 and _try_pay(IslandScript.ZONE_PRICE[zn]):
			_unlock_zone(zn)
		return
	if upgrade_maxed(i):
		return
	var n := buy_count(i)
	if not _try_pay(upgrade_price_n(i, n)):
		return
	var u: Dictionary = UPGRADES[i]
	var id: String = u["id"]
	var before := lvl(id)
	levels[id] = before + n
	_apply_levels()
	if id == "vacuum" and before == 0:
		_upgrade_text("Elektrik süpürgesi açıldı! [4]")
		_select_tool(TOOL_VACUUM)
	elif id == "cart" and before == 0:
		_upgrade_text("El arabası: çanta dolunca kendiliğinden satar")
	elif id == "detector" and before == 0:
		_upgrade_text("Dedektör: yakındaki buluntular ekranda görünür")
	else:
		_upgrade_text("%s Sv %d" % [u["name"], lvl(id)])
	if int(u["max"]) < 0:
		var after := lvl(id)
		for ms: int in MILESTONES:
			if before < ms and after >= ms:
				_float_text(player.global_position + Vector3(0, 3.4, 0), "KİLOMETRE TAŞI! ×3", Color(1.0, 0.75, 0.25))
		if floori(after / 10.0) > floori(before / 10.0):
			_float_text(player.global_position + Vector3(0, 3.1, 0), "×2 SIÇRAMA!", Color(1.0, 0.8, 0.3))


func _upgrade_text(text: String) -> void:
	_float_text(player.global_position + Vector3(0, 2.6, 0), text, Color(0.6, 0.9, 1.0))


func _try_pay(price: float) -> bool:
	if money < price:
		_float_text(player.global_position + Vector3(0, 2.6, 0), "Para yetmiyor", Color(1.0, 0.5, 0.5))
		_play_blip(blip_stream, 0.5, -8.0)
		return false
	money -= price
	shown_money = money
	for i in 3:
		get_tree().create_timer(0.07 * i).timeout.connect(_play_blip.bind(coin_stream, 1.2 + i * 0.15, -6.0))
	return true


func _update_hud() -> void:
	pass   # arayüz kendini hud.gd içinde günceller


# =====================================================================
# YARDIMCILAR
# =====================================================================

func _aim_ground_point() -> Variant:
	var mp := get_viewport().get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * (REACH + 4.0))
	q.collision_mask = 1
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return null
	return r["position"]


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

# [ad, değer, bölge]  — notları gorevler.gd FIND_NOTES içinde
const FINDS := [
	["Eski bozuk para", 15, 1], ["Kayıp yüzük", 60, 1], ["Paslı anahtar", 20, 1],
	["Defter sayfası", 40, 2], ["Oyuncak araba", 30, 2],
	["Antika cep saati", 80, 3], ["Defter sayfası", 40, 3],
	["Gümüş kaşık", 35, 4], ["Defter sayfası", 40, 4],
	["Eski fotoğraf", 50, 5], ["Cam misket", 15, 5],
	["Defter sayfası", 60, 6],
]

func _place_finds() -> void:
	# Her buluntu kendi bölgesinin içinde, kara üstünde rastgele bir yere
	for info: Array in FINDS:
		var zn: int = int(info[2])
		var placed := false
		for t in 4000:
			var x := randf_range(-300.0, 300.0)
			var z := randf_range(-300.0, 300.0)
			if zn == 1:
				x = spawn_point.x + randf_range(-55.0, 55.0)
				z = spawn_point.z + randf_range(-55.0, 20.0)
			var h: float = island.height_at(x, z)
			if h < 0.6 or island.zone_at(x, z) != zn:
				continue
			find_positions.append(Vector3(x, h, z))
			placed = true
			break
		if not placed:
			find_positions.append(Vector3(spawn_point.x, island.height_at(spawn_point.x, spawn_point.z), spawn_point.z))


func _check_finds() -> void:
	for i in find_positions.size():
		if found_finds.has(i):
			continue
		var p: Vector3 = find_positions[i]
		if not island.zone_unlocked(int(FINDS[i][2])):
			continue
		if island.sample_max(p) < CLEAN_THRESHOLD:
			_reveal_find(i)


func _reveal_find(i: int) -> void:
	found_finds.append(i)
	var info: Array = FINDS[i]
	var value: float = float(info[1]) * IslandScript.ZONE_MULT[int(info[2])] * money_mult() * 5.0
	money += value
	income_total += value
	var p: Vector3 = find_positions[i]
	_float_text(p + Vector3(0, 1.4, 0), "Buldun: %s!  +%s" % [info[0], _fmt(value)], Color(1.0, 0.85, 0.3))
	_message("Buluntu · %s" % info[0], Gorev.FIND_NOTES[i] if i < Gorev.FIND_NOTES.size() else str(info[0]))
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

var save_path := "user://kayit_1.json"
var save_name := ""
var play_time := 0.0
var created_at := 0

func _load_save() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var f := FileAccess.open(save_path, FileAccess.READ)
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
		"version": 2,
		"name": save_name,
		"play_time": play_time,
		"created": created_at,
		"last_played": int(Time.get_unix_time_from_system()),
		"summary": {"zone": current_zone, "pct": clean_pct},
		"seed": world_seed,
		"money": money,
		"levels": levels,
		"bag": bag, "bag_value": bag_value, "tool": current_tool,
		"completed": completed, "milestone": next_milestone,
		"island": island.save_data(),
		"zones": {"unlocked": island.unlocked_mask, "done": zones_done, "spawned": zones_spawned},
		"trash": trash,
		"finds": found_finds,
		"quests": {"i": quest_index, "base": quest_base, "trash": stat_trash, "sells": stat_sells, "announced": quest_announced, "journal": journal},
		"player": [player.global_position.x, player.global_position.z],
		"yaw": player.rotation.y,
		"volume": master_volume,
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


func _apply_save(d: Dictionary) -> void:
	money = float(d.get("money", 0.0))
	shown_money = money
	var lv: Dictionary = d.get("levels", {})
	for k in lv:
		levels[str(k)] = int(lv[k])
	_apply_levels()
	bag = int(d.get("bag", 0))
	bag_value = float(d.get("bag_value", 0.0))
	current_tool = clampi(int(d.get("tool", TOOL_SCYTHE)), 0, 3)
	if current_tool == TOOL_VACUUM and vacuum_level == 0:
		current_tool = TOOL_SCYTHE
	completed = bool(d.get("completed", false))
	next_milestone = int(d.get("milestone", 25))
	master_volume = float(d.get("volume", 0.8))
	island.load_data(d.get("island", {}))
	var zd: Dictionary = d.get("zones", {})
	island.set_unlocked(int(zd.get("unlocked", 2)))
	for v in zd.get("done", []):
		zones_done.append(int(v))
		props.restore(int(v), true)
	for v in zd.get("spawned", [1]):
		zones_spawned.append(int(v))

	for item in d.get("trash", []):
		var a: Array = item
		_spawn_trash(Vector3(a[1], a[2], a[3]), int(a[0]), Vector3(a[4], a[5], a[6]))

	for i in d.get("finds", []):
		found_finds.append(int(i))

	var qd: Dictionary = d.get("quests", {})
	stat_trash = int(qd.get("trash", 0))
	stat_sells = int(qd.get("sells", 0))
	quest_index = int(qd.get("i", 0))
	quest_base = qd.get("base", {})
	journal = qd.get("journal", [])
	quest_announced = bool(qd.get("announced", false))
	if qd.is_empty():
		quest_base = Gorev.make_base(self)
		_skip_done_quests()
	if quest_announced:
		quest_timer = 0.0
		var q := current_quest()
		if not q.is_empty():
			quest_announced = false   # yüklemede görevi kısa bir telsizle hatırlat
			quest_timer = 2.0

	var pp: Array = d.get("player", [])
	if pp.size() == 2:
		player.position = Vector3(pp[0], island.height_at(pp[0], pp[1]) + 0.3, pp[1])
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

func _toggle_pause() -> void:
	paused = not paused
	hud.set_pause_visible(paused)
	player.set_physics_process(not paused)
	player.look_enabled = not paused
	if not is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if not paused and get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_get_focus_owner().release_focus()
	_update_water_stream(false, Vector3.ZERO)
	spray.emitting = false
	if mist != null:
		mist.emitting = false
	if spray_player.playing:
		spray_player.stop()
	if paused:
		_save_game()


## Ayarları uygula (hud.gd ayarlar menüsünden gelir)
func apply_settings(s: Dictionary) -> void:
	var q: int = s["quality"]
	var vp := get_viewport()
	env.ssao_enabled = q >= 2
	env.ssil_enabled = q >= 3
	env.glow_enabled = q >= 1
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	vp.scaling_3d_scale = 0.75 if q == 0 else 1.0
	sun.shadow_enabled = q >= 1 or not is_mobile
	sun.directional_shadow_max_distance = [40.0, 80.0, 120.0, 200.0][q]
	env.volumetric_fog_enabled = bool(s["fog"]) and not is_mobile
	if grass != null:
		grass.set_enabled(bool(s.get("grass3d", true)))
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_anisotropy = 0.6
	if player != null:
		player.camera.far = float(s["draw"]) + 200.0
		player.camera.fov = float(s["fov"])
		player.mouse_sensitivity = 0.0005 * float(s["sens"])
	if not is_mobile:
		var want_fs: bool = s["fullscreen"]
		var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
	_set_volume(float(s["volume"]))


## Test modu: sırayla oyun içi ekran, dükkân ve menü görüntüsünü kaydeder, sonra çıkar
func _screenshot_step() -> void:
	shot_frame += 1
	print("kare ", shot_frame, " @ ", Time.get_ticks_msec(), " ms")
	match shot_frame:
		5:
			money = 12500.0
			shown_money = money
			bag = 4
		25:
			_save_shot("1_oyun_ici.png")
			_set_shop_open(true)
		40:
			_save_shot("2_dukkan.png")
			_set_shop_open(false)
			_toggle_pause()
		55:
			_save_shot("3_menu.png")
			get_tree().quit()


func _save_shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_dir.path_join(name))
	print("Ekran görüntüsü kaydedildi: ", name)


func select_tool_from_ui(i: int) -> void:
	_select_tool(i)


func _set_volume(v: float) -> void:
	master_volume = v
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))


func _new_game() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	get_tree().reload_current_scene()


## Kaydet ve ana menüye dön
func _save_and_quit() -> void:
	_save_game()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menu.tscn")


func _quit_game() -> void:
	_save_game()
	get_tree().quit()


# =====================================================================
# BİRİNCİ ŞAHIS YARDIMCILARI
# =====================================================================

func _set_shop_open(open: bool) -> void:
	shop_open = open
	hud.set_shop_visible(open)
	player.look_enabled = not open
	player.set_physics_process(not open)
	if not is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if not open and get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_get_focus_owner().release_focus()
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


## Kontrolcüyle menüde gezinmek için ilk butona odaklan
func _focus_first(root: Node) -> void:
	for c in root.get_children():
		if c is Button:
			(c as Button).grab_focus()
			return
		_focus_first(c)
		if get_viewport().gui_get_focus_owner() != null:
			return


## Büyük sayıları okunur yaz: 950 / 12,5 B / 3,20 Mn / 7,1 Mr ...
const SUFFIXES := ["", " B", " Mn", " Mr", " Tn", " Kn", " Kt", " Sn", " Sp", " Ok", " No", " Dc"]

func _fmt(v: float) -> String:
	if v < 1000.0:
		return str(int(floor(v)))
	var e := 0
	while v >= 1000.0 and e < SUFFIXES.size() - 1:
		v /= 1000.0
		e += 1
	var txt: String
	if v >= 100.0:
		txt = "%d" % int(v)
	elif v >= 10.0:
		txt = "%.1f" % v
	else:
		txt = "%.2f" % v
	return txt.replace(".", ",") + SUFFIXES[e]

func _fmt_mult(v: float) -> String:
	if v < 100.0:
		return ("%.1f" % v).replace(".", ",")
	return _fmt(v)
