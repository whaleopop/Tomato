## Beet character data (model generated from art/concepts/beet.png)
extends CharacterData
class_name BeetCharacter

func _init():
	character_name = "Beet"
	description = "A powerful melee fighter with crushing attacks"
	base_health = 110.0
	base_speed = 5.5
	model_path = "res://models/characters/Beet.glb"
	color = Color(0.72, 0.1, 0.3)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true
	
	# Active ability: Beet Crush - powerful melee strike
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Beet Crush"
	active_ability_data.description = "Powerful melee strike that deals heavy damage"
	active_ability_data.cooldown = 8.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/SlashingStrike.gd"
	active_ability = active_ability_data
	
	# Passive ability: Tough Skin - increased max health
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Tough Skin"
	passive_ability_data.description = "20% increased max health"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/ToughSkin.gd"
	passive_ability = passive_ability_data
