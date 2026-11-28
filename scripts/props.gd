extends Node3D
## Bölgelerin yapıları ve doğa: iskele, sahil eşyaları, liman rıhtımı, kayalar, çalılar.
## Modeller Poly Haven'dan (CC0). Her bölgenin yapıları önce yıpranmış görünür;
## bölge tamamlanınca "yenilenmiş" hâline geçer.

var island = null            # island.gd
var mats := {}               # "wood", "concrete", "metal"
var zone_sets := {}          # bölge -> Array[Dictionary] (yenilenecek parçalar)
var rng := RandomNumberGenerator.new()
var _templates := {}         # model yolu -> örnek sahne (parça kopyalamak için)
var pier_end := Vector3.ZERO # iskelenin deniz ucu (feribot buraya yanaşır)
var bobbers: Array = []      # [düğüm, taban y, faz] — onarılınca denizde salınan tekneler
var beam_pivot: Node3D = null
var lighthouse_on := false
var lamp_light: OmniLight3D = null
var glass_mat: StandardMaterial3D = null
var fountain_fx: CPUParticles3D = null
var ferry: Node3D = null
var ferry_t := -1.0          # <0: bekliyor; 0..1 yanaşıyor
var ferry_from := Vector3.ZERO
var ferry_to := Vector3.ZERO
var time := 0.0
var _last_rim: Array = []
signal ferry_arrived

const Isl := preload("res://scripts/island.gd")
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
	_build_boats()
	_build_village()
	_build_fields()
	_build_forest()
	_build_lighthouse()
	_build_ferry()
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
	pier_end = Vector3(x, DECK_Y, z_start + length)
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
			"appear":
				var ap: Node3D = item["node"]
				var full: Vector3 = item["scale"]
				ap.visible = true
				if instant:
					ap.scale = full
				else:
					ap.scale = Vector3.ONE * 0.01
					var tw4 := create_tween()
					tw4.tween_interval(rng.randf_range(0.2, 1.6))
					tw4.tween_property(ap, "scale", full, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			"boat":
				var bt: Node3D = item["node"]
				var up: Vector3 = item["rot"]
				var by: float = item["y"]
				if instant:
					bt.rotation = up
					bt.position.y = by
				else:
					var tw5 := create_tween()
					tw5.tween_interval(rng.randf_range(0.0, 1.5))
					tw5.tween_property(bt, "rotation", up, 2.0).set_trans(Tween.TRANS_SINE)
					tw5.parallel().tween_property(bt, "position:y", by, 2.0).set_trans(Tween.TRANS_SINE)
				bobbers.append([bt, by, rng.randf_range(0.0, TAU)])
			"fountain":
				fountain_fx.emitting = true
			"lighthouse":
				_light_lighthouse(instant)
			"vanish":
				var v: Node3D = item["node"]
				if instant:
					v.visible = false
				else:
					var tw3 := create_tween()
					tw3.tween_interval(rng.randf_range(0.0, 1.0))
					tw3.tween_property(v, "scale", Vector3.ZERO, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
					tw3.tween_callback(v.hide)



# ---------------------------------------------------------------------
# Kare güncellemesi: tekne salınımı, fener ışığı, feribot
# ---------------------------------------------------------------------

func _process(delta: float) -> void:
	time += delta
	for b: Array in bobbers:
		var n: Node3D = b[0]
		n.position.y = float(b[1]) + sin(time * 0.9 + float(b[2])) * 0.08
		n.rotation.z = sin(time * 0.7 + float(b[2]) * 1.7) * 0.03
	if lighthouse_on and beam_pivot != null:
		beam_pivot.rotation.y += delta * 0.9
	if ferry_t >= 0.0 and ferry_t < 1.0:
		ferry_t = minf(ferry_t + delta / 70.0, 1.0)
		var e := 1.0 - pow(1.0 - ferry_t, 3.0)    # yavaşlayarak yanaş
		ferry.position = ferry_from.lerp(ferry_to, e)
		ferry.position.y = sin(time * 0.6) * 0.12
		if ferry_t >= 1.0:
			ferry_arrived.emit()
	elif ferry != null and ferry.visible:
		ferry.position.y = sin(time * 0.6) * 0.12
		ferry.rotation.z = sin(time * 0.45) * 0.012


# ---------------------------------------------------------------------
# Tekne gövdesi: kesitlerden örülmüş yumuşak gövde (SurfaceTool)
# ---------------------------------------------------------------------

func _hull_mesh(length: float, beam: float, depth: float, flat_stern := 0.85) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 22
	var nv := 12
	var rows: Array = []
	for i in nu + 1:
		var u := float(i) / nu                      # 0 = kıç, 1 = pruva
		var w := beam * 0.5 * sqrt(maxf(0.0, 1.0 - pow(u, 3.0))) * (flat_stern + (1.0 - flat_stern) * sin(PI * u))
		var top := depth * (1.0 + 0.28 * u * u)
		var keel := depth * 0.55 * pow(u, 3.0)
		var row: Array = []
		for j in nv + 1:
			var t := PI * float(j) / nv
			var sx := cos(t)
			var sy := pow(sin(t), 0.75)
			var x := w * sx * (1.0 - 0.18 * sy * sy)
			var y := top - (top - keel) * sy
			row.append(Vector3(x, y, (u - 0.5) * length))
		rows.append(row)
	for i in nu:
		for j in nv:
			var a: Vector3 = rows[i][j]
			var b: Vector3 = rows[i + 1][j]
			var c: Vector3 = rows[i + 1][j + 1]
			var d: Vector3 = rows[i][j + 1]
			var ua := Vector2(float(j) / nv, float(i) / nu)
			var ub := Vector2(float(j) / nv, float(i + 1) / nu)
			var uc := Vector2(float(j + 1) / nv, float(i + 1) / nu)
			var ud := Vector2(float(j + 1) / nv, float(i) / nu)
			st.set_uv(ua); st.add_vertex(a)
			st.set_uv(ub); st.add_vertex(b)
			st.set_uv(uc); st.add_vertex(c)
			st.set_uv(ua); st.add_vertex(a)
			st.set_uv(uc); st.add_vertex(c)
			st.set_uv(ud); st.add_vertex(d)
	# Kıç aynası (düz kapak)
	var r0: Array = rows[0]
	var center := Vector3(0, depth * 0.55, r0[0].z)
	for j in nv:
		st.set_uv(Vector2(0.5, 0.0)); st.add_vertex(center)
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(r0[j + 1])
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(r0[j])
	st.generate_normals()
	_last_rim = [rows.map(func(r: Array) -> Vector3: return r[0]), rows.map(func(r: Array) -> Vector3: return r[nv])]
	return st.commit()


## Küpeşte: gövdenin üst kenarı boyunca ince şeritler (iki yan)
func _rim(parent: Node3D, mat: Material, thick: float, height: float) -> void:
	for side: Array in _last_rim:
		for i in side.size() - 1:
			var a: Vector3 = side[i]
			var b: Vector3 = side[i + 1]
			var mid := (a + b) * 0.5
			var seg := b - a
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(thick, height, seg.length() + 0.02)
			mi.mesh = bm
			mi.material_override = mat
			mi.transform = Transform3D(Basis.looking_at(seg.normalized(), Vector3.UP), mid + Vector3(0, -height * 0.4, 0))
			parent.add_child(mi)


func _paint(col: Color, rough := 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Küçük ahşap balıkçı teknesi: boyalı gövde, ahşap oturaklar, kenar şeridi
func _boat(parent: Node3D, length: float, col: Color) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var hull := MeshInstance3D.new()
	hull.mesh = _hull_mesh(length, length * 0.36, length * 0.17)
	var paint := _paint(col)
	hull.material_override = paint
	root.add_child(hull)
	var wood: Material = mats["wood"]
	var d := length * 0.17
	for k in 3:
		var z := (-0.3 + k * 0.28) * length
		var u := clampf(z / length + 0.5, 0.0, 1.0)
		var w := length * 0.36 * sqrt(maxf(0.0, 1.0 - pow(u, 3.0))) * (0.85 + 0.15 * sin(PI * u))
		_box(root, Vector3(0, d * 0.72, z), Vector3(w * 0.92, 0.05, 0.28), wood)
	# Küpeşte (gövde ağı en son üretilen olmalı: _last_rim)
	_rim(root, wood, 0.07, 0.09)
	# İç taban
	_box(root, Vector3(0, d * 0.28, -length * 0.08), Vector3(length * 0.36 * 0.55, 0.04, length * 0.6), wood)
	# Dıştan takma motor (kıçta)
	var dark := _paint(Color(0.1, 0.1, 0.11), 0.4)
	var motor := Node3D.new()
	motor.position = Vector3(0, d * 1.0, -length * 0.5 - 0.12)
	root.add_child(motor)
	_box(motor, Vector3(0, 0.2, 0), Vector3(0.32, 0.38, 0.42), dark)
	_box(motor, Vector3(0, -0.25, 0.02), Vector3(0.08, 0.6, 0.12), dark)
	_box(motor, Vector3(0, 0.05, 0.3), Vector3(0.04, 0.04, 0.4), _paint(Color(0.6, 0.6, 0.62), 0.3))
	_register(3, {"kind": "color", "mat": paint, "color": col})
	paint.albedo_color = col.lerp(Color(0.33, 0.30, 0.25), 0.75)
	return root


func _build_boats() -> void:
	var harbor := get_node_or_null("Liman") as Node3D
	if harbor == null:
		return
	var shore := _shore_point(Vector2(-1.0, 0.05))
	var cx := shore.x - 4.0
	var cols := [Color(0.1, 0.32, 0.6), Color(0.85, 0.82, 0.75), Color(0.72, 0.16, 0.12), Color(0.12, 0.45, 0.38), Color(0.92, 0.7, 0.2)]
	for i in 5:
		var L := rng.randf_range(5.0, 7.5)
		var b := _boat(harbor, L, cols[i])
		var z := shore.y - 18.0 + i * 9.0
		var up := Vector3(0, rng.randf_range(-0.08, 0.08), 0)
		b.position = Vector3(cx - 4.5 - L * 0.22 - 1.0, -0.55, z)
		b.rotation = Vector3(deg_to_rad(rng.randf_range(-6.0, 6.0)), up.y, deg_to_rad(rng.randf_range(18.0, 32.0)) * (1.0 if i % 2 == 0 else -1.0))
		_register(3, {"kind": "boat", "node": b, "rot": up, "y": -L * 0.06})
		# Halat: tekneden babaya
		var rope := _cylinder(harbor, Vector3(cx - 4.3 - L * 0.11, 1.2, z), 0.025, L * 0.25 + 1.2, _paint(Color(0.55, 0.48, 0.35), 0.9))
		rope.rotation.z = PI * 0.5 - 0.35


# ---------------------------------------------------------------------
# Köy meydanı (bölge 4): çeşme, banklar, kahve masaları, lambalar
# ---------------------------------------------------------------------

func _build_village() -> void:
	var root := Node3D.new()
	root.name = "Koy"
	add_child(root)
	var c2: Vector2 = Isl.PLAZA_CENTER
	var g := _ground(c2.x, c2.y)
	# Çeşme: taş havuz, su yüzeyi, orta sütun, üst çanak
	var stone := _dirty_copy("concrete")
	_cylinder(root, g + Vector3(0, 0.35, 0), 3.2, 0.7, stone)
	_collider(g + Vector3(0, 0.35, 0), Vector3(5.6, 0.7, 5.6))
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.25, 0.22, 0.14)
	water.roughness = 0.05
	water.metallic = 0.3
	_cylinder(root, g + Vector3(0, 0.62, 0), 2.95, 0.06, water)
	_cylinder(root, g + Vector3(0, 1.3, 0), 0.32, 1.6, stone)
	_cylinder(root, g + Vector3(0, 2.15, 0), 1.0, 0.22, stone)
	_register(4, {"kind": "material", "mat": stone})
	_register(4, {"kind": "color", "mat": water, "color": Color(0.18, 0.42, 0.52)})
	fountain_fx = CPUParticles3D.new()
	fountain_fx.position = g + Vector3(0, 2.3, 0)
	fountain_fx.amount = 160
	fountain_fx.lifetime = 1.1
	fountain_fx.direction = Vector3.UP
	fountain_fx.spread = 18.0
	fountain_fx.initial_velocity_min = 3.0
	fountain_fx.initial_velocity_max = 3.6
	fountain_fx.gravity = Vector3(0, -9.0, 0)
	fountain_fx.scale_amount_min = 0.05
	fountain_fx.scale_amount_max = 0.09
	var drop := SphereMesh.new()
	drop.radius = 0.5
	drop.height = 1.0
	drop.radial_segments = 6
	drop.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.8, 0.92, 1.0, 0.55)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.roughness = 0.05
	drop.material = dm
	fountain_fx.mesh = drop
	fountain_fx.emitting = false
	root.add_child(fountain_fx)
	_register(4, {"kind": "fountain"})
	# Meydan çevresi: banklar, masalar, sandalyeler, lambalar (patikaların üstüne değil)
	var placed := 0
	var a := 0.3
	while placed < 14 and a < TAU + 0.3:
		var r := 15.0 if placed % 2 == 0 else 20.0
		var x := c2.x + sin(a) * r
		var z := c2.y + cos(a) * r
		a += 0.43
		if island.path_distance(x, z) < 4.5 and Vector2(x, z).distance_to(c2) > Isl.PLAZA_RADIUS - 1.0:
			continue
		var p := _ground(x, z)
		var face := atan2(c2.x - x, c2.y - z)
		match placed % 4:
			0:
				var bn := _model(root, BENCH, p, face)
				_fallen(4, bn)
				_collider(p + Vector3(0, 0.4, 0), Vector3(1.2, 0.8, 0.5), face)
			1:
				var t := _model(root, PICNIC, p, face + PI * 0.5)
				_fallen(4, t)
				_collider(p + Vector3(0, 0.4, 0), Vector3(2.2, 0.8, 3.0), face + PI * 0.5)
			2:
				for k in 3:
					var ch := _model(root, CHAIR, _ground(x + cos(k * 2.1) * 1.1, z + sin(k * 2.1) * 1.1), rng.randf_range(0.0, TAU))
					_fallen(4, ch)
			3:
				var lp := _model(root, LAMP, p, face)
				_fallen(4, lp)
		placed += 1


# ---------------------------------------------------------------------
# Tarlalar (bölge 5): devrik çitler, saman balyaları (bölge bitince dizilir)
# ---------------------------------------------------------------------

func _zone_spot(zone: int, min_h: float, path_clear: float) -> Variant:
	for t in 3000:
		var x := rng.randf_range(-300.0, 300.0)
		var z := rng.randf_range(-300.0, 300.0)
		var h: float = island.height_at(x, z)
		if h < min_h or island.zone_at(x, z) != zone:
			continue
		if island.path_distance(x, z) < path_clear:
			continue
		return Vector3(x, h, z)
	return null


func _build_fields() -> void:
	var root := Node3D.new()
	root.name = "Tarlalar"
	add_child(root)
	var wood: Material = mats["wood"]
	for i in 10:
		var sp: Variant = _zone_spot(5, 1.8, 6.0)
		if sp == null:
			continue
		var p: Vector3 = sp
		var ang := rng.randf_range(0.0, PI)
		var fence := Node3D.new()
		fence.position = p
		fence.rotation.y = ang
		root.add_child(fence)
		var n := 6
		for k in n + 1:
			var px := (k - n * 0.5) * 2.0
			var gh: float = island.height_at(p.x + cos(ang) * px, p.z - sin(ang) * px) - p.y
			_box(fence, Vector3(px, gh + 0.55, 0), Vector3(0.12, 1.2, 0.12), wood)
			if k < n:
				_box(fence, Vector3(px + 1.0, gh + 0.85, 0), Vector3(2.05, 0.1, 0.05), wood)
				_box(fence, Vector3(px + 1.0, gh + 0.45, 0), Vector3(2.05, 0.1, 0.05), wood)
		var up := fence.rotation
		fence.rotation = Vector3(deg_to_rad(rng.randf_range(55.0, 80.0)) * (1.0 if i % 2 == 0 else -1.0), ang, 0)
		_register(5, {"kind": "node", "node": fence, "rot": up})
	# Saman balyaları: başta çürümüş dağınık balyalar, sonra yeni balyalar
	var old := _paint(Color(0.32, 0.28, 0.2), 1.0)
	var fresh := _paint(Color(0.84, 0.7, 0.38), 1.0)
	for i in 8:
		var sp2: Variant = _zone_spot(5, 1.8, 5.0)
		if sp2 == null:
			continue
		var p2: Vector3 = sp2
		var rot := rng.randf_range(0.0, TAU)
		var rotten := _cylinder(root, p2 + Vector3(0, 0.45, 0), 0.75, 1.1, old)
		rotten.rotation = Vector3(PI * 0.5, rot, 0)
		rotten.scale = Vector3(1.0, 1.0, 0.6)
		_register(5, {"kind": "vanish", "node": rotten})
		for k in 3:
			var bale := _cylinder(root, p2 + Vector3(cos(rot) * k * 1.3, 0.75, sin(rot) * k * 1.3), 0.75, 1.2, fresh)
			bale.rotation = Vector3(PI * 0.5, rot + PI * 0.5, 0)
			bale.visible = false
			_register(5, {"kind": "appear", "node": bale, "scale": Vector3.ONE})


# ---------------------------------------------------------------------
# Orman (bölge 6): patikaya devrilmiş ağaçlar kalkar, yön tabelası dikilir
# ---------------------------------------------------------------------

func _path_dir(x: float, z: float) -> float:
	# Patika yönü: uzaklık alanının eğimine dik
	var e := 0.5
	var gx: float = island.path_distance(x + e, z) - island.path_distance(x - e, z)
	var gz: float = island.path_distance(x, z + e) - island.path_distance(x, z - e)
	return atan2(gx, gz)


func _build_forest() -> void:
	var root := Node3D.new()
	root.name = "Orman"
	add_child(root)
	var n := 0
	for t in 6000:
		if n >= 6:
			break
		var x := rng.randf_range(-300.0, 300.0)
		var z := rng.randf_range(-300.0, 0.0)
		var h: float = island.height_at(x, z)
		if h < 1.8 or island.zone_at(x, z) != 6 or island.path_distance(x, z) > 1.2:
			continue
		var lg := _model(root, LOG, Vector3(x, h + 0.1, z), _path_dir(x, z), rng.randf_range(1.1, 1.5))
		_register(6, {"kind": "vanish", "node": lg})
		n += 1
	# Yön tabelası: patika üstünde, ormanın içinde
	for t in 4000:
		var x := rng.randf_range(-300.0, 300.0)
		var z := rng.randf_range(-300.0, 0.0)
		var h: float = island.height_at(x, z)
		if h < 1.8 or island.zone_at(x, z) != 6:
			continue
		var pd: float = island.path_distance(x, z)
		if pd < 2.6 or pd > 3.4:
			continue
		var sign_n := Node3D.new()
		sign_n.position = Vector3(x, h, z)
		root.add_child(sign_n)
		var wood: Material = mats["wood"]
		_box(sign_n, Vector3(0, 1.2, 0), Vector3(0.14, 2.4, 0.14), wood)
		var to_l := atan2(Isl.LIGHTHOUSE.x - x, Isl.LIGHTHOUSE.y - z)
		var arm := _box(sign_n, Vector3(0, 2.0, 0), Vector3(1.6, 0.32, 0.05), _paint(Color(0.85, 0.82, 0.72), 0.8))
		arm.rotation.y = to_l + PI * 0.5
		arm.position = Vector3(sin(to_l) * 0.7, 2.0, cos(to_l) * 0.7)
		var lbl := Label3D.new()
		lbl.text = "FENER →"
		lbl.font_size = 64
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.15, 0.15, 0.15)
		lbl.outline_size = 0
		lbl.double_sided = true
		lbl.position = Vector3(0, 0, 0.03)
		arm.add_child(lbl)
		sign_n.visible = false
		_register(6, {"kind": "appear", "node": sign_n, "scale": Vector3.ONE})
		break


# ---------------------------------------------------------------------
# Fener (bölge 7): tepede beyaz-kırmızı kule; bölge bitince yanar, ışık döner
# ---------------------------------------------------------------------

func _tapered(parent: Node3D, pos: Vector3, r_bottom: float, r_top: float, height: float, mat: Material, segs := 32) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bottom
	cm.top_radius = r_top
	cm.height = height
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_lighthouse() -> void:
	var lh: Vector2 = Isl.LIGHTHOUSE
	# Tepenin en yüksek yakın noktasını bul
	var best := Vector3(lh.x, island.height_at(lh.x, lh.y), lh.y)
	for t in 60:
		var q := lh + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
		var hq: float = island.height_at(q.x, q.y)
		if hq > best.y:
			best = Vector3(q.x, hq, q.y)
	var root := Node3D.new()
	root.name = "Fener"
	root.position = best - Vector3(0, 0.4, 0)
	add_child(root)
	var dir := "res://assets/textures/"
	var white := StandardMaterial3D.new()
	white.albedo_texture = load(dir + "beige_wall_001_diff.jpg")
	white.normal_enabled = true
	white.normal_texture = load(dir + "beige_wall_001_nor.jpg")
	white.roughness_texture = load(dir + "beige_wall_001_rough.png")
	white.uv1_triplanar = true
	white.uv1_scale = Vector3.ONE * 0.5
	var red := white.duplicate() as StandardMaterial3D
	white.albedo_color = Color(1.0, 1.0, 0.98)
	red.albedo_color = Color(0.78, 0.14, 0.1)
	var brick := StandardMaterial3D.new()
	brick.albedo_texture = load(dir + "red_bricks_04_diff.jpg")
	brick.normal_enabled = true
	brick.normal_texture = load(dir + "red_bricks_04_nor.jpg")
	brick.uv1_triplanar = true
	brick.uv1_scale = Vector3.ONE * 0.6
	# Kaide
	_tapered(root, Vector3(0, 1.2, 0), 4.6, 4.4, 2.4, brick, 8)
	# Gövde: 5 bant, yukarı doğru incelir
	var h0 := 2.4
	var H := 20.0
	for k in 5:
		var y0 := h0 + H * k / 5.0
		var rb := lerpf(3.4, 2.3, float(k) / 5.0)
		var rt := lerpf(3.4, 2.3, float(k + 1) / 5.0)
		_tapered(root, Vector3(0, y0 + H / 10.0, 0), rb, rt, H / 5.0 + 0.01, white if k % 2 == 0 else red)
	# Balkon ve korkuluk
	var metal: Material = mats["metal"]
	var top := h0 + H
	_tapered(root, Vector3(0, top + 0.15, 0), 3.3, 3.3, 0.3, metal, 24)
	var rail := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.1
	tm.outer_radius = 3.2
	tm.rings = 48
	rail.mesh = tm
	rail.material_override = metal
	rail.position = Vector3(0, top + 1.2, 0)
	root.add_child(rail)
	for k in 16:
		var a := TAU * k / 16.0
		_box(root, Vector3(cos(a) * 3.15, top + 0.7, sin(a) * 3.15), Vector3(0.06, 1.0, 0.06), metal)
	# Fener odası: cam, çerçeve, kubbe
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.25, 0.28, 0.27, 0.55)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.08
	glass_mat.metallic = 0.4
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(1.0, 0.85, 0.55)
	glass_mat.emission_energy_multiplier = 0.0
	_tapered(root, Vector3(0, top + 1.6, 0), 1.7, 1.7, 2.6, glass_mat, 16)
	for k in 8:
		var a := TAU * k / 8.0
		_box(root, Vector3(cos(a) * 1.72, top + 1.6, sin(a) * 1.72), Vector3(0.08, 2.6, 0.08), metal)
	_tapered(root, Vector3(0, top + 3.6, 0), 1.9, 0.12, 1.5, red, 24)
	_cylinder(root, Vector3(0, top + 4.6, 0), 0.05, 0.9, metal)
	# Kapı
	_box(root, Vector3(0, 3.4, 3.38), Vector3(1.3, 2.2, 0.12), mats["wood"])
	_collider(Vector3(best.x, best.y + 6.0, best.z), Vector3(6.6, 13.0, 6.6))
	# Işık: lamba + dönen iki huzme
	lamp_light = OmniLight3D.new()
	lamp_light.position = Vector3(0, top + 1.6, 0)
	lamp_light.light_color = Color(1.0, 0.85, 0.6)
	lamp_light.light_energy = 0.0
	lamp_light.omni_range = 40.0
	root.add_child(lamp_light)
	beam_pivot = Node3D.new()
	beam_pivot.position = Vector3(0, top + 1.6, 0)
	beam_pivot.visible = false
	root.add_child(beam_pivot)
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = load("res://shaders/beam.gdshader")
	for side in [1.0, -1.0]:
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.6
		cm.bottom_radius = 14.0
		cm.height = 220.0
		cm.radial_segments = 24
		cm.cap_top = false
		cm.cap_bottom = false
		beam.mesh = cm
		beam.material_override = beam_mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.rotation.z = PI * 0.5 * side
		beam.position = Vector3(110.0 * side, 0.0, 0)
		beam_pivot.add_child(beam)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.9, 0.7)
	spot.light_energy = 6.0
	spot.spot_range = 160.0
	spot.spot_angle = 6.0
	spot.rotation = Vector3(-0.06, PI * 0.5, 0)
	beam_pivot.add_child(spot)
	_register(7, {"kind": "material", "mat": white})
	_register(7, {"kind": "color", "mat": red, "color": red.albedo_color})
	white.albedo_color = DIRTY
	red.albedo_color = Color(0.36, 0.2, 0.16)
	_register(7, {"kind": "lighthouse"})


func _light_lighthouse(instant: bool) -> void:
	lighthouse_on = true
	beam_pivot.visible = true
	if instant:
		lamp_light.light_energy = 4.0
		glass_mat.emission_energy_multiplier = 3.0
		ferry.visible = true
		ferry.position = ferry_to
		ferry_t = 1.0
		return
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(lamp_light, "light_energy", 4.0, 2.0)
	tw.parallel().tween_property(glass_mat, "emission_energy_multiplier", 3.0, 2.0)
	tw.tween_callback(func() -> void:
		ferry.visible = true
		ferry.position = ferry_from
		ferry_t = 0.0)


# ---------------------------------------------------------------------
# Feribot: fener yanınca açıktan gelip iskelenin yanına yanaşır
# ---------------------------------------------------------------------

func _build_ferry() -> void:
	ferry = Node3D.new()
	ferry.name = "Feribot"
	add_child(ferry)
	var hull := MeshInstance3D.new()
	hull.mesh = _hull_mesh(26.0, 8.0, 3.2, 0.95)
	hull.material_override = _paint(Color(0.92, 0.93, 0.92), 0.4)
	hull.position.y = -1.6
	ferry.add_child(hull)
	var band := Node3D.new()
	band.position.y = -1.6
	ferry.add_child(band)
	_rim(band, _paint(Color(0.1, 0.25, 0.5), 0.4), 0.12, 0.7)
	var deck := _paint(Color(0.55, 0.5, 0.45), 0.8)
	_box(ferry, Vector3(0, 1.75, -1.5), Vector3(7.0, 0.15, 20.0), deck)
	var cabin := _paint(Color(0.95, 0.95, 0.94), 0.35)
	_box(ferry, Vector3(0, 3.1, -2.5), Vector3(6.0, 2.6, 11.0), cabin)
	_box(ferry, Vector3(0, 5.2, -1.0), Vector3(4.6, 1.6, 4.6), cabin)
	var win := _paint(Color(0.08, 0.12, 0.16), 0.1)
	win.metallic = 0.6
	for side in [-1.0, 1.0]:
		_box(ferry, Vector3(3.02 * side, 3.4, -2.5), Vector3(0.05, 0.9, 9.6), win)
	_box(ferry, Vector3(0, 5.3, 1.32), Vector3(4.0, 0.8, 0.05), win)
	var funnel := _cylinder(ferry, Vector3(0, 6.9, -3.0), 0.7, 2.2, _paint(Color(0.75, 0.15, 0.1), 0.5))
	funnel.rotation.x = -0.12
	ferry.visible = false
	# Yanaşma: iskele ucunun yanında, açıktan (güneyden) gelir
	ferry_to = Vector3(pier_end.x + 10.0, 0.0, pier_end.z - 4.0)
	ferry_from = ferry_to + Vector3(60.0, 0.0, 380.0)
	ferry.position = ferry_from
	ferry.rotation.y = atan2(ferry_to.x - ferry_from.x, ferry_to.z - ferry_from.z)
