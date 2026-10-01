## The gun in a hero's hands (on every peer, so others see what you carry). The model is fitted to
## RangedWeapon.hold_length for a standard 1.2 m hero (scaled with the hero) whatever size the file
## has, held in the right hand pointing where the hero looks. Heroes face +Z (PlayerInputHandler:
## rotation.y = atan2(x, z)), so their right hand is at -X; the Blaster Kit's barrels point along -Z
## and get turned around. Recoil, muzzle flash and the reload dip always return to the rest pose.
extends Node3D
class_name WeaponVisualComponent

const HERO_HEIGHT: float = 1.2                     # Player._load_character_model's standard height
const HAND: Vector3 = Vector3(-0.28, 0.6, 0.12)    # right hand of a standard hero (-X right, +Z forward)
const GRIP: float = 0.3                            # the hand sits this share of the length behind the middle

var player: Player = null
var current_weapon: RangedWeapon = null
var weapon_model: Node3D = null                   # holder: rest pose + animations; the model inside is fitted
var _rest: Transform3D = Transform3D.IDENTITY
var _length: float = 0.45
var _tween: Tween = null

static var _scenes: Dictionary = {}  # model path -> PackedScene (shared by all heroes)

func setup(p_player: Player):
	player = p_player
	name = "WeaponVisual"

	var combat = player.get_component("CombatComponent")
	if combat:
		combat.weapon_changed.connect(_on_weapon_changed)
		combat.shot_fired.connect(_on_shot_fired)
		combat.reload_started.connect(_on_reload_started)
		combat.reload_finished.connect(_on_reload_finished)
		if combat.equipped_ranged_weapon:
			_show_weapon(combat.equipped_ranged_weapon)

	var inventory = player.get_component("InventoryComponent")
	if inventory:
		inventory.weapon_equipped.connect(_on_weapon_equipped)
		inventory.weapon_slot_changed.connect(_on_weapon_slot_changed)

func _on_weapon_changed(weapon_data):
	if weapon_data is RangedWeapon:
		_show_weapon(weapon_data)
		return
	var combat = player.get_component("CombatComponent") if player else null
	if combat and combat.equipped_ranged_weapon:
		_show_weapon(combat.equipped_ranged_weapon)
	else:
		_hide_weapon()

func _on_weapon_equipped(weapon: RangedWeapon, _slot: int):
	# A picked-up gun only shows if it is the one in hand (auto-equip emits weapon_changed)
	var combat = player.get_component("CombatComponent") if player else null
	if weapon and combat and combat.equipped_ranged_weapon == weapon:
		_show_weapon(weapon)

func _on_weapon_slot_changed(slot: int):
	var inventory = player.get_component("InventoryComponent") if player else null
	if inventory:
		var weapon = inventory.get_weapon_in_slot(slot)
		if weapon:
			_show_weapon(weapon)
		else:
			_hide_weapon()

func _show_weapon(weapon: RangedWeapon):
	if weapon == current_weapon and weapon_model and is_instance_valid(weapon_model):
		return
	current_weapon = weapon
	if weapon_model:
		weapon_model.queue_free()
		weapon_model = null
	if _tween and _tween.is_valid():
		_tween.kill()

	var model = _instantiate(weapon.model_path)
	if not model:
		model = _create_default_weapon_mesh(weapon.weapon_type)
	var hero_scale = _hero_scale()
	_length = weapon.hold_length * hero_scale
	_fit(model, _length)
	if player:
		# This gun's own finish (a mastery camo) or the one for every gun
		var own: Dictionary = player.cosmetics.get("weapons", {})
		Cosmetics.apply_to_weapon(model, String(own.get(str(int(weapon.weapon_type)), player.cosmetics.get("weapon", "default"))))

	weapon_model = Node3D.new()
	weapon_model.name = "HeldWeapon"
	var turn = Node3D.new()  # barrel from the file's -Z to the hero's forward +Z
	turn.rotation.y = PI
	turn.add_child(model)
	weapon_model.add_child(turn)
	add_child(weapon_model)
	weapon_model.position = _hand() + Vector3(0, 0, _length * GRIP)
	_rest = weapon_model.transform

## Where the right hand is: HAND for a slim hero; round ones (tomato, melon) hold the gun at the
## front of their body, or it disappears inside them
func _hand() -> Vector3:
	var hand = HAND * _hero_scale()
	var model = player.get_node_or_null("Model") if player else null
	if not model:
		return hand
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b = ModelUtils._relative_xform(player, mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return hand
	hand.x = -max(abs(hand.x), -box.position.x * 0.7)  # right side (-X)
	hand.z = max(hand.z, box.end.z * 0.8)              # at the front of the body (+Z)
	return hand

## Show the gun again (a new weapon finish was put on)
func refresh() -> void:
	var weapon = current_weapon
	if weapon:
		current_weapon = null
		_show_weapon(weapon)

func _hide_weapon():
	current_weapon = null
	if weapon_model:
		weapon_model.queue_free()
		weapon_model = null

func _hero_scale() -> float:
	if player and player.character_data and player.character_data.model_scale > 0.0:
		return player.character_data.model_scale
	return 1.0

func _instantiate(path: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var scene = _scenes[path]
	return scene.instantiate() if scene is PackedScene else null

## Longest side = `length`, centered on the holder's origin, barrel still along -Z
func _fit(model: Node3D, length: float) -> void:
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b = ModelUtils._relative_xform(model, mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var s = length / max(box.size.x, box.size.y, box.size.z, 0.001)
	model.scale = Vector3.ONE * s
	model.position = -box.get_center() * s
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## Update weapon from external source (network sync of remote players)
func update_weapon(weapon_name: String):
	var inventory = player.get_component("InventoryComponent") if player else null
	if inventory:
		for slot in range(InventoryComponent.MAX_WEAPON_SLOTS):
			var weapon = inventory.get_weapon_in_slot(slot)
			if weapon and weapon.item_name == weapon_name:
				_show_weapon(weapon)
				return

## Simple stand-ins when a model file is missing, pointing along -Z like the Blaster Kit
func _create_default_weapon_mesh(weapon_type: RangedWeapon.WeaponType) -> Node3D:
	var container = Node3D.new()
	container.name = "DefaultWeaponMesh"
	var mesh_instance = MeshInstance3D.new()
	var material = StandardMaterial3D.new()
	material.metallic = 0.6
	material.roughness = 0.4
	var box = BoxMesh.new()
	match weapon_type:
		RangedWeapon.WeaponType.SHOTGUN:
			box.size = Vector3(0.1, 0.12, 0.7)
			material.albedo_color = Color(0.3, 0.25, 0.2)
		RangedWeapon.WeaponType.SNIPER:
			box.size = Vector3(0.07, 0.1, 1.0)
			material.albedo_color = Color(0.15, 0.15, 0.2)
		RangedWeapon.WeaponType.RIFLE:
			box.size = Vector3(0.08, 0.12, 0.8)
			material.albedo_color = Color(0.25, 0.25, 0.25)
		RangedWeapon.WeaponType.FLAMETHROWER:
			box.size = Vector3(0.14, 0.16, 0.75)
			material.albedo_color = Color(0.4, 0.2, 0.1)
		_:
			box.size = Vector3(0.1, 0.15, 0.35)
			material.albedo_color = Color(0.2, 0.2, 0.25)
	mesh_instance.mesh = box
	mesh_instance.set_surface_override_material(0, material)
	container.add_child(mesh_instance)
	return container

# ---------------------------------------------------------------- animation

func _animate(offset: Vector3, pitch_deg: float, out_time: float, back_time: float, hold: bool = false) -> void:
	if not weapon_model:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	weapon_model.transform = _rest
	var pose = Transform3D(_rest.basis.rotated(Vector3.RIGHT, deg_to_rad(pitch_deg)), _rest.origin + offset)
	_tween = create_tween()
	_tween.tween_property(weapon_model, "transform", pose, out_time).set_ease(Tween.EASE_OUT)
	if not hold:
		_tween.tween_property(weapon_model, "transform", _rest, back_time).set_ease(Tween.EASE_OUT)

func _on_shot_fired(_from: Vector3, _to: Vector3, _hit: bool):
	if not weapon_model:
		return
	# Kick back and up (-Z is backwards, -pitch lifts a +Z muzzle), then settle
	_animate(Vector3(0, 0.02, -0.06) * _hero_scale(), -8.0, 0.04, 0.12)
	_create_muzzle_flash()

func _create_muzzle_flash():
	if not weapon_model:
		return
	var tip = Vector3(0, 0, _length * 0.5)  # the barrel's end, in the holder
	var flash = OmniLight3D.new()
	flash.light_color = Color(1, 0.8, 0.3)
	flash.light_energy = 3.0
	flash.omni_range = 3.5
	flash.position = tip
	weapon_model.add_child(flash)
	var flash_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	flash_mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.9, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.7, 0.3)
	mat.emission_energy_multiplier = 8.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mesh.material_override = mat
	flash_mesh.position = tip
	flash_mesh.scale = Vector3(1.2, 1.2, 2.0)
	weapon_model.add_child(flash_mesh)
	var tween = flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.08)
	tween.parallel().tween_property(flash_mesh, "scale", Vector3.ONE * 0.01, 0.06)  # not 0: zero basis errors
	tween.tween_callback(flash.queue_free)
	tween.tween_callback(flash_mesh.queue_free)

func _on_reload_started():
	# Muzzle down and the gun lowered while the magazine goes in
	_animate(Vector3(0, -0.12, -0.08) * _hero_scale(), 35.0, 0.25, 0.0, true)

func _on_reload_finished():
	if not weapon_model:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var overshoot = Transform3D(_rest.basis, _rest.origin + Vector3(0, 0.04, 0.04))
	_tween.tween_property(weapon_model, "transform", overshoot, 0.15).set_ease(Tween.EASE_OUT)
	_tween.tween_property(weapon_model, "transform", _rest, 0.1).set_ease(Tween.EASE_IN_OUT)
