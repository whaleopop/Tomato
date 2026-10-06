## Landmarks: big garden things with a name that hold most of the loot (a few chests around each,
## the rich ones at the greenhouse and the windmill) - somewhere worth landing, fighting over or
## avoiding. plan() picks the spots from the map and the seed only, so LootSpawner (the chests)
## and CoverSpawner (the buildings, walls and bushes kept off them) agree on every peer.
## A landmark blocks walking and bullets like a wall; opaque ones also block sight (the
## greenhouse glass doesn't). It stands on its tile and falls with it (zone, flood).
extends StaticBody3D
class_name Landmark

enum Kind { WATERING_CAN, SCARECROW, GREENHOUSE, WINDMILL, COMPOST }

const NAMES = ["Giant Watering Can", "Scarecrow Hill", "Greenhouse", "Old Windmill", "Compost Heap"]
const CHESTS = [3, 2, 3, 3, 2]            # containers around it (the greenhouse has one inside)
const RICH = [false, false, true, true, false]
const COLORS = [Color(0.4, 0.85, 0.65), Color(1.0, 0.7, 0.3), Color(0.6, 0.95, 1.0), Color(1.0, 0.9, 0.55), Color(0.75, 0.55, 0.35)]
const SPACING: int = 6                    # hexes between landmarks
const EDGE_MARGIN: int = 3                # hexes from the rim

var kind: int = Kind.WATERING_CAN
var coords: Vector2i = Vector2i.ZERO
var _spin: Node3D = null                  # the windmill's sails
var _falling: bool = false
const NAME_NEAR: float = 14.0    # the sign starts to fade this close
const NAME_LINGER: float = 4.0   # seconds it stays after that
var _name_label: Label3D = null
var _name_near: float = -1.0     # seconds since the hero first came near (-1: not yet)
var _name_check: float = 0.0
var _name_done: bool = false

# ---------------------------------------------------------------- where

## [{kind, coords, chests: [Vector2i]}] for this map and seed. Pure: no nodes, own RNG, sorted order.
static func plan(grid: HexGrid, seed_value: int) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 424242
	var radius = grid.grid_radius
	var huts: Array = grid.get_meta("huts", [])
	var keys: Array = grid.tiles.keys()
	keys.sort()
	var candidates: Array = []
	for c in keys:
		if _dist(c, Vector2i.ZERO) > radius - EDGE_MARGIN or not _ground(grid.get_tile(c)):
			continue
		var near_hut = false
		for h in huts:
			if _dist(c, h) < 2:
				near_hut = true
		if near_hut or _spots(grid, c).size() < 3:
			continue
		candidates.append(c)

	var count = clampi(int(round(radius * 0.4)), 3, 8)
	var kinds: Array = [Kind.WINDMILL, Kind.GREENHOUSE, Kind.WATERING_CAN, Kind.SCARECROW, Kind.COMPOST]
	var extra: Array = [Kind.WATERING_CAN, Kind.COMPOST, Kind.GREENHOUSE, Kind.SCARECROW]
	while kinds.size() < count:
		kinds.append(extra[rng.randi() % extra.size()])
	kinds.resize(count)

	var result: Array = []
	for k in kinds:
		var pool: Array = []
		for c in candidates:
			var free = true
			for r in result:
				if _dist(c, r.coords) < SPACING:
					free = false
			if free:
				pool.append(c)
		if pool.is_empty():
			break
		# The windmill wants the highest ground, the scarecrow a hill
		if k == Kind.WINDMILL or k == Kind.SCARECROW:
			var best = 0
			for c in pool:
				best = maxi(best, grid.get_tile(c).level)
			var want = best if k == Kind.WINDMILL else mini(best, 1)
			pool = pool.filter(func(c): return grid.get_tile(c).level >= want)
		var at: Vector2i = pool[rng.randi() % pool.size()]
		var spots = _spots(grid, at)
		var chests: Array = []
		if k == Kind.GREENHOUSE:
			chests.append(at)  # inside
		while chests.size() < CHESTS[k] and not spots.is_empty():
			chests.append(spots.pop_at(rng.randi() % spots.size()))
		result.append({"kind": k, "coords": at, "chests": chests})
	return result

## Tiles taken by landmarks and their chests (no stray loot, walls or bushes there)
static func footprint(entries: Array) -> Dictionary:
	var taken := {}
	for e in entries:
		taken[e.coords] = true
		for c in e.chests:
			taken[c] = true
	return taken

static func _ground(tile: HexTile) -> bool:
	return tile != null and tile.is_playable() and not tile.is_water() and not tile.is_ramp() \
		and tile.biome_type != HexTile.BiomeType.THORNS

## Neighbours on the same level that can hold a chest
static func _spots(grid: HexGrid, c: Vector2i) -> Array:
	var level = grid.get_tile(c).level
	var spots: Array = []
	for d in HexTile.EDGE_DIRECTIONS:
		var n = grid.get_tile(c + d)
		if _ground(n) and n.level == level:
			spots.append(c + d)
	return spots

static func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(maxi(abs(a.x - b.x), abs(a.y - b.y)), abs(a.x + a.y - b.x - b.y))

# ---------------------------------------------------------------- building

## Stand on `tile` (its top), fall with it
func place(tile: HexTile, grid: HexGrid) -> void:
	coords = tile.hex_coords
	position = grid.hex_to_world(coords) + Vector3(0, CoverSpawner.tile_top(tile), 0)
	name = "Landmark_%d_%d" % [coords.x, coords.y]
	tile.tile_destroyed.connect(fall)
	tile.tree_exiting.connect(fall)

func _ready():
	collision_layer = HitscanSystem.LAYER_ENVIRONMENT | (0 if kind == Kind.GREENHOUSE else CoverSpawner.COVER_LAYER)
	collision_mask = 0
	add_to_group("map_landmarks")
	set_meta("marker_color", COLORS[kind])
	match kind:
		Kind.WATERING_CAN:
			_build_watering_can()
		Kind.SCARECROW:
			_build_scarecrow()
		Kind.GREENHOUSE:
			_build_greenhouse()
		Kind.WINDMILL:
			_build_windmill()
		Kind.COMPOST:
			_build_compost()
	_add_name()

func _process(delta: float):
	if _spin:
		_spin.rotate_z(delta * 0.8)
	_fade_name(delta)

func fall():
	if _falling or not is_inside_tree() or is_queued_for_deletion():
		return
	_falling = true
	collision_layer = 0
	remove_from_group("map_landmarks")
	var t = create_tween()
	t.tween_property(self, "position:y", position.y - 8.0, 1.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(queue_free)

## The name floats above it, like a sign
func _add_name():
	var label = Label3D.new()
	label.text = NAMES[kind]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.0065
	label.outline_size = 14
	label.modulate = COLORS[kind].lightened(0.3)
	label.outline_modulate = Color(0.05, 0.06, 0.1, 0.85)
	label.font = UITheme.font_black()
	label.position.y = [3.4, 4.2, 3.6, 7.8, 2.6][kind]
	label.no_depth_test = false
	add_child(label)
	_name_label = label

## The sign fades out a few seconds after the local hero first comes near
func _fade_name(delta: float) -> void:
	if _name_label == null or _name_done:
		return
	_name_check -= delta
	if _name_check > 0.0 and _name_near < 0.0:
		return
	if _name_near < 0.0:
		_name_check = 0.5
		for p in get_tree().get_nodes_in_group("players"):
			if p is Player and p.is_local_player and p.global_position.distance_to(global_position) < NAME_NEAR:
				_name_near = 0.0
				break
		return
	_name_near += delta
	if _name_near > NAME_LINGER:
		_name_done = true
		var t = create_tween()
		t.tween_property(_name_label, "modulate:a", 0.0, 1.0)
		t.tween_callback(_name_label.queue_free)

# ---------------------------------------------------------------- parts

static var _materials: Dictionary = {}

static func _mat(color: Color, metal: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var key = "%s|%.2f|%.2f" % [color.to_html(), metal, alpha]
	if not _materials.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(color, alpha)
		m.metallic = metal
		m.roughness = 0.35 if metal > 0.0 else 0.85
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.1
			m.metallic_specular = 0.9
		_materials[key] = m
	return _materials[key]

func _part(mesh: Mesh, material: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var m = MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	m.rotation = rot
	(parent if parent else self).add_child(m)
	return m

func _collide(shape: Shape3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var c = CollisionShape3D.new()
	c.shape = shape
	c.position = pos
	c.rotation = rot
	add_child(c)

static func _cyl(top: float, bottom: float, height: float, sides: int = 12) -> CylinderMesh:
	var m = CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return m

static func _box(size: Vector3) -> BoxMesh:
	var m = BoxMesh.new()
	m.size = size
	return m

static func _ball(radius: float, squash: float = 1.0, sides: int = 12) -> SphereMesh:
	var m = SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * squash
	m.radial_segments = sides
	m.rings = maxi(4, sides / 2)
	return m

## A tipped-over watering can, big enough to hide behind; the spout points at the sky
func _build_watering_can():
	rotation.y = float(coords.x * 7 + coords.y * 13) * 0.37
	var green = _mat(Color(0.25, 0.58, 0.45), 0.45)
	var dark = _mat(Color(0.17, 0.4, 0.32), 0.45)
	_part(_cyl(1.05, 1.05, 2.4, 16), green, Vector3(0, 1.05, 0), Vector3(0, 0, PI / 2))
	_part(_cyl(1.08, 1.08, 0.12, 16), dark, Vector3(1.2, 1.05, 0), Vector3(0, 0, PI / 2))
	_part(_cyl(1.08, 1.08, 0.12, 16), dark, Vector3(-1.2, 1.05, 0), Vector3(0, 0, PI / 2))
	_part(_cyl(0.1, 0.2, 2.4, 8), green, Vector3(1.9, 1.9, 0), Vector3(0, 0, -0.75))
	_part(_cyl(0.42, 0.12, 0.35, 12), dark, Vector3(2.75, 2.8, 0), Vector3(0, 0, -0.75))
	_part(_box(Vector3(1.4, 0.16, 0.2)), dark, Vector3(-0.2, 2.3, 0))
	_part(_box(Vector3(0.16, 0.5, 0.2)), dark, Vector3(-0.85, 2.05, 0))
	_part(_box(Vector3(0.16, 0.5, 0.2)), dark, Vector3(0.45, 2.05, 0))
	# A puddle where it spilled
	var puddle = _part(_cyl(1.3, 1.3, 0.02, 20), _mat(Color(0.35, 0.6, 0.85), 0.2, 0.7), Vector3(1.6, 0.02, 0.4))
	puddle.scale = Vector3(1.0, 1.0, 0.7)
	var shape = CylinderShape3D.new()
	shape.radius = 1.05
	shape.height = 2.4
	_collide(shape, Vector3(0, 1.05, 0), Vector3(0, 0, PI / 2))

## A pole with a crossbar, a plaid shirt, a pumpkin head and a straw hat
func _build_scarecrow():
	var wood = _mat(Color(0.5, 0.36, 0.22))
	_part(_cyl(0.09, 0.11, 3.2, 8), wood, Vector3(0, 1.6, 0))
	_part(_cyl(0.07, 0.07, 2.4, 8), wood, Vector3(0, 2.25, 0), Vector3(0, 0, PI / 2))
	_part(_box(Vector3(0.9, 1.0, 0.4)), _mat(Color(0.75, 0.2, 0.18)), Vector3(0, 1.85, 0))
	_part(_box(Vector3(0.92, 0.12, 0.42)), _mat(Color(0.25, 0.18, 0.12)), Vector3(0, 1.5, 0))
	for side in [-1, 1]:
		_part(_box(Vector3(0.7, 0.3, 0.3)), _mat(Color(0.7, 0.18, 0.16)), Vector3(side * 0.75, 2.25, 0))
		_part(_cyl(0.02, 0.12, 0.3, 6), _mat(Color(0.9, 0.78, 0.4)), Vector3(side * 1.2, 2.25, 0), Vector3(0, 0, -side * PI / 2))
	var head = _part(_ball(0.42, 0.85, 14), _mat(Color(0.95, 0.55, 0.15)), Vector3(0, 2.75, 0))
	head.scale = Vector3(1.15, 1.0, 1.0)
	_part(_cyl(0.04, 0.06, 0.25, 6), _mat(Color(0.3, 0.45, 0.15)), Vector3(0, 3.15, 0))
	_part(_cyl(0.72, 0.72, 0.05, 16), _mat(Color(0.9, 0.78, 0.42)), Vector3(0, 3.08, 0))
	_part(_cyl(0.28, 0.36, 0.35, 12), _mat(Color(0.88, 0.75, 0.38)), Vector3(0, 3.25, 0))
	for side in [-1, 1]:
		_part(_box(Vector3(0.1, 0.1, 0.05)), _mat(Color(0.1, 0.06, 0.02)), Vector3(side * 0.15, 2.82, 0.38))
	# A few crows on the crossbar
	for i in 2:
		var crow = Node3D.new()
		crow.position = Vector3(-0.9 + i * 1.75, 2.45, 0)
		add_child(crow)
		_part(_ball(0.13, 1.1, 8), _mat(Color(0.08, 0.08, 0.1)), Vector3.ZERO, Vector3.ZERO, crow)
		_part(_cyl(0.0, 0.05, 0.14, 6), _mat(Color(0.9, 0.7, 0.2)), Vector3(0, 0.03, 0.15), Vector3(PI / 2, 0, 0), crow)
	var shape = CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 3.2
	_collide(shape, Vector3(0, 1.6, 0))

## Glass walls on a white frame, a doorway in front, seedlings inside. The glass stops bullets
## and feet, not eyes (environment layer only).
func _build_greenhouse():
	rotation.y = (coords.x + coords.y * 3) % 6 * PI / 3.0
	var frame = _mat(Color(0.92, 0.94, 0.95))
	var glass = _mat(Color(0.7, 0.9, 1.0), 0.1, 0.28)
	var w = 3.2
	var d = 2.5
	var h = 1.9
	for x in [-w / 2, w / 2]:
		for z in [-d / 2, d / 2]:
			_part(_box(Vector3(0.1, h, 0.1)), frame, Vector3(x, h / 2, z))
	# Walls: back, sides, and the front around a doorway
	var panels = [
		[Vector3(0, h / 2, -d / 2), Vector3(w, h, 0.05)],
		[Vector3(-w / 2, h / 2, 0), Vector3(0.05, h, d)],
		[Vector3(w / 2, h / 2, 0), Vector3(0.05, h, d)],
		[Vector3(-w / 2 + 0.5, h / 2, d / 2), Vector3(1.0, h, 0.05)],
		[Vector3(w / 2 - 0.5, h / 2, d / 2), Vector3(1.0, h, 0.05)],
	]
	for p in panels:
		_part(_box(p[1]), glass, p[0])
		var shape = BoxShape3D.new()
		shape.size = p[1] + Vector3(0.04, 0, 0.04)
		_collide(shape, p[0])
	_part(_box(Vector3(w, 0.1, 0.1)), frame, Vector3(0, h, d / 2))
	_part(_box(Vector3(w, 0.1, 0.1)), frame, Vector3(0, h, -d / 2))
	# Gable roof: two glass slopes and a ridge
	for side in [-1, 1]:
		_part(_box(Vector3(w + 0.1, 0.05, d * 0.58)), glass, Vector3(0, h + 0.38, side * d * 0.25), Vector3(side * 0.55, 0, 0))
	_part(_box(Vector3(w + 0.1, 0.1, 0.1)), frame, Vector3(0, h + 0.72, 0))
	# Seedling beds along the back
	var soil = _mat(Color(0.35, 0.24, 0.16))
	var leaf = _mat(Color(0.35, 0.72, 0.3))
	_part(_box(Vector3(w - 0.4, 0.3, 0.5)), soil, Vector3(0, 0.15, -d / 2 + 0.4))
	for i in 7:
		_part(_ball(0.14, 1.2, 6), leaf, Vector3(-w / 2 + 0.45 + i * 0.38, 0.38, -d / 2 + 0.4))

## A stone tower with a red cap and turning sails: seen from half the map
func _build_windmill():
	var stone = _mat(Color(0.85, 0.8, 0.68))
	var roof = _mat(Color(0.62, 0.25, 0.18))
	var wood = _mat(Color(0.45, 0.32, 0.2))
	_part(_cyl(0.95, 1.4, 5.2, 12), stone, Vector3(0, 2.6, 0))
	_part(_cyl(0.0, 1.2, 1.4, 12), roof, Vector3(0, 5.9, 0))
	_part(_box(Vector3(0.7, 1.1, 0.1)), wood, Vector3(0, 0.55, 1.36), Vector3(-0.08, 0, 0))
	for y in [2.2, 3.8]:
		_part(_box(Vector3(0.4, 0.5, 0.08)), _mat(Color(0.25, 0.35, 0.5)), Vector3(0, y, 1.17 - (y - 2.2) * 0.08), Vector3(-0.08, 0, 0))
	_spin = Node3D.new()
	_spin.position = Vector3(0, 4.9, 1.25)
	add_child(_spin)
	_part(_cyl(0.18, 0.18, 0.4, 8), wood, Vector3.ZERO, Vector3(PI / 2, 0, 0), _spin)
	var sail = _mat(Color(0.95, 0.93, 0.86))
	for i in 4:
		var arm = Node3D.new()
		arm.rotation.z = i * PI / 2
		_spin.add_child(arm)
		_part(_box(Vector3(0.12, 2.6, 0.06)), wood, Vector3(0, 1.35, 0.1), Vector3.ZERO, arm)
		_part(_box(Vector3(0.6, 2.0, 0.03)), sail, Vector3(0.36, 1.55, 0.12), Vector3.ZERO, arm)
	var shape = CylinderShape3D.new()
	shape.radius = 1.3
	shape.height = 5.2
	_collide(shape, Vector3(0, 2.6, 0))

## A steaming mound of peels in a little fence
func _build_compost():
	var heap = _part(_ball(1.25, 0.6, 14), _mat(Color(0.38, 0.26, 0.16)), Vector3(0, 0.1, 0))
	heap.scale = Vector3(1.0, 1.0, 0.9)
	var bits = [Color(0.95, 0.55, 0.15), Color(0.85, 0.2, 0.2), Color(0.45, 0.7, 0.25), Color(0.95, 0.85, 0.3)]
	for i in 9:
		var a = i * 2.4
		var r = 0.35 + (i % 3) * 0.3
		_part(_box(Vector3(0.22, 0.08, 0.12)), _mat(bits[i % bits.size()]), Vector3(cos(a) * r, 0.62 - r * 0.25, sin(a) * r), Vector3(0.3, a, 0.2))
	var wood = _mat(Color(0.52, 0.38, 0.24))
	for i in 8:
		var a = i * TAU / 8.0
		if i == 2:
			continue  # the way in
		_part(_box(Vector3(0.1, 0.7, 0.1)), wood, Vector3(cos(a) * 1.55, 0.35, sin(a) * 1.55))
		var b = a + TAU / 16.0
		_part(_box(Vector3(1.15, 0.12, 0.05)), wood, Vector3(cos(b) * 1.45, 0.45, sin(b) * 1.45), Vector3(0, -b + PI / 2, 0))
	var steam = GPUParticles3D.new()
	steam.amount = 10
	steam.lifetime = 3.0
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0.1, 0.05, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.color = Color(0.9, 0.9, 0.85, 0.35)
	steam.process_material = pm
	var quad = QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	var qm = StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = FireTrail._soft_dot(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	quad.material = qm
	steam.draw_pass_1 = quad
	steam.position.y = 0.7
	add_child(steam)
	var shape = CylinderShape3D.new()
	shape.radius = 1.15
	shape.height = 0.8
	_collide(shape, Vector3(0, 0.4, 0))
