extends Node3D
## Temizlik robotları: açık bölgelerde kirli bir yer seçer, oraya gider, geçtiği yeri temizler.
## Robot gibi çalışır, oyuncu yanında olmasa da kazandırır (oyun açıkken; çevrimdışı ilerleme yok).

const Isl := preload("res://scripts/island.gd")
const TICK := 0.25          # temizleme aralığı (sn)
const RADIUS := 1.1         # robotun temizlediği yarıçap (m)

var game = null
var bots: Array = []        # her biri: {node, target, timer, brush, stuck}
var _shared := {}           # ortak ağlar ve malzemeler


func setup(g) -> void:
	game = g
	_make_shared()


func set_count(n: int) -> void:
	while bots.size() < n:
		_spawn()
	while bots.size() > n:
		var b: Dictionary = bots.pop_back()
		(b["node"] as Node3D).queue_free()


func _spawn() -> void:
	var n := _build_model()
	add_child(n)
	var c: Vector3 = game.container_pos
	var a := randf() * TAU
	var x := c.x + cos(a) * 3.0
	var z := c.z + 3.0 + sin(a) * 3.0
	n.position = Vector3(x, game.island.ground_height(x, z), z)
	var snd: AudioStream = game.sfx.get("robot")
	if snd != null:
		var ap := AudioStreamPlayer3D.new()
		ap.stream = snd
		ap.bus = "Efekt"
		ap.volume_db = -14.0
		ap.unit_size = 2.5
		ap.max_distance = 28.0
		ap.pitch_scale = randf_range(0.92, 1.08)
		ap.autoplay = true
		n.add_child(ap)
	bots.append({"node": n, "target": n.position, "timer": randf() * TICK, "brush": n.get_node("Firca"), "stuck": 0.0, "led": n.get_node("Led")})


func _process(delta: float) -> void:
	if game == null or game.paused or bots.is_empty():
		return
	var isl = game.island
	var speed: float = game.robot_speed()
	var strength: float = game.robot_strength()
	for b: Dictionary in bots:
		var n: Node3D = b["node"]
		var tgt: Vector3 = b["target"]
		var to := Vector2(tgt.x - n.position.x, tgt.z - n.position.z)
		var d := to.length()
		b["stuck"] = float(b["stuck"]) + delta
		if d < 0.5 or float(b["stuck"]) > 40.0:
			b["target"] = _pick_target(n.position)
			b["stuck"] = 0.0
			continue
		var dir := to / d
		var step := minf(speed * delta, d)
		var nx := n.position.x + dir.x * step
		var nz := n.position.z + dir.y * step
		var ny: float = isl.ground_height(nx, nz)
		if ny < 0.15:
			# Suya inmesin: başka hedef seç
			b["target"] = _pick_target(n.position)
			continue
		n.position = Vector3(nx, ny, nz)
		var want := atan2(dir.x, dir.y)
		n.rotation.y = lerp_angle(n.rotation.y, want, minf(1.0, delta * 6.0))
		(b["brush"] as Node3D).rotation.y += delta * 18.0
		b["timer"] = float(b["timer"]) - delta
		if float(b["timer"]) <= 0.0:
			b["timer"] = TICK
			var p := n.position
			var total := 0.0
			for layer: String in Isl.LAYER_NAMES:
				total += isl.clean(p, RADIUS, strength * TICK, layer)
			if total > 0.0:
				game.cleaned_since_payout += total
				if game.grass != null:
					game.grass.refresh_area(p, RADIUS + 0.4)
			# Hedef temizlendiyse yakında yeni kirli yer ara
			if isl.sample_max(tgt) < Isl.CLEAN_THRESHOLD:
				b["target"] = _pick_target(n.position)
				b["stuck"] = 0.0
		# Durum ışığı: çalışırken yanıp söner
		var led: MeshInstance3D = b["led"]
		led.visible = fmod(Time.get_ticks_msec() * 0.001 + n.position.x, 1.0) < 0.7


## Kirli ve açık bir yer: önce yakında, bulunamazsa adanın açık bölgelerinde
func _pick_target(from: Vector3) -> Vector3:
	var isl = game.island
	for t in 80:
		var x: float
		var z: float
		if t < 40:
			x = from.x + randf_range(-25.0, 25.0)
			z = from.z + randf_range(-25.0, 25.0)
		else:
			x = randf_range(-300.0, 300.0)
			z = randf_range(-300.0, 300.0)
		var zn: int = isl.zone_at(x, z)
		if zn <= 0 or not isl.zone_unlocked(zn):
			continue
		var h: float = isl.ground_height(x, z)
		if h < 0.3:
			continue
		var p := Vector3(x, h, z)
		if isl.sample_max(p) > Isl.CLEAN_THRESHOLD + 30:
			return p
	return from + Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))


# ---------------------------------------------------------------------
# Model: robot çim biçme makinesi görünümünde oval gövde
# ---------------------------------------------------------------------

func _make_shared() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.93, 0.94, 0.92)
	shell.roughness = 0.25
	shell.clearcoat_enabled = true
	shell.clearcoat = 0.6
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.11, 0.12)
	dark.roughness = 0.5
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.07, 0.08)
	glass.roughness = 0.08
	glass.metallic = 0.5
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.95, 0.55, 0.1)
	accent.roughness = 0.4
	var led := StandardMaterial3D.new()
	led.albedo_color = Color(0.3, 1.0, 0.45)
	led.emission_enabled = true
	led.emission = Color(0.3, 1.0, 0.45)
	led.emission_energy_multiplier = 3.0
	led.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var body := CylinderMesh.new()
	body.top_radius = 0.36
	body.bottom_radius = 0.42
	body.height = 0.16
	body.radial_segments = 32
	body.material = shell
	var top := SphereMesh.new()
	top.radius = 0.3
	top.height = 0.22
	top.radial_segments = 32
	top.rings = 12
	top.is_hemisphere = true
	top.material = glass
	var bumper := TorusMesh.new()
	bumper.inner_radius = 0.4
	bumper.outer_radius = 0.45
	bumper.rings = 32
	bumper.ring_segments = 8
	bumper.material = dark
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.12
	wheel.bottom_radius = 0.12
	wheel.height = 0.07
	wheel.radial_segments = 18
	wheel.material = dark
	var brush := CylinderMesh.new()
	brush.top_radius = 0.26
	brush.bottom_radius = 0.26
	brush.height = 0.02
	brush.radial_segments = 6
	brush.material = accent
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.5, 0.02, 0.08)
	stripe.material = accent
	var dot := SphereMesh.new()
	dot.radius = 0.025
	dot.height = 0.05
	dot.material = led
	var ant := CylinderMesh.new()
	ant.top_radius = 0.006
	ant.bottom_radius = 0.008
	ant.height = 0.22
	ant.material = dark
	_shared = {"body": body, "top": top, "bumper": bumper, "wheel": wheel, "brush": brush, "stripe": stripe, "led": dot, "ant": ant}


func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, nm := "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	if nm != "":
		m.name = nm
	parent.add_child(m)
	return m


func _build_model() -> Node3D:
	var root := Node3D.new()
	var oval := Node3D.new()
	oval.scale = Vector3(1.0, 1.0, 1.25)
	root.add_child(oval)
	_mi(oval, _shared["body"], Vector3(0, 0.17, 0))
	_mi(oval, _shared["bumper"], Vector3(0, 0.12, 0))
	var t := _mi(oval, _shared["top"], Vector3(0, 0.25, -0.04))
	t.scale = Vector3(1.0, 0.7, 1.0)
	_mi(oval, _shared["stripe"], Vector3(0, 0.255, 0.3))
	for side in [-1.0, 1.0]:
		var w := _mi(root, _shared["wheel"], Vector3(0.43 * side, 0.12, -0.25))
		w.rotation.z = PI * 0.5
	var br := Node3D.new()
	br.name = "Firca"
	br.position = Vector3(0, 0.04, 0.08)
	root.add_child(br)
	_mi(br, _shared["brush"], Vector3.ZERO)
	_mi(root, _shared["led"], Vector3(0, 0.31, 0.2), "Led")
	var a := _mi(root, _shared["ant"], Vector3(0.12, 0.38, -0.3))
	a.rotation.x = -0.25
	return root
