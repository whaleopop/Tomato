## Base structure class for buildings
extends Node3D
class_name Structure

signal structure_destroyed

var health: float = 100.0
var max_health: float = 100.0
var is_destroyed: bool = false

func _ready():
	add_to_group("structures")

func take_damage(amount: float):
	if is_destroyed:
		return
	
	health -= amount
	if health <= 0.0:
		destroy()

func destroy():
	if is_destroyed:
		return
	
	is_destroyed = true
	structure_destroyed.emit()
	
	# Animate destruction
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.5)  # not 0: physics can't invert a zero basis
	tween.tween_callback(queue_free)
