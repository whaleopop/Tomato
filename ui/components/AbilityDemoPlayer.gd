## Plays visual demonstrations of character abilities
extends Node3D
class_name AbilityDemoPlayer

@export var character_data: Resource  # CharacterData
@export var demo_interval: float = 4.0  # Seconds between ability demos
@export var auto_play: bool = true

var current_ability_index: int = 0
var demo_timer: float = 0.0
var abilities: Array = []
var effect_container: Node3D

func _ready():
	# Create container for temporary effects
	effect_container = Node3D.new()
	add_child(effect_container)

	if character_data:
		load_abilities_from_character(character_data)

	if auto_play:
		demo_timer = demo_interval * 0.5  # Start first demo sooner

func _process(delta):
	if not auto_play or abilities.is_empty():
		return

	demo_timer += delta

	if demo_timer >= demo_interval:
		demo_timer = 0.0
		play_next_ability_demo()

## Load abilities from CharacterData
func load_abilities_from_character(data: Resource):
	character_data = data
	abilities.clear()

	# CharacterData stores one AbilityData per slot
	if "active_ability" in data and data.active_ability:
		abilities.append(data.active_ability)

	if "passive_ability" in data and data.passive_ability:
		abilities.append(data.passive_ability)

## Play next ability in rotation
func play_next_ability_demo():
	if abilities.is_empty():
		return

	var ability = abilities[current_ability_index]
	play_ability_demo(ability)

	current_ability_index = (current_ability_index + 1) % abilities.size()

## Play demo for specific ability (AbilityData, ActiveAbility or PassiveAbility)
func play_ability_demo(ability) -> void:
	# Clear previous effects
	_clear_effects()

	# Create demo based on ability type
	if ability is PassiveAbility or (ability is AbilityData and ability.ability_type == "passive"):
		_demo_passive_ability(ability)
	else:
		_demo_active_ability(ability)

## Demo active ability (projectiles, bursts, etc.)
func _demo_active_ability(ability) -> void:
	# Generic active ability demo - override for specific abilities

	# Create burst effect
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 25
	particles.lifetime = 1.5
	particles.explosiveness = 0.7

	var process_mat = ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_mat.emission_sphere_radius = 0.3
	process_mat.direction = Vector3(1, 0.2, 0)  # Shoot forward
	process_mat.spread = 20
	process_mat.initial_velocity_min = 3.0
	process_mat.initial_velocity_max = 5.0
	process_mat.gravity = Vector3(0, -2, 0)
	process_mat.scale_min = 0.08
	process_mat.scale_max = 0.15

	# Color based on ability type (placeholder logic)
	var ability_color = _get_ability_color(ability)
	var gradient = Gradient.new()
	gradient.add_point(0.0, ability_color)
	gradient.add_point(1.0, Color(ability_color.r, ability_color.g, ability_color.b, 0.0))
	var gradient_tex = GradientTexture1D.new()
	gradient_tex.gradient = gradient
	process_mat.color_ramp = gradient_tex

	particles.process_material = process_mat

	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	particles.draw_pass_1 = sphere

	particles.position = Vector3(0, 1.2, 0.5)
	effect_container.add_child(particles)

	# Add flash light
	var flash = OmniLight3D.new()
	flash.light_color = ability_color
	flash.light_energy = 3.0
	flash.omni_range = 4.0
	flash.position = particles.position
	effect_container.add_child(flash)

	# Fade out flash
	var tween = create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 1.0).set_ease(Tween.EASE_OUT)

## Demo passive ability (aura, stat boost indicators)
func _demo_passive_ability(ability) -> void:
	# Create aura effect
	var aura = GPUParticles3D.new()
	aura.emitting = true
	aura.amount = 15
	aura.lifetime = 3.0

	var process_mat = ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_mat.emission_sphere_radius = 0.8
	process_mat.direction = Vector3.UP
	process_mat.spread = 180
	process_mat.initial_velocity_min = 0.3
	process_mat.initial_velocity_max = 0.8
	process_mat.gravity = Vector3.ZERO
	process_mat.scale_min = 0.06
	process_mat.scale_max = 0.12

	var ability_color = _get_ability_color(ability)
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(ability_color.r, ability_color.g, ability_color.b, 0.0))
	gradient.add_point(0.3, ability_color)
	gradient.add_point(1.0, Color(ability_color.r, ability_color.g, ability_color.b, 0.0))
	var gradient_tex = GradientTexture1D.new()
	gradient_tex.gradient = gradient
	process_mat.color_ramp = gradient_tex

	aura.process_material = process_mat

	var sphere = SphereMesh.new()
	sphere.radius = 0.08
	aura.draw_pass_1 = sphere

	aura.position = Vector3(0, 0.8, 0)
	effect_container.add_child(aura)

	# Pulse light
	var pulse_light = OmniLight3D.new()
	pulse_light.light_color = ability_color
	pulse_light.light_energy = 0.0
	pulse_light.omni_range = 3.0
	pulse_light.position = Vector3(0, 1.0, 0)
	effect_container.add_child(pulse_light)

	# Pulsing animation
	var tween = create_tween()
	tween.set_loops(2)
	tween.tween_property(pulse_light, "light_energy", 2.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(pulse_light, "light_energy", 0.3, 0.5).set_ease(Tween.EASE_IN_OUT)

## Get color for ability (placeholder - can be customized per ability)
func _get_ability_color(ability) -> Color:
	# Try to get color from ability if it has one
	if "effect_color" in ability:
		return ability.effect_color

	# Otherwise use defaults based on ability name/type
	var ability_name: String = ability.ability_name if "ability_name" in ability else ""

	if "fire" in ability_name.to_lower() or "burn" in ability_name.to_lower():
		return Color(1.0, 0.4, 0.1)  # Orange/red
	elif "ice" in ability_name.to_lower() or "frost" in ability_name.to_lower():
		return Color(0.3, 0.7, 1.0)  # Blue
	elif "heal" in ability_name.to_lower():
		return Color(0.2, 1.0, 0.3)  # Green
	elif "speed" in ability_name.to_lower():
		return Color(1.0, 1.0, 0.3)  # Yellow
	elif "damage" in ability_name.to_lower() or "attack" in ability_name.to_lower():
		return Color(1.0, 0.2, 0.2)  # Red
	elif "defense" in ability_name.to_lower() or "shield" in ability_name.to_lower():
		return Color(0.3, 0.5, 1.0)  # Blue
	else:
		return Color(0.7, 0.5, 1.0)  # Purple (default)

## Clear all effect children
func _clear_effects():
	for child in effect_container.get_children():
		child.queue_free()

## Start/stop auto play
func set_auto_play(enabled: bool):
	auto_play = enabled
	demo_timer = 0.0

## Manually trigger ability demo by index
func play_ability_by_index(index: int):
	if index >= 0 and index < abilities.size():
		current_ability_index = index
		play_ability_demo(abilities[index])
