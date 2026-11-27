extends Node3D
## Oyuncunun çevresinde 3D kuru ot tutamları.
## Sadece "grass" katmanı biçilmemiş yerlerde çıkar; tırpanla biçilen yerde anında kaybolur.
## Dünyaya sabit bir ızgara kullanır: oyuncu birkaç metre yürüyünce ızgara yeniden kurulur.

const SPACING := 0.33          # tutamlar arası mesafe (m)
const RADIUS := 16.0           # oyuncu çevresinde otun çizildiği yarıçap (m)
const REBUILD_DIST := 4.0      # bu kadar yürüyünce ızgara yeniden kurulur
const SHOW_THRESHOLD := 70     # ot maskesi bu değerin üstündeyse tutam görünür

var island = null
var target: Node3D = null      # oyuncu
var mm: MultiMesh
var mmi: MultiMeshInstance3D
var mat: ShaderMaterial
var n_side := 0
var origin_cell := Vector2i.ZERO   # ızgaranın sol üst hücresi (dünya hücresi)
var last_center := Vector3(1e9, 0, 1e9)
var enabled := true
var pending_row := -1          # kademeli yeniden kurulumda sıradaki satır (-1 = iş yok)
const ROWS_PER_FRAME := 20


func setup(isl, player: Node3D) -> void:
	island = isl
	target = player
	n_side = int(ceil(RADIUS * 2.0 / SPACING))
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _tuft_mesh()
	mm.instance_count = n_side * n_side
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# Izgara konumları değişse de görünmez olmasın diye geniş sınır kutusu
	mmi.custom_aabb = AABB(Vector3(-1e5, -100, -1e5), Vector3(2e5, 400, 2e5))


func set_enabled(v: bool) -> void:
	enabled = v
	if mmi != null:
		mmi.visible = v
	if v:
		last_center = Vector3(1e9, 0, 1e9)


func set_gloom(v: float) -> void:
	if mat != null:
		mat.set_shader_parameter("gloom", v)


func _process(_delta: float) -> void:
	if not enabled or target == null:
		return
	var p := target.global_position
	if Vector2(p.x - last_center.x, p.z - last_center.z).length() > REBUILD_DIST:
		_rebuild(p)
	if pending_row >= 0:
		var end := mini(n_side, pending_row + ROWS_PER_FRAME)
		for gz in range(pending_row, end):
			for gx in n_side:
				_set_instance(gx, gz)
		pending_row = end if end < n_side else -1


func _hash(x: int, z: int) -> float:
	var v := sin(float(x) * 127.1 + float(z) * 311.7) * 43758.5453
	return v - floor(v)


func _rebuild(center: Vector3) -> void:
	last_center = center
	var c0 := Vector2i(int(floor((center.x - RADIUS) / SPACING)), int(floor((center.z - RADIUS) / SPACING)))
	origin_cell = c0
	pending_row = 0   # satırlar birkaç kareye yayılarak kurulur (takılma olmasın)


## Biçilen alanın tutamlarını güncelle (tırpandan sonra çağrılır)
func refresh_area(pos: Vector3, radius: float) -> void:
	if not enabled or mm == null:
		return
	var x0 := int(floor((pos.x - radius) / SPACING)) - origin_cell.x
	var x1 := int(ceil((pos.x + radius) / SPACING)) - origin_cell.x
	var z0 := int(floor((pos.z - radius) / SPACING)) - origin_cell.y
	var z1 := int(ceil((pos.z + radius) / SPACING)) - origin_cell.y
	for gz in range(maxi(0, z0), mini(n_side - 1, z1) + 1):
		for gx in range(maxi(0, x0), mini(n_side - 1, x1) + 1):
			_set_instance(gx, gz)


func _set_instance(gx: int, gz: int) -> void:
	var idx := gz * n_side + gx
	var cx := origin_cell.x + gx
	var cz := origin_cell.y + gz
	var r1 := _hash(cx, cz)
	var r2 := _hash(cz + 17, cx - 31)
	var r3 := _hash(cx * 3 + 5, cz * 7 - 2)
	var x := (cx + r1) * SPACING
	var z := (cz + r2) * SPACING
	var d := Vector2(x - last_center.x, z - last_center.z).length()
	var v: int = island.sample(Vector3(x, 0, z), "grass") if d < RADIUS else 0
	if v < SHOW_THRESHOLD:
		mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3(x, -50, z)))
		return
	var dens := clampf(float(v - SHOW_THRESHOLD) / 120.0, 0.0, 1.0)
	var hgt := lerpf(0.3, 0.8, dens) * lerpf(0.6, 1.35, r3 * r3)
	# Kenarlara doğru (uzakta) biraz kısalsın: geçiş yumuşak görünsün
	hgt *= 1.0 - smoothstep(RADIUS * 0.75, RADIUS, d) * 0.6
	var wdt := lerpf(0.8, 1.2, r1)
	var b := Basis(Vector3.UP, r2 * TAU).scaled(Vector3(wdt, hgt, wdt))
	var y: float = island.ground_height(x, z) - 0.03
	mm.set_instance_transform(idx, Transform3D(b, Vector3(x, y, z)))
	# Renk: saman sarısı ile soluk yeşil-kahve arası
	var tint := Color(1.0, 1.0, 1.0).lerp(Color(0.8, 0.95, 0.7), r3 * 0.8).lerp(Color(1.1, 0.95, 0.78), r1 * 0.5)
	tint = tint * lerpf(0.75, 1.1, r2)
	tint.a = r2
	mm.set_instance_custom_data(idx, tint)


## Bir tutam: farklı yönlere eğilmiş 7 ince, sivri, hafif kavisli yaprak (yükseklik 1 birim)
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var blades := 12
	var segs := 3
	for b in blades:
		var ang := TAU * b / blades + rng.randf_range(-0.4, 0.4)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var lean := rng.randf_range(0.08, 0.55)
		var h := rng.randf_range(0.45, 1.0)
		var w := rng.randf_range(0.007, 0.014)
		var base := dir * rng.randf_range(0.0, 0.09)
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for s in segs + 1:
			var t := float(s) / segs
			var center := base + Vector3(0, t * h, 0) + dir * lean * t * t
			var half := w * (1.0 - t * 0.92)
			var l := center - side * half
			var r := center + side * half
			if s > 0:
				var t0 := float(s - 1) / segs
				var n := side.cross(Vector3(0, 1, 0) + dir * lean).normalized()
				for vtx in [[prev_l, t0], [prev_r, t0], [r, t], [prev_l, t0], [r, t], [l, t]]:
					st.set_normal(n)
					st.set_uv(Vector2(0.5, float(vtx[1])))
					st.add_vertex(vtx[0])
			prev_l = l
			prev_r = r
	return st.commit()
