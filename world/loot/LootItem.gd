## Loot item that can be picked up
extends Area3D
class_name LootItem

signal item_picked_up(item: LootItem, player: Player)

enum ItemType {
	HEALTH,
	AMMO,
	WEAPON,
	ABILITY_BOOST,
	SHIELD,
	HARVEST  # map event bonus (MapEvents.Harvest in item_value): speed, damage or a full shield
}

@export var item_type: ItemType = ItemType.HEALTH
@export var item_name: String = "Item"
@export var item_value: float = 25.0  # Health amount, damage boost, etc.
@export var respawn_time: float = 30.0  # 0 = no respawn

# The actual ItemData instance to give to player (for WEAPON, AMMO types)
var item_data: ItemData = null

var is_active: bool = true
var visual: Node3D = null            # the model: bobs and spins
var halo: MeshInstance3D = null      # glow on the ground in the loot type's color
var beam: MeshInstance3D = null      # light pillar for the good stuff (weapons, shields, boosts)
var original_position: Vector3 = Vector3.ZERO
var interact_prompt: Label3D = null
var _picked_by_local_player: bool = false  # Screen effects only for our own pickups
var _landed: bool = true             # false while popping out of a container

# Bobbing animation
var bob_time: float = 0.0
var bob_height: float = 0.12
var bob_speed: float = 2.4
var rotation_speed: float = 1.1

const INTERACT_RANGE: float = 2.0
const FLIGHT_TIME: float = 0.55
const ARC_HEIGHT: float = 1.3
const HOVER_HEIGHT: float = 0.45     # items rest this far above the ground

func _ready():
	add_to_group("loot_items")
	add_to_group("interactable")  # For E key pickup
	original_position = position

	_create_visual()
	_create_collision()

	# Connect signal for auto-pickup when walking over
	body_entered.connect(_on_body_entered)

func _process(delta: float):
	if not is_active:
		return

	if not _landed:
		return

	# Bobbing animation
	bob_time += delta * bob_speed
	if visual:
		visual.position.y = sin(bob_time) * bob_height
		visual.rotation.y += delta * rotation_speed
	if halo:
		halo.scale = Vector3.ONE * (1.0 + sin(bob_time * 1.3) * 0.08)

	# Update interact prompt for E key pickup
	_update_interact_prompt()

func _update_interact_prompt():
	# Find local player
	var local_player: Player = null
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p is Player and p.is_local_player:
			local_player = p
			break

	if not local_player:
		if interact_prompt and interact_prompt.visible:
			interact_prompt.visible = false
		return

	var dist = global_position.distance_to(local_player.global_position)

	if dist <= INTERACT_RANGE:
		if not interact_prompt:
			_create_interact_prompt()
		interact_prompt.visible = true
	elif interact_prompt:
		interact_prompt.visible = false

func _create_interact_prompt():
	interact_prompt = Label3D.new()
	interact_prompt.text = "[X] %s" % tr(item_name)
	interact_prompt.position = Vector3(0, 0.8, 0)
	interact_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	interact_prompt.font_size = 36
	interact_prompt.outline_size = 6
	interact_prompt.modulate = Color(1, 1, 0.8)
	interact_prompt.no_depth_test = true
	add_child(interact_prompt)

## Called when player presses E near item
func interact(player: Player):
	if not is_active or not _landed:
		return

	# Check distance
	var dist = global_position.distance_to(player.global_position)
	if dist > INTERACT_RANGE:
		return

	print("[LootItem] Player pressing E to pickup: %s" % item_name)
	_pickup(player)

func _create_visual():
	visual = Node3D.new()
	visual.name = "ItemVisual"
	add_child(visual)
	var model = LootVisuals.harvest_model(_color()) if item_type == ItemType.HARVEST else LootVisuals.pickup_model(item_type, item_data)
	visual.add_child(model if model else _fallback_mesh())

	var color = _color()
	halo = LootVisuals.halo(color, 0.55)
	halo.position.y = -HOVER_HEIGHT + 0.03
	add_child(halo)
	if item_type in [ItemType.WEAPON, ItemType.SHIELD, ItemType.ABILITY_BOOST, ItemType.HARVEST]:
		beam = LootVisuals.beam(color, 2.2, 0.1)
		beam.position.y += -HOVER_HEIGHT
		(beam.material_override as StandardMaterial3D).albedo_color.a = 0.55
		add_child(beam)

## Pop out of an opening container: fly from `from` in an arc to where the item rests,
## bounce and settle. It cannot be picked up before it lands.
func launch(from: Vector3, delay: float = 0.0):
	_landed = false
	var rest = global_position
	visual.visible = false
	_show_glow(false)
	global_position = from
	var t = create_tween()
	t.tween_interval(delay)
	t.tween_callback(func(): visual.visible = true)
	t.tween_method(_fly.bind(from, rest), 0.0, 1.0, FLIGHT_TIME)
	t.tween_callback(_on_landed)

## Harvest bonus (HarvestPatch): grows out of the ground for `seconds`, pickable once ripe
func grow_in(seconds: float):
	if seconds <= 0.0:
		return
	_landed = false
	_show_glow(false)
	visual.scale = Vector3.ONE * 0.05
	var t = create_tween()
	t.tween_property(visual, "scale", Vector3.ONE * 0.8, seconds).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_on_landed)

func _color() -> Color:
	if item_type == ItemType.HARVEST:
		return MapEvents.harvest_color(int(item_value))
	return LootVisuals.type_color(item_type)

func _fly(k: float, from: Vector3, rest: Vector3):
	var p = from.lerp(rest, k)
	p.y += sin(k * PI) * ARC_HEIGHT
	global_position = p
	visual.rotation = Vector3(k * TAU, k * TAU * 1.5, 0)
	visual.scale = Vector3.ONE * lerp(0.4, 1.0, min(k * 3.0, 1.0))

func _on_landed():
	visual.rotation = Vector3.ZERO
	visual.position.y = 0.0
	visual.scale = Vector3(1.35, 0.65, 1.35)
	create_tween().tween_property(visual, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_show_glow(true)
	var puff = LootVisuals.sparkles(_color(), 8, 2.5, 0.5)
	puff.position.y = -HOVER_HEIGHT + 0.1
	add_child(puff)
	puff.emitting = true
	get_tree().create_timer(0.8).timeout.connect(puff.queue_free)
	bob_time = 0.0
	_landed = true
	# Whoever already stands on the landing spot gets it now (body_entered won't fire again)
	await get_tree().physics_frame
	if is_inside_tree() and is_active:
		for body in get_overlapping_bodies():
			_on_body_entered(body)
			if not is_active:
				break

func _show_glow(on: bool):
	for g in [halo, beam]:
		if not g:
			continue
		g.visible = true
		var mat: StandardMaterial3D = g.material_override
		var target = (0.55 if g == beam else 1.0) if on else 0.0
		if on:
			mat.albedo_color.a = 0.0
			create_tween().tween_property(mat, "albedo_color:a", target, 0.4)
		else:
			mat.albedo_color.a = 0.0

func _fallback_mesh() -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "ItemMesh"

	var mesh: Mesh
	var material = StandardMaterial3D.new()
	material.emission_enabled = true

	match item_type:
		ItemType.HEALTH:
			mesh = SphereMesh.new()
			mesh.radius = 0.25
			mesh.height = 0.5
			material.albedo_color = Color(0.2, 0.9, 0.3)
			material.emission = Color(0.1, 0.5, 0.15)
		ItemType.AMMO:
			mesh = BoxMesh.new()
			mesh.size = Vector3(0.3, 0.2, 0.4)
			material.albedo_color = Color(0.9, 0.7, 0.2)
			material.emission = Color(0.5, 0.35, 0.1)
		ItemType.WEAPON:
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.1
			mesh.bottom_radius = 0.15
			mesh.height = 0.5
			material.albedo_color = Color(0.7, 0.7, 0.8)
			material.emission = Color(0.3, 0.3, 0.4)
			material.metallic = 0.8
		ItemType.ABILITY_BOOST:
			mesh = PrismMesh.new()
			mesh.size = Vector3(0.4, 0.4, 0.4)
			material.albedo_color = Color(0.8, 0.3, 0.9)
			material.emission = Color(0.4, 0.15, 0.45)
		ItemType.SHIELD:
			mesh = TorusMesh.new()
			mesh.inner_radius = 0.15
			mesh.outer_radius = 0.3
			material.albedo_color = Color(0.3, 0.6, 0.9)
			material.emission = Color(0.15, 0.3, 0.45)

	material.emission_energy_multiplier = 0.5
	mesh_instance.mesh = mesh
	mesh_instance.set_surface_override_material(0, material)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance

func _create_collision():
	var collision = CollisionShape3D.new()
	collision.name = "PickupArea"
	var shape = SphereShape3D.new()
	shape.radius = 0.8  # Pickup radius
	collision.shape = shape
	add_child(collision)

	# Set collision layer for items
	collision_layer = 4  # Layer 3 for items
	collision_mask = 2   # Detect players (layer 2)

func _on_body_entered(body: Node3D):
	if not is_active or not _landed:
		return

	if not body is Player:
		return

	# On a client only our own player may pick things up by walking over them.
	# Pickups by anyone else are decided by the server and replicated via NetworkLootManager.
	var mp = get_tree().get_multiplayer()
	if mp.has_multiplayer_peer() and not mp.is_server() and not body.is_local_player:
		return

	_pickup(body as Player)

func _pickup(player: Player):
	is_active = false
	_picked_by_local_player = player != null and player.is_local_player
	item_picked_up.emit(self, player)

	# Apply item effect
	_apply_effect(player)

	# Visual feedback
	_play_pickup_effect()

	# Handle respawn or removal
	if respawn_time > 0:
		_start_respawn_timer()
	else:
		queue_free()

func _apply_effect(player: Player):
	match item_type:
		ItemType.HEALTH:
			var inventory = player.get_component("InventoryComponent")
			if inventory:
				var pack = HealthPack.new()
				pack.heal_amount = item_value
				inventory.add_item(pack)
				print("[LootItem] Added Health Pack (heal=%f) to inventory" % item_value)
		ItemType.AMMO:
			var inventory = player.get_component("InventoryComponent")
			if inventory:
				# If item_data is set, use it. Otherwise create a default AmmoItem
				var ammo_item = item_data if item_data is AmmoItem else _create_default_ammo()
				if inventory.add_item(ammo_item):
					print("[LootItem] Added %s to inventory" % ammo_item.item_name)
				else:
					print("[LootItem] Inventory full, cannot add ammo")
		ItemType.WEAPON:
			print("[LootItem] Picking up WEAPON type item")
			var inventory = player.get_component("InventoryComponent")
			if inventory:
				print("[LootItem] InventoryComponent found")
				# If item_data is set, use it. Otherwise create a default weapon
				var weapon_item = item_data if item_data is RangedWeapon else _create_default_weapon()
				print("[LootItem] Weapon item: %s (is RangedWeapon: %s)" % [weapon_item.item_name, weapon_item is RangedWeapon])
				# Add to weapon slot (not regular inventory)
				var slot = inventory.add_weapon_to_slot(weapon_item)
				if slot >= 0:
					print("[LootItem] ✓ Added %s to weapon slot %d" % [weapon_item.item_name, slot + 1])
				else:
					print("[LootItem] Weapon slots full, cannot add weapon")
		ItemType.ABILITY_BOOST:
			# Temporary ability cooldown reduction
			var ability = player.get_component("AbilityComponent")
			if ability:
				ability.boost_cooldowns(item_value)
		ItemType.SHIELD:
			var health = player.get_component("HealthComponent")
			if health and health.has_method("add_shield"):
				health.add_shield(item_value)
			print("[LootItem] Shield pickup (value: %f)" % item_value)
		ItemType.HARVEST:
			MapEvents.apply_harvest(player, int(item_value))

func _play_pickup_effect():
	# Hide the model and its glow
	for n in [visual, halo, beam]:
		if n:
			n.visible = false

	var item_color: Color
	match item_type:
		ItemType.HEALTH:
			item_color = Color(0.2, 1.0, 0.3)
		ItemType.AMMO:
			item_color = Color(1.0, 0.8, 0.2)
		ItemType.WEAPON:
			item_color = Color(0.8, 0.8, 0.9)
		ItemType.ABILITY_BOOST:
			item_color = Color(0.9, 0.3, 1.0)
		ItemType.SHIELD:
			item_color = Color(0.3, 0.7, 1.0)
		ItemType.HARVEST:
			item_color = _color()

	# Main pickup burst particles
	var particles = GPUParticles3D.new()
	particles.amount = 20
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 1.0

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.2
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, -8, 0)
	mat.scale_min = 0.08
	mat.scale_max = 0.15
	mat.color = item_color

	particles.process_material = mat

	var mesh = SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh

	add_child(particles)

	# Star burst effect (sparkles)
	var stars = GPUParticles3D.new()
	stars.amount = 12
	stars.lifetime = 0.8
	stars.one_shot = true
	stars.explosiveness = 0.9

	var star_mat = ParticleProcessMaterial.new()
	star_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	star_mat.emission_sphere_radius = 0.1
	star_mat.direction = Vector3(0, 1, 0)
	star_mat.spread = 180.0
	star_mat.initial_velocity_min = 4.0
	star_mat.initial_velocity_max = 7.0
	star_mat.gravity = Vector3(0, -3, 0)
	star_mat.scale_min = 0.12
	star_mat.scale_max = 0.25
	star_mat.color = Color(1, 1, 0.7)  # Golden sparkles

	# Scale down over time
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0, 1))
	scale_curve.add_point(Vector2(1, 0))
	var scale_texture = CurveTexture.new()
	scale_texture.curve = scale_curve
	star_mat.scale_curve = scale_texture

	stars.process_material = star_mat

	# Star mesh (small prism for sparkle)
	var star_mesh = PrismMesh.new()
	star_mesh.size = Vector3(0.08, 0.08, 0.08)
	stars.draw_pass_1 = star_mesh

	add_child(stars)

	# Rising glow effect (goes upward and fades)
	var glow = GPUParticles3D.new()
	glow.amount = 8
	glow.lifetime = 1.0
	glow.one_shot = true
	glow.explosiveness = 0.5

	var glow_mat = ParticleProcessMaterial.new()
	glow_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	glow_mat.direction = Vector3(0, 1, 0)
	glow_mat.spread = 15.0
	glow_mat.initial_velocity_min = 2.0
	glow_mat.initial_velocity_max = 3.5
	glow_mat.gravity = Vector3(0, 0.5, 0)  # Slight upward drift
	glow_mat.scale_min = 0.2
	glow_mat.scale_max = 0.4

	# Color gradient from item color to white
	var color_gradient = Gradient.new()
	color_gradient.set_color(0, item_color)
	color_gradient.set_color(1, Color(1, 1, 1, 0))
	var color_texture = GradientTexture1D.new()
	color_texture.gradient = color_gradient
	glow_mat.color_ramp = color_texture

	glow.process_material = glow_mat

	var glow_mesh = SphereMesh.new()
	glow_mesh.radius = 0.1
	glow_mesh.height = 0.2
	glow.draw_pass_1 = glow_mesh

	add_child(glow)

	# Trigger screen effect based on item type
	_trigger_screen_effect()

func _trigger_screen_effect():
	if not _picked_by_local_player:
		return
	var screen_effects = get_node_or_null("/root/ScreenEffects")
	if not screen_effects:
		return

	match item_type:
		ItemType.HEALTH:
			ScreenEffects.heal_effect()
		ItemType.SHIELD:
			ScreenEffects.flash(Color(0.3, 0.6, 1.0), 0.15, 0.15)
		ItemType.ABILITY_BOOST:
			ScreenEffects.ability_ready_pulse()
		ItemType.WEAPON:
			ScreenEffects.flash(Color(1, 1, 0.8), 0.1, 0.1)
		ItemType.HARVEST:
			ScreenEffects.flash(_color(), 0.2, 0.2)

func _start_respawn_timer():
	await get_tree().create_timer(respawn_time).timeout
	_respawn()

func _respawn():
	is_active = true
	for n in [visual, halo, beam]:
		if n:
			n.visible = true
	position = original_position
	print("[LootItem] %s respawned" % item_name)

## Create default ammo based on item_value (used as ammo type)
func _create_default_ammo() -> AmmoItem:
	var ammo_type = int(item_value) % 3 as AmmoItem.AmmoType  # Use item_value as type hint
	var ammo = AmmoItem.new(ammo_type, 30)
	return ammo

## Create default weapon (pistol)
func _create_default_weapon() -> RangedWeapon:
	var weapon = RangedWeapon.new()
	weapon.item_name = "Pistol"
	weapon.ammo_type = AmmoItem.AmmoType.PISTOL
	weapon.current_ammo = 12
	weapon.magazine_size = 12
	weapon.reload_time = 2.0
	return weapon
