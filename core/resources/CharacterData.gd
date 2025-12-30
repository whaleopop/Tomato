## Resource defining character data (vegetable/fruit)
extends Resource
class_name CharacterData

@export var character_name: String = ""
@export var description: String = ""
@export var model_path: String = ""
@export var base_health: float = 100.0
@export var base_speed: float = 5.0
@export var active_ability: AbilityData = null
@export var passive_ability: AbilityData = null
@export var icon: Texture2D = null

