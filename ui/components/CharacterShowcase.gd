## Transparent 3D turntable that shows one character model over the UI background.
## Has its own World3D, so it never renders (or is lit by) the game world.
extends HiResView
class_name CharacterShowcase

@export var rotation_speed: float = 0.6  # sway speed
@export var sway_angle: float = 0.75     # radians left/right of the 3/4 front view (0 = spin)
@export var target_height: float = 1.35


var camera: Camera3D
var turntable: Node3D
var stage_material: StandardMaterial3D
var _model: Node3D = null
var _time: float = 0.0

## Interactive (the shop's big preview): drag to turn the model and tilt the view, wheel to zoom,
## double click to reset. It sways on its own again after IDLE_RETURN seconds without input.
var interactive: bool = false:
	set(value):
		interactive = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = Control.CURSOR_DRAG if value else Control.CURSOR_ARROW
const ORBIT_CENTER := Vector3(0, 0.6, 0)
const PITCH_MIN: float = -0.1
const PITCH_MAX: float = 0.75
const ZOOM_MIN: float = 1.8
const ZOOM_MAX: float = 6.0
const IDLE_RETURN: float = 4.0
var _yaw: float = -0.3
var _yaw_speed: float = 0.0
var _pitch: float = 0.12
var _zoom: float = 5.0
var _zoom_target: float = 5.0
var _dragging: bool = false
var _idle: float = 99.0

func _init():
	super()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

	var env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.85)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.4
	key.light_color = Color(1.0, 0.96, 0.9)
	viewport.add_child(key)

	# Colored rim lights give the "neon glass" look
	var rim_left = OmniLight3D.new()
	rim_left.position = Vector3(-1.8, 1.6, -1.2)
	rim_left.light_color = Color(0.45, 1.0, 0.55)
	rim_left.light_energy = 2.2
	rim_left.omni_range = 5.0
	viewport.add_child(rim_left)

	var rim_right = OmniLight3D.new()
	rim_right.position = Vector3(1.8, 1.4, -1.0)
	rim_right.light_color = Color(0.75, 0.45, 1.0)
	rim_right.light_energy = 2.0
	rim_right.omni_range = 5.0
	viewport.add_child(rim_right)

	camera = Camera3D.new()
	camera.fov = 32.0
	camera.position = Vector3(0, 1.05, 4.2)
	camera.rotation_degrees = Vector3(-7, 0, 0)
	viewport.add_child(camera)

	# Glowing stage disc
	var stage = MeshInstance3D.new()
	var disc = CylinderMesh.new()
	disc.top_radius = 0.85
	disc.bottom_radius = 0.9
	disc.height = 0.06
	stage.mesh = disc
	stage_material = StandardMaterial3D.new()
	stage_material.albedo_color = Color(1, 1, 1, 0.12)
	stage_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stage_material.emission_enabled = true
	stage_material.emission = Color(0.52, 0.91, 0.42)
	stage_material.emission_energy_multiplier = 0.6
	stage_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stage.material_override = stage_material
	stage.position.y = -0.03
	viewport.add_child(stage)

	turntable = Node3D.new()
	viewport.add_child(turntable)

func _process(delta: float):
	_time += delta
	if interactive:
		_process_interactive(delta)
		return
	if turntable:
		if sway_angle > 0.0:
			# Keep the face in view: generated models are best from the front
			turntable.rotation.y = -0.3 + sin(_time * rotation_speed) * sway_angle
		else:
			turntable.rotation.y += rotation_speed * delta
		turntable.position.y = sin(_time * 1.6) * 0.03

func _process_interactive(delta: float):
	_idle += delta
	if not _dragging:
		if _idle > IDLE_RETURN and sway_angle <= 0.0:
			_yaw += rotation_speed * delta  # props spin all the way round
			_pitch = lerp(_pitch, 0.12, 1.0 - exp(-delta * 1.5))
		elif _idle > IDLE_RETURN:
			# Back to the gentle sway around the 3/4 front view
			var sway = -0.3 + sin((_idle - IDLE_RETURN) * rotation_speed) * sway_angle
			_yaw = lerp_angle(_yaw, sway, 1.0 - exp(-delta * 1.5))
			_pitch = lerp(_pitch, 0.12, 1.0 - exp(-delta * 1.5))
		else:
			_yaw += _yaw_speed * delta  # throw momentum
			_yaw_speed *= exp(-delta * 4.0)
	_zoom = lerp(_zoom, _zoom_target, 1.0 - exp(-delta * 10.0))
	turntable.rotation.y = _yaw
	turntable.position.y = sin(_time * 1.6) * 0.03
	camera.position = ORBIT_CENTER + Vector3(0, sin(_pitch), cos(_pitch)) * _zoom
	camera.look_at(ORBIT_CENTER)

func _gui_input(event: InputEvent):
	if not interactive:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_idle = 0.0
			if event.pressed and event.double_click:
				reset_view()
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step = -0.3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.3
			_zoom_target = clamp(_zoom_target + step, ZOOM_MIN, ZOOM_MAX)
			_idle = 0.0
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_yaw += event.relative.x * 0.012
		_yaw_speed = clamp(event.relative.x * 0.012 / max(get_process_delta_time(), 0.001), -12.0, 12.0)
		_pitch = clamp(_pitch + event.relative.y * 0.006, PITCH_MIN, PITCH_MAX)
		_idle = 0.0
		accept_event()

## Back to the front view at the default zoom
func reset_view():
	_yaw = -0.3
	_yaw_speed = 0.0
	_pitch = 0.12
	_zoom_target = 5.0
	_idle = 99.0

## Show a character (CharacterData). Falls back to a colored capsule without a model.
func show_character(data: CharacterData):
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = Node3D.new()
	turntable.add_child(_model)

	if data:
		stage_material.emission = data.color.lightened(0.2)
	sway_angle = 0.75
	_time = 0.0  # every new character starts facing the camera

	if data and data.model_path != "" and ResourceLoader.exists(data.model_path):
		var scene = load(data.model_path)
		if scene:
			var instance = scene.instantiate()
			ModelUtils.apply_lowpoly_look(instance)
			_model.add_child(instance)
			_normalize(instance)
			_play_idle(instance)
	else:
		var mesh = MeshInstance3D.new()
		var capsule = CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.2
		mesh.mesh = capsule
		var mat = StandardMaterial3D.new()
		mat.albedo_color = data.color if data else Color(0.6, 0.6, 0.6)
		mesh.material_override = mat
		mesh.position.y = 0.6
		_model.add_child(mesh)

	# Pop-in
	_model.scale = Vector3.ONE * 0.6
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "scale", Vector3.ONE, 0.35)

## Show a character with specific skin and hat applied (for shop skin/hat preview).
func show_character_with_wear(data: CharacterData, skin_id: String, hat_id: String):
	show_character(data)
	if _model and is_instance_valid(_model) and _model.get_child_count() > 0:
		Cosmetics.apply_to_character(_model, skin_id, hat_id)
	else:
		# Model loads async via instantiate; apply cosmetics after pop-in tween
		await get_tree().create_timer(0.4).timeout
		if _model and is_instance_valid(_model) and _model.get_child_count() > 0:
			Cosmetics.apply_to_character(_model, skin_id, hat_id)

## Show any prop (weapon, pickup, container): fitted to `fit_size`, standing on the stage.
## `spin` turns it all the way round instead of the character's sway.
func show_model(instance: Node3D, color: Color, fit_size: float = 1.2, spin: bool = true, lift: float = 0.35):
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = Node3D.new()
	turntable.add_child(_model)
	stage_material.emission = color.lightened(0.2)
	sway_angle = 0.0 if spin else 0.75
	_time = 0.0
	if instance:
		_model.add_child(instance)
		instance.scale = Vector3.ONE  # measured unscaled (LootVisuals.fit may have scaled it)
		instance.position = Vector3.ZERO
		var aabb = _collect_aabb(instance, Transform3D.IDENTITY)
		var longest = max(aabb.size.x, aabb.size.y, aabb.size.z)
		if longest > 0.0001:
			var s = fit_size / longest
			instance.scale = Vector3.ONE * s
			var center = aabb.get_center()
			# lift > 0: float with the center at that height (pickups), 0: stand on the stage
			var y = -aabb.position.y * s if lift <= 0.0 else lift - center.y * s
			instance.position = Vector3(-center.x * s, y, -center.z * s)
	_model.scale = Vector3.ONE * 0.6
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "scale", Vector3.ONE, 0.35)

## Rigged models (tools/ai_models) come with an idle clip: play it in the menu
func _play_idle(instance: Node):
	var players = instance.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var ap: AnimationPlayer = players[0]
	if ap.has_animation("idle"):
		ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		ap.play("idle")

## Scale to target_height, stand on y=0 and center on X/Z
func _normalize(instance: Node3D):
	var aabb = _collect_aabb(instance, Transform3D.IDENTITY)
	if aabb.size.y <= 0.0001:
		return
	# Wide models (pumpkin) would fill the whole frame if we only matched the height
	var s = target_height / max(aabb.size.y, max(aabb.size.x, aabb.size.z) * 0.8)
	instance.scale = Vector3.ONE * s
	var center = aabb.get_center()
	instance.position = Vector3(-center.x * s, -aabb.position.y * s, -center.z * s)

func _collect_aabb(node: Node, xform: Transform3D) -> AABB:
	var result = AABB()
	var has_any = false
	var node_xform = xform
	if node is Node3D:
		node_xform = xform * node.transform
	if node is MeshInstance3D and node.mesh:
		result = node_xform * node.get_aabb()
		has_any = true
	for child in node.get_children():
		var child_aabb = _collect_aabb(child, node_xform)
		if child_aabb.size != Vector3.ZERO:
			result = child_aabb if not has_any else result.merge(child_aabb)
			has_any = true
	return result
