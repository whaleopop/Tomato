## One meteor of a meteor shower (MapEvents): a red circle on the ground that fills up while the
## meteor comes, then the rock streaks in, bursts, the tiles jump and the spot keeps burning.
## The gameplay part of the impact (knockback, damage) is MapEvents.meteor_impact; the fire
## burns like Spicy Dash's (damage only counts on the server).
extends Node3D
class_name MeteorStrike

const FALL_TIME: float = 0.55
const FIRE_DAMAGE: float = 4.0       # per tick of the fire left behind

var events: MapEvents = null
var delay: float = 3.0               # seconds until it hits
var _t: float = 0.0
var _ring: MeshInstance3D = null
var _fill: MeshInstance3D = null
var _rock: Node3D = null
var _from: Vector3 = Vector3.ZERO
var _hit: bool = false

static var _ring_material: StandardMaterial3D = null
static var _fill_material: StandardMaterial3D = null

func _ready():
	add_to_group("map_markers")  # the minimap shows it
	set_meta("marker_color", Color(1.0, 0.25, 0.15))
	var r = MapEvents.METEOR_RADIUS
	_ring = _disc(r, _get_ring_material())
	_fill = _disc(r, _get_fill_material())
	_fill.scale = Vector3(0.05, 1.0, 0.05)

func _disc(radius: float, material: Material) -> MeshInstance3D:
	var disc = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	disc.mesh = quad
	disc.material_override = material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.06
	add_child(disc)
	return disc

func _process(delta: float):
	if _hit:
		return
	_t += delta
	var k = clamp(_t / delay, 0.0, 1.0)
	_fill.scale = Vector3(k, 1.0, k)
	_ring.transparency = 0.25 * (0.5 + 0.5 * sin(_t * (8.0 + 10.0 * k)))
	if not _rock and _t >= delay - FALL_TIME:
		_launch()
	if _rock:
		var f = clamp((_t - (delay - FALL_TIME)) / FALL_TIME, 0.0, 1.0)
		_rock.global_position = _from.lerp(global_position, f * f)
	if _t >= delay:
		_impact()

func _launch() -> void:
	_rock = Node3D.new()
	_rock.name = "Meteor"
	add_child(_rock)
	_from = global_position + Vector3(-6.0, 22.0, 4.0)
	_rock.global_position = _from
	var body = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 7
	sphere.rings = 4
	body.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.18, 0.14)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.1)
	mat.emission_energy_multiplier = 1.6
	body.material_override = mat
	_rock.add_child(body)
	var trail = GPUParticles3D.new()
	trail.amount = 48
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.visibility_aabb = AABB(Vector3(-12, -30, -12), Vector3(24, 40, 24))
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = (_from - global_position).normalized()
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3.ZERO
	var shrink = Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.1))
	var shrink_tex = CurveTexture.new()
	shrink_tex.curve = shrink
	pm.scale_curve = shrink_tex
	var ramp = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.9, 0.4, 1.0), Color(1.0, 0.42, 0.08, 0.85), Color(0.3, 0.1, 0.05, 0.0)])
	var ramp_tex = GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	trail.process_material = pm
	var quad = QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	quad.material = FireTrail._get_flame_material()
	trail.draw_pass_1 = quad
	_rock.add_child(trail)
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.light_energy = 2.5
	light.omni_range = 7.0
	light.shadow_enabled = false
	_rock.add_child(light)

func _impact() -> void:
	_hit = true
	remove_from_group("map_markers")
	var pos = global_position
	var parent = get_parent()
	LandingImpact.create_at(parent, pos, Color(1.0, 0.55, 0.25), 1.6)
	AbilityFX.splash(self, pos, Color(0.45, 0.3, 0.22), MapEvents.METEOR_RADIUS * 0.8)
	HexTile.shake_around(self, pos, 1.3, 2.0)
	if events and is_instance_valid(events):
		events.meteor_impact(pos)
	# The crater keeps burning for a while
	var fire = FireTrail.new()
	fire.name = "MeteorFire"
	fire.tick_damage = FIRE_DAMAGE
	fire.lifetime = MapEvents.METEOR_FIRE_TIME
	fire.flame_scale = 1.3
	parent.add_child(fire)
	fire.global_position = pos
	var points: Array = [pos]
	for i in 5:
		var a = TAU * i / 5.0 + randf() * 0.4
		points.append(pos + Vector3(cos(a), 0.0, sin(a)) * MapEvents.METEOR_RADIUS * 0.5)
	fire.lay_points(points, 0.25)
	for n in [_ring, _fill, _rock]:
		if n:
			n.visible = false
	get_tree().create_timer(0.8).timeout.connect(queue_free)

static func _get_ring_material() -> StandardMaterial3D:
	if not _ring_material:
		_ring_material = _decal_material([0.0, 0.8, 0.88, 1.0], [Color(1, 0.2, 0.1, 0.0), Color(1, 0.2, 0.1, 0.0), Color(1, 0.25, 0.12, 0.95), Color(1, 0.25, 0.12, 0.0)])
	return _ring_material

static func _get_fill_material() -> StandardMaterial3D:
	if not _fill_material:
		_fill_material = _decal_material([0.0, 0.85, 1.0], [Color(1, 0.15, 0.05, 0.28), Color(1, 0.2, 0.08, 0.42), Color(1, 0.2, 0.08, 0.0)])
	return _fill_material

static func _decal_material(offsets: Array, colors: Array) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_receive_shadows = true
	var g = Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var tex = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	mat.albedo_texture = tex
	return mat
