## Handles combat: attacks, weapons, damage dealing
extends Component
class_name CombatComponent

signal attack_started
signal attack_finished
signal weapon_changed(new_weapon)
signal target_hit(target, damage: float)  # target: Entity

var current_weapon: WeaponData = null
var attack_cooldown: float = 0.0
var is_attacking: bool = false
var attack_range: float = 2.0
var base_damage: float = 10.0
var ranged_damage_multiplier: float = 1.0  # Multiplier for ranged weapon damage

func _init(p_entity = null):  # p_entity: Entity
	entity = p_entity

func update(delta: float):
	if not enabled:
		return
	
	if attack_cooldown > 0.0:
		attack_cooldown -= delta

func can_attack() -> bool:
	return enabled and attack_cooldown <= 0.0 and not is_attacking

func attack(target_position: Vector3, target_entity = null) -> bool:  # target_entity: Entity
	if not can_attack():
		return false
	
	is_attacking = true
	attack_started.emit()

	var damage = base_damage
	if current_weapon:
		damage = current_weapon.damage
		attack_range = current_weapon.range
		attack_cooldown = current_weapon.cooldown

		# Apply ranged damage multiplier for ranged weapons
		if current_weapon.weapon_type == "ranged":
			damage *= ranged_damage_multiplier
	else:
		attack_cooldown = 0.5  # Default cooldown
	
	# Check if target is in range
	if target_entity:
		var distance = entity.global_position.distance_to(target_entity.global_position)
		if distance > attack_range:
			is_attacking = false
			attack_finished.emit()
			return false
		
		# Deal damage to target
		var health_component = target_entity.get_component("HealthComponent")
		if health_component:
			var actual_damage = health_component.take_damage(damage, entity)
			target_hit.emit(target_entity, actual_damage)
	
	# Finish attack after cooldown
	if entity and is_instance_valid(entity):
		await entity.get_tree().create_timer(attack_cooldown).timeout
	is_attacking = false
	attack_finished.emit()
	
	return true

func equip_weapon(weapon: WeaponData):
	current_weapon = weapon
	weapon_changed.emit(weapon)

func unequip_weapon():
	current_weapon = null
	weapon_changed.emit(null)

func get_weapon() -> WeaponData:
	return current_weapon

func set_base_damage(damage: float):
	base_damage = damage

func set_attack_range(range_value: float):
	attack_range = range_value

func set_ranged_damage_multiplier(value: float):
	ranged_damage_multiplier = max(0.0, value)

