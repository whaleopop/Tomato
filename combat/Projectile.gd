## Projectile for ranged weapons
extends CharacterBody3D
class_name Projectile

signal hit_target(target: Node3D)
signal projectile_expired

var damage: float = 10.0
var speed: float = 20.0
var direction: Vector3 = Vector3.ZERO
var lifetime: float = 5.0
var owner_entity = null  # Entity

func _ready():
	# Create visual representation
	var mesh_instance = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.1
	mesh_instance.mesh = sphere_mesh
	add_child(mesh_instance)
	
	# Set up collision: the projectile itself is on no layer (players must not bump into it),
	# it looks for the environment (1) and players (2); without this it never met a player
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.1
	collision.shape = shape
	add_child(collision)
	collision_layer = 0
	collision_mask = HitscanSystem.LAYER_ENVIRONMENT | HitscanSystem.LAYER_PLAYERS
	if owner_entity is PhysicsBody3D:
		add_collision_exception_with(owner_entity)

func _physics_process(delta: float):
	# Move projectile
	velocity = direction * speed
	move_and_slide()

	# Check lifetime
	lifetime -= delta
	if lifetime <= 0.0:
		projectile_expired.emit()
		queue_free()
		return

	# Check collisions: a player takes the hit, anything else (tile, wall) just stops it
	for i in range(get_slide_collision_count()):
		var collider = get_slide_collision(i).get_collider()
		if collider == owner_entity:
			continue
		if collider and collider.has_method("get_component"):
			_on_hit(collider)
		else:
			queue_free()
		break

func _on_hit(target):  # target: Entity
	hit_target.emit(target)
	
	# Deal damage
	var health = target.get_component("HealthComponent")
	if health:
		health.take_damage(damage, owner_entity)
	
	queue_free()

func setup(p_owner, p_direction: Vector3, p_damage: float, p_speed: float):  # p_owner: Entity
	owner_entity = p_owner
	direction = p_direction.normalized()
	damage = p_damage
	speed = p_speed
