shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// 洗濯物（上端を固定して下が揺れる）
uniform float wind = 1.0;
varying vec3 icol;

void vertex() {
	// 頂点色の a = 竿からの距離（0..1）
	float k = COLOR.a;
	VERTEX.z += sin(TIME * 2.3 + VERTEX.x * 1.3) * 0.14 * k * wind;
	VERTEX.x += sin(TIME * 1.7 + VERTEX.z * 0.5 + VERTEX.x) * 0.05 * k * wind;
	icol = COLOR.rgb;
}

void fragment() {
	ALBEDO = icol;
	ROUGHNESS = 0.9;
}
