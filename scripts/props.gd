extends Node3D
## Bölgelerin yapıları ve doğa: iskele, sahil eşyaları, liman rıhtımı, kayalar, çalılar.
## Modeller Poly Haven'dan (CC0). Her bölgenin yapıları önce yıpranmış görünür;
## bölge tamamlanınca "yenilenmiş" hâline geçer.

var island = null            # island.gd
var mats := {}               # "wood", "concrete", "metal"
var zone_sets := {}          # bölge -> Array[Dictionary] (yenilenecek parçalar)
var rng := RandomNumberGenerator.new()
var _templates := {}         # model yolu -> örnek sahne (parça kopyalamak için)

const DIRTY := Color(0.42, 0.40, 0.34)
const DECK_Y := 1.35
const M := "res://assets/models/"
const PIER := M + "modular_wooden_pier/modular_wooden_pier_2k.gltf"
const CRATE := M + "wooden_crate_01/wooden_crate_01_2k.gltf"
const BARRELS := M + "wooden_barrels_01/wooden_barrels_01_2k.gltf"
const PCRATE := M + "plastic_crate_02/plastic_crate_02_2k.gltf"
const LIFEBUOY := M + "lifebuoy/lifebuoy_2k.gltf"
const BUOY := M + "ocean_buoy/ocean_buoy_2k.gltf"
const LAMP := M + "street_lamp_01/street_lamp_01_2k.gltf"
const BENCH := M + "painted_wooden_bench/painted_wooden_bench_2k.gltf"
const PICNIC := M + "wooden_picnic_table/wooden_picnic_table_2k.gltf"
const CHAIR := M + "plastic_monobloc_chair_01/plastic_monobloc_chair_01_2k.gltf"
const ROCKS := M + "rock_moss_set_01/rock_moss_set_01_2k.gltf"
const ROCK07 := M + "rock_07/rock_07_2k.gltf"
const ROCK09 := M + "rock_09/rock_09_2k.gltf"
const SHRUB := M + "shrub_03/shrub_03_2k.gltf"
const LOG := M + "dead_tree_trunk/dead_tree_trunk_2k.gltf"


func setup(isl, materials: Dictionary, seed_value: int) -> void:
	island = isl
	mats = materials
	rng.seed = seed_value
	_build_pier()
	_build_beach()
	_build_harbor()
	_build_nature()
	for t: Node in _templates.values():
		t.free()
	_templates.clear()


# ---------------------------------------------------------------------
# Ortak yardımcılar
# ---------------------------------------------------------------------

func _register(zone: int, item: Dictionary) -> void:
	if not zone_sets.has(zone):
		zone_sets[zone] = []
	(zone_sets[zone] as Array).append(item)


func _dirty_copy(key: String) -> StandardMaterial3D:
	var m: StandardMaterial3D = (mats[key] as StandardMaterial3D).duplicate()
	m.albedo_color = DIRTY
	return m


## Bütün modeli yerleştir
func _model(parent: Node3D, path: String, pos: Vector3, rot_y := 0.0, scl := 1.0) -> Node3D:
	var ps: PackedScene = load(path)
	var n: Node3D = ps.instantiate()
	n.position = pos
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * scl
	parent.add_child(n)
	return n


## Çok parçalı modelden tek bir parçanın ağı (örn. kaya setinden bir kaya)
func _part_mesh(path: String, part_name: String) -> Mesh:
	if not _templates.has(path):
		var ps: PackedScene = load(path)
		_templates[path] = ps.instantiate()
	var t: Node = _templates[path]
	var src := t.find_child(part_name, true, false) as MeshInstance3D
	if src == null:
		push_warning("Model parçası bulunamadı: %s / %s" % [path, part_name])
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.1, 0.1)
		return bm
	return src.mesh


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi


func _collider(pos: Vector3, size: Vector3, rot_y := 0.0) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)


func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _shore_point(dir: Vector2) -> Vector2:
	var d := dir.normalized()
	var r := 345.0
	while r > 20.0:
		var p := d * r
		if island.height_at(p.x, p.y) > 0.3:
			return p
		r -= 1.0
	return d * 20.0


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, island.height_at(x, z), z)


## Yıkılmış hâl: devrik eşya, bölge bitince ayağa kalkar
func _fallen(zone: int, n: Node3D) -> void:
	var upright := n.rotation
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	n.rotation = Vector3(deg_to_rad(rng.randf_range(70.0, 90.0)) * side, upright.y, 0)
	n.position.y += 0.25
	_register(zone, {"kind": "node", "node": n, "rot": upright, "dy": -0.25})


# ---------------------------------------------------------------------
# İskele (bölge 1): gerçek ahşap iskele modeli; kırık bölümler onarılır
# ---------------------------------------------------------------------

func _build_pier() -> void:
	var root := Node3D.new()
	root.name = "Iskele"
	add_child(root)
	var sp: Vector3 = island.spawn_point
	var z0 := sp.z
	while island.height_at(sp.x, z0) > 0.4 and z0 < sp.z + 60.0:
		z0 += 0.5
	var z_start := z0 - 6.0
	var seg := 2.9
	var count := 12
	var width := 2.5
	var x := sp.x - 5.0
	# Modelde güverte üstü y = 2.65; genişlik x: -0.28..2.23 -> merkez 0.98
	var off := Vector3(x - 0.98, DECK_Y - 2.65, 0)
	var intact := _part_mesh(PIER, "modular_wooden_pier_section_02")
	var broken_meshes: Array[Mesh] = [_part_mesh(PIER, "modular_wooden_pier_section_01"), _part_mesh(PIER, "modular_wooden_pier_section_03")]
	for i in count:
		var pos := off + Vector3(0, 0, z_start + i * seg)
		var good := MeshInstance3D.new()
		good.mesh = intact
		good.position = pos
		root.add_child(good)
		if i > 0 and rng.randf() < 0.45:
			var bad := MeshInstance3D.new()
			bad.mesh = broken_meshes[rng.randi() % broken_meshes.size()]
			bad.position = pos
			root.add_child(bad)
			good.visible = false
			_register(1, {"kind": "swap", "show": good, "hide": bad})
	var length := seg * count
	# Yürünebilir güverte (kırık yerlerde de yürünür ki oyuncu takılmasın)
	_collider(Vector3(x, DECK_Y - 0.1, z_start + length * 0.5), Vector3(width, 0.2, length))

	# Can simidi, fenerler, sandık ve kasalar
	_model(root, LIFEBUOY, Vector3(x + width * 0.5 + 0.05, DECK_Y + 0.6, z_start + 8.0), PI * 0.5)
	for k in 2:
		_model(root, LAMP, Vector3(x - width * 0.5 + 0.2, DECK_Y, z_start + 6.0 + k * 18.0), PI * 0.5)
	var end_z := z_start + length - 2.0
	var c1 := _model(root, CRATE, Vector3(x - 0.5, DECK_Y, end_z), 0.3)
	_model(root, PCRATE, Vector3(x + 0.6, DECK_Y, end_z - 0.8), -0.4)
	_model(root, PCRATE, Vector3(x + 0.6, DECK_Y + 0.25, end_z - 0.75), 0.2)
	_fallen(1, c1)


# ---------------------------------------------------------------------
# Sahil (bölge 2): devrik şemsiyeler, sandalyeler, banklar, piknik masaları,
# kıyıya vurmuş kütükler, açıkta şamandıralar
# ---------------------------------------------------------------------

func _beach_spot(min_back: float, max_back: float) -> Variant:
	for t in 200:
		var a := rng.randf_range(-0.75, 0.75)
		var dir := Vector2(sin(a), cos(a))
		var shore := _shore_point(dir)
		var p := shore - dir * rng.randf_range(min_back, max_back)
		var h: float = island.height_at(p.x, p.y)
		if h < 0.4 or h > 2.0 or island.zone_at(p.x, p.y) != 2:
			continue
		return Vector3(p.x, h, p.y)
	return null


func _build_beach() -> void:
	var root := Node3D.new()
	root.name = "Sahil"
	add_child(root)
	var colors := [Color(0.85, 0.2, 0.15), Color(0.1, 0.45, 0.8), Color(0.95, 0.75, 0.15), Color(0.15, 0.6, 0.45)]
	for i in 10:
		var sp: Variant = _beach_spot(4.0, 12.0)
		if sp == null:
			continue
		var p: Vector3 = sp
		var col: Color = colors[i % colors.size()]
		var faded := StandardMaterial3D.new()
		faded.albedo_color = col.lerp(Color(0.55, 0.52, 0.48), 0.7)
		faded.roughness = 0.9
		faded.cull_mode = BaseMaterial3D.CULL_DISABLED
		var umb := Node3D.new()
		umb.position = p
		root.add_child(umb)
		_cylinder(umb, Vector3(0, 1.1, 0), 0.03, 2.2, mats["metal"])
		var canopy := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 1.4
		cm.height = 0.45
		cm.radial_segments = 8
		cm.cap_bottom = false
		canopy.mesh = cm
		canopy.material_override = faded
		canopy.position = Vector3(0, 2.15, 0)
		umb.add_child(canopy)
		var upright := Vector3(deg_to_rad(rng.randf_range(-4.0, 4.0)), rng.randf_range(0.0, TAU), 0)
		umb.rotation = Vector3(deg_to_rad(rng.randf_range(65.0, 80.0)), upright.y, 0)
		_register(2, {"kind": "node", "node": umb, "rot": upright})
		_register(2, {"kind": "color", "mat": faded, "color": col})
		# Yanında iki plastik sandalye
		for k in 2:
			var ch := _model(root, CHAIR, _ground(p.x + 1.3 + k * 0.8, p.z + 0.6), rng.randf_range(0.0, TAU))
			_fallen(2, ch)
	# Banklar ve piknik masaları, sahilin biraz gerisinde
	for i in 6:
		var sp2: Variant = _beach_spot(10.0, 22.0)
		if sp2 == null:
			continue
		var p2: Vector3 = sp2
		var is_bench := i % 2 == 0
		var n := _model(root, BENCH if is_bench else PICNIC, p2, rng.randf_range(0.0, TAU))
		var rot := n.rotation.y
		_fallen(2, n)
		_collider(p2 + Vector3(0, 0.4, 0), Vector3(1.2, 0.8, 0.5) if is_bench else Vector3(2.2, 0.8, 3.0), rot)
	# Kıyıya vurmuş kütükler: bölge bitince kaybolur
	for i in 8:
		var sp3: Variant = _beach_spot(1.0, 6.0)
		if sp3 == null:
			continue
		var p3: Vector3 = sp3
		var lg := _model(root, LOG, p3 + Vector3(0, 0.05, 0), rng.randf_range(0.0, TAU), rng.randf_range(0.8, 1.3))
		_register(2, {"kind": "vanish", "node": lg})
	# Açıkta şamandıralar, hafifçe inip kalkar
	for i in 4:
		var a := rng.randf_range(-0.6, 0.6)
		var dir := Vector2(sin(a), cos(a))
		var s := _shore_point(dir) + dir * rng.randf_range(25.0, 45.0)
		var b := _model(root, BUOY, Vector3(s.x, -0.3, s.y), rng.randf_range(0.0, TAU))
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "position:y", 0.0, 2.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "position:y", -0.3, 2.2).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------------
# Liman (bölge 3): batı kıyısında beton rıhtım, kasalar, fıçılar, lambalar
# ---------------------------------------------------------------------

func _build_harbor() -> void:
	var root := Node3D.new()
	root.name = "Liman"
	add_child(root)
	var shore := _shore_point(Vector2(-1.0, 0.05))
	var concrete := _dirty_copy("concrete")
	var top := 1.7
	var length := 46.0
	var cx := shore.x - 4.0
	var cz := shore.y
	var depth := top + 6.0
	_box(root, Vector3(cx, top - depth * 0.5, cz), Vector3(9.0, depth, length), concrete)
	_collider(Vector3(cx, top - 0.5, cz), Vector3(9.0, 1.0, length))
	# Rampa
	var ramp_h: float = maxf(island.height_at(cx + 7.0, cz), 0.5)
	var ramp_len := 8.0
	var ang := atan2(top - ramp_h, ramp_len)
	var ramp := _box(root, Vector3(cx + 4.5 + ramp_len * 0.5, (top + ramp_h) * 0.5 - 0.15, cz), Vector3(ramp_len / cos(ang), 0.3, 6.0), concrete)
	ramp.rotation.z = ang
	var rb := StaticBody3D.new()
	rb.position = ramp.position
	rb.rotation.z = ang
	var rcs := CollisionShape3D.new()
	var rbs := BoxShape3D.new()
	rbs.size = Vector3(ramp_len / cos(ang), 0.3, 6.0)
	rcs.shape = rbs
	rb.add_child(rcs)
	add_child(rb)
	# Babalar ve lambalar
	var zz := cz - length * 0.5 + 3.0
	var k := 0
	while zz < cz + length * 0.5:
		_cylinder(root, Vector3(cx - 4.0, top + 0.3, zz), 0.18, 0.6, mats["metal"])
		if k % 2 == 0:
			_model(root, LAMP, Vector3(cx + 3.8, top, zz + 1.5), 0.0)
		zz += 7.0
		k += 1
	# Can simitleri rıhtım kenarında
	for j in 2:
		_model(root, LIFEBUOY, Vector3(cx - 4.55, top - 0.6, cz - 8.0 + j * 16.0), -PI * 0.5)
	# Kasa ve fıçı yığınları: başta dağınık/devrik, bölge bitince düzelir
	for j in 7:
		var bx := cx + rng.randf_range(-2.0, 3.0)
		var bz := cz + rng.randf_range(-length * 0.45, length * 0.45)
		var r := rng.randf_range(0.0, TAU)
		match j % 3:
			0:
				var c := _model(root, CRATE, Vector3(bx, top, bz), r)
				_fallen(3, c)
				_collider(Vector3(bx, top + 0.2, bz), Vector3(0.85, 0.4, 0.45), r)
			1:
				for s in 3:
					var pc := _model(root, PCRATE, Vector3(bx, top + s * 0.25, bz), r + rng.randf_range(-0.2, 0.2))
					if s == 2:
						_fallen(3, pc)
				_collider(Vector3(bx, top + 0.38, bz), Vector3(0.55, 0.75, 0.45), r)
			2:
				_model(root, BARRELS, Vector3(bx, top, bz), r, 0.8)
				_collider(Vector3(bx, top + 0.4, bz), Vector3(3.0, 0.8, 2.0), r)
	_register(3, {"kind": "material", "mat": concrete})


# ---------------------------------------------------------------------
# Doğa: yosunlu kayalar, büyük kayalar (kıyı ve fener tepesi), çalılar, kütükler.
# MultiMesh ile toplu çizilir; uzaktakiler gizlenir.
# ---------------------------------------------------------------------

func _scatter(mesh: Mesh, count: int, smin: float, smax: float, ok: Callable, vis_end: float, col_size: Vector3) -> void:
	var xs: Array[Transform3D] = []
	var tries := 0
	while xs.size() < count and tries < count * 60:
		tries += 1
		var x := rng.randf_range(-300.0, 300.0)
		var z := rng.randf_range(-300.0, 300.0)
		var h: float = island.height_at(x, z)
		if not ok.call(x, z, h):
			continue
		if Vector2(x - island.spawn_point.x, z - island.spawn_point.z).length() < 12.0:
			continue
		var s := rng.randf_range(smin, smax)
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s))
		xs.append(Transform3D(b, Vector3(x, h - 0.02 * s, z)))
		if col_size != Vector3.ZERO:
			_collider(Vector3(x, h + col_size.y * s * 0.5, z), col_size * s * 0.8)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = vis_end
	mmi.visibility_range_end_margin = 10.0
	add_child(mmi)


func _build_nature() -> void:
	# Yosunlu kayalar: iç kesimler
	var inland := func(_x: float, _z: float, h: float) -> bool: return h > 2.2
	for i in 6:
		_scatter(_part_mesh(ROCKS, "rock_moss_set_01_rock0%d" % (i + 1)), 14, 0.6, 1.4, inland, 220.0, Vector3(1.8, 1.0, 1.8))
	# Büyük kayalar: kıyı şeridi ve fener tepesi
	var coast_or_hill := func(x: float, z: float, h: float) -> bool:
		return (h > 0.2 and h < 1.0) or (h > 6.0 and Vector2(x, z).distance_to(Vector2(150, -150)) < 110.0)
	_scatter(_part_mesh(ROCK07, "rock_07"), 30, 9.0, 16.0, coast_or_hill, 300.0, Vector3(0.15, 0.13, 0.28))
	_scatter(_part_mesh(ROCK09, "rock_09_LOD0"), 30, 18.0, 30.0, coast_or_hill, 300.0, Vector3(0.08, 0.03, 0.14))
	# Çalılar: iç kesimler
	var bushy := func(_x: float, _z: float, h: float) -> bool: return h > 1.8
	for n in ["a", "b", "c", "d"]:
		_scatter(_part_mesh(SHRUB, "shrub_03_" + n), 90, 2.5, 4.5, bushy, 90.0, Vector3.ZERO)
	# Devrik ağaç gövdeleri: kuzey (orman) tarafı
	var foresty := func(_x: float, z: float, h: float) -> bool: return h > 2.0 and z < 0.0
	_scatter(_part_mesh(LOG, "dead_tree_trunk"), 40, 0.9, 1.6, foresty, 160.0, Vector3.ZERO)


# ---------------------------------------------------------------------
# Yenileme
# ---------------------------------------------------------------------

## Bölge tamamlanınca yapıları yenile. instant: kayıttan yüklerken animasyonsuz.
func restore(zone: int, instant: bool) -> void:
	if not zone_sets.has(zone):
		return
	for item: Dictionary in zone_sets[zone]:
		match str(item["kind"]):
			"material":
				var m: StandardMaterial3D = item["mat"]
				if instant:
					m.albedo_color = Color.WHITE
				else:
					create_tween().tween_property(m, "albedo_color", Color.WHITE, 2.5)
			"color":
				var m2: StandardMaterial3D = item["mat"]
				var c: Color = item["color"]
				if instant:
					m2.albedo_color = c
				else:
					create_tween().tween_property(m2, "albedo_color", c, 2.5)
			"node":
				var n: Node3D = item["node"]
				var r: Vector3 = item["rot"]
				var dy: float = item.get("dy", 0.0)
				if instant:
					n.rotation = r
					n.position.y += dy
				else:
					var tw := create_tween()
					tw.tween_interval(rng.randf_range(0.0, 1.2))
					tw.tween_property(n, "rotation", r, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					tw.parallel().tween_property(n, "position:y", n.position.y + dy, 0.9)
			"swap":
				var show_n: Node3D = item["show"]
				var hide_n: Node3D = item["hide"]
				if instant:
					show_n.visible = true
					hide_n.visible = false
				else:
					var tw2 := create_tween()
					tw2.tween_interval(rng.randf_range(0.2, 1.5))
					tw2.tween_callback(show_n.show)
					tw2.tween_callback(hide_n.hide)
			"vanish":
				var v: Node3D = item["node"]
				if instant:
					v.visible = false
				else:
					var tw3 := create_tween()
					tw3.tween_interval(rng.randf_range(0.0, 1.0))
					tw3.tween_property(v, "scale", Vector3.ZERO, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
					tw3.tween_callback(v.hide)
