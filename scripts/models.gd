extends RefCounted
## Hazır modelleri (GLB / FBX) yükleyip istenen boyuta getiren yardımcılar.
## Paketlerin birimleri farklı (cm / m), bu yüzden her modeli ölçüp ölçekliyoruz.

static var _cache := {}


## Modeli yükler, en büyük boyutu (ya da yüksekliği) `size` metre olacak şekilde ölçekler.
## Dönen düğümün orijini modelin taban merkezidir. Ölçeklenmiş boyut "dims" meta verisinde.
static func make(path: String, size: float, by_height: bool = false) -> Node3D:
	var scene: PackedScene = _cache.get(path)
	if scene == null:
		scene = load(path)
		_cache[path] = scene
	var holder := Node3D.new()
	var inst: Node3D = scene.instantiate()
	holder.add_child(inst)
	var box := aabb_of(inst)
	var dims := box.size
	var ref_size: float = dims.y if by_height else maxf(dims.x, maxf(dims.y, dims.z))
	var s := size / maxf(ref_size, 0.0001)
	var center := box.get_center()
	inst.position -= Vector3(center.x, box.position.y, center.z)
	holder.scale = Vector3.ONE * s
	holder.set_meta("dims", dims * s)
	return holder


## Bir düğüm ağacındaki görünür tüm mesh'lerin, düğümün ebeveyn uzayındaki sınır kutusu.
static func aabb_of(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[root, root.transform]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			if mi.mesh != null and mi.visible:
				var b: AABB = xf * mi.get_aabb()
				if first:
					result = b
					first = false
				else:
					result = result.merge(b)
		for c in n.get_children():
			if c is Node3D:
				var c3: Node3D = c
				stack.append([c3, xf * c3.transform])
	if first:
		result = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return result


## Gölge ayarı: küçük nesneler gölge düşürmesin (web'de performans için).
static func set_shadows(root: Node, enabled: bool) -> void:
	for c in root.get_children():
		if c is GeometryInstance3D:
			var g: GeometryInstance3D = c
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		set_shadows(c, enabled)


## Dokusu eksik modellere düz renk verir (tüm yüzeyler için).
static func tint(root: Node, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	_apply_override(root, mat)


static func _apply_override(root: Node, mat: Material) -> void:
	for c in root.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = mat
		_apply_override(c, mat)
