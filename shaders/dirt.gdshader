shader_type spatial;

// Kir maskesi: 1 = kirli, 0 = temiz. main.gd her karede günceller.
uniform sampler2D dirt_mask : filter_linear, repeat_disable;
uniform float area_size = 40.0;
uniform float hint = 0.0; // son lekeleri parlatma (0-1)

// Temiz zemin: beton döşeme taşları
uniform sampler2D clean_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D clean_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D clean_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float clean_tile = 2.4;   // dokunun bir tekrarı kaç metre

// Kir: iki doku, gürültüyle karışır (yapraklı çamur + toprak)
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float dirt_tile = 2.2;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 mask_uv = world_pos.xz / area_size + 0.5;
	float d = texture(dirt_mask, mask_uv).r;

	vec2 cuv = world_pos.xz / clean_tile;
	vec3 c_alb = texture(clean_albedo, cuv).rgb;
	vec3 c_nrm = texture(clean_normal, cuv).rgb;
	float c_rgh = texture(clean_rough, cuv).r;

	vec2 duv = world_pos.xz / dirt_tile;
	// İki kir dokusunu büyük ölçekli gürültüyle karıştır, tekrar hissini kır
	float n = value_noise(world_pos.xz * 0.12) * 0.7 + value_noise(world_pos.xz * 0.5) * 0.3;
	float soil_w = smoothstep(0.35, 0.65, n);
	vec3 m_alb = mix(texture(mud_albedo, duv).rgb, texture(soil_albedo, duv * 0.9 + 0.37).rgb, soil_w);
	vec3 m_nrm = mix(texture(mud_normal, duv).rgb, texture(soil_normal, duv * 0.9 + 0.37).rgb, soil_w);
	float m_rgh = mix(0.92, texture(soil_rough, duv * 0.9 + 0.37).r, soil_w);

	// Kirin kenarı biraz yumuşak ve yeni yıkanan yer hafif ıslak görünsün
	float t = smoothstep(0.12, 0.4, d);
	float wet_edge = smoothstep(0.0, 0.12, d) * (1.0 - t);

	ALBEDO = mix(c_alb * (1.0 - wet_edge * 0.25), m_alb, t);
	NORMAL_MAP = mix(c_nrm, m_nrm, t);
	ROUGHNESS = mix(mix(c_rgh, 0.25, wet_edge), m_rgh, t);
	SPECULAR = 0.5;
	EMISSION = vec3(1.0, 0.55, 0.1) * t * hint * (0.35 + 0.65 * (0.5 + 0.5 * sin(TIME * 4.0))) * 0.6;
}
