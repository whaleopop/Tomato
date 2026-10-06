## Newton's Apple (Apple): an apple drops out of the sky onto the aimed spot. A shadow warns where;
## whoever is under it when it lands is hit, stunned for a moment and pushed aside.
extends ActiveAbility
class_name NewtonsApple

var damage: float = 35.0
var radius: float = 1.9
var stun_time: float = 1.2
var fall_time: float = 0.75

func aim_preview() -> Dictionary:
	return {"shape": "circle", "range": max_range, "radius": radius}
const DROP_HEIGHT: float = 12.0

func _init():
	ability_name = "Newton's Apple"
	cast_pose = "cast_raise"
	icon = "arrow_down"
	cooldown = 9.0
	duration = 0.2
	max_range = 9.0

func _on_activate(entity, target_position: Vector3) -> bool:
	var parent = AbilityFX._parent(entity)
	if not parent:
		return false
	var spot = AbilityFX._ground(entity, target_position)
	var shadow = _shadow()
	parent.add_child(shadow)
	shadow.global_position = spot + Vector3(0, 0.05, 0)
	shadow.scale = Vector3.ONE * 0.2
	var apple = _apple(AbilityFX.hero_color(entity, Color(0.85, 0.15, 0.12)))
	parent.add_child(apple)
	apple.global_position = spot + Vector3(0, DROP_HEIGHT, 0)
	var t = apple.create_tween().set_parallel(true)
	t.tween_property(apple, "global_position", spot + Vector3(0, 0.45, 0), fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(apple, "rotation", Vector3(2.5, 1.0, 0.0), fall_time)
	shadow.create_tween().tween_property(shadow, "scale", Vector3.ONE, fall_time)
	if entity.is_inside_tree():
		await entity.get_tree().create_timer(fall_time).timeout
	if is_instance_valid(shadow):
		shadow.queue_free()
	if is_instance_valid(apple):
		var bounce = apple.create_tween()
		bounce.tween_property(apple, "scale", Vector3(1.3, 0.7, 1.3), 0.08)
		bounce.tween_property(apple, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC)
		bounce.tween_interval(0.5)
		bounce.tween_property(apple, "scale", Vector3.ONE * 0.01, 0.3)
		bounce.tween_callback(apple.queue_free)
	if not is_instance_valid(entity) or not entity.is_inside_tree():
		return true
	LandingImpact.create_at(parent, spot, Color(0.95, 0.5, 0.4), 0.9)
	HexTile.shake_around(entity, spot, 0.7, 1.4)
	if replay:
		return true
	for other in entity.get_tree().get_nodes_in_group("entities"):
		if other == entity or not other is Node3D or not other.has_method("get_component"):
			continue
		var off: Vector3 = other.global_position - spot
		off.y = 0.0
		if off.length() > radius:
			continue
		var health = other.get_component("HealthComponent")
		if health:
			health.take_damage(damage, entity)
		var status = other.get_component("StatusComponent")
		if status:
			status.apply("stun", stun_time)
			if off.length() > 0.05:
				status.push(off.normalized() * 6.0, 0.25)
	return true

func _apple(color: Color) -> Node3D:
	var root = Node3D.new()
	var body = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.8
	sphere.radial_segments = 10
	sphere.rings = 6
	body.mesh = sphere
	body.material_override = AbilityFX._flat(color)
	root.add_child(body)
	var stem = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.05
	cyl.height = 0.25
	stem.mesh = cyl
	stem.material_override = AbilityFX._flat(Color(0.35, 0.22, 0.1))
	stem.position.y = 0.45
	root.add_child(stem)
	var leaf = MeshInstance3D.new()
	var prism = PrismMesh.new()
	prism.size = Vector3(0.2, 0.3, 0.04)
	leaf.mesh = prism
	leaf.material_override = AbilityFX._flat(Color(0.3, 0.7, 0.25))
	leaf.position = Vector3(0.1, 0.5, 0)
	leaf.rotation.z = -0.9
	root.add_child(leaf)
	return root

func _shadow() -> MeshInstance3D:
	var disc = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	disc.mesh = quad
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = FireTrail._soft_dot(Color(0.05, 0.02, 0.02, 0.6), Color(0.05, 0.02, 0.02, 0.0))
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return disc
