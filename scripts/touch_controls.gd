extends CanvasLayer
## Telefon kontrolleri: sol yarıda sanal çubuk (yürü), sağ yarıda kaydırarak bakış,
## sağ altta eylem butonları. Sadece dokunmatik cihazlarda oluşturulur.

const STICK_RADIUS := 110.0
const LOOK_SENSITIVITY := 0.006

var player = null   # player.gd (add_look fonksiyonu var)
var move_index := -1
var look_index := -1
var move_origin := Vector2.ZERO
var stick_base: Panel
var stick_knob: Panel
var button_rects: Array[Rect2] = []
var interact_button: TouchScreenButton


func _ready() -> void:
	layer = 5
	stick_base = _circle_panel(STICK_RADIUS * 2.0, Color(1, 1, 1, 0.12))
	stick_knob = _circle_panel(90.0, Color(1, 1, 1, 0.35))
	stick_base.visible = false
	stick_knob.visible = false

	_add_button("KULLAN", "use_tool", Vector2(1090, 480), 150.0)
	_add_button("ALET", "tool_next", Vector2(1160, 340), 96.0)
	_add_button("KOŞ", "run", Vector2(960, 560), 96.0)
	interact_button = _add_button("DÜKKÂN", "interact", Vector2(960, 420), 96.0)
	_add_button("II", "pause", Vector2(1190, 16), 72.0)


func set_interact_visible(v: bool) -> void:
	interact_button.visible = v


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _on_button(t.position):
				return
			if t.position.x < 560.0 and move_index == -1:
				move_index = t.index
				move_origin = t.position
				stick_base.position = move_origin - stick_base.size * 0.5
				stick_knob.position = move_origin - stick_knob.size * 0.5
				stick_base.visible = true
				stick_knob.visible = true
			elif t.position.x >= 560.0 and look_index == -1:
				look_index = t.index
		else:
			if t.index == move_index:
				move_index = -1
				stick_base.visible = false
				stick_knob.visible = false
				_apply_move(Vector2.ZERO)
			elif t.index == look_index:
				look_index = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == move_index:
			var off := d.position - move_origin
			if off.length() > STICK_RADIUS:
				off = off.normalized() * STICK_RADIUS
			stick_knob.position = move_origin + off - stick_knob.size * 0.5
			_apply_move(off / STICK_RADIUS)
		elif d.index == look_index and player != null:
			player.add_look(d.relative * LOOK_SENSITIVITY)


func _apply_move(v: Vector2) -> void:
	_set_action("move_left", maxf(-v.x, 0.0))
	_set_action("move_right", maxf(v.x, 0.0))
	_set_action("move_up", maxf(-v.y, 0.0))
	_set_action("move_down", maxf(v.y, 0.0))


func _set_action(action: String, strength: float) -> void:
	if strength > 0.08:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _on_button(p: Vector2) -> bool:
	for r in button_rects:
		if r.has_point(p):
			return true
	return false


func _add_button(text: String, action: String, pos: Vector2, size: float) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.texture_normal = _circle_texture(int(size), Color(1, 1, 1, 0.22))
	b.texture_pressed = _circle_texture(int(size), Color(1, 1, 1, 0.45))
	b.action = action
	b.position = pos
	var lbl := Label.new()
	lbl.text = text
	lbl.size = Vector2(size, size)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18 if size < 120.0 else 24)
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	b.add_child(lbl)
	add_child(b)
	button_rects.append(Rect2(pos, Vector2(size, size)))
	return b


func _circle_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)
			var edge: float = 1.0 if dist > r - 4.0 else 0.0
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a * minf(1.0, color.a + edge * 0.35)))
	return ImageTexture.create_from_image(img)


func _circle_panel(diameter: float, color: Color) -> Panel:
	var p := Panel.new()
	p.size = Vector2(diameter, diameter)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(diameter * 0.5))
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p
