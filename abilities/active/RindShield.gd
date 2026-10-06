## Rind Shield (Watermelon): the melon hardens its rind - a shield for a few seconds - and the
## crack of it knocks everyone around back. What is left of the shield after SHIELD_TIME is gone.
extends ActiveAbility
class_name RindShield

var shield: float = 40.0
var shield_time: float = 5.0
var radius: float = 3.5
var push_speed: float = 11.0
var damage: float = 10.0

func aim_preview() -> Dictionary:
	return {"shape": "self", "radius": radius}

func _init():
	ability_name = "Rind Shield"
	cast_pose = "cast_raise"
	icon = "shield"
	cooldown = 12.0
	duration = 0.3

func _on_activate(entity, target_position: Vector3) -> bool:
	_bubble(entity)
	var parent = AbilityFX._parent(entity)
	if parent:
		LandingImpact.create_at(parent, entity.global_position, Color(0.45, 0.9, 0.45), 1.0)
	if replay:
		return true
	var mp = entity.get_tree().get_multiplayer()
	if mp.has_multiplayer_peer() and not mp.is_server():
		return true  # the server grants the shield, the sync shows it
	var health = entity.get_component("HealthComponent")
	if health:
		var granted = min(shield, HealthComponent.MAX_SHIELD - health.shield)
		health.add_shield(granted)
		entity.get_tree().create_timer(shield_time).timeout.connect(func():
			if is_instance_valid(entity) and granted > 0.0:
				health.set_shield(max(health.shield - granted, 0.0)))
	for other in entity.get_tree().get_nodes_in_group("entities"):
		if other == entity or not other is Node3D or not other.has_method("get_component"):
			continue
		var off: Vector3 = other.global_position - entity.global_position
		off.y = 0.0
		if off.length() > radius:
			continue
		var their_health = other.get_component("HealthComponent")
		if their_health:
			their_health.take_damage(damage, entity)
		var status = other.get_component("StatusComponent")
		if status:
			status.push((off.normalized() if off.length() > 0.05 else Vector3.FORWARD) * push_speed, 0.35)
	return true

## A green bubble around the melon while the shield lasts
func _bubble(entity: Node3D) -> void:
	var bubble = MeshInstance3D.new()
	bubble.name = "RindBubble"
	var sphere = SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 1.7
	bubble.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.3, 0.85, 0.35, 0.28)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bubble.material_override = mat
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	entity.add_child(bubble)
	bubble.position = Vector3(0, 0.65, 0)
	bubble.scale = Vector3.ONE * 0.3
	var t = bubble.create_tween()
	t.tween_property(bubble, "scale", Vector3.ONE * 1.15, 0.18).set_ease(Tween.EASE_OUT)
	t.tween_property(bubble, "scale", Vector3.ONE, 0.2)
	t.tween_interval(max(shield_time - 0.8, 0.1))
	t.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	t.tween_callback(bubble.queue_free)
