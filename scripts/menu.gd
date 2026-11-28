extends Node3D
## Ana menü: arkada yavaşça dönen gökyüzü, solda oyun adı, sağda 3 kayıt yuvası.
## Dolu yuva: Oyna / Sil (iki kez onay). Boş yuva: ad yaz, Yeni oyun.

const HudScript := preload("res://scripts/hud.gd")
const Kayit := preload("res://scripts/kayit.gd")
const IslandScript := preload("res://scripts/island.gd")

var ui = null              # hud.gd'nin görünüm araçları (paneller, düğmeler, yazı tipleri)
var cam: Camera3D
var slot_box: VBoxContainer
var loading: Control
var first_focus: Control = null
var shot_dir := ""         # test: ekran görüntüsü
var frame := 0


func _ready() -> void:
	Kayit.migrate()
	_build_backdrop()
	ui = HudScript.new()
	ui.layer = 5
	add_child(ui)
	ui.init_style()
	_build_menu()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ekran="):
			shot_dir = a.substr(8)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Menü müziği: oyunun müziğinin iki katmanı birlikte
	for nm in ["muzik_taban", "muzik_melodi"]:
		var path := "res://assets/audio/%s.ogg" % nm
		if ResourceLoader.exists(path):
			var st: AudioStream = load(path)
			st.loop = true
			var ap := AudioStreamPlayer.new()
			ap.stream = st
			ap.volume_db = -10.0 if nm == "muzik_taban" else -14.0
			add_child(ap)
			ap.play()


func _build_backdrop() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := PanoramaSkyMaterial.new()
	var tex := "res://assets/textures/"
	psm.panorama = load(tex + ("sky_sunny.hdr" if ResourceLoader.exists(tex + "sky_sunny.hdr") else "sky_garden.hdr"))
	sky.sky_material = psm
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 70
	cam.rotation_degrees = Vector3(8, 0, 0)
	add_child(cam)
	cam.make_current()


func _process(delta: float) -> void:
	cam.rotation.y += delta * 0.025
	if shot_dir != "":
		frame += 1
		if frame == 20:
			get_viewport().get_texture().get_image().save_png(shot_dir.path_join("0_ana_menu.png"))
			print("Ekran görüntüsü kaydedildi: 0_ana_menu.png")
			get_tree().quit()


func _build_menu() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)

	# Hafif karartma: yazılar gökyüzünde okunsun
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.05, 0.04, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	# Sol: oyun adı, kısa tanıtım, çıkış
	var left: VBoxContainer = ui._vbox(26)
	left.position = Vector2(72, 0)
	left.size = Vector2(440, 720)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(left)
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size = Vector2(440, 0)
	title.add_theme_font_size_override("normal_font_size", 64)
	if ui.font_display != null:
		title.add_theme_font_override("normal_font", ui.font_display)
	title.add_theme_color_override("default_color", HudScript.TEXT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.text = "Junk to [color=#F2B84B]Shine[/color]"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(title)
	var tag: Label = ui._shadow(ui._label("Fırtınanın harap ettiği adayı karış karış temizle,\nkasvetli adayı yeniden güneşli bir cennete çevir.", 16, HudScript.TEXT_2, false, left))
	tag.add_theme_constant_override("line_spacing", 4)
	var quit_b: Button = ui._button("Oyundan çık", "outline", Vector2(220, 48), 16)
	quit_b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quit_b.pressed.connect(func() -> void: get_tree().quit())
	left.add_child(quit_b)

	# Sağ: kayıt yuvaları
	var pg: Array = ui._glass(24.0, 0.68, Vector4(26, 24, 26, 24))
	var panel: Control = pg[0]
	panel.custom_minimum_size = Vector2(600, 0)
	panel.position = Vector2(1280 - 72 - 600, 96)
	root.add_child(panel)
	var pv: VBoxContainer = ui._vbox(16, pg[1])
	ui._label("Kayıt yuvaları", 24, HudScript.TEXT, true, pv)
	slot_box = ui._vbox(12, pv)
	_refresh_slots()

	# Yükleniyor perdesi
	var lg: Array = ui._glass(999.0, 0.7, Vector4(28, 14, 28, 14))
	loading = lg[0]
	ui._label("Ada hazırlanıyor…", 22, HudScript.TEXT, true, lg[1])
	loading.position = Vector2(640 - 130, 330)
	loading.visible = false
	root.add_child(loading)


func _refresh_slots() -> void:
	for c in slot_box.get_children():
		c.queue_free()
	first_focus = null
	for n in range(1, Kayit.SLOTS + 1):
		_slot_card(n)
	_focus_later()


func _focus_later() -> void:
	await get_tree().process_frame
	if first_focus != null and is_instance_valid(first_focus):
		first_focus.grab_focus()


func _slot_card(n: int) -> void:
	var sm := Kayit.summary(n)
	var card := PanelContainer.new()
	var cs: StyleBoxFlat = ui._box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.08), 1, 16)
	cs.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", cs)
	slot_box.add_child(card)
	var row: HBoxContainer = ui._hbox(14, card)
	# Yuva numarası
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", ui._box(Color(HudScript.GOLD, 0.14) if sm["exists"] else Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 14))
	badge.custom_minimum_size = Vector2(52, 52)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bl: Label = ui._label(str(n), 22, HudScript.GOLD if sm["exists"] else HudScript.DIM, true, badge)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(badge)
	var info: VBoxContainer = ui._vbox(4, row)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if sm["exists"]:
		ui._label(sm["name"], 19, HudScript.TEXT, true, info)
		var zn: int = clampi(int(sm["zone"]), 0, 7)
		var zname: String = IslandScript.ZONE_NAMES[zn]
		ui._label("%s · ada %%%s temiz · %s para" % [zname, ("%.1f" % float(sm["pct"])).replace(".", ","), _fmt(float(sm["money"]))], 13, HudScript.GREEN_TEXT, false, info)
		ui._label("Oynama %s · son: %s" % [Kayit.fmt_duration(sm["play_time"]), Kayit.fmt_date(sm["last_played"])], 12, HudScript.MUTED, false, info)
		var del_b: Button = ui._button("Sil", "outline", Vector2(64, 44), 14, false)
		del_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		del_b.set_meta("armed", false)
		del_b.pressed.connect(func() -> void: _delete_pressed(n, del_b))
		row.add_child(del_b)
		var play_b: Button = ui._button("Oyna", "gold", Vector2(104, 44), 16)
		play_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		play_b.pressed.connect(func() -> void: _start(n, ""))
		row.add_child(play_b)
		if first_focus == null:
			first_focus = play_b
	else:
		ui._label("Boş yuva", 17, HudScript.MUTED, true, info)
		var name_in := LineEdit.new()
		name_in.placeholder_text = "Adanın adı"
		name_in.text = "Ada %d" % n
		name_in.max_length = 24
		name_in.custom_minimum_size = Vector2(0, 38)
		name_in.add_theme_font_size_override("font_size", 15)
		if ui.font_body != null:
			name_in.add_theme_font_override("font", ui.font_body)
		var ns: StyleBoxFlat = ui._box(Color(0, 0, 0, 0.25), Color(1, 1, 1, 0.18), 1, 10)
		ns.content_margin_left = 12
		ns.content_margin_right = 12
		var nf: StyleBoxFlat = ns.duplicate()
		nf.border_color = HudScript.GOLD
		name_in.add_theme_stylebox_override("normal", ns)
		name_in.add_theme_stylebox_override("focus", nf)
		name_in.add_theme_color_override("font_color", HudScript.TEXT)
		name_in.add_theme_color_override("caret_color", HudScript.GOLD)
		info.add_child(name_in)
		var new_b: Button = ui._button("Yeni oyun", "light", Vector2(132, 44), 15)
		new_b.size_flags_vertical = Control.SIZE_SHRINK_END
		new_b.pressed.connect(func() -> void: _start(n, name_in.text.strip_edges()))
		name_in.text_submitted.connect(func(_t: String) -> void: _start(n, name_in.text.strip_edges()))
		row.add_child(new_b)
		if first_focus == null:
			first_focus = new_b


func _delete_pressed(n: int, b: Button) -> void:
	if b.get_meta("armed"):
		Kayit.delete(n)
		_refresh_slots()
	else:
		b.set_meta("armed", true)
		b.text = "Emin misin?"
		b.custom_minimum_size = Vector2(120, 44)
		ui._style_button(b, "gold", 12)


func _start(n: int, new_name: String) -> void:
	if new_name == "" and not Kayit.summary(n)["exists"]:
		new_name = "Ada %d" % n
	Kayit.choose(n, new_name)
	loading.visible = true
	# Perde görünsün diye iki kare bekle, sonra adayı kur
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://main.tscn")


func _fmt(v: float) -> String:
	const SUF := ["", " B", " Mn", " Mr", " Tn", " Kn", " Kt"]
	if v < 1000.0:
		return str(int(floor(v)))
	var e := 0
	while v >= 1000.0 and e < SUF.size() - 1:
		v /= 1000.0
		e += 1
	var t: String = ("%d" % int(v)) if v >= 100.0 else (("%.1f" % v) if v >= 10.0 else ("%.2f" % v))
	return t.replace(".", ",") + SUF[e]
