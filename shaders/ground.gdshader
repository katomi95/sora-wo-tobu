shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform float night = 0.0;
uniform vec3 hor_col : source_color = vec3(1.0, 0.55, 0.3);
uniform vec3 zen_col : source_color = vec3(0.2, 0.3, 0.5);
uniform vec3 sun_dir = vec3(-0.35, 0.08, -0.93);
uniform float sun_vis = 1.0;
uniform float river_z = -600.0;
uniform vec4 city = vec4(-640.0, 340.0, 640.0, -1460.0);

varying vec3 wp;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	vec2 q = mod(p - 30.0, 60.0);
	vec2 d = min(q, 60.0 - q);
	float rx = step(d.y, 7.0);
	float rz = step(d.x, 7.0);
	float road = max(rx, rz);
	float walk = max(step(d.y, 9.5), step(d.x, 9.5)) * (1.0 - road);
	float inside = step(city.x, p.x) * step(p.x, city.z) * step(p.y, city.y) * step(city.w, p.y);

	vec3 col = vec3(0.17, 0.17, 0.16) * (0.85 + 0.3 * vnoise(p * 0.2));
	col = mix(col, vec3(0.30, 0.29, 0.28), walk);
	col = mix(col, vec3(0.075, 0.075, 0.085), road);
	// 中央線と横断歩道
	float cl = rx * (1.0 - rz) * step(d.y, 0.12) * step(0.5, fract(p.x / 6.0));
	cl += rz * (1.0 - rx) * step(d.x, 0.12) * step(0.5, fract(p.y / 6.0));
	float zx = rz * step(7.5, d.y) * step(d.y, 10.5) * step(0.5, fract(p.x / 1.1)) * step(d.x, 6.5);
	float zz = rx * step(7.5, d.x) * step(d.x, 10.5) * step(0.5, fract(p.y / 1.1)) * step(d.y, 6.5);
	col = mix(col, vec3(0.6), clamp(cl + zx + zz, 0.0, 1.0) * 0.8);

	// 街の外は畑と林
	vec3 field = mix(vec3(0.12, 0.13, 0.08), vec3(0.07, 0.09, 0.05), vnoise(p * 0.01));
	col = mix(field, col, inside);

	// 川（橋の上は道路のまま）
	float rv = abs(p.y - river_z);
	float water = step(rv, 20.0) * (1.0 - rz * inside);
	vec3 em = vec3(0.0);
	if (water > 0.5) {
		vec3 vd = normalize(wp - CAMERA_POSITION_WORLD);
		vec2 rp = p * vec2(0.08, 0.35) + vec2(TIME * 0.15, TIME * 0.05);
		vec2 nn = vec2(vnoise(rp) - 0.5, vnoise(rp * 1.7 + 3.0) - 0.5) * 0.12;
		vec3 r = normalize(vec3(vd.x + nn.x, -vd.y, vd.z + nn.y));
		vec3 refl = mix(hor_col, zen_col, smoothstep(0.0, 0.5, r.y));
		float glint = pow(max(dot(r, normalize(sun_dir)), 0.0), 60.0) * sun_vis;
		col = vec3(0.02, 0.03, 0.04);
		em = refl * 0.55 + vec3(1.0, 0.6, 0.3) * glint * 2.5;
	} else {
		// 街灯のあかり溜まり
		float lx = abs(mod(p.x, 40.0) - 20.0);
		float lz = abs(mod(p.y, 40.0) - 20.0);
		float pool = exp(-(lx * lx + (d.y - 8.5) * (d.y - 8.5)) / 22.0) * step(d.y, 12.0);
		pool += exp(-(lz * lz + (d.x - 8.5) * (d.x - 8.5)) / 22.0) * step(d.x, 12.0);
		em = vec3(1.0, 0.72, 0.42) * pool * night * 0.35 * inside;
		em += vec3(0.5, 0.35, 0.25) * road * night * 0.05 * inside;
	}
	ALBEDO = col;
	EMISSION = em;
	ROUGHNESS = 0.95;
}
