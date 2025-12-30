## Ability bar UI component
extends Control
class_name AbilityBar

var ability_component: AbilityComponent = null
var ability_buttons: Array[Button] = []

func _ready():
	pass

func setup(p_ability_component: AbilityComponent):
	ability_component = p_ability_component
	
	if ability_component:
		ability_component.ability_activated.connect(_on_ability_activated)
		ability_component.ability_cooldown_finished.connect(_on_cooldown_finished)
		_update_abilities()

func _update_abilities():
	# Clear existing buttons
	for button in ability_buttons:
		button.queue_free()
	ability_buttons.clear()
	
	if not ability_component:
		return
	
	# Create buttons for each active ability
	for i in range(ability_component.active_abilities.size()):
		var ability = ability_component.active_abilities[i]
		var button = Button.new()
		button.text = ability.ability_name
		button.custom_minimum_size = Vector2(80, 80)
		button.position = Vector2(i * 90, 0)
		add_child(button)
		ability_buttons.append(button)
		
		# Connect button
		button.pressed.connect(_on_ability_button_pressed.bind(i))

func _on_ability_button_pressed(index: int):
	if ability_component:
		# Get mouse position in world
		var camera = get_viewport().get_camera_3d()
		if camera:
			var mouse_pos = get_viewport().get_mouse_position()
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 1000.0
			
			# Get world_3d from viewport (Control doesn't have get_world_3d())
			var world_3d = get_viewport().world_3d
			if not world_3d:
				return
			
			var space_state = world_3d.direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			var result = space_state.intersect_ray(query)
			
			var target_pos = Vector3.ZERO
			if result:
				target_pos = result.position
			
			ability_component.activate_ability(index, target_pos)

func _on_ability_activated(ability: ActiveAbility):
	_update_abilities()

func _on_cooldown_finished(ability: ActiveAbility):
	_update_abilities()
