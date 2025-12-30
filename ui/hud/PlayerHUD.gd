## Main player HUD
extends Control
class_name PlayerHUD

var health_bar: HealthBar = null
var ability_bar: AbilityBar = null
var minimap: Minimap = null

var player: Player = null

func _ready():
	# Try to get child nodes, but don't fail if they don't exist
	health_bar = get_node_or_null("HealthBar")
	ability_bar = get_node_or_null("AbilityBar")
	minimap = get_node_or_null("Minimap")
	
	if not health_bar:
		print("[PlayerHUD] WARNING: HealthBar not found, creating default...")
		_create_default_health_bar()
	
	if not ability_bar:
		print("[PlayerHUD] WARNING: AbilityBar not found, creating default...")
		_create_default_ability_bar()
	
	if not minimap:
		print("[PlayerHUD] WARNING: Minimap not found, creating default...")
		_create_default_minimap()

func setup(p_player: Player):
	player = p_player
	
	# Connect to player components
	if player:
		var health = player.get_component("HealthComponent")
		if health and health_bar:
			health_bar.setup(health)
		
		var ability_component = player.get_component("AbilityComponent")
		if ability_component and ability_bar:
			ability_bar.setup(ability_component)

func _process(delta: float):
	if player and minimap:
		# Update minimap
		minimap.update_player_position(player.global_position)

func _create_default_health_bar():
	# Create a simple health bar positioned in top-left
	health_bar = HealthBar.new()
	health_bar.name = "HealthBar"
	health_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	health_bar.position = Vector2(20, 20)
	health_bar.custom_minimum_size = Vector2(250, 60)
	add_child(health_bar)
	print("[PlayerHUD] ✓ Default HealthBar created at top-left")

func _create_default_ability_bar():
	# Create a simple ability bar positioned at bottom-center
	ability_bar = AbilityBar.new()
	ability_bar.name = "AbilityBar"
	ability_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ability_bar.anchor_top = 1.0
	ability_bar.anchor_bottom = 1.0
	ability_bar.offset_left = -180
	ability_bar.offset_right = 180
	ability_bar.offset_top = -100
	ability_bar.offset_bottom = -20
	add_child(ability_bar)
	print("[PlayerHUD] ✓ Default AbilityBar created at bottom-center")

func _create_default_minimap():
	# Create a simple minimap positioned in top-right
	minimap = Minimap.new()
	minimap.name = "Minimap"
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -220
	minimap.offset_right = -20
	minimap.offset_top = 20
	minimap.offset_bottom = 220
	add_child(minimap)
	print("[PlayerHUD] ✓ Default Minimap created at top-right")
