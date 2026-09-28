## Small shared visuals: thrown juice blobs and splashes (Tomato Splash and its reskins), melee
## slash arcs (Beet Crush) and floating damage / heal numbers over players.
## Visual only - they run on every peer (a replayed cast plays them too).
extends RefCounted
class_name AbilityFX

## The caster's hero color (juice of the tomato, lemon, banana...)
static func hero_color(entity: Node, fallback: Color = Color(0.9, 0.25, 0.2)) -> Color:
	if entity and entity.get("character_data") and entity.character_data:
		return entity.character_data.color
	return fallback

static func _parent(entity: Node) -> Node:
	var p = entity.get_parent() if entity else null
	return p if p is Node3D else (entity.get_tree().current_scene if entity and entity.is_inside_tree() else null)

## A blob flying along an arc from `from` to `to` in `time` seconds
static func throw_blob(entity: Node, from: Vector3, to: Vector3, color: Color, time: float) -> void:
	var parent = _parent(entity)
	if not parent:
		return
	var blob = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	sphere.radial_segments = 8
	sphere.rings = 4
	blob.mesh = sphere
	blob.material_override = _flat(color)
	parent.add_child(blob)
	blob.global_position = from
	var peak = max(from.y, to.y) + 1.6 + from.distance_to(to) * 0.12
	var tween = blob.create_tween()
	tween.tween_method(func(t: float):
		if is_instance_valid(blob):
			var p = from.lerp(to, t)
			p.y = lerp(from.y, to.y, t) + (peak - max(from.y, to.y)) * 4.0 * t * (1.0 - t)
			blob.global_position = p
			blob.rotation = Vector3(t * 9.0, t * 5.0, 0), 0.0, 1.0, time)
	tween.tween_callback(blob.queue_free)

## Juice burst and a splat on the ground
static func splash(entity: Node, pos: Vector3, color: Color, radius: float) -> void:
	var parent = _parent(entity)
	if not parent:
		return
	var drops = GPUParticles3D.new()
	drops.amount = 40
	drops.lifetime = 0.9
	drops.one_shot = true
	drops.explosiveness = 1.0
	var process = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.4
	process.direction = Vector3.UP
	process.spread = 75.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 7.0
	process.gravity = Vector3(0, -14, 0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	drops.process_material = process
	var drop_mesh = SphereMesh.new()
	drop_mesh.radius = 0.09
	drop_mesh.height = 0.18
	drop_mesh.radial_segments = 6
	drop_mesh.rings = 3
	drop_mesh.material = _flat(color)
	drops.draw_pass_1 = drop_mesh
	parent.add_child(drops)
	drops.global_position = pos + Vector3(0, 0.3, 0)
	drops.emitting = true

	var splat = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 1.7
	splat.mesh = plane
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.8)
	mat.albedo_texture = FireTrail._soft_dot(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	splat.material_override = mat
	splat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(splat)
	splat.global_position = _ground(entity, pos) + Vector3(0, 0.04, 0)
	splat.rotation.y = randf() * TAU
	splat.scale = Vector3.ONE * 0.3
	var t = splat.create_tween()
	t.tween_property(splat, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.2)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.8)
	t.tween_callback(func():
		splat.queue_free()
		if is_instance_valid(drops):
			drops.queue_free())

## A sweeping crescent in front of the caster (melee cone)
static func slash(entity: Node3D, forward: Vector3, reach: float, angle_deg: float, color: Color) -> void:
	var parent = _parent(entity)
	if not parent:
		return
	var arc = MeshInstance3D.new()
	var mesh = ArrayMesh.new()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var steps = 16
	var half = deg_to_rad(angle_deg) / 2.0
	var inner = reach * 0.35
	for i in steps:
		var a0 = -half + (2.0 * half) * i / steps
		var a1 = -half + (2.0 * half) * (i + 1) / steps
		var edge_fade = sin(PI * (i + 0.5) / steps)  # thin at both ends
		var p0 = Vector3(sin(a0), 0, cos(a0))
		var p1 = Vector3(sin(a1), 0, cos(a1))
		var c_in = Color(color, 0.0)
		var c_out = Color(color.lightened(0.4), 0.85 * edge_fade)
		for v in [[p0 * inner, c_in], [p0 * reach, c_out], [p1 * reach, c_out], [p0 * inner, c_in], [p1 * reach, c_out], [p1 * inner, c_in]]:
			verts.append(v[0])
			cols.append(v[1])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	arc.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc.material_override = mat
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(arc)
	arc.global_position = entity.global_position + Vector3(0, 0.7, 0)
	arc.rotation.y = atan2(forward.x, forward.z)
	arc.scale = Vector3(0.5, 1, 0.5)
	var t = arc.create_tween().set_parallel(true)
	t.tween_property(arc, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(arc, "rotation:y", arc.rotation.y + 0.5, 0.3)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_delay(0.1)
	t.chain().tween_callback(arc.queue_free)

## "-25" / "+30" floating up from a player (Player connects its HealthComponent)
static func number(entity: Node3D, amount: float, color: Color) -> void:
	if not entity or not entity.is_inside_tree() or abs(amount) < 0.5:
		return
	var label = Label3D.new()
	label.text = ("+%d" if amount > 0 else "%d") % int(round(amount))
	label.font = UITheme.font_black()
	label.font_size = 72
	label.outline_size = 14
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.75)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.006
	label.top_level = true  # doesn't follow the player, but hides with it (fog of war)
	entity.add_child(label)
	var start = entity.global_position + Vector3(randf_range(-0.3, 0.3), 1.9, 0)
	label.global_position = start
	var t = label.create_tween().set_parallel(true)
	t.tween_property(label, "global_position", start + Vector3(0, 0.9, 0), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.55)
	t.tween_property(label, "outline_modulate:a", 0.0, 0.35).set_delay(0.55)
	t.chain().tween_callback(label.queue_free)

static func _ground(entity: Node, pos: Vector3) -> Vector3:
	if entity is Node3D and entity.is_inside_tree():
		var q = PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2.0, pos + Vector3.DOWN * 4.0, 1)
		var hit = entity.get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			return hit.position
	return pos

static var _flat_cache: Dictionary = {}

static func _flat(color: Color) -> StandardMaterial3D:
	var key = color.to_html()
	if not _flat_cache.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.35
		_flat_cache[key] = m
	return _flat_cache[key]
