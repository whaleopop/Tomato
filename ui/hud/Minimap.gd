## Minimap UI component
extends Control
class_name Minimap

var map_size: Vector2 = Vector2(200, 200)
var player_position: Vector2 = Vector2.ZERO

func _ready():
	custom_minimum_size = map_size

func _draw():
	# Draw minimap background
	draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.2, 0.2, 0.2))
	
	# Draw player position
	if player_position != Vector2.ZERO:
		draw_circle(player_position, 5.0, Color.GREEN)

func update_player_position(world_pos: Vector3):
	# Convert world position to minimap coordinates
	# This is a simplified version
	player_position = Vector2(world_pos.x, world_pos.z) * 0.1 + map_size * 0.5
	queue_redraw()

