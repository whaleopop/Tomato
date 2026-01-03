## Tomato character data
extends CharacterData
class_name TomatoCharacter

func _init():
	character_name = "Tomato"
	description = "A brave red warrior with juicy resilience"
	base_health = 90.0
	base_speed = 6.0
	model_path = "res://models/Tomato.glb"
	color = Color(0.9, 0.2, 0.2)  # Red
	model_scale = 0.8
	model_offset = Vector3(0, 0, 0)
	
	# Active ability: Tomato Splash - throws acidic juice
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Tomato Splash"
	active_ability_data.description = "Throws acidic tomato juice that damages enemies"
	active_ability_data.cooldown = 8.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/TomatoSplash.gd"
	active_ability = active_ability_data
	
	# Passive ability: Juicy Resilience - regenerates health slowly
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Juicy Resilience"
	passive_ability_data.description = "Slowly regenerates health over time"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/HealthRegeneration.gd"
	passive_ability = passive_ability_data

