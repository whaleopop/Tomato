## Fire effect that stays on ground and damages players
extends Area3D
class_name FireEffect

signal fire_expired

@export var damage_per_second: float = 5.0
@export var duration: float = 3.0
@export var radius: float = 1.0

var time_remaining: float = 0.0
var entities_in_fire: Array[Node3D] = []
var particles: GPUParticles3D = null
var light: OmniLight3D = null

func _ready():
	time_remaining = duration

	# Setup collision
	_setup_collision()

	# Create fire particles
	_create_fire_particles()

	# Create light
	_create_light()

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _setup_collision():
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = radius
	shape.height = 1.5
	collision.shape = shape
	add_child(collision)

	collision_layer = 0
	collision_mask = 2  # Detect players

func _create_fire_particles():
	particles = GPUParticles3D.new()
	particles.amount = 30
	particles.lifetime = 0.8
	particles.explosiveness = 0.0
	particles.randomness = 0.5

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_radius = radius
	mat.emission_ring_inner_radius = 0.0
	mat.emission_ring_height = 0.3
	mat.emission_ring_axis = Vector3(0, 1, 0)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 20.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, 1, 0)  # Fire rises
	mat.scale_min = 0.2
	mat.scale_max = 0.5

	# Fire color gradient
	var gradient = GradientTexture1D.new()
	var grad = Gradient.new()
	grad.add_point(0.0, Color(1.0, 0.9, 0.3, 1.0))  # Yellow core
	grad.add_point(0.3, Color(1.0, 0.5, 0.1, 0.9))  # Orange
	grad.add_point(0.6, Color(0.8, 0.2, 0.05, 0.6))  # Red
	grad.add_point(1.0, Color(0.2, 0.1, 0.1, 0.0))  # Smoke
	gradient.gradient = grad
	mat.color_ramp = gradient

	# Scale curve
	var scale_curve = CurveTexture.new()
	var curve = Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	scale_curve.curve = curve
	mat.scale_curve = scale_curve

	particles.process_material = mat

	# Fire mesh
	var mesh = SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	particles.draw_pass_1 = mesh

	add_child(particles)

func _create_light():
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 2.0
	light.omni_range = radius * 3.0
	light.omni_attenuation = 1.5
	light.position = Vector3(0, 0.5, 0)
	add_child(light)

func _process(delta: float):
	time_remaining -= delta

	# Damage entities in fire
	for entity in entities_in_fire:
		if is_instance_valid(entity) and entity.has_method("get_component"):
			var health = entity.get_component("HealthComponent")
			if health:
				health.take_damage(damage_per_second * delta, self)

	# Flicker light
	if light:
		light.light_energy = 2.0 + randf() * 0.5

	# Fade out near end
	if time_remaining < 1.0:
		var fade = time_remaining
		if particles:
			particles.amount_ratio = fade
		if light:
			light.light_energy *= fade

	if time_remaining <= 0:
		fire_expired.emit()
		queue_free()

func _on_body_entered(body: Node3D):
	if body is Player:
		entities_in_fire.append(body)
		print("[FireEffect] Player entered fire")

func _on_body_exited(body: Node3D):
	entities_in_fire.erase(body)

## Static helper to create fire at position
static func create_at(pos: Vector3, parent: Node, dmg: float = 5.0, dur: float = 3.0, rad: float = 1.0) -> FireEffect:
	var fire = FireEffect.new()
	fire.damage_per_second = dmg
	fire.duration = dur
	fire.radius = rad
	fire.position = pos
	parent.add_child(fire)
	return fire
