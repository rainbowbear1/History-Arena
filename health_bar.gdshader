shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Enemy health bar: a quad that always faces the camera. `ratio` is the health left; `trail` lags
// behind it so a hit shows as a pale strip that drains away.
uniform float ratio : hint_range(0.0, 1.0) = 1.0;
uniform float trail : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.85, 0.18, 0.12, 1.0);
uniform float border = 0.06;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 inner = (UV - vec2(border * 0.3, border)) / (1.0 - vec2(border * 0.6, border * 2.0));
	vec3 color = vec3(0.05);
	if (inner.x >= 0.0 && inner.x <= 1.0 && inner.y >= 0.0 && inner.y <= 1.0) {
		color = vec3(0.18);
		if (inner.x < ratio) {
			color = fill_color.rgb * (inner.y < 0.45 ? 1.15 : 0.9);
		} else if (inner.x < trail) {
			color = vec3(1.0, 0.92, 0.7);
		}
	}
	ALBEDO = color;
}
