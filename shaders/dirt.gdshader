shader_type spatial;
render_mode diffuse_burley;

// Kir maskesi: 1 = kirli, 0 = temiz. main.gd her karede günceller.
uniform sampler2D dirt_mask : filter_linear, repeat_disable;
uniform float area_size = 40.0;
uniform vec3 clean_a : source_color = vec3(0.80, 0.81, 0.77);
uniform vec3 clean_b : source_color = vec3(0.71, 0.73, 0.69);
uniform vec3 dirt_a : source_color = vec3(0.33, 0.25, 0.17);
uniform vec3 dirt_b : source_color = vec3(0.21, 0.24, 0.11);
uniform float hint = 0.0; // son lekeleri parlatma (0-1)

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / area_size + 0.5;
	float d = texture(dirt_mask, uv).r;

	// Temiz zemin: hafif renk farklı karolar + derz çizgileri
	vec2 tile = floor(world_pos.xz * 0.5);
	vec2 inside = fract(world_pos.xz * 0.5);
	float grout = step(0.95, max(inside.x, inside.y));
	vec3 clean = mix(clean_a, clean_b, hash(tile));
	clean = mix(clean, clean * 0.7, grout);

	// Kirli zemin: lekeli, iki tonlu
	float n = hash(floor(world_pos.xz * 3.0));
	vec3 dirt = mix(dirt_a, dirt_b, n);

	float t = smoothstep(0.12, 0.35, d);
	ALBEDO = mix(clean, dirt, t);
	ROUGHNESS = mix(0.3, 1.0, t);
	SPECULAR = mix(0.65, 0.2, t);
	EMISSION = vec3(1.0, 0.55, 0.1) * t * hint * (0.5 + 0.5 * sin(TIME * 5.0)) * 0.4;
}
