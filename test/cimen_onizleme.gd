extends Node3D
## 3D ot ve parçacık önizlemesi (test): düz zemin, ortasında biçilmiş bir şerit, yıkayıcı parçacıkları.
## Çalıştırma: godot --path . res://test/cimen_onizleme.tscn -- --ekran=/tmp/ekran

const GrassScript := preload("res://scripts/grass.gd")

class FakeIsland:
	func sample(p: Vector3, _layer: String) -> int:
		# x = -0.8..0.8 arası biçilmiş şerit, geri kalan uzun ot
		if absf(p.x - 0.3) < 0.8 and p.z > -8.0:
			return 0
		return 120 + int(80.0 * (0.5 + 0.5 * sin(p.x * 0.7) * cos(p.z * 0.5)))
	func ground_height(_x: float, _z: float) -> float:
		return 0.0

var frame := 0
var shot_dir := "user://onizleme"


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
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	# Zemin: biçilmiş çim yerine şimdilik kıyı toprağı dokusu
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/coast_sand_rocks_02_diff.jpg")
	gm.normal_enabled = true
	gm.normal_texture = load("res://assets/textures/coast_sand_rocks_02_nor.jpg")
	gm.uv1_scale = Vector3(20, 20, 1)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	var target := Node3D.new()
	add_child(target)
	var grass := GrassScript.new()
	add_child(grass)
	grass.setup(FakeIsland.new(), target)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.65, 7)
	cam.rotation_degrees = Vector3(-14, 0, 0)
	cam.fov = 75
	add_child(cam)
	cam.make_current()


func _process(_delta: float) -> void:
	frame += 1
	if frame == 40:
		get_viewport().get_texture().get_image().save_png(shot_dir.path_join("6_cimen.png"))
		print("Ekran görüntüsü kaydedildi: 6_cimen.png")
		get_tree().quit()
