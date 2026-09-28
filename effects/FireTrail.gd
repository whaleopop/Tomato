## Burning strip left by Spicy Dash: flames along the dash line that hurt anyone standing in
## them (not the caster). Damage ticks everywhere, but HealthComponent.take_damage only counts
## on the server, so every peer can run the same node for the visuals.
extends Node3D
class_name FireTrail

const SPACING: float = 0.8      # one flame patch per this many metres
const RADIUS: float = 0.9       # how close counts as "in the fire"
const LIFETIME: float = 3.0
const TICK: float = 0.5
const TICK_DAMAGE: float = 5.0  # 10 per second

var caster: Node3D = null
## Zone fire (HexTile.set_zone_state) reuses the look: no damage of its own, longer, no light
var tick_damage: float = TICK_DAMAGE
var lifetime: float = LIFETIME
var with_light: bool = true
var flame_scale: float = 1.0  # bigger patches for the zone fire on whole tiles
var _points: Array = []         # [position, appears_at]
var _flames: Array = []
var _age: float = 0.0
var _tick_left: float = TICK
var _dying: bool = false
var _light: OmniLight3D = null

static var _flame_material: StandardMaterial3D = null
static var _scorch_material: StandardMaterial3D = null

## Flames along `direction` from `start`, `length` metres, lit one after another over `spread_time`
func lay(start: Vector3, direction: Vector3, length: float, spread_time: float) -> void:
	var count = max(1, int(length / SPACING) + 1)
	var space = get_world_3d().direct_space_state if is_inside_tree() else null
	for i in count:
		var along = min(i * SPACING, length)
		var point = start + direction * along
		if space:  # sit on the ground under each patch (tiles have different heights)
			var q = PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.5, point + Vector3.DOWN * 2.0, 1)
			var hit = space.intersect_ray(q)
			if hit:
				point.y = hit.position.y
		var appears = spread_time * (along / length) if length > 0.01 else 0.0
		_points.append([point, appears])
		_flames.append(_make_flame(point))
	if not with_light:
		return
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 1.6
	_light.omni_range = max(3.0, length * 0.7)
	_light.shadow_enabled = false
	add_child(_light)
	_light.global_position = start + direction * length * 0.5 + Vector3.UP * 0.8

## Flames at the given points (already on the ground), lit one after another over `spread_time`
func lay_points(points: Array, spread_time: float) -> void:
	for i in points.size():
		var appears = spread_time * float(i) / max(points.size() - 1, 1)
		_points.append([points[i], appears])
		_flames.append(_make_flame(points[i]))

func _process(delta: float):
	_age += delta
	for i in _flames.size():
		var flame: Node3D = _flames[i]
		if is_instance_valid(flame) and not flame.visible and _age >= _points[i][1]:
			flame.visible = true
			flame.get_node("Flames").emitting = true
	if _dying:
		return
	if _age >= lifetime:
		_burn_out()
		return
	if _light:
		_light.light_energy = 1.4 + sin(_age * 17.0) * 0.25 + sin(_age * 7.0) * 0.15
	_tick_left -= delta
	if _tick_left <= 0.0 and tick_damage > 0.0:
		_tick_left += TICK
		_burn()

## Everyone standing in any lit patch takes one tick (once, however many patches they touch)
func _burn() -> void:
	for other in get_tree().get_nodes_in_group("entities"):
		if other == caster or not other is Node3D or not other.has_method("get_component"):
			continue
		var health = other.get_component("HealthComponent")
		if not health or health.is_dead:
			continue
		for p in _points:
			if _age < p[1]:
				continue
			var offset: Vector3 = other.global_position - p[0]
			if abs(offset.y) < 1.5 and Vector2(offset.x, offset.z).length() <= RADIUS:
				health.take_damage(tick_damage, caster if is_instance_valid(caster) else null)
				break

func _burn_out() -> void:
	if _dying:
		return
	_dying = true
	for flame in _flames:
		if is_instance_valid(flame):
			flame.get_node("Flames").emitting = false
	var tween = create_tween().set_parallel(true)
	for flame in _flames:
		if is_instance_valid(flame):
			tween.tween_property(flame.get_node("Scorch"), "transparency", 1.0, 0.9)
	if _light:
		tween.tween_property(_light, "light_energy", 0.0, 0.6)
	tween.chain().tween_callback(queue_free)

func _make_flame(point: Vector3) -> Node3D:
	var patch = Node3D.new()
	patch.visible = false
	add_child(patch)
	patch.global_position = point

	var scorch = MeshInstance3D.new()
	scorch.name = "Scorch"
	var plane = PlaneMesh.new()
	plane.size = Vector2(1.5, 1.5) * flame_scale
	scorch.mesh = plane
	scorch.material_override = _get_scorch_material()
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scorch.position = Vector3(0, 0.04, 0)
	scorch.rotation.y = randf() * TAU
	patch.add_child(scorch)

	var flames = GPUParticles3D.new()
	flames.name = "Flames"
	flames.amount = int(12 * flame_scale)
	flames.lifetime = 0.6
	flames.emitting = false
	flames.visibility_aabb = AABB(Vector3(-1, 0, -1) * flame_scale, Vector3(2, 2.5, 2) * flame_scale)
	var process = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35 * flame_scale
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0, 1.5, 0)
	process.scale_min = 0.6
	process.scale_max = 1.1
	var shrink = Curve.new()
	shrink.add_point(Vector2(0.0, 0.7))
	shrink.add_point(Vector2(0.25, 1.0))
	shrink.add_point(Vector2(1.0, 0.1))
	var shrink_tex = CurveTexture.new()
	shrink_tex.curve = shrink
	process.scale_curve = shrink_tex
	var ramp = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.82, 0.25, 0.95), Color(1.0, 0.4, 0.06, 0.85), Color(0.45, 0.07, 0.02, 0.0)])
	var ramp_tex = GradientTexture1D.new()
	ramp_tex.gradient = ramp
	process.color_ramp = ramp_tex
	flames.process_material = process
	var quad = QuadMesh.new()
	quad.size = Vector2(0.45, 0.45) * sqrt(flame_scale)
	quad.material = _get_flame_material()
	flames.draw_pass_1 = quad
	flames.position = Vector3(0, 0.1, 0)
	patch.add_child(flames)
	return patch

static func _soft_dot(inner: Color, outer: Color) -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.set_color(0, inner)
	gradient.set_color(1, outer)
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex

static func _get_flame_material() -> StandardMaterial3D:
	if not _flame_material:
		_flame_material = StandardMaterial3D.new()
		_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Plain alpha blending: additive flames washed out to white on the bright grass
		_flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_flame_material.vertex_color_use_as_albedo = true
		_flame_material.vertex_color_is_srgb = true  # the ramp colors are sRGB; read as linear they wash out
		_flame_material.albedo_texture = _soft_dot(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
		_flame_material.disable_receive_shadows = true
	return _flame_material

static func _get_scorch_material() -> StandardMaterial3D:
	if not _scorch_material:
		_scorch_material = StandardMaterial3D.new()
		_scorch_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_scorch_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_scorch_material.albedo_texture = _soft_dot(Color(1.0, 0.5, 0.12, 0.85), Color(0.25, 0.05, 0.0, 0.0))
		_scorch_material.disable_receive_shadows = true
	return _scorch_material
