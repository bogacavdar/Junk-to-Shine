shader_type spatial;
render_mode cull_disabled;

// Parça bilgisi (her parça kendi maskesini taşır)
uniform vec2 chunk_origin;
uniform float chunk_size = 40.0;
uniform sampler2D dirt_mask : filter_linear, repeat_disable;
uniform sampler2D leaf_mask : filter_linear, repeat_disable;
uniform float hint = 0.0;
uniform sampler2D zone_map : filter_nearest, repeat_disable;
uniform int unlocked_zones = 2;
uniform float dirt_bias = 0.42;
uniform float dirt_contrast = 2.4;
uniform float leaf_bias = 0.55;
uniform float leaf_contrast = 2.8;

// Temiz zemin türleri: kum (kıyı), toprak/çim (düzlük), kaya (yamaç)
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

// Kir (yıkayıcı) ve yaprak (süpürge) katmanları
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
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
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
	// Su kenarında ıslak, koyu kum
	float wet = 1.0 - smoothstep(0.2, 0.9, h);
	alb *= 1.0 - wet * 0.35;
	rgh = mix(rgh, 0.2, wet);

	// Kir katmanı
	float d = clamp((texture(dirt_mask, muv).r - dirt_bias) * dirt_contrast + 0.5, 0.0, 1.0);
	d *= smoothstep(0.05, 0.35, h);   // deniz altında kir yok
	float t = smoothstep(0.12, 0.4, d);
	vec2 duv = world_pos.xz / mud_tile;
	alb = mix(alb, texture(mud_albedo, duv).rgb, t);
	nrm = mix(nrm, texture(mud_normal, duv).rgb, t);
	rgh = mix(rgh, 0.92, t);

	// Yaprak katmanı (yükseklik haritasıyla doğal kenar)
	vec2 luv = world_pos.xz / leaf_tile;
	float lm = clamp((texture(leaf_mask, muv).r - leaf_bias) * leaf_contrast + 0.5, 0.0, 1.0);
	lm *= smoothstep(1.1, 1.6, h);    // kumsalda yaprak yok
	float lh = texture(leaf_height, luv).r;
	float leaf_t = smoothstep(0.45, 0.62, lm * 1.15 - (1.0 - lh) * 0.45);
	alb = mix(alb, texture(leaf_albedo, luv).rgb, leaf_t);
	nrm = mix(nrm, texture(leaf_normal, luv).rgb, leaf_t);
	rgh = mix(rgh, 0.85, leaf_t);

	// Kapalı bölge: soluk ve karanlık, sınırında turuncu şerit
	int zone = int(round(texture(zone_map, muv).r * 255.0 / 32.0));
	if (zone > 0 && ((unlocked_zones >> zone) & 1) == 0) {
		float g = dot(alb, vec3(0.3, 0.59, 0.11));
		alb = mix(alb, vec3(g), 0.75) * 0.45;
		vec2 ts = vec2(1.0 / 33.0);
		bool edge = false;
		for (int k = 0; k < 4; k++) {
			vec2 o = (k == 0) ? vec2(ts.x, 0.0) : (k == 1) ? vec2(-ts.x, 0.0) : (k == 2) ? vec2(0.0, ts.y) : vec2(0.0, -ts.y);
			int nz = int(round(texture(zone_map, clamp(muv + o, 0.0, 1.0)).r * 255.0 / 32.0));
			if (nz > 0 && ((unlocked_zones >> nz) & 1) == 1) { edge = true; }
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
	EMISSION = vec3(1.0, 0.55, 0.1) * max(t, leaf_t * 0.6) * hint * (0.35 + 0.65 * (0.5 + 0.5 * sin(TIME * 4.0))) * 0.5;
}
