## The main menu's backdrop: a little piece of the real map in the golden hour - game hex tiles
## (grass, a meadow, a terrace with trees behind, cover walls at the sides) - with your arsenal:
## a wooden rack on which all twelve guns hang in the finishes they wear (PlayerProfile), each with
## a plate of its mastery level (Mastery.gd), a shelf of ammo / medkit / shield, crates and a barrel
## around, string lights over it. Your hero stands on a dais in front (show_hero, the menu cycles
## the heroes you own). The view leans a little towards the mouse. Own World3D.
## With `interactive` (the main menu) the things in it can be pointed at and clicked - the hero,
## every gun, the sign, the shelf pickups and the containers: picked without physics (a ray from
## the camera against a box per thing), the hovered one reacts and a tooltip chip floats by it.
## Other screens (ScenicBackground) keep it passive: clicks go through.
extends HiResView
class_name MenuDiorama

## The hero on the dais was clicked (MainMenu opens their wardrobe)
signal hero_clicked(data: CharacterData)
## A gun on the rack was clicked (its finishes)
signal gun_clicked(weapon_type: int)
## A container ("chest", "crate", "barrel", "supply_drop"; data = its ContainerType), the sign
## ("sign", null) or a shelf pickup ("shelf", its guide entry title) was clicked
signal prop_clicked(kind: String, data)
## The empty dais (show_empty_slot) was clicked: invite a friend to fill it
signal invite_clicked

## The containers that can be clicked (prop_clicked kinds) and their names (LocaleRu keys)
const PROP_KINDS = {
	LootContainer.ContainerType.CHEST: "chest",
	LootContainer.ContainerType.CRATE: "crate",
	LootContainer.ContainerType.BARREL: "barrel",
	LootContainer.ContainerType.SUPPLY_DROP: "supply_drop",
}
const PROP_TITLES = {"chest": "Chest", "crate": "Crate", "barrel": "Barrel", "supply_drop": "Supply Drop"}
## Shelf pickup -> its entry title in the guide's Items tab (Encyclopedia._item_entries)
const SHELF_ENTRIES = {
	LootItem.ItemType.AMMO: "Ammo",
	LootItem.ItemType.HEALTH: "Health Pack",
	LootItem.ItemType.SHIELD: "Shield",
	LootItem.ItemType.ABILITY_BOOST: "Ability Boost",
}
const TOOLTIP_GAP: float = 14.0
const HOVER_EASE: float = 12.0

## Point and click the scene (the main menu); off: the mouse goes through it (other screens)
var interactive: bool = false:
	set(value):
		interactive = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		if not value:
			_set_hover(-1)
## The hero standing on the dais now (show_hero); null on an empty slot (show_empty_slot)
var hero_data: CharacterData = null
var _plus_sign: Node3D = null  # the floating "+" over an empty dais (show_empty_slot)

const PARTY_SPOT := Vector3(0.1, 0.0, 2.3)  # a small second dais beside the hero, front-left
var _party_holder: Node3D = null
var _party_plus: Node3D = null
var _party_ring_mat: StandardMaterial3D = null
var _party_visible: bool = false

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


var camera: Camera3D
var grid: HexGrid
var _ground_y: float = 0.0
var _hero_holder: Node3D
var _hero_model: Node3D
var _dais_glow: StandardMaterial3D
var _lean := Vector2.ZERO
var _time: float = 0.0
var _bulbs: Array = []

# Picking: {kind, data, aabb (world), node (what reacts), base_pos, base_scale, plate (Label3D),
# title, action, anchor (where the tooltip points)}
var _pickables: Array = []
var _hover: int = -1
var _mouse_in: bool = false
var _mouse_local := Vector2.ZERO
var _hero_glow: float = 0.0        # 0..1, the dais ring brightens while the hero is hovered
var _hero_spin: float = 0.0        # one turn on a click, added to the sway
var _busy: Dictionary = {}         # node -> its click animation runs (no hover tweens meanwhile)
var _tooltip: PanelContainer = null
var _tip_title: Label = null
var _tip_action: Label = null
var _tip_alpha: float = 0.0
var _tip_anchor := Vector3.ZERO
var _tip_shown: bool = false
var _tweens: Dictionary = {}       # node -> its running hover / click tween (one at a time)

func _init():
	super()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.positional_shadow_atlas_size = 2048

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
	_build_tooltip()
	var hero_pick = _add_pickable("hero", null, _hero_box(), _hero_holder, "", "Click: wardrobe")
	hero_pick["anchor"] = HERO_SPOT + Vector3(0, _ground_y + HERO_HEIGHT + 0.2, 0)  # over the head

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
	var sign_at = rack.position + sign_label.position
	_add_pickable("sign", null, AABB(sign_at - Vector3(1.3, 0.3, 0.2), Vector3(2.6, 0.6, 0.4)), sign_label, "ARSENAL", "Click: weapon guide")

	# The guns, in the finishes they wear, each with its mastery plate under it
	for t in RangedWeapon.WeaponType.size():
		var row = t / GUN_COLS
		var col = t % GUN_COLS
		var row_h = (h + 0.25 - SHELF_TOP - 0.45) / GUN_ROWS  # clear of what lies on the shelf
		var cell = Vector3(-w / 2.0 + w / GUN_COLS * (col + 0.5), h + 0.1 - (row + 0.5) * row_h, 0.12)
		var weapon = RangedWeapon.create_weapon(t)
		var model = LootVisuals.pickup_model(LootItem.ItemType.WEAPON, weapon)
		var holder: Node3D = null
		if model:
			Cosmetics.apply_to_weapon(model, PlayerProfile.weapon_finish_for(t))
			holder = Node3D.new()
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
		if holder:
			# one box per rack cell: the gun and its plate
			var cell_size = Vector3(w / GUN_COLS - 0.12, row_h - 0.04, 0.6)
			var centre = rack.position + cell + Vector3(0, -0.04, 0.1)
			var tip_title = "%s  ·  %s" % [tr(weapon.item_name), tr("Lv %d") % p.level]
			var pick = _add_pickable("gun", t, AABB(centre - cell_size / 2.0, cell_size), holder, tip_title, "Click: finishes")
			pick["plate"] = plate
			pick["plate_color"] = plate.modulate
			pick["anchor"] = rack.position + cell + Vector3(0, 0.16, 0.3)

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
		# the guide's entry for it (Encyclopedia._item_entries titles)
		var entry = SHELF_ENTRIES.get(shelf_items[i][0], "")
		if entry != "":
			_add_pickable("shelf", entry, _mesh_box(holder, 0.08), holder, entry, "Click: guide")

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
		var kind = PROP_KINDS.get(s[0], "")
		if kind != "":
			_add_pickable(kind, s[0], _mesh_box(model, 0.05), model, PROP_TITLES[kind], "Click: shop")

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
	_build_party_stage()

## A small second dais beside the hero's: empty until there is a free party slot, then it hosts
## its own glowing "+" (set_party_slot). Always built; hidden (ring off, "+" off) when not needed.
func _build_party_stage():
	var dais = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.62
	cyl.bottom_radius = 0.7
	cyl.height = 0.14
	cyl.radial_segments = 6
	dais.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.2, 0.24)
	mat.roughness = 0.55
	dais.material_override = mat
	dais.position = PARTY_SPOT + Vector3(0, _ground_y + 0.07, 0)
	viewport.add_child(dais)
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.66
	torus.rings = 5
	torus.ring_segments = 16
	ring.mesh = torus
	_party_ring_mat = _glow_material(UITheme.GOLD, 0.0)  # starts dark: no free slot yet
	ring.material_override = _party_ring_mat
	ring.position = PARTY_SPOT + Vector3(0, _ground_y + 0.15, 0)
	viewport.add_child(ring)
	_party_holder = Node3D.new()
	_party_holder.position = PARTY_SPOT + Vector3(0, _ground_y + 0.14, 0)
	viewport.add_child(_party_holder)

## Put a hero on the dais, in what they wear
func show_hero(data: CharacterData, skin: String, hat: String) -> void:
	if not _hero_holder:
		return
	hero_data = data
	for p in _pickables:
		if p.kind == "hero":
			p.data = data
			p.title = tr("%s  ·  Lv %d") % [tr(data.character_name), PlayerProfile.hero_progress(data.character_name).level]
	if _hover >= 0 and _pickables[_hover].kind == "hero":
		_fill_tooltip(_pickables[_hover])
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

## An empty dais with an inviting "+": no hero picked yet, or there is a free party slot. Clicking
## it emits invite_clicked (MainMenu opens FRIENDS) instead of hero_clicked.
func show_empty_slot() -> void:
	if not _hero_holder:
		return
	hero_data = null
	for p in _pickables:
		if p.kind == "hero":
			p.data = null
			p.title = tr("Invite a friend")
			p.action = tr("Click: friends")
	if _hover >= 0 and _pickables[_hover].kind == "hero":
		_fill_tooltip(_pickables[_hover])
	if _hero_model and is_instance_valid(_hero_model):
		_hero_model.queue_free()
		_hero_model = null
	_dais_glow.albedo_color = UITheme.GOLD
	_dais_glow.emission = UITheme.GOLD.lightened(0.2)
	if _plus_sign and is_instance_valid(_plus_sign):
		return  # already showing it
	_plus_sign = Node3D.new()
	_hero_holder.add_child(_plus_sign)
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.42
	torus.rings = 5
	torus.ring_segments = 16
	ring.mesh = torus
	var ring_mat = _glow_material(UITheme.GOLD, 1.6)
	ring.material_override = ring_mat
	ring.rotation_degrees.x = 90
	ring.position.y = 0.9
	_plus_sign.add_child(ring)
	for rot in [0.0, PI / 2.0]:  # a "+" out of two crossed bars
		var bar = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.38, 0.1, 0.1)
		bar.mesh = box
		bar.material_override = ring_mat
		bar.rotation.z = rot
		bar.position.y = 0.9
		_plus_sign.add_child(bar)
	_plus_sign.scale = Vector3.ZERO
	var pop = create_tween()
	pop.tween_property(_plus_sign, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

var _party_pick_index: int = -1  # the invite dais's entry in _pickables (set up once, shown / hidden)

## Shown when there is a real free spot to invite a friend into (MainMenu reads Online.party()):
## a small glowing "+" pedestal beside the hero. Hidden the rest of the time (solo with no party,
## or the party is already full) - its dais stands there dark and unclickable.
func set_party_slot(free: bool) -> void:
	if free == _party_visible:
		return
	_party_visible = free
	if free and _party_plus == null:
		_party_plus = Node3D.new()
		_party_holder.add_child(_party_plus)
		var ring_mat = _glow_material(UITheme.GOLD, 1.4)
		for part in [["ring", 0.0], ["bar1", 0.0], ["bar2", PI / 2.0]]:
			if part[0] == "ring":
				var ring = MeshInstance3D.new()
				var torus = TorusMesh.new()
				torus.inner_radius = 0.22
				torus.outer_radius = 0.28
				torus.rings = 5
				torus.ring_segments = 14
				ring.mesh = torus
				ring.material_override = ring_mat
				ring.rotation_degrees.x = 90
				ring.position.y = 0.55
				_party_plus.add_child(ring)
			else:
				var bar = MeshInstance3D.new()
				var box = BoxMesh.new()
				box.size = Vector3(0.26, 0.07, 0.07)
				bar.mesh = box
				bar.material_override = ring_mat
				bar.rotation.z = part[1]
				bar.position.y = 0.55
				_party_plus.add_child(bar)
		_party_plus.scale = Vector3.ZERO
	if _party_pick_index < 0:
		var pick = _add_pickable("invite", null, AABB(PARTY_SPOT + Vector3(-0.7, _ground_y, -0.7), Vector3(1.4, 1.1, 1.4)), _party_holder, tr("Invite a friend"), "Click: friends")
		_party_pick_index = _pickables.find(pick)
	if _party_plus:
		var t = create_tween()
		t.tween_property(_party_plus, "scale", Vector3.ONE if free else Vector3.ZERO, 0.35).set_trans(Tween.TRANS_BACK if free else Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

# ---------------------------------------------------------------- pointing and clicking

## A thing that can be pointed at: kind / data go out with the click signal, aabb (world) is what
## the mouse ray is tested against, node is what reacts
func _add_pickable(kind: String, data, aabb: AABB, node: Node3D, title: String, action: String) -> Dictionary:
	var pick = {
		"kind": kind, "data": data, "aabb": aabb, "node": node,
		"base_pos": node.position if node else Vector3.ZERO,
		"base_scale": node.scale if node else Vector3.ONE,
		"title": title, "action": action,
		"anchor": aabb.get_center() + Vector3(0, aabb.size.y / 2.0, 0),
	}
	_pickables.append(pick)
	return pick

## The box the hero (and the dais under them) is clicked by
func _hero_box() -> AABB:
	return AABB(HERO_SPOT + Vector3(-0.65, _ground_y, -0.65), Vector3(1.3, HERO_HEIGHT + 0.45, 1.3))

## World-space box around every visible mesh under a node (grown by pad)
func _mesh_box(node: Node3D, pad: float) -> AABB:
	var box := AABB()
	var first = true
	var meshes = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi in meshes:
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(node.global_position - Vector3(0.3, 0, 0.3), Vector3(0.6, 0.6, 0.6))
	return box.grow(pad)

## Which pickable is under this point of the container (-1: none): the nearest box the ray hits
func _pick(local: Vector2) -> int:
	if not camera or size.x < 1.0 or size.y < 1.0:
		return -1
	var vp_pos = local * Vector2(viewport.size) / size
	var origin = camera.project_ray_origin(vp_pos)
	var dir = camera.project_ray_normal(vp_pos)
	var best = -1
	var best_dist = INF
	for i in _pickables.size():
		if _pickables[i].kind == "invite" and not _party_visible:
			continue  # no free party slot right now: the dais stands there but can't be clicked
		for box in _pick_boxes(_pickables[i]):
			var hit = box.intersects_ray(origin, dir)
			if hit == null:
				continue
			var d = origin.distance_squared_to(hit)
			if d < best_dist:
				best_dist = d
				best = i
	return best

## The boxes a pickable is hit by: the hero by their own meshes as they stand now plus the flat
## dais (one box round both reached far past a small hero and took the shelf pickups and guns
## beside them), everything else by its one box
func _pick_boxes(p: Dictionary) -> Array:
	if p.kind == "hero" and _hero_model and is_instance_valid(_hero_model):
		var dais = AABB(HERO_SPOT + Vector3(-1.0, _ground_y, -1.0), Vector3(2.0, 0.22, 2.0))
		return [_mesh_box(_hero_model, 0.06), dais]
	return [p.aabb]

## What the mouse is over: "hero", "gun", "sign", "shelf", a container kind, or "" (MainMenu
## pauses its hero cycling while the hero is pointed at)
func hovered_kind() -> String:
	return String(_pickables[_hover].kind) if _hover >= 0 and _hover < _pickables.size() else ""

func _set_hover(index: int) -> void:
	if index == _hover:
		return
	if _hover >= 0 and _hover < _pickables.size():
		_hover_out(_pickables[_hover])
	_hover = index
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if index >= 0 else Control.CURSOR_ARROW
	if index >= 0:
		Sfx.ui("ui_hover")
		_hover_in(_pickables[index])
		_fill_tooltip(_pickables[index])

## A fresh tween for this node; the one it had stops (hover in / out / click don't fight)
func _tween_for(node: Node, parallel: bool = true) -> Tween:
	var old = _tweens.get(node)
	if old and old.is_valid():
		old.kill()
	var t = create_tween().set_parallel(parallel).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tweens[node] = t
	return t

## The pointed-at thing reacts: a gun slides out and grows, its plate brightens; the hero hops;
## props bounce; the sign swells
func _hover_in(p: Dictionary) -> void:
	var node: Node3D = p.node
	if not is_instance_valid(node) or _busy.has(node):
		return
	match p.kind:
		"hero":
			_hop(node, p.base_pos, 0.22, 0.32)
		"gun":
			var t = _tween_for(node)
			t.tween_property(node, "position", p.base_pos + Vector3(0, 0.06, 0.45), 0.22)
			t.tween_property(node, "scale", p.base_scale * 1.14, 0.22).set_trans(Tween.TRANS_BACK)
			t.tween_property(node, "rotation:x", 0.12, 0.22)  # muzzle tips up off the pegs
			if p.has("plate") and is_instance_valid(p.plate):
				t.tween_property(p.plate, "modulate", Color(1.0, 0.95, 0.75), 0.18)
		"sign":
			var t = _tween_for(node)
			t.tween_property(node, "scale", p.base_scale * 1.12, 0.25).set_trans(Tween.TRANS_BACK)
			t.tween_property(node, "modulate", Color(1.0, 0.95, 0.75), 0.2)
		"shelf":
			var t = _tween_for(node)
			t.tween_property(node, "position", p.base_pos + Vector3(0, 0.12, 0.08), 0.2)
			t.tween_property(node, "scale", p.base_scale * 1.18, 0.22).set_trans(Tween.TRANS_BACK)
		_:
			_hop(node, p.base_pos, 0.12, 0.3, p.base_scale)

func _hover_out(p: Dictionary) -> void:
	var node: Node3D = p.node
	if not is_instance_valid(node) or _busy.has(node):
		return
	match p.kind:
		"hero":
			pass  # the hop lands on its own
		"gun", "shelf":
			var t = _tween_for(node)
			t.tween_property(node, "position", p.base_pos, 0.25)
			t.tween_property(node, "scale", p.base_scale, 0.25)
			if p.kind == "gun":
				t.tween_property(node, "rotation:x", 0.0, 0.25)
			if p.has("plate") and is_instance_valid(p.plate):
				t.tween_property(p.plate, "modulate", p.plate_color, 0.25)
		"sign":
			var t = _tween_for(node)
			t.tween_property(node, "scale", p.base_scale, 0.25)
			t.tween_property(node, "modulate", Color(1.0, 0.85, 0.55), 0.25)

## A little jump with a squash on the way down and a stretch on the way up
func _hop(node: Node3D, base_pos: Vector3, height: float, time: float, base_scale: Vector3 = Vector3.ONE) -> Tween:
	var up = _tween_for(node, false)
	up.tween_property(node, "scale", base_scale * Vector3(1.12, 0.86, 1.12), time * 0.18).set_trans(Tween.TRANS_QUAD)
	up.tween_property(node, "scale", base_scale * Vector3(0.94, 1.1, 0.94), time * 0.25).set_trans(Tween.TRANS_QUAD)
	up.parallel().tween_property(node, "position:y", base_pos.y + height, time * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	up.tween_property(node, "position:y", base_pos.y, time * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	up.parallel().tween_property(node, "scale", base_scale, time * 0.4)
	up.tween_property(node, "scale", base_scale * Vector3(1.06, 0.94, 1.06), time * 0.1)
	up.tween_property(node, "scale", base_scale, time * 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return up

## Juice first (the hero jumps and spins, the gun pops off its pegs, a prop bounces), then the
## signal - MainMenu opens the screen a moment later
func _click(p: Dictionary) -> void:
	Sfx.ui("ui_click")
	var node: Node3D = p.node
	if is_instance_valid(node) and not _busy.has(node):
		_busy[node] = true
		var done: Tween
		match p.kind:
			"hero":
				done = _hop(node, p.base_pos, 0.6, 0.6)
				var spin = create_tween()
				_hero_spin = 0.0
				spin.tween_property(self, "_hero_spin", TAU, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			"gun":
				done = _tween_for(node, false)
				done.tween_property(node, "position", p.base_pos + Vector3(0, 0.25, 0.9), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				done.parallel().tween_property(node, "scale", p.base_scale * 1.3, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				done.parallel().tween_property(node, "rotation:x", 0.25, 0.18)
				done.tween_interval(0.35)
				done.tween_property(node, "position", p.base_pos, 0.3).set_trans(Tween.TRANS_CUBIC)
				done.parallel().tween_property(node, "scale", p.base_scale, 0.3)
				done.parallel().tween_property(node, "rotation:x", 0.0, 0.3)
			_:
				done = _hop(node, p.base_pos, 0.3, 0.42, p.base_scale)
		done.finished.connect(func():
			_busy.erase(node)
			if _hover >= 0 and _pickables[_hover].node == node and p.kind != "hero":
				_hover_in(p))  # still pointed at: back to the hover pose
	match p.kind:
		"hero":
			if p.data:
				hero_clicked.emit(p.data)
			else:
				invite_clicked.emit()  # the empty slot: p.data is null (show_empty_slot)
		"gun":
			gun_clicked.emit(int(p.data))
		"invite":
			invite_clicked.emit()  # the party's small second dais (set_party_slot)
		_:
			prop_clicked.emit(p.kind, p.data)

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		# the motion reached us: the scene itself is under the mouse (not a button over it)
		_mouse_in = true
		_mouse_local = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var index = _pick(event.position)
		if index >= 0:
			_set_hover(index)
			_click(_pickables[index])
			accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		_mouse_in = false
		_set_hover(-1)

## Hover follows the mouse and the leaning camera: picked again every frame while the mouse is
## over the scene itself (not over a button or an overlay on top of it)
func _update_hover() -> void:
	if not interactive or not is_visible_in_tree():
		_set_hover(-1)
		return
	# something else took the mouse (an overlay, a button) without a mouse-exit reaching us
	var vp = get_viewport()
	var over = vp.gui_get_hovered_control() if vp else null
	if over != null and over != self:
		_mouse_in = false
	if not _mouse_in:
		_set_hover(-1)
		return
	_set_hover(_pick(_mouse_local))

# ---------------------------------------------------------------- the tooltip

## A navy chip with a gold rim: the thing's name over what a click does
func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 10
	_tooltip.add_theme_stylebox_override("panel", UITheme.navy_box(Color(0.04, 0.06, 0.11, 0.94), Color(UITheme.GOLD, 0.85), 12, 16, 9))
	_tooltip.modulate.a = 0.0
	_tooltip.visible = false
	add_child(_tooltip)
	var box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	_tooltip.add_child(box)
	_tip_title = Label.new()
	_tip_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # translated when filled
	_tip_title.uppercase = true
	_tip_title.add_theme_font_override("font", UITheme.font_black())
	_tip_title.add_theme_font_size_override("font_size", UITheme.FONT_HEADING)
	_tip_title.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	box.add_child(_tip_title)
	_tip_action = Label.new()
	_tip_action.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_tip_action.uppercase = true
	_tip_action.add_theme_font_override("font", UITheme.font_black())
	_tip_action.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	_tip_action.add_theme_color_override("font_color", UITheme.GOLD)
	box.add_child(_tip_action)

func _fill_tooltip(p: Dictionary) -> void:
	if not _tooltip:
		return
	_tip_title.text = tr(String(p.title))
	_tip_action.text = "▸  " + tr(String(p.action))
	_tip_anchor = p.anchor
	_tooltip.reset_size()

## Eases in / out and sits by the thing it names, clamped inside the scene below the top bar
func _update_tooltip(delta: float) -> void:
	if not _tooltip:
		return
	var target = 1.0 if _hover >= 0 else 0.0
	_tip_alpha = move_toward(_tip_alpha, target, delta * (8.0 if target > 0.0 else 6.0))
	_tooltip.visible = _tip_alpha > 0.01
	if not _tooltip.visible or not camera:
		_tip_shown = false
		return
	_tooltip.modulate.a = _tip_alpha
	_tooltip.scale = Vector2.ONE * (0.9 + 0.1 * ease(_tip_alpha, 0.5))
	if camera.is_position_behind(_tip_anchor):
		_tooltip.visible = false
		return
	var at = camera.unproject_position(_tip_anchor) * size / Vector2(viewport.size).max(Vector2.ONE)
	var tip = _tooltip.size
	var pos = at + Vector2(-tip.x / 2.0, -tip.y - TOOLTIP_GAP)
	pos.x = clampf(pos.x, 12.0, maxf(12.0, size.x - tip.x - 12.0))
	pos.y = clampf(pos.y, ScreenHeader.CONTENT_TOP, maxf(ScreenHeader.CONTENT_TOP, size.y - tip.y - 12.0))
	_tooltip.pivot_offset = Vector2(tip.x / 2.0, tip.y)
	# glides from one thing to the next, appears right where it belongs
	if _tip_shown:
		_tooltip.position = _tooltip.position.lerp(pos, 1.0 - exp(-HOVER_EASE * delta))
	else:
		_tooltip.position = pos
	_tip_shown = true

## Where the front edge of the dais is on screen (container coordinates; MainMenu hangs the hero's
## nameplate under it)
func dais_screen_point() -> Vector2:
	if not camera:
		return size / 2.0
	var front = HERO_SPOT + Vector3(0, _ground_y, 1.05)
	return camera.unproject_position(front) * size / Vector2(viewport.size).max(Vector2.ONE)

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
	if interactive or _hover >= 0:
		_update_hover()
	_update_tooltip(delta)
	if _hero_holder:
		# turned to the camera, swaying a little (and one full turn on a click)
		_hero_holder.rotation.y = 0.35 + sin(_time * 0.6) * 0.25 + _hero_spin
	if _dais_glow:
		_hero_glow = move_toward(_hero_glow, 1.0 if hovered_kind() == "hero" else 0.0, delta * 4.0)
		_dais_glow.emission_energy_multiplier = 2.0 + _hero_glow * (2.6 + sin(_time * 6.0) * 0.4)
	for i in _bulbs.size():
		_bulbs[i].emission_energy_multiplier = 2.2 + sin(_time * 2.0 + i * 0.9) * 0.6
	if _plus_sign and is_instance_valid(_plus_sign):
		_plus_sign.position.y = 0.15 + sin(_time * 1.8) * 0.08  # bobs gently to invite a click
		_plus_sign.rotation.y = _time * 0.8
	if _party_visible and _party_ring_mat:
		var lit = 1.6 + (1.0 if hovered_kind() == "invite" else 0.0) + sin(_time * 2.4) * 0.3
		_party_ring_mat.emission_energy_multiplier = lit
	elif _party_ring_mat:
		_party_ring_mat.emission_energy_multiplier = 0.0
	if _party_plus and is_instance_valid(_party_plus) and _party_visible:
		_party_plus.position.y = sin(_time * 1.8 + 1.4) * 0.07
		_party_plus.rotation.y = _time * 0.8
