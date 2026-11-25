extends CharacterBody3D
## Birinci şahıs oyuncu: fareyle bakar, WASD ile yürür (Shift: koş).
## Elindeki alet kameraya bağlı, yürürken hafifçe sallanır.

var walk_speed := 4.5
var run_speed := 7.5
var mouse_sensitivity := 0.0025
var look_enabled := true

var head: Node3D
var camera: Camera3D
var tool_root: Node3D
var tool_nodes: Array[Node3D] = []
var nozzle_marker: Node3D

const TOOL_BASE := Vector3(0.3, -0.3, -0.55)
var bob_time := 0.0
var using_tool := false
var active_tool := 1
var use_time := 0.0


func _ready() -> void:
	collision_layer = 4   # oyuncu katmanı
	collision_mask = 1    # sadece dünyaya çarpar, çöplerin içinden geçer

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)

	head = Node3D.new()
	head.position.y = 1.65
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 1500.0
	head.add_child(camera)
	camera.current = true

	tool_root = Node3D.new()
	tool_root.position = TOOL_BASE
	camera.add_child(tool_root)
	_build_tools()


func _build_tools() -> void:
	# Süpürge: sap sağ alttan öne-aşağı uzanır, fırça başı ekranın altında görünür
	var broom := Node3D.new()
	broom.position = Vector3(0.05, 0.12, 0.12)
	var stick_dir := Vector3(-0.2, -0.75, -1.4).normalized()
	broom.quaternion = Quaternion(Vector3.UP, -stick_dir)
	tool_root.add_child(broom)
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://assets/textures/wooden_gate_diff.jpg")
	wood.albedo_color = Color(1.25, 1.1, 0.95)
	wood.uv1_scale = Vector3(0.6, 2.0, 1.0)
	wood.roughness = 0.55
	var stick := CylinderMesh.new()
	stick.top_radius = 0.016
	stick.bottom_radius = 0.018
	stick.height = 1.7
	stick.radial_segments = 12
	stick.material = wood
	_add_to(broom, stick, Vector3(0, -0.85, 0))
	var block := BoxMesh.new()
	block.size = Vector3(0.42, 0.06, 0.09)
	block.material = wood
	_add_to(broom, block, Vector3(0, -1.72, 0))
	var bristle_mat := _mat(Color(0.32, 0.22, 0.12), 0.95)
	for i in 14:
		var bristle := BoxMesh.new()
		bristle.size = Vector3(0.022, 0.13, 0.07)
		bristle.material = bristle_mat
		var bx := -0.19 + i * (0.38 / 13.0)
		var bm := _add_to(broom, bristle, Vector3(bx, -1.81, 0.0))
		bm.rotation_degrees = Vector3(0, 0, randf_range(-6.0, 6.0))

	# Basınçlı yıkama tabancası: sarı gövde, kabza, tetik, metal uzatma borusu, nozül, hortum.
	# Tabanca nişangâha (ekran ortasında ~3 m ileri) bakacak şekilde döndürülür.
	var gun := Node3D.new()
	tool_root.add_child(gun)
	gun.basis = Basis.looking_at((Vector3(0, 0, -3.0) - TOOL_BASE).normalized(), Vector3.UP)
	var yellow := _mat(Color(0.95, 0.72, 0.05), 0.4)
	var black := _mat(Color(0.06, 0.06, 0.07), 0.7)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.76, 0.78)
	steel.metallic = 0.9
	steel.roughness = 0.28

	var body := CapsuleMesh.new()
	body.radius = 0.035
	body.height = 0.26
	body.material = yellow
	var body_mi := _add_to(gun, body, Vector3(0, 0, 0.02))
	body_mi.rotation_degrees = Vector3(90, 0, 0)
	var grip := CapsuleMesh.new()
	grip.radius = 0.024
	grip.height = 0.16
	grip.material = black
	var grip_mi := _add_to(gun, grip, Vector3(0, -0.075, 0.09))
	grip_mi.rotation_degrees = Vector3(-18, 0, 0)
	var trigger := BoxMesh.new()
	trigger.size = Vector3(0.014, 0.05, 0.02)
	trigger.material = black
	var trig_mi := _add_to(gun, trigger, Vector3(0, -0.05, 0.035))
	trig_mi.rotation_degrees = Vector3(-15, 0, 0)

	var lance := CylinderMesh.new()
	lance.top_radius = 0.009
	lance.bottom_radius = 0.009
	lance.height = 0.62
	lance.radial_segments = 12
	lance.material = steel
	var lance_mi := _add_to(gun, lance, Vector3(0, 0.005, -0.42))
	lance_mi.rotation_degrees = Vector3(90, 0, 0)
	var sleeve := CylinderMesh.new()
	sleeve.top_radius = 0.016
	sleeve.bottom_radius = 0.016
	sleeve.height = 0.1
	sleeve.radial_segments = 12
	sleeve.material = black
	var sleeve_mi := _add_to(gun, sleeve, Vector3(0, 0.005, -0.16))
	sleeve_mi.rotation_degrees = Vector3(90, 0, 0)
	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.018
	nozzle.bottom_radius = 0.013
	nozzle.height = 0.07
	nozzle.radial_segments = 12
	nozzle.material = black
	var noz_mi := _add_to(gun, nozzle, Vector3(0, 0.005, -0.76))
	noz_mi.rotation_degrees = Vector3(90, 0, 0)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.009
	tip.bottom_radius = 0.011
	tip.height = 0.025
	tip.radial_segments = 10
	tip.material = _mat(Color(0.85, 0.1, 0.08), 0.5)
	var tip_mi := _add_to(gun, tip, Vector3(0, 0.005, -0.805))
	tip_mi.rotation_degrees = Vector3(90, 0, 0)
	nozzle_marker = Node3D.new()
	nozzle_marker.position = Vector3(0, 0.005, -0.82)
	gun.add_child(nozzle_marker)

	var hose := CylinderMesh.new()
	hose.top_radius = 0.011
	hose.bottom_radius = 0.011
	hose.height = 0.6
	hose.radial_segments = 8
	hose.material = black
	var hose_mi := _add_to(gun, hose, Vector3(0, -0.2, 0.25))
	hose_mi.rotation_degrees = Vector3(-35, 0, 0)

	# Elektrik süpürgesi: kalın hortum + geniş ağız
	var vac := Node3D.new()
	vac.rotation_degrees = Vector3(-40, 5, 0)
	tool_root.add_child(vac)
	var tube := CylinderMesh.new()
	tube.top_radius = 0.045
	tube.bottom_radius = 0.045
	tube.height = 1.0
	tube.radial_segments = 14
	tube.material = _mat(Color(0.45, 0.3, 0.65), 0.5)
	_add_to(vac, tube, Vector3(0, -0.2, 0))
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.35, 0.07, 0.16)
	mouth.material = _mat(Color(0.2, 0.2, 0.22), 0.6)
	_add_to(vac, mouth, Vector3(0, -0.72, 0))

	tool_nodes = [broom, gun, vac]


func _unhandled_input(event: InputEvent) -> void:
	if not look_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x - motion.relative.y * mouse_sensitivity, deg_to_rad(-85.0), deg_to_rad(80.0))


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3.ZERO
	if input.length() > 0.05:
		dir = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	# Kontrolcü sağ çubuğu ile bakış
	if look_enabled:
		var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if look.length() > 0.0:
			add_look(Vector2(look.x * 2.6, look.y * 2.0) * delta * (1.0 + look.length()))
	var running := Input.is_action_pressed("run")
	var spd := run_speed if running else walk_speed
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 25.0 * delta
	move_and_slide()

	# Yürürken kafa ve alet sallanması
	if dir != Vector3.ZERO and is_on_floor():
		bob_time += delta * spd * 1.7
	else:
		bob_time = lerpf(bob_time, roundf(bob_time / PI) * PI, clampf(delta * 6.0, 0.0, 1.0))
	camera.position.y = sin(bob_time) * 0.035
	tool_root.position = TOOL_BASE + Vector3(cos(bob_time * 0.5) * 0.012, sin(bob_time) * 0.018, 0)

	# Kullanırken alet hareketi: süpürge sağa sola süpürür, yıkayıcı tepme, elektrik süpürgesi titreşim
	var target_rot := Vector3.ZERO
	if using_tool:
		use_time += delta
		match active_tool:
			0:
				target_rot = Vector3(0, sin(use_time * 7.0) * 0.32, sin(use_time * 7.0) * -0.08)
			1:
				tool_root.position += Vector3(randf_range(-0.003, 0.003), randf_range(-0.003, 0.003), 0.012)
			2:
				tool_root.position += Vector3(randf_range(-0.0025, 0.0025), randf_range(-0.0025, 0.0025), 0)
	else:
		use_time = 0.0
	tool_root.rotation = tool_root.rotation.lerp(target_rot, clampf(delta * 12.0, 0.0, 1.0))


## Bakış açısını değiştirir (radyan cinsinden yatay/dikey). Kontrolcü ve dokunmatik kullanır.
func add_look(v: Vector2) -> void:
	if not look_enabled:
		return
	rotate_y(-v.x)
	head.rotation.x = clampf(head.rotation.x - v.y, deg_to_rad(-85.0), deg_to_rad(80.0))


func nozzle_position() -> Vector3:
	if nozzle_marker != null:
		return nozzle_marker.global_position
	return tool_root.global_position - camera.global_basis.z * 0.6


func set_using(v: bool) -> void:
	using_tool = v


func set_tool(t: int) -> void:
	active_tool = t
	for i in tool_nodes.size():
		tool_nodes[i].visible = (i == t)


func cheer() -> void:
	pass


func _add_to(parent: Node3D, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
