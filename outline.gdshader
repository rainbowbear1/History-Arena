// Outline for answer soldiers: draws each body part again, grown by a fixed world-space width and
// with front faces culled, so only a coloured rim shows around the silhouette. Used as
// material_overlay. Parts are primitive meshes centred on their origin, so growing each vertex
// away from the centre keeps corners closed.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 color : source_color = vec4(0.95, 0.15, 0.1, 1.0);
uniform float width = 0.045;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	VERTEX += sign(VERTEX) * width / max(scale, vec3(0.001));
}

void fragment() {
	ALBEDO = color.rgb;
}
