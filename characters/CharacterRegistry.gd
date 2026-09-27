## Single source of truth for the playable character roster.
## Used by menus, client world and server so every peer builds the same character from its name.
extends RefCounted
class_name CharacterRegistry

static func get_all() -> Array[CharacterData]:
	return [
		TomatoCharacter.new(),
		CarrotCharacter.new(),
		PumpkinCharacter.new(),
		CornCharacter.new(),
		BroccoliCharacter.new(),
		BeetCharacter.new(),
		GreenPepperCharacter.new(),
		TurnipCharacter.new(),
		AppleCharacter.new(),
		LemonCharacter.new(),
		GrapeCharacter.new(),
		WatermelonCharacter.new(),
	]

static func get_by_name(character_name: String) -> CharacterData:
	match character_name:
		"Tomato":
			return TomatoCharacter.new()
		"Carrot":
			return CarrotCharacter.new()
		"Pumpkin":
			return PumpkinCharacter.new()
		"Corn":
			return CornCharacter.new()
		"Broccoli":
			return BroccoliCharacter.new()
		"Beet":
			return BeetCharacter.new()
		"Green Pepper":
			return GreenPepperCharacter.new()
		"Turnip":
			return TurnipCharacter.new()
		"Apple":
			return AppleCharacter.new()
		"Lemon":
			return LemonCharacter.new()
		"Grape":
			return GrapeCharacter.new()
		"Watermelon":
			return WatermelonCharacter.new()
	return null
