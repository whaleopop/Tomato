## Watermelon character data (model generated from art/concepts/watermelon.png)
extends CharacterData
class_name WatermelonCharacter

func _init():
	character_name = "Watermelon"
	description = "A slow, heavy melon with the thickest rind on the island"
	base_health = 160.0
	base_speed = 3.8
	model_path = "res://models/characters/Watermelon.glb"
	color = Color(0.25, 0.6, 0.25)
	model_scale = 1.0  # Auto-normalized to the standard height
	model_origin_at_feet = true

	# Active ability: Melon Roll
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Melon Roll"
	active_ability_data.description = "Rolls forward at high speed"
	active_ability_data.cooldown = 7.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/Dash.gd"
	active_ability = active_ability_data

	# Passive ability: Thick Rind
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Thick Rind"
	passive_ability_data.description = "Takes less damage from every hit"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/DamageResistance.gd"
	passive_ability = passive_ability_data
