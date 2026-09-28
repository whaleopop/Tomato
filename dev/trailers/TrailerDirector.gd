## Trailer reels for future players: heroes and their abilities, weapons, containers and loot,
## the zone, the map events. Everything is the real game (same entities, abilities, loot and zone code), staged
## offline with a scripted camera and captions. Recorded by dev/trailers/record.gd with Godot's
## Movie Maker (see dev/trailers/README.md).
extends Node3D

const SAFE_TILE_HEIGHT: float = 0.45

var reel: String = "heroes"
var world: Node3D
var grid: HexGrid
var cam: Camera3D
var ui: CanvasLayer
var fader: ColorRect
var loot_spawner: LootSpawner

## The camera is driven through these two, tweened by the shots
var cam_pos: Vector3 = Vector3(0, 8, 10)
var cam_target: Vector3 = Vector3.ZERO
var cam_follow: Node3D = null
var cam_follow_offset: Vector3 = Vector3(0, 0.9, 0)

var _video_time: float = 0.0  # with --fixed-fps this is the time in the recorded video

## "MARK name 12.345" in the log: where the shots are (dev/trailers/highlights.py cuts by them)
func mark(what: String) -> void:
	print("MARK %s %.3f" % [what, _video_time])

func _process(delta: float):
	_video_time += delta
	if cam_follow and is_instance_valid(cam_follow):
		cam_target = cam_follow.global_position + cam_follow_offset
	if cam:
		cam.global_position = cam_pos
		if cam_pos.distance_to(cam_target) > 0.01:
			cam.look_at(cam_target, Vector3.UP)
		# ScreenEffects.shake moves the game camera; ours is placed every frame, so shake it here
		var shake = ScreenEffects.instance.shake_amount if ScreenEffects.instance else 0.0
		if shake > 0.0:
			cam.global_position += (cam.global_transform.basis.x * randf_range(-1.0, 1.0) + cam.global_transform.basis.y * randf_range(-1.0, 1.0)) * shake * 0.5

func run(p_reel: String) -> void:
	reel = p_reel
	_setup_common()
	match reel:
		"heroes":
			await _reel_heroes()
		"weapons":
			await _reel_weapons()
		"loot":
			await _reel_loot()
		"zone":
			await _reel_zone()
		"events":
			await _reel_events()
	await fade(1.0, 0.6)
	get_tree().quit()

# ================================================================ stage

func _setup_common():
	world = Node3D.new()
	world.name = "TrailerWorld"
	add_child(world)
	var env = load("res://world/GameEnvironment.gd").new()
	world.add_child(env)
	cam = Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.current = true

	ui = CanvasLayer.new()
	ui.layer = 20
	add_child(ui)
	fader = ColorRect.new()
	fader.color = Color(0.02, 0.03, 0.07, 1.0)
	fader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fader)
	var tag = UITheme.create_label("ROYALTIM", null, UITheme.FONT_SMALL)
	ui.add_child(tag)
	tag.add_theme_font_override("font", UITheme.font_black())
	tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	tag.position = Vector2(34, 26)

## Hand-made arena: grass in the middle, a pond, a beach, forest patches and the mountain rim
func build_arena(radius: int = 7) -> void:
	grid = HexGrid.new(radius)
	grid.name = "ArenaGrid"
	world.add_child(grid)
	var noise = FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.25
	var pond = [Vector2i(-4, 1), Vector2i(-4, 2), Vector2i(-5, 2), Vector2i(-3, 1)]
	for q in range(-radius, radius + 1):
		for r in range(max(-radius, -q - radius), min(radius, -q + radius) + 1):
			var c = Vector2i(q, r)
			var d = max(abs(q), abs(r), abs(q + r))
			var tile = HexTile.new()
			tile.hex_coords = c
			tile.position = grid.hex_to_world(c)
			var n = noise.get_noise_2d(q, r)
			tile.set_height(SAFE_TILE_HEIGHT + n * 0.12)
			var biome = HexTile.BiomeType.GRASS
			if d >= radius:
				biome = HexTile.BiomeType.MOUNTAIN
			elif c in pond:
				biome = HexTile.BiomeType.WATER if c != Vector2i(-3, 1) else HexTile.BiomeType.SHALLOW_WATER
			elif d >= radius - 1 and n > 0.1:
				biome = HexTile.BiomeType.FOREST
			elif d >= 3 and n < -0.35:
				biome = HexTile.BiomeType.BEACH
			tile.biome_type = biome
			if biome == HexTile.BiomeType.MOUNTAIN:
				tile.can_spawn = false
			grid.add_tile(c, tile)
	grid.update_tile_edges()
	var ripples = WaterRipples.new()
	ripples.grid = grid
	world.add_child(ripples)
	# A bit of cover as scenery
	var cover = CoverSpawner.new()
	world.add_child(cover)
	cover.hex_grid = grid
	for pair in [[Vector2i(2, -4), Vector2i(3, -4), CoverWall.Kind.STONE], [Vector2i(-2, -3), Vector2i(-2, -2), CoverWall.Kind.WOOD],
			[Vector2i(4, 0), Vector2i(4, 1), CoverWall.Kind.SANDBAG], [Vector2i(-1, 4), Vector2i(0, 4), CoverWall.Kind.STONE]]:
		cover._spawn_wall(grid.get_tile(pair[0]), grid.get_tile(pair[1]), pair[2])
	for c in [Vector2i(3, -2), Vector2i(-4, -1), Vector2i(1, 3), Vector2i(-2, 5)]:
		cover._place_bush(c, grid.get_tile(c))
	loot_spawner = LootSpawner.new()
	world.add_child(loot_spawner)
	loot_spawner.hex_grid = grid

func tile_top(c: Vector2i) -> Vector3:
	var tile = grid.get_tile(c)
	return grid.hex_to_world(c) + Vector3(0, CoverSpawner.tile_top(tile) if tile else 0.3, 0)

func spawn_hero(data: CharacterData, pos: Vector3, face: Vector3 = Vector3(0, 0, 10), drop_in: bool = false) -> Player:
	var p = Player.new()
	p.name = "Trailer_%s_%d" % [data.character_name, randi() % 10000]
	world.add_child(p)
	p.setup_character(data)
	p.spawn(pos + Vector3(0, 0.2, 0))
	var animator = p.get_node_or_null("Animator")
	if animator and not drop_in:  # already standing there, no drop from the sky
		animator.set("_spawn_delay", -1.0)
		animator.set("_spawn_t", -1.0)
		if animator.pivot:
			animator.pivot.visible = true
	face_to(p, face)
	return p

func face_to(p: Node3D, point: Vector3):
	var d = point - p.global_position
	d.y = 0.0
	if d.length_squared() > 0.01:
		p.rotation.y = atan2(d.x, d.z)

func clear_world_players():
	for p in get_tree().get_nodes_in_group("players"):
		p.queue_free()

# ================================================================ camera and captions

func cam_to(pos: Vector3, target: Vector3, time: float, trans: int = Tween.TRANS_SINE) -> Tween:
	cam_follow = null
	var t = create_tween().set_parallel(true).set_trans(trans).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "cam_pos", pos, time)
	t.tween_property(self, "cam_target", target, time)
	return t

func cam_cut(pos: Vector3, target: Vector3):
	cam_follow = null
	cam_pos = pos
	cam_target = target

## Slow circle around `center`
func orbit(center: Vector3, radius: float, height: float, from_deg: float, to_deg: float, time: float) -> Tween:
	cam_follow = null
	cam_target = center
	var t = create_tween()
	t.tween_method(func(a: float):
		cam_pos = center + Vector3(sin(deg_to_rad(a)) * radius, height, cos(deg_to_rad(a)) * radius)
		cam_target = center, from_deg, to_deg, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return t

func fade(to_alpha: float, time: float) -> void:
	var t = create_tween()
	t.tween_property(fader, "color:a", to_alpha, time)
	await t.finished

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

## Big centered chapter title
func chapter(title: String, subtitle: String, seconds: float, accent: Color = UITheme.ACCENT_PRIMARY, top: bool = false) -> void:
	var holder = CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if top:
		holder.anchor_bottom = 0.42
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(holder)
	var col = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	holder.add_child(col)
	var pill = UITheme.create_pill("ROYALTIM", accent, col)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var t = UITheme.create_hero_title(title, col)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 96)
	t.add_theme_color_override("font_shadow_color", Color(accent, 0.5))
	if subtitle != "":
		var s = UITheme.create_subtitle(subtitle, col)
		s.add_theme_font_size_override("font_size", 30)
		s.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	holder.modulate.a = 0.0
	holder.scale = Vector2(1.08, 1.08)
	holder.pivot_offset = get_viewport().get_visible_rect().size / 2.0
	var tw = create_tween().set_parallel(true)
	tw.tween_property(holder, "modulate:a", 1.0, 0.35)
	tw.tween_property(holder, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(max(0.1, seconds - 0.8))
	tw.chain().tween_property(holder, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(holder.queue_free)

## Lower-third card: name (colored), lines of text and chips
func lower_third(title: String, lines: Array, pills: Array, color: Color, seconds: float, right: bool = false) -> void:
	var card = PanelContainer.new()
	var box = UITheme.glass_box(Color(0.04, 0.05, 0.1, 0.78), Color(color, 0.75), 24, 30, 20)
	box.shadow_color = Color(color, 0.35)
	box.shadow_size = 22
	card.add_theme_stylebox_override("panel", box)
	card.custom_minimum_size = Vector2(620, 0)
	ui.add_child(card)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	if not pills.is_empty():
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		for p in pills:
			UITheme.create_pill(p[0], p[1], row)
	var t = UITheme.create_hero_title(title, col)
	t.add_theme_font_size_override("font_size", 64)
	t.add_theme_color_override("font_color", color.lightened(0.35))
	t.add_theme_color_override("font_shadow_color", Color(color, 0.5))
	for line in lines:
		var l = UITheme.create_label(line, col, 26)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 560
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.88))
	await get_tree().process_frame
	var screen = get_viewport().get_visible_rect().size
	var x_in = screen.x - card.size.x - 70 if right else 70.0
	card.position = Vector2(x_in + (80 if right else -80), screen.y - card.size.y - 80)
	card.modulate.a = 0.0
	var tw = create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.3)
	tw.tween_property(card, "position:x", x_in, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(max(0.1, seconds - 0.75))
	tw.chain().tween_property(card, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(card.queue_free)

func _ground_at(pos: Vector3) -> Vector3:
	var c = grid.world_to_hex(pos)
	return Vector3(pos.x, tile_top(c).y, pos.z)

## The same pill at the bottom center (the zone reel shows the HUD at the top)
func bottom_caption(text: String, color: Color, seconds: float) -> void:
	top_caption(text, color, seconds, true)

## Small caption at the top ("F - Томатный всплеск")
func top_caption(text: String, color: Color, seconds: float, bottom: bool = false) -> void:
	var holder = CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM if bottom else Control.PRESET_CENTER_TOP)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if bottom:
		holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
		holder.offset_bottom = -70
	else:
		holder.offset_top = 60
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(holder)
	var pill = PanelContainer.new()
	var box = UITheme.glass_box(Color(0.04, 0.05, 0.1, 0.8), Color(color, 0.8), 99, 30, 12)
	box.shadow_color = Color(color, 0.35)
	box.shadow_size = 16
	pill.add_theme_stylebox_override("panel", box)
	holder.add_child(pill)
	var l = UITheme.create_heading(text, pill)
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", color.lightened(0.4))
	holder.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.25)
	tw.tween_interval(max(0.1, seconds - 0.55))
	tw.tween_property(holder, "modulate:a", 0.0, 0.3)
	tw.tween_callback(holder.queue_free)

# ================================================================ reels

## Camera spot `offset` from `subject`, looking past it so the subject sits left (shift > 0)
## or right (shift < 0) of the frame center - room for a caption card on the other side
func framed(subject: Vector3, offset: Vector3, shift: float) -> Array:
	var pos = subject + offset
	var forward = (subject - pos).normalized()
	var right = forward.cross(Vector3.UP).normalized()
	return [pos, subject + right * shift]

func _reel_heroes() -> void:
	build_arena(7)
	var roster = CharacterRegistry.get_all()
	cam_cut(Vector3(0, 7, 14), Vector3(0, 0.5, 0))
	orbit(Vector3(0, 0.5, 0), 14.0, 7.0, -20.0, 20.0, 4.0)
	await fade(0.0, 0.8)
	chapter(tr("Heroes"), tr("%d veggies, each with its own trick") % roster.size(), 3.0)
	await wait(3.2)

	var spot = tile_top(Vector2i(0, 0))
	var partner_spot = spot + Vector3(2.7, 0, 1.3)  # within reach of the melee abilities too
	for i in roster.size():
		var data: CharacterData = roster[i]
		var partner_data: CharacterData = roster[(i + 5) % roster.size()]
		var hero = spawn_hero(data, spot, spot + Vector3(-0.8, 0, 3.0))
		var partner = spawn_hero(partner_data, partner_spot, spot)
		partner.visible = false
		mark("hero_%s" % data.character_name.to_lower().replace(" ", "_"))
		# 1) close-up: the hero drops in on the right, its card on the left
		var a = framed(spot + Vector3(0, 0.75, 0), Vector3(-0.2, 0.55, 3.2), -0.95)
		var b = framed(spot + Vector3(0, 0.75, 0), Vector3(-0.1, 0.4, 2.6), -0.8)
		cam_cut(a[0], a[1])
		cam_to(b[0], b[1], 2.5)
		lower_third(tr(data.character_name), [tr(data.description)],
			[[tr("%d HP") % int(data.base_health), UITheme.ACCENT_SUCCESS], [tr("Speed %.1f") % data.base_speed, UITheme.ACCENT_INFO]],
			data.color, 2.5)
		await wait(2.55)
		mark("ability_%s" % data.character_name.to_lower().replace(" ", "_"))
		# 2) the active ability on a sparring partner: the pair on the left, the card on the right
		partner.visible = true
		face_to(hero, partner.global_position)
		face_to(partner, hero.global_position)
		var mid = (spot + partner.global_position) / 2.0 + Vector3(0, 0.6, 0)
		var c = framed(mid, Vector3(-1.6, 2.3, 5.2), 1.7)
		cam_cut(c[0], c[1])
		var d = framed(mid, Vector3(-1.2, 2.0, 4.6), 1.5)
		cam_to(d[0], d[1], 3.2)
		if data.active_ability:
			lower_third(tr(data.active_ability.ability_name), [tr(data.active_ability.description)],
				[[tr("Active · F"), UITheme.ACCENT_SECONDARY], [tr("Cooldown: %d s") % int(round(data.active_ability.cooldown)), Color(1, 1, 1, 0.7)]],
				data.color, 3.2, true)
		await wait(0.35)
		var abilities = hero.get_component("AbilityComponent")
		if abilities:
			abilities.activate_ability(0, partner.global_position)
		await wait(2.9)
		# 3) the passive, back on the hero
		var e = framed(hero.global_position + Vector3(0, 0.75, 0), Vector3(0.6, 0.6, 3.0), -0.9)
		cam_cut(e[0], e[1])
		face_to(hero, e[0])
		if data.passive_ability:
			lower_third(tr(data.passive_ability.ability_name), [tr(data.passive_ability.description)],
				[[tr("Passive"), UITheme.ACCENT_BEET]], UITheme.ACCENT_BEET, 1.9)
		var f = framed(hero.global_position + Vector3(0, 0.75, 0), Vector3(0.9, 0.5, 2.6), -0.8)
		cam_to(f[0], f[1], 1.9)
		await wait(1.9)
		await fade(1.0, 0.16)
		hero.queue_free()
		partner.queue_free()
		for n in world.find_children("*", "Node3D", true, false):
			if n is FireTrail:
				n.queue_free()
		await wait(0.05)
		await fade(0.0, 0.16)

	mark("lineup")
	# Everyone together: two rows, the title on top
	var front_row = 6
	for i in roster.size():
		var back = i >= front_row
		var idx = i - front_row if back else i
		var count = roster.size() - front_row if back else front_row
		var x = (idx - (count - 1) / 2.0) * 1.3
		var z = -1.5 if back else 0.0
		var pos = spot + Vector3(x, 0, z + 1.0)
		spawn_hero(roster[i], pos, pos + Vector3(x * 0.15, 0, 8))
	cam_cut(spot + Vector3(0, 1.0, 5.4), spot + Vector3(0, 0.95, 0.5))
	cam_to(spot + Vector3(0, 1.5, 7.2), spot + Vector3(0, 0.85, 0.5), 5.0)
	await wait(1.2)
	chapter(tr("Pick yours"), tr("The last veggie standing wins"), 3.6, UITheme.ACCENT_PRIMARY, true)
	await wait(4.0)

func _reel_weapons() -> void:
	build_arena(7)
	var shooter_spot = _ground_at(Vector3(-3.6, 0, 0.2))
	var targets_at = [_ground_at(Vector3(3.6, 0, -1.7)), _ground_at(Vector3(4.3, 0, 0.1)), _ground_at(Vector3(3.5, 0, 1.9))]
	cam_cut(Vector3(-2, 5, 12), shooter_spot)
	await fade(0.0, 0.8)
	chapter(tr("Weapons"), tr("Five guns, and each one changes how far you see"), 3.0, UITheme.ACCENT_SECONDARY)
	await wait(3.2)
	var roster = CharacterRegistry.get_all()
	var shooter_data = CharacterRegistry.get_by_name("Carrot")
	var total_weight = 0
	for w in LootContainer.WEAPON_WEIGHTS.values():
		total_weight += w
	var n = 0
	for type in RangedWeapon.WeaponType.values():
		var weapon = RangedWeapon.create_weapon(type)
		var shooter = spawn_hero(shooter_data, shooter_spot, targets_at[1])
		var dummies = []
		for k in targets_at.size():
			var dummy = spawn_hero(roster[(n * 3 + k + 2) % roster.size()], targets_at[k], shooter_spot)
			dummy.get_component("HealthComponent").set_max_health(900.0, true)  # stand through the demo
			dummies.append(dummy)
		n += 1
		var inventory = shooter.get_component("InventoryComponent")
		var slot = inventory.add_weapon_to_slot(weapon)
		inventory.add_item(AmmoItem.new(weapon.ammo_type, 300))
		inventory.switch_weapon_slot(slot)
		face_to(shooter, targets_at[1])
		var mid = (shooter_spot + targets_at[1]) / 2.0
		mark("weapon_" + RangedWeapon.WeaponType.keys()[type].to_lower())
		cam_cut(mid + Vector3(-1.2, 2.3, 8.4), mid + Vector3(-0.8, 0.45, 0))
		cam_to(mid + Vector3(-0.4, 2.0, 7.2), mid + Vector3(-0.3, 0.5, 0), 4.6)
		var share = float(LootContainer.WEAPON_WEIGHTS.get(type, 0)) / max(total_weight, 1)
		var rarity = "Common" if share >= 0.24 else ("Uncommon" if share >= 0.14 else "Rare")
		var damage_text = ("%d × %d" % [int(weapon.damage), weapon.pellet_count]) if weapon.pellet_count > 1 else "%d" % int(weapon.damage)
		lower_third(tr(weapon.item_name), [
			tr("Damage per shot") + ": " + damage_text + "   ·   " + tr("Shots per second") + ": " + str(snappedf(1.0 / weapon.fire_rate, 0.1)).trim_suffix(".0"),
			tr("Range") + ": " + tr("%d m") % int(weapon.range) + "   ·   " + tr("Sight") + ": " + tr("%d m") % int(weapon.visibility_range),
		], [[tr(rarity), UITheme.ACCENT_INFO], [tr(AmmoItem.get_ammo_type_name(weapon.ammo_type)), UITheme.ACCENT_SECONDARY]], UITheme.ACCENT_SECONDARY, 4.6)
		# Shoot at the dummies for a while
		var combat = shooter.get_component("CombatComponent")
		var t := 0.0
		var k = 0
		while t < 4.4:
			var target = dummies[k % dummies.size()]
			if is_instance_valid(target):
				face_to(shooter, target.global_position)
				if combat.can_attack():
					if combat.attack(target.global_position + Vector3(0, 0.8, 0)):
						if not weapon.is_continuous_fire() or randf() < 0.1:
							k += 1
			await get_tree().process_frame
			t += get_process_delta_time()
		await fade(1.0, 0.2)
		shooter.queue_free()
		for d in dummies:
			if is_instance_valid(d):
				d.queue_free()
		await wait(0.05)
		await fade(0.0, 0.2)
	cam_cut(Vector3(0, 9, 13), Vector3(0, 0, 0))
	orbit(Vector3(0, 0, 0), 14.0, 8.0, 0.0, 40.0, 3.5)
	chapter(tr("Find them in containers"), tr("Every veggie lands with a pistol"), 3.2, UITheme.ACCENT_SECONDARY)
	await wait(3.5)

func _reel_loot() -> void:
	build_arena(7)
	cam_cut(Vector3(0, 6, 11), Vector3(0, 0.3, 0))
	await fade(0.0, 0.8)
	chapter(tr("Containers and loot"), tr("Walk up, press E - and grab what flies out"), 3.0, UITheme.ACCENT_INFO)
	await wait(3.2)
	var hero = spawn_hero(CharacterRegistry.get_by_name("Pineapple"), tile_top(Vector2i(-1, 2)), tile_top(Vector2i(0, 0)))
	var types = [
		[LootContainer.ContainerType.CRATE, "Crate", Vector2i(1, -1), 11],
		[LootContainer.ContainerType.BARREL, "Barrel", Vector2i(-2, 0), 23],
		[LootContainer.ContainerType.CHEST, "Chest", Vector2i(0, 0), 37],
	]
	for c in types:
		var container = loot_spawner._create_container(c[0])
		container.loot_seed = c[3]
		loot_spawner.add_child(container)
		container.global_position = tile_top(c[2])
		var p = container.global_position
		mark("container_" + c[1].to_lower())
		cam_cut(p + Vector3(2.6, 1.6, 3.4), p + Vector3(0, 0.4, 0))
		cam_to(p + Vector3(1.6, 2.4, 4.4), p + Vector3(0, 0.3, 0), 3.6)
		var info = tr("%d items") % container.loot_count if container.loot_count > 1 else tr("1 item")
		var lines = [info]
		if container.guaranteed_health:
			lines.append(tr("One of them is a health pack"))
		lower_third(tr(c[1]), lines, [], Color(0.95, 0.75, 0.45), 3.6)
		await wait(0.9)
		container.interact(null)
		await wait(2.9)
	# Pickups: the pineapple walks through the loot
	top_caption(tr("Health packs, shields, ability crystals, ammo, guns"), UITheme.ACCENT_SUCCESS, 3.4)
	var items = get_tree().get_nodes_in_group("loot_items")
	var health = hero.get_component("HealthComponent")
	health.take_damage(60.0, null)
	cam_follow = hero
	cam_follow_offset = Vector3(0, 0.6, 0)
	var mv = hero.get_component("MovementComponent")
	var t := 0.0
	while t < 5.5:
		var goal = null
		for it in items:
			if is_instance_valid(it) and it.is_inside_tree() and it.get("is_active"):
				if goal == null or it.global_position.distance_to(hero.global_position) < goal.global_position.distance_to(hero.global_position):
					goal = it
		if goal:
			var d = goal.global_position - hero.global_position
			d.y = 0
			mv.set_move_direction(d.normalized())
			face_to(hero, goal.global_position)
		else:
			mv.set_move_direction(Vector3.ZERO)
		cam_pos = cam_pos.lerp(hero.global_position + Vector3(0.8, 3.4, 4.6), 0.06)
		await get_tree().process_frame
		t += get_process_delta_time()
	mv.set_move_direction(Vector3.ZERO)
	# Supply drop
	var drop_at = tile_top(Vector2i(2, 1))
	var drop = loot_spawner.spawn_supply_drop_at(drop_at, 777)
	mark("supply_drop")
	cam_cut(drop_at + Vector3(4.5, 2.2, 7.0), drop_at + Vector3(0, 16.0, 0))
	cam_follow = drop
	cam_follow_offset = Vector3(0, -0.6, 0)
	top_caption(tr("Supply Drop") + ": " + tr("Falls from the sky every minute of the match"), UITheme.ACCENT_PRIMARY, 4.2)
	await wait(4.4)
	cam_to(drop_at + Vector3(3.6, 2.0, 5.6), drop_at + Vector3(0, 0.5, 0), 0.8)
	lower_third(tr("Supply Drop"), [tr("%d items") % 4, tr("One of them is a health pack")], [[tr("Rare"), UITheme.ACCENT_PRIMARY]], UITheme.ACCENT_PRIMARY, 3.0)
	drop.interact(null)
	await wait(3.2)
	orbit(drop_at, 9.0, 5.0, 30.0, 80.0, 3.2)
	chapter(tr("Loot fast"), tr("The zone won't wait"), 3.0, UITheme.ACCENT_INFO)
	await wait(3.3)

func _reel_zone() -> void:
	var map_gen = MapGenerator.new()
	world.add_child(map_gen)
	grid = await map_gen.generate_map(MapGenerator.MATCH_MAP_RADIUS, 424242)
	var seed_value = map_gen.get_map_seed()
	loot_spawner = LootSpawner.new()
	world.add_child(loot_spawner)
	loot_spawner.setup(grid, seed_value)
	loot_spawner.spawn_initial_containers()
	var cover = CoverSpawner.new()
	world.add_child(cover)
	cover.setup(grid, seed_value, CoverSpawner.container_tiles(grid, loot_spawner))
	var ds = DestructionSystem.new()
	world.add_child(ds)
	ds.start(grid)
	ds.stage_left = 1000.0

	# A few heroes around the island, one of them "you" with the HUD
	var roster = CharacterRegistry.get_all()
	var heroes = []
	var edge_tiles = ds._tiles_outside(ds._radius - 1)
	var you_tile = grid.get_tile(edge_tiles[edge_tiles.size() / 2]) if not edge_tiles.is_empty() else grid.get_tile(Vector2i(0, 0))
	var center_world = grid.hex_to_world(ds.center)
	var you = spawn_hero(roster[7], you_tile.global_position + Vector3(0, 0.4, 0), center_world)
	heroes.append(you)
	for i in 5:
		var c = edge_tiles[(i * 7 + 3) % max(edge_tiles.size(), 1)] if not edge_tiles.is_empty() else Vector2i(i, 0)
		var t = grid.get_tile(c)
		heroes.append(spawn_hero(roster[(i * 2 + 1) % roster.size()], t.global_position + Vector3(0, 0.4, 0), center_world))
	var hud = PlayerHUD.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud_layer.add_child(hud)
	await get_tree().process_frame
	hud.setup(you, grid)
	for part in [hud.weapon_slots_ui, hud.ammo_display, hud.ability_bar, hud.crosshair]:
		if part:
			part.visible = false

	# The island
	cam_cut(Vector3(0, 60, 55), Vector3(0, 0, 0))
	cam_to(Vector3(0, 48, 40), Vector3(0, 0, 2), 4.5)
	await fade(0.0, 0.8)
	chapter(tr("The zone"), tr("The island closes in - and there is no falling off"), 3.2, UITheme.ACCENT_DANGER)
	await wait(4.0)
	# Warning
	mark("zone_warn")
	ds.stage_left = 0.02
	await wait(0.2)
	var p = you.global_position
	var inward = center_world - p
	inward.y = 0
	inward = inward.normalized()
	var side = inward.cross(Vector3.UP)
	cam_to(p + inward * 8.0 + side * 1.5 + Vector3(0, 5.0, 0), p + Vector3(0, 0.8, 0) - inward * 1.5, 2.2)
	bottom_caption(tr("The next ring glows - you have a few seconds"), UITheme.ACCENT_WARNING, 3.8)
	await wait(4.2)
	# Fire: everyone runs to the middle, "you" a bit late
	mark("zone_burn")
	ds.stage_left = 0.02
	await wait(0.1)
	bottom_caption(tr("Then it burns"), UITheme.ACCENT_DANGER, 3.0)
	for h in heroes:
		if h != you and is_instance_valid(h):
			var d = center_world - h.global_position
			d.y = 0
			h.get_component("MovementComponent").set_move_direction(d.normalized())
	cam_to(p + inward * 6.5 + side * 1.0 + Vector3(0, 3.6, 0), p + Vector3(0, 0.9, 0) - inward * 1.0, 3.0)
	await wait(1.6)
	var mv = you.get_component("MovementComponent")
	var run_dir = center_world - you.global_position
	run_dir.y = 0
	mv.set_move_direction(run_dir.normalized() * 0.001)  # face, stand still: the mountain will shove
	await wait(2.4)
	# Mountains
	mark("zone_rise")
	for h in heroes:
		if is_instance_valid(h):
			h.get_component("MovementComponent").set_move_direction(Vector3.ZERO)
	ds.stage_left = 0.02
	await wait(0.1)
	bottom_caption(tr("Mountains rise and shove everyone inwards"), Color(0.9, 0.82, 0.72), 3.4)
	cam_to(p + inward * 11.0 + side * 5.0 + Vector3(0, 7.0, 0), p + inward * 1.5 + Vector3(0, 0.8, 0), 3.4)
	await wait(3.6)
	# "You" sits the rest out safe in the middle (the HUD must not show the death screen)
	you.get_component("HealthComponent").set_invulnerable(true)
	you.global_position = grid.hex_to_world(ds.center) + Vector3(0, CoverSpawner.tile_top(grid.get_tile(ds.center)) + 0.3, 0)
	# Fast-forward from above
	mark("zone_aerial")
	bottom_caption(tr("Ring after ring, towards a random spot"), UITheme.ACCENT_WARNING, 5.0)
	cam_follow = null
	cam_to(Vector3(center_world.x, 55, center_world.z + 42), center_world, 3.0)
	ds.time_scale = 22.0
	await wait(6.5)
	ds.time_scale = 1.0
	# The core
	while not ds.core_mode and ds.is_active:
		ds.stage_left = 0.02
		await wait(0.35)
		if ds.stage == DestructionSystem.Stage.WAIT and not ds.core_mode:
			continue
	# Three more for the final fight in the burning core
	for i in 3:
		var a = TAU * i / 3.0
		var pos = center_world + Vector3(cos(a), 0, sin(a)) * 2.4
		pos.y = CoverSpawner.tile_top(grid.get_tile(grid.world_to_hex(pos))) if grid.get_tile(grid.world_to_hex(pos)) else center_world.y + 0.3
		var fighter = spawn_hero(roster[(i * 4 + 2) % roster.size()], pos, center_world)
		fighter.get_component("HealthComponent").set_max_health(400.0, true)
	ds.stage_left = 0.02  # the core warning is up: straight on to the fire
	await wait(0.2)
	mark("zone_core")
	cam_to(center_world + Vector3(-7, 8, 10), center_world, 2.0)
	bottom_caption(tr("At the end even the core burns: fight!"), UITheme.ACCENT_DANGER, 3.8)
	await wait(4.2)
	chapter("ROYALTIM", tr("The last veggie standing wins"), 3.4, UITheme.ACCENT_PRIMARY)
	await wait(3.6)

# ---------------------------------------------------------------- map events

## A playable land tile exactly `dist` hexes from `c` (the first in sorted order after `skip` of them)
func _tile_at(c: Vector2i, dist: int, skip: int = 0) -> Vector2i:
	var found: Array = []
	for other in grid.tiles:
		var t = grid.get_tile(other)
		if t and t.is_playable() and not t.is_water() and DestructionSystem._dist(other, c) == dist:
			found.append(other)
	found.sort()
	return found[skip % found.size()] if not found.is_empty() else c

func _stop_all(heroes: Array) -> void:
	for h in heroes:
		if is_instance_valid(h):
			h.get_component("MovementComponent").set_move_direction(Vector3.ZERO)

func _run_to(h: Player, point: Vector3) -> void:
	var d = point - h.global_position
	d.y = 0.0
	face_to(h, point)
	h.get_component("MovementComponent").set_move_direction(d.normalized())

func _reel_events() -> void:
	var map_gen = MapGenerator.new()
	world.add_child(map_gen)
	grid = await map_gen.generate_map(MapGenerator.MATCH_MAP_RADIUS, 424242)
	var seed_value = map_gen.get_map_seed()
	loot_spawner = LootSpawner.new()
	world.add_child(loot_spawner)
	loot_spawner.setup(grid, seed_value)
	var cover = CoverSpawner.new()
	world.add_child(cover)
	cover.setup(grid, seed_value, CoverSpawner.container_tiles(grid, loot_spawner))
	var ds = DestructionSystem.new()
	world.add_child(ds)
	ds.start(grid)
	ds.stage_left = 1000.0
	var events = MapEvents.new()
	world.add_child(events)
	events.setup(grid, cover, true)
	var director = MapEventDirector.new()
	world.add_child(director)
	director.setup(grid, ds, events, loot_spawner, cover)
	director.rng.seed = 5150
	director.is_active = true
	director._next = 1.0e9  # no events of its own: the shots call them

	var roster = CharacterRegistry.get_all()
	var center_world = grid.hex_to_world(ds.center)
	var you_c = _tile_at(ds.center, 2)
	var you = spawn_hero(roster[7], tile_top(you_c), center_world)
	you.is_local_player = true  # the night lantern, the HUD bonus pill
	var heroes = [you]
	for i in 3:
		heroes.append(spawn_hero(roster[(i * 3 + 2) % roster.size()], tile_top(_tile_at(you_c, 1, i * 2)), you.global_position))
	for h in heroes:
		h.get_component("HealthComponent").set_max_health(600.0, true)
	var hud = PlayerHUD.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud_layer.add_child(hud)
	await get_tree().process_frame
	hud.setup(you, grid)
	for part in [hud.weapon_slots_ui, hud.ammo_display, hud.ability_bar, hud.crosshair]:
		if part:
			part.visible = false

	# The island
	cam_cut(Vector3(center_world.x, 60, center_world.z + 55), center_world)
	cam_to(Vector3(center_world.x, 44, center_world.z + 36), center_world + Vector3(0, 0, 2), 4.5)
	await fade(0.0, 0.8)
	chapter(tr("Map events"), tr("The island won't let you sit still"), 3.2, UITheme.ACCENT_WARNING)
	await wait(4.0)

	# Meteors: red circles around the group, they scatter, the rocks come down
	mark("ev_meteors")
	var p = you.global_position
	cam_to(p + Vector3(-3.0, 9.5, 11.5), p + Vector3(0.5, 0, -1.0), 1.8)
	await wait(1.4)
	var points: Array = []
	for h in heroes:
		points.append(_ground_at(h.global_position + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))))
	for i in 3:
		var a = TAU * i / 3.0 + 0.4
		points.append(_ground_at(p + Vector3(cos(a), 0, sin(a)) * 6.0))
	var delays: Array = []
	for i in points.size():
		delays.append(2.4 + i * 0.28)
	director.send("meteors", {"points": points, "delays": delays})
	bottom_caption(tr("Meteor shower: red circles, then rocks from the sky"), UITheme.ACCENT_DANGER, 5.0)
	await wait(1.0)
	for i in heroes.size():
		var h = heroes[i]
		if i % 2 == 0:
			var a = TAU * i / heroes.size()
			_run_to(h, h.global_position + Vector3(cos(a), 0, sin(a)) * 5.0)
	await wait(0.8)
	_stop_all(heroes)
	await wait(3.6)

	# Earthquake next to the walls
	mark("ev_quake")
	var walls: Array = []
	for w in cover.walls:
		if is_instance_valid(w) and not w._falling:
			walls.append(w)
	var focus_wall = walls[0]
	var best = -1
	for w in walls:
		if w.global_position.distance_to(center_world) > 26.0:
			continue
		var near = 0
		for o in walls:
			if o.global_position.distance_to(w.global_position) < 8.0:
				near += 1
		if near > best:
			best = near
			focus_wall = w
	var f = focus_wall.global_position
	walls.sort_custom(func(a, b): return a.global_position.distance_to(f) < b.global_position.distance_to(f))
	var falling: Array = []
	for i in min(7, walls.size()):
		falling.append([String(walls[i].name), 0.7 + i * 0.55])
	for i in 3:
		heroes[i + 1].global_position = _ground_at(f + Vector3(-2.5 + i * 2.5, 0, 2.2)) + Vector3(0, 0.2, 0)
		face_to(heroes[i + 1], f)
	cam_cut(f + Vector3(-2.5, 7.0, 10.5), f + Vector3(0, 0.3, 0))
	await wait(0.5)
	director.send("quake", {"seconds": 5.0, "walls": falling})
	bottom_caption(tr("Earthquake: walls fall, aim shakes"), Color(0.92, 0.76, 0.52), 5.0)
	await wait(5.6)

	# Night, then fog: the fog of war closes in
	mark("ev_night")
	for i in 3:
		heroes[i + 1].global_position = tile_top(_tile_at(you_c, 1, i * 2)) + Vector3(0, 0.2, 0)
	var vis = VisibilitySystem.new()
	world.add_child(vis)
	vis.setup(grid)
	for c in grid.tiles:  # the whole island already explored: dim outside your sight, no clouds
		vis.explored[c] = true
	vis.explored_count = grid.tiles.size()
	vis.register_source(you)
	vis.local_player = you
	cam_to(p + Vector3(-2.0, 12.0, 13.0), p + Vector3(0, 0, -1.0), 1.5)
	await wait(1.8)
	director.send("night", {"seconds": 25.0, "style": "night"})
	bottom_caption(tr("Night: everyone sees half as far"), Color(0.62, 0.72, 1.0), 4.2)
	await wait(4.6)
	events._night_left = 0.01
	hud._event_left = 0.0
	await wait(0.6)
	director.send("night", {"seconds": 25.0, "style": "fog"})
	bottom_caption(tr("Or thick fog - bushes hide you even better"), Color(0.82, 0.86, 0.92), 3.8)
	await wait(4.0)
	events._night_left = 0.01
	hud._event_left = 0.0
	await wait(0.4)
	vis.queue_free()

	# Flood at the biggest shore
	var flood = director.plan("flood")
	if not flood.is_empty():
		mark("ev_flood")
		var drowned: Array = flood.drown
		var fc: Vector2i = drowned[0][0] if not drowned.is_empty() else flood.deepen[0]
		var most = -1
		for e in drowned:
			var n = 0
			for o in drowned:
				if DestructionSystem._dist(e[0], o[0]) <= 2:
					n += 1
			if n > most:
				most = n
				fc = e[0]
		var fp = grid.hex_to_world(fc)
		cam_cut(fp + Vector3(-3.5, 9.0, 11.0), fp)
		await wait(1.0)
		director.send("flood", flood)
		bottom_caption(tr("Flood: the water rises, shores go under"), Color(0.4, 0.75, 1.0), 4.6)
		await wait(5.0)

	# Rift: two heroes dash across, one stands on it and gets pushed off
	var rift = director.plan("rift")
	if not rift.is_empty():
		mark("ev_rift")
		rift.warn = 5.0
		rift.burn = 2.0
		var coords: Array = rift.coords
		var rc: Vector2i = coords[0]
		var best_score = -INF
		for c in coords:  # a stretch on dry land, not too far out
			var d = DestructionSystem._dist(c, ds.center)
			if grid.get_tile(c).is_water() or d < 3:
				continue
			var score = -abs(d - 4)
			for step in HexTile.EDGE_DIRECTIONS:
				var n = grid.get_tile(c + step)
				if n and n.is_playable() and not n.is_water():
					score += 10
			if score > best_score:
				best_score = score
				rc = c
		var rp = grid.hex_to_world(rc) + Vector3(0, CoverSpawner.tile_top(grid.get_tile(rc)), 0)
		var side = Vector3(-rift.dir.z, 0, rift.dir.x).normalized()
		heroes[1].global_position = rp + Vector3(0, 0.2, 0)
		heroes[2].global_position = _ground_at(rp - side * 4.5 + rift.dir * 1.5) + Vector3(0, 0.2, 0)
		heroes[3].global_position = _ground_at(rp - side * 4.5 - rift.dir * 1.5) + Vector3(0, 0.2, 0)
		you.global_position = _ground_at(rp + side * 4.0) + Vector3(0, 0.2, 0)
		for h in heroes:
			face_to(h, rp)
		cam_cut(rp + side * 11.0 + Vector3(0, 9.0, 0) + rift.dir * 2.0, rp)
		await wait(0.6)
		director.send("rift", rift)
		bottom_caption(tr("Rift: a crack splits the island - get across in time"), UITheme.ACCENT_WARNING, 6.0)
		await wait(2.2)
		_run_to(heroes[2], heroes[2].global_position + side * 8.0)
		await wait(0.4)
		_run_to(heroes[3], heroes[3].global_position + side * 8.0)
		await wait(1.5)
		_stop_all(heroes)
		cam_to(rp + side * 12.0 + Vector3(0, 7.0, 0) - rift.dir * 1.0, rp + Vector3(0, 0.8, 0), 3.2)
		await wait(4.2)

	# Harvest: a bonus grows next to "you", you get there first
	mark("ev_harvest")
	# On open dry land, away from the new rock ridge
	var hp_c = _tile_at(ds.center, 3)
	var best_spot = -INF
	var ridge: Array = rift.get("coords", []) if not rift.is_empty() else []
	for c in grid.tiles:
		var tile = grid.get_tile(c)
		var d = DestructionSystem._dist(c, ds.center)
		if not tile or not tile.is_playable() or tile.is_water() or d < 2 or d > 4:
			continue
		var clear = 99
		for r in ridge:
			clear = min(clear, DestructionSystem._dist(c, r))
		var score = min(clear, 4) * 10
		for dd in [1, 2]:
			for o in grid.tiles:
				var ot = grid.get_tile(o)
				if DestructionSystem._dist(o, c) == dd and ot and ot.is_playable() and not ot.is_water():
					score += 1
		if score > best_spot:
			best_spot = score
			hp_c = c
	var harvest_pos = tile_top(hp_c)
	you.global_position = tile_top(_tile_at(hp_c, 2, 0)) + Vector3(0, 0.2, 0)
	heroes[1].global_position = tile_top(_tile_at(hp_c, 2, 6)) + Vector3(0, 0.2, 0)
	for h in [you, heroes[1]]:
		face_to(h, harvest_pos)
	var mid = (you.global_position + harvest_pos) / 2.0
	cam_cut(mid + Vector3(-1.0, 7.0, 8.5), mid + Vector3(0.8, 0.2, 0))
	await wait(0.5)
	director.send("harvest", {"pos": harvest_pos, "bonus": MapEvents.Harvest.SPEED, "item_id": 9000001, "grow": 3.2})
	bottom_caption(tr("Harvest: a rare bonus grows - everyone wants it"), UITheme.ACCENT_SUCCESS, 5.0)
	await wait(2.4)
	_run_to(you, harvest_pos)
	_run_to(heroes[1], harvest_pos)
	var t := 0.0
	while t < 3.0 and you.global_position.distance_to(harvest_pos) > 0.5:
		await get_tree().process_frame
		t += get_process_delta_time()
	_stop_all(heroes)
	await wait(2.8)

	# Zone drop: the next zone step brings a rich supply drop
	mark("ev_zone_drop")
	ds.current_phase = 1
	ds.stage = DestructionSystem.Stage.WAIT
	ds.stage_left = 0.02
	await wait(0.15)
	ds.stage_left = 1000.0
	var drop: LootContainer = null
	for c in get_tree().get_nodes_in_group("loot_containers"):
		if c.rich:
			drop = c
	if drop:
		var ground = drop.global_position - Vector3(0, 20.0, 0)
		cam_cut(ground + Vector3(4.5, 2.4, 7.5), ground + Vector3(0, 16.0, 0))
		cam_follow = drop
		cam_follow_offset = Vector3(0, -0.6, 0)
		bottom_caption(tr("A supply drop falls into the next zone - with the good stuff"), LootContainer.RICH_COLOR, 5.0)
		await wait(4.3)
		cam_to(ground + Vector3(3.8, 2.3, 6.0), ground + Vector3(0, 0.5, 0), 0.8)
		await wait(1.0)
		drop.interact(null)
		await wait(2.6)

	# The final zone shifts
	mark("ev_shift")
	ds.stage = DestructionSystem.Stage.WAIT
	ds.stage_left = 3.2  # the shift is announced for then, and the next step comes with it
	ds._radius = 3
	ds._shifted = false
	ds._plan_shift()
	cam_to(center_world + Vector3(0, 34, 27), center_world, 2.0)
	bottom_caption(tr("At the very end the zone shifts - watch the minimap"), UITheme.ACCENT_WARNING, 5.5)
	await wait(3.4)
	ds.stage_left = 1000.0
	await wait(2.8)
	chapter("ROYALTIM", tr("No two matches alike"), 3.4, UITheme.ACCENT_PRIMARY)
	await wait(3.6)
