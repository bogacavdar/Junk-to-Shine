extends Node3D
## Ada: kodla üretilen arazi + 40 m'lik parçalara (chunk) bölünmüş temizlik maskeleri.
## Katmanlar (her biri gerçekte o zemine uygun aletle temizlenir):
##   grass : uzamış kuru ot      -> tırpan (yalnız toprak/çim zeminde)
##   leaf  : yaprak/dal, kumsalda deniz yosunu -> tırmık
##   dirt  : çamur/yosun/leke    -> basınçlı yıkayıcı (yalnız taş yol ve meydanlarda)
## Her parçanın kendi maskeleri var; sadece temizlenen parçanın dokusu güncellenir.

const ISLAND_RADIUS := 300.0     # ada yarıçapı (m) -> yaklaşık 600 x 600 m
const CHUNK_SIZE := 40.0         # bir parçanın kenarı (m)
const GRID := 16                 # 16 x 16 parça = 640 m kare alan
const MASK_RES := 256            # parça başına maske çözünürlüğü (6,4 px/m)
const VERTS := 33                # parça başına arazi ızgarası (1,25 m aralık)
const SURF_RES := 65             # parça başına zemin türü haritası (0,625 m aralık)
const CLEAN_THRESHOLD := 40      # görünen değer bu eşiğin altına inince piksel "temiz" sayılır

# Maskeler ham gürültü olarak tutulur; yoğunluk (bias/kontrast) shader'da uygulanır.
# surface: "hard" = sadece taş yolda, "soft" = sadece toprakta, "any" = her yerde
const LAYER_NAMES := ["dirt", "leaf", "grass"]
const LAYERS := {
	"dirt": {"bias": 0.40, "contrast": 2.4, "freq": 0.012, "min_h": 0.15, "surface": "hard"},
	"leaf": {"bias": 0.55, "contrast": 2.8, "freq": 0.02, "min_h": 0.3, "surface": "any"},
	"grass": {"bias": 0.32, "contrast": 2.6, "freq": 0.008, "min_h": 1.6, "surface": "soft"},
}
var raw_threshold := {}   # katman -> ham değer eşiği (0-255)

# Bölgeler: 0 = deniz. Sıra açılış sırasıdır; her bölge bir öncekinin %75'i temizlenince açılır
# (ya da dükkândan erken satın alınır).
const ZONE_NAMES := ["Deniz", "İskele", "Sahil", "Liman", "Köy", "Tarlalar", "Orman", "Fener Tepesi"]
const ZONE_MULT := [0.0, 1.0, 3.0, 9.0, 27.0, 80.0, 240.0, 700.0]       # kazanç çarpanı
const ZONE_PRICE := [0.0, 0.0, 400.0, 8000.0, 150000.0, 3.0e6, 6.0e7, 1.2e9]  # erken açma fiyatı
const ZONE_AUTO := 0.75        # bir önceki bölge bu oranda temizse sonraki kendiliğinden açılır
const ISKELE_RADIUS := 40.0
const LIGHTHOUSE := Vector2(150.0, -150.0)

# Taş yollar ve köy meydanı (sert zemin). Yol yarı genişliği:
const PATH_HALF := 2.0
const PLAZA_CENTER := Vector2(0.0, 0.0)
const PLAZA_RADIUS := 26.0
var path_segments: Array[Vector4] = []   # (ax, az, bx, bz)

var spawn_point := Vector3.ZERO
var harbor_point := Vector2.ZERO
var unlocked_mask := 1 << 1    # başta sadece iskele açık
var zone_total := PackedInt64Array()
var zone_clean := PackedInt64Array()
var layer_total := {}
var layer_clean := {}

var terrain_shader: Shader
var textures := {}
var noise_shape := FastNoiseLite.new()
var noise_detail := FastNoiseLite.new()

# Parça verileri: anahtar = Vector2i(cx, cz)
var chunks := {}


func setup(world_seed: int, shader: Shader, tex: Dictionary) -> void:
	terrain_shader = shader
	textures = tex
	noise_shape.seed = world_seed
	noise_shape.frequency = 0.004
	noise_shape.fractal_octaves = 4
	noise_detail.seed = world_seed + 7
	noise_detail.frequency = 0.03
	noise_detail.fractal_octaves = 3
	zone_total.resize(ZONE_NAMES.size())
	zone_clean.resize(ZONE_NAMES.size())
	zone_total.fill(0)
	zone_clean.fill(0)
	for layer: String in LAYER_NAMES:
		layer_total[layer] = 0
		layer_clean[layer] = 0
		var L: Dictionary = LAYERS[layer]
		raw_threshold[layer] = int(255.0 * (float(L["bias"]) + (CLEAN_THRESHOLD / 255.0 - 0.5) / float(L["contrast"])))
	# Başlangıç: güney kıyısında kumsalın bittiği yer (bölgeler buna göre çizilir)
	var z := ISLAND_RADIUS * 1.1
	while z > 0.0 and height_at(0.0, z) < 1.8:
		z -= 1.0
	spawn_point = Vector3(0.0, height_at(0.0, z - 4.0), z - 4.0)
	harbor_point = _shore_point(Vector2(-1.0, 0.05))
	_build_paths()
	for cz in GRID:
		for cx in GRID:
			_build_chunk(Vector2i(cx, cz))


## Arazi yüksekliği (deniz seviyesi = 0). Ortada tepeler, kenarlarda kumsal, dışarıda deniz tabanı.
func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length() / ISLAND_RADIUS
	var shape := 1.0 - d + noise_shape.get_noise_2d(x, z) * 0.35
	if shape < 0.0:
		return shape * 25.0 - 0.5
	# Kıyıda yumuşak kumsal, içeride yükselen tepeler; kuzeydoğuda fener tepesi
	var hill := shape * shape * 28.0
	var lighthouse := maxf(0.0, 1.0 - Vector2(x - 150.0, z + 150.0).length() / 90.0)
	hill += lighthouse * lighthouse * 30.0
	return 0.6 + hill + noise_detail.get_noise_2d(x, z) * 0.8 * clampf(shape * 4.0, 0.0, 1.0)


func _shore_point(dir: Vector2) -> Vector2:
	var d := dir.normalized()
	var r := 345.0
	while r > 20.0:
		var p := d * r
		if height_at(p.x, p.y) > 0.3:
			return p
		r -= 1.0
	return d * 20.0


# ---------------------------------------------------------------------
# Taş yollar ve meydan
# ---------------------------------------------------------------------

func _build_paths() -> void:
	path_segments.clear()
	var sp := Vector2(spawn_point.x, spawn_point.z)
	# İskeleden köy meydanına
	_polyline([sp + Vector2(0, -3), Vector2(10, sp.y - 70), Vector2(-8, 110), Vector2(4, 50), Vector2(0, PLAZA_RADIUS - 2)])
	# Meydandan limana
	var hp := harbor_point + Vector2(8.0, 0.0)
	_polyline([Vector2(-PLAZA_RADIUS + 2, 0), Vector2(-90, 12), Vector2(-160, -6), hp])
	# Meydandan fener tepesine
	_polyline([Vector2(18, -18), Vector2(70, -60), Vector2(105, -110), Vector2(135, -138)])
	# Tarlalara doğru bir yan yol
	_polyline([Vector2(20, 16), Vector2(80, 70), Vector2(120, 140)])


func _polyline(pts: Array) -> void:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		path_segments.append(Vector4(a.x, a.y, b.x, b.y))


## Sert zemine (yol/meydan kenarına) uzaklık; içerideyse negatif
func path_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := p.distance_to(PLAZA_CENTER) - PLAZA_RADIUS
	for s: Vector4 in path_segments:
		var a := Vector2(s.x, s.y)
		var b := Vector2(s.z, s.w)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t) - PATH_HALF)
	return best


func _chunk_near_paths(origin: Vector3) -> bool:
	var c := Vector2(origin.x + CHUNK_SIZE * 0.5, origin.z + CHUNK_SIZE * 0.5)
	return path_distance(c.x, c.y) < CHUNK_SIZE * 0.78


# ---------------------------------------------------------------------
# Bölgeler
# ---------------------------------------------------------------------

## Bir noktanın bölgesi (konum ve yüksekliğe göre)
func zone_of(x: float, z: float, h: float) -> int:
	if h < 0.0:
		return 0
	if Vector2(x - spawn_point.x, z - spawn_point.z).length() < ISKELE_RADIUS:
		return 1
	if Vector2(x, z).distance_to(LIGHTHOUSE) < 110.0:
		return 7
	var ang := atan2(x, z)   # 0 = güney (başlangıç tarafı), -PI/2 = batı
	if h < 1.6:
		if absf(ang) < 0.87:
			return 2
		if absf(ang + PI * 0.5) < 0.96:
			return 3
	if Vector2(x, z).length() < 120.0:
		return 4
	if z > 0.0:
		return 5
	return 6


func zone_unlocked(zn: int) -> bool:
	return zn > 0 and (unlocked_mask >> zn) & 1 == 1


## Oyuncunun bulunduğu bölge (parça ızgarasından)
func zone_at(x: float, z: float) -> int:
	var key := chunk_of(x, z)
	if not chunks.has(key):
		return 0
	var origin := chunk_origin(key)
	var step := CHUNK_SIZE / float(VERTS - 1)
	var i := clampi(int(round((x - origin.x) / step)), 0, VERTS - 1)
	var j := clampi(int(round((z - origin.z) / step)), 0, VERTS - 1)
	var zm: PackedByteArray = chunks[key]["zones"]
	return zm[j * VERTS + i]


func zone_fraction(zn: int) -> float:
	if zone_total[zn] <= 0:
		return 0.0
	return minf(1.0, float(zone_clean[zn]) / float(zone_total[zn]))


func set_unlocked(mask: int) -> void:
	unlocked_mask = mask
	for k in chunks:
		(chunks[k]["mat"] as ShaderMaterial).set_shader_parameter("unlocked_zones", unlocked_mask)


func chunk_origin(c: Vector2i) -> Vector3:
	var half := GRID * CHUNK_SIZE * 0.5
	return Vector3(-half + c.x * CHUNK_SIZE, 0, -half + c.y * CHUNK_SIZE)


func chunk_of(x: float, z: float) -> Vector2i:
	var half := GRID * CHUNK_SIZE * 0.5
	return Vector2i(int(floor((x + half) / CHUNK_SIZE)), int(floor((z + half) / CHUNK_SIZE)))


# ---------------------------------------------------------------------
# Parça kurulumu
# ---------------------------------------------------------------------

func _build_chunk(c: Vector2i) -> void:
	var origin := chunk_origin(c)
	var step := CHUNK_SIZE / float(VERTS - 1)
	var heights := PackedFloat32Array()
	heights.resize(VERTS * VERTS)
	var max_h := -1000.0
	for j in VERTS:
		for i in VERTS:
			var h: float = height_at(origin.x + i * step, origin.z + j * step)
			heights[j * VERTS + i] = h
			max_h = maxf(max_h, h)
	if max_h < -0.6:
		return   # tamamen deniz altında: parça yok

	# Arazi ağı
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in VERTS:
		for i in VERTS:
			var hl: float = heights[j * VERTS + maxi(i - 1, 0)]
			var hr: float = heights[j * VERTS + mini(i + 1, VERTS - 1)]
			var hd: float = heights[maxi(j - 1, 0) * VERTS + i]
			var hu: float = heights[mini(j + 1, VERTS - 1) * VERTS + i]
			st.set_normal(Vector3(hl - hr, 2.0 * step, hd - hu).normalized())
			st.set_uv(Vector2(float(i) / (VERTS - 1), float(j) / (VERTS - 1)))
			st.add_vertex(Vector3(i * step, heights[j * VERTS + i], j * step))
	for j in VERTS - 1:
		for i in VERTS - 1:
			var a := j * VERTS + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + VERTS)
			st.add_index(a + 1)
			st.add_index(a + VERTS + 1)
			st.add_index(a + VERTS)
	var mesh := st.commit()

	# Bölge haritası: köşe başına bir bölge
	var zones := PackedByteArray()
	zones.resize(VERTS * VERTS)
	var zimg_data := PackedByteArray()
	zimg_data.resize(VERTS * VERTS)
	for j in VERTS:
		for i in VERTS:
			var zn := zone_of(origin.x + i * step, origin.z + j * step, heights[j * VERTS + i])
			zones[j * VERTS + i] = zn
			zimg_data[j * VERTS + i] = zn * 32
	var z_tex := ImageTexture.create_from_image(Image.create_from_data(VERTS, VERTS, false, Image.FORMAT_L8, zimg_data))

	# Zemin türü haritası: 255 = taş yol/meydan (sert), 0 = toprak
	var surface := PackedByteArray()
	surface.resize(SURF_RES * SURF_RES)
	surface.fill(0)
	if _chunk_near_paths(origin):
		var sstep := CHUNK_SIZE / float(SURF_RES - 1)
		for j in SURF_RES:
			for i in SURF_RES:
				var d := path_distance(origin.x + i * sstep, origin.z + j * sstep)
				surface[j * SURF_RES + i] = int(255.0 * (1.0 - smoothstep(-0.4, 0.4, d)))
	var s_tex := ImageTexture.create_from_image(Image.create_from_data(SURF_RES, SURF_RES, false, Image.FORMAT_L8, surface))

	var mat := ShaderMaterial.new()
	mat.shader = terrain_shader
	mat.set_shader_parameter("zone_map", z_tex)
	mat.set_shader_parameter("surface_map", s_tex)
	mat.set_shader_parameter("unlocked_zones", unlocked_mask)
	for k in textures:
		mat.set_shader_parameter(k, textures[k])
	mat.set_shader_parameter("chunk_origin", Vector2(origin.x, origin.z))
	mat.set_shader_parameter("chunk_size", CHUNK_SIZE)
	for layer: String in LAYER_NAMES:
		mat.set_shader_parameter(layer + "_bias", LAYERS[layer]["bias"])
		mat.set_shader_parameter(layer + "_contrast", LAYERS[layer]["contrast"])

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = origin
	add_child(mi)

	# Çarpışma: yükseklik haritası
	var body := StaticBody3D.new()
	body.position = origin + Vector3(CHUNK_SIZE * 0.5, 0, CHUNK_SIZE * 0.5)
	var cs := CollisionShape3D.new()
	var hs := HeightMapShape3D.new()
	hs.map_width = VERTS
	hs.map_depth = VERTS
	var scaled := PackedFloat32Array()
	scaled.resize(VERTS * VERTS)
	for n in VERTS * VERTS:
		scaled[n] = heights[n] / step
	hs.map_data = scaled
	cs.shape = hs
	cs.scale = Vector3(step, step, step)
	body.add_child(cs)
	add_child(body)

	var ch := {"mesh": mi, "mat": mat, "modified": false, "heights": heights, "zones": zones, "surface": surface}
	chunks[c] = ch
	# Maskeler (gürültüden, hızlı: FastNoiseLite.get_image yerel kodda çalışır)
	for layer: String in LAYER_NAMES:
		var data := _noise_mask(c, float(LAYERS[layer]["freq"]))
		var img := Image.create_from_data(MASK_RES, MASK_RES, false, Image.FORMAT_L8, data)
		var tex := ImageTexture.create_from_image(img)
		mat.set_shader_parameter(layer + "_mask", tex)
		ch[layer] = data
		ch[layer + "_img"] = img
		ch[layer + "_tex"] = tex
		var cnt := _count_est(c, layer, data)
		for zn in ZONE_NAMES.size():
			layer_total[layer] += cnt[zn]
			zone_total[zn] += cnt[zn]


func _noise_mask(c: Vector2i, freq: float) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = noise_shape.seed + int(freq * 1000.0)
	n.frequency = freq / (MASK_RES / CHUNK_SIZE)
	n.fractal_octaves = 3
	n.offset = Vector3(c.x * MASK_RES, c.y * MASK_RES, 0)
	var img := n.get_image(MASK_RES, MASK_RES)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


## Bu katman bu pikselde var olabilir mi? (yükseklik ve zemin türüne göre)
func _allowed(ch: Dictionary, layer: String, x: int, y: int) -> bool:
	var heights: PackedFloat32Array = ch["heights"]
	var vi: int = mini(int(round(x * (VERTS - 1) / float(MASK_RES))), VERTS - 1)
	var vj: int = mini(int(round(y * (VERTS - 1) / float(MASK_RES))), VERTS - 1)
	var L: Dictionary = LAYERS[layer]
	if heights[vj * VERTS + vi] < float(L["min_h"]):
		return false
	var surf_rule: String = L["surface"]
	if surf_rule == "any":
		return true
	var surface: PackedByteArray = ch["surface"]
	var si: int = mini(int(round(x * (SURF_RES - 1) / float(MASK_RES))), SURF_RES - 1)
	var sj: int = mini(int(round(y * (SURF_RES - 1) / float(MASK_RES))), SURF_RES - 1)
	var hard: bool = surface[sj * SURF_RES + si] >= 128
	return hard if surf_rule == "hard" else not hard


## Kirli piksel sayısını bölge bölge örnekleyerek tahmin et (her 8 pikselde bir)
func _count_est(c: Vector2i, layer: String, data: PackedByteArray) -> PackedInt64Array:
	var ch: Dictionary = chunks[c]
	var zones: PackedByteArray = ch["zones"]
	var thr: int = raw_threshold[layer]
	var out := PackedInt64Array()
	out.resize(ZONE_NAMES.size())
	out.fill(0)
	for y in range(4, MASK_RES, 8):
		var j: int = mini(int(round(y * (VERTS - 1) / float(MASK_RES))), VERTS - 1)
		for x in range(4, MASK_RES, 8):
			if data[y * MASK_RES + x] < thr:
				continue
			if not _allowed(ch, layer, x, y):
				continue
			var i: int = mini(int(round(x * (VERTS - 1) / float(MASK_RES))), VERTS - 1)
			out[zones[j * VERTS + i]] += 64
	return out


# ---------------------------------------------------------------------
# Temizleme
# ---------------------------------------------------------------------

## Bir noktada fırça ile temizle. layer: "dirt", "leaf" ya da "grass".
## Döner: temizlenen piksellerin bölge çarpanıyla ağırlıklı toplamı (para hesabı için).
## Kapalı bölgede ve o katmanın olamayacağı zeminde temizlenmez.
func clean(pos: Vector3, radius: float, amount: float, layer: String) -> float:
	var value := 0.0
	var c0 := chunk_of(pos.x - radius, pos.z - radius)
	var c1 := chunk_of(pos.x + radius, pos.z + radius)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var key := Vector2i(cx, cz)
			if not chunks.has(key):
				continue
			value += _clean_chunk(key, pos, radius, amount, layer)
	return value


func _clean_chunk(key: Vector2i, pos: Vector3, radius: float, amount: float, layer: String) -> float:
	var ch: Dictionary = chunks[key]
	var data: PackedByteArray = ch[layer]
	var zones: PackedByteArray = ch["zones"]
	var origin := chunk_origin(key)
	var ppm := MASK_RES / CHUNK_SIZE
	var cx := (pos.x - origin.x) * ppm
	var cy := (pos.z - origin.z) * ppm
	var r_px := maxf(1.0, radius * ppm)
	var x0 := maxi(0, int(cx - r_px))
	var x1 := mini(MASK_RES - 1, int(cx + r_px))
	var y0 := maxi(0, int(cy - r_px))
	var y1 := mini(MASK_RES - 1, int(cy + r_px))
	if x0 > x1 or y0 > y1:
		return 0.0
	var cleaned := 0
	var value := 0.0
	var changed := false
	var thr: int = raw_threshold[layer]
	for y in range(y0, y1 + 1):
		var vj: int = mini(int(round(y * (VERTS - 1) / float(MASK_RES))), VERTS - 1)
		for x in range(x0, x1 + 1):
			var dx: float = x - cx
			var dy: float = y - cy
			var dist := sqrt(dx * dx + dy * dy) / r_px
			if dist > 1.0:
				continue
			var idx: int = y * MASK_RES + x
			var old: int = data[idx]
			if old == 0:
				continue
			var zn: int = zones[vj * VERTS + mini(int(round(x * (VERTS - 1) / float(MASK_RES))), VERTS - 1)]
			if (unlocked_mask >> zn) & 1 == 0:
				continue
			if not _allowed(ch, layer, x, y):
				continue
			var nv := int(maxf(0.0, float(old) - amount * (1.0 - dist * dist * 0.7)))
			data[idx] = nv
			changed = true
			if old >= thr and nv < thr:
				cleaned += 1
				zone_clean[zn] += 1
				value += ZONE_MULT[zn]
	if changed:
		ch[layer] = data
		ch["modified"] = true
		var img: Image = ch[layer + "_img"]
		img.set_data(MASK_RES, MASK_RES, false, Image.FORMAT_L8, data)
		(ch[layer + "_tex"] as ImageTexture).update(img)
		layer_clean[layer] += cleaned
	return value


## Bir noktadaki görünen maske değeri (0-255); katman orada olamıyorsa 0
func sample(pos: Vector3, layer: String) -> int:
	var key := chunk_of(pos.x, pos.z)
	if not chunks.has(key):
		return 0
	var ch: Dictionary = chunks[key]
	var origin := chunk_origin(key)
	var ppm := MASK_RES / CHUNK_SIZE
	var x := clampi(int((pos.x - origin.x) * ppm), 0, MASK_RES - 1)
	var y := clampi(int((pos.z - origin.z) * ppm), 0, MASK_RES - 1)
	if not _allowed(ch, layer, x, y):
		return 0
	var data: PackedByteArray = ch[layer]
	var L: Dictionary = LAYERS[layer]
	var eff := clampf((float(data[y * MASK_RES + x]) / 255.0 - float(L["bias"])) * float(L["contrast"]) + 0.5, 0.0, 1.0)
	return int(eff * 255.0)


## Bir noktada herhangi bir katmanın en yüksek görünen değeri
func sample_max(pos: Vector3) -> int:
	var m := 0
	for layer: String in LAYER_NAMES:
		m = maxi(m, sample(pos, layer))
	return m


func set_hint(v: float) -> void:
	for k in chunks:
		(chunks[k]["mat"] as ShaderMaterial).set_shader_parameter("hint", v)


# ---------------------------------------------------------------------
# Kayıt: sadece değişen parçalar, sıkıştırılmış
# ---------------------------------------------------------------------

func save_data() -> Dictionary:
	var out := {}
	for k in chunks:
		var ch: Dictionary = chunks[k]
		if ch["modified"]:
			var entry := {}
			for layer: String in LAYER_NAMES:
				entry[layer] = Marshalls.raw_to_base64((ch[layer] as PackedByteArray).compress(FileAccess.COMPRESSION_DEFLATE))
			out["%d,%d" % [k.x, k.y]] = entry
	return out


func load_data(d: Dictionary) -> void:
	for key_s in d:
		var parts: PackedStringArray = str(key_s).split(",")
		if parts.size() != 2:
			continue
		var k := Vector2i(int(parts[0]), int(parts[1]))
		if not chunks.has(k):
			continue
		var entry = d[key_s]
		if not (entry is Dictionary):
			continue   # eski biçimdeki kayıt (yıkama dönemi): yok say
		var ch: Dictionary = chunks[k]
		for layer: String in LAYER_NAMES:
			if not (entry as Dictionary).has(layer):
				continue
			var raw := Marshalls.base64_to_raw(str(entry[layer])).decompress(MASK_RES * MASK_RES, FileAccess.COMPRESSION_DEFLATE)
			if raw.size() != MASK_RES * MASK_RES:
				continue
			var before := _count_est(k, layer, ch[layer])
			var after := _count_est(k, layer, raw)
			for zn in ZONE_NAMES.size():
				var diff: int = before[zn] - after[zn]
				zone_clean[zn] += diff
				layer_clean[layer] += diff
			ch[layer] = raw
			var img: Image = ch[layer + "_img"]
			img.set_data(MASK_RES, MASK_RES, false, Image.FORMAT_L8, raw)
			(ch[layer + "_tex"] as ImageTexture).update(img)
		ch["modified"] = true


func total_clean() -> int:
	var s := 0
	for layer: String in LAYER_NAMES:
		s += int(layer_clean[layer])
	return s


func clean_fraction() -> float:
	var t := 0
	for layer: String in LAYER_NAMES:
		t += int(layer_total[layer])
	return minf(1.0, float(total_clean()) / float(maxi(1, t)))
