## 3D character preview for UI (character selection, etc.)
extends HiResView
class_name CharacterPreview3D

@export var character_data: Resource  # CharacterData resource
@export var auto_rotate: bool = true
@export var rotation_speed: float = 0.5  # Radians per second
@export var show_ability_demo: bool = false  # Show ability effects
@export var camera_distance: float = 5.0
@export var camera_height: float = 1.5


var camera: Camera3D
var character_instance: Node3D
var environment: WorldEnvironment
var directional_light: DirectionalLight3D
var character_pivot: Node3D  # Pivot for rotation

func _ready():
	# Create viewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true

	# Create environment with nice lighting
	_setup_environment()

	# Create camera
	camera = Camera3D.new()
	camera.position = Vector3(0, camera_height, camera_distance)
	viewport.add_child(camera)
	camera.look_at(Vector3(0, camera_height * 0.7, 0), Vector3.UP)

	# Create pivot for character rotation
	character_pivot = Node3D.new()
	viewport.add_child(character_pivot)

	# Load character if data provided
	if character_data:
		load_character(character_data)

	# Connect to resize
	resized.connect(_on_resized)

func _process(delta):
	if auto_rotate and character_pivot:
		character_pivot.rotation.y += rotation_speed * delta

	# Update ability demo effects
	if show_ability_demo and character_instance:
		_update_ability_demo(delta)

## Load and display character from CharacterData
func load_character(data: Resource):
	character_data = data

	# Clear existing character
	if character_instance and is_instance_valid(character_instance):
		character_instance.queue_free()

	# Create character instance
	# Note: This assumes characters have 3D models/scenes
	# Adjust path based on your project structure
	var character_scene_path = _get_character_scene_path(data)

	if character_scene_path and ResourceLoader.exists(character_scene_path):
		var character_scene = load(character_scene_path)
		character_instance = character_scene.instantiate()
		character_pivot.add_child(character_instance)

		# Center character
		character_instance.position = Vector3.ZERO

		# Start ability demo if enabled
		if show_ability_demo:
			_start_ability_demo()
	else:
		# Fallback: create simple placeholder mesh
		_create_placeholder_character()

## Setup environment and lighting
func _setup_environment():
	# World environment
	environment = WorldEnvironment.new()
	var env = Environment.new()

	# Set background
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.15, 0.0)  # Transparent dark blue

	# Ambient light
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.8)
	env.ambient_light_energy = 0.5

	environment.environment = env
	viewport.add_child(environment)

	# Directional light (key light)
	directional_light = DirectionalLight3D.new()
	directional_light.light_energy = 1.2
	directional_light.light_color = Color(1.0, 0.95, 0.9)
	directional_light.rotation_degrees = Vector3(-45, 45, 0)
	directional_light.shadow_enabled = true
	viewport.add_child(directional_light)

	# Fill light (opposite side, dimmer)
	var fill_light = OmniLight3D.new()
	fill_light.light_energy = 0.4
	fill_light.light_color = Color(0.7, 0.8, 1.0)
	fill_light.position = Vector3(-2, 2, 2)
	viewport.add_child(fill_light)

	# Rim light (from behind, creates outline)
	var rim_light = SpotLight3D.new()
	rim_light.light_energy = 0.8
	rim_light.light_color = Color(1.0, 1.0, 1.2)
	rim_light.position = Vector3(0, 2, -3)
	rim_light.rotation_degrees = Vector3(30, 0, 0)
	rim_light.spot_range = 10
	rim_light.spot_angle = 45
	viewport.add_child(rim_light)

## Get character scene path from CharacterData
func _get_character_scene_path(data: Resource) -> String:
	# Try to get character_name from data
	if "character_name" in data:
		var char_name: String = data.character_name
		# Construct path - adjust based on your project structure
		return "res://characters/models/%s.tscn" % char_name.to_lower()

	return ""

## Create placeholder character (simple capsule)
func _create_placeholder_character():
	character_instance = Node3D.new()

	var mesh_instance = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	mesh_instance.mesh = capsule

	# Material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.3, 0.3)  # Reddish
	mesh_instance.material_override = material

	character_instance.add_child(mesh_instance)
	character_pivot.add_child(character_instance)

## Start ability demonstration (visual effects)
var ability_demo_timer: float = 0.0
var ability_demo_particles: GPUParticles3D = null

func _start_ability_demo():
	# Create particle effect for abilities
	ability_demo_particles = GPUParticles3D.new()
	ability_demo_particles.amount = 20
	ability_demo_particles.lifetime = 2.0
	ability_demo_particles.explosiveness = 0.0

	# Process material
	var process_mat = ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_mat.emission_sphere_radius = 0.5
	process_mat.direction = Vector3.UP
	process_mat.spread = 45
	process_mat.initial_velocity_min = 0.5
	process_mat.initial_velocity_max = 1.5
	process_mat.gravity = Vector3.ZERO
	process_mat.scale_min = 0.05
	process_mat.scale_max = 0.15

	# Color gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 0.5, 1))
	gradient.add_point(1.0, Color(1, 0.5, 0, 0))
	process_mat.color_ramp = gradient

	ability_demo_particles.process_material = process_mat

	# Draw pass (small sphere)
	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	ability_demo_particles.draw_pass_1 = sphere

	character_instance.add_child(ability_demo_particles)
	ability_demo_particles.position = Vector3(0, 1.0, 0)
	ability_demo_particles.emitting = true

func _update_ability_demo(delta):
	ability_demo_timer += delta

	# Pulse effect every 3 seconds
	if ability_demo_timer > 3.0:
		ability_demo_timer = 0.0

		if ability_demo_particles:
			ability_demo_particles.restart()

## Handle resize
func _on_resized():
	pass  # HiResView sizes the viewport

## Set rotation speed
func set_rotation_speed(speed: float):
	rotation_speed = speed

## Toggle auto rotation
func set_auto_rotate(enabled: bool):
	auto_rotate = enabled

## Manually set rotation
func set_character_rotation(angle_rad: float):
	if character_pivot:
		character_pivot.rotation.y = angle_rad
