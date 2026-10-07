shader_type sky;

// 0 = 夕焼け、1 = 夜
uniform float tod = 0.0;
uniform vec3 sun_dir = vec3(-0.35, 0.08, -0.93);

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float t = tod;
	vec3 sd = normalize(sun_dir);
	float sdot = max(dot(d, sd), 0.0);
	float hh = max(d.y, 0.0);

	vec3 zen = mix(vec3(0.16, 0.24, 0.50), vec3(0.012, 0.02, 0.06), smoothstep(0.0, 0.85, t));
	vec3 mid = mix(vec3(0.62, 0.42, 0.58), vec3(0.035, 0.045, 0.11), smoothstep(0.0, 0.9, t));
	vec3 hor = mix(vec3(1.0, 0.55, 0.28), vec3(0.11, 0.10, 0.19), smoothstep(0.0, 0.95, t));
	hor = mix(hor, vec3(0.55, 0.25, 0.32), smoothstep(0.35, 0.6, t) * (1.0 - smoothstep(0.6, 0.95, t)) * 0.6);

	vec3 col = mix(hor, mid, smoothstep(0.0, 0.2, hh));
	col = mix(col, zen, smoothstep(0.12, 0.75, hh));

	// 太陽の方角の地平線だけ赤く燃える
	vec2 dh = normalize(d.xz + vec2(1e-5));
	vec2 sh = normalize(sd.xz);
	float az = max(dot(dh, sh), 0.0);
	float glow = pow(az, 4.0) * exp(-hh * 7.0);
	col += vec3(1.0, 0.42, 0.12) * glow * (1.0 - smoothstep(0.0, 0.85, t)) * 0.9;
	col += vec3(0.30, 0.10, 0.16) * glow * smoothstep(0.5, 1.0, t) * 0.6;
	float vis = 1.0 - smoothstep(0.2, 0.55, t);
	col += vec3(1.0, 0.8, 0.5) * smoothstep(0.9994, 0.99975, sdot) * 4.0 * vis;
	col += vec3(1.0, 0.55, 0.25) * pow(sdot, 120.0) * 1.2 * vis;
	col += vec3(1.0, 0.5, 0.25) * pow(sdot, 12.0) * 0.25 * (1.0 - t);

	if (d.y < 0.0) {
		col = mix(hor * 0.8, hor * 0.35, smoothstep(0.0, -0.25, d.y));
	}

	// 雲
	if (d.y > 0.005) {
		vec2 uv = d.xz / (d.y + 0.06) * 0.9 + vec2(TIME * 0.0015, TIME * 0.0008);
		float c = fbm(uv * 1.2);
		float cover = smoothstep(0.48, 0.78, c) * smoothstep(0.005, 0.12, d.y);
		float shade = fbm(uv * 2.4 + vec2(3.1, 1.2));
		vec3 lit = mix(vec3(1.0, 0.58, 0.45), vec3(0.20, 0.16, 0.26), smoothstep(0.0, 0.9, t));
		lit += vec3(1.0, 0.55, 0.25) * pow(sdot, 5.0) * (1.0 - t) * 0.9;
		vec3 dark = mix(vec3(0.42, 0.28, 0.42), vec3(0.025, 0.03, 0.07), smoothstep(0.0, 0.8, t));
		vec3 cc = mix(dark, lit, smoothstep(0.35, 0.75, shade));
		col = mix(col, cc, cover * 0.9);
	}

	// 星
	if (d.y > 0.0) {
		vec3 sp = d * 260.0;
		vec3 id = floor(sp);
		float r = hash21(id.xy + id.z * 17.31);
		float dd = length(fract(sp) - 0.5);
		float star = step(0.993, r) * smoothstep(0.2, 0.05, dd);
		col += vec3(0.9, 0.92, 1.0) * star * smoothstep(0.55, 1.0, t) * smoothstep(0.04, 0.3, d.y) * (0.5 + r * 0.5);
	}
	COLOR = col;
}
