extends RefCounted
## Kayıt yuvaları: 3 ayrı ada kaydı (user://kayit_1.json ...).
## Ana menü yuvayı Engine meta'sına yazar, oyun oradan okur.

const SLOTS := 3
const OLD_PATH := "user://ada_kayit.json"


static func path(n: int) -> String:
	return "user://kayit_%d.json" % n


static func current_slot() -> int:
	return int(Engine.get_meta("kayit_yuvasi", 1))


static func pending_name() -> String:
	return str(Engine.get_meta("kayit_adi", ""))


static func choose(n: int, new_name: String = "") -> void:
	Engine.set_meta("kayit_yuvasi", n)
	Engine.set_meta("kayit_adi", new_name)


## Eski tek kayıt dosyası varsa 1. yuvaya taşı (kaybolmasın)
static func migrate() -> void:
	if FileAccess.file_exists(OLD_PATH) and not FileAccess.file_exists(path(1)):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(OLD_PATH), ProjectSettings.globalize_path(path(1)))


static func read(n: int) -> Dictionary:
	if not FileAccess.file_exists(path(n)):
		return {}
	var f := FileAccess.open(path(n), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func delete(n: int) -> void:
	if FileAccess.file_exists(path(n)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path(n)))


## Menüde gösterilecek özet
static func summary(n: int) -> Dictionary:
	var d := read(n)
	if d.is_empty():
		return {"exists": false}
	var sm: Dictionary = d.get("summary", {})
	return {
		"exists": true,
		"name": str(d.get("name", "Ada %d" % n)),
		"play_time": float(d.get("play_time", 0.0)),
		"last_played": int(d.get("last_played", 0)),
		"money": float(d.get("money", 0.0)),
		"zone": int(sm.get("zone", 1)),
		"pct": float(sm.get("pct", 0.0)),
	}


static func fmt_duration(sec: float) -> String:
	var m := int(sec / 60.0)
	if m < 60:
		return "%d dk" % m
	return "%d sa %d dk" % [m / 60, m % 60]


static func fmt_date(unix: int) -> String:
	if unix <= 0:
		return "—"
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var t := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%02d.%02d.%d %02d:%02d" % [t["day"], t["month"], t["year"], t["hour"], t["minute"]]
