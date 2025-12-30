## Health Regeneration - slowly regenerates health
extends PassiveAbility
class_name HealthRegeneration

var regen_rate: float = 2.0  # Health per second
var regen_timer: float = 0.0
var regen_interval: float = 1.0  # Heal every second

func _init():
	ability_name = "Health Regeneration"
	cooldown = 0.0

func update(delta: float, entity):  # entity: Entity
	if not is_applied:
		return
	
	regen_timer += delta
	
	if regen_timer >= regen_interval:
		regen_timer = 0.0
		var health = entity.get_component("HealthComponent")
		if health and not health.is_dead:
			health.heal(regen_rate * regen_interval)

func _on_apply(entity):  # entity: Entity
	pass

func _on_remove(entity):  # entity: Entity
	pass

