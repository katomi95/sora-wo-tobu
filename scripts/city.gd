class_name City
extends Node3D

# 夕方の街。区画は 60m 格子（道路の中心は 30+60k、区画の中心は 60k）。
# 会社（出発）は原点、自宅マンションは -Z 方向に約1km。

const ROOF_Y := 90.0
const ROOF_HALF := 18.0
const RIVER_Z := -600.0
const OFFICE_WIN := Vector3(-45.5, 74.0, -180.0)
const TOP_FLOOR := 86.0
const CROSS := Vector3(30, 0, -510)
const SUPER := Vector3(-60, 0, -720)
const KONBINI := Vector3(60, 0, -712)
const LAUNDRY := Vector3(-30, 14, -836)
const HOME_C := Vector3(60, 0, -1020)
const HOME_STAND := Vector3(68.5, 21.1, -1013.3)
const HOME_DOOR := Vector3(68.5, 21.1, -1014.6)
const SUN_AZ := Vector3(-0.36, 0.0, -0.93)

const RESERVED := [Vector2i(0, 0), Vector2i(-1, -3), Vector2i(-1, -5), Vector2i(1, -5), Vector2i(-1, -12),
	Vector2i(1, -12), Vector2i(0, -14), Vector2i(-1, -14), Vector2i(1, -17), Vector2i(0, -17), Vector2i(-1, -17)]

var rng := RandomNumberGenerator.new()
var boxes := {}  # Vector2i -> Array[AABB]

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var bmat: ShaderMaterial
var gmat: ShaderMaterial
var far_mats: Array[ShaderMaterial] = []
var lamp_mat: StandardMaterial3D
var farlight_mat: StandardMaterial3D
var red_mat: StandardMaterial3D
var cloth_mat: ShaderMaterial
var tod := 0.0

var bxf: Array[Transform3D] = []
var bcol: Array[Color] = []
var bcus: Array[Color] = []
var clutter := Kit.Builder.new()

# 交差点
var crowd: Array[Dictionary] = []
var walk_green: Array[Node3D] = []
var walk_red: Array[Node3D] = []
var crossing := false
var cross_t := 0.0

# 自宅
var home_curtain: MeshInstance3D
var home_light: OmniLight3D


func _init() -> void:
	rng.seed = 20261007


func build() -> void:
	_environment()
	_ground()
	_far()
	_start_tower()
	_office_tower()
	_buildings()
	_crossing()
	_super()
	_mansions()
	_streetlights()
	_cars()
	_farlights()
	_commit_buildings()
	set_tod(0.0)


# ---------------------------------------------------------------- 空・光
func _environment() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_bias = 0.05
	sun.light_color = Color(1.0, 0.62, 0.38)
	add_child(sun)


func sun_dir() -> Vector3:
	var el := deg_to_rad(lerpf(5.5, -9.0, tod))
	return (SUN_AZ * cos(el) + Vector3.UP * sin(el)).normalized()


func hor_color(t: float) -> Color:
	var a := Color(1.0, 0.55, 0.28).lerp(Color(0.11, 0.10, 0.19), smoothstep(0.0, 0.95, t))
	var k := smoothstep(0.35, 0.6, t) * (1.0 - smoothstep(0.6, 0.95, t)) * 0.6
	return a.lerp(Color(0.55, 0.25, 0.32), k)


func zen_color(t: float) -> Color:
	return Color(0.16, 0.24, 0.5).lerp(Color(0.012, 0.02, 0.06), smoothstep(0.0, 0.85, t))


func set_tod(t: float) -> void:
	tod = clampf(t, 0.0, 1.0)
	var sd := sun_dir()
	var hor := hor_color(tod)
	var zen := zen_color(tod)
	var night := smoothstep(0.0, 0.75, tod)
	sky_mat.set_shader_parameter("tod", tod)
	sky_mat.set_shader_parameter("sun_dir", sd)
	gmat.set_shader_parameter("night", night)
	gmat.set_shader_parameter("hor_col", hor)
	gmat.set_shader_parameter("zen_col", zen)
	gmat.set_shader_parameter("sun_dir", sd)
	gmat.set_shader_parameter("sun_vis", 1.0 - smoothstep(0.2, 0.55, tod))
	bmat.set_shader_parameter("night", night)
	bmat.set_shader_parameter("sky_col", hor.lerp(zen, 0.35))
	for i in far_mats.size():
		far_mats[i].set_shader_parameter("hor_col", hor * 0.9)
		var b := Color(0.25, 0.17, 0.25).lerp(Color(0.03, 0.035, 0.07), smoothstep(0.0, 0.9, tod))
		far_mats[i].set_shader_parameter("base", b.lerp(hor, 0.25 if i == 0 else 0.0))
	env.fog_light_color = hor.lerp(zen, 0.15)
	env.fog_density = lerpf(0.0011, 0.0008, tod)
	env.ambient_light_color = Color(0.6, 0.46, 0.5).lerp(Color(0.16, 0.18, 0.3), smoothstep(0.0, 0.85, tod))
	env.ambient_light_energy = lerpf(0.9, 0.8, tod)
	sun.light_energy = lerpf(1.5, 0.0, smoothstep(0.0, 0.55, tod))
	sun.visible = sun.light_energy > 0.02
	sun.light_color = Color(1.0, 0.62, 0.38).lerp(Color(1.0, 0.42, 0.3), tod * 1.5)
	var lsd := sd
	if lsd.y < 0.05:
		lsd = (Vector3(lsd.x, 0, lsd.z).normalized() * 0.995 + Vector3.UP * 0.1).normalized()
	sun.basis = Basis.looking_at(-lsd, Vector3.UP)
	var on := smoothstep(0.08, 0.3, tod)
	lamp_mat.emission_energy_multiplier = 0.2 + on * 3.0
	farlight_mat.emission_energy_multiplier = 0.3 + night * 2.5


# ---------------------------------------------------------------- 地面・遠景
func _ground() -> void:
	gmat = ShaderMaterial.new()
	gmat.shader = load("res://shaders/ground.gdshader")
	gmat.set_shader_parameter("river_z", RIVER_Z)
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	pm.subdivide_width = 24
	pm.subdivide_depth = 24
	var mi := Kit.add_mesh(self, pm, Vector3(0, 0, -500), gmat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 橋の欄干
	var b := Kit.Builder.new()
	for kx in range(-11, 11):
		var x := 30.0 + 60.0 * kx
		for s in [-1.0, 1.0]:
			b.box(Vector3(x + s * 7.3, 0.6, RIVER_Z), Vector3(0.3, 1.2, 42), Color(0.45, 0.45, 0.47))
	# 護岸
	for s in [-1.0, 1.0]:
		b.box(Vector3(0, 0.15, RIVER_Z + s * 20.2), Vector3(1300, 0.3, 0.6), Color(0.4, 0.4, 0.4))
	Kit.add_mesh(self, b.commit(Kit.vc_mat()))


func _far() -> void:
	var layers := [[3300.0, 160.0, 420.0, 0.9, 3], [2500.0, 80.0, 230.0, 0.55, 11]]
	for li in layers.size():
		var L: Array = layers[li]
		var fm := ShaderMaterial.new()
		fm.shader = load("res://shaders/far.gdshader")
		fm.set_shader_parameter("haze", L[3])
		far_mats.append(fm)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 240
		var noise := FastNoiseLite.new()
		noise.seed = L[4]
		noise.frequency = 2.2
		noise.fractal_octaves = 4
		var pts: Array[Vector3] = []
		for i in n + 1:
			var a := TAU * i / n
			var d := Vector3(sin(a), 0, cos(a))
			var h: float = L[1] + (L[2] - L[1]) * clampf(noise.get_noise_2d(d.x, d.z) * 0.9 + 0.5, 0.0, 1.0)
			pts.append(d * L[0] + Vector3(0, h, 0))
		for i in n:
			var a0 := pts[i]
			var a1 := pts[i + 1]
			var b0 := Vector3(a0.x, -30, a0.z)
			var b1 := Vector3(a1.x, -30, a1.z)
			for v in [b0, a0, a1, b0, a1, b1]:
				st.add_vertex(v)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = fm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, 0, -500)
		add_child(mi)


# ---------------------------------------------------------------- 建物
func _add_building(c: Vector3, size: Vector3, col: Color, style: int, bias := -1.0, collide := true) -> void:
	var xf := Transform3D(Basis.from_scale(size), c + Vector3(0, size.y * 0.5, 0))
	bxf.append(xf)
	bcol.append(col)
	bcus.append(Color(rng.randf(), float(style), rng.randf() if bias < 0.0 else bias, 0))
	if collide:
		_collider(AABB(c - Vector3(size.x * 0.5, 0, size.z * 0.5), size))
	if size.y > 75.0:
		_red_light(c + Vector3(0, size.y + 0.4, 0), size)


func _collider(a: AABB) -> void:
	var k := Vector2i(roundi(a.get_center().x / 60.0), roundi(a.get_center().z / 60.0))
	if not boxes.has(k):
		boxes[k] = []
	boxes[k].append(a)


var red_lights: Array[Vector3] = []


func _red_light(top: Vector3, size: Vector3) -> void:
	for s in [Vector2(-1, -1), Vector2(1, 1)]:
		red_lights.append(top + Vector3(s.x * size.x * 0.45, 0, s.y * size.z * 0.45))


func _wall_color(style: int) -> Color:
	match style:
		0:
			return [Color(0.42, 0.44, 0.47), Color(0.34, 0.36, 0.4), Color(0.5, 0.49, 0.47), Color(0.28, 0.3, 0.34)][rng.randi() % 4]
		1:
			return [Color(0.62, 0.58, 0.52), Color(0.55, 0.53, 0.5), Color(0.6, 0.5, 0.42), Color(0.68, 0.66, 0.62)][rng.randi() % 4]
		_:
			return [Color(0.5, 0.45, 0.4), Color(0.45, 0.42, 0.42), Color(0.55, 0.5, 0.45), Color(0.4, 0.38, 0.36)][rng.randi() % 4]


func _buildings() -> void:
	for kz in range(-24, 6):
		for kx in range(-10, 11):
			var key := Vector2i(kx, kz)
			if key in RESERVED or kz == -10:
				continue
			var c := Vector2(60.0 * kx, 60.0 * kz)
			var z := c.y
			var hmin := 8.0
			var hmax := 30.0
			var styles := [1, 1, 2]
			if z > -480.0:
				var k := clampf(c.length() / 420.0, 0.0, 1.0)
				hmin = lerpf(30.0, 14.0, k)
				hmax = lerpf(115.0, 45.0, k)
				styles = [0, 0, 0, 2]
			elif z > -790.0:
				hmin = 10.0
				hmax = 42.0
				styles = [0, 2, 2, 1]
			if kx == 0 and z < -30.0 and z > -560.0:
				hmax = minf(hmax, 48.0)
			# 風の通り道（二本の高いビル）
			_fill_block(c, hmin, hmax, styles)
	# 街の外側（低い家並み）
	for kz in range(-34, 16):
		for kx in range(-20, 21):
			if kx >= -10 and kx <= 10 and kz >= -24 and kz <= 5:
				continue
			if kz == -10 or rng.randf() > 0.45:
				continue
			_fill_block(Vector2(60.0 * kx, 60.0 * kz), 4.0, 14.0, [1, 1, 2], false)
	# 風のビル
	_add_building(Vector3(-60, 0, -300), Vector3(34, 128, 30), Color(0.3, 0.33, 0.38), 0)
	_add_building(Vector3(60, 0, -300), Vector3(30, 116, 34), Color(0.4, 0.42, 0.45), 0)
	# 赤い航空障害灯
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	mm.mesh = sm
	mm.instance_count = red_lights.size()
	for i in red_lights.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, red_lights[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	red_mat = Kit.emit_mat(Color(1.0, 0.1, 0.05), 4.0)
	mmi.material_override = red_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _fill_block(c: Vector2, hmin: float, hmax: float, styles: Array, collide := true) -> void:
	var half := 20.0
	var cells: Array[Rect2] = []
	var r := rng.randf()
	if r < 0.28:
		cells.append(Rect2(c.x - half, c.y - half, half * 2, half * 2))
	elif r < 0.6:
		if rng.randf() < 0.5:
			cells.append(Rect2(c.x - half, c.y - half, half, half * 2))
			cells.append(Rect2(c.x, c.y - half, half, half * 2))
		else:
			cells.append(Rect2(c.x - half, c.y - half, half * 2, half))
			cells.append(Rect2(c.x - half, c.y, half * 2, half))
	else:
		for i in 2:
			for j in 2:
				cells.append(Rect2(c.x - half + half * i, c.y - half + half * j, half, half))
	for cell in cells:
		if rng.randf() < 0.08:
			continue
		var m := rng.randf_range(1.0, 3.5)
		var w := cell.size.x - m * 2.0
		var d := cell.size.y - rng.randf_range(1.0, 3.5) * 2.0
		var h := lerpf(hmin, hmax, pow(rng.randf(), 1.6))
		if cells.size() == 4:
			h *= 0.75
		var style: int = styles[rng.randi() % styles.size()]
		var ctr := cell.get_center()
		_add_building(Vector3(ctr.x, 0, ctr.y), Vector3(w, h, d), _wall_color(style), style, -1.0, collide)
		# 屋上の設備
		if collide and rng.randf() < 0.6:
			for k in rng.randi_range(1, 3):
				var s := Vector3(rng.randf_range(1.5, 4.0), rng.randf_range(1.0, 2.5), rng.randf_range(1.5, 4.0))
				var p := Vector3(ctr.x + rng.randf_range(-w, w) * 0.3, h + s.y * 0.5, ctr.y + rng.randf_range(-d, d) * 0.3)
				clutter.box(p, s, Color(0.4, 0.41, 0.42) * rng.randf_range(0.7, 1.1))


func _commit_buildings() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	mm.instance_count = bxf.size()
	for i in bxf.size():
		mm.set_instance_transform(i, bxf[i])
		mm.set_instance_color(i, bcol[i])
		mm.set_instance_custom_data(i, bcus[i])
	bmat = bmat if bmat else _bmat()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bmat
	add_child(mmi)
	var cl := Kit.add_mesh(self, clutter.commit(Kit.vc_mat()))
	cl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _bmat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/building.gdshader")
	return m


# ---------------------------------------------------------------- 会社の屋上
func _start_tower() -> void:
	bmat = _bmat()
	# 最上階だけ -Z 側が奥まっていて、窓際の部長の席が外から見える
	var tc := Color(0.36, 0.38, 0.42)
	var w := ROOF_HALF * 2
	var rec := 1.6
	_add_building(Vector3.ZERO, Vector3(w, TOP_FLOOR, w), tc, 0, 0.8)
	_add_building(Vector3(0, TOP_FLOOR, rec * 0.5), Vector3(w, ROOF_Y - 0.6 - TOP_FLOOR, w - rec), tc, 0, 0.2, false)
	_add_building(Vector3(0, ROOF_Y - 0.6, 0), Vector3(w, 0.6, w), tc, 0, 0.0, false)
	_boss_floor()
	var b := Kit.Builder.new()
	var y := ROOF_Y
	var gray := Color(0.42, 0.42, 0.43)
	var h := ROOF_HALF
	# パラペット
	for s in [-1.0, 1.0]:
		b.box(Vector3(0, y + 0.25, s * (h - 0.18)), Vector3(h * 2, 0.5, 0.36), gray)
		b.box(Vector3(s * (h - 0.18), y + 0.25, 0), Vector3(0.36, 0.5, h * 2), gray)
	# 床の防水シート
	b.box(Vector3(0, y + 0.01, 0), Vector3(h * 2 - 0.7, 0.02, h * 2 - 0.7), Color(0.3, 0.31, 0.3))
	# フェンス（-Z 側の真ん中だけ途切れている）
	var fc := Color(0.22, 0.24, 0.24)
	var fi := h - 0.6
	var x := -fi
	while x <= fi + 0.01:
		for side in 4:
			var p := Vector3(x, 0, -fi)
			match side:
				1: p = Vector3(x, 0, fi)
				2: p = Vector3(-fi, 0, x)
				3: p = Vector3(fi, 0, x)
			if side == 0 and absf(x) < 2.5:
				continue
			b.box(Vector3(p.x, y + 0.6, p.z), Vector3(0.06, 1.2, 0.06), fc)
		x += 2.0
	for rail_y in [0.55, 1.18]:
		b.box(Vector3(0, y + rail_y, fi), Vector3(fi * 2, 0.05, 0.05), fc)
		b.box(Vector3(-fi, y + rail_y, 0), Vector3(0.05, 0.05, fi * 2), fc)
		b.box(Vector3(fi, y + rail_y, 0), Vector3(0.05, 0.05, fi * 2), fc)
		for s in [-1.0, 1.0]:
			b.box(Vector3(s * (fi + 2.5) * 0.5, y + rail_y, -fi), Vector3(fi - 2.5, 0.05, 0.05), fc)
	# 金網（細い横線で表現）
	for k in range(1, 8):
		var ry := 0.14 * k + 0.1
		b.box(Vector3(0, y + ry, fi), Vector3(fi * 2, 0.012, 0.012), fc)
		b.box(Vector3(-fi, y + ry, 0), Vector3(0.012, 0.012, fi * 2), fc)
		b.box(Vector3(fi, y + ry, 0), Vector3(0.012, 0.012, fi * 2), fc)
		for s in [-1.0, 1.0]:
			b.box(Vector3(s * (fi + 2.5) * 0.5, y + ry, -fi), Vector3(fi - 2.5, 0.012, 0.012), fc)
	# 階段室・給水塔・室外機
	b.box(Vector3(10, y + 1.6, 11), Vector3(6, 3.2, 5), Color(0.5, 0.5, 0.5))
	b.box(Vector3(10, y + 1.05, 8.47), Vector3(1.0, 2.1, 0.06), Color(0.3, 0.32, 0.34))
	b.cyl(Vector3(-10, y, 10), 2.2, 4.0, Color(0.55, 0.56, 0.58), 16)
	for i in 4:
		b.box(Vector3(-12 + i * 1.6, y + 0.5, -6), Vector3(1.2, 1.0, 0.8), Color(0.6, 0.6, 0.6))
	b.box(Vector3(12, y + 4, -12), Vector3(0.15, 8, 0.15), Color(0.5, 0.5, 0.5))
	Kit.add_mesh(self, b.commit(Kit.vc_mat()))
	var g := Kit.Builder.new()
	g.box(Vector3(10, y + 2.3, 8.47), Vector3(0.5, 0.35, 0.05), Color(0.9, 0.95, 1.0))
	g.box(Vector3(12, y + 8.1, -12), Vector3(0.35, 0.35, 0.35), Color(1.0, 0.1, 0.05))
	Kit.add_mesh(self, g.commit(Kit.glow_mat(1.5)))


func roof_block(p: Vector3) -> Vector3:
	# 屋上を歩くときの当たり（フェンスの内側＋途切れた所はパラペットまで）
	var lim := ROOF_HALF - 1.0
	p.x = clampf(p.x, -lim, lim)
	if absf(p.x) < 1.9:
		p.z = clampf(p.z, -(ROOF_HALF - 0.5), lim)
	else:
		p.z = clampf(p.z, -lim, lim)
	# 階段室と給水塔
	var hut := Rect2(10 - 3.4, 11 - 2.9, 6.8, 5.8)
	if hut.has_point(Vector2(p.x, p.z)):
		var dl := [p.x - hut.position.x, hut.end.x - p.x, p.z - hut.position.y, hut.end.y - p.z]
		var m: float = dl.min()
		match dl.find(m):
			0: p.x = hut.position.x
			1: p.x = hut.end.x
			2: p.z = hut.position.y
			3: p.z = hut.end.y
	var tv := Vector2(p.x + 10, p.z - 10)
	if tv.length() < 2.7:
		tv = tv.normalized() * 2.7
		p.x = tv.x - 10
		p.z = tv.y + 10
	if p.x > -12.6 and p.x < -6.6 and absf(p.z + 6.0) < 0.9:
		p.z = -6.9 if p.z < -6.0 else -5.1
	return p


# 会社の最上階。屋上の縁から一瞬沈んだときに、窓際でまだ働く部長が見える
func _boss_floor() -> void:
	var z := -ROOF_HALF
	var fy := TOP_FLOOR
	var g := Kit.Builder.new()
	var s := Kit.Builder.new()
	var ins := -ROOF_HALF + 1.6
	# 奥の壁。明かりが点いているのは部長の席のまわりだけ
	g.box(Vector3(-2.5, fy + 1.7, ins - 0.03), Vector3(9, 3.3, 0.04), Color(0.36, 0.35, 0.33))
	for sx in [-1.0, 1.0]:
		var cx: float = -2.5 + sx * 13.25
		g.box(Vector3(cx, fy + 1.7, ins - 0.03), Vector3(17.5, 3.3, 0.04), Color(0.1, 0.1, 0.12))
	for x in [-4.5, -0.5]:
		g.box(Vector3(x, ROOF_Y - 0.63, z + 0.9), Vector3(2.8, 0.04, 0.25), Color(1.3, 1.3, 1.35))
	g.box(Vector3(-2.5, fy + 0.02, z + 0.8), Vector3(9, 0.04, 1.6), Color(0.3, 0.31, 0.34))
	# 書類棚とホワイトボード
	for x in [-6.0, -5.2, 1.0]:
		g.box(Vector3(x, fy + 0.9, ins - 0.25), Vector3(0.75, 1.8, 0.4), Color(0.32, 0.33, 0.35))
	g.box(Vector3(-0.4, fy + 1.6, ins - 0.06), Vector3(1.6, 1.0, 0.04), Color(0.75, 0.75, 0.73))
	# 部長の机（電気スタンドとモニター）
	g.box(Vector3(-3.2, fy + 0.72, z + 0.75), Vector3(1.6, 0.06, 0.8), Color(0.45, 0.32, 0.22))
	g.box(Vector3(-2.55, fy + 1.0, z + 0.75), Vector3(0.04, 0.36, 0.5), Color(0.55, 0.7, 0.95) * 1.3)
	g.box(Vector3(-3.85, fy + 1.12, z + 0.6), Vector3(0.22, 0.1, 0.22), Color(1.6, 1.45, 1.1))
	g.box(Vector3(-3.75, fy + 0.95, z + 0.6), Vector3(0.03, 0.4, 0.03), Color(0.2, 0.2, 0.2))
	g.box(Vector3(-3.1, fy + 0.79, z + 0.6), Vector3(0.35, 0.08, 0.25), Color(0.85, 0.85, 0.82))
	# 帰ったあとの、暗い机
	for x in [-9.0, 4.0, 8.5, 13.0, -13.5]:
		g.box(Vector3(x, fy + 0.72, z + 0.8), Vector3(1.6, 0.06, 0.7), Color(0.14, 0.14, 0.15))
		g.box(Vector3(x, fy + 1.0, z + 0.6), Vector3(0.5, 0.32, 0.04), Color(0.05, 0.05, 0.06))
	Kit.add_mesh(self, g.commit(Kit.glow_mat(1.0)))
	# 窓の桟
	var x := -6.0
	while x <= 6.01:
		s.box(Vector3(x, fy + 1.7, z + 0.04), Vector3(0.1, 3.4, 0.08), Color(0.2, 0.22, 0.25))
		x += 2.0
	s.box(Vector3(0, fy + 0.05, z + 0.04), Vector3(12.1, 0.1, 0.08), Color(0.2, 0.22, 0.25))
	Kit.add_mesh(self, s.commit(Kit.vc_mat()))
	# 部長（窓の外を向いて座っている。髪はない）
	var boss := Kit.person(self, Color(0.85, 0.85, 0.82), Color(0.2, 0.2, 0.22), Vector3(-3.2, fy - 0.42, z + 1.25), true, 1.06)
	for ch in boss.get_children():
		if ch is MeshInstance3D and ch.position.y > 1.68:
			ch.visible = false


# ---------------------------------------------------------------- 残業しているよその会社
func _office_tower() -> void:
	var c := Vector3(-60, 0, -180)
	var fy := 72.0
	var b := Kit.Builder.new()
	var wall := Color(0.32, 0.35, 0.4)
	b.box(c + Vector3(0, fy * 0.5, 0), Vector3(30, fy, 30), wall)
	b.box(c + Vector3(0, (140.0 + fy + 4.0) * 0.5, 0), Vector3(30, 140.0 - fy - 4.0, 30), wall, Basis.IDENTITY, false)
	var mi := Kit.add_mesh(self, b.commit(bmat))
	mi.name = "BuchoTower"
	_collider(AABB(c - Vector3(15, 0, 15), Vector3(30, 140, 30)))
	_red_light(c + Vector3(0, 140.4, 0), Vector3(30, 140, 30))
	# 柱
	var s := Kit.Builder.new()
	for i in 5:
		for j in [-1.0, 1.0]:
			var o := -14.6 + i * 7.3
			s.box(c + Vector3(o, fy + 2.0, j * 14.6), Vector3(0.8, 4.0, 0.8), Color(0.25, 0.27, 0.3))
			s.box(c + Vector3(j * 14.6, fy + 2.0, o), Vector3(0.8, 4.0, 0.8), Color(0.25, 0.27, 0.3))
	s.box(c + Vector3(0, fy + 2.0, 0), Vector3(9, 4, 9), Color(0.3, 0.3, 0.32))
	Kit.add_mesh(self, s.commit(Kit.vc_mat()))
	# 室内（蛍光灯に照らされている）
	var g := Kit.Builder.new()
	g.box(c + Vector3(0, fy + 0.05, 0), Vector3(29.4, 0.1, 29.4), Color(0.26, 0.28, 0.32))
	g.box(c + Vector3(0, fy + 3.95, 0), Vector3(29.4, 0.1, 29.4), Color(0.55, 0.57, 0.6))
	for i in 6:
		for j in 6:
			g.box(c + Vector3(-12.5 + i * 5, fy + 3.88, -12.5 + j * 5), Vector3(1.2, 0.05, 3.0), Color(1.2, 1.25, 1.3))
	g.box(c + Vector3(0, fy + 2.0, 0), Vector3(9.05, 3.8, 9.05), Color(0.45, 0.44, 0.42))
	# 机の島
	for i in 3:
		for j in 4:
			var dp := c + Vector3(-5.5 + i * 5.5, fy + 0.72, -10.5 + j * 7.0)
			if absf(dp.x - c.x) < 6.0 and absf(dp.z - c.z) < 6.0:
				continue
			g.box(dp, Vector3(3.2, 0.06, 2.6), Color(0.72, 0.7, 0.66))
			for k in 4:
				var mp := dp + Vector3(-0.8 + (k % 2) * 1.6, 0.28, -0.6 + (k / 2) * 1.2)
				g.box(mp, Vector3(0.5, 0.32, 0.04), Color(0.55, 0.7, 0.95) * 1.4)
	# 窓際の机（窓のほうを向いている）
	var bd := c + Vector3(12.0, fy + 0.72, 0.0)
	g.box(bd, Vector3(1.6, 0.06, 2.8), Color(0.5, 0.36, 0.25))
	g.box(bd + Vector3(-0.4, 0.25, 0.6), Vector3(0.04, 0.32, 0.5), Color(0.55, 0.7, 0.95) * 1.4)
	g.box(bd + Vector3(0.0, 0.36, -0.9), Vector3(0.1, 0.6, 0.1), Color(0.2, 0.2, 0.2))
	g.box(bd + Vector3(0.0, 0.66, -0.9), Vector3(0.3, 0.12, 0.3), Color(1.5, 1.4, 1.1))
	Kit.add_mesh(self, g.commit(Kit.glow_mat(1.0)))
	# まだ残っている二人
	var p1 := Kit.person(self, Color(0.82, 0.84, 0.86), Color(0.2, 0.2, 0.22), bd + Vector3(-1.1, -0.95, 0.2), true)
	p1.rotation.y = -PI * 0.5
	var other := Kit.person(self, Color(0.82, 0.84, 0.86), Color(0.18, 0.2, 0.25), c + Vector3(6.3, fy - 0.25, -3.5 + 0.9), true)
	other.rotation.y = PI


# ---------------------------------------------------------------- 交差点
func _crossing() -> void:
	var b := Kit.Builder.new()
	var g := Kit.Builder.new()
	var c := CROSS
	var pole := Color(0.3, 0.32, 0.3)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := c + Vector3(sx * 9.0, 0, sz * 9.0)
			b.box(p + Vector3(0, 2.8, 0), Vector3(0.18, 5.6, 0.18), pole)
			# 車用信号（赤）
			b.box(p + Vector3(-sx * 2.5, 5.4, 0), Vector3(5.0, 0.12, 0.12), pole)
			b.box(p + Vector3(-sx * 4.5, 5.4, 0), Vector3(1.3, 0.45, 0.35), Color(0.15, 0.16, 0.15))
			g.box(p + Vector3(-sx * 4.5 + 0.4, 5.4, sz * 0.19), Vector3(0.3, 0.3, 0.02), Color(2.0, 0.15, 0.1))
			# 歩行者信号
			b.box(p + Vector3(0, 2.6, sz * 0.2), Vector3(0.45, 0.8, 0.2), Color(0.15, 0.16, 0.15))
			var red := Kit.box_node(self, Vector3(0.36, 0.3, 0.03), p + Vector3(0, 2.8, sz * 0.31), Kit.emit_mat(Color(1.0, 0.15, 0.1), 2.5))
			var grn := Kit.box_node(self, Vector3(0.36, 0.3, 0.03), p + Vector3(0, 2.42, sz * 0.31), Kit.emit_mat(Color(0.2, 1.0, 0.75), 2.5))
			grn.visible = false
			walk_red.append(red)
			walk_green.append(grn)
	Kit.add_mesh(self, b.commit(Kit.vc_mat()))
	Kit.add_mesh(self, g.commit(Kit.glow_mat(1.0)))
	# 信号待ちの人たち
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var bodies := [Color(0.16, 0.17, 0.2), Color(0.12, 0.12, 0.13), Color(0.8, 0.8, 0.78), Color(0.35, 0.3, 0.25),
		Color(0.5, 0.15, 0.15), Color(0.2, 0.3, 0.45), Color(0.6, 0.55, 0.45)]
	for ci in 4:
		var cv: Vector2 = corners[ci]
		for k in rng.randi_range(5, 8):
			var p := c + Vector3(cv.x * rng.randf_range(8.0, 11.5), 0.02, cv.y * rng.randf_range(8.0, 11.5))
			var per := Kit.person(self, bodies[rng.randi() % bodies.size()], Color(0.15, 0.15, 0.17), p)
			per.rotation.y = rng.randf() * TAU
			# 行き先：向かい、横、斜め
			var dst_c: Vector2 = corners[(ci + rng.randi_range(1, 3)) % 4]
			var dst := c + Vector3(dst_c.x * rng.randf_range(8.5, 11.5), 0.02, dst_c.y * rng.randf_range(8.5, 11.5))
			crowd.append({"n": per, "from": p, "to": dst, "spd": rng.randf_range(1.1, 1.6), "delay": rng.randf_range(0.0, 2.0), "ph": rng.randf() * TAU})
	# 赤信号で止まっている車
	var cars := Kit.Builder.new()
	var lights := Kit.Builder.new()
	var cols := [Color(0.85, 0.85, 0.85), Color(0.1, 0.1, 0.12), Color(0.55, 0.56, 0.6), Color(0.5, 0.1, 0.1)]
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var side := Vector3(-dir.z, 0, dir.x)
		for k in 3:
			var p: Vector3 = c - dir * (13.0 + k * 6.0) - side * 3.5 + Vector3(0, 0.65, 0)
			var bas := Basis.looking_at(-dir)
			cars.box(p, Vector3(1.8, 1.3, 4.2), cols[rng.randi() % cols.size()], bas)
			for sx in [-0.6, 0.6]:
				lights.box(p + bas * Vector3(sx, -0.15, 2.12), Vector3(0.4, 0.25, 0.02), Color(2.5, 2.4, 2.2))
				lights.box(p + bas * Vector3(sx, -0.15, -2.12), Vector3(0.4, 0.25, 0.02), Color(1.6, 0.1, 0.05))
	Kit.add_mesh(self, cars.commit(Kit.vc_mat(0.5)))
	Kit.add_mesh(self, lights.commit(Kit.glow_mat(1.0)))


func start_crossing() -> void:
	if crossing:
		return
	crossing = true
	cross_t = 0.0
	for n in walk_red:
		n.visible = false
	for n in walk_green:
		n.visible = true


func update(dt: float) -> void:
	if crossing:
		cross_t += dt
		for p in crowd:
			var tt: float = cross_t - p["delay"]
			if tt <= 0.0:
				continue
			var from: Vector3 = p["from"]
			var to: Vector3 = p["to"]
			var dist := from.distance_to(to)
			var s := clampf(tt * p["spd"] / dist, 0.0, 1.0)
			var n: Node3D = p["n"]
			n.position = from.lerp(to, s)
			if s < 1.0:
				n.position.y = 0.02 + absf(sin(tt * 7.0 + p["ph"])) * 0.05
				var dir := (to - from).normalized()
				n.rotation.y = atan2(-dir.x, -dir.z)
	# 航空障害灯の点滅
	var bl := fmod(Time.get_ticks_msec() / 1000.0, 1.6) < 0.8
	red_mat.emission_energy_multiplier = 4.0 if bl else 0.3


# ---------------------------------------------------------------- スーパーとコンビニ
func _super() -> void:
	var font: Font = load("res://fonts/sans.ttf")
	var b := Kit.Builder.new()
	var g := Kit.Builder.new()
	var s := SUPER + Vector3(-6, 0, 0)
	b.box(s + Vector3(0, 3.5, 0), Vector3(28, 7, 36), Color(0.78, 0.76, 0.7))
	b.box(s + Vector3(14.3, 6.6, 0), Vector3(0.6, 1.4, 36), Color(0.85, 0.2, 0.15))
	g.box(s + Vector3(14.05, 1.5, 0), Vector3(0.1, 2.6, 30), Color(1.3, 1.2, 0.95))
	_collider(AABB(s - Vector3(14, 0, 18), Vector3(28, 8, 36)))
	# 屋上の看板
	b.box(s + Vector3(4, 7.0 + 2.5, 0), Vector3(0.4, 5, 0.4), Color(0.3, 0.3, 0.3))
	b.box(s + Vector3(4, 7.0 + 2.5, 8), Vector3(0.4, 5, 0.4), Color(0.3, 0.3, 0.3))
	g.box(s + Vector3(4.3, 7.0 + 4.0, 4), Vector3(0.2, 3.0, 12), Color(1.6, 0.85, 0.2))
	var lb := Label3D.new()
	lb.font = font
	lb.text = "スーパー まるやす"
	lb.font_size = 180
	lb.pixel_size = 0.012
	lb.modulate = Color(0.85, 0.12, 0.08)
	lb.outline_size = 0
	lb.shaded = false
	lb.position = s + Vector3(4.45, 11.0, 4)
	lb.rotation.y = PI * 0.5
	add_child(lb)
	# 駐車場の車
	var cols := [Color(0.85, 0.85, 0.85), Color(0.1, 0.1, 0.12), Color(0.55, 0.56, 0.6), Color(0.2, 0.3, 0.5)]
	for i in 7:
		if rng.randf() < 0.3:
			continue
		b.box(SUPER + Vector3(14.5, 0.65, -15 + i * 4.4), Vector3(4.2, 1.3, 1.8), cols[rng.randi() % cols.size()])
	# コンビニ
	var k := KONBINI
	b.box(k + Vector3(0, 2.4, 0), Vector3(14, 4.8, 11), Color(0.85, 0.86, 0.86))
	g.box(k + Vector3(0, 1.4, 5.55), Vector3(12.5, 2.4, 0.1), Color(1.7, 1.75, 1.8))
	g.box(k + Vector3(0, 4.1, 5.56), Vector3(14, 0.35, 0.1), Color(0.2, 0.7, 0.4) * 1.6)
	g.box(k + Vector3(0, 3.7, 5.56), Vector3(14, 0.35, 0.1), Color(1.0, 0.5, 0.15) * 1.6)
	g.box(k + Vector3(0, 3.3, 5.56), Vector3(14, 0.35, 0.1), Color(0.2, 0.4, 0.9) * 1.6)
	g.box(k + Vector3(-5.5, 4.83, 0), Vector3(2, 0.05, 2), Color(1.2, 1.2, 1.2))
	_collider(AABB(k - Vector3(7, 0, 5.5), Vector3(14, 5, 11)))
	for i in 3:
		b.box(k + Vector3(-4.5 + i * 4.5, 0.65, 11.0), Vector3(1.8, 1.3, 4.2), cols[rng.randi() % cols.size()])
	Kit.add_mesh(self, b.commit(Kit.vc_mat()))
	Kit.add_mesh(self, g.commit(Kit.glow_mat(1.0)))
	# コンビニのブロックのほかの建物
	_add_building(Vector3(45, 0, -733), Vector3(16, 22, 14), _wall_color(2), 2)
	_add_building(Vector3(72, 0, -733), Vector3(14, 30, 14), _wall_color(1), 1)


# ---------------------------------------------------------------- マンション（ベランダ付き）
func _mansions() -> void:
	cloth_mat = ShaderMaterial.new()
	cloth_mat.shader = load("res://shaders/cloth.gdshader")
	_mansion(Vector3(0, 0, -846), 38, 12, 8, 0.6, true)
	_mansion(Vector3(-60, 0, -846), 36, 12, 6, 0.5, true)
	_add_building(Vector3(0, 0, -860), Vector3(20, 8, 6), _wall_color(1), 1)
	_mansion(HOME_C, 34, 12, 11, 0.25, false, true)
	# 自宅のまわり
	_add_building(Vector3(50, 0, -1034), Vector3(14, 9, 10), _wall_color(1), 1)
	_add_building(Vector3(72, 0, -1034), Vector3(10, 7, 10), _wall_color(1), 1)
	_mansion(Vector3(0, 0, -1024), 32, 12, 7, 0.4, true)
	_mansion(Vector3(-60, 0, -1022), 34, 12, 9, 0.35, true)


func _mansion(c: Vector3, w: float, d: float, floors: int, laundry_p: float, laundry := true, home := false) -> void:
	var b := Kit.Builder.new()
	var g := Kit.Builder.new()
	var cl := Kit.Builder.new()
	var body := Kit.Builder.new()
	var hgt := floors * 3.0 + 1.0
	var wall := Color(0.72, 0.68, 0.6) if not home else Color(0.74, 0.7, 0.64)
	body.box(c + Vector3(0, hgt * 0.5, 0), Vector3(w, hgt, d), wall)
	Kit.add_mesh(self, body.commit(bmat))
	_collider(AABB(c - Vector3(w * 0.5, 0, d * 0.5), Vector3(w, hgt, d + 3.0)))
	var units := maxi(2, roundi(w / 5.6))
	var uw := w / units
	var fz := c.z + d * 0.5
	var lc := [Color(1.0, 0.78, 0.5), Color(1.0, 0.85, 0.65), Color(0.85, 0.92, 1.0), Color(1.0, 0.7, 0.45)]
	var cloth_cols := [Color(0.9, 0.9, 0.88), Color(0.6, 0.75, 0.9), Color(0.95, 0.7, 0.7), Color(0.95, 0.9, 0.6),
		Color(0.4, 0.5, 0.7), Color(0.85, 0.85, 0.95), Color(0.7, 0.85, 0.7)]
	for f in range(1, floors):
		var y := f * 3.0
		for u in units:
			var x := c.x - w * 0.5 + uw * (u + 0.5)
			b.box(Vector3(x, y + 0.08, fz + 0.75), Vector3(uw - 0.1, 0.16, 1.5), wall * 0.9, Basis.IDENTITY, false)
			b.box(Vector3(x, y + 0.65, fz + 1.46), Vector3(uw - 0.1, 1.0, 0.08), Color(0.5, 0.53, 0.56))
			b.box(Vector3(x, y + 1.17, fz + 1.46), Vector3(uw - 0.1, 0.05, 0.1), Color(0.35, 0.36, 0.37))
			b.box(Vector3(x - uw * 0.5 + 0.05, y + 1.2, fz + 0.75), Vector3(0.08, 2.4, 1.5), wall * 0.85)
			var is_home := home and f == 7 and u == 4
			var lit := rng.randf() < 0.55 or is_home
			var door_c := Vector3(x, y + 1.25, fz + 0.03)
			if is_home:
				home_curtain = MeshInstance3D.new()
				var qm := BoxMesh.new()
				qm.size = Vector3(uw * 0.72, 2.1, 0.04)
				home_curtain.mesh = qm
				home_curtain.position = door_c
				home_curtain.material_override = Kit.emit_mat(Color(1.0, 0.8, 0.55), 1.4)
				home_curtain.material_override.albedo_color = Color(0.5, 0.4, 0.3)
				add_child(home_curtain)
				home_light = OmniLight3D.new()
				home_light.light_color = Color(1.0, 0.75, 0.5)
				home_light.light_energy = 0.7
				home_light.omni_range = 6.0
				home_light.position = door_c + Vector3(0, 0.3, 0.9)
				add_child(home_light)
				# 物干し竿と鉢植え
				b.box(Vector3(x, y + 2.3, fz + 1.0), Vector3(uw - 0.4, 0.04, 0.04), Color(0.7, 0.7, 0.7))
				b.cyl(Vector3(x + uw * 0.35, y + 0.16, fz + 0.5), 0.18, 0.3, Color(0.55, 0.3, 0.2), 8, 0.22)
				b.box(Vector3(x + uw * 0.35, y + 0.65, fz + 0.5), Vector3(0.35, 0.5, 0.35), Color(0.2, 0.4, 0.2))
				b.box(Vector3(x - uw * 0.3, y + 0.35, fz + 0.4), Vector3(0.5, 0.4, 0.4), Color(0.4, 0.42, 0.45))
			elif lit:
				g.box(door_c, Vector3(uw * 0.72, 2.1, 0.04), lc[rng.randi() % lc.size()] * rng.randf_range(0.8, 1.2))
			else:
				b.box(door_c, Vector3(uw * 0.72, 2.1, 0.04), Color(0.08, 0.09, 0.12))
			if laundry and rng.randf() < laundry_p:
				b.box(Vector3(x, y + 2.3, fz + 1.0), Vector3(uw - 0.4, 0.04, 0.04), Color(0.7, 0.7, 0.7))
				var n := rng.randi_range(2, 5)
				for i in n:
					var cx := x - uw * 0.4 + (uw * 0.8) * (i + 0.5) / n
					var ww := rng.randf_range(0.4, 0.75)
					var hh := rng.randf_range(0.5, 0.9)
					var col: Color = cloth_cols[rng.randi() % cloth_cols.size()]
					_cloth(cl, Vector3(cx, y + 2.28, fz + 1.0), ww, hh, col)
	Kit.add_mesh(self, b.commit(Kit.vc_mat()))
	Kit.add_mesh(self, g.commit(Kit.glow_mat(1.0)))
	if cl.count > 0:
		var cm := Kit.add_mesh(self, cl.commit(cloth_mat))
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _cloth(cl: Kit.Builder, top: Vector3, w: float, h: float, col: Color) -> void:
	# 頂点色の a に「竿からの距離」を入れてシェーダで揺らす
	var seg := 3
	for i in seg:
		var y0 := -h * i / seg
		var y1 := -h * (i + 1) / seg
		var c0 := Color(col.r, col.g, col.b, float(i) / seg)
		var c1 := Color(col.r, col.g, col.b, float(i + 1) / seg)
		var a := top + Vector3(-w * 0.5, y0, 0)
		var bb := top + Vector3(w * 0.5, y0, 0)
		var c := top + Vector3(w * 0.5, y1, 0)
		var d := top + Vector3(-w * 0.5, y1, 0)
		for v in [[a, c0], [bb, c0], [c, c1], [a, c0], [c, c1], [d, c1]]:
			cl.st.set_color(v[1])
			cl.st.set_normal(Vector3(0, 0, 1))
			cl.st.add_vertex(v[0])
	cl.count += 1


# ---------------------------------------------------------------- 街灯・車・遠くの灯り
func _streetlights() -> void:
	var poles: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	for kz in range(-24, 6):
		var zc := 30.0 + 60.0 * kz
		var x := -620.0
		while x < 620.0:
			for s in [-1.0, 1.0]:
				poles.append(Transform3D(Basis.IDENTITY, Vector3(x, 3.5, zc + s * 8.6)))
				heads.append(Transform3D(Basis.IDENTITY, Vector3(x, 7.0, zc + s * 7.9)))
			x += 40.0
	for kx in range(-11, 11):
		var xc := 30.0 + 60.0 * kx
		var z := 320.0
		while z > -1440.0:
			if absf(z - RIVER_Z) > 22.0:
				for s in [-1.0, 1.0]:
					poles.append(Transform3D(Basis.IDENTITY, Vector3(xc + s * 8.6, 3.5, z)))
					heads.append(Transform3D(Basis.IDENTITY, Vector3(xc + s * 7.9, 7.0, z)))
			z -= 40.0
	var pm := CylinderMesh.new()
	pm.top_radius = 0.08
	pm.bottom_radius = 0.1
	pm.height = 7.0
	pm.radial_segments = 5
	pm.rings = 1
	_mm(pm, poles, Kit.mat(Color(0.25, 0.26, 0.27)))
	var hm := BoxMesh.new()
	hm.size = Vector3(0.7, 0.2, 0.7)
	lamp_mat = Kit.emit_mat(Color(1.0, 0.8, 0.55), 3.0)
	_mm(hm, heads, lamp_mat)


func _mm(mesh: Mesh, xfs: Array[Transform3D], m: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _cars() -> void:
	var xf: Array[Transform3D] = []
	var cus: Array[Color] = []
	var cols: Array[Color] = []
	var palette := [Color(0.85, 0.85, 0.85), Color(0.1, 0.1, 0.12), Color(0.55, 0.56, 0.6), Color(0.5, 0.1, 0.1),
		Color(0.2, 0.28, 0.45), Color(0.9, 0.9, 0.92), Color(0.3, 0.3, 0.32)]
	var lane := func(origin: Vector3, dir: Vector3, length: float) -> void:
		var n := int(length / rng.randf_range(45.0, 75.0))
		var spd := rng.randf_range(8.0, 13.0)
		for i in n:
			xf.append(Transform3D(Basis.looking_at(-dir), origin + Vector3(0, 0.65, 0)))
			cus.append(Color(length * (i + rng.randf_range(-0.3, 0.3)) / n, spd * rng.randf_range(0.9, 1.1), length, 0))
			cols.append(palette[rng.randi() % palette.size()])
	for kz in range(-24, 6):
		var zc := 30.0 + 60.0 * kz
		if absf(zc - CROSS.z) < 1.0:
			continue
		lane.call(Vector3(0, 0, zc - 3.5), Vector3(1, 0, 0), 1260.0)
		lane.call(Vector3(0, 0, zc + 3.5), Vector3(-1, 0, 0), 1260.0)
	for kx in range(-11, 11):
		var xc := 30.0 + 60.0 * kx
		if absf(xc - CROSS.x) < 1.0:
			continue
		lane.call(Vector3(xc + 3.5, 0, -560), Vector3(0, 0, 1), 1780.0)
		lane.call(Vector3(xc - 3.5, 0, -560), Vector3(0, 0, -1), 1780.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 1.3, 4.2)
	mm.mesh = bm
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
		mm.set_instance_custom_data(i, cus[i])
	mm.custom_aabb = AABB(Vector3(-700, -5, -1500), Vector3(1400, 20, 1900))
	var cm := ShaderMaterial.new()
	cm.shader = load("res://shaders/car.gdshader")
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = cm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _farlights() -> void:
	var xfs: Array[Transform3D] = []
	for i in 2600:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(0.0, 1.0)) * 1900.0 + 700.0
		var p := Vector3(sin(a) * r, 0.8, cos(a) * r - 500.0)
		if absf(p.x) < 650.0 and p.z < 350.0 and p.z > -1470.0:
			continue
		xfs.append(Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.8, 2.0)), p))
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	farlight_mat = Kit.emit_mat(Color(1.0, 0.75, 0.45), 2.0)
	_mm(bm, xfs, farlight_mat)


# ---------------------------------------------------------------- 当たり
func push_out(p: Vector3, r: float) -> Vector3:
	var k := Vector2i(roundi(p.x / 60.0), roundi(p.z / 60.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var kk := k + Vector2i(dx, dz)
			if not boxes.has(kk):
				continue
			for a: AABB in boxes[kk]:
				var mn := a.position - Vector3(r, 0, r)
				var mx := a.end + Vector3(r, r, r)
				if p.x <= mn.x or p.x >= mx.x or p.z <= mn.z or p.z >= mx.z or p.y >= mx.y:
					continue
				var pen := [p.x - mn.x, mx.x - p.x, p.z - mn.z, mx.z - p.z, mx.y - p.y]
				var m: float = pen.min()
				match pen.find(m):
					0: p.x = mn.x
					1: p.x = mx.x
					2: p.z = mn.z
					3: p.z = mx.z
					4: p.y = mx.y
	return p
