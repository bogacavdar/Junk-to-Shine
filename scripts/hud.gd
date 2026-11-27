extends CanvasLayer
## Oyun arayüzü: oyun içi ekran, dükkân ve duraklatma/ayarlar menüsü.
## Tasarım: koyu buzlu cam paneller, güneş altını (para, seçim) ve yaprak yeşili (temizlik ilerlemesi).
## Oyun mantığı main.gd'de; bu dosya sadece gösterir ve düğmeleri oyuna iletir.

const GOLD := Color("#F2B84B")
const GREEN := Color("#7BD389")
const GREEN_TEXT := Color("#B9E6BF")
const TEXT := Color("#F4F1EA")
const TEXT_2 := Color("#E2DED4")
const MUTED := Color("#C9C4B8")
const DIM := Color("#8D897F")
const INK := Color("#141A17")

const ICON_DIR := "res://assets/ui/"
const TOOL_ICONS := ["tirpan", "tirmik", "yikayici", "supurge"]
const UPGRADE_ICON := {
	"scythe": "tirpan", "scythe_w": "tirpan", "broom": "tirmik", "broom_w": "tirmik",
	"pressure": "yikayici", "nozzle": "yikayici", "vacuum": "supurge",
	"bag": "canta", "shoes": "ayakkabi", "bonus": "prim",
}
const TAB_UPGRADES := [
	["scythe", "scythe_w", "broom", "broom_w", "pressure", "nozzle", "vacuum"],
	["bag", "shoes", "bonus"],
	[],   # Bölgeler
]
const SETTINGS_PATH := "user://ayarlar.cfg"
const IslandScript := preload("res://scripts/island.gd")

var game = null              # main.gd
var font_display: Font = null
var font_body: Font = null
var glass_shader: Shader

# Oyun içi ekran
var hud_root: Control
var money_label: Label
var rate_label: Label
var bag_text: Label
var bag_bar: ProgressBar
var zone_name: Label
var zone_bar: ProgressBar
var zone_pct: Label
var zone_mult: Label
var island_label: Label
var goal_panel: Control
var goal_title: Label
var goal_desc: Label
var goal_bar: ProgressBar
var crosshair: TextureRect
var tool_title: Label
var tool_slots: Array[Button] = []
var tool_slot_icons: Array[TextureRect] = []
var tool_slot_nums: Array[Label] = []
var prompt_chip: Control
var banner: Control
var banner_label: Label
var hints: Control

# Dükkân
var shop_root: Control
var shop_money: Label
var shop_tab := 0
var shop_tab_buttons: Array[Button] = []
var shop_grid: GridContainer
var shop_cards: Array = []     # her kart: {kind, id/zone, name, effect, bar, button, level}
var shop_close: Button

# Duraklatma / ayarlar
var pause_root: Control
var pause_sub: Label
var settings_tab := 0
var settings_tab_buttons: Array[Button] = []
var settings_pages: Array[Control] = []
var quality_buttons: Array[Button] = []
var settings := {
	"quality": 2, "draw": 300.0, "fov": 75.0, "sens": 5.0,
	"fullscreen": true, "fog": false, "volume": 0.8,
}
var value_labels := {}
var first_pause_button: Button

# Kazanç hızı (son birkaç saniye)
var income_samples: Array = []


func setup(g) -> void:
	game = g
	layer = 5
	glass_shader = load("res://shaders/glass.gdshader")
	font_display = _try_font(["res://assets/fonts/SpaceGrotesk-Variable.ttf"], 700)
	font_body = _try_font(["res://assets/fonts/Inter-Variable.ttf"], 450)
	_load_settings()
	if game.is_mobile and not FileAccess.file_exists(SETTINGS_PATH):
		settings["quality"] = 0
		settings["draw"] = 180.0
	_build_hud()
	_build_shop()
	_build_pause()
	apply_settings()


## Değişken yazı tipini istenen kalınlıkta yükle; dosya yoksa Godot'nun varsayılanı kalır
func _try_font(paths: Array, weight: int) -> Font:
	for p: String in paths:
		if ResourceLoader.exists(p):
			var fv := FontVariation.new()
			fv.base_font = load(p)
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
			return fv
	return null


# =====================================================================
# Yapı taşları
# =====================================================================

## Buzlu cam panel: arkası bulanık, köşeleri yuvarlak. İçerik döndürülen MarginContainer'a eklenir.
func _glass(radius: float, alpha: float = 0.6, pad: Vector4 = Vector4(16, 14, 16, 14)) -> Array:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = glass_shader
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("tint", Color(0.047, 0.067, 0.059, alpha))
	bg.material = mat
	bg.resized.connect(func() -> void: mat.set_shader_parameter("size", bg.size))
	panel.add_child(bg)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", int(pad.x))
	m.add_theme_constant_override("margin_top", int(pad.y))
	m.add_theme_constant_override("margin_right", int(pad.z))
	m.add_theme_constant_override("margin_bottom", int(pad.w))
	panel.add_child(m)
	return [panel, m]


func _label(text: String, size: int, color: Color, display := false, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var f := font_display if display else font_body
	if f != null:
		l.add_theme_font_override("font", f)
	if parent != null:
		parent.add_child(l)
	return l


func _shadow(l: Label) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 3)
	return l


func _bar(width: float, height: float, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(width, height)
	b.show_percentage = false
	b.max_value = 1.0
	b.step = 0.0001
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.14)
	bg.set_corner_radius_all(int(height * 0.5))
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(int(height * 0.5))
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(0)
	return s


## Düğme biçimleri: "gold" (alınabilir), "light" (ana), "outline" (ikincil), "dim" (alınamaz), "pill" / "pill_on" (sekme)
func _style_button(b: Button, kind: String, radius: int = 12) -> void:
	var normal: StyleBoxFlat
	var fc := TEXT
	match kind:
		"gold":
			normal = _box(GOLD, Color(0, 0, 0, 0), 0, radius)
			fc = Color("#2A1D05")
		"light", "pill_on":
			normal = _box(TEXT, Color(0, 0, 0, 0), 0, radius)
			fc = INK
		"accent":
			normal = _box(Color(GOLD, 0.14), GOLD, 2, radius)
		"green":
			normal = _box(Color(GREEN, 0.14), Color(GREEN, 0.5), 1, radius)
			fc = GREEN_TEXT
		"dim":
			normal = _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.14), 1, radius)
			fc = DIM
		_:
			normal = _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.18), 1, radius)
			fc = TEXT_2
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover.bg_color.lightened(0.12) if kind in ["gold", "light", "pill_on"] else Color(1, 1, 1, 0.10)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	focus.draw_center = false
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", focus)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(st, fc)
	b.focus_mode = Control.FOCUS_ALL


func _button(text: String, kind: String, size: Vector2, font_size: int = 15, display := true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", font_size)
	var f := font_display if display else font_body
	if f != null:
		b.add_theme_font_override("font", f)
	_style_button(b, kind, 17 if kind.begins_with("pill") else 12)
	return b


func _icon(name: String, size: float, color: Color = TEXT) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(ICON_DIR + name + ".svg")
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _hbox(sep: int, parent: Node = null) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	if parent != null:
		parent.add_child(h)
	return h


func _vbox(sep: int, parent: Node = null) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	if parent != null:
		parent.add_child(v)
	return v


func _keycap(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := _box(Color(0, 0, 0, 0.25), Color(1, 1, 1, 0.45), 1, 6)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	_label(text, 12, TEXT, true, p)
	return p


# =====================================================================
# Oyun içi ekran
# =====================================================================

func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_root)

	# Kenar gölgesi: üst ve altta hafif karartma (yazılar her zeminde okunsun)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.38))
	grad.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var top_shade := TextureRect.new()
	top_shade.texture = gt
	top_shade.stretch_mode = TextureRect.STRETCH_SCALE
	top_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_shade.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_shade.custom_minimum_size = Vector2(0, 160)
	top_shade.size = Vector2(1280, 160)
	top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(top_shade)

	# --- Sol üst: para ve çanta
	var mc: Array = _glass(18.0, 0.58)
	var money_panel: PanelContainer = mc[0]
	money_panel.position = Vector2(24, 24)
	money_panel.custom_minimum_size = Vector2(240, 0)
	hud_root.add_child(money_panel)
	var mv := _vbox(10, mc[1])
	var mrow := _hbox(10, mv)
	mrow.alignment = BoxContainer.ALIGNMENT_BEGIN
	var coin := _icon("para", 30, Color.WHITE)
	mrow.add_child(coin)
	money_label = _label("0", 30, TEXT, true, mrow)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(spacer)
	rate_label = _label("", 12, GREEN_TEXT, false, mrow)
	rate_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bv := _vbox(6, mv)
	var brow := _hbox(8, bv)
	_label("Çanta", 12, MUTED, false, brow)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(sp2)
	bag_text = _label("", 12, TEXT, false, brow)
	bag_bar = _bar(200, 6, GOLD)
	bv.add_child(bag_bar)

	# --- Üst orta: bölge şeridi
	var zc := CenterContainer.new()
	zc.position = Vector2(340, 24)
	zc.size = Vector2(600, 80)
	zc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(zc)
	var zv := _vbox(8, zc)
	zv.alignment = BoxContainer.ALIGNMENT_CENTER
	var zg: Array = _glass(999.0, 0.58, Vector4(18, 9, 18, 9))
	zv.add_child(zg[0])
	(zg[0] as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var zrow := _hbox(14, zg[1])
	zone_name = _label("İSKELE", 15, TEXT, true, zrow)
	zone_name.add_theme_constant_override("outline_size", 0)
	zone_bar = _bar(160, 6, GREEN)
	zone_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zrow.add_child(zone_bar)
	zone_pct = _label("%0", 14, TEXT, false, zrow)
	var chip := PanelContainer.new()
	var cs := _box(Color(0, 0, 0, 0), Color(GOLD, 0.45), 1, 999)
	cs.content_margin_left = 8
	cs.content_margin_right = 8
	cs.content_margin_top = 1
	cs.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", cs)
	zone_mult = _label("×1", 12, GOLD, false, chip)
	zrow.add_child(chip)
	island_label = _shadow(_label("", 12, TEXT_2, false, zv))
	island_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# --- Sağ üst: sıradaki bölge hedefi
	var gg: Array = _glass(18.0, 0.58)
	goal_panel = gg[0]
	goal_panel.custom_minimum_size = Vector2(252, 0)
	goal_panel.position = Vector2(1280 - 24 - 252, 24)
	hud_root.add_child(goal_panel)
	var gv := _vbox(6, gg[1])
	var gl := _label("SIRADAKİ BÖLGE", 11, GREEN_TEXT, false, gv)
	gl.add_theme_constant_override("line_spacing", 0)
	goal_title = _label("", 18, TEXT, true, gv)
	goal_desc = _label("", 12, MUTED, false, gv)
	goal_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_desc.custom_minimum_size = Vector2(220, 0)
	goal_bar = _bar(220, 6, GREEN)
	gv.add_child(goal_bar)

	# --- Orta: nişangâh
	crosshair = _icon("nisan", 30, Color.WHITE)
	crosshair.position = Vector2(640 - 15, 360 - 15)
	hud_root.add_child(crosshair)

	# --- Dükkân çağrısı (konteynerin yanında)
	var pg: Array = _glass(999.0, 0.6, Vector4(14, 8, 16, 8))
	prompt_chip = pg[0]
	var ph := _hbox(8, pg[1])
	if game.is_mobile:
		_label("DÜKKÂN düğmesine bas", 14, TEXT, true, ph)
	else:
		ph.add_child(_keycap("E"))
		_label("Dükkânı aç", 14, TEXT, true, ph)
	prompt_chip.position = Vector2(560, 470)
	prompt_chip.visible = false
	hud_root.add_child(prompt_chip)

	# --- Alt orta: alet çubuğu
	var tc := VBoxContainer.new()
	tc.add_theme_constant_override("separation", 10)
	tc.alignment = BoxContainer.ALIGNMENT_END
	tc.position = Vector2(640 - 170, 720 - 24 - 124)
	tc.size = Vector2(340, 124)
	hud_root.add_child(tc)
	tool_title = _shadow(_label("", 16, TEXT, true, tc))
	tool_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tg: Array = _glass(20.0, 0.58, Vector4(8, 8, 8, 8))
	(tg[0] as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tc.add_child(tg[0])
	var th := _hbox(8, tg[1])
	for i in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(68, 68)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: game.select_tool_from_ui(i))
		var ic := _icon(TOOL_ICONS[i], 36)
		ic.position = Vector2(16, 16)
		b.add_child(ic)
		var num := _label(str(i + 1), 11, MUTED, true, b)
		num.position = Vector2(7, 3)
		th.add_child(b)
		tool_slots.append(b)
		tool_slot_icons.append(ic)
		tool_slot_nums.append(num)

	# --- Sol alt: kısayollar (masaüstü)
	hints = _hbox(14)
	hints.position = Vector2(24, 720 - 28 - 22)
	if not game.is_mobile:
		for pair in [["E", "Dükkân"], ["ESC", "Menü"], ["1-4", "Alet"]]:
			var hh := _hbox(6, hints)
			hh.add_child(_keycap(pair[0]))
			_shadow(_label(pair[1], 12, TEXT_2, false, hh))
	hud_root.add_child(hints)

	# --- Bildirim şeridi (yeni bölge, bölge bitti)
	var bg: Array = _glass(999.0, 0.66, Vector4(28, 14, 28, 14))
	banner = bg[0]
	banner_label = _label("", 30, TEXT, true, bg[1])
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.visible = false
	hud_root.add_child(banner)


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	_update_income(delta)
	if hud_root.visible:
		_update_hud()
	if shop_root.visible:
		_update_shop()


func _update_income(delta: float) -> void:
	income_samples.append([delta, float(game.income_total)])
	var total_t := 0.0
	for s: Array in income_samples:
		total_t += float(s[0])
	while income_samples.size() > 2 and total_t > 5.0:
		total_t -= float(income_samples[0][0])
		income_samples.pop_front()


func _income_rate() -> float:
	if income_samples.size() < 2:
		return 0.0
	var t := 0.0
	for i in range(1, income_samples.size()):
		t += float(income_samples[i][0])
	var d: float = float(income_samples[-1][1]) - float(income_samples[0][1])
	return maxf(0.0, d / maxf(0.5, t))


func _update_hud() -> void:
	money_label.text = game._fmt(game.shown_money)
	var r := _income_rate()
	rate_label.text = ("+%s/sn" % game._fmt(r)) if r >= 0.5 else ""
	var cap: int = game.bag_capacity()
	bag_text.text = "%d / %d · değeri %s" % [game.bag, cap, game._fmt(game.bag_value)]
	bag_bar.value = float(game.bag) / float(maxi(1, cap))
	(bag_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color("#E8705A") if game.bag >= cap else GOLD

	var zn: int = game.current_zone
	var Isl = IslandScript
	if zn > 0:
		zone_name.text = str(Isl.ZONE_NAMES[zn]).to_upper()
		var f: float = game.island.zone_fraction(zn)
		zone_bar.value = f
		zone_pct.text = "%%%d" % int(f * 100.0)
		zone_mult.text = "×" + game._fmt_mult(Isl.ZONE_MULT[zn])
	else:
		zone_name.text = "DENİZ"
		zone_bar.value = 0.0
		zone_pct.text = ""
		zone_mult.text = "—"
	var m2: float = float(game.island.total_clean()) / 40.96
	island_label.text = "Ada %%%s temiz · %s m²" % [("%.1f" % game.clean_pct).replace(".", ","), game._fmt(m2)]

	var nz: int = game.next_locked_zone()
	goal_panel.visible = nz > 0
	if nz > 0:
		goal_title.text = "%s açılıyor" % Isl.ZONE_NAMES[nz]
		goal_desc.text = "%s bölgesinin %%%d'ini temizle ya da dükkândan aç" % [Isl.ZONE_NAMES[nz - 1], int(Isl.ZONE_AUTO * 100.0)]
		goal_bar.value = clampf(game.island.zone_fraction(nz - 1) / Isl.ZONE_AUTO, 0.0, 1.0)

	crosshair.visible = not game.shop_open
	prompt_chip.visible = game.near_shop and not game.shop_open
	var t: int = game.current_tool
	var lv := ""
	match t:
		0: lv = "Sv %d" % game.lvl("scythe")
		1: lv = "Sv %d" % game.lvl("broom")
		2: lv = "Sv %d" % game.lvl("pressure")
		3: lv = "Sv %d" % game.vacuum_level
	tool_title.text = "%s · %s" % [game.tool_names[t], lv]
	for i in 4:
		var locked: bool = i == 3 and game.vacuum_level == 0
		var kind := "accent" if i == t else ("dim" if locked else "outline")
		if tool_slots[i].get_meta("kind", "") != kind:
			tool_slots[i].set_meta("kind", kind)
			_style_button(tool_slots[i], kind, 14)
			tool_slots[i].focus_mode = Control.FOCUS_NONE
		tool_slot_icons[i].texture = load(ICON_DIR + ("kilit" if locked else TOOL_ICONS[i]) + ".svg")
		tool_slot_icons[i].modulate = TEXT if i == t else (DIM if locked else TEXT_2)
		tool_slot_nums[i].add_theme_color_override("font_color", GOLD if i == t else (DIM if locked else MUTED))


func show_banner(text: String) -> void:
	banner_label.text = text
	banner.visible = true
	banner.modulate.a = 0.0
	banner.reset_size()
	await get_tree().process_frame
	banner.position = Vector2(640 - banner.size.x * 0.5, 210)
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.0)
	tw.tween_property(banner, "modulate:a", 0.0, 0.8)
	tw.tween_callback(banner.hide)


# =====================================================================
# Dükkân
# =====================================================================

func _build_shop() -> void:
	shop_root = Control.new()
	shop_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_root.visible = false
	add_child(shop_root)
	# Arkadaki oyunu bulanıklaştır ve karart
	var back: Array = _glass(0.0, 0.45, Vector4.ZERO)
	(back[0] as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	((back[0] as PanelContainer).get_child(0).material as ShaderMaterial).set_shader_parameter("blur", 4.5)
	shop_root.add_child(back[0])

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_root.add_child(center)
	var pg: Array = _glass(24.0, 0.72, Vector4(26, 24, 26, 22))
	(pg[0] as Control).custom_minimum_size = Vector2(980, 0)
	center.add_child(pg[0])
	var v := _vbox(18, pg[1])

	var head := _hbox(16, v)
	_label("Dükkân", 28, TEXT, true, head)
	var tabs := _hbox(6, head)
	for i in 3:
		var tb := _button(["Aletler", "Genel", "Bölgeler"][i], "pill", Vector2(0, 36), 13, false)
		tb.add_theme_constant_override("h_separation", 0)
		var st: StyleBoxFlat = tb.get_theme_stylebox("normal")
		st.content_margin_left = 16
		st.content_margin_right = 16
		tb.pressed.connect(func() -> void: _set_shop_tab(i))
		tabs.add_child(tb)
		shop_tab_buttons.append(tb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_icon("para", 22, Color.WHITE))
	shop_money = _label("", 22, TEXT, true, head)
	shop_close = Button.new()
	shop_close.custom_minimum_size = Vector2(44, 44)
	_style_button(shop_close, "outline", 12)
	var xi := _icon("kapat", 18, TEXT_2)
	xi.position = Vector2(13, 13)
	shop_close.add_child(xi)
	shop_close.tooltip_text = "Kapat"
	shop_close.pressed.connect(func() -> void: game._set_shop_open(false))
	head.add_child(shop_close)

	shop_grid = GridContainer.new()
	shop_grid.columns = 2
	shop_grid.add_theme_constant_override("h_separation", 12)
	shop_grid.add_theme_constant_override("v_separation", 12)
	v.add_child(shop_grid)

	var foot := _hbox(8, v)
	_label("Her 10 seviyede güç iki katına çıkar · ince çubuk bir sonraki ×2'ye ne kadar kaldığını gösterir", 12, MUTED, false, foot)
	var sp3 := Control.new()
	sp3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp3)
	if not game.is_mobile:
		foot.add_child(_keycap("E"))
		_label("kapat", 12, MUTED, false, foot)
	_set_shop_tab(0)


func _set_shop_tab(i: int) -> void:
	shop_tab = i
	for k in shop_tab_buttons.size():
		var on := k == i
		_style_button(shop_tab_buttons[k], "pill_on" if on else "pill", 18)
		var st: StyleBoxFlat = shop_tab_buttons[k].get_theme_stylebox("normal")
		st.content_margin_left = 16
		st.content_margin_right = 16
	for c in shop_grid.get_children():
		c.queue_free()
	shop_cards.clear()
	if i < 2:
		for id: String in TAB_UPGRADES[i]:
			_add_upgrade_card(id)
	else:
		for zn in range(2, IslandScript.ZONE_NAMES.size()):
			_add_zone_card(zn)
	_update_shop()


func _card_shell(icon_name: String) -> Array:
	var card := PanelContainer.new()
	var cs := _box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.08), 1, 16)
	cs.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", cs)
	card.custom_minimum_size = Vector2(458, 0)
	var row := _hbox(14, card)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", _box(Color(GREEN, 0.14), Color(0, 0, 0, 0), 0, 14))
	tile.custom_minimum_size = Vector2(52, 52)
	var ic := _icon(icon_name, 28, GREEN_TEXT)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.add_child(ic)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tile)
	var info := _vbox(4, row)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := _hbox(8, info)
	var name_l := _label("", 15, TEXT, true, top)
	var lvl_l := _label("", 12, MUTED, false, top)
	lvl_l.size_flags_vertical = Control.SIZE_SHRINK_END
	var eff := _label("", 13, GREEN_TEXT, false, info)
	var bar := _bar(220, 4, GREEN)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(bar)
	var btn := _button("", "gold", Vector2(116, 44), 15)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(btn)
	shop_grid.add_child(card)
	return [name_l, lvl_l, eff, bar, btn]


func _add_upgrade_card(id: String) -> void:
	var idx := -1
	for k in game.upgrades.size():
		if game.upgrades[k]["id"] == id:
			idx = k
	if idx < 0:
		return
	var parts := _card_shell(UPGRADE_ICON.get(id, "prim"))
	var btn: Button = parts[4]
	btn.pressed.connect(func() -> void: game._on_shop_button(idx))
	shop_cards.append({"kind": "up", "idx": idx, "id": id, "name": parts[0], "lvl": parts[1], "eff": parts[2], "bar": parts[3], "btn": btn, "style": ""})


func _add_zone_card(zn: int) -> void:
	var parts := _card_shell("bolge")
	var btn: Button = parts[4]
	btn.pressed.connect(func() -> void: game._on_shop_button(game.upgrades.size()))
	shop_cards.append({"kind": "zone", "zone": zn, "name": parts[0], "lvl": parts[1], "eff": parts[2], "bar": parts[3], "btn": btn, "style": ""})


func _set_btn_style(c: Dictionary, kind: String) -> void:
	if c["style"] == kind:
		return
	c["style"] = kind
	_style_button(c["btn"], kind, 12)


func _update_shop() -> void:
	shop_money.text = game._fmt(game.money)
	var Isl = IslandScript
	for c: Dictionary in shop_cards:
		var btn: Button = c["btn"]
		if c["kind"] == "up":
			var u: Dictionary = game.upgrades[c["idx"]]
			var l: int = game.lvl(c["id"])
			(c["name"] as Label).text = u["name"]
			(c["lvl"] as Label).text = "Sv %d" % l
			(c["eff"] as Label).text = game.upgrade_effect(c["id"])
			var mx: int = u["max"]
			(c["bar"] as ProgressBar).value = (float(l) / float(mx)) if mx > 0 else (float(l % 10) / 10.0)
			if game.upgrade_maxed(c["idx"]):
				btn.text = "MAKS"
				btn.disabled = true
				_set_btn_style(c, "green")
			else:
				var price: float = game.upgrade_price(c["idx"])
				btn.text = game._fmt(price)
				var ok: bool = game.money >= price
				btn.disabled = not ok
				_set_btn_style(c, "gold" if ok else "dim")
		else:
			var zn: int = c["zone"]
			(c["name"] as Label).text = Isl.ZONE_NAMES[zn]
			(c["lvl"] as Label).text = "kazanç ×" + game._fmt_mult(Isl.ZONE_MULT[zn])
			var prev_f: float = game.island.zone_fraction(zn - 1)
			(c["bar"] as ProgressBar).value = 1.0 if game.island.zone_unlocked(zn) else clampf(prev_f / Isl.ZONE_AUTO, 0.0, 1.0)
			if game.island.zone_unlocked(zn):
				(c["eff"] as Label).text = "Açık · %%%d temiz" % int(game.island.zone_fraction(zn) * 100.0)
				btn.text = "Açık"
				btn.disabled = true
				_set_btn_style(c, "green")
			elif zn == game.next_locked_zone():
				(c["eff"] as Label).text = "%s %%%d / %%%d olunca açılır" % [Isl.ZONE_NAMES[zn - 1], int(prev_f * 100.0), int(Isl.ZONE_AUTO * 100.0)]
				var zp: float = Isl.ZONE_PRICE[zn]
				btn.text = game._fmt(zp)
				var ok2: bool = game.money >= zp
				btn.disabled = not ok2
				_set_btn_style(c, "gold" if ok2 else "dim")
			else:
				(c["eff"] as Label).text = "Önce %s açılmalı" % Isl.ZONE_NAMES[zn - 1]
				btn.text = "Kilitli"
				btn.disabled = true
				_set_btn_style(c, "dim")


func set_shop_visible(v: bool) -> void:
	shop_root.visible = v
	hud_root.visible = not v
	if v:
		_set_shop_tab(shop_tab)
		await get_tree().process_frame
		if shop_cards.size() > 0:
			(shop_cards[0]["btn"] as Button).grab_focus()
		else:
			shop_close.grab_focus()


# =====================================================================
# Duraklatma ve ayarlar
# =====================================================================

func _build_pause() -> void:
	pause_root = Control.new()
	pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.visible = false
	add_child(pause_root)
	var back: Array = _glass(0.0, 0.5, Vector4.ZERO)
	(back[0] as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	((back[0] as PanelContainer).get_child(0).material as ShaderMaterial).set_shader_parameter("blur", 5.0)
	pause_root.add_child(back[0])

	# Sol sütun: oyun adı ve ana düğmeler
	var left := _vbox(28)
	left.position = Vector2(72, 0)
	left.size = Vector2(360, 720)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_root.add_child(left)
	var tv := _vbox(6, left)
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size = Vector2(360, 0)
	title.add_theme_font_size_override("normal_font_size", 52)
	if font_display != null:
		title.add_theme_font_override("normal_font", font_display)
	title.add_theme_color_override("default_color", TEXT)
	title.text = "Junk to [color=#F2B84B]Shine[/color]"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(title)
	pause_sub = _label("Oyun duraklatıldı", 14, MUTED, false, tv)
	var bv := _vbox(10, left)
	first_pause_button = _pause_button(bv, "Devam et", "light", func() -> void: game._toggle_pause())
	_pause_button(bv, "Ayarlar", "outline", func() -> void: _focus_settings())
	_pause_button(bv, "Kaydet ve çık", "outline", func() -> void: game._save_and_quit())
	var ng := _pause_button(bv, "Yeni oyun başlat", "outline", func() -> void: _confirm_new_game())
	ng.set_meta("confirm", false)

	# Sağ: ayarlar paneli
	var sg: Array = _glass(24.0, 0.70, Vector4(28, 26, 28, 26))
	var sp: Control = sg[0]
	sp.custom_minimum_size = Vector2(600, 470)
	sp.position = Vector2(1280 - 72 - 600, 125)
	pause_root.add_child(sp)
	var sv := _vbox(22, sg[1])
	var sh := _hbox(8, sv)
	_label("Ayarlar", 24, TEXT, true, sh)
	var sp4 := Control.new()
	sp4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sp4)
	for i in 3:
		var tb := _button(["Görüntü", "Ses", "Kontroller"][i], "pill", Vector2(0, 34), 13, false)
		tb.pressed.connect(func() -> void: _set_settings_tab(i))
		sh.add_child(tb)
		settings_tab_buttons.append(tb)

	# Görüntü
	var pv := _vbox(18, sv)
	settings_pages.append(pv)
	var qv := _vbox(8, pv)
	_label("GRAFİK KALİTESİ", 12, GREEN_TEXT, false, qv)
	var qg := GridContainer.new()
	qg.columns = 4
	qg.add_theme_constant_override("h_separation", 8)
	qv.add_child(qg)
	for i in 4:
		var qb := _button(["Düşük", "Orta", "Yüksek", "Ultra"][i], "outline", Vector2(130, 44), 14, false)
		qb.pressed.connect(func() -> void:
			settings["quality"] = i
			_after_setting())
		qg.add_child(qb)
		quality_buttons.append(qb)
	_slider_row(pv, "Çizim mesafesi", "draw", 80.0, 600.0, 10.0, " m")
	_slider_row(pv, "Görüş açısı", "fov", 60.0, 100.0, 1.0, "°")
	_toggle_row(pv, "Tam ekran", "fullscreen")
	_toggle_row(pv, "Işık hüzmeleri ve sis", "fog")

	# Ses
	var av := _vbox(18, sv)
	settings_pages.append(av)
	_slider_row(av, "Genel ses", "volume", 0.0, 1.0, 0.05, "%")

	# Kontroller
	var kv := _vbox(14, sv)
	settings_pages.append(kv)
	_slider_row(kv, "Fare hassasiyeti", "sens", 1.0, 10.0, 0.5, "")
	var keys := GridContainer.new()
	keys.columns = 2
	keys.add_theme_constant_override("h_separation", 24)
	keys.add_theme_constant_override("v_separation", 8)
	kv.add_child(keys)
	for pair in [["WASD", "Yürü"], ["Shift", "Koş"], ["Sol tık", "Aleti kullan"], ["1  2  3  4", "Tırpan, tırmık, yıkayıcı, elk. süpürgesi"], ["E", "Dükkân (konteynerin yanında)"], ["ESC", "Menü"]]:
		var kh := _hbox(0, keys)
		kh.custom_minimum_size = Vector2(110, 0)
		kh.add_child(_keycap(pair[0]))
		_label(pair[1], 13, TEXT_2, false, keys)
	_label("Kontrolcü ve dokunmatik ekran da desteklenir.", 12, MUTED, false, kv)
	_set_settings_tab(0)


func _pause_button(parent: Node, text: String, kind: String, cb: Callable) -> Button:
	var b := _button(text, kind, Vector2(360, 52), 17)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var st: StyleBoxFlat = b.get_theme_stylebox("normal")
	st.content_margin_left = 20
	(b.get_theme_stylebox("hover") as StyleBoxFlat).content_margin_left = 20
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _confirm_new_game() -> void:
	# İki kez basılınca: ilk basış uyarır
	for b in pause_root.find_children("*", "Button", true, false):
		var bb := b as Button
		if bb.has_meta("confirm"):
			if bb.get_meta("confirm"):
				game._new_game()
			else:
				bb.set_meta("confirm", true)
				bb.text = "Emin misin? Tekrar bas: kayıt silinir"
				_style_button(bb, "gold", 12)


func _focus_settings() -> void:
	_set_settings_tab(settings_tab)
	settings_tab_buttons[settings_tab].grab_focus()


func _set_settings_tab(i: int) -> void:
	settings_tab = i
	for k in settings_pages.size():
		settings_pages[k].visible = k == i
		_style_button(settings_tab_buttons[k], "pill_on" if k == i else "pill", 14)
		var st: StyleBoxFlat = settings_tab_buttons[k].get_theme_stylebox("normal")
		st.content_margin_left = 14
		st.content_margin_right = 14


func _slider_row(parent: Node, text: String, key: String, mn: float, mx: float, step: float, unit: String) -> void:
	var h := _hbox(16, parent)
	var l := _label(text, 14, TEXT, false, h)
	l.custom_minimum_size = Vector2(160, 0)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(settings[key])
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 32)
	s.focus_mode = Control.FOCUS_ALL
	var grab := _box(GOLD, Color(0, 0, 0, 0), 0, 999)
	var track := _box(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 0, 999)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var filled := _box(GOLD, Color(0, 0, 0, 0), 0, 999)
	filled.content_margin_top = 3
	filled.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", filled)
	s.add_theme_stylebox_override("grabber_area_highlight", filled)
	var gimg := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	gimg.fill(Color(0, 0, 0, 0))
	for y in 18:
		for x in 18:
			var d := Vector2(x - 8.5, y - 8.5).length()
			if d < 8.5:
				gimg.set_pixel(x, y, TEXT if d < 6.5 else GOLD)
	var gtex := ImageTexture.create_from_image(gimg)
	s.add_theme_icon_override("grabber", gtex)
	s.add_theme_icon_override("grabber_highlight", gtex)
	h.add_child(s)
	var vl := _label("", 13, MUTED, false, h)
	vl.custom_minimum_size = Vector2(58, 0)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_labels[key] = [vl, unit]
	_refresh_value(key)
	s.value_changed.connect(func(v: float) -> void:
		settings[key] = v
		_refresh_value(key)
		_after_setting())


func _refresh_value(key: String) -> void:
	var vl: Label = value_labels[key][0]
	var unit: String = value_labels[key][1]
	var v: float = settings[key]
	if unit == "%":
		vl.text = "%%%d" % int(round(v * 100.0))
	elif key == "sens":
		vl.text = ("%.1f" % v).replace(".", ",")
	else:
		vl.text = "%d%s" % [int(v), unit]


func _toggle_row(parent: Node, text: String, key: String) -> void:
	var h := _hbox(16, parent)
	h.custom_minimum_size = Vector2(0, 40)
	var l := _label(text, 14, TEXT, false, h)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cb := CheckButton.new()
	cb.button_pressed = bool(settings[key])
	cb.focus_mode = Control.FOCUS_ALL
	cb.add_theme_icon_override("checked", _toggle_tex(true))
	cb.add_theme_icon_override("unchecked", _toggle_tex(false))
	cb.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	cb.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	cb.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	var fs := _box(Color(0, 0, 0, 0), GOLD, 2, 999)
	fs.draw_center = false
	cb.add_theme_stylebox_override("focus", fs)
	cb.toggled.connect(func(on: bool) -> void:
		settings[key] = on
		_after_setting())
	h.add_child(cb)


func _toggle_tex(on: bool) -> ImageTexture:
	var w := 44
	var hgt := 24
	var img := Image.create(w, hgt, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bg := GREEN if on else Color(1, 1, 1, 0.18)
	var knob := TEXT if on else MUTED
	var kx := 32.0 if on else 12.0
	for y in hgt:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(px.x, 12.0, 32.0)
			if px.distance_to(Vector2(cx, 12.0)) <= 12.0:
				img.set_pixel(x, y, bg)
			if px.distance_to(Vector2(kx, 12.0)) <= 9.0:
				img.set_pixel(x, y, knob)
	return ImageTexture.create_from_image(img)


func _after_setting() -> void:
	apply_settings()
	_save_settings()


func apply_settings() -> void:
	for k in quality_buttons.size():
		_style_button(quality_buttons[k], "accent" if k == int(settings["quality"]) else "outline", 12)
	game.apply_settings(settings)


func set_pause_visible(v: bool) -> void:
	pause_root.visible = v
	hud_root.visible = not v
	if v:
		pause_sub.text = "Oyun duraklatıldı · %s, %%%d" % [IslandScript.ZONE_NAMES[maxi(1, game.current_zone)], int(game.island.zone_fraction(maxi(1, game.current_zone)) * 100.0)]
		for b in pause_root.find_children("*", "Button", true, false):
			var bb := b as Button
			if bb.has_meta("confirm") and bb.get_meta("confirm"):
				bb.set_meta("confirm", false)
				bb.text = "Yeni oyun başlat"
				_style_button(bb, "outline", 12)
		await get_tree().process_frame
		first_pause_button.grab_focus()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cf.get_value("ayarlar", k, settings[k])


func _save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("ayarlar", k, settings[k])
	cf.save(SETTINGS_PATH)
