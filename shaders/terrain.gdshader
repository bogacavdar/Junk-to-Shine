shader_type spatial;
render_mode cull_disabled;

// Parça bilgisi (her parça kendi maskelerini taşır)
uniform vec2 chunk_origin;
uniform float chunk_size = 40.0;
uniform sampler2D dirt_mask : filter_linear, repeat_disable;
uniform sampler2D leaf_mask : filter_linear, repeat_disable;
uniform sampler2D grass_mask : filter_linear, repeat_disable;
uniform sampler2D zone_map : filter_nearest, repeat_disable;     // 33 x 33, bölge * 32
uniform sampler2D surface_map : filter_linear, repeat_disable;   // 65 x 65, 1 = taş yol/meydan
uniform float hint = 0.0;
uniform int unlocked_zones = 2;
uniform float dirt_bias = 0.40;
uniform float dirt_contrast = 2.4;
uniform float leaf_bias = 0.55;
uniform float leaf_contrast = 2.8;
uniform float grass_bias = 0.32;
uniform float grass_contrast = 2.6;

// Temiz zemin: kum (kıyı), biçilmiş çim/toprak (iç kesim), kaya (yamaç), taş yol (yollar ve meydan)
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 sand_tint = vec3(1.0);
uniform float sand_tile = 3.0;
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 ground_tint = vec3(1.0);
uniform float ground_tile = 4.0;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_tile = 4.0;
uniform sampler2D pave_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float pave_tile = 2.0;

// Temizlenecek katmanlar: uzun kuru ot (tırpan), çamur (yıkayıcı), yaprak / deniz yosunu (tırmık)
uniform sampler2D dry_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 dry_tint = vec3(1.0);
uniform float dry_tile = 2.0;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float mud_tile = 2.5;
uniform sampler2D leaf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaf_height : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float leaf_tile = 1.8;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Köşe ızgarasıyla hizalı doku koordinatı (res x res doku, köşe i -> doku merkezi)
vec2 grid_uv(vec2 muv, float res) {
	return (muv * (res - 1.0) + 0.5) / res;
}

int zone_at(vec2 muv) {
	return int(round(texture(zone_map, grid_uv(clamp(muv, 0.0, 1.0), 33.0)).r * 255.0 / 32.0));
}

bool zone_open(int z) {
	return ((unlocked_zones >> z) & 1) == 1;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 muv = (world_pos.xz - chunk_origin) / chunk_size;
	float h = world_pos.y;
	float slope = 1.0 - world_nrm.y;
	float n = vnoise(world_pos.xz * 0.08);
	float n2 = vnoise(world_pos.xz * 0.9);

	// Temiz zemin karışımı
	vec2 suv = world_pos.xz / sand_tile;
	vec2 guv = world_pos.xz / ground_tile;
	vec2 ruv = world_pos.xz / rock_tile;
	float sand_w = 1.0 - smoothstep(1.2, 2.6, h + (n - 0.5) * 1.2);
	float rock_w = smoothstep(0.22, 0.42, slope + (n - 0.5) * 0.1);
	vec3 alb = mix(texture(ground_albedo, guv).rgb * ground_tint, texture(sand_albedo, suv).rgb * sand_tint, sand_w);
	vec3 nrm = mix(texture(ground_normal, guv).rgb, texture(sand_normal, suv).rgb, sand_w);
	alb = mix(alb, texture(rock_albedo, ruv).rgb, rock_w);
	nrm = mix(nrm, texture(rock_normal, ruv).rgb, rock_w);
	float rgh = mix(0.9, 0.95, sand_w);

	// Taş yol ve meydan (kenarları hafif düzensiz)
	float hard_raw = texture(surface_map, grid_uv(clamp(muv, 0.0, 1.0), 65.0)).r;
	float hard_w = smoothstep(0.35, 0.65, hard_raw + (n2 - 0.5) * 0.25);
	vec2 puv = world_pos.xz / pave_tile;
	alb = mix(alb, texture(pave_albedo, puv).rgb, hard_w);
	nrm = mix(nrm, texture(pave_normal, puv).rgb, hard_w);
	rgh = mix(rgh, 0.8, hard_w);

	// Su kenarında ıslak, koyu kum
	float wet = 1.0 - smoothstep(0.2, 0.9, h);
	alb *= 1.0 - wet * 0.35;
	rgh = mix(rgh, 0.2, wet);

	// Uzamış kuru ot (toprak zeminde; tırpanla biçilir)
	float gm = clamp((texture(grass_mask, muv).r - grass_bias) * grass_contrast + 0.5, 0.0, 1.0);
	gm *= (1.0 - hard_w) * smoothstep(1.4, 1.9, h) * (1.0 - rock_w * 0.7);
	float grass_t = smoothstep(0.12, 0.4, gm);
	vec2 dguv = world_pos.xz / dry_tile;
	alb = mix(alb, texture(dry_albedo, dguv).rgb * dry_tint, grass_t);
	nrm = mix(nrm, texture(dry_normal, dguv).rgb, grass_t);
	rgh = mix(rgh, 0.95, grass_t);

	// Çamur ve yosun (sadece taş yolda; yıkayıcıyla temizlenir)
	float d = clamp((texture(dirt_mask, muv).r - dirt_bias) * dirt_contrast + 0.5, 0.0, 1.0);
	d *= hard_w * smoothstep(0.05, 0.35, h);
	float t = smoothstep(0.12, 0.4, d);
	vec2 duv = world_pos.xz / mud_tile;
	alb = mix(alb, texture(mud_albedo, duv).rgb, t);
	nrm = mix(nrm, texture(mud_normal, duv).rgb, t);
	rgh = mix(rgh, 0.92, t);

	// Yaprak ve dal döküntüsü; kumsalda koyu yeşil-kahve deniz yosunu (tırmıkla toplanır)
	vec2 luv = world_pos.xz / leaf_tile;
	float lm = clamp((texture(leaf_mask, muv).r - leaf_bias) * leaf_contrast + 0.5, 0.0, 1.0);
	lm *= smoothstep(0.25, 0.6, h);
	float lh = texture(leaf_height, luv).r;
	float leaf_t = smoothstep(0.45, 0.62, lm * 1.15 - (1.0 - lh) * 0.45);
	vec3 leaf_col = texture(leaf_albedo, luv).rgb * mix(vec3(1.0), vec3(0.38, 0.46, 0.27), sand_w);
	alb = mix(alb, leaf_col, leaf_t);
	nrm = mix(nrm, texture(leaf_normal, luv).rgb, leaf_t);
	rgh = mix(rgh, mix(0.85, 0.35, sand_w), leaf_t);

	// Kapalı bölge: soluk ve karanlık, sınırında turuncu şerit
	int zone = zone_at(muv);
	if (zone > 0 && !zone_open(zone)) {
		float g = dot(alb, vec3(0.3, 0.59, 0.11));
		alb = mix(alb, vec3(g), 0.75) * 0.45;
		float ts = 1.0 / 32.0;
		bool edge = false;
		for (int k = 0; k < 4; k++) {
			vec2 o = vec2(0.0, -ts);
			if (k == 0) { o = vec2(ts, 0.0); }
			else if (k == 1) { o = vec2(-ts, 0.0); }
			else if (k == 2) { o = vec2(0.0, ts); }
			int nz = zone_at(muv + o);
			if (nz > 0 && zone_open(nz)) { edge = true; }
		}
		if (edge) {
			float stripe = step(0.5, fract((world_pos.x + world_pos.z) * 0.5));
			alb = mix(alb, mix(vec3(0.9, 0.45, 0.05), vec3(0.08), stripe), 0.85);
		}
	}

	ALBEDO = alb;
	NORMAL_MAP = nrm;
	ROUGHNESS = rgh;
	SPECULAR = 0.45;
	EMISSION = vec3(1.0, 0.55, 0.1) * max(max(t, grass_t * 0.5), leaf_t * 0.6) * hint * (0.35 + 0.65 * (0.5 + 0.5 * sin(TIME * 4.0))) * 0.5;
}
