## Apple character data (model generated from art/concepts/apple.png)
extends CharacterData
class_name AppleCharacter

func _init():
	character_name = "Apple"
	description = "A furious apple bruiser that keeps the doctor - and everyone else - away"
	base_health = 115.0
	base_speed = 5.5
	model_path = "res://models/characters/Apple.glb"
	color = Color(0.85, 0.2, 0.15)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true

	# Active ability: Core Slam
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Core Slam"
	active_ability_data.description = "Pounds the ground, damaging every enemy around"
	active_ability_data.cooldown = 9.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/PumpkinSmash.gd"
	active_ability = active_ability_data

	# Passive ability: Crisp Skin
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Crisp Skin"
	passive_ability_data.description = "Extra maximum health"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/ToughSkin.gd"
	passive_ability = passive_ability_data
