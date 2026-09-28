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

	# Active ability: Newton's Apple
	var active_ability_data = AbilityData.new()
	active_ability_data.ability_name = "Newton's Apple"
	active_ability_data.description = "An apple drops on the aimed spot: 35 damage and a 1.2 s stun"
	active_ability_data.cooldown = 9.0
	active_ability_data.ability_type = "active"
	active_ability_data.script_path = "res://abilities/active/NewtonsApple.gd"
	active_ability = active_ability_data

	# Passive ability: Unshakable
	var passive_ability_data = AbilityData.new()
	passive_ability_data.ability_name = "Unshakable"
	passive_ability_data.description = "Can't be stunned, slowed, blinded or knocked back"
	passive_ability_data.ability_type = "passive"
	passive_ability_data.script_path = "res://abilities/passive/Unshakable.gd"
	passive_ability = passive_ability_data
