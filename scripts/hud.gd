class_name Hud
extends CanvasLayer

# 字幕・操作表示・自宅の目印・暗転・タイトル

var serif: Font = load("res://fonts/serif.ttf")
var root: Control
var fade_rect: ColorRect
var title: Label
var title_sub: Label
var sub: Label
var prompt: Label
var hint: Label
var nav: Label
var marker: Label
var queue: Array = []
var sub_busy := false
var prompt_t := 0.0


func _init() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	marker = _label(22, Color(1.0, 0.92, 0.75), 6)
	marker.text = "自宅\n▼"
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.size = Vector2(80, 70)
	marker.visible = false

	sub = _label(30, Color(1, 1, 1), 10)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.anchor_left = 0.0
	sub.anchor_right = 1.0
	sub.offset_left = 20
	sub.offset_right = -20
	sub.offset_top = -120
	sub.offset_bottom = -60
	sub.modulate.a = 0.0

	prompt = _label(30, Color(1, 1, 1), 8)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.anchor_left = 0.0
	prompt.anchor_right = 1.0
	prompt.offset_top = 90
	prompt.offset_bottom = 140
	prompt.visible = false

	hint = _label(19, Color(1, 1, 1, 0.85), 6)
	hint.position = Vector2(28, 24)
	hint.modulate.a = 0.0

	nav = _label(20, Color(1, 0.95, 0.85, 0.9), 6)
	nav.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	nav.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nav.offset_left = -320
	nav.offset_top = -56
	nav.offset_right = -28
	nav.offset_bottom = -24
	nav.visible = false

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade_rect)

	title = _label(96, Color(1, 1, 1), 0)
	title.label_settings.font = serif
	title.label_settings.shadow_size = 12
	title.label_settings.shadow_color = Color(0, 0, 0, 0.35)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.offset_bottom = -60
	title.text = "そらをとぶ"
	title.modulate.a = 0.0

	title_sub = _label(20, Color(1, 1, 1, 0.8), 4)
	title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_sub.set_anchors_preset(Control.PRESET_CENTER)
	title_sub.anchor_left = 0.0
	title_sub.anchor_right = 1.0
	title_sub.offset_top = 60
	title_sub.offset_bottom = 100
	title_sub.modulate.a = 0.0


func _label(sz: int, col: Color, outline: int) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = sz
	ls.font_color = col
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0, 0.55)
	ls.shadow_size = 4
	ls.shadow_color = Color(0, 0, 0, 0.3)
	ls.shadow_offset = Vector2(0, 2)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func fade(to: float, t: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", to, t)
	return tw


func show_title(on: bool, t := 1.5, sub_text := "") -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(title, "modulate:a", 1.0 if on else 0.0, t)
	if sub_text != "":
		title_sub.text = sub_text
	tw.tween_property(title_sub, "modulate:a", 1.0 if on and sub_text != "" else 0.0, t)


## 独り言・会話。重なったら順番に出す
func say(text: String, dur := 3.2, col := Color(1, 1, 1)) -> void:
	queue.append([text, dur, col])
	if not sub_busy:
		_next()


func _next() -> void:
	if queue.is_empty():
		sub_busy = false
		return
	sub_busy = true
	var q: Array = queue.pop_front()
	sub.text = "「" + str(q[0]) + "」"
	sub.label_settings.font_color = q[2]
	var tw := create_tween()
	tw.tween_property(sub, "modulate:a", 1.0, 0.25)
	tw.tween_interval(q[1])
	tw.tween_property(sub, "modulate:a", 0.0, 0.4)
	tw.tween_interval(0.3)
	tw.tween_callback(_next)


func show_prompt(text: String) -> void:
	prompt.text = text
	prompt.visible = text != ""


func show_hint(text: String, dur := 7.0) -> void:
	hint.text = text
	var tw := create_tween()
	tw.tween_property(hint, "modulate:a", 1.0, 0.6)
	tw.tween_interval(dur)
	tw.tween_property(hint, "modulate:a", 0.0, 1.2)


func update_nav(cam: Camera3D, target: Vector3, from: Vector3, on: bool) -> void:
	nav.visible = on
	marker.visible = false
	if not on:
		return
	var d := Vector2(target.x - from.x, target.z - from.z).length()
	nav.text = "自宅まで " + str(int(d)) + "m"
	if not cam.is_position_behind(target) and d > 6.0:
		var sp := cam.unproject_position(target + Vector3(0, 2.5, 0))
		var vs := root.get_viewport_rect().size
		if sp.x > 0 and sp.y > 0 and sp.x < vs.x and sp.y < vs.y:
			marker.visible = true
			marker.position = sp - Vector2(40, 66)
			marker.modulate.a = clampf(1.0 - (d - 500.0) / 300.0, 0.25, 1.0)


func _process(dt: float) -> void:
	if prompt.visible:
		prompt_t += dt
		prompt.modulate.a = 0.65 + 0.35 * sin(prompt_t * 3.0)
