shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Deniz: üst üste binen dalgalar, derinliğe göre renk, kıyıda köpük
uniform vec3 deep_color : source_color = vec3(0.02, 0.1, 0.14);
uniform vec3 shallow_color : source_color = vec3(0.12, 0.38, 0.4);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.95);
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform float gloom = 1.0;   // 1 = kasvetli (gri deniz), 0 = güneşli

varying vec3 wpos;

vec3 wave(vec2 p, vec2 dir, float freq, float speed, float amp) {
	float ph = dot(p, dir) * freq + TIME * speed;
	float c = cos(ph) * amp * freq;
	// x: yükseklik, y/z: türevler
	return vec3(sin(ph) * amp, c * dir.x, c * dir.y);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 a = wave(w.xz, normalize(vec2(1.0, 0.3)), 0.12, 1.1, 0.28);
	vec3 b = wave(w.xz, normalize(vec2(-0.4, 1.0)), 0.23, 1.6, 0.13);
	vec3 c = wave(w.xz, normalize(vec2(0.7, -0.6)), 0.55, 2.3, 0.05);
	vec3 s = a + b + c;
	VERTEX.y += s.x;
	NORMAL = normalize(vec3(-s.y, 1.0, -s.z));
	wpos = w;
	wpos.y += s.x;
}

void fragment() {
	// Derinlik farkı: su yüzeyi ile altındaki zemin arasındaki mesafe
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float thickness = clamp(-world.z - (-VERTEX.z), 0.0, 100.0);

	float deep = smoothstep(0.0, 4.0, thickness);
	vec3 col = mix(shallow_color, deep_color, deep);
	col = mix(col, vec3(dot(col, vec3(0.33))) * 0.8, gloom * 0.5);

	// Kıyı köpüğü
	float foam = 1.0 - smoothstep(0.0, 0.7, thickness);
	foam *= 0.6 + 0.4 * sin(TIME * 2.0 + wpos.x * 0.5 + wpos.z * 0.3);
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.8);

	vec2 uv1 = wpos.xz * 0.05 + vec2(TIME * 0.02, TIME * 0.013);
	vec2 uv2 = wpos.xz * 0.09 - vec2(TIME * 0.017, -TIME * 0.011);
	NORMAL_MAP = normalize(texture(detail_normal, uv1).rgb + texture(detail_normal, uv2).rgb - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;

	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.12, gloom);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(0.55, 0.97, deep);
}
