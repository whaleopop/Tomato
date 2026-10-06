# Coder cookbook: the project's recurring patterns

Real patterns from the code (trimmed). Copy the shape, check the current file before pasting - names drift. Add a recipe when the same question comes up twice.

## Server -> client: a field in the per-tick player state
```gdscript
# ServerPlayer.get_sync_data()
var health = player_entity.get_component("HealthComponent")
if health:
	data["shield"] = health.shield
var fx = status.to_sync()
if not fx.is_empty():            # omit empty values - the state goes to every client 20x/s
	data["fx"] = fx

# NetworkingComponent.apply_sync_data(data) on the client
if data.has("shield"):
	health.set_shield(float(data["shield"]))
```
Rarely changing values (names, cosmetics, stats) go in `TickSystem.SLOW_KEYS`; per-victim data is stripped for other viewers in `TickSystem` (like "hits").

## Server -> clients: a one-off event (respecting the fog)
```gdscript
# NetworkManager (RPC nodes live under /root/NetworkManager only)
func broadcast_ability_cast(caster_id: int, ability_index: int, target_position: Vector3):
	if not multiplayer.multiplayer_peer or not multiplayer.is_server() or not game_server:
		return
	var world = game_server.server_world
	var caster = world.get_player(caster_id)
	for peer_id in multiplayer.get_peers():
		if ServerVisibility.can_see(world.get_player(peer_id), caster, world.hex_grid):
			_receive_ability_cast.rpc_id(peer_id, caster_id, ability_index, target_position)

@rpc("authority", "call_remote", "reliable")
func _receive_ability_cast(caster_id: int, ability_index: int, target_position: Vector3):
	var world = _get_client_world()
	var caster = world.get_player(caster_id) if world else null
	if caster and is_instance_valid(caster):
		caster.get_component("AbilityComponent").play_remote_cast(ability_index, target_position)
```
The host doesn't get its own RPC (`call_remote`): do the host's side directly where the event happens. Events everyone must see (kills, zone) skip the fog filter.

## Client -> server: a menu / UI action
```gdscript
# client
player_input.send_ui_action({"drop_item": slot})
# ServerPlayer.process_input(input_data) - validate, never trust
if input_data.has("drop_item"):
	inventory_comp.drop_item(int(input_data.drop_item))
```

## Gameplay only on the server
```gdscript
func take_damage(amount: float, source = null) -> float:
	if not enabled or is_dead or invulnerable:
		return 0.0
	if not _is_authority():       # clients get health from the sync
		return 0.0

func _is_authority() -> bool:
	if not entity or not is_instance_valid(entity) or not entity.is_inside_tree():
		return true
	return entity.get_tree().get_multiplayer().is_server()
```
States: `StatusComponent.apply(kind, seconds, value)` / `push(velocity, seconds)` - same gate inside.

## Active ability (runs on caster, server, and as replay)
```gdscript
extends ActiveAbility
class_name Dash

var dash_speed: float = 15.0
var dash_distance: float = 5.0

func _init():
	ability_name = "Dash"      # an id: English, translated only for display
	cooldown = 3.0
	duration = 0.3

func aim_preview() -> Dictionary:   # keep in step with the numbers
	return {"shape": "line", "range": dash_distance, "width": 1.0}

func _on_activate(entity, target_position: Vector3) -> bool:
	var movement = entity.get_component("MovementComponent")
	if not movement:
		return false
	var dir := target_position - entity.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else entity.global_transform.basis.z  # heroes face +Z
	if not replay:                      # replay = visuals only
		movement.dash(dir * dash_speed, dash_distance / dash_speed)
	_create_dash_effect(entity, dir)    # visuals everywhere
	return true
```
Hook it up in `characters/data/<Hero>Character.gd`: `active_ability_data.script_path = "res://abilities/active/<Name>.gd"`. Name + description in `LocaleRu.STRINGS`.

## Passive ability = an entity meta the rules read
```gdscript
extends PassiveAbility
class_name HotTemper
const VALUE = 1.25

func _on_apply(entity):
	entity.set_meta("hot_temper", VALUE)

func _on_remove(entity):
	if entity.has_meta("hot_temper"):
		entity.remove_meta("hot_temper")

# read where the rule lives, e.g. CombatComponent.get_damage_multiplier()
if entity and entity.has_meta("hot_temper"):
	m *= float(entity.get_meta("hot_temper"))
```

## A full screen
```gdscript
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.create_background(self, true)                 # scenic garden behind
	var header := ScreenHeader.make(self, "FRIENDS", "SOCIAL")   # title, gold kicker; back chip on by default
	header.back_pressed.connect(_on_back)
	var content := MarginContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_top = ScreenHeader.CONTENT_TOP
	add_child(content)

func _on_back():
	SceneTransition.fade_to_scene("res://scenes/MainMenuScene.tscn")   # never bare change_scene_to_file
```
Shell screens (Home / Shop / Profile / Friends tabs) do NOT call `ScreenHeader.make`: `MenuShell.show_bar()` then `MenuShell.header` (the one persistent bar; no title zone - put the screen's title in a fixed `ScreenHeader.SUBNAV_H` row under it, side margin `ScreenHeader.SIDE_MARGIN`). An overlay / scene with its own header: `MenuShell.cover(node)` or `MenuShell.hide_bar()`.
`ScreenHeader.make(parent, title, kicker, back := true, has_title := true)` (non-shell screens); settings chip: `header.add_settings_chip()`. Spacing / sizes / colors only from `UITheme` (see ui-design.md).

## Text and translation
```gdscript
# LocaleRu.STRINGS
"%d  ALIVE": "%d  В ЖИВЫХ",
"Plays %s  ·  Lv %d": "Играет за: %s  ·  ур. %d",
# code: translate the pattern, then format
alive_label.text = tr("%d  ALIVE") % alive
# static / RefCounted code: Locale.t("...")
```

## Icons, 3D previews, sound, tweens
```gdscript
UITheme.create_icon_chip("settings", row, Vector2(48, 44), tr("Settings"))
UITheme.create_icon_label("coin", UITheme.format_coins(n), row, UITheme.FONT_SMALL)

class_name MyPreview extends HiResView     # 3D inside UI
func _init():
	super()                                 # first, always
	viewport.own_world_3d = true
	viewport.transparent_bg = true
# picking: convert with to_vp / from_vp

Sfx.at("pickup", global_position)   # 3D, where it happens (every peer that sees it)
Sfx.own("reload")                   # your own hero, flat
Sfx.ui("click")                     # menus

var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
t.tween_property(panel, "modulate:a", 1.0, 0.16)
```
