class_name Kit
extends RefCounted

# 形と材質の小道具。モデルはすべてここの箱・円柱の組み合わせで作る。


## 頂点色つきの箱をまとめて1つのメッシュにする
class Builder:
	var st := SurfaceTool.new()
	var count := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
		# Godot は時計回りが表。法線と同じ向きに張られていたら裏返す
		var tri := [a, b, c, a, c, d]
		if (b - a).cross(c - a).dot(n) > 0.0:
			tri = [a, c, b, a, d, c]
		for v in tri:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(v)
		count += 1

	## basis で回した箱（中心 c、寸法 s）
	func box(c: Vector3, s: Vector3, col: Color, b: Basis = Basis.IDENTITY, skip_bottom := true) -> void:
		var h := s * 0.5
		var ax := [b.x, b.y, b.z]
		var dims := [h.x, h.y, h.z]
		for i in 3:
			for sg in [-1.0, 1.0]:
				if skip_bottom and i == 1 and sg < 0.0:
					continue
				var n: Vector3 = ax[i] * sg
				var u: Vector3 = ax[(i + 1) % 3] * dims[(i + 1) % 3]
				var v: Vector3 = ax[(i + 2) % 3] * dims[(i + 2) % 3]
				var o: Vector3 = c + n * dims[i]
				quad(o - u - v, o + u - v, o + u + v, o - u + v, n, col)

	## 角柱で近似した円柱（y 方向）
	func cyl(c: Vector3, r: float, hgt: float, col: Color, seg := 8, r_top := -1.0) -> void:
		if r_top < 0.0:
			r_top = r
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var n := ((d0 + d1) * 0.5).normalized()
			quad(c + d0 * r, c + d1 * r, c + d1 * r_top + Vector3(0, hgt, 0), c + d0 * r_top + Vector3(0, hgt, 0), n, col)
			var top := c + Vector3(0, hgt, 0)
			_tri(top, top + d0 * r_top, top + d1 * r_top, Vector3.UP, col)

	func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
		var tri := [a, b, c]
		if (b - a).cross(c - a).dot(n) > 0.0:
			tri = [a, c, b]
		for v in tri:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(v)

	func commit(mat: Material) -> ArrayMesh:
		var m := st.commit()
		if m.get_surface_count() > 0:
			m.surface_set_material(0, mat)
		return m


static func vc_mat(rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


## 頂点色のまま光る（照明の影響を受けない）
static func glow_mat(energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(energy, energy, energy)
	return m


static func mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


static func emit_mat(c: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


static func add_mesh(parent: Node, mesh: Mesh, pos := Vector3.ZERO, mat_override: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if mat_override:
		mi.material_override = mat_override
	parent.add_child(mi)
	return mi


static func box_node(parent: Node, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return add_mesh(parent, bm, pos, m)


## 遠目に見える人（胴・頭・脚）。unlit=true なら室内灯の下のように明るく見せる
static func person(parent: Node, body: Color, legs: Color, pos: Vector3, unlit := false, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.scale = Vector3.ONE * scale
	parent.add_child(root)
	var mk := func(c: Color) -> Material:
		return unshaded(c) if unlit else mat(c)
	var skin := Color(0.85, 0.68, 0.55)
	box_node(root, Vector3(0.38, 0.62, 0.24), Vector3(0, 1.17, 0), mk.call(body))
	box_node(root, Vector3(0.34, 0.85, 0.22), Vector3(0, 0.43, 0), mk.call(legs))
	var hm := SphereMesh.new()
	hm.radius = 0.12
	hm.height = 0.26
	hm.radial_segments = 8
	hm.rings = 4
	add_mesh(root, hm, Vector3(0, 1.62, 0), mk.call(skin))
	var hair := SphereMesh.new()
	hair.radius = 0.125
	hair.height = 0.16
	hair.radial_segments = 8
	hair.rings = 3
	add_mesh(root, hair, Vector3(0, 1.7, 0.01), mk.call(Color(0.08, 0.07, 0.06)))
	return root
