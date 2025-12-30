## Top-down camera controller
extends Camera3D
class_name CameraController

var target: Node3D = null
var follow_distance: float = 15.0
var follow_height: float = 20.0
var follow_speed: float = 5.0

func _ready():
	# Set up top-down view
	rotation_degrees = Vector3(-60, 0, 0)

func _process(delta: float):
	if target:
		var target_pos = target.global_position
		var desired_pos = target_pos + Vector3(0, follow_height, follow_distance)
		
		global_position = global_position.lerp(desired_pos, follow_speed * delta)
		look_at(target_pos, Vector3.UP)

func set_target(p_target: Node3D):
	target = p_target

