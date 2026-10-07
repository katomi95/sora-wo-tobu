shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

// 遠くの山並み。裾を地平線の色に溶かす
uniform vec3 base : source_color = vec3(0.12, 0.10, 0.18);
uniform vec3 hor_col : source_color = vec3(1.0, 0.55, 0.3);
uniform float haze = 0.6;
varying float hgt;

void vertex() {
	hgt = VERTEX.y;
}

void fragment() {
	float k = clamp(1.0 - hgt / 420.0, 0.0, 1.0);
	ALBEDO = mix(base, hor_col, k * haze * 0.7);
}
