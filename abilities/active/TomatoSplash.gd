## Tomato Splash - throws acidic juice
extends ActiveAbility
class_name TomatoSplash

var damage: float = 30.0
var splash_radius: float = 3.0

func _init():
	ability_name = "Tomato Splash"
	cooldown = 8.0
	duration = 0.5
	max_range = 9.0  # a throw, not a sniper: clamped towards the cursor

const FLIGHT_TIME: float = 0.35  # the blob is thrown: it hits when it lands (dodgeable)

func _on_activate(entity, target_position: Vector3) -> bool:  # entity: Entity
	var color = AbilityFX.hero_color(entity)
	AbilityFX.throw_blob(entity, entity.global_position + Vector3(0, 1.0, 0), target_position, color, FLIGHT_TIME)
	if entity.is_inside_tree():
		await entity.get_tree().create_timer(FLIGHT_TIME).timeout
	if not is_instance_valid(entity) or not entity.is_inside_tree():
		return true

	# Everyone in the splash where it lands
	for target in _find_targets_in_radius(entity, target_position):
		var health = target.get_component("HealthComponent")
		if health:
			health.take_damage(damage, entity)
	_create_splash_effect(entity, target_position)
	return true

func _find_targets_in_radius(entity, center: Vector3) -> Array:  # entity: Entity
	var targets: Array = []
	var all_entities = entity.get_tree().get_nodes_in_group("entities")

	for other_entity in all_entities:
		if other_entity == entity:
			continue

		var distance = center.distance_to(other_entity.global_position)
		if distance <= splash_radius:
			targets.append(other_entity)

	return targets

func _create_splash_effect(entity, position: Vector3):  # entity: Entity
	AbilityFX.splash(entity, position, AbilityFX.hero_color(entity), splash_radius)

