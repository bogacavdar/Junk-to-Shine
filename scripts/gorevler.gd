extends RefCounted
## Görevler ve hafif hikâye.
##
## Fırtına adayı darmadağın etmiş; feribotlar artık uğramıyor. Karşı kıyıdaki kooperatiften
## Selin telsizle yol gösterir. Adanın eski fener bekçisi Nuri Dede'nin defter sayfaları
## kirin altından tek tek çıkar. Son hedef: Fener Tepesi'ni temizleyip feneri yeniden yakmak.
##
## Her görev: [kimden, başlık, telsiz/defter metni, hedef türü, hedef, sayı, ödül, bölge]
## Hedef türleri:
##   zone   -> bölgenin oranı (sayı 0..1)        unlock -> bölge açık mı
##   done   -> bölge tertemiz (ödülü alındı)     level  -> yükseltme seviyesi
##   trash  -> bu görevde toplanan çöp           sell   -> bu görevde konteynerde satış
##   finds  -> toplam buluntu                    earn   -> bu görevde kazanılan para
## Ödül: sayı × bölgenin kazanç çarpanı × prim

const SELIN := "Selin · telsiz"
const NURI := "Nuri Dede'nin defteri"

const LIST := [
	# --- İskele
	[SELIN, "Hoş geldin", "Sesim geliyor mu? Fırtınadan beri adaya kimse çıkmadı. İskelenin etrafındaki kuru otlardan başla, tırpanı geniş savur.", "zone", 1, 0.08, 40.0, 1],
	[SELIN, "İlk yük", "Yerde bir sürü çöp var. Üstünden geçince çantana girer; dolunca iskeledeki konteynere götürüp sat.", "sell", 0, 1.0, 60.0, 1],
	[SELIN, "Bıçağı bile", "Konteynerin yanındaki dükkândan tırpanı geliştir. Keskin bir tırpan işini yarıya indirir.", "level", "scythe", 5.0, 80.0, 1],
	[SELIN, "Yaprak denizi", "Taşların üstü yaprak ve dal dolu. Tırmığa geç (2) ve iskeleyi süpür.", "level", "broom", 5.0, 100.0, 1],
	[NURI, "Defterin ilk sayfası", "Kirin altında bazen bir şeyler parlar. Dedektör sinyali ya da şans: iki buluntu çıkar.", "finds", 0, 2.0, 150.0, 1],
	[SELIN, "Sahile yol", "İskele toparlandı sayılır. Bölgenin dörtte üçünü temizle ya da dükkânın Bölgeler sekmesinden sahili hemen aç.", "unlock", 2, 1.0, 200.0, 1],
	# --- Sahil
	[SELIN, "Yosun sezonu", "Sahile fırtınadan kalma yosun vurmuş. Tırmığını Sv 12'ye çıkar, kum tekrar görünsün.", "level", "broom", 12.0, 120.0, 2],
	[SELIN, "Şezlonglar geri gelsin", "Sahilin yarısını temizle. Kooperatif, temiz kumsala yeni şezlong göndereceğini söylüyor.", "zone", 2, 0.5, 160.0, 2],
	[SELIN, "Çöp seferi", "Sahil şişe ve ambalaj dolu. Bu turda 40 çöp topla.", "trash", 0, 40.0, 120.0, 2],
	[NURI, "Islak sayfalar", "Dedenin defterinin sayfaları adaya dağılmış. Toplam dört buluntuya ulaş.", "finds", 0, 4.0, 200.0, 2],
	[SELIN, "Limana uzan", "Limandaki tekneler bizi bekliyor. Liman bölgesini aç.", "unlock", 3, 1.0, 250.0, 2],
	# --- Liman
	[SELIN, "Çamurlu rıhtım", "Rıhtım taşları çamura gömülmüş. Yıkayıcının basıncını Sv 10'a çıkar ve yolları parlat.", "level", "pressure", 10.0, 150.0, 3],
	[SELIN, "Elektrik süpürgesi", "Kooperatif bir elektrik süpürgesi yolladı, konteynerde. Dükkândan al; çöpü uzaktan çeker.", "level", "vacuum", 1.0, 200.0, 3],
	[SELIN, "Liman tertemiz", "Tekneciler limanı görünce gözlerine inanmayacak. Limanın tamamını temizle.", "done", 3, 1.0, 300.0, 3],
	[SELIN, "Köye çık", "Köy meydanında yaşlılar seni bekliyor. Köyü aç.", "unlock", 4, 1.0, 300.0, 3],
	# --- Köy
	[SELIN, "Meydan", "Köy meydanının yarısını temizle; kahveci masalarını yeniden dışarı çıkaracak.", "zone", 4, 0.5, 200.0, 4],
	[SELIN, "Kooperatif kasası", "Bu işten para kazanmadan devam edemeyiz. Bu görev boyunca toplam 400 B kazan.", "earn", 0, 400000.0, 250.0, 4],
	[NURI, "Fenerin anahtarı", "Defter: 'Anahtar, adanın bir köşesinde kirin altında.' Toplam yedi buluntuya ulaş.", "finds", 0, 7.0, 300.0, 4],
	[SELIN, "Tarlalara", "Köyün arkasındaki tarlalar diz boyu ot. Tarlaları aç.", "unlock", 5, 1.0, 350.0, 4],
	# --- Tarlalar
	[SELIN, "Usta tırpancı", "Bu otlar için usta işi tırpan lazım: tırpanı Sv 50'ye, kilometre taşının ötesine çıkar.", "level", "scythe", 50.0, 250.0, 5],
	[SELIN, "Hasat zamanı", "Tarlaların %60'ını temizle; köylüler yeniden ekim yapabilsin.", "zone", 5, 0.6, 300.0, 5],
	[SELIN, "Orman yolu", "Fener Tepesi'ne giden yol ormandan geçiyor. Ormanı aç.", "unlock", 6, 1.0, 400.0, 5],
	# --- Orman
	[NURI, "Son sayfa", "Defterin son sayfası ormanda bir yerde. Bütün buluntuları bul.", "finds", 0, 12.0, 400.0, 6],
	[SELIN, "Patika", "Ormanın yarısını temizle; tepeye çıkan patika açılsın.", "zone", 6, 0.5, 350.0, 6],
	[SELIN, "Tepeye", "Fener Tepesi seni bekliyor. Son bölgeyi aç.", "unlock", 7, 1.0, 500.0, 6],
	# --- Fener Tepesi
	[SELIN, "Feneri yak", "Fener Tepesi'ni tamamen temizle. Fener yanınca feribotlar yeniden uğrayacak.", "done", 7, 1.0, 1000.0, 7],
]

## Buluntuların altına yazılan defter notları (buluntu sırasıyla)
const FIND_NOTES := [
	"Eski bir bozuk para. Arkasında adanın eski feneri kazılı.",
	"Kayıp bir yüzük. İçinde 'N. ve S. — 1974' yazıyor.",
	"Paslı bir anahtar. Nuri Dede'nin kulübesinin anahtarı olabilir.",
	"Defter sayfası: 'Fırtına üç gün sürdü. Fenerin camları kırıldı, ışığı ben söndürdüm.'",
	"Bir oyuncak araba. Köyde çocuklar yazın iskeleden denize atlarmış.",
	"Antika bir cep saati. Hâlâ çalışıyor, dede her gece saat dokuzda feneri yakarmış.",
	"Defter sayfası: 'Liman boşaldı. Tekneler karşı kıyıya sığındı, dönmeleri için ışık lazım.'",
	"Gümüş bir kaşık. Köy kahvesinin damgası var.",
	"Defter sayfası: 'Fenerin yedek anahtarı tepedeki taşın altında. Kim bulursa feneri o yaksın.'",
	"Eski bir fotoğraf: fenerin önünde gülümseyen bir adam ve küçük bir kız. Arkasında 'Selin'le' yazıyor.",
	"Bir cam misket. Tarlaların kenarında bir çocuk oyununun parçası.",
	"Defter sayfası: 'Ada temizlenirse insanlar döner. Döndüklerinde fener yanıyor olsun.'",
]

const ENDING := "Fener yeniden yanıyor. Uzakta ilk feribotun düdüğü duyuluyor. Selin telsizden sesleniyor: 'Dedem de bunu görmek isterdi. Teşekkürler.'"


static func count() -> int:
	return LIST.size()


static func get_quest(i: int) -> Array:
	return LIST[i] if i >= 0 and i < LIST.size() else []


## Görevin şu anki değeri (hedefle karşılaştırmak için)
static func value(q: Array, game, base: Dictionary) -> float:
	match str(q[3]):
		"zone":
			return game.island.zone_fraction(int(q[4]))
		"unlock":
			return 1.0 if game.island.zone_unlocked(int(q[4])) else 0.0
		"done":
			return 1.0 if game.zones_done.has(int(q[4])) else game.island.zone_fraction(int(q[4])) / 0.97
		"level":
			return float(game.lvl(str(q[4])))
		"trash":
			return float(game.stat_trash - int(base.get("trash", 0)))
		"sell":
			return float(game.stat_sells - int(base.get("sells", 0)))
		"finds":
			return float(game.found_finds.size())
		"earn":
			return game.income_total - float(base.get("earn", 0.0))
	return 0.0


static func progress(q: Array, game, base: Dictionary) -> float:
	return clampf(value(q, game, base) / float(q[5]), 0.0, 1.0)


static func is_done(q: Array, game, base: Dictionary) -> bool:
	return value(q, game, base) >= float(q[5]) - 0.0001


## İlerleme yazısı: "%34" ya da "12 / 40"
static func progress_text(q: Array, game, base: Dictionary) -> String:
	var v := value(q, game, base)
	match str(q[3]):
		"zone":
			return "%%%d / %%%d" % [int(v * 100.0), int(float(q[5]) * 100.0)]
		"done":
			return "%%%d" % int(clampf(v, 0.0, 1.0) * 100.0)
		"unlock":
			return "Açık" if v >= 1.0 else "Kapalı"
		"level":
			return "Sv %d / %d" % [int(v), int(q[5])]
		"earn":
			return "%s / %s" % [game._fmt(maxf(v, 0.0)), game._fmt(float(q[5]))]
	return "%d / %d" % [int(minf(v, float(q[5]))), int(q[5])]


## Görev başlarken sayaçların o anki değerleri
static func make_base(game) -> Dictionary:
	return {"trash": game.stat_trash, "sells": game.stat_sells, "earn": game.income_total}


## Kartta görünen kısa hedef
static func objective_text(q: Array, game) -> String:
	var zn := ["Deniz", "İskele", "Sahil", "Liman", "Köy", "Tarlalar", "Orman", "Fener Tepesi"]
	match str(q[3]):
		"zone":
			return "%s bölgesinin %%%d'ini temizle" % [zn[int(q[4])], int(float(q[5]) * 100.0)]
		"unlock":
			return "%s bölgesini aç" % zn[int(q[4])]
		"done":
			return "%s bölgesini tamamen temizle" % zn[int(q[4])]
		"level":
			var nm := str(q[4])
			for u: Dictionary in game.upgrades:
				if u["id"] == q[4]:
					nm = u["name"]
			return "%s: Sv %d" % [nm, int(q[5])] if int(q[5]) > 1 else "%s satın al" % nm
		"trash":
			return "%d çöp topla" % int(q[5])
		"sell":
			return "Çantayı konteynerde sat"
		"finds":
			return "Toplam %d buluntu çıkar" % int(q[5])
		"earn":
			return "%s para kazan" % game._fmt(float(q[5]))
	return ""
