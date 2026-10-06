## Looks of the special biomes (BiomeRules), so you can tell them apart at a glance: tall grass
## that hides you, flowers on the meadow, glowing mushrooms, ice shards on the frost, thorny
## brambles. One MultiMesh per kind of part on the tile ("Decor"), seeded by the tile coordinates,
## visual only (no collision), gone when the tile changes biome (paths, zone, flood).
extends RefCounted
class_name BiomeDecor

const SWAY_SHADER = preload("res://shaders/foliage_sway.gdshader")

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

## (Re)build the decor of `tile` for its biome
static func decorate(tile: HexTile) -> void:
	var old = tile.get_node_or_null("Decor")
	if old:
		old.queue_free()
		old.name = "DecorOld"
	if tile.is_ramp() or tile.is_destroyed or DisplayServer.get_name() == "headless":
		return
	var parts: Array = []  # [mesh, material, [Transform3D], [Color]]
	var rng = RandomNumberGenerator.new()
	rng.seed = (tile.hex_coords.x * 92837111) ^ (tile.hex_coords.y * 689287499) ^ tile.biome_type
	match tile.biome_type:
		HexTile.BiomeType.GRASS:
			parts = _grassland(rng, ShaderHelper.biome_color(HexTile.BiomeType.GRASS), true)
		HexTile.BiomeType.FOREST:
			parts = _grassland(rng, ShaderHelper.biome_color(HexTile.BiomeType.FOREST), false)
			parts.append_array(_ferns(rng))
		HexTile.BiomeType.SWAMP:
			parts = _reeds(rng)
		HexTile.BiomeType.ROCK:
			parts = _boulders(rng)
		HexTile.BiomeType.WATER, HexTile.BiomeType.SHALLOW_WATER:
			parts = _lilies(rng, tile)
		HexTile.BiomeType.BEACH:
			if tile.has_meta("path"):
				parts = _path_sides(rng, tile)
		HexTile.BiomeType.TALL_GRASS:
			parts = _tall_grass(rng)
		HexTile.BiomeType.MEADOW:
			parts = _meadow(rng)
		HexTile.BiomeType.MUSHROOM:
			parts = _mushrooms(rng)
		HexTile.BiomeType.FROST:
			parts = _frost(rng)
		HexTile.BiomeType.THORNS:
			parts = _thorns(rng)
	if parts.is_empty():
		return
	var holder = Node3D.new()
	holder.name = "Decor"
	holder.position.y = HexTile.HEX_HEIGHT * 0.5
	tile.add_child(holder)
	for part in parts:
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = part[0]
		mm.instance_count = part[2].size()
		for i in part[2].size():
			mm.set_instance_transform(i, part[2][i])
			mm.set_instance_color(i, part[3][i])
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = part[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var range_end = RenderQuality.decor_range()
		if range_end > 0.0:
			mmi.visibility_range_end = range_end
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(mmi)

## A random spot on the hexagon's top, clear of the very edge
static func _spot(rng: RandomNumberGenerator, margin: float = 0.85) -> Vector3:
	while true:
		var p = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * HexTile.HEX_RADIUS * margin
		var inside = true
		for k in 6:
			var a = PI / 3.0 * k
			if p.dot(Vector2(cos(a), sin(a))) > HexTile.HEX_INNER_RADIUS * margin:
				inside = false
		if inside:
			return Vector3(p.x, 0.0, p.y)
	return Vector3.ZERO

static func _xf(pos: Vector3, yaw: float, scale: Vector3, tilt: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis = Basis.from_euler(Vector3(tilt.x, yaw, tilt.z)).scaled(scale)
	return Transform3D(basis, pos)

# ---------------------------------------------------------------- the biomes

## Tufts of grass everywhere, now and then a flower or a dandelion puff
static func _grassland(rng: RandomNumberGenerator, base: Color, flowers: bool) -> Array:
	var tufts: Array = []
	var tuft_colors: Array = []
	for i in 30:
		var p = _spot(rng, 0.95)
		var s = rng.randf_range(0.6, 1.1)
		tufts.append(_xf(p, rng.randf() * TAU, Vector3(s, s * rng.randf_range(0.8, 1.2), s)))
		tuft_colors.append(base.lightened(rng.randf_range(0.02, 0.18)).lerp(Color(0.85, 0.85, 0.35), rng.randf() * 0.15))
	var parts: Array = [[_mesh("tuft"), _sway(0.18), tufts, tuft_colors]]
	if flowers:
		var stems: Array = []
		var stem_colors: Array = []
		var heads: Array = []
		var head_colors: Array = []
		for i in rng.randi_range(2, 7):
			var p = _spot(rng)
			var h = rng.randf_range(0.8, 1.2)
			stems.append(_xf(p, 0.0, Vector3(1, h, 1)))
			stem_colors.append(base.darkened(0.1))
			heads.append(_xf(p + Vector3(0, 0.34 * h, 0), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.7, 1.1)))
			# Dandelions: yellow flowers and white puffs
			head_colors.append([Color(1.0, 0.86, 0.2), Color(1.0, 0.86, 0.2), Color(0.98, 0.98, 0.95), Color(0.95, 0.6, 0.85)][rng.randi() % 4])
		parts.append([_mesh("stem"), _sway(0.1), stems, stem_colors])
		parts.append([_mesh("flower"), _sway(0.0), heads, head_colors])
	return parts

static func _ferns(rng: RandomNumberGenerator) -> Array:
	var xf: Array = []
	var colors: Array = []
	for plant in 4:
		var c = _spot(rng, 0.8)
		for i in 6:
			xf.append(_xf(c, i * TAU / 6.0 + rng.randf() * 0.4, Vector3.ONE * rng.randf_range(0.8, 1.2), Vector3(rng.randf_range(0.7, 1.1), 0, 0)))
			colors.append(Color(0.2, 0.48, 0.18).lerp(Color(0.35, 0.6, 0.22), rng.randf()))
	return [[_mesh("frond"), _sway(0.08), xf, colors]]

## Reeds with brown cattail heads
static func _reeds(rng: RandomNumberGenerator) -> Array:
	var reeds: Array = []
	var reed_colors: Array = []
	var heads: Array = []
	var head_colors: Array = []
	for clump in 6:
		var c = _spot(rng, 0.85)
		for i in 7:
			var p = c + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
			var h = rng.randf_range(0.9, 1.5)
			reeds.append(_xf(p, rng.randf() * TAU, Vector3(1.0, h, 1.0)))
			reed_colors.append(Color(0.42, 0.55, 0.25).lerp(Color(0.6, 0.62, 0.3), rng.randf()))
			if i % 3 == 0:
				heads.append(_xf(p + Vector3(0, h * 0.8, 0), 0.0, Vector3.ONE))
				head_colors.append(Color(0.42, 0.26, 0.14))
	return [[_mesh("blade"), _sway(0.12), reeds, reed_colors], [_mesh("cattail"), _sway(0.12), heads, head_colors]]

static func _boulders(rng: RandomNumberGenerator) -> Array:
	var xf: Array = []
	var colors: Array = []
	for i in rng.randi_range(3, 6):
		var p = _spot(rng, 0.8)
		var s = rng.randf_range(0.5, 1.4)
		xf.append(_xf(p, rng.randf() * TAU, Vector3(s * rng.randf_range(0.9, 1.3), s * rng.randf_range(0.5, 0.8), s), Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))))
		colors.append(Color(0.55, 0.53, 0.5).lerp(Color(0.68, 0.64, 0.58), rng.randf()))
	return [[_mesh("boulder"), _stone(), xf, colors]]

## Lily pads (some with a pink flower) on part of the water
static func _lilies(rng: RandomNumberGenerator, tile: HexTile) -> Array:
	if rng.randf() > (0.45 if tile.biome_type == HexTile.BiomeType.SHALLOW_WATER else 0.3):
		return []
	var pads: Array = []
	var pad_colors: Array = []
	var flowers: Array = []
	var flower_colors: Array = []
	for i in rng.randi_range(3, 7):
		var p = _spot(rng, 0.8) + Vector3(0, -0.035, 0)
		var s = rng.randf_range(0.8, 1.4)
		pads.append(_xf(p, rng.randf() * TAU, Vector3(s, 1.0, s)))
		pad_colors.append(Color(0.25, 0.55, 0.22).lerp(Color(0.4, 0.66, 0.26), rng.randf()))
		if rng.randf() < 0.3:
			flowers.append(_xf(p + Vector3(0, 0.05, 0), rng.randf() * TAU, Vector3.ONE))
			flower_colors.append(Color(1.0, 0.62, 0.8))
	var parts: Array = [[_mesh("lily"), _sway(0.0), pads, pad_colors]]
	if not flowers.is_empty():
		parts.append([_mesh("flower"), _sway(0.0), flowers, flower_colors])
	return parts

## Along a dirt path: little fences where it meets the grass and a vegetable bed here and there
static func _path_sides(rng: RandomNumberGenerator, tile: HexTile) -> Array:
	var grid = tile.get_parent() as HexGrid
	if not grid:
		return []
	var posts: Array = []
	var post_colors: Array = []
	var rails: Array = []
	var rail_colors: Array = []
	var wood = Color(0.6, 0.44, 0.28)
	for k in 6:
		var n = grid.get_tile(tile.hex_coords + HexTile.EDGE_DIRECTIONS[k])
		if not n or n.has_meta("path") or n.is_water() or n.is_mountain() or n.level != tile.level or rng.randf() < 0.45:
			continue
		# The edge between corners k - 1 and k (corner i at 60 i + 30 degrees), pulled in a little
		var a0 = deg_to_rad(60.0 * k - 30.0)
		var a1 = deg_to_rad(60.0 * k + 30.0)
		var p0 = Vector3(cos(a0), 0, sin(a0)) * HexTile.HEX_RADIUS * 0.86
		var p1 = Vector3(cos(a1), 0, sin(a1)) * HexTile.HEX_RADIUS * 0.86
		for t in [0.1, 0.5, 0.9]:
			posts.append(_xf(p0.lerp(p1, t), 0.0, Vector3.ONE))
			post_colors.append(wood)
		var along = p1 - p0
		var yaw = atan2(along.x, along.z)
		for y in [0.18, 0.32]:
			rails.append(_xf((p0 + p1) * 0.5 + Vector3(0, y, 0), yaw, Vector3(1.0, 1.0, along.length() * 0.8)))
			rail_colors.append(wood.lightened(0.08))
	var parts: Array = []
	if not posts.is_empty():
		parts.append([_mesh("post"), _sway(0.0), posts, post_colors])
		parts.append([_mesh("rail"), _sway(0.0), rails, rail_colors])
	# A vegetable bed: rows of leafy tops (carrots, beets) on dark soil
	if rng.randf() < 0.35:
		var soil: Array = []
		var tops: Array = []
		var top_colors: Array = []
		var turn = Basis(Vector3.UP, rng.randf() * TAU)
		var off = _spot(rng, 0.3)
		soil.append(Transform3D(turn, off))
		for row in 3:
			for i in 5:
				var local = Vector3(-0.6 + i * 0.3, 0.1, -0.3 + row * 0.3)
				tops.append(_xf(off + turn * local, rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.8, 1.2)))
				top_colors.append(Color(0.3, 0.62, 0.22).lerp(Color(0.5, 0.75, 0.25), rng.randf()))
		parts.append([_mesh("bed"), _sway(0.0), soil, [Color(0.33, 0.22, 0.14)]])
		parts.append([_mesh("tuft"), _sway(0.1), tops, top_colors])
	return parts

static func _tall_grass(rng: RandomNumberGenerator) -> Array:
	var xf: Array = []
	var colors: Array = []
	for clump in 14:
		var c = _spot(rng, 0.9)
		for i in 6:
			var p = c + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
			var h = rng.randf_range(0.95, 1.45)
			xf.append(_xf(p, rng.randf() * TAU, Vector3(1.0, h, 1.0), Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))))
			colors.append(Color(0.62, 0.72, 0.26).lerp(Color(0.85, 0.8, 0.4), rng.randf() * 0.6))
	return [[_mesh("blade"), _sway(0.16), xf, colors]]

static func _meadow(rng: RandomNumberGenerator) -> Array:
	var stems: Array = []
	var stem_colors: Array = []
	var heads: Array = []
	var head_colors: Array = []
	var palette = [Color(1.0, 0.5, 0.75), Color(1.0, 0.9, 0.35), Color(0.97, 0.97, 1.0), Color(0.7, 0.55, 1.0), Color(1.0, 0.45, 0.35)]
	for i in 26:
		var p = _spot(rng)
		var h = rng.randf_range(0.7, 1.2)
		stems.append(_xf(p, 0.0, Vector3(1, h, 1)))
		stem_colors.append(Color(0.3, 0.6, 0.25))
		heads.append(_xf(p + Vector3(0, 0.34 * h, 0), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.8, 1.3)))
		head_colors.append(palette[rng.randi() % palette.size()])
	return [[_mesh("stem"), _sway(0.1), stems, stem_colors], [_mesh("flower"), _sway(0.0), heads, head_colors]]

static func _mushrooms(rng: RandomNumberGenerator) -> Array:
	var stems: Array = []
	var caps: Array = []
	var stem_colors: Array = []
	var cap_colors: Array = []
	for i in 9:
		var p = _spot(rng, 0.8)
		var s = rng.randf_range(0.6, 1.3) if i > 1 else rng.randf_range(1.8, 2.6)  # a couple of big ones
		stems.append(_xf(p, 0.0, Vector3(s, s, s)))
		stem_colors.append(Color(0.92, 0.88, 0.8))
		caps.append(_xf(p + Vector3(0, 0.3 * s, 0), rng.randf() * TAU, Vector3(s, s, s)))
		cap_colors.append([Color(0.7, 0.35, 0.95), Color(0.9, 0.25, 0.35), Color(0.45, 0.6, 1.0)][rng.randi() % 3])
	return [[_mesh("mush_stem"), _sway(0.0), stems, stem_colors], [_mesh("mush_cap"), _glow(), caps, cap_colors]]

static func _frost(rng: RandomNumberGenerator) -> Array:
	var xf: Array = []
	var colors: Array = []
	for cluster in 4:
		var c = _spot(rng, 0.75)
		for i in 4:
			var p = c + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
			var h = rng.randf_range(0.4, 1.1)
			xf.append(_xf(p, rng.randf() * TAU, Vector3(1.0, h, 1.0), Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))))
			colors.append(Color(0.75, 0.92, 1.0).lerp(Color(1, 1, 1), rng.randf() * 0.5))
	return [[_mesh("shard"), _ice(), xf, colors]]

static func _thorns(rng: RandomNumberGenerator) -> Array:
	var spikes: Array = []
	var spike_colors: Array = []
	var berries: Array = []
	var berry_colors: Array = []
	for bush in 7:
		var c = _spot(rng, 0.85)
		for i in 7:
			var dir = rng.randf() * TAU
			var lean = rng.randf_range(0.3, 1.0)
			spikes.append(_xf(c, dir, Vector3(1.0, rng.randf_range(0.5, 0.95), 1.0), Vector3(lean, 0, 0)))
			spike_colors.append(Color(0.3, 0.2, 0.14).lerp(Color(0.2, 0.3, 0.14), rng.randf()))
		for i in 3:
			berries.append(_xf(c + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.2, 0.5), rng.randf_range(-0.3, 0.3)), 0.0, Vector3.ONE))
			berry_colors.append(Color(0.85, 0.12, 0.2))
	return [[_mesh("spike"), _sway(0.04), spikes, spike_colors], [_mesh("berry"), _sway(0.0), berries, berry_colors]]

# ---------------------------------------------------------------- shared meshes and materials

static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		"tuft":
			m = _tuft_mesh()
		"frond":
			m = _lifted(_cone(0.12, 0.0, 0.7, 3), 0.35)
		"cattail":
			m = _lifted(_cone(0.045, 0.045, 0.2, 6), 0.0)
		"boulder":
			var rock = SphereMesh.new()
			rock.radius = 0.35
			rock.height = 0.7
			rock.radial_segments = 7
			rock.rings = 4
			m = _lifted(rock, 0.12)
		"lily":
			var pad = _cone(0.3, 0.3, 0.02, 9)
			pad.cap_top = true  # seen from above
			m = _lifted(pad, 0.0)
		"post":
			m = _lifted(_cone(0.04, 0.035, 0.45, 5), 0.22)
		"rail":
			var rail = BoxMesh.new()
			rail.size = Vector3(0.04, 0.05, 1.0)
			m = rail
		"bed":
			var bed = BoxMesh.new()
			bed.size = Vector3(1.5, 0.12, 1.0)
			m = _lifted(bed, 0.04)
		"blade":
			m = _lifted(_cone(0.07, 0.0, 1.0, 3), 0.5)
		"stem":
			m = _lifted(_cone(0.015, 0.015, 0.34, 4), 0.17)
		"flower":
			var s = SphereMesh.new()
			s.radius = 0.08
			s.height = 0.1
			s.radial_segments = 6
			s.rings = 3
			m = s
		"mush_stem":
			m = _lifted(_cone(0.06, 0.08, 0.3, 6), 0.15)
		"mush_cap":
			var cap = SphereMesh.new()
			cap.radius = 0.2
			cap.height = 0.2
			cap.is_hemisphere = true
			cap.radial_segments = 10
			cap.rings = 4
			m = cap
		"shard":
			m = _lifted(_cone(0.12, 0.0, 1.0, 5), 0.5)
		"spike":
			m = _lifted(_cone(0.04, 0.0, 0.9, 3), 0.45)
		"berry":
			var b = SphereMesh.new()
			b.radius = 0.06
			b.height = 0.12
			b.radial_segments = 6
			b.rings = 3
			m = b
	_meshes[kind] = m
	return m

## A tuft: seven thin blades fanning out from one spot (flat triangles, drawn from both sides)
static func _tuft_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 7:
		var a = TAU * i / 7.0 + 0.4 * sin(i * 2.3)
		var out = Vector3(cos(a), 0, sin(a))
		var side = Vector3(-out.z, 0, out.x) * 0.035
		var h = 0.28 + 0.12 * fmod(i * 0.37, 1.0)
		var tip = out * (0.1 + 0.05 * fmod(i * 0.61, 1.0)) + Vector3(0, h, 0)
		for v in [out * 0.02 - side, out * 0.02 + side, tip]:
			st.set_color(Color.WHITE)  # the MultiMesh instance color tints it
			st.set_normal((Vector3.UP * 2.0 + out).normalized())
			st.add_vertex(v)
	return st.commit()

static func _stone() -> StandardMaterial3D:
	if not _materials.has("stone"):
		var m = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.95
		_materials["stone"] = m
	return _materials["stone"]

static func _cone(bottom: float, top: float, height: float, sides: int) -> CylinderMesh:
	var c = CylinderMesh.new()
	c.bottom_radius = bottom
	c.top_radius = top
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	c.cap_top = false
	return c

## The mesh moved up so it stands on y = 0 (the sway bends from there)
static func _lifted(mesh: PrimitiveMesh, lift: float) -> ArrayMesh:
	var arrays = mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += lift
	arrays[Mesh.ARRAY_VERTEX] = verts
	var out = ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out

static func _sway(amount: float) -> ShaderMaterial:
	var key = "sway%.2f" % amount
	if not _materials.has(key):
		var m = ShaderMaterial.new()
		m.shader = SWAY_SHADER
		m.set_shader_parameter("sway", amount)
		_materials[key] = m
	return _materials[key]

static func _glow() -> ShaderMaterial:
	if not _materials.has("glow"):
		var m = ShaderMaterial.new()
		m.shader = SWAY_SHADER
		m.set_shader_parameter("sway", 0.0)
		m.set_shader_parameter("emission", 0.35)
		_materials["glow"] = m
	return _materials["glow"]

static func _ice() -> StandardMaterial3D:
	if not _materials.has("ice"):
		var m = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.albedo_color = Color(1, 1, 1)
		m.metallic = 0.2
		m.roughness = 0.08
		m.emission_enabled = true
		m.emission = Color(0.35, 0.55, 0.7)
		m.emission_energy_multiplier = 0.25
		_materials["ice"] = m
	return _materials["ice"]
