## Manages entity health, damage, and death
extends Component
class_name HealthComponent

signal health_changed(current: float, max_health: float)
signal damage_taken(amount: float, source)  # source: Entity
signal damage_dodged(amount: float, source)  # source: Entity
signal healed(amount: float)
signal died
signal revived
signal shield_changed(shield: float)

var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false
var invulnerable: bool = false
var damage_resistance: float = 0.0  # Percentage (0.0 - 1.0)
var dodge_chance: float = 0.0  # Percentage (0.0 - 1.0) for DodgeChance passive
## Shield pickups: absorbs damage before health. Server-side like damage; clients get it from
## the state sync (ServerPlayer.get_state -> NetworkingComponent)
var shield: float = 0.0
const MAX_SHIELD: float = 60.0

func _init(p_entity = null, p_max_health: float = 100.0):  # p_entity: Entity
	entity = p_entity
	max_health = p_max_health
	current_health = max_health

func take_damage(amount: float, source = null) -> float:  # source: Entity
	if not enabled or is_dead or invulnerable:
		return 0.0
	# Only the server decides damage; clients get health from the sync (_apply_damage).
	# A client killing its copy of someone the server didn't kill left an unhittable "ghost".
	if not _is_authority():
		return 0.0

	# Check for dodge (DodgeChance passive ability)
	if dodge_chance > 0.0 and randf() < dodge_chance:
		damage_dodged.emit(amount, source)
		return 0.0

	# Apply damage resistance
	var actual_damage = amount * (1.0 - damage_resistance)
	var absorbed = 0.0
	if shield > 0.0:
		absorbed = min(shield, actual_damage)
		set_shield(shield - absorbed)
		actual_damage -= absorbed
		if actual_damage <= 0.0:
			damage_taken.emit(0.0, source)  # still a hit (flinch, hit marker)
			return absorbed
	var dealt = absorbed + _apply_damage(actual_damage, source)
	_thorns(dealt, source)
	return dealt

## Spiky Skin passive (meta "thorns"): whoever hurt us gets a share of it back (not reflected again)
func _thorns(dealt: float, source) -> void:
	if dealt <= 0.0 or not entity or not entity.has_meta("thorns"):
		return
	if source == null or source == entity or not is_instance_valid(source) or not source.has_method("get_component"):
		return
	var their_health = source.get_component("HealthComponent")
	if their_health and not their_health.is_dead:
		their_health.take_damage(dealt * float(entity.get_meta("thorns")), null)

func add_shield(amount: float) -> void:
	set_shield(shield + amount)

func set_shield(value: float) -> void:
	value = clamp(value, 0.0, MAX_SHIELD)
	if is_equal_approx(value, shield):
		return
	shield = value
	shield_changed.emit(shield)

## Internal method to apply damage directly (used by network sync)
func _apply_damage(amount: float, source = null) -> float:
	current_health = max(0.0, current_health - amount)

	health_changed.emit(current_health, max_health)
	damage_taken.emit(amount, source)

	if current_health <= 0.0 and not is_dead:
		die()

	return amount

func heal(amount: float) -> float:
	if not enabled or is_dead:
		return 0.0
	
	var old_health = current_health
	current_health = min(max_health, current_health + amount)
	var actual_heal = current_health - old_health
	
	if actual_heal > 0.0:
		health_changed.emit(current_health, max_health)
		healed.emit(actual_heal)
	
	return actual_heal

func die():
	if is_dead:
		return
	
	is_dead = true
	current_health = 0.0
	set_shield(0.0)
	health_changed.emit(current_health, max_health)
	died.emit()

func revive(health_percent: float = 1.0):
	if not is_dead:
		return
	
	is_dead = false
	current_health = max_health * health_percent
	health_changed.emit(current_health, max_health)
	revived.emit()

func set_max_health(new_max: float, heal_to_full: bool = false):
	max_health = new_max
	if heal_to_full:
		current_health = max_health
	else:
		current_health = min(current_health, max_health)
	health_changed.emit(current_health, max_health)

func get_health_percent() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health

func set_invulnerable(value: bool):
	invulnerable = value

func set_damage_resistance(value: float):
	damage_resistance = clamp(value, 0.0, 1.0)

func set_dodge_chance(value: float):
	dodge_chance = clamp(value, 0.0, 1.0)

func _is_authority() -> bool:
	if not entity or not is_instance_valid(entity) or not entity.is_inside_tree():
		return true
	return entity.get_tree().get_multiplayer().is_server()

