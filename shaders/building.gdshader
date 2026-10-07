shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// INSTANCE_CUSTOM: r=種, g=様式(0 事務所 / 1 住宅 / 2 雑居), b=点灯率の偏り
uniform float night = 0.0;
uniform vec3 sky_col : source_color = vec3(0.7, 0.5, 0.5);

varying vec3 wp;
varying vec3 wn;
varying vec4 cd;
varying vec3 icol;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cd = INSTANCE_CUSTOM;
	icol = COLOR.rgb;
}

void fragment() {
	// 補間で値がわずかに揺れるとハッシュが画素ごとに暴れるので整数に丸める
	float seed = floor(cd.r * 97.0 + 0.5);
	float style = floor(cd.g + 0.5);
	vec3 wall = icol;
	if (wn.y > 0.5) {
		float r = hash21(floor(wp.xz * 0.5) + seed);
		ALBEDO = wall * 0.5 * (0.85 + 0.15 * r);
		ROUGHNESS = 0.95;
	} else {
		vec2 tg = normalize(vec2(-wn.z, wn.x));
		float u = dot(wp.xz, tg);
		float v = wp.y;
		vec2 cell = vec2(3.2, 3.8);
		vec2 win = vec2(0.88, 0.6);
		if (style > 0.5 && style < 1.5) { cell = vec2(4.6, 3.0); win = vec2(0.42, 0.55); }
		if (style > 1.5) { cell = vec2(2.8, 3.3); win = vec2(0.55, 0.5); }
		vec2 g = vec2(u, v - 1.2) / cell;
		vec2 id = floor(g);
		vec2 f = fract(g);
		float inwin = step(abs(f.x - 0.5), win.x * 0.5) * step(abs(f.y - 0.5), win.y * 0.5);
		inwin *= step(0.0, g.y);
		float r1 = hash21(id + vec2(seed * 13.1, seed));
		float r2 = hash21(id * 1.7 + vec2(seed * 3.3 + 5.0, 2.0));
		float rf = hash21(vec2(id.y * 3.1, seed + 7.0));
		float ratio = mix(0.14, 0.5, night) * (0.55 + 0.9 * cd.b);
		float pick = style < 0.5 ? mix(r1, rf, 0.65) : r1;
		float lit = step(pick, ratio);
		vec3 lc = mix(vec3(1.0, 0.76, 0.48), vec3(0.82, 0.92, 1.0), step(style < 0.5 ? 0.35 : 0.75, r2));
		float lum = mix(0.5, 1.7, night);
		vec3 glass = sky_col * (0.12 + 0.3 * (1.0 - night)) * (0.55 + 0.45 * r2);
		vec3 em_near = inwin * (glass + lit * lc * lum * (0.6 + 0.5 * r2));
		float cover = win.x * win.y;
		vec3 em_far = cover * (glass + ratio * lc * lum * 0.8);
		float fw = max(fwidth(g.x), fwidth(g.y));
		float far = smoothstep(0.2, 0.6, fw);
		float wm = mix(inwin, cover, far);
		float ao = 0.7 + 0.3 * smoothstep(0.0, 25.0, v);
		ALBEDO = mix(wall * ao, vec3(0.04, 0.05, 0.07), wm);
		EMISSION = mix(em_near, em_far, far);
		// 1階の店先
		float shop = step(0.4, v) * step(v, 3.6) * step(0.45, hash21(vec2(floor(u / 6.0), seed)));
		EMISSION += vec3(1.0, 0.85, 0.6) * shop * night * 0.9;
		ROUGHNESS = 0.85;
	}
}
