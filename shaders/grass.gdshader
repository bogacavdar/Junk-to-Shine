shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Kuru, uzamış ot tutamları: köke doğru koyu, uca doğru açık; rüzgârda uçları sallanır.
// INSTANCE_CUSTOM.rgb = tutam rengi, .a = rastgele faz

uniform vec3 root_color : source_color = vec3(0.2, 0.19, 0.1);
uniform vec3 tip_color : source_color = vec3(0.6, 0.53, 0.32);
uniform float wind_strength = 0.14;
uniform float wind_speed = 1.6;
uniform float gloom = 0.0;   // kasvetli havada renkler solar

varying float tip;
varying vec3 tint;

void vertex() {
	tip = UV.y;
	tint = INSTANCE_CUSTOM.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.a * 6.2831;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + wp.x * 0.05);
	float sway = sin(TIME * wind_speed + wp.x * 0.35 + wp.z * 0.25 + phase) * wind_strength * gust;
	float k = tip * tip;
	VERTEX.x += sway * k;
	VERTEX.z += sway * 0.6 * k;
	// Yumuşak ışık: normal çoğunlukla yukarı baksın (yassı kartların sert gölgelenmesi olmasın)
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.75));
}

void fragment() {
	vec3 c = mix(root_color, tip_color, smoothstep(0.0, 1.0, tip)) * tint;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(g), gloom * 0.5);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = c * 0.45;
	AO = mix(0.45, 1.0, tip);
	AO_LIGHT_AFFECT = 0.6;
}
