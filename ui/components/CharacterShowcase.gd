## Transparent 3D turntable that shows one character model over the UI background.
## Has its own World3D, so it never renders (or is lit by) the game world.
extends SubViewportContainer
class_name CharacterShowcase

@export var rotation_speed: float = 0.6  # sway speed
@export var sway_angle: float = 0.75     # radians left/right of the 3/4 front view (0 = spin)
@export var target_height: float = 1.35

var viewport: SubViewport
var camera: Camera3D
var turntable: Node3D
var stage_material: StandardMaterial3D
var _model: Node3D = null
var _time: float = 0.0

func _init():
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)

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
	if turntable:
		if sway_angle > 0.0:
			# Keep the face in view: generated models are best from the front
			turntable.rotation.y = -0.3 + sin(_time * rotation_speed) * sway_angle
		else:
			turntable.rotation.y += rotation_speed * delta
		turntable.position.y = sin(_time * 1.6) * 0.03

## Show a character (CharacterData). Falls back to a colored capsule without a model.
func show_character(data: CharacterData):
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = Node3D.new()
	turntable.add_child(_model)

	if data:
		stage_material.emission = data.color.lightened(0.2)
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
