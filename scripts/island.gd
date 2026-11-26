extends Node3D
## Ada: kodla üretilen arazi + 40 m'lik parçalara (chunk) bölünmüş kir ve yaprak maskeleri.
## Her parçanın kendi maskesi var; sadece temizlenen parçanın dokusu güncellenir.

const ISLAND_RADIUS := 300.0     # ada yarıçapı (m) -> yaklaşık 600 x 600 m
const CHUNK_SIZE := 40.0         # bir parçanın kenarı (m)
const GRID := 16                 # 16 x 16 parça = 640 m kare alan
const MASK_RES := 256            # parça başına maske çözünürlüğü (6,4 px/m)
const VERTS := 33                # parça başına arazi ızgarası (1,25 m aralık)
const CLEAN_THRESHOLD := 40      # görünen değer bu eşiğin altına inince piksel "temiz" sayılır

# Maskeler ham gürültü olarak tutulur; yoğunluk (bias/kontrast) shader'da uygulanır.
const LAYERS := {
	"dirt": {"bias": 0.42, "contrast": 2.4, "min_h": 0.15},
	"leaf": {"bias": 0.55, "contrast": 2.8, "min_h": 1.3},
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

var spawn_point := Vector3.ZERO
var unlocked_mask := 1 << 1    # başta sadece iskele açık
var zone_total := PackedInt64Array()
var zone_clean := PackedInt64Array()

var terrain_shader: Shader
var textures := {}
var noise_shape := FastNoiseLite.new()
var noise_detail := FastNoiseLite.new()

# Parça verileri: anahtar = Vector2i(cx, cz)
var chunks := {}          # Vector2i -> Dictionary {mesh, mat, dirt, leaf, dirt_img, leaf_img, dirt_tex, leaf_tex, modified}
var dirt_total := 0       # adadaki toplam kirli piksel
var dirt_clean := 0       # temizlenen kirli piksel
var leaf_total := 0
var leaf_clean := 0


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
	# Başlangıç: güney kıyısında kumsalın bittiği yer (bölgeler buna göre çizilir)
	var z := ISLAND_RADIUS * 1.1
	while z > 0.0 and height_at(0.0, z) < 1.8:
		z -= 1.0
	spawn_point = Vector3(0.0, height_at(0.0, z - 4.0), z - 4.0)
	for layer: String in LAYERS:
		var L: Dictionary = LAYERS[layer]
		raw_threshold[layer] = int(255.0 * (float(L["bias"]) + (CLEAN_THRESHOLD / 255.0 - 0.5) / float(L["contrast"])))
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


func _build_chunk(c: Vector2i) -> void:
	var origin := chunk_origin(c)
	var step := CHUNK_SIZE / float(VERTS - 1)
	var heights := PackedFloat32Array()
	heights.resize(VERTS * VERTS)
	var max_h := -1000.0
	var min_h := 1000.0
	for j in VERTS:
		for i in VERTS:
			var h: float = height_at(origin.x + i * step, origin.z + j * step)
			heights[j * VERTS + i] = h
			max_h = maxf(max_h, h)
			min_h = minf(min_h, h)
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
	for j in VERTS:
		for i in VERTS:
			zones[j * VERTS + i] = zone_of(origin.x + i * step, origin.z + j * step, heights[j * VERTS + i])
	var zimg_data := PackedByteArray()
	zimg_data.resize(VERTS * VERTS)
	for n in VERTS * VERTS:
		zimg_data[n] = zones[n] * 32
	var z_tex := ImageTexture.create_from_image(Image.create_from_data(VERTS, VERTS, false, Image.FORMAT_L8, zimg_data))

	var mat := ShaderMaterial.new()
	mat.shader = terrain_shader
	mat.set_shader_parameter("zone_map", z_tex)
	mat.set_shader_parameter("unlocked_zones", unlocked_mask)
	for k in textures:
		mat.set_shader_parameter(k, textures[k])
	mat.set_shader_parameter("chunk_origin", Vector2(origin.x, origin.z))
	mat.set_shader_parameter("chunk_size", CHUNK_SIZE)
	mat.set_shader_parameter("dirt_bias", LAYERS["dirt"]["bias"])
	mat.set_shader_parameter("dirt_contrast", LAYERS["dirt"]["contrast"])
	mat.set_shader_parameter("leaf_bias", LAYERS["leaf"]["bias"])
	mat.set_shader_parameter("leaf_contrast", LAYERS["leaf"]["contrast"])

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

	# Maskeler (gürültüden, hızlı: FastNoiseLite.get_image yerel kodda çalışır)
	var dirt := _noise_mask(c, 0.012)
	var leaf := _noise_mask(c, 0.02)
	var d_img := Image.create_from_data(MASK_RES, MASK_RES, false, Image.FORMAT_L8, dirt)
	var l_img := Image.create_from_data(MASK_RES, MASK_RES, false, Image.FORMAT_L8, leaf)
	var d_tex := ImageTexture.create_from_image(d_img)
	var l_tex := ImageTexture.create_from_image(l_img)
	mat.set_shader_parameter("dirt_mask", d_tex)
	mat.set_shader_parameter("leaf_mask", l_tex)
	chunks[c] = {"mesh": mi, "mat": mat, "dirt": dirt, "leaf": leaf, "dirt_img": d_img, "leaf_img": l_img,
		"dirt_tex": d_tex, "leaf_tex": l_tex, "modified": false, "heights": heights, "zones": zones}
	var dc := _count_est(c, "dirt", dirt)
	var lc := _count_est(c, "leaf", leaf)
	for zn in ZONE_NAMES.size():
		dirt_total += dc[zn]
		leaf_total += lc[zn]
		zone_total[zn] += dc[zn] + lc[zn]


func _noise_mask(c: Vector2i, freq: float) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = noise_shape.seed + int(freq * 1000.0)
	n.frequency = freq / (MASK_RES / CHUNK_SIZE)
	n.fractal_octaves = 3
	n.offset = Vector3(c.x * MASK_RES, c.y * MASK_RES, 0)
	var img := n.get_image(MASK_RES, MASK_RES)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


## Kirli piksel sayısını bölge bölge örnekleyerek tahmin et (her 8 pikselde bir; deniz/kumsal altı hariç)
func _count_est(c: Vector2i, layer: String, data: PackedByteArray) -> PackedInt64Array:
	var heights: PackedFloat32Array = chunks[c]["heights"]
	var zones: PackedByteArray = chunks[c]["zones"]
	var thr: int = raw_threshold[layer]
	var min_h: float = LAYERS[layer]["min_h"]
	var px_per_vert := float(MASK_RES) / float(VERTS - 1)
	var out := PackedInt64Array()
	out.resize(ZONE_NAMES.size())
	out.fill(0)
	for y in range(4, MASK_RES, 8):
		var j: int = mini(int(round(y / px_per_vert)), VERTS - 1)
		for x in range(4, MASK_RES, 8):
			var i: int = mini(int(round(x / px_per_vert)), VERTS - 1)
			if heights[j * VERTS + i] < min_h:
				continue
			if data[y * MASK_RES + x] >= thr:
				out[zones[j * VERTS + i]] += 64
	return out


## Bir noktada fırça ile temizle. layer: "dirt" ya da "leaf".
## Döner: temizlenen piksellerin bölge çarpanıyla ağırlıklı toplamı (para hesabı için). Kapalı bölgede temizlenmez.
func clean(pos: Vector3, radius: float, amount: float, layer: String) -> float:
	var cleaned := 0.0
	var c0 := chunk_of(pos.x - radius, pos.z - radius)
	var c1 := chunk_of(pos.x + radius, pos.z + radius)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var key := Vector2i(cx, cz)
			if not chunks.has(key):
				continue
			cleaned += _clean_chunk(key, pos, radius, amount, layer)
	return cleaned


func _clean_chunk(key: Vector2i, pos: Vector3, radius: float, amount: float, layer: String) -> float:
	var ch: Dictionary = chunks[key]
	var data: PackedByteArray = ch[layer]
	var zones: PackedByteArray = ch["zones"]
	var px_per_vert := float(MASK_RES) / float(VERTS - 1)
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
		for x in range(x0, x1 + 1):
			var dx: float = x - cx
			var dy: float = y - cy
			var dist := sqrt(dx * dx + dy * dy) / r_px
			if dist > 1.0:
				continue
			var zn: int = zones[mini(int(round(y / px_per_vert)), VERTS - 1) * VERTS + mini(int(round(x / px_per_vert)), VERTS - 1)]
			if (unlocked_mask >> zn) & 1 == 0:
				continue
			var idx: int = y * MASK_RES + x
			var old: int = data[idx]
			if old == 0:
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
		if layer == "dirt":
			dirt_clean += cleaned
		else:
			leaf_clean += cleaned
	return value


## Bir noktadaki maske değeri (0-255), parça yoksa 0
func sample(pos: Vector3, layer: String) -> int:
	var key := chunk_of(pos.x, pos.z)
	if not chunks.has(key):
		return 0
	var origin := chunk_origin(key)
	var ppm := MASK_RES / CHUNK_SIZE
	var x := clampi(int((pos.x - origin.x) * ppm), 0, MASK_RES - 1)
	var y := clampi(int((pos.z - origin.z) * ppm), 0, MASK_RES - 1)
	var data: PackedByteArray = chunks[key][layer]
	var L: Dictionary = LAYERS[layer]
	var heights: PackedFloat32Array = chunks[key]["heights"]
	var px_per_vert := float(MASK_RES) / float(VERTS - 1)
	var vi: int = mini(int(x / px_per_vert), VERTS - 1)
	var vj: int = mini(int(y / px_per_vert), VERTS - 1)
	if heights[vj * VERTS + vi] < float(L["min_h"]):
		return 0
	var eff := clampf((float(data[y * MASK_RES + x]) / 255.0 - float(L["bias"])) * float(L["contrast"]) + 0.5, 0.0, 1.0)
	return int(eff * 255.0)


func set_hint(v: float) -> void:
	for k in chunks:
		(chunks[k]["mat"] as ShaderMaterial).set_shader_parameter("hint", v)


## Kayıt: sadece değişen parçalar, sıkıştırılmış
func save_data() -> Dictionary:
	var out := {}
	for k in chunks:
		var ch: Dictionary = chunks[k]
		if ch["modified"]:
			var key_s := "%d,%d" % [k.x, k.y]
			out[key_s] = [
				Marshalls.raw_to_base64((ch["dirt"] as PackedByteArray).compress(FileAccess.COMPRESSION_DEFLATE)),
				Marshalls.raw_to_base64((ch["leaf"] as PackedByteArray).compress(FileAccess.COMPRESSION_DEFLATE)),
			]
	return out


func load_data(d: Dictionary) -> void:
	for key_s in d:
		var parts: PackedStringArray = str(key_s).split(",")
		if parts.size() != 2:
			continue
		var k := Vector2i(int(parts[0]), int(parts[1]))
		if not chunks.has(k):
			continue
		var arr: Array = d[key_s]
		var ch: Dictionary = chunks[k]
		for li in 2:
			var layer: String = "dirt" if li == 0 else "leaf"
			var raw := Marshalls.base64_to_raw(str(arr[li])).decompress(MASK_RES * MASK_RES, FileAccess.COMPRESSION_DEFLATE)
			if raw.size() != MASK_RES * MASK_RES:
				continue
			var before := _count_est(k, layer, ch[layer])
			var after := _count_est(k, layer, raw)
			for zn in ZONE_NAMES.size():
				var diff: int = before[zn] - after[zn]
				zone_clean[zn] += diff
				if layer == "dirt":
					dirt_clean += diff
				else:
					leaf_clean += diff
			ch[layer] = raw
			var img: Image = ch[layer + "_img"]
			img.set_data(MASK_RES, MASK_RES, false, Image.FORMAT_L8, raw)
			(ch[layer + "_tex"] as ImageTexture).update(img)
		ch["modified"] = true


func clean_fraction() -> float:
	return minf(1.0, float(dirt_clean + leaf_clean) / float(maxi(1, dirt_total + leaf_total)))
