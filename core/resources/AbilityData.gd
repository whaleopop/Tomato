## Resource defining ability data
extends Resource
class_name AbilityData

@export var ability_name: String = ""
@export var description: String = ""
@export var cooldown: float = 5.0
@export var duration: float = 0.0
@export var ability_type: String = "active"  # "active" or "passive"
@export var script_path: String = ""
@export var icon: Texture2D = null

