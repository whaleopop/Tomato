## The main menu's backdrop: a little piece of the real map in the golden hour - game hex tiles
## (grass, a meadow, a terrace with trees behind, cover walls at the sides) - with your arsenal:
## a wooden rack on which all twelve guns hang in the finishes they wear (PlayerProfile), each with
## a plate of its mastery level (Mastery.gd), a shelf of ammo / medkit / shield, crates and a barrel
## around, string lights over it. Your hero stands on a dais in front (show_hero, the menu cycles
## the heroes you own). The view leans a little towards the mouse. Own World3D.
extends SubViewportContainer
class_name MenuDiorama

const RADIUS: int = 4
const TILE_HEIGHT: float = 0.45                 # like the training ground's tiles
const HERO_SPOT := Vector3(2.4, 0.0, 1.4)
const RACK_SPOT := Vector3(2.6, 0.0, -2.4)
const RACK_SIZE := Vector2(7.2, 3.5)
const SHELF_TOP: float = 0.85       # the guns hang above the shelf
const GUN_ROWS: int = 3
const GUN_COLS: int = 4
const HERO_HEIGHT: float = 1.45
const WOOD := Color(0.45, 0.29, 0.17)
const WOOD_DARK := Color(0.3, 0.19, 0.11)

var viewport: SubViewport
var camera: Camera3D
var grid: HexGrid
var _ground_y: float = 0.0
var _hero_holder: Node3D
var _hero_model: Node3D
var _dais_glow: StandardMaterial3D
var _lean := Vector2.ZERO
var _time: float = 0.0
var _bulbs: Array = []

func _init():
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.positional_shadow_atlas_size = 2048
	add_child(viewport)

func _ready():
	PlayerProfile.load_profile()
	_build_environment()
	_build_ground()
	_build_arsenal()
	_build_props()
	_build_hero_stage()
	camera = Camera3D.new()
	camera.fov = 48.0
	viewport.add_child(camera)
	_place_camera()

# ---------------------------------------------------------------- light and sky

func _build_environment():
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.38, 0.7)
	sky_mat.sky_horizon_color = Color(1.0, 0.72, 0.5)
	sky_mat.ground_horizon_color = Color(0.85, 0.6, 0.45)
	sky_mat.ground_bottom_color = Color(0.2, 0.18, 0.2)
	sky_mat.sun_angle_max = 20.0
	var sky = Sky.new()
	sky.sky_material = sky_mat
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(1.0, 0.78, 0.6)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.35
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -48, 0)   # low, warm, from the right behind the camera
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	viewport.add_child(sun)
	var rim = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 140, 0)
	rim.light_color = Color(0.55, 0.65, 1.0)
	rim.light_energy = 0.35
	viewport.add_child(rim)

# ---------------------------------------------------------------- the ground

func _build_ground():
	grid = HexGrid.new(RADIUS)
	grid.name = "MenuGrid"
	viewport.add_child(grid)
	var step = HexTile.TERRACE_STEP / HexTile.HEX_HEIGHT
	for q in range(-RADIUS, RADIUS + 1):
		for r in range(max(-RADIUS, -q - RADIUS), min(RADIUS, -q + RADIUS) + 1):
			var c = Vector2i(q, r)
			var tile = HexTile.new()
			tile.hex_coords = c
			tile.position = grid.hex_to_world(c)
			var biome = HexTile.BiomeType.GRASS
			var level = 0
			if r <= -2:
				level = 1                                  # a terrace behind the arsenal
				biome = HexTile.BiomeType.FOREST if (q + r) % 2 == 0 else HexTile.BiomeType.GRASS
			elif r >= 2 or q <= -2:
				biome = HexTile.BiomeType.MEADOW           # flowers in front
			tile.biome_type = biome
			tile.level = level
			tile.set_height(TILE_HEIGHT + level * step)
			grid.add_tile(c, tile)
	grid.update_tile_edges()
	_ground_y = CoverSpawner.tile_top(grid.get_tile(Vector2i.ZERO))
	# Trees on the terrace, a wall or two at the sides
	var rng = RandomNumberGenerator.new()
	rng.seed = 2718
	for c in [Vector2i(-1, -2), Vector2i(1, -3), Vector2i(3, -3), Vector2i(-2, -2), Vector2i(4, -4), Vector2i(0, -3)]:
		var tile = grid.get_tile(c)
		if not tile:
			continue
		var tree = GardenTree.new()
		tree.tree_seed = rng.randi()
		tree.position = grid.hex_to_world(c) + Vector3(rng.randf_range(-0.6, 0.6), CoverSpawner.tile_top(tile), rng.randf_range(-0.6, 0.6))
		viewport.add_child(tree)
	for w in [[Vector2i(-1, 0), Vector2i(-1, 1), CoverWall.Kind.STONE], [Vector2i(3, 0), Vector2i(3, -1), CoverWall.Kind.WOOD], [Vector2i(-2, 1), Vector2i(-2, 2), CoverWall.Kind.SANDBAG]]:
		var a = grid.hex_to_world(w[0])
		var b = grid.hex_to_world(w[1])
		var wall = CoverWall.new()
		wall.kind = w[2]
		var across = (b - a).normalized()
		wall.position = (a + b) / 2.0 + Vector3(0, _ground_y, 0)
		wall.rotation.y = atan2(across.x, across.z)
		viewport.add_child(wall)

# ---------------------------------------------------------------- the arsenal

func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D, metal: float = 0.0) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.35 if metal > 0.5 else 0.85
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_arsenal():
	var rack = Node3D.new()
	rack.name = "Arsenal"
	rack.position = RACK_SPOT + Vector3(0, _ground_y, 0)
	viewport.add_child(rack)
	var w = RACK_SIZE.x
	var h = RACK_SIZE.y
	# The board of planks, posts, a top beam with a little roof, the shelf below
	for i in 8:
		var plank_w = w / 8.0
		var shade = WOOD.darkened(0.06 * (i % 3))
		_box(Vector3(plank_w - 0.03, h, 0.1), Vector3(-w / 2.0 + plank_w * (i + 0.5), 0.25 + h / 2.0, 0), shade, rack)
	for side in [-1, 1]:
		_box(Vector3(0.22, h + 0.7, 0.22), Vector3(side * (w / 2.0 + 0.1), (h + 0.7) / 2.0, 0.05), WOOD_DARK, rack)
	_box(Vector3(w + 0.7, 0.22, 0.3), Vector3(0, h + 0.5, 0.05), WOOD_DARK, rack)
	var roof = _box(Vector3(w + 1.0, 0.08, 0.9), Vector3(0, h + 0.92, 0.2), Color(0.55, 0.22, 0.16), rack)
	roof.rotation.x = 0.22
	_box(Vector3(w, 0.1, 0.55), Vector3(0, SHELF_TOP - 0.05, 0.3), WOOD_DARK, rack)          # the shelf
	_box(Vector3(w, SHELF_TOP - 0.1, 0.06), Vector3(0, (SHELF_TOP - 0.1) / 2.0, 0.55), WOOD.darkened(0.15), rack)  # its front
	# A sign over it
	var sign_label = Label3D.new()
	sign_label.text = Locale.t("ARSENAL")
	sign_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sign_label.font = UITheme.font_black()
	sign_label.font_size = 64
	sign_label.outline_size = 12
	sign_label.outline_modulate = Color(0.15, 0.08, 0.03)
	sign_label.modulate = Color(1.0, 0.85, 0.55)
	sign_label.pixel_size = 0.006
	sign_label.position = Vector3(0, h + 0.5, 0.22)
	sign_label.font_size = 52
	rack.add_child(sign_label)

	# The guns, in the finishes they wear, each with its mastery plate under it
	for t in RangedWeapon.WeaponType.size():
		var row = t / GUN_COLS
		var col = t % GUN_COLS
		var row_h = (h + 0.25 - SHELF_TOP - 0.45) / GUN_ROWS  # clear of what lies on the shelf
		var cell = Vector3(-w / 2.0 + w / GUN_COLS * (col + 0.5), h + 0.1 - (row + 0.5) * row_h, 0.12)
		var weapon = RangedWeapon.create_weapon(t)
		var model = LootVisuals.pickup_model(LootItem.ItemType.WEAPON, weapon)
		if model:
			Cosmetics.apply_to_weapon(model, PlayerProfile.weapon_finish_for(t))
			var holder = Node3D.new()
			holder.add_child(model)
			holder.rotation.y = -PI / 2.0          # barrels (along -Z) point to the right: side-on
			holder.scale = Vector3.ONE * 1.5  # true to size between guns (LootVisuals.weapon_scale), big on the rack
			holder.position = cell + Vector3(0, 0.12, 0.08)
			rack.add_child(holder)
		# two pegs
		for px in [-0.32, 0.32]:
			_box(Vector3(0.05, 0.05, 0.22), cell + Vector3(px, -0.08, 0.06), Color(0.75, 0.62, 0.35), rack, 0.8)
		var p = PlayerProfile.weapon_progress(t)
		var plate_col = Mastery.tier_color(p.tier) if p.tier >= 0 else Color(0.85, 0.8, 0.7)
		_box(Vector3(1.1, 0.2, 0.03), cell + Vector3(0, -0.3, 0.06), plate_col.darkened(0.45) if p.tier >= 0 else Color(0.2, 0.14, 0.09), rack, 0.7 if p.tier >= 0 else 0.0)
		var plate = Label3D.new()
		plate.text = "%s  ·  %s" % [Locale.t(weapon.item_name, "short"), Locale.t("Lv %d") % p.level]
		plate.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		plate.font = UITheme.font_black()
		plate.font_size = 40
		plate.outline_size = 8
		plate.outline_modulate = Color(0.05, 0.03, 0.02, 0.8)
		plate.modulate = plate_col.lightened(0.25)
		plate.pixel_size = 0.0042
		plate.position = cell + Vector3(0, -0.3, 0.085)
		rack.add_child(plate)

	# String lights along the beam
	for i in 15:
		var x = -w / 2.0 + w * i / 14.0
		var sag = sin(PI * fmod(i, 5) / 4.0) * 0.12
		var bulb = MeshInstance3D.new()
		var ball = SphereMesh.new()
		ball.radius = 0.06
		ball.height = 0.12
		bulb.mesh = ball
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.5)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.75, 0.4)
		mat.emission_energy_multiplier = 2.5
		bulb.material_override = mat
		bulb.position = Vector3(x, h + 0.34 - sag, 0.3)
		rack.add_child(bulb)
		_bulbs.append(mat)
	for side in [-1, 1]:
		var lamp = OmniLight3D.new()
		lamp.position = Vector3(side * w * 0.28, h + 0.1, 1.2)
		lamp.light_color = Color(1.0, 0.75, 0.45)
		lamp.light_energy = 1.6
		lamp.omni_range = 5.0
		rack.add_child(lamp)

	# On the shelf: ammo, a medkit, a shield, an ability crystal
	var shelf_items = [
		[LootItem.ItemType.AMMO, AmmoItem.new(AmmoItem.AmmoType.RIFLE, 30)],
		[LootItem.ItemType.AMMO, AmmoItem.new(AmmoItem.AmmoType.SHOTGUN, 12)],
		[LootItem.ItemType.HEALTH, null],
		[LootItem.ItemType.SHIELD, null],
		[LootItem.ItemType.AMMO, AmmoItem.new(AmmoItem.AmmoType.SNIPER, 10)],
		[LootItem.ItemType.ABILITY_BOOST, null],
		[LootItem.ItemType.AMMO, AmmoItem.new(AmmoItem.AmmoType.PISTOL, 36)],
	]
	for i in shelf_items.size():
		var item = LootVisuals.pickup_model(shelf_items[i][0], shelf_items[i][1])
		if not item:
			continue
		var holder = Node3D.new()
		holder.add_child(item)
		holder.position = Vector3(-w / 2.0 + w * (i + 0.5) / shelf_items.size(), SHELF_TOP + 0.12, 0.36)
		holder.scale = Vector3.ONE * 0.6
		holder.rotation.y = (i % 3 - 1) * 0.4
		rack.add_child(holder)

# ---------------------------------------------------------------- crates around

func _build_props():
	var spots = [
		[LootContainer.ContainerType.CHEST, Vector3(-1.4, 0, -1.6), 0.4, 1.0],
		[LootContainer.ContainerType.CRATE, Vector3(6.6, 0, -1.4), -0.3, 1.0],
		[LootContainer.ContainerType.CRATE, Vector3(6.75, 0.62, -1.45), 0.5, 0.7],
		[LootContainer.ContainerType.BARREL, Vector3(-0.6, 0, -0.4), 0.0, 1.0],
		[LootContainer.ContainerType.SUPPLY_DROP, Vector3(6.2, 0, 1.2), -0.6, 1.0],
	]
	for s in spots:
		var model = LootVisuals.container_model(s[0])
		if not model:
			continue
		model.position = s[1] + Vector3(0, _ground_y, 0)
		model.rotation.y = s[2]
		model.scale = Vector3.ONE * s[3]
		var parachute = model.find_child("Parachute", true, false)
		if parachute:
			parachute.visible = false
		viewport.add_child(model)

# ---------------------------------------------------------------- the hero

func _build_hero_stage():
	var dais = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.95
	cyl.bottom_radius = 1.05
	cyl.height = 0.18
	cyl.radial_segments = 6                    # a little hex, like the tiles
	dais.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.25, 0.3)
	mat.roughness = 0.5
	dais.material_override = mat
	dais.position = HERO_SPOT + Vector3(0, _ground_y + 0.09, 0)
	viewport.add_child(dais)
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 6
	torus.ring_segments = 6
	ring.mesh = torus
	_dais_glow = StandardMaterial3D.new()
	_dais_glow.emission_enabled = true
	_dais_glow.emission_energy_multiplier = 2.0
	ring.material_override = _dais_glow
	ring.position = HERO_SPOT + Vector3(0, _ground_y + 0.19, 0)
	viewport.add_child(ring)
	_hero_holder = Node3D.new()
	_hero_holder.position = HERO_SPOT + Vector3(0, _ground_y + 0.18, 0)
	viewport.add_child(_hero_holder)

## Put a hero on the dais, in what they wear
func show_hero(data: CharacterData, skin: String, hat: String) -> void:
	if not _hero_holder:
		return
	if _hero_model and is_instance_valid(_hero_model):
		_hero_model.queue_free()
	_hero_model = Node3D.new()
	_hero_holder.add_child(_hero_model)
	_dais_glow.albedo_color = data.color
	_dais_glow.emission = data.color.lightened(0.2)
	if data.model_path != "" and ResourceLoader.exists(data.model_path):
		var instance = load(data.model_path).instantiate()
		ModelUtils.apply_lowpoly_look(instance)
		_hero_model.add_child(instance)
		ModelUtils.normalize_to_height(instance, HERO_HEIGHT)
		Cosmetics.apply_to_character(_hero_model, skin, hat)
		var players = instance.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty() and players[0].has_animation("idle"):
			players[0].get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			players[0].play("idle")
	# Drop onto the dais
	_hero_model.position.y = 1.2
	_hero_model.scale = Vector3.ONE * 0.85
	var t = create_tween().set_parallel()
	t.tween_property(_hero_model, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_hero_model, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.3)

# ---------------------------------------------------------------- camera

func _place_camera():
	var base = Vector3(4.6, _ground_y + 2.8, 10.6)
	camera.position = base + Vector3(_lean.x * 0.9, -_lean.y * 0.4, 0)
	camera.look_at(Vector3(1.8 + _lean.x * 0.3, _ground_y + 1.6, -0.8), Vector3.UP)

func _process(delta: float):
	_time += delta
	var vp = get_viewport()
	if vp and camera:
		var m = vp.get_mouse_position() / vp.get_visible_rect().size.max(Vector2.ONE) - Vector2(0.5, 0.5)
		_lean = _lean.lerp(m, 1.0 - exp(-2.5 * delta))
		_place_camera()
	if _hero_holder:
		# turned to the camera, swaying a little
		_hero_holder.rotation.y = 0.35 + sin(_time * 0.6) * 0.25
	for i in _bulbs.size():
		_bulbs[i].emission_energy_multiplier = 2.2 + sin(_time * 2.0 + i * 0.9) * 0.6
