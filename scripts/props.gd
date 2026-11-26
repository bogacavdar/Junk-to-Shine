extends Node3D
## Bölgelerin yapıları: iskele, sahil şemsiyeleri, liman rıhtımı.
## Her yapı önce yıpranmış görünür; bölge tamamlanınca "yenilenmiş" hâline geçer.

var island = null            # island.gd
var mats := {}               # "wood", "concrete", "metal"
var zone_sets := {}          # bölge -> Array[Dictionary] (yenilenecek parçalar)
var rng := RandomNumberGenerator.new()

const DIRTY := Color(0.42, 0.40, 0.34)
const DECK_Y := 1.35


func setup(isl, materials: Dictionary, seed_value: int) -> void:
	island = isl
	mats = materials
	rng.seed = seed_value
	_build_pier()
	_build_beach()
	_build_harbor()


# ---------------------------------------------------------------------
# Ortak yardımcılar
# ---------------------------------------------------------------------

func _register(zone: int, item: Dictionary) -> void:
	if not zone_sets.has(zone):
		zone_sets[zone] = []
	(zone_sets[zone] as Array).append(item)


## Kirli kopya: aynı doku, koyu ve soluk renk. Yenilenince beyaza döner.
func _dirty_copy(key: String) -> StandardMaterial3D:
	var m: StandardMaterial3D = (mats[key] as StandardMaterial3D).duplicate()
	m.albedo_color = DIRTY
	return m


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


## Kıyı noktası: merkezden verilen yöne doğru giderken karanın bittiği yer
func _shore_point(dir: Vector2) -> Vector2:
	var d := dir.normalized()
	var r := 345.0
	while r > 20.0:
		var p := d * r
		if island.height_at(p.x, p.y) > 0.3:
			return p
		r -= 1.0
	return d * 20.0


# ---------------------------------------------------------------------
# İskele (bölge 1): başlangıç noktasından denize uzanan ahşap iskele
# ---------------------------------------------------------------------

func _build_pier() -> void:
	var root := Node3D.new()
	root.name = "Iskele"
	add_child(root)
	var sp: Vector3 = island.spawn_point
	# İskele, başlangıçtan güneye doğru denize uzanır
	var z0 := sp.z
	while island.height_at(sp.x, z0) > 0.4 and z0 < sp.z + 60.0:
		z0 += 0.5
	var z_start := z0 - 6.0
	var length := 34.0
	var width := 3.6
	var x := sp.x - 5.0
	var wood := _dirty_copy("wood")
	var metal: Material = mats["metal"]

	# Tahtalar (MultiMesh): bazıları kırık / eksik
	var plank := BoxMesh.new()
	plank.size = Vector3(width, 0.07, 0.24)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plank
	var count := int(length / 0.27)
	mm.instance_count = count
	var full: Array[Transform3D] = []
	var broken: Array[Transform3D] = []
	for i in count:
		var t := Transform3D(Basis(), Vector3(x, DECK_Y, z_start + i * 0.27))
		full.append(t)
		var r := rng.randf()
		if r < 0.12:
			broken.append(Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), t.origin))   # eksik tahta
		elif r < 0.3:
			var b := Basis(Vector3(0, 0, 1), rng.randf_range(-0.12, 0.12)).rotated(Vector3.UP, rng.randf_range(-0.08, 0.08))
			broken.append(Transform3D(b, t.origin + Vector3(rng.randf_range(-0.2, 0.2), -0.03, 0)))   # kaymış tahta
		else:
			broken.append(t)
		mm.set_instance_transform(i, broken[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = wood
	root.add_child(mmi)

	# Kirişler ve kazıklar
	for side in [-1.0, 1.0]:
		_box(root, Vector3(x + side * (width * 0.5 - 0.15), DECK_Y - 0.14, z_start + length * 0.5), Vector3(0.18, 0.2, length), wood)
	var zz := z_start + 1.0
	while zz < z_start + length:
		for side in [-1.0, 1.0]:
			var px: float = x + side * (width * 0.5 - 0.15)
			var floor_h: float = minf(island.height_at(px, zz), DECK_Y - 0.3)
			var h := DECK_Y - floor_h + 0.6
			_cylinder(root, Vector3(px, floor_h - 0.6 + h * 0.5, zz), 0.13, h, wood)
		zz += 3.0
	# Babalar (halat bağlama) ve sonunda iki ahşap sandık
	for k in 3:
		_cylinder(root, Vector3(x + width * 0.5 - 0.3, DECK_Y + 0.25, z_start + 10.0 + k * 9.0), 0.11, 0.45, metal)
	_box(root, Vector3(x - 1.0, DECK_Y + 0.35, z_start + length - 2.0), Vector3(0.7, 0.7, 0.7), wood, 0.3)
	_box(root, Vector3(x - 0.95, DECK_Y + 1.05, z_start + length - 2.05), Vector3(0.6, 0.6, 0.6), wood, -0.2)

	# Yürünebilir zemin
	_collider(Vector3(x, DECK_Y - 0.05, z_start + length * 0.5), Vector3(width, 0.2, length))

	_register(1, {"kind": "multimesh", "mm": mm, "full": full})
	_register(1, {"kind": "material", "mat": wood})


# ---------------------------------------------------------------------
# Sahil (bölge 2): devrilmiş, solmuş şemsiyeler ve şezlonglar
# ---------------------------------------------------------------------

func _build_beach() -> void:
	var root := Node3D.new()
	root.name = "Sahil"
	add_child(root)
	var colors := [Color(0.85, 0.2, 0.15), Color(0.1, 0.45, 0.8), Color(0.95, 0.75, 0.15), Color(0.15, 0.6, 0.45)]
	var placed := 0
	var tries := 0
	while placed < 10 and tries < 4000:
		tries += 1
		var a := rng.randf_range(-0.75, 0.75)
		var dir := Vector2(sin(a), cos(a))
		var shore := _shore_point(dir)
		var p := shore - dir * rng.randf_range(4.0, 12.0)
		var h: float = island.height_at(p.x, p.y)
		if h < 0.5 or h > 1.5 or island.zone_at(p.x, p.y) != 2:
			continue
		placed += 1
		var col: Color = colors[placed % colors.size()]
		var faded := StandardMaterial3D.new()
		faded.albedo_color = col.lerp(Color(0.55, 0.52, 0.48), 0.7)
		faded.roughness = 0.9
		faded.cull_mode = BaseMaterial3D.CULL_DISABLED
		var umb := Node3D.new()
		umb.position = Vector3(p.x, h, p.y)
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
		# Devrilmiş hâli
		var fall_rot := Vector3(deg_to_rad(rng.randf_range(65.0, 80.0)), rng.randf_range(0.0, TAU), 0)
		var upright := Vector3(deg_to_rad(rng.randf_range(-4.0, 4.0)), fall_rot.y, 0)
		umb.rotation = fall_rot
		_register(2, {"kind": "node", "node": umb, "rot": upright})
		_register(2, {"kind": "color", "mat": faded, "color": col})
		# Yanına bir şezlong
		var lounger := _box(root, Vector3(p.x + 1.6, h + 0.25, p.y + 0.4), Vector3(0.65, 0.08, 1.9), _dirty_copy("wood"), rng.randf_range(-0.4, 0.4))
		_register(2, {"kind": "material", "mat": lounger.material_override})


# ---------------------------------------------------------------------
# Liman (bölge 3): batı kıyısında beton rıhtım, babalar, kasalar
# ---------------------------------------------------------------------

func _build_harbor() -> void:
	var root := Node3D.new()
	root.name = "Liman"
	add_child(root)
	var shore := _shore_point(Vector2(-1.0, 0.05))
	var concrete := _dirty_copy("concrete")
	var wood := _dirty_copy("wood")
	var top := 1.7
	var length := 46.0
	var cx := shore.x - 4.0
	var cz := shore.y
	# Rıhtım bloğu: deniz tabanından üst seviyeye
	var depth := top + 6.0
	_box(root, Vector3(cx, top - depth * 0.5, cz), Vector3(9.0, depth, length), concrete)
	_collider(Vector3(cx, top - 0.5, cz), Vector3(9.0, 1.0, length))
	# Rıhtıma çıkış rampası (kıyı tarafı)
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
	# Babalar deniz kenarında
	var zz := cz - length * 0.5 + 3.0
	while zz < cz + length * 0.5:
		_cylinder(root, Vector3(cx - 4.0, top + 0.3, zz), 0.18, 0.6, mats["metal"])
		zz += 7.0
	# Kasa yığınları
	for k in 6:
		var bx := cx + rng.randf_range(-1.5, 3.5)
		var bz := cz + rng.randf_range(-length * 0.45, length * 0.45)
		var stack := rng.randi_range(1, 3)
		for s in stack:
			_box(root, Vector3(bx, top + 0.45 + s * 0.9, bz), Vector3(0.9, 0.9, 0.9), wood, rng.randf_range(-0.3, 0.3))
		_collider(Vector3(bx, top + 0.45 * stack, bz), Vector3(0.9, 0.9 * stack, 0.9))
	_register(3, {"kind": "material", "mat": concrete})
	_register(3, {"kind": "material", "mat": wood})


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
				if instant:
					n.rotation = r
				else:
					var tw := create_tween()
					tw.tween_interval(rng.randf_range(0.0, 1.2))
					tw.tween_property(n, "rotation", r, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			"multimesh":
				var mm: MultiMesh = item["mm"]
				var full: Array = item["full"]
				for i in full.size():
					mm.set_instance_transform(i, full[i])
