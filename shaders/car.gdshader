shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// INSTANCE_CUSTOM: x=初期位置, y=速度, z=道の長さ
varying vec3 lp;
varying vec3 icol;

void vertex() {
	float len = INSTANCE_CUSTOM.z;
	float s = mod(INSTANCE_CUSTOM.x + TIME * INSTANCE_CUSTOM.y, len) - len * 0.5;
	lp = VERTEX;
	VERTEX.z += s;
	icol = COLOR.rgb;
}

void fragment() {
	float lamp = step(abs(abs(lp.x) - 0.6), 0.22) * step(abs(lp.y + 0.15), 0.14);
	float front = step(2.0, lp.z);
	float back = step(lp.z, -2.0);
	float glass = step(0.15, lp.y) * (1.0 - front - back);
	ALBEDO = mix(icol, vec3(0.05, 0.06, 0.08), glass * 0.8);
	EMISSION = vec3(1.0, 0.95, 0.85) * lamp * front * 4.0 + vec3(1.0, 0.08, 0.04) * lamp * back * 2.5;
	ROUGHNESS = 0.5;
}
