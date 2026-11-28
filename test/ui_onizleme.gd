extends "res://scripts/main.gd"
## Arayüz önizlemesi (test): 3D dünyayı kurmadan, gerçek oyun ekranının fotoğrafı üzerinde
## oyun içi ekranı, dükkânı ve menüyü çizer, ekran görüntülerini kaydeder.
## Çalıştırma: godot --path . res://test/ui_onizleme.tscn -- --ekran=/tmp/ekran

class FakeIsland:
	func zone_fraction(z: int) -> float:
		return [0.0, 0.42, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0][z]
	func zone_unlocked(z: int) -> bool:
		return z <= 1
	func total_clean() -> int:
		return 50790


var frame := 0


func _ready() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	var bg := TextureRect.new()
	bg.texture = load("res://test/onizleme_arka_plan.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_layer.add_child(bg)
	player = PlayerScript.new()
	add_child(player)
	player.set_physics_process(false)
	env = Environment.new()
	sun = DirectionalLight3D.new()
	island = FakeIsland.new()
	money = 12540.0
	shown_money = money
	income_total = 0.0
	bag = 9
	bag_value = 340.0
	current_zone = 1
	clean_pct = 0.8
	current_tool = TOOL_SCYTHE
	levels = {"scythe": 13, "scythe_w": 6, "broom": 8, "broom_w": 4, "pressure": 2, "nozzle": 1, "bag": 2, "robot": 3, "robot_p": 7, "scythe_t": 1}
	near_shop = false
	hud = HudScript.new()
	add_child(hud)
	hud.setup(self)
	_apply_levels()
	quest_index = 6
	quest_base = {}
	journal = [["Selin · telsiz", "Sesim geliyor mu? Fırtınadan beri adaya kimse çıkmadı. İskelenin etrafındaki kuru otlardan başla, tırpanı geniş savur."], ["Buluntu · Paslı anahtar", "Paslı bir anahtar. Nuri Dede'nin kulübesinin anahtarı olabilir."]]
	hud.show_message("Selin · telsiz", "Sahile fırtınadan kalma yosun vurmuş. Tırmığını Sv 12'ye çıkar, kum tekrar görünsün.")
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--ekran="):
			shot_dir = a.substr(8)
	if shot_dir == "":
		shot_dir = "user://onizleme"
	DirAccess.make_dir_recursive_absolute(shot_dir)


func _process(_delta: float) -> void:
	frame += 1
	income_total += 0.8
	match frame:
		20:
			_save_shot("1_oyun_ici.png")
			shop_open = true
			hud.set_shop_visible(true)
		40:
			_save_shot("2_dukkan_aletler.png")
			hud._set_shop_tab(2)
		48:
			_save_shot("2b_dukkan_makineler.png")
			hud._set_shop_tab(3)
		55:
			_save_shot("3_dukkan_bolgeler.png")
			shop_open = false
			hud.set_shop_visible(false)
			hud.set_pause_visible(true)
		75:
			_save_shot("4_menu_goruntu.png")
			hud._set_settings_tab(2)
		90:
			_save_shot("5_menu_kontroller.png")
			hud._show_journal(true)
		105:
			_save_shot("7_gorev_gunlugu.png")
			get_tree().quit()


func _physics_process(_delta: float) -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass


func apply_settings(_s: Dictionary) -> void:
	pass


func _set_shop_open(open: bool) -> void:
	shop_open = open
	hud.set_shop_visible(open)


func _toggle_pause() -> void:
	pass
