extends Node3D
## Koddan yapılan bölge modelleri önizlemesi (test): fener, feribot, tekneler, köy çeşmesi.
## Çalıştırma: godot --path . res://test/bolge_onizleme.tscn -- --ekran=/tmp/ekran

const PropsScript := preload("res://scripts/props.gd")

class FakeIsland:
	var spawn_point := Vector3(0, 1, 40)
	func height_at(x: float, z: float) -> float:
		# Düz kara x > -20; batısı deniz. Fener noktasında tepe.
		var hill := maxf(0.0, 1.0 - Vector2(x - 150.0, z + 150.0).length() / 30.0) * 6.0
		return (1.0 if x > -20.0 else -2.0) + hill
	func zone_at(_x: float, _z: float) -> int:
		return 4
	func path_distance(_x: float, _z: float) -> float:
		return 10.0

var frame := 0
var shot_dir := "user://onizleme"
var cam: Camera3D
var props


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ekran="):
			shot_dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := PanoramaSkyMaterial.new()
	psm.panorama = load("res://assets/textures/sky_sunny.hdr")
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	# Kara ve deniz
	var land := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 600)
	land.mesh = pm
	land.position = Vector3(180, 1.0, -100)
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/coast_sand_rocks_02_diff.jpg")
	gm.uv1_scale = Vector3(60, 90, 1)
	gm.roughness = 0.95
	land.material_override = gm
	add_child(land)
	var sea := MeshInstance3D.new()
	var sm := PlaneMesh.new()
	sm.size = Vector2(2000, 2000)
	sea.mesh = sm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.08, 0.28, 0.38)
	wm.roughness = 0.08
	wm.metallic = 0.4
	sea.material_override = wm
	add_child(sea)
	# Bölge yapıları
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://assets/textures/wooden_gate_diff.jpg")
	wood.uv1_triplanar = true
	var conc := StandardMaterial3D.new()
	conc.albedo_texture = load("res://assets/textures/square_concrete_pavers_diff.jpg")
	conc.uv1_triplanar = true
	conc.uv1_scale = Vector3.ONE * 0.5
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.23, 0.24)
	metal.metallic = 0.8
	metal.roughness = 0.45
	props = PropsScript.new()
	props.island = FakeIsland.new()
	props.mats = {"wood": wood, "concrete": conc, "metal": metal}
	add_child(props)
	props.pier_end = Vector3(-40, 1.35, 20)
	props._build_ferry()
	props._build_lighthouse()
	props._build_village()
	var harbor := Node3D.new()
	harbor.name = "Liman"
	props.add_child(harbor)
	var cols := [Color(0.1, 0.32, 0.6), Color(0.85, 0.82, 0.75), Color(0.72, 0.16, 0.12)]
	for i in 3:
		var b: Node3D = props._boat(harbor, 6.0 + i * 0.6, cols[i])
		b.position = Vector3(-26.0 - i * 0.2, -0.35, 40.0 + i * 5.0)
	props.restore(3, true)
	props.restore(4, true)
	props.restore(7, true)
	cam = Camera3D.new()
	cam.fov = 70
	add_child(cam)
	cam.make_current()
	_view(0)


func _view(k: int) -> void:
	match k:
		0:  # Fener, uzaktan
			cam.position = Vector3(90, 8, -95)
			cam.look_at(Vector3(150, 18, -150))
		1:  # Tekneler ve feribot
			cam.position = Vector3(-14, 4, 30)
			cam.look_at(Vector3(-24, 1, 42))
		2:  # Köy çeşmesi ve banklar
			cam.position = Vector3(10, 4.5, 22)
			cam.look_at(Vector3(0, 1.5, 0))


func _process(_delta: float) -> void:
	frame += 1
	var names := ["8_fener.png", "9_tekneler.png", "10_koy_meydani.png"]
	for k in 3:
		if frame == 40 + k * 30:
			get_viewport().get_texture().get_image().save_png(shot_dir.path_join(names[k]))
			print("Ekran görüntüsü kaydedildi: ", names[k])
			if k < 2:
				_view(k + 1)
			else:
				get_tree().quit()
