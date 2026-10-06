## Kernel Barrage - shoots multiple projectiles
extends ActiveAbility
class_name KernelBarrage

var damage_per_kernel: float = 15.0
var kernel_count: int = 5
var spread_angle: float = 30.0  # Degrees

func aim_preview() -> Dictionary:
	return {"shape": "cone", "range": 14.0, "angle": spread_angle}

func _init():
	ability_name = "Kernel Barrage"
	icon = "dot"
	cooldown = 7.0
	duration = 0.8

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	# Calculate direction
	var direction: Vector3
	if target_position != Vector3.ZERO:
		direction = (target_position - entity.global_position).normalized()
	else:
		direction = entity.global_transform.basis.z
	
	# Along the ground, in a cone centered on the aim
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.001 else entity.global_transform.basis.z
	for i in range(kernel_count):
		var t = (i - (kernel_count - 1) / 2.0) / max(kernel_count - 1, 1)
		var kernel_direction = direction.rotated(Vector3.UP, deg_to_rad(t * spread_angle))
		_fire_kernel(entity, kernel_direction)

	return true

func _fire_kernel(entity, direction: Vector3):  # entity: Entity
	var projectile = Projectile.new()
	# Owner first: _ready makes the kernel ignore whoever fired it
	projectile.setup(entity, direction, damage_per_kernel, 15.0)
	var world = entity.get_tree().current_scene
	if not world:
		return
	world.add_child(projectile)
	# Slightly in front of the shooter, at chest height (position needs the node in the tree)
	projectile.global_position = entity.global_position + direction * 0.5 + Vector3(0, 0.5, 0)
