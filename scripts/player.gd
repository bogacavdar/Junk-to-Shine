extends CharacterBody3D
## Oyuncu: WASD ile yürür, görseli aletin baktığı yere döner.

var speed := 7.5
var visual: Node3D


func _ready() -> void:
	collision_layer = 4   # oyuncu katmanı
	collision_mask = 1    # sadece dünyaya çarpar, çöplerin içinden geçer

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	add_child(cs)

	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)

	# Gövde (tulum)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.35
	body_mesh.height = 1.3
	body_mesh.radial_segments = 8
	body_mesh.rings = 2
	body_mesh.material = _mat(Color(0.2, 0.45, 0.8))
	_add_mesh(body_mesh, Vector3(0, 0.75, 0))

	# Kafa
	var head := SphereMesh.new()
	head.radius = 0.26
	head.height = 0.52
	head.radial_segments = 8
	head.rings = 4
	head.material = _mat(Color(0.96, 0.78, 0.62))
	_add_mesh(head, Vector3(0, 1.65, 0))

	# Kep
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.24
	cap_mesh.bottom_radius = 0.28
	cap_mesh.height = 0.14
	cap_mesh.radial_segments = 8
	cap_mesh.material = _mat(Color(1.0, 0.75, 0.1))
	_add_mesh(cap_mesh, Vector3(0, 1.86, 0))

	# Sırt tankı
	var tank := BoxMesh.new()
	tank.size = Vector3(0.45, 0.6, 0.25)
	tank.material = _mat(Color(1.0, 0.75, 0.1))
	_add_mesh(tank, Vector3(0, 1.0, 0.38))

	# Yıkama tabancası (ileri, -Z yönüne bakar)
	var gun := CylinderMesh.new()
	gun.top_radius = 0.05
	gun.bottom_radius = 0.07
	gun.height = 0.7
	gun.radial_segments = 6
	gun.material = _mat(Color(0.25, 0.25, 0.28))
	var gun_mi := _add_mesh(gun, Vector3(0.32, 0.95, -0.4))
	gun_mi.rotation_degrees = Vector3(-80, 0, 0)


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity.x = input.x * speed
	velocity.z = input.y * speed
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 25.0 * delta
	move_and_slide()


func face(point: Vector3) -> void:
	var flat := Vector3(point.x, visual.global_position.y, point.z)
	if flat.distance_to(visual.global_position) > 0.2:
		visual.look_at(flat, Vector3.UP)


func _add_mesh(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	visual.add_child(mi)
	return mi


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m
