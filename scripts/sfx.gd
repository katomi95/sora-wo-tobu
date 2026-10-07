extends Node

# 音はすべて tools/gen_audio.py で合成した WAV。ループ設定はここで行う。

const NAMES := ["step0", "step1", "step2", "land", "whoosh", "sigh", "flap", "door", "kankan", "crow"]
const LOOPS := ["wind_roof", "wind_fly", "city", "drone", "bgm", "signal", "heli"]

var snd := {}
var loops := {}
var players: Array[AudioStreamPlayer] = []
var idx := 0
var muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		snd[n] = load("res://audio/%s.wav" % n)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	for n in LOOPS:
		var s: AudioStreamWAV = load("res://audio/%s.wav" % n).duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.volume_db = -80.0
		add_child(p)
		loops[n] = p


func set_mute(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)


func play(n: String, vol: float = 0.0, pitch: float = 1.0) -> void:
	if not snd.has(n):
		return
	var p := players[idx]
	idx = (idx + 1) % players.size()
	p.stream = snd[n]
	p.volume_db = vol
	p.pitch_scale = pitch
	p.play()


## ループ音を db まで t 秒でフェード（-60 以下で停止）
func fade(n: String, db: float, t: float = 1.0) -> void:
	var p: AudioStreamPlayer = loops[n]
	if p.has_meta("tw"):
		var old: Tween = p.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	if db > -60.0 and not p.playing:
		p.volume_db = -60.0
		p.play()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", db, maxf(t, 0.01))
	if db <= -60.0:
		tw.tween_callback(p.stop)
	p.set_meta("tw", tw)


func vol(n: String, db: float) -> void:
	var p: AudioStreamPlayer = loops[n]
	p.volume_db = db
	if not p.playing and db > -60.0:
		p.play()
