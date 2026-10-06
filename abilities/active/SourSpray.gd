## Sour Spray (Lemon): a cone of lemon juice. It stings a little, but whoever it hits can hardly
## see for a few seconds (StatusComponent "blind": their fog of war closes in).
extends ActiveAbility
class_name SourSpray

var damage: float = 12.0
var reach: float = 6.5
var angle: float = 70.0          # degrees, the whole cone
var blind_time: float = 3.5
var blind_factor: float = 0.35   # share of their sight left

func aim_preview() -> Dictionary:
	return {"shape": "cone", "range": reach, "angle": angle}

func _init():
	ability_name = "Sour Spray"
	cast_pose = "cast_spray"
	icon = "sparkle"
	cooldown = 9.0
	duration = 0.4

func _on_activate(entity, target_position: Vector3) -> bool:
	var forward = _aim(entity, target_position)
	_spray_effect(entity, forward)
	if replay:
		return true
	for other in entity.get_tree().get_nodes_in_group("entities"):
		if other == entity or not other is Node3D or not other.has_method("get_component"):
			continue
		var to_other: Vector3 = other.global_position - entity.global_position
		to_other.y = 0.0
		if to_other.length() > reach or rad_to_deg(forward.angle_to(to_other.normalized())) > angle / 2.0:
			continue
		var eye = Vector3(0, 1.0, 0)
		if CoverSpawner.fire_blocked(entity.get_world_3d(), entity.global_position + eye, other.global_position + eye):
			continue  # juice doesn't go through walls
		var health = other.get_component("HealthComponent")
		if health:
			health.take_damage(damage, entity)
		var status = other.get_component("StatusComponent")
		if status:
			status.apply("blind", blind_time, blind_factor)
	return true

static func _aim(entity: Node3D, target_position: Vector3) -> Vector3:
	var forward: Vector3 = entity.global_transform.basis.z  # heroes face +Z
	if target_position != Vector3.ZERO:
		var aim = target_position - entity.global_position
		aim.y = 0.0
		if aim.length_squared() > 0.01:
			forward = aim.normalized()
	forward.y = 0.0
	return forward.normalized()

func _spray_effect(entity: Node3D, forward: Vector3) -> void:
	var parent = AbilityFX._parent(entity)
	if not parent:
		return
	var color = AbilityFX.hero_color(entity, Color(1.0, 0.85, 0.2))
	var drops = GPUParticles3D.new()
	drops.amount = 70
	drops.lifetime = 0.55
	drops.one_shot = true
	drops.explosiveness = 0.75
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = forward
	pm.spread = angle / 2.0
	pm.initial_velocity_min = reach * 1.4
	pm.initial_velocity_max = reach * 2.0
	pm.damping_min = reach * 1.2
	pm.damping_max = reach * 1.8
	pm.gravity = Vector3(0, -6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var ramp = Gradient.new()
	ramp.set_color(0, Color(color.lightened(0.3), 0.95))
	ramp.set_color(1, Color(color, 0.0))
	var ramp_tex = GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	drops.process_material = pm
	var quad = QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	quad.material = LandingImpact.soft_particle_material(false)
	drops.draw_pass_1 = quad
	parent.add_child(drops)
	drops.global_position = entity.global_position + Vector3(0, 0.8, 0) + forward * 0.4
	drops.emitting = true
	drops.finished.connect(drops.queue_free)
