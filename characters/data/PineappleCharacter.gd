## Pineapple character data (model generated from art/concepts/pineapple.png)
extends CharacterData
class_name PineappleCharacter

func _init():
	character_name = "Pineapple"
	description = "A grumpy tropical brawler in spiky armor. Lands on your head, crown first"
	base_health = 125.0
	base_speed = 5.0
	model_path = "res://models/characters/Pineapple.glb"
	color = Color(0.95, 0.66, 0.12)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true

	# Active ability: Crown Drop - leaps to the target and lands on everyone there
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Crown Drop"
	active_ability_data.description = "Leaps to the target spot and hurts everyone where it lands"
	active_ability_data.cooldown = 8.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/TurnipToss.gd"
	active_ability = active_ability_data

	# Passive ability: Spiky Skin
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Spiky Skin"
	passive_ability_data.description = "Whoever hurts the pineapple takes 20% of the damage back"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/SpikySkin.gd"
	passive_ability = passive_ability_data
