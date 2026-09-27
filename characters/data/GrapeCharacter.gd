## Grape character data (model generated from art/concepts/grape.png)
extends CharacterData
class_name GrapeCharacter

func _init():
	character_name = "Grape"
	description = "A whole bunch of trouble: fires its own grapes"
	base_health = 90.0
	base_speed = 6.0
	model_path = "res://models/characters/Grape.glb"
	color = Color(0.5, 0.28, 0.7)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true

	# Active ability: Grape Shot
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Grape Shot"
	active_ability_data.description = "Fires a volley of grapes at the target"
	active_ability_data.cooldown = 8.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/KernelBarrage.gd"
	active_ability = active_ability_data

	# Passive ability: Loose Bunch
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Loose Bunch"
	passive_ability_data.description = "Chance to dodge incoming damage"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/DodgeChance.gd"
	passive_ability = passive_ability_data
