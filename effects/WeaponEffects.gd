## Visual effects for weapons: muzzle flash, tracers, hit effects
extends Node3D
class_name WeaponEffects

## Create a muzzle flash effect at position
static func create_muzzle_flash(parent: Node3D, position: Vector3, direction: Vector3 = Vector3.FORWARD) -> void:
	var flash = _create_flash_mesh()
	flash.position = position
	parent.add_child(flash)

	# Look in direction
	if direction != Vector3.ZERO:
		flash.look_at(position + direction, Vector3.UP)

	# Animate and remove
	var tween = flash.create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE * 0.01, 0.08)  # never exactly 0: a zero basis spams "det == 0"
	tween.tween_callback(flash.queue_free)

static func _create_flash_mesh() -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	mesh_instance.mesh = mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 0.9, 0.5)
	material.emission_enabled = true
	material.emission = Color(1, 0.7, 0.3)
	material.emission_energy_multiplier = 5.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material

	mesh_instance.scale = Vector3(1.5, 1.5, 2.0)

	return mesh_instance

## Create a bullet tracer from start to end
static func create_tracer(parent: Node3D, start: Vector3, end: Vector3, color: Color = Color(1, 0.9, 0.4), duration: float = 0.1) -> void:
	var tracer = _create_tracer_mesh(start, end, color)
	parent.add_child(tracer)

	# Animate fade out
	var material = tracer.material_override as StandardMaterial3D
	if material:
		var tween = tracer.create_tween()
		tween.tween_property(material, "albedo_color:a", 0.0, duration)
		tween.parallel().tween_property(material, "emission_energy_multiplier", 0.0, duration)
		tween.tween_callback(tracer.queue_free)

static func _create_tracer_mesh(start: Vector3, end: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()

	var direction = end - start
	var length = direction.length()

	# Create cylinder mesh for tracer
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.02
	mesh.height = length
	mesh_instance.mesh = mesh

	# Position at midpoint
	var midpoint = start + direction * 0.5
	mesh_instance.position = midpoint

	# Rotate to align with direction using look_at_from_position (works without being in tree)
	var dir_normalized = direction.normalized()
	if dir_normalized != Vector3.UP and dir_normalized != Vector3.DOWN:
		mesh_instance.look_at_from_position(midpoint, end, Vector3.UP)
		mesh_instance.rotate_object_local(Vector3.RIGHT, PI / 2)
	else:
		mesh_instance.rotation.x = 0 if direction.y > 0 else PI

	# Glowing material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.9)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material

	return mesh_instance

## Create hit effect (sparks/blood) at position
static func create_hit_effect(parent: Node3D, position: Vector3, normal: Vector3, hit_type: String = "default") -> void:
	match hit_type:
		"blood":
			_create_blood_effect(parent, position, normal)
		"metal":
			_create_spark_effect(parent, position, normal)
		"environment":
			_create_dust_effect(parent, position, normal)
		_:
			_create_spark_effect(parent, position, normal)

static func _create_blood_effect(parent: Node3D, position: Vector3, normal: Vector3) -> void:
	var particles = GPUParticles3D.new()
	particles.position = position
	particles.amount = 12
	particles.lifetime = 0.4
	particles.one_shot = true
	particles.explosiveness = 0.95

	var material = ParticleProcessMaterial.new()
	material.direction = normal
	material.spread = 30.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0
	material.gravity = Vector3(0, -15, 0)
	material.scale_min = 0.05
	material.scale_max = 0.12
	material.color = Color(0.7, 0.1, 0.1)
	particles.process_material = material

	# Simple sphere mesh for particles
	var mesh = SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh

	parent.add_child(particles)
	particles.emitting = true

	# Auto-remove after effect completes
	var timer = parent.get_tree().create_timer(1.0)
	timer.timeout.connect(particles.queue_free)

static func _create_spark_effect(parent: Node3D, position: Vector3, normal: Vector3) -> void:
	var particles = GPUParticles3D.new()
	particles.position = position
	particles.amount = 8
	particles.lifetime = 0.3
	particles.one_shot = true
	particles.explosiveness = 0.95

	var material = ParticleProcessMaterial.new()
	material.direction = normal
	material.spread = 45.0
	material.initial_velocity_min = 4.0
	material.initial_velocity_max = 8.0
	material.gravity = Vector3(0, -10, 0)
	material.scale_min = 0.02
	material.scale_max = 0.06
	material.color = Color(1, 0.8, 0.3)
	material.emission_color = Color(1, 0.6, 0.2)
	particles.process_material = material

	var mesh = SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	particles.draw_pass_1 = mesh

	parent.add_child(particles)
	particles.emitting = true

	# Light flash
	var light = OmniLight3D.new()
	light.position = position
	light.light_color = Color(1, 0.7, 0.3)
	light.light_energy = 2.0
	light.omni_range = 3.0
	parent.add_child(light)

	var tween = light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.15)
	tween.tween_callback(light.queue_free)

	var timer = parent.get_tree().create_timer(0.8)
	timer.timeout.connect(particles.queue_free)

static func _create_dust_effect(parent: Node3D, position: Vector3, normal: Vector3) -> void:
	var particles = GPUParticles3D.new()
	particles.position = position
	particles.amount = 6
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 0.9

	var material = ParticleProcessMaterial.new()
	material.direction = normal
	material.spread = 60.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 3.0
	material.gravity = Vector3(0, -3, 0)
	material.scale_min = 0.1
	material.scale_max = 0.25
	material.color = Color(0.6, 0.55, 0.45, 0.7)
	particles.process_material = material

	var mesh = SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	particles.draw_pass_1 = mesh

	parent.add_child(particles)
	particles.emitting = true

	var timer = parent.get_tree().create_timer(1.0)
	timer.timeout.connect(particles.queue_free)

## Create impact decal at hit position
static func create_impact_decal(parent: Node3D, position: Vector3, normal: Vector3, decal_type: String = "bullet") -> void:
	var decal = Decal.new()
	decal.position = position + normal * 0.01  # Slight offset to prevent z-fighting

	# A decal projects along its -Y: turn its Y axis onto the surface normal
	# (works before the node is in the tree, unlike look_at)
	var n = normal.normalized()
	if n.is_equal_approx(Vector3.DOWN):
		decal.rotation.x = PI
	elif not n.is_equal_approx(Vector3.UP) and n != Vector3.ZERO:
		decal.quaternion = Quaternion(Vector3.UP, n)

	decal.size = Vector3(0.15, 0.05, 0.15)

	# Create simple albedo texture (circle)
	# In production, use actual decal textures
	decal.modulate = Color(0.2, 0.2, 0.2, 0.8)

	parent.add_child(decal)

	# Fade out decal after time
	var tween = decal.create_tween()
	tween.tween_interval(5.0)  # Stay visible for 5 seconds
	tween.tween_property(decal, "modulate:a", 0.0, 1.0)
	tween.tween_callback(decal.queue_free)

## Combined effect for a complete shot
static func create_shot_effects(
	parent: Node3D,
	muzzle_position: Vector3,
	hit_position: Vector3,
	hit_normal: Vector3,
	hit_target: Node3D = null,
	weapon_type: String = "pistol"
) -> void:
	var direction = (hit_position - muzzle_position).normalized()

	# Muzzle flash
	create_muzzle_flash(parent, muzzle_position, direction)

	# Tracer color based on weapon
	var tracer_color = Color(1, 0.9, 0.4)
	match weapon_type:
		"sniper":
			tracer_color = Color(0.4, 0.8, 1.0)
		"shotgun":
			tracer_color = Color(1, 0.6, 0.3)

	# Tracer
	create_tracer(parent, muzzle_position, hit_position, tracer_color)

	# Hit effect
	var hit_type = "environment"
	if hit_target:
		if hit_target.is_in_group("players") or hit_target.is_in_group("enemies"):
			hit_type = "blood"
		elif hit_target.is_in_group("metal"):
			hit_type = "metal"

	create_hit_effect(parent, hit_position, hit_normal, hit_type)

	# Impact decal (only on environment)
	if hit_type == "environment" or hit_type == "metal":
		create_impact_decal(parent, hit_position, hit_normal)

## Shotgun spread visualization
static func create_shotgun_effects(
	parent: Node3D,
	muzzle_position: Vector3,
	hit_results: Array[Dictionary]
) -> void:
	# Single muzzle flash for shotgun
	create_muzzle_flash(parent, muzzle_position, Vector3.FORWARD)

	# Multiple tracers
	for result in hit_results:
		var end_pos = result.get("position", result.get("end_position", muzzle_position + Vector3.FORWARD * 30))
		create_tracer(parent, muzzle_position, end_pos, Color(1, 0.6, 0.3), 0.08)

		if result.get("hit", false):
			var normal = result.get("normal", Vector3.UP)
			var collider = result.get("collider")

			var hit_type = "environment"
			if collider and (collider.is_in_group("players") or collider.is_in_group("enemies")):
				hit_type = "blood"

			create_hit_effect(parent, result.position, normal, hit_type)
