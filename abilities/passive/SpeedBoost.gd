## Speed Boost - increases movement speed (Carrot passive)
extends PassiveAbility
class_name SpeedBoost

var speed_multiplier: float = 1.1  # 10% increase
var original_speed: float = -1.0  # -1 means not stored yet

func _init():
	ability_name = "Swift Movement"
	cooldown = 0.0

func _on_apply(entity):  # entity: Entity
	var movement = entity.get_component("MovementComponent")
	if movement:
		# Store original speed only on first application
		if original_speed < 0:
			original_speed = movement.get_speed()
		movement.set_speed(original_speed * speed_multiplier)
		print("[SpeedBoost] Applied %.0f%% speed boost to %s" % [(speed_multiplier - 1.0) * 100, entity.name])

func _on_remove(entity):  # entity: Entity
	var movement = entity.get_component("MovementComponent")
	if movement and original_speed >= 0:
		movement.set_speed(original_speed)
		print("[SpeedBoost] Removed speed boost from %s, restored speed to %.1f" % [entity.name, original_speed])
		original_speed = -1.0  # Reset for next application

