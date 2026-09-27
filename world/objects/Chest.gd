## Loot chest that players can open
extends Node3D
class_name Chest

signal chest_opened(player: Player)
signal loot_dropped(items: Array)
signal chest_open_sound_requested  # For audio system to handle

var is_opened: bool = false
var loot_table: LootTable = null
var loot_items: Array[ItemData] = []

# Visual components
var chest_base: MeshInstance3D
var chest_lid: MeshInstance3D
var glow_light: OmniLight3D
var particles: GPUParticles3D

func _ready():
	add_to_group("chests")
	
	# Create visual representation
	_create_visual()

func _create_visual():
	# Create chest base
	chest_base = MeshInstance3D.new()
	var base_mesh = BoxMesh.new()
	base_mesh.size = Vector3(1.0, 0.6, 0.8)
	chest_base.mesh = base_mesh

	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = Color(0.6, 0.4, 0.2)  # Brown
	base_material.metallic = 0.2
	base_material.roughness = 0.7
	chest_base.set_surface_override_material(0, base_material)

	chest_base.position.y = 0.3
	add_child(chest_base)

	# Create chest lid (positioned at top of base)
	chest_lid = MeshInstance3D.new()
	var lid_mesh = BoxMesh.new()
	lid_mesh.size = Vector3(1.0, 0.4, 0.8)
	chest_lid.mesh = lid_mesh

	var lid_material = StandardMaterial3D.new()
	lid_material.albedo_color = Color(0.5, 0.3, 0.15)  # Darker brown
	lid_material.metallic = 0.3
	lid_material.roughness = 0.6
	chest_lid.set_surface_override_material(0, lid_material)

	# Position lid at top of base, pivot at back edge
	chest_lid.position = Vector3(0, 0.5, -0.4)
	add_child(chest_lid)

	# Add golden trim (decorative box on lid)
	var trim = MeshInstance3D.new()
	var trim_mesh = BoxMesh.new()
	trim_mesh.size = Vector3(0.8, 0.05, 0.05)
	trim.mesh = trim_mesh

	var trim_material = StandardMaterial3D.new()
	trim_material.albedo_color = Color(0.8, 0.6, 0.2)  # Gold
	trim_material.metallic = 0.8
	trim_material.roughness = 0.3
	trim_material.emission_enabled = true
	trim_material.emission = Color(0.4, 0.3, 0.1)
	trim_material.emission_energy_multiplier = 0.5
	trim.set_surface_override_material(0, trim_material)

	trim.position = Vector3(0, 0.2, 0)
	chest_lid.add_child(trim)

	# Create glow light (disabled initially)
	glow_light = OmniLight3D.new()
	glow_light.light_color = Color(1.0, 0.8, 0.3)  # Golden glow
	glow_light.light_energy = 0.0
	glow_light.omni_range = 3.0
	glow_light.position = Vector3(0, 0.8, 0)
	add_child(glow_light)

	# Create particles (disabled initially)
	_create_particles()

func open(player: Player) -> Array[ItemData]:
	if is_opened:
		return []
	
	is_opened = true
	chest_opened.emit(player)
	
	# Generate loot
	if loot_table:
		loot_items = loot_table.generate_loot()
	else:
		# Default loot
		loot_items = _generate_default_loot()
	
	loot_dropped.emit(loot_items)
	
	# Visual feedback
	_animate_open()
	
	return loot_items

func _generate_default_loot() -> Array[ItemData]:
	var items: Array[ItemData] = []
	
	# Random chance for different items
	if randf() < 0.5:
		var health_pack = HealthPack.new()
		items.append(health_pack)
	
	return items

func _create_particles():
	particles = GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 30
	particles.lifetime = 1.5
	particles.explosiveness = 0.8

	# Process material
	var process_mat = ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_mat.emission_box_extents = Vector3(0.5, 0.2, 0.4)
	process_mat.direction = Vector3.UP
	process_mat.spread = 30
	process_mat.initial_velocity_min = 2.0
	process_mat.initial_velocity_max = 4.0
	process_mat.gravity = Vector3(0, -5, 0)
	process_mat.scale_min = 0.05
	process_mat.scale_max = 0.15

	# Golden sparkle gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 0.9, 0.3, 1))
	gradient.add_point(0.5, Color(1, 0.7, 0.2, 0.8))
	gradient.add_point(1.0, Color(1, 0.5, 0.1, 0))
	process_mat.color_ramp = gradient

	particles.process_material = process_mat

	# Draw pass (sparkle mesh)
	var sparkle_mesh = SphereMesh.new()
	sparkle_mesh.radius = 0.08
	sparkle_mesh.height = 0.16
	particles.draw_pass_1 = sparkle_mesh

	particles.position = Vector3(0, 0.6, 0)
	add_child(particles)

func _animate_open():
	# Emit sound signal
	chest_open_sound_requested.emit()

	# Create tween for smooth animation
	var tween = create_tween()
	tween.set_parallel(true)  # Run animations in parallel

	# Animate lid opening (rotate around back edge)
	tween.tween_property(chest_lid, "rotation_degrees", Vector3(-75, 0, 0), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Animate glow light
	tween.tween_property(glow_light, "light_energy", 3.0, 0.4).set_ease(Tween.EASE_OUT)

	# Slight bounce of chest
	tween.tween_property(self, "position:y", position.y + 0.2, 0.2).set_ease(Tween.EASE_OUT)

	# Add particles after slight delay
	await get_tree().create_timer(0.2).timeout
	if particles:
		particles.emitting = true

	# Return to original position
	var bounce_tween = create_tween()
	bounce_tween.tween_property(self, "position:y", position.y, 0.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BOUNCE)

	# Fade out glow after 2 seconds
	await get_tree().create_timer(2.0).timeout
	var fade_tween = create_tween()
	fade_tween.tween_property(glow_light, "light_energy", 0.3, 1.0).set_ease(Tween.EASE_IN)

func can_be_opened_by(player: Player) -> bool:
	return not is_opened and global_position.distance_to(player.global_position) < 2.0
