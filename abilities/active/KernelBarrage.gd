## Kernel Barrage - shoots multiple projectiles
extends ActiveAbility
class_name KernelBarrage

var damage_per_kernel: float = 15.0
var kernel_count: int = 5
var spread_angle: float = 30.0  # Degrees

func _init():
	ability_name = "Kernel Barrage"
	cooldown = 7.0
	duration = 0.8

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	# Calculate direction
	var direction: Vector3
	if target_position != Vector3.ZERO:
		direction = (target_position - entity.global_position).normalized()
	else:
		direction = entity.global_transform.basis.z
	
	# Fire kernels in a cone
	for i in range(kernel_count):
		var angle_offset = (i - kernel_count / 2.0) * (spread_angle / kernel_count)
		var kernel_direction = direction.rotated(Vector3.UP, deg_to_rad(angle_offset))
		_fire_kernel(entity, kernel_direction)
	
	return true

func _fire_kernel(entity, direction: Vector3):  # entity: Entity
	# Create projectile
	var projectile = Projectile.new()

	# Position slightly in front of entity
	var spawn_offset = direction * 0.5 + Vector3(0, 0.5, 0)
	projectile.global_position = entity.global_position + spawn_offset

	# Configure projectile
	projectile.setup(entity, direction, damage_per_kernel, 15.0)

	# Add to scene
	var world = entity.get_tree().current_scene
	if world:
		world.add_child(projectile)
