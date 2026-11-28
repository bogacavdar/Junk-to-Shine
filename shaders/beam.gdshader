shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Fener huzmesi: kaynağa yakın parlak, uzaklaştıkça ve kenarlarda söner
uniform vec4 color : source_color = vec4(1.0, 0.88, 0.62, 1.0);
uniform float strength = 0.35;

void fragment() {
	// CylinderMesh UV.y: 0 üst (ince uç, kaynak), 1 alt (geniş uç)
	float along = 1.0 - UV.y;
	float fade = pow(along, 2.2);
	float edge = abs(dot(NORMAL, VIEW));
	float soft = smoothstep(0.0, 0.6, edge);
	ALBEDO = color.rgb;
	ALPHA = clamp(fade * soft * strength, 0.0, 1.0);
}
