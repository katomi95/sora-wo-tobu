class_name Man
extends Node3D

# 主人公（くたびれた中年会社員）。前は -Z。
# 関節は Node3D の入れ子で、姿勢は数値の辞書を補間して動かす。

const POSES := {
	# lean=前かがみ, head=うつむき, arm=腕を前へ, out=腕を外へ, elb=肘, leg=脚を前へ, knee=膝, shrug=肩の上下
	# pitch=体ごと前に倒す（飛行）, roll=体の傾き
	"idle": {"lean": 11.0, "head": 24.0, "armL": 3.0, "armR": 5.0, "outL": 4.0, "outR": 5.0, "elbL": 8.0, "elbR": 12.0,
		"legL": 0.0, "legR": 0.0, "kneeL": 3.0, "kneeR": 2.0, "shrug": -0.03, "pitch": 0.0, "roll": 0.0, "lift": 0.0},
	"look_down": {"lean": 8.0, "head": 42.0, "armL": 2.0, "armR": 4.0, "outL": 3.0, "outR": 5.0, "elbL": 6.0, "elbR": 10.0,
		"legL": 0.0, "legR": 0.0, "kneeL": 2.0, "kneeR": 2.0, "shrug": -0.04, "pitch": 0.0, "roll": 0.0, "lift": 0.0},
	"walk": {"lean": 12.0, "head": 18.0, "armL": 0.0, "armR": 4.0, "outL": 4.0, "outR": 5.0, "elbL": 10.0, "elbR": 12.0,
		"legL": 0.0, "legR": 0.0, "kneeL": 4.0, "kneeR": 4.0, "shrug": -0.03, "pitch": 0.0, "roll": 0.0, "lift": 0.0},
	"step": {"lean": 4.0, "head": 8.0, "armL": 6.0, "armR": 8.0, "outL": 6.0, "outR": 6.0, "elbL": 10.0, "elbR": 12.0,
		"legL": 0.0, "legR": 30.0, "kneeL": 4.0, "kneeR": 25.0, "shrug": -0.01, "pitch": 6.0, "roll": 0.0, "lift": 0.0},
	"fly": {"lean": 10.0, "head": -22.0, "armL": -4.0, "armR": 50.0, "outL": 12.0, "outR": 6.0, "elbL": 38.0, "elbR": 10.0,
		"legL": 30.0, "legR": 18.0, "kneeL": 40.0, "kneeR": 52.0, "shrug": -0.02, "pitch": 44.0, "roll": 0.0, "lift": 0.0},
	"stand": {"lean": 4.0, "head": 4.0, "armL": 2.0, "armR": 4.0, "outL": 4.0, "outR": 5.0, "elbL": 8.0, "elbR": 10.0,
		"legL": 0.0, "legR": 0.0, "kneeL": 2.0, "kneeR": 2.0, "shrug": 0.0, "pitch": 0.0, "roll": 0.0, "lift": 0.0},
}

var pose: Dictionary = POSES["idle"].duplicate()
var target: Dictionary = POSES["idle"].duplicate()
var blend_rate := 3.0
var cur_pose := "idle"
var walk_speed := 0.0   # 0..1 歩きの強さ
var walk_phase := 0.0
var wind := 0.4         # ネクタイと上着のはためき
var fly_amt := 0.0      # 飛行時のぶらぶら
var breath := 0.0
var sigh_t := -1.0
var t := 0.0
var extra_roll := 0.0
var extra_pitch := 0.0
var step_cb: Callable

var body: Node3D
var torso: Node3D
var neck: Node3D
var head: Node3D
var sh_l: Node3D
var sh_r: Node3D
var el_l: Node3D
var el_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var kn_l: Node3D
var kn_r: Node3D
var tie1: Node3D
var tie2: Node3D
var tails: Node3D
var tails_back: Node3D


func _init() -> void:
	var suit := Kit.mat(Color(0.16, 0.17, 0.2), 0.75)
	var pants := Kit.mat(Color(0.14, 0.15, 0.17), 0.75)
	var shirt := Kit.mat(Color(0.86, 0.86, 0.83))
	var tie := Kit.mat(Color(0.45, 0.1, 0.12), 0.6)
	var skin := Kit.mat(Color(0.86, 0.67, 0.55))
	var hair := Kit.mat(Color(0.12, 0.11, 0.1))
	var dark := Kit.mat(Color(0.05, 0.05, 0.05), 0.4)
	var bag := Kit.mat(Color(0.1, 0.07, 0.05), 0.5)

	body = _pivot(self, Vector3(0, 0.95, 0))
	torso = _pivot(body, Vector3.ZERO)
	_box(torso, Vector3(0.4, 0.18, 0.26), Vector3(0, 0.04, 0), pants)
	_box(torso, Vector3(0.46, 0.5, 0.29), Vector3(0, 0.37, 0), suit)
	_box(torso, Vector3(0.42, 0.26, 0.05), Vector3(0, 0.24, -0.16), suit)
	_box(torso, Vector3(0.13, 0.24, 0.02), Vector3(0, 0.5, -0.15), shirt)
	_box(torso, Vector3(0.2, 0.06, 0.18), Vector3(0, 0.63, -0.04), shirt)
	# ゆるめたネクタイ
	_box(torso, Vector3(0.06, 0.05, 0.03), Vector3(0, 0.56, -0.165), tie)
	tie1 = _pivot(torso, Vector3(0, 0.54, -0.168))
	_box(tie1, Vector3(0.065, 0.2, 0.012), Vector3(0, -0.1, 0), tie)
	tie2 = _pivot(tie1, Vector3(0, -0.2, 0))
	_box(tie2, Vector3(0.08, 0.17, 0.012), Vector3(0, -0.08, 0), tie)
	# 上着の裾
	tails = _pivot(torso, Vector3(0, 0.12, -0.12))
	_box(tails, Vector3(0.44, 0.2, 0.04), Vector3(0, -0.1, 0), suit)
	tails_back = _pivot(torso, Vector3(0, 0.12, 0.13))
	_box(tails_back, Vector3(0.44, 0.22, 0.04), Vector3(0, -0.11, 0), suit)

	neck = _pivot(torso, Vector3(0, 0.62, 0))
	_box(neck, Vector3(0.09, 0.1, 0.09), Vector3(0, 0.04, 0), skin)
	head = _pivot(neck, Vector3(0, 0.06, 0))
	var hm := SphereMesh.new()
	hm.radius = 0.115
	hm.height = 0.25
	hm.radial_segments = 14
	hm.rings = 8
	Kit.add_mesh(head, hm, Vector3(0, 0.12, 0), skin)
	var hr := SphereMesh.new()
	hr.radius = 0.12
	hr.height = 0.2
	hr.radial_segments = 14
	hr.rings = 6
	var hmi := Kit.add_mesh(head, hr, Vector3(0, 0.13, 0.035), hair)
	hmi.scale = Vector3(1.03, 0.9, 0.92)
	# 薄くなった頭頂（肌色で上から覆う）
	var top := SphereMesh.new()
	top.radius = 0.09
	top.height = 0.08
	top.radial_segments = 12
	top.rings = 4
	Kit.add_mesh(head, top, Vector3(0, 0.215, 0.0), skin)
	# 眼鏡・眉（ハの字）・口
	for sx in [-0.048, 0.048]:
		_box(head, Vector3(0.07, 0.008, 0.008), Vector3(sx, 0.152, -0.114), dark)
		_box(head, Vector3(0.07, 0.006, 0.008), Vector3(sx, 0.112, -0.114), dark)
		_box(head, Vector3(0.006, 0.04, 0.008), Vector3(sx - 0.035, 0.132, -0.114), dark)
		_box(head, Vector3(0.006, 0.04, 0.008), Vector3(sx + 0.035, 0.132, -0.114), dark)
		_box(head, Vector3(0.016, 0.014, 0.006), Vector3(sx, 0.13, -0.111), dark)
	_box(head, Vector3(0.026, 0.006, 0.008), Vector3(0, 0.145, -0.116), dark)
	_box(head, Vector3(0.012, 0.012, 0.1), Vector3(0.1, 0.135, -0.06), dark)
	_box(head, Vector3(0.012, 0.012, 0.1), Vector3(-0.1, 0.135, -0.06), dark)
	var br := _box(head, Vector3(0.055, 0.012, 0.012), Vector3(0.045, 0.165, -0.108), hair)
	br.rotation.z = deg_to_rad(-16)
	var bl := _box(head, Vector3(0.055, 0.012, 0.012), Vector3(-0.045, 0.165, -0.108), hair)
	bl.rotation.z = deg_to_rad(16)
	_box(head, Vector3(0.045, 0.008, 0.01), Vector3(0, 0.065, -0.11), Kit.mat(Color(0.45, 0.25, 0.22)))
	_box(head, Vector3(0.03, 0.04, 0.03), Vector3(0, 0.105, -0.12), skin)

	sh_r = _pivot(torso, Vector3(0.255, 0.56, 0))
	sh_l = _pivot(torso, Vector3(-0.255, 0.56, 0))
	for side in [[sh_r, 1.0], [sh_l, -1.0]]:
		var sh: Node3D = side[0]
		_box(sh, Vector3(0.13, 0.32, 0.14), Vector3(0, -0.15, 0), suit)
		var el := _pivot(sh, Vector3(0, -0.3, 0))
		_box(el, Vector3(0.11, 0.26, 0.12), Vector3(0, -0.12, 0), suit)
		_box(el, Vector3(0.1, 0.04, 0.11), Vector3(0, -0.26, 0), shirt)
		var hand := SphereMesh.new()
		hand.radius = 0.048
		hand.height = 0.11
		hand.radial_segments = 8
		hand.rings = 4
		Kit.add_mesh(el, hand, Vector3(0, -0.31, 0), skin)
		if side[1] > 0.0:
			el_r = el
			# 鞄
			_box(el, Vector3(0.025, 0.05, 0.12), Vector3(0, -0.36, 0), bag)
			_box(el, Vector3(0.09, 0.3, 0.42), Vector3(0, -0.53, 0), bag)
			_box(el, Vector3(0.092, 0.02, 0.06), Vector3(0, -0.42, -0.1), Kit.mat(Color(0.6, 0.55, 0.4), 0.3))
		else:
			el_l = el

	hip_r = _pivot(body, Vector3(0.11, 0, 0))
	hip_l = _pivot(body, Vector3(-0.11, 0, 0))
	for hp in [hip_r, hip_l]:
		_box(hp, Vector3(0.17, 0.47, 0.19), Vector3(0, -0.22, 0), pants)
		var kn := _pivot(hp, Vector3(0, -0.46, 0))
		_box(kn, Vector3(0.15, 0.44, 0.16), Vector3(0, -0.21, 0), pants)
		_box(kn, Vector3(0.115, 0.08, 0.28), Vector3(0, -0.45, -0.05), dark)
		if hp == hip_r:
			kn_r = kn
		else:
			kn_l = kn

	for c in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	return Kit.box_node(parent, size, pos, m)


func set_pose(name: String, rate := 3.0) -> void:
	if name == cur_pose and is_equal_approx(rate, blend_rate):
		return
	cur_pose = name
	target = POSES[name].duplicate()
	blend_rate = rate


func snap_pose(name: String) -> void:
	cur_pose = name
	target = POSES[name].duplicate()
	pose = POSES[name].duplicate()


func sigh() -> void:
	sigh_t = 0.0


func update(dt: float) -> void:
	t += dt
	var k := 1.0 - exp(-blend_rate * dt)
	for key in pose:
		pose[key] = lerpf(pose[key], target[key], k)
	var p := pose
	breath += dt

	var lean: float = p["lean"]
	var hd: float = p["head"]
	var shrug: float = p["shrug"] + sin(breath * 1.6) * 0.006
	# ため息：肩が上がって、落ちる
	if sigh_t >= 0.0:
		sigh_t += dt
		var s := sigh_t
		var up := smoothstep(0.0, 0.6, s) * (1.0 - smoothstep(0.75, 1.4, s))
		shrug += up * 0.045 - smoothstep(0.8, 1.6, s) * 0.02 * (1.0 - smoothstep(2.2, 3.5, s))
		hd += smoothstep(0.8, 1.6, s) * 10.0 * (1.0 - smoothstep(2.5, 4.0, s))
		lean += smoothstep(0.9, 1.6, s) * 4.0 * (1.0 - smoothstep(2.5, 4.0, s))
		if s > 4.0:
			sigh_t = -1.0

	# 歩き
	var sw := 0.0
	var bob := 0.0
	if walk_speed > 0.01:
		var prev := walk_phase
		walk_phase += dt * 5.2 * walk_speed
		sw = sin(walk_phase) * walk_speed
		bob = abs(cos(walk_phase)) * 0.025 * walk_speed
		if step_cb.is_valid() and floor(prev / PI) != floor(walk_phase / PI):
			step_cb.call()

	# 飛行中のぶらぶら
	var fl := fly_amt
	var dang := sin(t * 1.3) * 6.0 * fl
	var dang2 := sin(t * 1.1 + 1.3) * 7.0 * fl

	body.position.y = 0.95 + bob + p["lift"]
	body.rotation = Vector3(deg_to_rad(-(p["pitch"] + extra_pitch)), 0, deg_to_rad(p["roll"] + extra_roll))
	torso.rotation.x = deg_to_rad(-lean)
	neck.rotation.x = deg_to_rad(-hd * 0.4)
	head.rotation.x = deg_to_rad(-hd * 0.6)
	sh_r.position.y = 0.56 + shrug
	sh_l.position.y = 0.56 + shrug
	sh_l.rotation = Vector3(deg_to_rad(p["armL"] - sw * 12.0 + dang * 0.5), 0, deg_to_rad(-p["outL"]))
	sh_r.rotation = Vector3(deg_to_rad(p["armR"] + sw * 8.0 + dang2 * 0.4), 0, deg_to_rad(p["outR"]))
	el_l.rotation.x = deg_to_rad(p["elbL"] + max(0.0, -sw) * 8.0)
	el_r.rotation.x = deg_to_rad(p["elbR"] + max(0.0, sw) * 6.0)
	hip_l.rotation.x = deg_to_rad(p["legL"] + sw * 22.0 + dang)
	hip_r.rotation.x = deg_to_rad(p["legR"] - sw * 22.0 - dang2)
	kn_l.rotation.x = deg_to_rad(-(p["kneeL"] + max(0.0, -sw) * 28.0 + dang2 * 0.6))
	kn_r.rotation.x = deg_to_rad(-(p["kneeR"] + max(0.0, sw) * 28.0 + dang * 0.6))

	# ネクタイと上着のはためき
	var w := wind
	var f1 := sin(t * 7.0) * 0.5 + sin(t * 11.3 + 1.0) * 0.5
	var f2 := sin(t * 9.1 + 2.0) * 0.6 + sin(t * 15.7) * 0.4
	tie1.rotation.x = deg_to_rad(-lean * 0.6 + (8.0 + f1 * 14.0) * w + 25.0 * fl)
	tie1.rotation.z = deg_to_rad(f2 * 10.0 * w)
	tie2.rotation.x = deg_to_rad((f2 * 22.0) * w + 10.0 * fl)
	tails.rotation.x = deg_to_rad(-(4.0 + f1 * 6.0) * w - 30.0 * fl)
	tails_back.rotation.x = deg_to_rad((6.0 + f2 * 8.0) * w + 35.0 * fl)
