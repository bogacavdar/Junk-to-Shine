shader_type canvas_item;
// Buzlu cam panel: arkadaki ekranı bulanıklaştırır, renk katar, köşeleri yuvarlar, ince kenar çizer
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 size = vec2(100.0, 100.0);
uniform float radius = 18.0;
uniform vec4 tint : source_color = vec4(0.047, 0.067, 0.059, 0.6);
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.10);
uniform float blur = 3.5;

void fragment() {
	vec2 p = UV * size;
	vec2 half_size = size * 0.5;
	float r = min(radius, min(half_size.x, half_size.y));
	vec2 q = abs(p - half_size) - (half_size - vec2(r));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	float inside = 1.0 - smoothstep(-0.75, 0.75, d);
	vec3 bg = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	vec3 col = mix(bg, tint.rgb, tint.a);
	float edge = 1.0 - smoothstep(0.0, 1.2, abs(d + 0.6));
	col = mix(col, border_color.rgb, border_color.a * edge);
	COLOR = vec4(col, inside);
}
