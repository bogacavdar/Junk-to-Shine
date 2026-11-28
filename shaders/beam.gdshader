shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Fener huzmesi: kaynağa yakın parlak, uzaklaştıkça ve kenarlarda söner.
// half_len: CylinderMesh yüksekliğinin yarısı; üst uç (+y) kaynaktır.
uniform vec4 color : source_color = vec4(1.0, 0.9, 0.68, 1.0);
uniform float strength = 0.22;
uniform float half_len = 80.0;
varying float along;

void vertex() {
	along = clamp((VERTEX.y + half_len) / (2.0 * half_len), 0.0, 1.0);
}

void fragment() {
	float fade = along * along * along * smoothstep(0.0, 0.35, along);
	float edge = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float soft = smoothstep(0.1, 0.75, edge);
	ALBEDO = color.rgb;
	ALPHA = clamp(fade * soft * strength, 0.0, 1.0);
}
