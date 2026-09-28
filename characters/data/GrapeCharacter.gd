## Grape character data (model generated from art/concepts/grape.png)
extends CharacterData
class_name GrapeCharacter

func _init():
	character_name = "Grape"
	description = "A whole bunch of trouble: now you see it, now you don't"
	base_health = 90.0
	base_speed = 6.0
	model_path = "res://models/characters/Grape.glb"
	color = Color(0.5, 0.28, 0.7)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true

	# Active ability: Grape Decoy
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Grape Decoy"
	active_ability_data.description = "Vanish for 3.5 s while a decoy grape runs on. A shot gives you away"
	active_ability_data.cooldown = 12.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/GrapeDecoy.gd"
	active_ability = active_ability_data

	# Passive ability: Small Target
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Small Target"
	passive_ability_data.description = "Enemies spot you only from 3/4 of their sight distance"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/SmallTarget.gd"
	passive_ability = passive_ability_data
