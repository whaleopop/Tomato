## A round cartoon tree in the forest (CoverSpawner, seeded like the walls): the trunk blocks
## walking, bullets and sight like a thin wall; the canopy is looks only and fades out around
## the local hero (global shader parameter "hero_position", set by the Player), so the top-down
## camera never loses you under the leaves. Some are fruit trees. Falls with its tile.
extends StaticBody3D
class_name GardenTree

const CANOPY_SHADER = preload("res://shaders/tree_canopy.gdshader")
const TRUNK_RADIUS: float = 0.22
const TRUNK_HEIGHT: float = 2.0

var tree_seed: int = 0
var _falling: bool = false

static var _trunk_material: StandardMaterial3D = null
static var _canopy_materials: Dictionary = {}

func _ready():
	collision_layer = HitscanSystem.LAYER_ENVIRONMENT | CoverSpawner.COVER_LAYER
	collision_mask = 0
	var rng = RandomNumberGenerator.new()
	rng.seed = tree_seed
	var size = rng.randf_range(0.85, 1.25)

	if not _trunk_material:
		_trunk_material = StandardMaterial3D.new()
		_trunk_material.albedo_color = Color(0.45, 0.32, 0.22)
		_trunk_material.roughness = 1.0
	var trunk = MeshInstance3D.new()
	var tm = CylinderMesh.new()
	tm.top_radius = TRUNK_RADIUS * 0.7
	tm.bottom_radius = TRUNK_RADIUS
	tm.height = TRUNK_HEIGHT * size
	tm.radial_segments = 7
	tm.rings = 1
	trunk.mesh = tm
	trunk.material_override = _trunk_material
	trunk.position.y = TRUNK_HEIGHT * size * 0.5
	add_child(trunk)

	# The canopy: a few overlapping low-poly balls in two greens
	var fruit = rng.randf() < 0.3
	var greens = [Color(0.3, 0.58, 0.22), Color(0.38, 0.66, 0.25), Color(0.25, 0.5, 0.2)]
	var base_y = TRUNK_HEIGHT * size * 0.85
	for i in rng.randi_range(3, 5):
		var ball = MeshInstance3D.new()
		var sm = SphereMesh.new()
		var r = rng.randf_range(0.7, 1.05) * size
		sm.radius = r
		sm.height = r * 1.8
		sm.radial_segments = 8
		sm.rings = 5
		ball.mesh = sm
		ball.material_override = _canopy(greens[i % greens.size()])
		var a = rng.randf() * TAU
		var off = 0.0 if i == 0 else rng.randf_range(0.4, 0.8) * size
		ball.position = Vector3(cos(a) * off, base_y + rng.randf_range(0.2, 0.9) * size, sin(a) * off)
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(ball)
	if fruit:
		var dots = [Color(0.9, 0.18, 0.15), Color(1.0, 0.6, 0.1)][rng.randi() % 2]
		for i in 7:
			var f = MeshInstance3D.new()
			var fm = SphereMesh.new()
			fm.radius = 0.1
			fm.height = 0.2
			fm.radial_segments = 6
			fm.rings = 3
			f.mesh = fm
			f.material_override = _canopy(dots)
			var a = rng.randf() * TAU
			var up = rng.randf_range(-0.3, 0.6)
			f.position = Vector3(cos(a) * 1.05 * size, base_y + 0.5 * size + up, sin(a) * 1.05 * size)
			add_child(f)

	var shape = CylinderShape3D.new()
	shape.radius = TRUNK_RADIUS + 0.05
	shape.height = TRUNK_HEIGHT * size
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = TRUNK_HEIGHT * size * 0.5
	add_child(col)

static func _canopy(color: Color) -> ShaderMaterial:
	var key = color.to_html()
	if not _canopy_materials.has(key):
		var m = ShaderMaterial.new()
		m.shader = CANOPY_SHADER
		m.set_shader_parameter("leaf_color", color)
		_canopy_materials[key] = m
	return _canopy_materials[key]

func attach_to(tile: HexTile) -> void:
	tile.tile_destroyed.connect(fall)
	tile.tree_exiting.connect(fall)

func fall():
	if _falling or not is_inside_tree() or is_queued_for_deletion():
		return
	_falling = true
	collision_layer = 0
	var t = create_tween().set_parallel()
	t.tween_property(self, "rotation:z", randf_range(1.2, 1.5) * (1.0 if randf() > 0.5 else -1.0), 0.8).set_ease(Tween.EASE_IN)
	t.tween_property(self, "position:y", position.y - 5.0, 1.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.chain().tween_callback(queue_free)
