## Helpers for imported character/prop models
extends RefCounted
class_name ModelUtils

static var _paper_material: ShaderMaterial = null

## Vertex-colored meshes (AI characters from tools/ai_models) get the concept's paper low-poly
## material: their colors live in the vertices, which Godot's glTF importer does not always
## show, and shaders/lowpoly_paper.gdshader adds the card grain and fibres on top.
static func apply_lowpoly_look(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if not mesh:
			continue
		for i in mesh.get_surface_count():
			if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0:
				mi.set_surface_override_material(i, paper_material())

## One shared instance: every character batches with the same shader
static func paper_material() -> ShaderMaterial:
	if _paper_material == null:
		_paper_material = ShaderMaterial.new()
		_paper_material.shader = load("res://shaders/lowpoly_paper.gdshader")
	return _paper_material

## Scale a model to `height`, stand it on y = 0 and center it on X/Z (any origin convention)
static func normalize_to_height(model: Node3D, height: float) -> void:
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var local_xform = model.global_transform.affine_inverse() * mi.global_transform if model.is_inside_tree() else _relative_xform(model, mi)
		var b = local_xform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first or box.size.y <= 0.0001:
		return
	var s = height / box.size.y
	model.scale = Vector3.ONE * s
	var c = box.get_center()
	model.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)

static func _relative_xform(root: Node3D, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var n: Node = node
	while n and n != root:
		if n is Node3D:
			xform = n.transform * xform
		n = n.get_parent()
	return xform
