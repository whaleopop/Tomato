## Life in the air around the camera (GameEnvironment adds it; looks only, nothing is synced):
## pollen motes drifting in the sun, a few leaves tumbling down, butterflies fluttering by during
## the day and fireflies when the night event (MapEvents) falls or the sun is setting.
## Everything follows the spot the camera looks at; particles stay in the world as it moves.
extends Node3D
class_name AmbientLife

const BUTTERFLIES: int = 7
const WANDER: float = 11.0       # how far from the camera's spot butterflies roam

var _pollen: GPUParticles3D = null
var _leaves: GPUParticles3D = null
var _fireflies: GPUParticles3D = null
var _butterflies: Array = []     # [node, target, speed, phase, wings]
var _anchor := Vector3.ZERO
var _night: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready():
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_rng.randomize()
	_pollen = _particles(140, 9.0, Vector3(18, 2.5, 14), 0.07, Color(1.0, 0.97, 0.8, 0.7), false)
	var pm: ParticleProcessMaterial = _pollen.process_material
	pm.gravity = Vector3(0.15, 0.02, 0.05)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.initial_velocity_max = 0.2
	_leaves = _particles(22, 7.0, Vector3(18, 1.0, 14), 0.2, Color(1, 1, 1, 1), false)
	var lm: ParticleProcessMaterial = _leaves.process_material
	lm.gravity = Vector3(0.5, -0.6, 0.2)
	lm.angular_velocity_min = -180.0
	lm.angular_velocity_max = 180.0
	lm.turbulence_enabled = true
	lm.turbulence_noise_strength = 1.2
	var ramp = Gradient.new()
	ramp.set_color(0, Color(0.45, 0.7, 0.25))
	ramp.set_color(1, Color(0.95, 0.6, 0.2))
	var ramp_tex = GradientTexture1D.new()
	ramp_tex.gradient = ramp
	lm.color_initial_ramp = ramp_tex
	_fireflies = _particles(70, 5.0, Vector3(15, 1.0, 11), 0.09, Color(0.85, 1.0, 0.35, 1.0), true)
	var fm: ParticleProcessMaterial = _fireflies.process_material
	fm.gravity = Vector3.ZERO
	fm.turbulence_enabled = true
	fm.turbulence_noise_strength = 1.5
	fm.turbulence_noise_scale = 2.0
	_fireflies.amount_ratio = 0.0
	for i in BUTTERFLIES:
		_butterflies.append(_make_butterfly())

## Soft round particles in a box around the anchor
func _particles(amount: int, lifetime: float, box: Vector3, size: float, color: Color, glow: bool) -> GPUParticles3D:
	var p = GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.visibility_aabb = AABB(-box * 1.5 - Vector3(0, 4, 0), box * 3.0 + Vector3(0, 8, 0))
	var m = ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = box
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 0.05
	m.initial_velocity_max = 0.3
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.color = color
	var fade = Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.2, 1.0))
	fade.add_point(Vector2(0.8, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_tex = CurveTexture.new()
	fade_tex.curve = fade
	m.alpha_curve = fade_tex
	p.process_material = m
	var quad = QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = FireTrail._soft_dot(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	if glow:
		mat.emission_enabled = true
		mat.emission = Color(0.8, 1.0, 0.3)
		mat.emission_energy_multiplier = 3.0
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func _make_butterfly() -> Array:
	var node = Node3D.new()
	add_child(node)
	var colors = [Color(1.0, 0.85, 0.25), Color(1.0, 0.55, 0.2), Color(0.55, 0.75, 1.0), Color(1.0, 1.0, 1.0), Color(0.95, 0.5, 0.85)]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = colors[_rng.randi() % colors.size()]
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var wings: Array = []
	for side in [-1, 1]:
		var hinge = Node3D.new()
		node.add_child(hinge)
		var wing = MeshInstance3D.new()
		var quad = QuadMesh.new()
		quad.size = Vector2(0.16, 0.13)
		quad.orientation = PlaneMesh.FACE_Y
		wing.mesh = quad
		wing.material_override = mat
		wing.position = Vector3(side * 0.08, 0, 0)
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hinge.add_child(wing)
		wings.append([hinge, side])
	node.position = _anchor + Vector3(_rng.randf_range(-WANDER, WANDER), 1.5, _rng.randf_range(-WANDER, WANDER))
	return [node, node.position, _rng.randf_range(1.2, 2.2), _rng.randf() * TAU, wings]

func _process(delta: float):
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	# The spot the camera looks at, on the ground (y about 1)
	var forward = -camera.global_transform.basis.z
	if forward.y < -0.05:
		var t = (camera.global_position.y - 1.0) / -forward.y
		_anchor = camera.global_position + forward * t
	for p in [_pollen, _leaves, _fireflies]:
		p.global_position = _anchor + Vector3(0, 1.2 if p != _leaves else 4.5, 0)

	# Night (the event) or late sunset: fireflies come out, butterflies go to sleep
	var environment = get_parent() as GameEnvironment
	var dusk = environment.dusk if environment else 0.0
	var dark = clamp((1.0 - MapEvents.sight_factor) * 2.0, 0.0, 1.0)
	var target = max(dark, smoothstep(0.75, 1.0, dusk) * 0.6)
	_night = move_toward(_night, target, delta * 0.4)
	_fireflies.amount_ratio = _night
	_pollen.amount_ratio = 1.0 - _night * 0.7

	for b in _butterflies:
		_fly(b, delta, _night < 0.5)

func _fly(b: Array, delta: float, awake: bool) -> void:
	var node: Node3D = b[0]
	node.visible = awake
	if not awake:
		return
	var pos = node.position
	var target: Vector3 = b[1]
	if pos.distance_to(target) < 0.5 or target.distance_to(_anchor) > WANDER * 1.6:
		b[1] = _anchor + Vector3(_rng.randf_range(-WANDER, WANDER), _rng.randf_range(0.9, 2.4), _rng.randf_range(-WANDER, WANDER))
		target = b[1]
	if pos.distance_to(_anchor) > WANDER * 2.5:
		node.position = b[1]  # the camera ran off: meet it there
		return
	b[3] += delta * 14.0
	var dir = (target - pos).normalized()
	# Fluttery: bobbing up and down, wobbling sideways
	var wobble = Vector3(sin(b[3] * 0.23), sin(b[3] * 0.5) * 0.6, cos(b[3] * 0.19)) * 0.6
	node.position = pos + (dir + wobble * 0.5) * float(b[2]) * delta
	if dir.length_squared() > 0.001:
		node.rotation.y = lerp_angle(node.rotation.y, atan2(dir.x, dir.z), delta * 4.0)
	var flap = sin(b[3]) * 1.1
	for w in b[4]:
		w[0].rotation.z = flap * w[1]
