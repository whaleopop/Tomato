## Photosynthesis (Broccoli): standing still in the sun, the broccoli heals
extends PassiveAbility
class_name Photosynthesis

const STILL_TIME: float = 1.0        # seconds without moving before it starts
const HEAL_PER_SECOND: float = 5.0
const TICK: float = 0.5

var _still: float = 0.0
var _tick: float = 0.0

func _init():
	ability_name = "Photosynthesis"
	icon = "flower"
	cooldown = 0.0

func update(delta: float, entity):  # entity: Entity
	if not is_applied or not is_instance_valid(entity):
		return
	var movement = entity.get_component("MovementComponent")
	var health = entity.get_component("HealthComponent")
	if not movement or not health or health.is_dead:
		return
	if movement.is_moving or not movement.is_grounded:
		_still = 0.0
		_tick = 0.0
		return
	_still += delta
	if _still < STILL_TIME:
		return
	_tick += delta
	if _tick >= TICK:
		_tick -= TICK
		health.heal(HEAL_PER_SECOND * TICK)
