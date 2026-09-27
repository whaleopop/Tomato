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
@export var color: Color = Color(0.5, 0.5, 0.5)  # Character color for visuals
@export var model_scale: float = 1.0  # Scale multiplier for model normalization
@export var model_offset: Vector3 = Vector3.ZERO  # Offset for model positioning
## True for models whose origin is at the feet (AI-generated / rigged by tools/ai_models)
@export var model_origin_at_feet: bool = false

