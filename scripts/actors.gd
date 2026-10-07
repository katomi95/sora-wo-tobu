class_name Actors
extends RefCounted

# 空の脇役たち：鳥の群れ・ヘリ・飛行機


class Flock:
	extends Node3D
	var birds: Array[Dictionary] = []
	var vel := Vector3.ZERO
	var t := 0.0
	var scattered := false
	var active := false

	func _init(n := 22) -> void:
		var m := Kit.mat(Color(0.08, 0.08, 0.09))
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for i in n:
			var b := Node3D.new()
			add_child(b)
			Kit.box_node(b, Vector3(0.14, 0.12, 0.42), Vector3.ZERO, m)
			var wl := Node3D.new()
			var wr := Node3D.new()
			b.add_child(wl)
			b.add_child(wr)
			Kit.box_node(wl, Vector3(0.5, 0.02, 0.2), Vector3(-0.25, 0, 0), m)
			Kit.box_node(wr, Vector3(0.5, 0.02, 0.2), Vector3(0.25, 0, 0), m)
			var off := Vector3(rng.randf_range(-6, 6), rng.randf_range(-2.5, 2.5), rng.randf_range(-5, 5))
			birds.append({"n": b, "wl": wl, "wr": wr, "off": off, "ph": rng.randf() * TAU, "v": Vector3.ZERO,
				"rate": rng.randf_range(9.0, 12.0)})
		visible = false

	func launch(from: Vector3, v: Vector3) -> void:
		position = from
		vel = v
		active = true
		visible = true
		scattered = false
		t = 0.0
		for b in birds:
			b["n"].position = b["off"]
			b["v"] = Vector3.ZERO

	func scatter(from: Vector3) -> void:
		if scattered:
			return
		scattered = true
		var rng := RandomNumberGenerator.new()
		for b in birds:
			var wp: Vector3 = to_global(b["n"].position)
			var away := (wp - from)
			away.y = absf(away.y) + 1.0
			b["v"] = away.normalized() * rng.randf_range(6.0, 11.0) + Vector3(0, rng.randf_range(1.0, 4.0), 0)
			b["rate"] = b["rate"] * 1.6

	func near(p: Vector3, r: float) -> bool:
		if not active or scattered:
			return false
		for b in birds:
			if to_global(b["n"].position).distance_to(p) < r:
				return true
		return false

	func update(dt: float) -> void:
		if not active:
			return
		t += dt
		position += vel * dt
		var dir := vel.normalized()
		for b in birds:
			var n: Node3D = b["n"]
			b["ph"] += dt * b["rate"]
			var bv: Vector3 = b["v"]
			if scattered:
				n.position += bv * dt
			else:
				n.position = b["off"] + Vector3(0, sin(t * 0.8 + b["ph"] * 0.1) * 0.4, 0)
			var fd := (dir * vel.length() + bv).normalized()
			if fd.length() > 0.1:
				n.basis = Basis.looking_at(fd, Vector3.UP)
			var fl := sin(b["ph"]) * 0.7
			b["wl"].rotation.z = -fl
			b["wr"].rotation.z = fl
		if t > 40.0:
			active = false
			visible = false


class Heli:
	extends Node3D
	var center := Vector3.ZERO
	var radius := 90.0
	var t := 0.0
	var rotor: Node3D
	var blink: MeshInstance3D

	func _init() -> void:
		var m := Kit.mat(Color(0.2, 0.22, 0.25))
		var body := SphereMesh.new()
		body.radius = 1.4
		body.height = 2.4
		var bm := Kit.add_mesh(self, body, Vector3.ZERO, m)
		bm.scale = Vector3(1.0, 1.0, 1.6)
		Kit.box_node(self, Vector3(0.3, 0.3, 5.0), Vector3(0, 0.2, 4.2), m)
		Kit.box_node(self, Vector3(0.1, 1.2, 0.6), Vector3(0, 0.7, 6.6), m)
		Kit.box_node(self, Vector3(0.1, 0.1, 2.2), Vector3(0.9, -1.4, 0), m)
		Kit.box_node(self, Vector3(0.1, 0.1, 2.2), Vector3(-0.9, -1.4, 0), m)
		rotor = Node3D.new()
		rotor.position = Vector3(0, 1.3, 0)
		add_child(rotor)
		Kit.box_node(rotor, Vector3(10, 0.05, 0.3), Vector3.ZERO, m)
		Kit.box_node(rotor, Vector3(0.3, 0.05, 10), Vector3.ZERO, m)
		blink = Kit.box_node(self, Vector3(0.3, 0.3, 0.3), Vector3(0, -1.2, 0), Kit.emit_mat(Color(1, 0.1, 0.05), 6.0))
		Kit.box_node(self, Vector3(0.25, 0.25, 0.25), Vector3(0, 1.3, 7.0), Kit.emit_mat(Color(1, 1, 1), 3.0))

	func update(dt: float) -> void:
		t += dt
		var a := t * 0.12
		var p := center + Vector3(cos(a) * radius, sin(t * 0.3) * 4.0, sin(a) * radius)
		var tangent := Vector3(-sin(a), 0, cos(a))
		position = p
		basis = Basis.looking_at(tangent, Vector3.UP) * Basis(Vector3.RIGHT, -0.08)
		rotor.rotation.y += dt * 30.0
		blink.visible = fmod(t, 1.2) < 0.15


class Airplane:
	extends Node3D
	var vel := Vector3(28, 0, 6)
	var t := 0.0
	var lamps: Array[MeshInstance3D] = []

	func _init() -> void:
		var m := Kit.mat(Color(0.5, 0.52, 0.55))
		Kit.box_node(self, Vector3(3, 3, 30), Vector3.ZERO, m)
		Kit.box_node(self, Vector3(30, 0.5, 5), Vector3(0, -0.5, 1), m)
		Kit.box_node(self, Vector3(10, 0.4, 3), Vector3(0, 0.5, 13), m)
		lamps.append(Kit.box_node(self, Vector3(1.4, 1.4, 1.4), Vector3(-15, -0.5, 1), Kit.emit_mat(Color(1, 0.1, 0.05), 8.0)))
		lamps.append(Kit.box_node(self, Vector3(1.4, 1.4, 1.4), Vector3(15, -0.5, 1), Kit.emit_mat(Color(0.1, 1, 0.3), 8.0)))
		lamps.append(Kit.box_node(self, Vector3(1.6, 1.6, 1.6), Vector3(0, -1.8, 0), Kit.emit_mat(Color(1, 1, 1), 10.0)))

	func update(dt: float) -> void:
		t += dt
		position += vel * dt
		basis = Basis.looking_at(vel.normalized(), Vector3.UP)
		lamps[2].visible = fmod(t, 1.4) < 0.12
