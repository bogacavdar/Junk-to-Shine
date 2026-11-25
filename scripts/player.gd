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

const TOOL_BASE := Vector3(0.3, -0.3, -0.55)
var bob_time := 0.0


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
	camera.far = 400.0
	head.add_child(camera)
	camera.current = true

	tool_root = Node3D.new()
	tool_root.position = TOOL_BASE
	camera.add_child(tool_root)
	_build_tools()


func _build_tools() -> void:
	# Süpürge: sap + fırça başı, öne ve aşağı eğik
	var broom := Node3D.new()
	broom.rotation_degrees = Vector3(-35, 8, 0)
	tool_root.add_child(broom)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.018
	stick.bottom_radius = 0.018
	stick.height = 1.3
	stick.radial_segments = 10
	stick.material = _mat(Color(0.55, 0.38, 0.2), 0.7)
	_add_to(broom, stick, Vector3(0, -0.25, 0))
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.45, 0.08, 0.12)
	head_mesh.material = _mat(Color(0.75, 0.6, 0.25), 0.9)
	_add_to(broom, head_mesh, Vector3(0, -0.9, 0))

	# Basınçlı yıkama tabancası
	var gun := Node3D.new()
	tool_root.add_child(gun)
	var body := BoxMesh.new()
	body.size = Vector3(0.07, 0.14, 0.22)
	body.material = _mat(Color(0.9, 0.75, 0.1), 0.45)
	_add_to(gun, body, Vector3(0, 0, 0))
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.016
	barrel.bottom_radius = 0.02
	barrel.height = 0.55
	barrel.radial_segments = 12
	barrel.material = _mat(Color(0.2, 0.2, 0.22), 0.3)
	var barrel_mi := _add_to(gun, barrel, Vector3(0, 0.04, -0.35))
	barrel_mi.rotation_degrees = Vector3(-90, 0, 0)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.05, 0.14, 0.06)
	grip.material = _mat(Color(0.15, 0.15, 0.16), 0.8)
	var grip_mi := _add_to(gun, grip, Vector3(0, -0.1, 0.04))
	grip_mi.rotation_degrees = Vector3(15, 0, 0)

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


## Bakış açısını değiştirir (radyan cinsinden yatay/dikey). Kontrolcü ve dokunmatik kullanır.
func add_look(v: Vector2) -> void:
	if not look_enabled:
		return
	rotate_y(-v.x)
	head.rotation.x = clampf(head.rotation.x - v.y, deg_to_rad(-85.0), deg_to_rad(80.0))


func nozzle_position() -> Vector3:
	return tool_root.global_position - camera.global_basis.z * 0.6 + camera.global_basis.y * 0.04


func set_tool(t: int) -> void:
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
