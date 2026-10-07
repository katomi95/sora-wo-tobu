extends Node3D

# そらをとぶ
# タイトル → 屋上（不穏）→ 縁まで歩く →「飛ぶ」→ お先失礼します〜 → 帰宅飛行 → ベランダ → 暗転

const GAP_Z := -16.6
const FLY_MAX := 8.5
const FLY_IDLE := 1.4
const LINES := ["ちょっと寒いな", "明日早いんだよなあ", "腹減ったな", "あ、ゴミ出し明日か"]
const WAYPOINTS := [Vector3(-6, 82, -150), Vector3(0, 78, -300), Vector3(8, 62, -420), Vector3(28, 42, -505),
	Vector3(10, 38, -620), Vector3(-25, 34, -715), Vector3(-30, 28, -815), Vector3(40, 30, -950)]

var city: City
var man: Man
var hud: Hud
var cam: Camera3D
var flock: Actors.Flock
var heli: Actors.Heli
var plane: Actors.Airplane
var gust_fx: CPUParticles3D

var state := "title"
var gt := 0.0          # 経過時間（ゲーム内）
var st := 0.0          # 状態に入ってからの時間
var busy := false      # 演出中（操作不可）

# 飛行
var pos := Vector3.ZERO
var heading := 0.0
var speed := 0.0
var vy := 0.0
var yaw_v := 0.0
var push := Vector3.ZERO
var gust_t := -1.0
var tod := 0.0
var start_dist := 1.0
var done := {}
var last_line := 0.0  # 飛行開始で上書き
var next_line := 26.0
var line_pool: Array = []
var bound_said := false
var knock := Vector3.ZERO

# カメラ
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_mode := "free"   # free / walk / chase / fixed
var cam_k := 3.0

# 起動引数
var autoplay := false
var quit_at_end := false
var shots_dir := ""
var shot_times: Array = []
var bot_wp := 0
var phase_arg := ""
var arg_pos := Vector3.INF
var arg_head := 0.0
var arg_tod := -1.0
var arg_look := Vector3.INF


func _ready() -> void:
	_parse_args()
	city = City.new()
	add_child(city)
	city.build()

	man = Man.new()
	add_child(man)
	man.step_cb = func() -> void: Sfx.play("step" + str(randi() % 3), -10.0, randf_range(0.9, 1.05))

	flock = Actors.Flock.new()
	add_child(flock)
	heli = Actors.Heli.new()
	heli.center = Vector3(300, 140, -560)
	add_child(heli)
	plane = Actors.Airplane.new()
	plane.position = Vector3(-1800, 700, -1500)
	plane.vel = Vector3(26, 0, 5)
	add_child(plane)
	_make_gust_fx()

	cam = Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.1
	cam.far = 7000.0
	add_child(cam)
	cam.make_current()

	hud = Hud.new()
	add_child(hud)

	line_pool = LINES.duplicate()
	line_pool.shuffle()
	start_dist = _hdist(Vector3(0, 0, -20), City.HOME_STAND)

	# 屋上のフェンス際でうなだれている
	man.position = Vector3(7.0, City.ROOF_Y, -16.3)
	man.snap_pose("look_down")
	man.wind = 0.6
	_set_cam(Vector3(15, 97.5, 8), Vector3(3, 90, -40), "fixed")

	if arg_tod >= 0.0:
		city.set_tod(arg_tod)
	match phase_arg:
		"walk":
			hud.fade(0.0, 0.3)
			_ambience_roof()
			_begin_walk()
		"fly":
			hud.fade(0.0, 0.3)
			_begin_fly(Vector3(0, City.ROOF_Y + 0.8, -22) if arg_pos == Vector3.INF else arg_pos, deg_to_rad(arg_head))
		"end":
			hud.fade(0.0, 0.3)
			bot_wp = WAYPOINTS.size()
			_begin_fly(City.HOME_STAND + Vector3(0, 3, 30), 0.0)
		_:
			_title()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = true
		elif a == "--quit":
			quit_at_end = true
		elif a == "--mute":
			Sfx.set_mute(true)
		elif a.begins_with("--fast="):
			Engine.time_scale = float(a.substr(7))
		elif a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a.begins_with("--at="):
			for s in a.substr(5).split(","):
				shot_times.append(float(s))
		elif a.begins_with("--phase="):
			phase_arg = a.substr(8)
		elif a.begins_with("--pos="):
			var v := a.substr(6).split(",")
			arg_pos = Vector3(float(v[0]), float(v[1]), float(v[2]))
		elif a.begins_with("--head="):
			arg_head = float(a.substr(7))
		elif a.begins_with("--tod="):
			arg_tod = float(a.substr(6))
		elif a.begins_with("--look="):
			var v := a.substr(7).split(",")
			arg_look = Vector3(float(v[0]), float(v[1]), float(v[2]))


# ---------------------------------------------------------------- タイトル・導入
func _title() -> void:
	state = "title"
	hud.fade(0.0, 3.0)
	_ambience_roof()
	await get_tree().create_timer(1.2).timeout
	if state == "title":
		hud.show_title(true, 2.0, "クリック または スペースキーで はじめる")


func _ambience_roof() -> void:
	Sfx.fade("wind_roof", -7.0, 2.0)
	Sfx.fade("city", -24.0, 2.0)


func _start_intro() -> void:
	state = "intro"
	busy = true
	hud.show_title(false, 1.2)
	Sfx.fade("drone", -13.0, 4.0)
	# 1. 背中越しの夕焼け
	_set_cam(Vector3(15, 97.5, 8), Vector3(3, 90, -40), "fixed")
	var tw := create_tween()
	tw.tween_property(self, "cam_pos", Vector3(11, 94.5, 1), 6.0).set_trans(Tween.TRANS_SINE)
	await _wait(3.0)
	Sfx.play("crow", -16.0)
	await _wait(3.0)
	# 2. 横顔。ため息
	tw.kill()
	_set_cam(Vector3(10.2, 91.25, -18.6), Vector3(7.0, 91.35, -16.1), "fixed")
	tw = create_tween()
	tw.tween_property(self, "cam_pos", Vector3(9.6, 91.2, -18.2), 5.0)
	await _wait(1.0)
	man.sigh()
	Sfx.play("sigh", -4.0)
	await _wait(4.0)
	# 3. 見下ろす（はるか下の道路）
	tw.kill()
	_set_cam(Vector3(7.2, 91.7, -18.3), Vector3(6.6, 0.0, -38.0), "fixed")
	tw = create_tween()
	tw.tween_property(self, "cam_look", Vector3(6.8, 0.0, -30.0), 3.5).set_trans(Tween.TRANS_SINE)
	await _wait(3.5)
	tw.kill()
	_begin_walk()


func _begin_walk() -> void:
	state = "walk"
	busy = false
	st = 0.0
	man.set_pose("walk", 2.0)
	cam_mode = "walk"
	_walk_cam(true)
	hud.show_hint("WASD / 矢印キー：歩く", 6.0)


# ---------------------------------------------------------------- 屋上を歩く
func _walk(dt: float) -> void:
	var inp := Vector2.ZERO
	if autoplay:
		var to := Vector2(0.0, -17.3) - Vector2(man.position.x, man.position.z)
		if to.length() > 0.2:
			inp = to.normalized()
	else:
		if _key(KEY_W) or _key(KEY_UP):
			inp.y -= 1
		if _key(KEY_S) or _key(KEY_DOWN):
			inp.y += 1
		if _key(KEY_A) or _key(KEY_LEFT):
			inp.x -= 1
		if _key(KEY_D) or _key(KEY_RIGHT):
			inp.x += 1
		inp = inp.normalized()
	var moving := inp.length() > 0.1
	man.walk_speed = move_toward(man.walk_speed, 1.0 if moving else 0.0, dt * 4.0)
	if moving:
		var p := man.position + Vector3(inp.x, 0, inp.y) * 1.15 * dt
		man.position = city.roof_block(p)
		var want := atan2(-inp.x, -inp.y)
		man.rotation.y = lerp_angle(man.rotation.y, want, 1.0 - exp(-6.0 * dt))
	var at_edge := absf(man.position.x) < 1.9 and man.position.z < GAP_Z
	if at_edge and state == "walk":
		state = "edge"
		man.set_pose("look_down", 2.0)
		hud.show_prompt("［Space］　飛ぶ")
	elif not at_edge and state == "edge":
		state = "walk"
		man.set_pose("walk", 2.0)
		hud.show_prompt("")
	if state == "walk" and not moving:
		man.set_pose("idle", 2.0)
	elif state == "walk" and moving:
		man.set_pose("walk", 2.0)
	if state == "edge" and autoplay and st > 0.0:
		if not done.has("bot_edge"):
			done["bot_edge"] = gt
		elif gt - done["bot_edge"] > 1.5:
			_jump()
	_walk_cam(false)


func _walk_cam(snap: bool) -> void:
	var p := man.position
	var to := p + Vector3(1.6, 1.85, 4.2)
	var look := p + Vector3(-0.6, 1.0, -4.0)
	if snap:
		_set_cam(to, look, "walk")
	else:
		cam_pos = to
		cam_look = look


# ---------------------------------------------------------------- 飛ぶ
func _jump() -> void:
	if busy:
		return
	busy = true
	state = "jump"
	hud.show_prompt("")
	man.walk_speed = 0.0
	Sfx.fade("drone", -60.0, 2.5)
	# 正面を向いて、しばし立ち尽くす
	var tw := create_tween()
	tw.tween_property(man, "rotation:y", 0.0, 0.6)
	tw.parallel().tween_property(man, "position:x", clampf(man.position.x, -0.8, 0.8), 0.6)
	man.set_pose("look_down", 2.0)
	await _wait(0.9)
	_set_cam(Vector3(5.2, 90.2, -22.5), Vector3(0.0, 90.9, -17.6), "fixed")
	await _wait(0.5)
	# パラペットに上がる
	man.set_pose("step", 4.0)
	Sfx.play("step1", -8.0)
	tw = create_tween()
	tw.tween_property(man, "position", Vector3(man.position.x, City.ROOF_Y + 0.5, -17.82), 0.7).set_trans(Tween.TRANS_SINE)
	await _wait(0.7)
	Sfx.play("step2", -9.0)
	man.set_pose("look_down", 3.0)
	man.wind = 1.0
	Sfx.fade("wind_roof", -3.0, 1.5)
	tw = create_tween()
	tw.tween_property(self, "cam_pos", Vector3(4.2, 90.5, -21.6), 3.0).set_trans(Tween.TRANS_SINE)
	await _wait(3.0)
	# 踏み出す → 一瞬沈む（最上階の窓に部長）→ ふわっと戻る
	man.set_pose("step", 3.0)
	await _wait(0.35)
	var p0 := man.position
	_set_cam(Vector3(4.6, 88.4, -24.6), p0 + Vector3(0, 1.0, 0), "track")
	Sfx.play("whoosh", -10.0, 0.85)
	Sfx.fade("wind_roof", -60.0, 2.5)
	tw = create_tween()
	tw.tween_property(man, "position", p0 + Vector3(0, -3.0, -0.9), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(man, "position", p0 + Vector3(0, -3.3, -1.1), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(man, "position", p0 + Vector3(0, 0.5, -1.7), 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _wait(0.55)
	man.set_pose("stand", 2.5)
	await _wait(1.9)
	# 浮かび上がって、進みはじめてから
	Sfx.fade("wind_fly", -18.0, 2.0)
	Sfx.fade("city", -17.0, 3.0)
	pos = man.position
	heading = 0.0
	speed = 0.4
	state = "takeoff"
	st = 0.0
	man.set_pose("fly", 1.1)
	await _wait(1.0)
	hud.say("お先失礼します〜", 2.6)


func _takeoff(dt: float) -> void:
	# 浮かび上がったあとは、そのまま水平に滑り出す
	speed = move_toward(speed, 3.2, dt * 1.2)
	pos += Vector3(0, 0, -1) * speed * dt
	pos.y = move_toward(pos.y, City.ROOF_Y + 1.0, dt * 0.25)
	man.fly_amt = move_toward(man.fly_amt, 1.0, dt * 0.6)
	man.wind = move_toward(man.wind, 0.7, dt * 0.3)
	man.position = pos
	if st > 3.4 and cam_mode != "chase":
		cam_mode = "chase"
		cam_k = 1.2
	if st > 5.2:
		_begin_fly(pos, 0.0, false)


func _begin_fly(p: Vector3, h: float, fresh := true) -> void:
	state = "fly"
	busy = false
	st = 0.0
	last_line = gt - 8.0
	pos = p
	heading = h
	if fresh:
		speed = 3.0
		man.snap_pose("fly")
		man.fly_amt = 1.0
		man.wind = 0.7
		Sfx.fade("wind_fly", -18.0, 1.0)
		Sfx.fade("city", -17.0, 1.0)
		cam_k = 3.0
		_set_cam(pos + Vector3(0, 2.2, 7), pos + Vector3(0, 0.3, -8), "chase")
	man.position = pos
	cam_mode = "chase"
	var tw := create_tween()
	tw.tween_property(self, "cam_k", 3.0, 3.0)
	hud.show_hint("W：前へ　　A / D：曲がる\nSpace：上昇　　Shift：下降", 8.0)
	await _wait(3.0)
	if state == "fly":
		Sfx.fade("bgm", -12.0, 6.0)


func _fly(dt: float) -> void:
	var fwd_in := 0.0
	var turn_in := 0.0
	var up_in := 0.0
	if autoplay:
		var wps := WAYPOINTS + [City.HOME_STAND + Vector3(0, 1.0, 5.0)]
		var tgt: Vector3 = wps[mini(bot_wp, wps.size() - 1)]
		var d := tgt - pos
		if Vector2(d.x, d.z).length() < 14.0 and bot_wp < wps.size() - 1:
			bot_wp += 1
		var want := atan2(-d.x, -d.z)
		turn_in = clampf(angle_difference(heading, want) * 2.0, -1.0, 1.0)
		up_in = clampf(d.y * 0.3, -1.0, 1.0)
		fwd_in = 1.0 if Vector2(d.x, d.z).length() > 25.0 or absf(turn_in) < 0.5 else 0.3
	else:
		if _key(KEY_W) or _key(KEY_UP):
			fwd_in = 1.0
		if _key(KEY_S) or _key(KEY_DOWN):
			fwd_in = -1.0
		if _key(KEY_A) or _key(KEY_LEFT):
			turn_in += 1.0
		if _key(KEY_D) or _key(KEY_RIGHT):
			turn_in -= 1.0
		if _key(KEY_SPACE):
			up_in += 1.0
		if _key(KEY_SHIFT) or _key(KEY_CTRL) or _key(KEY_C):
			up_in -= 1.0

	var want_spd := FLY_MAX if fwd_in > 0.0 else (0.0 if fwd_in < 0.0 else FLY_IDLE)
	speed = move_toward(speed, want_spd, dt * (1.6 if want_spd > speed else 2.4))
	yaw_v = lerpf(yaw_v, turn_in * 0.8, 1.0 - exp(-3.0 * dt))
	heading += yaw_v * dt
	vy = lerpf(vy, up_in * (4.0 if up_in > 0.0 else 5.0), 1.0 - exp(-2.5 * dt))
	var f := Vector3(-sin(heading), 0, -cos(heading))
	var vel := f * speed + Vector3(0, vy, 0) + push + knock
	knock = knock.move_toward(Vector3.ZERO, dt * 4.0)
	pos += vel * dt
	pos.y = clampf(pos.y, 4.0, 230.0)
	pos = city.push_out(pos, 1.0)
	# 行き過ぎ
	var b := Vector2(clampf(pos.x, -650.0, 650.0), clampf(pos.z, -1450.0, 250.0))
	if b != Vector2(pos.x, pos.z):
		pos.x = lerpf(pos.x, b.x, 1.0 - exp(-2.0 * dt))
		pos.z = lerpf(pos.z, b.y, 1.0 - exp(-2.0 * dt))
		if not bound_said:
			bound_said = true
			hud.say("おっと、行きすぎた", 2.4)

	man.position = pos + Vector3(0, sin(gt * 1.3) * 0.08, 0)
	man.rotation.y = heading
	man.extra_roll = lerpf(man.extra_roll, yaw_v * 22.0 + push.x * 0.0, 1.0 - exp(-3.0 * dt))
	man.extra_pitch = lerpf(man.extra_pitch, (speed - 4.0) * 1.6 - vy * 5.0, 1.0 - exp(-2.0 * dt))
	man.wind = lerpf(man.wind, 0.45 + speed * 0.06 + push.length() * 0.15, 1.0 - exp(-2.0 * dt))
	Sfx.vol("wind_fly", -24.0 + speed * 0.9 + push.length() * 1.5)

	# 夕方から夜へ（家に近づくほど暗くなる）
	var prog := clampf(1.0 - _hdist(pos, City.HOME_STAND) / start_dist, 0.0, 1.0)
	var want_tod := lerpf(0.06, 0.93, prog)
	if arg_tod < 0.0:
		tod = maxf(tod, lerpf(tod, want_tod, 1.0 - exp(-0.5 * dt)))
		city.set_tod(tod)

	_events(dt)

	# 着地
	var land_pt := City.HOME_STAND + Vector3(0, 0.6, 3.0)
	if _hdist(pos, land_pt) < 7.5 and absf(pos.y - land_pt.y) < 5.0:
		_land()


# ---------------------------------------------------------------- 道中の出来事
func _events(dt: float) -> void:
	# よその会社もまだ残業している
	if not done.has("office") and pos.distance_to(City.OFFICE_WIN) < 70.0:
		done["office"] = gt
		_line("あ、まだ残ってる", 3.0)
	# ビル風
	if not done.has("gust") and pos.z < -280.0:
		done["gust"] = gt
		gust_t = 0.0
		Sfx.fade("wind_fly", -6.0, 0.8)
		gust_fx.emitting = true
	if gust_t >= 0.0:
		gust_t += dt
		var r := Vector3(cos(heading), 0, -sin(heading))
		var k := smoothstep(0.0, 1.0, gust_t) * (1.0 - smoothstep(3.5, 5.5, gust_t))
		push = r * 5.5 * k
		if gust_t > 1.4 and not done.has("gust_line"):
			done["gust_line"] = gt
			_line("今日は風あるなあ", 3.0)
		if gust_t > 5.5:
			gust_t = -1.0
			push = Vector3.ZERO
			gust_fx.emitting = false
	gust_fx.global_position = pos + Vector3(0, 0.8, 0)
	gust_fx.rotation.y = heading
	# 鳥の群れ（前方を横切る）
	if not done.has("birds") and pos.z < -385.0:
		done["birds"] = gt
		var f := Vector3(-sin(heading), 0, -cos(heading))
		var r := Vector3(cos(heading), 0, -sin(heading))
		flock.launch(pos + f * 55.0 - r * 48.0 + Vector3(0, 0.5, 0), r * 8.5 - f * 1.0)
		Sfx.play("flap", -18.0)
	flock.update(dt)
	if flock.near(pos + Vector3(0, 0.9, 0), 3.2):
		flock.scatter(pos)
		Sfx.play("flap", -3.0)
		knock = Vector3(0, 1.5, 0) - Vector3(-sin(heading), 0, -cos(heading)) * 3.0
		if not done.has("otto"):
			done["otto"] = gt
			_line("おっと", 1.6)
	# 信号待ち
	if not done.has("cross") and _hdist(pos, City.CROSS) < 120.0:
		done["cross"] = gt
		_line("ここの信号、長いんだよな", 3.2)
	if done.has("cross") and not city.crossing and gt - done["cross"] > 3.2:
		city.start_crossing()
	if city.crossing:
		var d := pos.distance_to(City.CROSS)
		Sfx.vol("signal", clampf(-8.0 - d * 0.35, -60.0, -10.0) if city.cross_t < 30.0 else -80.0)
	# 川を渡ると遠くで踏切
	if not done.has("kankan") and pos.z < -590.0:
		done["kankan"] = gt
		Sfx.play("kankan", -20.0)
	# スーパー
	if not done.has("super") and _hdist(pos, City.SUPER) < 110.0:
		done["super"] = gt
		_line("スーパー寄ってくか", 2.8)
		_line_later("……いや、いいか", 4.5, 2.4)
	# 洗濯物
	if not done.has("laundry") and pos.distance_to(City.LAUNDRY) < 75.0:
		done["laundry"] = gt
		_line("明日雨か……", 3.0)
	# ヘリの音
	var hd := pos.distance_to(heli.position)
	Sfx.vol("heli", clampf(-6.0 - hd * 0.12, -60.0, -14.0))
	# ふと出る独り言
	if gt - last_line > next_line and not line_pool.is_empty() and _hdist(pos, City.HOME_STAND) > 160.0:
		_line(line_pool.pop_back(), 3.0)
		next_line = randf_range(24.0, 32.0)


func _line(text: String, dur: float) -> void:
	last_line = gt
	hud.say(text, dur)
	print("LINE t=", snappedf(gt, 0.1), " ", text)


func _line_later(text: String, delay: float, dur: float) -> void:
	await _wait(delay)
	_line(text, dur)


# ---------------------------------------------------------------- 着地・おわり
func _land() -> void:
	if busy:
		return
	busy = true
	state = "land"
	print("LANDED t=", snappedf(gt, 0.1))
	Sfx.fade("bgm", -26.0, 3.0)
	Sfx.fade("wind_fly", -60.0, 2.5)
	Sfx.fade("heli", -60.0, 1.0)
	gust_fx.emitting = false
	var stand := City.HOME_STAND
	_set_cam(cam.global_position, cam_look, "fixed")
	var ctw := create_tween().set_parallel(true)
	ctw.tween_property(self, "cam_pos", stand + Vector3(2.4, 2.1, 4.4), 2.6).set_trans(Tween.TRANS_SINE)
	ctw.tween_property(self, "cam_look", stand + Vector3(-0.4, 0.95, -0.6), 2.6).set_trans(Tween.TRANS_SINE)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(man, "position", stand, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(man, "rotation:y", 0.0, 1.6)
	tw.tween_property(man, "fly_amt", 0.0, 1.8)
	tw.tween_property(man, "extra_roll", 0.0, 1.0)
	tw.tween_property(man, "extra_pitch", 0.0, 1.0)
	tw.tween_property(man, "wind", 0.15, 2.0)
	man.set_pose("stand", 2.2)
	await _wait(2.2)
	Sfx.play("land", -8.0)
	man.set_pose("idle", 2.0)
	await _wait(1.2)
	# サッシを開ける
	man.rotation.y = 0.0
	Sfx.play("door", -6.0)
	var cur := city.home_curtain
	var ct := create_tween()
	ct.tween_property(cur, "scale:x", 0.45, 0.8)
	ct.parallel().tween_property(cur, "position:x", cur.position.x - 0.75, 0.8)
	ct.parallel().tween_property(city.home_light, "light_energy", 2.2, 0.8)
	await _wait(1.0)
	hud.say("ただいまー", 1.6)
	await _wait(2.4)
	hud.say("おかえり。今日遅かったね", 2.6, Color(1.0, 0.88, 0.7))
	await _wait(3.5)
	man.set_pose("stand", 2.0)
	hud.say("ちょっと向かい風強くて", 2.6)
	await _wait(3.6)
	# 部屋に入る
	man.walk_speed = 0.6
	var wt := create_tween()
	wt.tween_property(man, "position", City.HOME_DOOR + Vector3(0, 0, -1.2), 1.6)
	await _wait(1.0)
	hud.fade(1.0, 1.6)
	Sfx.fade("bgm", -60.0, 3.0)
	Sfx.fade("city", -60.0, 3.0)
	Sfx.fade("signal", -60.0, 1.0)
	await _wait(2.6)
	man.visible = false
	state = "end"
	st = 0.0
	print("ENDING REACHED t=", snappedf(gt, 0.1))
	hud.show_title(true, 2.0)
	await _wait(3.0)
	hud.title_sub.text = "おわり"
	var tw2 := create_tween()
	tw2.tween_property(hud.title_sub, "modulate:a", 1.0, 1.5)
	if quit_at_end:
		await _wait(1.0)
		get_tree().quit()


# ---------------------------------------------------------------- 毎フレーム
func _process(dt: float) -> void:
	gt += dt
	st += dt
	match state:
		"walk", "edge":
			_walk(dt)
		"takeoff":
			_takeoff(dt)
		"fly":
			_fly(dt)
		"title":
			if autoplay and gt > 1.0:
				_start_intro()
	man.update(dt)
	city.update(dt)
	heli.update(dt)
	plane.update(dt)
	_camera(dt)
	hud.update_nav(cam, City.HOME_STAND, pos, state == "fly")
	_shots()


func _camera(dt: float) -> void:
	match cam_mode:
		"track":
			cam.position = cam_pos
			_look(man.position + Vector3(0, 0.9, 0), 1.0 - exp(-5.0 * dt))
			return
		"walk":
			var k := 1.0 - exp(-3.0 * dt)
			cam.position = cam.position.lerp(cam_pos, k)
			_look(cam_look, k)
			return
		"chase":
			var f := Vector3(-sin(heading), 0, -cos(heading))
			var p := man.position if state == "takeoff" else pos
			cam_pos = p - f * 4.6 + Vector3(0, 1.5 - vy * 0.15, 0)
			cam_look = p + f * 7.0 + Vector3(0, 0.3, 0)
			var k := 1.0 - exp(-cam_k * dt)
			cam.position = cam.position.lerp(cam_pos, k)
			_look(cam_look, k)
			return
	cam.position = cam_pos
	if arg_look != Vector3.INF:
		cam_look = arg_look
	cam.look_at(cam_look, Vector3.UP)


var _cur_look := Vector3.ZERO


func _look(target: Vector3, k: float) -> void:
	_cur_look = _cur_look.lerp(target, k)
	cam.look_at(_cur_look, Vector3.UP)


func _set_cam(p: Vector3, look: Vector3, mode: String) -> void:
	cam_pos = p
	cam_look = look
	_cur_look = look
	cam_mode = mode
	cam.position = p
	cam.look_at(look, Vector3.UP)


func _unhandled_input(e: InputEvent) -> void:
	var press := false
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_M:
			Sfx.set_mute(not Sfx.muted)
			return
		press = e.physical_keycode == KEY_SPACE or e.physical_keycode == KEY_ENTER
	if e is InputEventMouseButton and e.pressed:
		press = true
	if not press:
		return
	match state:
		"title":
			_start_intro()
		"edge":
			_jump()
		"end":
			if st > 3.0:
				get_tree().reload_current_scene()


func _key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)


func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _wait(t: float) -> Signal:
	return get_tree().create_timer(t).timeout


func _make_gust_fx() -> void:
	gust_fx = CPUParticles3D.new()
	gust_fx.emitting = false
	gust_fx.amount = 22
	gust_fx.lifetime = 0.6
	gust_fx.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(1.8, 0.02)
	gust_fx.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.2, 0.19, 0.19)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	gust_fx.material_override = m
	gust_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	gust_fx.emission_box_extents = Vector3(6, 3, 6)
	gust_fx.direction = Vector3(1, 0, 0)
	gust_fx.spread = 4.0
	gust_fx.gravity = Vector3.ZERO
	gust_fx.initial_velocity_min = 14.0
	gust_fx.initial_velocity_max = 20.0
	gust_fx.particle_flag_align_y = false
	add_child(gust_fx)


# ---------------------------------------------------------------- 撮影（検証用）
func _shots() -> void:
	if shots_dir == "" or shot_times.is_empty():
		return
	if gt >= float(shot_times[0]):
		var t: float = shot_times.pop_front()
		DirAccess.make_dir_recursive_absolute(shots_dir)
		var img := get_viewport().get_texture().get_image()
		var path := shots_dir + "/shot_" + str(snappedf(t, 0.1)).replace(".", "_") + ".png"
		img.save_png(path)
		print("SHOT ", path)
		if shot_times.is_empty() and quit_at_end:
			get_tree().quit()
