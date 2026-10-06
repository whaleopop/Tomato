## The landing map as a small 3D diorama: every tile a column at its real height (terraces, ramps,
## lakes below their banks, the rim mountains), trees and rocks, landmarks with their names, all on a
## wooden plinth. Same interface as HexMapView (tiles / reserved / selected, hex_clicked / hex_hovered),
## so SpawnSelectMenu drives both. Own World3D, like CharacterShowcase.
## Drag to turn, right / middle drag to move, wheel to zoom, double click to reset, click to pick.
extends HiResView
class_name HexMap3DView

signal hex_clicked(coords: Vector2i)
signal hex_hovered(coords: Vector2i)

const INVALID = Vector2i(-9999, -9999)
const SQRT3 = 1.7320508

const R: float = HexTile.HEX_RADIUS
const GAP: float = 0.95            # tile tops a bit smaller than the tile: the grid reads
const H_SCALE: float = 1.35         # heights a little exaggerated, so the relief reads from above
const BASE_Y: float = -1.4          # every column reaches down to the plinth
const MOUNTAIN_PEAK: float = 2.4    # rim mountains, lower than in the game so they don't hide the edge
const PITCH_MIN: float = 0.35
const PITCH_MAX: float = 1.45
const CLICK_SLOP: float = 6.0       # px: a press that moved less is a click, not a drag

const SOIL = Color("5b4636")
const WOOD = Color("8a5a36")

var tiles: Dictionary = {}     # Vector2i -> {biome, height, level, ramp, spawnable, landmark}
var reserved: Dictionary = {}  # Vector2i -> true
var selected: Vector2i = INVALID
var hovered: Vector2i = INVALID
var accent: Color = Color(0.52, 0.91, 0.42)


var camera: Camera3D
var _island: Node3D           # rebuilt by set_tiles
var _reserved_node: Node3D    # rebuilt by set_reserved
var _hover_ring: MeshInstance3D
var _pin: Node3D
var _pin_head: MeshInstance3D
var _pin_beam: MeshInstance3D
var _landmark_gems: Array = []

var _target: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.95
var _dist: float = 100.0
var _goal_target: Vector3 = Vector3.ZERO
var _goal_yaw: float = 0.0
var _goal_pitch: float = 0.95
var _goal_dist: float = 100.0
var _fit_dist: float = 100.0
var _island_radius: float = 50.0
var _time: float = 0.0

var _press_button: int = 0
var _press_pos: Vector2 = Vector2.ZERO
var _dragged: bool = false

func _init():
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

	var env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.72, 0.9)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.6
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	sun.shadow_blur = 1.5
	viewport.add_child(sun)

	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.75, 1.0)
	viewport.add_child(fill)

	camera = Camera3D.new()
	camera.fov = 34.0
	camera.near = 0.5
	camera.far = 2000.0
	viewport.add_child(camera)

	_hover_ring = MeshInstance3D.new()
	_hover_ring.mesh = _ring_mesh(R * 1.02, R * 0.84)
	_hover_ring.material_override = _glow_material(Color(1, 1, 1, 0.9))
	_hover_ring.visible = false
	viewport.add_child(_hover_ring)

	_pin = Node3D.new()
	_pin.visible = false
	viewport.add_child(_pin)
	var cap = MeshInstance3D.new()
	cap.mesh = _ring_mesh(R * 1.05, R * 0.0)
	cap.material_override = _glow_material(Color(accent, 0.85))
	_pin.add_child(cap)
	_pin_beam = MeshInstance3D.new()
	var beam = CylinderMesh.new()
	beam.top_radius = 0.35
	beam.bottom_radius = 0.7
	beam.height = 14.0
	beam.radial_segments = 12
	_pin_beam.mesh = beam
	_pin_beam.position.y = 7.0
	_pin_beam.material_override = _glow_material(Color(accent, 0.28))
	_pin.add_child(_pin_beam)
	_pin_head = MeshInstance3D.new()
	var head = CylinderMesh.new()  # an upside-down cone: "you land here"
	head.top_radius = 1.7
	head.bottom_radius = 0.0
	head.height = 3.2
	head.radial_segments = 6
	_pin_head.mesh = head
	var head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = accent
	head_mat.emission_enabled = true
	head_mat.emission = accent
	head_mat.emission_energy_multiplier = 1.2
	_pin_head.material_override = head_mat
	_pin.add_child(_pin_head)

func _ready():
	resized.connect(_update_fit)

func _process(delta: float):
	_time += delta
	var k = 1.0 - exp(-delta * 10.0)
	_yaw = lerp_angle(_yaw, _goal_yaw, k)
	_pitch = lerp(_pitch, _goal_pitch, k)
	_dist = lerp(_dist, _goal_dist, k)
	_target = _target.lerp(_goal_target, k)
	_place_camera()

	if _pin.visible:
		var bob = sin(_time * 3.0)
		_pin_head.position.y = 5.0 + bob * 0.6
		_pin_head.rotation.y = _time * 1.5
		(_pin_beam.material_override as StandardMaterial3D).albedo_color.a = 0.35 + 0.15 * (0.5 + 0.5 * bob)
	for gem in _landmark_gems:
		if is_instance_valid(gem):
			gem.rotation.y = _time * 0.8

func _place_camera():
	var offset = Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	camera.position = _target + offset
	camera.look_at(_target, Vector3.UP)

# ---------------------------------------------------------------- HexMapView's interface

func set_tiles(data: Dictionary):
	tiles = data
	_build_island()
	_update_fit()
	reset_view()
	set_reserved(reserved.keys())
	set_selected(selected)

func set_reserved(coords_list: Array):
	reserved.clear()
	for c in coords_list:
		reserved[c] = true
	if is_instance_valid(_reserved_node):
		_reserved_node.queue_free()
	_reserved_node = Node3D.new()
	viewport.add_child(_reserved_node)
	var mat = _glow_material(Color(1.0, 0.38, 0.40, 0.8))
	var flag_mat = _glow_material(Color(1.0, 0.38, 0.40, 0.55))
	for c in reserved.keys():
		if not tiles.has(c):
			continue
		var cap = MeshInstance3D.new()
		cap.mesh = _ring_mesh(R * GAP, 0.0)
		cap.material_override = mat
		cap.position = _surface(c) + Vector3(0, 0.08, 0)
		_reserved_node.add_child(cap)
		var post = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 5.0
		cyl.radial_segments = 8
		post.mesh = cyl
		post.material_override = flag_mat
		post.position = cap.position + Vector3(0, 2.5, 0)
		_reserved_node.add_child(post)

func set_selected(coords: Vector2i):
	selected = coords
	_pin.visible = coords != INVALID and tiles.has(coords)
	if _pin.visible:
		_pin.position = _surface(coords) + Vector3(0, 0.1, 0)

func is_selectable(coords: Vector2i) -> bool:
	if not tiles.has(coords) or reserved.has(coords):
		return false
	var t = tiles[coords]
	return t.get("spawnable", t.get("biome", 0) != 4)

func reset_view():
	_goal_target = Vector3.ZERO
	_goal_yaw = 0.0
	_goal_pitch = 0.95
	_goal_dist = _fit_dist

# ---------------------------------------------------------------- geometry

static func hex_to_world(c: Vector2i) -> Vector3:
	return Vector3(SQRT3 * R * (c.x + c.y * 0.5), 0.0, 1.5 * R * c.y)

static func world_to_hex(x: float, z: float) -> Vector2i:
	var qf = (SQRT3 / 3.0 * x - 1.0 / 3.0 * z) / R
	var rf = (2.0 / 3.0 * z) / R
	var sf = -qf - rf
	var q = round(qf)
	var r = round(rf)
	var s = round(sf)
	var dq = abs(q - qf)
	var dr = abs(r - rf)
	var ds = abs(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))

## World y of the tile's flat top (as HexTile: height in HEX_HEIGHT units, top half a slab up)
func _top_y(t: Dictionary) -> float:
	var h: float = float(t.get("height", 0.0))
	return (h * HexTile.HEX_HEIGHT + HexTile.HEX_HEIGHT * 0.5) * H_SCALE

func _is_ramp(t: Dictionary) -> bool:
	return int(t.get("ramp", -1)) >= 0

## Middle of the walkable top (ramps: half a step up)
func _surface(c: Vector2i) -> Vector3:
	var t: Dictionary = tiles[c]
	var y = _top_y(t) + (HexTile.TERRACE_STEP * 0.5 * H_SCALE if _is_ramp(t) else 0.0)
	return hex_to_world(c) + Vector3(0, y, 0)

## Highest point of the tile (for picking): mountains count their peak
func _pick_top(c: Vector2i) -> float:
	var t: Dictionary = tiles[c]
	var y = _top_y(t)
	if int(t.get("biome", 0)) == HexTile.BiomeType.MOUNTAIN:
		return y + MOUNTAIN_PEAK
	if _is_ramp(t):
		return y + HexTile.TERRACE_STEP * H_SCALE * 0.5
	return y

## Top corner i (60 * i + 30 degrees) of a tile, ramps lifted like HexTile._corner_lift
func _corner(c: Vector2i, t: Dictionary, i: int, radius: float) -> Vector3:
	var angle = deg_to_rad(60.0 * i + 30.0)
	var lift = 0.0
	var dir = int(t.get("ramp", -1))
	if dir >= 0:
		var along = cos(deg_to_rad(60.0 * i + 30.0 - 60.0 * dir)) * HexTile.HEX_RADIUS / HexTile.HEX_INNER_RADIUS
		lift = HexTile.TERRACE_STEP * H_SCALE * clamp((along + 1.0) * 0.5, 0.0, 1.0)
	return hex_to_world(c) + Vector3(cos(angle) * radius, _top_y(t) + lift, sin(angle) * radius)

## One triangle facing `out` (Godot's front faces are clockwise, so the winding is fixed here)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, color: Color):
	var n = (b - a).cross(c - a)
	if n.dot(out) > 0.0:
		var tmp = b
		b = c
		c = tmp
		n = -n
	var normal = -n.normalized()
	for v in [a, b, c]:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(v)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, b_low: Vector3, a_low: Vector3, out: Vector3, color: Color):
	_tri(st, a, b, b_low, out, color)
	_tri(st, a, b_low, a_low, out, color)

func _tile_color(t: Dictionary) -> Color:
	var biome = int(t.get("biome", 0))
	var color: Color = HexMapView.BIOME_COLORS.get(biome, Color(0.5, 0.5, 0.5))
	var level = int(t.get("level", 0))
	if level > 0:
		color = color.lightened(0.05 * level)
	var landlike = biome != 4 and biome != 5 and biome != HexTile.BiomeType.MOUNTAIN
	if landlike and not t.get("spawnable", true):
		color = color.darkened(0.3)
	return color

# ---------------------------------------------------------------- building the diorama

func _build_island():
	_landmark_gems.clear()
	if is_instance_valid(_island):
		_island.queue_free()
	_island = Node3D.new()
	viewport.add_child(_island)
	if tiles.is_empty():
		return

	var land = SurfaceTool.new()
	land.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water = SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trees: Array = []   # Transform3D, Color
	var rocks: Array = []
	var ring = 0
	_island_radius = 0.0

	for c in tiles.keys():
		var t: Dictionary = tiles[c]
		var biome = int(t.get("biome", 0))
		var center = hex_to_world(c)
		ring = max(ring, (abs(c.x) + abs(c.y) + abs(c.x + c.y)) / 2)
		_island_radius = max(_island_radius, center.length() + R)
		var color = _tile_color(t)
		var is_water = biome == 4 or biome == 5
		var st = water if is_water else land
		var side = color.darkened(0.25).lerp(Color("3d5f8a") if is_water else SOIL, 0.55)

		var top: Array = []
		for i in 6:
			top.append(_corner(c, t, i, R * GAP))
		var mid = (top[0] + top[3]) * 0.5
		var up = Vector3.UP
		for i in range(1, 5):
			_tri(st, top[0], top[i], top[i + 1], up, color)
		for i in 6:
			var a: Vector3 = top[i]
			var b: Vector3 = top[(i + 1) % 6]
			var out = Vector3((a + b).x * 0.5 - center.x, 0, (a + b).z * 0.5 - center.z).normalized()
			# The upper band keeps the ground's color (a grass lip over the cliff), then soil
			var lip = min(0.35, a.y - BASE_Y)
			var a_mid = Vector3(a.x, a.y - lip, a.z)
			var b_mid = Vector3(b.x, b.y - lip, b.z)
			_quad(st, a, b, b_mid, a_mid, out, color.darkened(0.12))
			_quad(st, a_mid, b_mid, Vector3(b.x, BASE_Y, b.z), Vector3(a.x, BASE_Y, a.z), out, side)

		if biome == HexTile.BiomeType.MOUNTAIN:
			_build_mountain(land, c, top, mid)

		var rng = RandomNumberGenerator.new()
		rng.seed = hash(c)
		if biome == 1 or biome == 10:  # forest, frost: little firs
			for n in rng.randi_range(2, 3):
				var p = mid + Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(-0.9, 0.9))
				var s = rng.randf_range(0.8, 1.2)
				var tint = Color("2c6b3c") if biome == 1 else Color("d8eef5")
				trees.append([Transform3D(Basis().scaled(Vector3(s, s, s)), p), tint.darkened(rng.randf_range(0.0, 0.15))])
		elif biome == 3 or biome == 13 or (biome == 0 and rng.randf() < 0.12):
			for n in rng.randi_range(1, 2):
				var p = mid + Vector3(rng.randf_range(-0.9, 0.9), 0.1, rng.randf_range(-0.9, 0.9))
				var s = rng.randf_range(0.35, 0.7)
				rocks.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.7, s)), p), Color("8c8a92").darkened(rng.randf_range(0.0, 0.2))])
		elif biome == 12:  # mushroom grove: a big cap or two
			for n in rng.randi_range(1, 2):
				var p = mid + Vector3(rng.randf_range(-0.8, 0.8), 0.25, rng.randf_range(-0.8, 0.8))
				var s = rng.randf_range(0.5, 0.8)
				rocks.append([Transform3D(Basis().scaled(Vector3(s, s * 0.5, s)), p), Color("b765c9")])

	var land_mesh = MeshInstance3D.new()
	land_mesh.mesh = land.commit()
	land_mesh.material_override = _vertex_material(0.9, 0.0)
	_island.add_child(land_mesh)

	var water_mesh = MeshInstance3D.new()
	water_mesh.mesh = water.commit()
	water_mesh.material_override = _vertex_material(0.3, 0.3)
	_island.add_child(water_mesh)

	_island.add_child(_build_plinth(ring))
	_island.add_child(_scatter(trees, _tree_mesh()))
	_island.add_child(_scatter(rocks, _rock_mesh()))
	_build_landmarks()

## A rocky cone on the rim tile, snow at the peak
func _build_mountain(st: SurfaceTool, c: Vector2i, base: Array, mid: Vector3):
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(c) + 7
	var peak_h = MOUNTAIN_PEAK * rng.randf_range(0.75, 1.1)
	var shift = Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	var upper: Array = []
	for i in 6:
		var p: Vector3 = base[i]
		upper.append(mid + shift + (p - mid) * 0.35 + Vector3(0, peak_h * 0.8, 0))
	var peak = mid + shift + Vector3(0, peak_h, 0)
	var rock = Color("6d6774")
	var snow = Color("eef2f7")
	for i in 6:
		var a: Vector3 = base[i]
		var b: Vector3 = base[(i + 1) % 6]
		var a2: Vector3 = upper[i]
		var b2: Vector3 = upper[(i + 1) % 6]
		var out = ((a + b) * 0.5 - mid).normalized() + Vector3.UP * 0.6
		_quad(st, a2, b2, b, a, out, rock.darkened(0.08 * (i % 2)))
		_tri(st, a2, b2, peak, (a2 + b2) * 0.5 - mid + Vector3.UP, snow)

## The wooden board the island stands on: a soil slab and a wider wooden base
func _build_plinth(ring: int) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var soil_r = ring * SQRT3 * R + R * 1.6
	_slab(st, soil_r, BASE_Y + 0.01, BASE_Y - 1.4, SOIL.darkened(0.35), SOIL)
	_slab(st, soil_r + R * 1.2, BASE_Y - 1.4, BASE_Y - 2.6, WOOD, WOOD.darkened(0.25))
	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = _vertex_material(0.85, 0.0)
	return mesh

## A flat-topped hexagon (corners at 60 * i: the island's own outline)
func _slab(st: SurfaceTool, radius: float, top_y: float, bottom_y: float, top_color: Color, side_color: Color):
	var top: Array = []
	for i in 6:
		var a = deg_to_rad(60.0 * i)
		top.append(Vector3(cos(a) * radius, top_y, sin(a) * radius))
	for i in range(1, 5):
		_tri(st, top[0], top[i], top[i + 1], Vector3.UP, top_color)
	for i in 6:
		var a: Vector3 = top[i]
		var b: Vector3 = top[(i + 1) % 6]
		var out = Vector3((a + b).x, 0, (a + b).z).normalized()
		_quad(st, a, b, Vector3(b.x, bottom_y, b.z), Vector3(a.x, bottom_y, a.z), out, side_color)

func _build_landmarks():
	for c in tiles.keys():
		var kind = int(tiles[c].get("landmark", -1))
		if kind < 0 or kind >= Landmark.NAMES.size():
			continue
		var col: Color = Landmark.COLORS[kind]
		var at = _surface(c)
		var gem = MeshInstance3D.new()
		var sphere = SphereMesh.new()  # 4 sides, 2 rings: an octahedron
		sphere.radius = 0.9
		sphere.height = 2.2
		sphere.radial_segments = 4
		sphere.rings = 1
		gem.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 0.8
		gem.material_override = mat
		gem.position = at + Vector3(0, 2.6, 0)
		_island.add_child(gem)
		_landmark_gems.append(gem)

		var label = Label3D.new()
		label.text = Landmark.NAMES[kind]
		label.font = UITheme.font_black()
		label.font_size = 26
		label.outline_size = 9
		label.outline_modulate = Color(0.03, 0.04, 0.08, 0.9)
		label.modulate = col.lightened(0.35)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.pixel_size = 0.00065
		label.no_depth_test = true
		label.render_priority = 2
		label.outline_render_priority = 1
		label.position = at + Vector3(0, 4.4, 0)
		_island.add_child(label)

func _scatter(items: Array, mesh: Mesh) -> MultiMeshInstance3D:
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var node = MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _vertex_material(0.9, 0.0)
	return node

func _tree_mesh() -> Mesh:
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.75
	cone.height = 2.0
	cone.radial_segments = 6
	cone.rings = 1
	var st = SurfaceTool.new()
	st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, 1.3, 0)))
	var trunk = CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.16
	trunk.height = 0.5
	trunk.radial_segments = 5
	trunk.rings = 1
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 0.25, 0)))
	return st.commit()

func _rock_mesh() -> Mesh:
	var rock = SphereMesh.new()
	rock.radius = 0.7
	rock.height = 1.2
	rock.radial_segments = 6
	rock.rings = 3
	return rock

## A flat hex band (inner > 0) or a filled hex (inner = 0), lying on y = 0
func _ring_mesh(outer: float, inner: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o: Array = []
	var n: Array = []
	for i in 6:
		var a = deg_to_rad(60.0 * i + 30.0)
		o.append(Vector3(cos(a) * outer, 0, sin(a) * outer))
		n.append(Vector3(cos(a) * inner, 0, sin(a) * inner))
	for i in 6:
		var j = (i + 1) % 6
		if inner > 0.0:
			_quad(st, n[i], n[j], o[j], o[i], Vector3.UP, Color.WHITE)
		elif i >= 1 and i <= 4:
			_tri(st, o[0], o[i], o[i + 1], Vector3.UP, Color.WHITE)
	return st.commit()

static func _vertex_material(roughness: float, specular: float) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = roughness
	if specular > 0.0:
		mat.metallic_specular = specular
	return mat

static func _glow_material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat

# ---------------------------------------------------------------- camera fit

func _update_fit():
	if size.x <= 0 or size.y <= 0:
		return
	var half = deg_to_rad(camera.fov * 0.5)  # fov is vertical
	var aspect = size.x / size.y
	var fit_v = _island_radius / tan(half)
	var fit_h = _island_radius / (tan(half) * aspect)
	var was_fit = is_equal_approx(_goal_dist, _fit_dist)
	_fit_dist = max(fit_v * 0.9, fit_h * 0.98)  # seen from above the far side shrinks: a bit closer fits
	if was_fit:
		_goal_dist = _fit_dist

# ---------------------------------------------------------------- picking and input

## The tile under a screen point: march the camera ray until it dips under a tile's top
func pick(screen_pos: Vector2) -> Vector2i:
	if tiles.is_empty():
		return INVALID
	var vp_pos := to_vp(screen_pos)
	var from = camera.project_ray_origin(vp_pos)
	var dir = camera.project_ray_normal(vp_pos)
	if dir.y >= -0.01:
		return INVALID
	var top_limit = 3.0 * HexTile.TERRACE_STEP * H_SCALE + MOUNTAIN_PEAK + 1.0
	var t = max(0.0, (from.y - top_limit) / -dir.y)
	var t_end = (from.y - BASE_Y) / -dir.y
	var step = R * 0.12
	while t <= t_end:
		var p = from + dir * t
		var c = world_to_hex(p.x, p.z)
		if tiles.has(c) and p.y <= _pick_top(c):
			return c
		t += step
	return INVALID

func _set_hovered(c: Vector2i):
	if c == hovered:
		return
	hovered = c
	_hover_ring.visible = c != INVALID
	if c != INVALID:
		_hover_ring.position = _surface(c) + Vector3(0, 0.12, 0)
		var ok = is_selectable(c)
		(_hover_ring.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.9) if ok else Color(1.0, 0.45, 0.45, 0.8)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ok else Control.CURSOR_FORBIDDEN
		hex_hovered.emit(c)
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_goal_dist = clamp(_goal_dist * 0.88, _fit_dist * 0.3, _fit_dist * 1.4)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_goal_dist = clamp(_goal_dist / 0.88, _fit_dist * 0.3, _fit_dist * 1.4)
				accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
					reset_view()
				elif event.pressed:
					_press_button = event.button_index
					_press_pos = event.position
					_dragged = false
				elif event.button_index == _press_button:
					if not _dragged and _press_button == MOUSE_BUTTON_LEFT:
						var c = pick(event.position)
						if c != INVALID:
							hex_clicked.emit(c)
					_press_button = 0
				accept_event()
	elif event is InputEventMouseMotion:
		if _press_button != 0:
			if not _dragged and event.position.distance_to(_press_pos) > CLICK_SLOP:
				_dragged = true
				_set_hovered(INVALID)
			if _dragged:
				if _press_button == MOUSE_BUTTON_LEFT:
					_goal_yaw -= event.relative.x * 0.008
					_goal_pitch = clamp(_goal_pitch + event.relative.y * 0.006, PITCH_MIN, PITCH_MAX)
				else:
					# Move the view over the island (screen drag -> ground plane)
					var right = Vector3(cos(_yaw), 0, -sin(_yaw))
					var fwd = Vector3(sin(_yaw), 0, cos(_yaw))
					var k = _dist / max(size.y, 1.0) * 1.1
					_goal_target -= (right * event.relative.x + fwd * event.relative.y) * k
					var flat = Vector2(_goal_target.x, _goal_target.z)
					if flat.length() > _island_radius * 0.8:
						flat = flat.normalized() * _island_radius * 0.8
						_goal_target = Vector3(flat.x, 0, flat.y)
			accept_event()
		else:
			_set_hovered(pick(event.position))

func _notification(what: int):
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hovered(INVALID)
