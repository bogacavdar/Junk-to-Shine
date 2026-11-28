shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Fener huzmesi: kaynağa yakın parlak, uzaklaştıkça ve kenarlarda söner.
// half_len: CylinderMesh yüksekliğinin yarısı; üst uç (+y) kaynaktır.
uniform vec4 color : source_color = vec4(1.0, 0.88, 0.62, 1.0);
uniform float strength = 0.16;
uniform float half_len = 110.0;
varying float along;

void vertex() {
	along = clamp((VERTEX.y + half_len) / (2.0 * half_len), 0.0, 1.0);
}

void fragment() {
	float fade = pow(along, 3.0);
	float edge = abs(dot(NORMAL, VIEW));
	float soft = smoothstep(0.05, 0.7, edge);
	ALBEDO = color.rgb * fade * soft * strength;
	ALPHA = 1.0;
}
