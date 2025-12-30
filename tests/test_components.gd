## Tests for component system
extends "res://addons/gut/test.gd"

var entity  # Entity
var health_component: HealthComponent
var movement_component: MovementComponent

func before_each():
	entity = Entity.new()
	health_component = HealthComponent.new(entity, 100.0)
	movement_component = MovementComponent.new(entity)
	entity.add_component(health_component)
	entity.add_component(movement_component)

func after_each():
	if entity:
		entity.queue_free()

func test_entity_has_component():
	assert_true(entity.has_component("HealthComponent"))
	assert_true(entity.has_component("MovementComponent"))
	assert_false(entity.has_component("CombatComponent"))

func test_health_component_take_damage():
	var initial_health = health_component.current_health
	health_component.take_damage(20.0)
	assert_eq(health_component.current_health, initial_health - 20.0)

func test_health_component_heal():
	health_component.current_health = 50.0
	health_component.heal(30.0)
	assert_eq(health_component.current_health, 80.0)

func test_health_component_die():
	health_component.take_damage(100.0)
	assert_true(health_component.is_dead)

func test_movement_component_set_direction():
	movement_component.set_move_direction(Vector3(1, 0, 0))
	assert_true(movement_component.is_moving)

func test_movement_component_stop():
	movement_component.set_move_direction(Vector3(1, 0, 0))
	movement_component.stop()
	assert_false(movement_component.is_moving)

