## Tests for ability system
extends "res://addons/gut/test.gd"

var entity  # Entity
var ability_component: AbilityComponent
var dash_ability: Dash

func before_each():
	entity = Entity.new()
	ability_component = AbilityComponent.new(entity)
	entity.add_component(ability_component)
	dash_ability = Dash.new()

func after_each():
	if entity:
		entity.queue_free()

func test_add_active_ability():
	ability_component.add_active_ability(dash_ability)
	assert_eq(ability_component.active_abilities.size(), 1)

func test_ability_cooldown():
	ability_component.add_active_ability(dash_ability)
	var success = ability_component.activate_ability(0, Vector3.ZERO)
	assert_true(success)
	
	# Try to activate again immediately (should fail due to cooldown)
	var success2 = ability_component.activate_ability(0, Vector3.ZERO)
	assert_false(success2)

func test_passive_ability_apply():
	var passive = DamageResistance.new(0.1)
	ability_component.add_passive_ability(passive)
	assert_eq(ability_component.passive_abilities.size(), 1)

