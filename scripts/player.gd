extends CharacterBody3D
## Oyuncu: WASD ile yürür, görseli aletin baktığı yere döner.

var speed := 7.5
var visual: Node3D
var tool_nodes: Array[Node3D] = []
var character: Node3D
var anim: AnimationPlayer
var cheering := false

const Models := preload("res://scripts/models.gd")


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

	# Karakter modeli: KayKit Rogue (silah ve pelerin gizli), +Z'ye baktığı için 180° çevrilir
	character = Models.make("res://assets/character/Rogue.glb", 1.85, true)
	character.rotation_degrees.y = 180.0
	visual.add_child(character)
	for part in ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable", "Rogue_Cape"]:
		var n := character.find_child(part, true, false)
		if n is Node3D:
			(n as Node3D).visible = false
	var ap := character.find_child("AnimationPlayer", true, false)
	if ap is AnimationPlayer:
		anim = ap as AnimationPlayer
		for loop_name in ["Idle", "Running_A", "Walking_A"]:
			if anim.has_animation(loop_name):
				anim.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
		_play("Idle")

	# Sırt tankı
	var tank := BoxMesh.new()
	tank.size = Vector3(0.4, 0.5, 0.22)
	tank.material = _mat(Color(1.0, 0.75, 0.1))
	_add_mesh(tank, Vector3(0, 1.05, 0.32))

	# Yıkama tabancası (ileri, -Z yönüne bakar)
	var gun := CylinderMesh.new()
	gun.top_radius = 0.05
	gun.bottom_radius = 0.07
	gun.height = 0.7
	gun.radial_segments = 6
	gun.material = _mat(Color(0.25, 0.25, 0.28))
	var gun_mi := _add_mesh(gun, Vector3(0.32, 0.95, -0.4))
	gun_mi.rotation_degrees = Vector3(-80, 0, 0)

	# Süpürge: sap + fırça başı, öne ve yere doğru eğik
	var broom := Node3D.new()
	broom.position = Vector3(0.35, 0.95, -0.3)
	broom.rotation_degrees = Vector3(40, 0, 0)
	visual.add_child(broom)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.03
	stick.bottom_radius = 0.03
	stick.height = 1.4
	stick.radial_segments = 6
	stick.material = _mat(Color(0.6, 0.42, 0.22))
	_add_to(broom, stick, Vector3.ZERO)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.55, 0.12, 0.18)
	head_mesh.material = _mat(Color(0.85, 0.7, 0.3))
	_add_to(broom, head_mesh, Vector3(0, -0.7, 0))

	# Elektrik süpürgesi: kalın hortum + geniş ağız
	var vac := Node3D.new()
	vac.position = Vector3(0.32, 0.85, -0.35)
	vac.rotation_degrees = Vector3(50, 0, 0)
	visual.add_child(vac)
	var tube := CylinderMesh.new()
	tube.top_radius = 0.08
	tube.bottom_radius = 0.08
	tube.height = 1.1
	tube.radial_segments = 8
	tube.material = _mat(Color(0.55, 0.35, 0.75))
	_add_to(vac, tube, Vector3.ZERO)
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.45, 0.1, 0.22)
	mouth.material = _mat(Color(0.25, 0.25, 0.28))
	_add_to(vac, mouth, Vector3(0, -0.55, 0))

	tool_nodes = [broom, gun_mi, vac]


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity.x = input.x * speed
	velocity.z = input.y * speed
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 25.0 * delta
	move_and_slide()
	if not cheering:
		_play("Running_A" if input.length() > 0.1 else "Idle")


func _play(anim_name: String) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	if anim.current_animation != anim_name:
		anim.play(anim_name, 0.15)


func cheer() -> void:
	if anim == null or not anim.has_animation("Cheer"):
		return
	cheering = true
	anim.play("Cheer", 0.15)
	await anim.animation_finished
	cheering = false


func set_tool(t: int) -> void:
	for i in tool_nodes.size():
		tool_nodes[i].visible = (i == t)


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


func _add_to(parent: Node3D, mesh: Mesh, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m
