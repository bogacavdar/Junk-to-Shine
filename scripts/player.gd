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
var head_markers: Array = []   # alet başına zemine değen uç (yoksa null)
var scythe_blade: Node3D
var rake_head: Node3D
var gun_body_mat: StandardMaterial3D
var tier_parts: Array = [null, null, null]   # alet başına motor/ek parça düğümü

const TOOL_BASE := Vector3(0.3, -0.3, -0.55)
var bob_time := 0.0
var using_tool := false
var active_tool := 0
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
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://assets/textures/wooden_gate_diff.jpg")
	wood.albedo_color = Color(1.25, 1.1, 0.95)
	wood.uv1_scale = Vector3(0.6, 2.0, 1.0)
	wood.roughness = 0.55
	var blade_steel := StandardMaterial3D.new()
	blade_steel.albedo_color = Color(0.55, 0.56, 0.58)
	blade_steel.metallic = 0.85
	blade_steel.roughness = 0.35
	blade_steel.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Tırpan: uzun ahşap sap, ortada tutamak, ucunda yere paralel kavisli bıçak
	var scythe := Node3D.new()
	scythe.position = Vector3(0.05, 0.1, 0.1)
	var s_dir := Vector3(-0.35, -0.7, -1.3).normalized()
	scythe.quaternion = Quaternion(Vector3.UP, -s_dir)
	tool_root.add_child(scythe)
	var s_stick := CylinderMesh.new()
	s_stick.top_radius = 0.017
	s_stick.bottom_radius = 0.019
	s_stick.height = 1.6
	s_stick.radial_segments = 12
	s_stick.material = wood
	_add_to(scythe, s_stick, Vector3(0, -0.8, 0))
	var s_handle := CylinderMesh.new()
	s_handle.top_radius = 0.014
	s_handle.bottom_radius = 0.014
	s_handle.height = 0.16
	s_handle.radial_segments = 10
	s_handle.material = wood
	var sh := _add_to(scythe, s_handle, Vector3(0.07, -0.45, 0))
	sh.rotation_degrees = Vector3(0, 0, 90)
	var blade := MeshInstance3D.new()
	blade.mesh = _scythe_blade(blade_steel)
	blade.position = Vector3(0, -1.6, 0)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scythe.add_child(blade)
	scythe_blade = blade
	var s_tip := Node3D.new()
	s_tip.position = Vector3(0, -1.62, 0)
	scythe.add_child(s_tip)

	# Tırmık: ahşap sap, metal kafa, aşağı bakan dişler
	var rake := Node3D.new()
	rake.position = Vector3(0.05, 0.12, 0.12)
	var r_dir := Vector3(-0.2, -0.75, -1.4).normalized()
	rake.quaternion = Quaternion(Vector3.UP, -r_dir)
	tool_root.add_child(rake)
	var r_stick := CylinderMesh.new()
	r_stick.top_radius = 0.016
	r_stick.bottom_radius = 0.018
	r_stick.height = 1.6
	r_stick.radial_segments = 12
	r_stick.material = wood
	_add_to(rake, r_stick, Vector3(0, -0.8, 0))
	rake_head = Node3D.new()
	rake_head.position = Vector3(0, -1.6, 0)
	rake.add_child(rake_head)
	var bar := BoxMesh.new()
	bar.size = Vector3(0.42, 0.03, 0.035)
	bar.material = blade_steel
	_add_to(rake_head, bar, Vector3.ZERO)
	var tine := CylinderMesh.new()
	tine.top_radius = 0.005
	tine.bottom_radius = 0.004
	tine.height = 0.1
	tine.radial_segments = 6
	tine.material = blade_steel
	for i in 14:
		var tx := -0.195 + i * (0.39 / 13.0)
		var tm := _add_to(rake_head, tine, Vector3(tx, -0.04, 0.03))
		tm.rotation_degrees = Vector3(-35, 0, 0)
	var r_tip := Node3D.new()
	r_tip.position = Vector3(0, -1.69, 0.06)
	rake.add_child(r_tip)

	# Basınçlı yıkama tabancası: sarı gövde, kabza, tetik, metal uzatma borusu, nozül, hortum.
	# Tabanca nişangâha (ekran ortasında ~3 m ileri) bakacak şekilde döndürülür.
	var gun := Node3D.new()
	tool_root.add_child(gun)
	gun.basis = Basis.looking_at((Vector3(0, 0, -3.0) - TOOL_BASE).normalized(), Vector3.UP)
	var yellow := _mat(Color(0.95, 0.72, 0.05), 0.4)
	gun_body_mat = yellow
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
	var v_tip := Node3D.new()
	v_tip.position = Vector3(0, -0.76, 0)
	vac.add_child(v_tip)

	tool_nodes = [scythe, rake, gun, vac]
	head_markers = [s_tip, r_tip, null, v_tip]


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
				# Tırpan: geniş, yatay savuruş
				var sw := sin(use_time * 4.5)
				target_rot = Vector3(0, sw * 0.55, sw * -0.12)
			1:
				# Tırmık: ileri uzanıp geri çekme
				tool_root.position += Vector3(0, 0, sin(use_time * 6.0) * 0.12)
				target_rot = Vector3(sin(use_time * 6.0) * 0.06, 0, 0)
			2:
				tool_root.position += Vector3(randf_range(-0.003, 0.003), randf_range(-0.003, 0.003), 0.012)
			3:
				tool_root.position += Vector3(randf_range(-0.0025, 0.0025), randf_range(-0.0025, 0.0025), 0)
	else:
		use_time = 0.0
	tool_root.rotation = tool_root.rotation.lerp(target_rot, clampf(delta * 12.0, 0.0, 1.0))
	_keep_tool_above_ground()


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


## Aletin ucu zeminin içine girmesin: uç zeminin altındaysa aleti yukarı kaldır
func _keep_tool_above_ground() -> void:
	if active_tool >= head_markers.size() or head_markers[active_tool] == null:
		return
	var tip: Node3D = head_markers[active_tool]
	var p := tip.global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.5, 0), p + Vector3(0, -0.5, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var ground_y: float = (hit["position"] as Vector3).y + 0.02
	if p.y < ground_y:
		tool_root.global_position += Vector3(0, ground_y - p.y, 0)


## Tırpan bıçağı: yere paralel, hafif kavisli, uca doğru incelen ince metal şerit
func _scythe_blade(mat: Material) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var seg := 14
	var length := 0.75
	for i in seg:
		var t0 := float(i) / seg
		var t1 := float(i + 1) / seg
		var a0 := _blade_pt(t0, length)
		var a1 := _blade_pt(t1, length)
		var b0 := a0 + Vector3(0, 0, lerpf(0.09, 0.005, t0))
		var b1 := a1 + Vector3(0, 0, lerpf(0.09, 0.005, t1))
		st.set_normal(Vector3.UP)
		st.add_vertex(a0)
		st.add_vertex(a1)
		st.add_vertex(b1)
		st.add_vertex(a0)
		st.add_vertex(b1)
		st.add_vertex(b0)
	return st.commit()


## Bıçak sapa dik olarak yana uzanır ve uca doğru öne kıvrılır
func _blade_pt(t: float, length: float) -> Vector3:
	return Vector3(-t * length, 0.0, -sin(t * PI * 0.5) * 0.22)


## Alet kademeleri: motor gövdesi, daha geniş kafa, farklı renk
func set_tier(t_scythe: int, t_rake: int, t_washer: int) -> void:
	var tiers := [t_scythe, t_rake, t_washer]
	var engine_col := [Color(0.95, 0.42, 0.08), Color(0.85, 0.12, 0.1)]
	for t in 2:
		if tier_parts[t] != null:
			tier_parts[t].queue_free()
			tier_parts[t] = null
		var k: int = tiers[t]
		if k == 0:
			continue
		var pod := Node3D.new()
		pod.position = Vector3(0, -0.25, 0.0)
		tool_nodes[t].add_child(pod)
		tier_parts[t] = pod
		# Motor gövdesi: renkli kapak, siyah silindir, egzoz
		var shell := BoxMesh.new()
		shell.size = Vector3(0.13, 0.16, 0.12)
		shell.material = _mat(engine_col[k - 1], 0.35)
		_add_to(pod, shell, Vector3(0, 0, 0.07))
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.045
		cyl.bottom_radius = 0.045
		cyl.height = 0.1
		cyl.radial_segments = 14
		cyl.material = _mat(Color(0.08, 0.08, 0.09), 0.6)
		var cm := _add_to(pod, cyl, Vector3(0.0, -0.03, 0.13))
		cm.rotation_degrees = Vector3(0, 0, 90)
		var pipe := CylinderMesh.new()
		pipe.top_radius = 0.01
		pipe.bottom_radius = 0.01
		pipe.height = 0.08
		pipe.material = _mat(Color(0.6, 0.6, 0.62), 0.3)
		_add_to(pod, pipe, Vector3(0.05, 0.08, 0.1))
	var w := pow(1.35, t_scythe)
	scythe_blade.scale = Vector3(w, 1.0, w)
	rake_head.scale = Vector3(pow(1.35, t_rake) * (1.0 if t_rake < 2 else 1.25), 1.0, 1.0)
	var gun_cols := [Color(0.95, 0.72, 0.05), Color(0.1, 0.35, 0.75), Color(0.85, 0.12, 0.1)]
	gun_body_mat.albedo_color = gun_cols[clampi(t_washer, 0, 2)]
