shader_type sky;

// İki gökyüzü arasında geçiş: kasvetli (başlangıç) -> güneşli (temizlendikçe)
uniform sampler2D sky_gloomy : filter_linear;
uniform sampler2D sky_sunny : filter_linear;
uniform float sunny = 0.0;
uniform float gloomy_energy = 0.7;
uniform float sunny_energy = 1.0;
uniform float gloomy_desaturate = 0.0;   // ayrı kasvetli HDRI gelene kadar güneşliyi soldurmak için

void sky() {
	vec2 uv = vec2(atan(EYEDIR.x, -EYEDIR.z) / (2.0 * PI) + 0.5, acos(clamp(EYEDIR.y, -1.0, 1.0)) / PI);
	vec3 g = texture(sky_gloomy, uv).rgb;
	float lum = dot(g, vec3(0.3, 0.59, 0.11));
	g = mix(g, vec3(lum) * vec3(0.92, 0.95, 1.0), gloomy_desaturate) * gloomy_energy;
	vec3 s = texture(sky_sunny, uv).rgb * sunny_energy;
	COLOR = mix(g, s, sunny);
}
