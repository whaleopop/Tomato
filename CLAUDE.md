# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ROYALTIM-3 is a 3D top-down battle royale game built with **Godot 4.7** (Steam build 4.7.2) featuring anthropomorphic vegetables and fruits as characters. The game uses a procedurally generated hexagonal map with a destruction system instead of a shrinking zone.

## Running the Project

Open the project in Godot 4.7 and run `scenes/MainMenuScene.tscn`.

### Running Tests

Tests use GUT (Godot Unit Testing), which is not installed right now, so they live in `tests_disabled/`. Install GUT and move them back to `tests/` to run them via `Project -> Tools -> Run Tests`:
- `test_components.gd` - Component system tests
- `test_inventory.gd` - Inventory tests
- `test_abilities.gd` - Ability tests
- `test_hex_grid.gd` - Hexagonal grid tests

## Architecture

### Component-Based System

The project uses a component-based architecture (ECS-like) where entities are composed of modular components.

**Base classes:**
- `Component` (`core/components/Component.gd`) - RefCounted base class with `entity` reference, `enabled` state, and `update(delta)` method
- `Entity` (`core/entities/Entity.gd`) - Node3D that holds a dictionary of components, calls `update()` on enabled components each frame

**Key components** (in `core/components/`):
- `MovementComponent` - Movement handling
- `HealthComponent` - Health and damage
- `CombatComponent` - Combat system
- `AbilityComponent` - Ability management
- `InventoryComponent` - Item inventory
- `NetworkingComponent` - Network synchronization

### Ability System

Located in `abilities/`:
- `Ability.gd` - Base class with cooldown system
- `ActiveAbility.gd` - Abilities activated by player (has `activate(entity, target_position)`, `duration`, signals)
- `PassiveAbility.gd` - Always-active abilities (override `_apply_passive(entity)`)

To add a new ability:
1. Create class extending `ActiveAbility` or `PassiveAbility`
2. Override `_on_activate()` for active or `_apply_passive()` for passive
3. Reference in character data

### Network Architecture

Server-authoritative multiplayer using ENet:
- **Server** (`network/server/`): `GameServer`, `ServerWorld`, `ServerPlayer`, `TickSystem`
- **Client** (`network/client/`): `GameClient`, `ClientWorld`
- **Sync** (`network/sync/`): `NetworkSync`

**Autoloads** (singletons):
- `NetworkManager` - Manages server/client lifecycle
- `GameManager` - Game state management

**Data flow:**
1. Client sends input to server via RPC
2. Server processes input authoritatively
3. Server broadcasts world state to all clients
4. Clients interpolate received state

**Tick rates:**
- Entities simulate themselves in `Entity._physics_process`; `TickSystem` only broadcasts state (20/sec, `unreliable_ordered`, only while a match runs). Never update components from TickSystem too - it doubles movement speed.

**Invariants (breaking these caused real bugs):**
- Every RPC node lives under `/root/NetworkManager` (`NetworkLobby`, `NetworkLootManager`): RPCs are routed by node path, which must match on all peers.
- Listen server: the host adopts `ServerWorld`'s map/loot (`ClientWorld.adopt_server_world`); the host's local `Player` is registered as the server entity for id 1. Remote players on the host are the ServerWorld entities - never spawn a second copy.
- Server and clients must use `MapGenerator.MATCH_MAP_RADIUS` and the same seed (lake placement depends on radius). Loot uses `LootSpawner.setup(grid, map_seed)` with its own RNG so container ids/contents match everywhere.
- Server-side entities get `setup_character()` + `give_starting_loadout()` so speed/health/weapon match the owning client. Call `setup_character()` after `add_child` (components are created in `_ready`).
- `is_local_player` is a property, not a method (`has_method("is_local_player")` is always false).
- Map destruction runs on the server from match start and is replicated via `NetworkManager.broadcast_tiles_destroyed`.
- `SceneTransition.fade_to_scene` queues requests made during a running fade; don't bypass it with bare `change_scene_to_file` in menus.
- Returning to `MainMenu` calls `NetworkManager.stop_all()`.
- Only the server applies gameplay damage: `HealthComponent.take_damage` returns 0 on clients (they get health from the sync via `_apply_damage`). Clients killing their copy of a player left unhittable "ghosts".
- Match end: `GameServer._check_match_end` (last one standing among the players at match start, 2+ players) -> `NetworkManager.match_ended(winner_id, winner_name)` on every peer -> `PlayerHUD` result screen. The dead send no input (`PlayerInputHandler._input_blocked`, `ServerPlayer.process_input`).
- Input: one-shot actions are latched every frame and sent on the 30 Hz tick; visible nodes in group `blocks_game_input` (pause menu, inventory, result screen) stop gameplay input. Menu actions (inventory use/drop) go to the server via `PlayerInputHandler.send_ui_action`.
- Server-side fog (anti-wallhack): `TickSystem` sends each client its own world state; players it can't see (`ServerVisibility.can_see`: sight radius, cover walls, bushes) arrive as `{"hidden": true, health, max_health}` - clients keep a frozen invisible copy (`net_hidden` meta) or none at all, so count things like "alive" from `ClientWorld.last_player_states`, not from player nodes. Shots and ability casts only go to clients that can hear / see them.
- Ability casts are replicated: `AbilityComponent.ability_cast` -> `ServerPlayer` -> `NetworkManager.broadcast_ability_cast` -> `play_remote_cast` on the other clients' copies with `Ability.replay = true` (visuals only: no movement, no heals; damage is server-side anyway).
- Late joiners: the map info carries the loot history (`NetworkLootManager.get_late_join_state`: opened containers, picked items, supply drops); containers / items that register later are opened / removed then. Late join is only allowed for `GameServer.LATE_JOIN_WINDOW` seconds and never twice per `NetworkManager.client_token` (an eliminated player can't come back as a fresh one); refused clients get the reason via `NetworkLobby._receive_join_refused`.

### World Generation

Located in `world/generation/`:
- `HexGenerator.gd` - Generates hexagonal grid structure
- `HexGrid.gd` - Grid management
- `HexTile.gd` - Individual tile representation
- `MapGenerator.gd` - Orchestrates map generation

Seamless ground: tile materials are shared (one per biome, one for all water, `ShaderHelper`); per-tile data goes in instance uniforms. `HexTile.update_edges` tells each tile what lies across its six edges (joined neighbour of the same kind and level -> colors blend; step / shore / void -> rim or foam) and moves its top corners to the height the joined tiles share (visual only, collision stays flat). `HexGrid.update_tile_edges` runs after generation; destroyed / removed tiles refresh their neighbours (`refresh_edges_around`). Shader noise must use the integer `hash()` - the old `fract(p * big)` hash drew the noise cells as a grid of lines.
Water (`shaders/water.gdshader`): height-field normals, shore foam, SSR reflections (`GameEnvironment`), and player ripples uploaded by `WaterRipples` (added by `MapGenerator`; `WaterRipples.splash` for landings). Water and swamp slow walking: `MovementComponent.terrain_multiplier` from `HexTile.speed_factor` (ray down to the tile), identical on server and client.

### Map Destruction System

Located in `world/destruction/`:
- `DestructionSystem.gd` - Controls map destruction timing
- `TileDestroyer.gd` - Handles individual tile destruction

Replaces traditional battle royale zone by progressively destroying tiles: every phase eats more of the outer edge, sooner, until a 19-tile core is left.

### Cover and fog of war

- `world/cover/CoverSpawner.gd`: wall pieces (`CoverWall`, 1-3 hex edges, stone / wood / sandbags by biome) and `Bush`es, seeded from the map seed with its own RNG (server, clients and the client cutscene build identical cover). Walls stand on edges so tile centers stay free for spawns and containers; they are on the environment layer (movement, bullets) and `COVER_LAYER` (16: sight and line of fire). A client-reported hit through a wall is turned into a real shot at the wall (`ServerPlayer._process_client_hit`).
- `world/visibility/VisibilitySystem.gd`: per-tile sight (weapon range, rays against `COVER_LAYER`) + explored memory for the local player; enemies in a bush are hidden unless close or shooting. `FogOverlay` (`shaders/fog_overlay.gdshader`) is a full-screen pass that rebuilds world positions from the depth buffer, so everything it should fog must be opaque (tiles and water are; don't write ALPHA in `hex_tile.gdshader`). The minimap only shows explored tiles.

### Resource Types

Located in `core/resources/`:
- `CharacterData` - Character stats (health, speed) and ability references
- `WeaponData` - Weapon properties
- `ItemData` - Item definitions
- `AbilityData` - Ability configuration

### Adding New Content

**New character:**
1. Create resource file in `characters/data/` extending `CharacterData`
2. Set `character_name`, `base_health`, `base_speed`
3. Assign active/passive abilities

**New item:**
1. Create class in `inventory/items/` extending `ItemData`
2. Add to loot tables in `inventory/loot/`

### UI

All menus/HUD are built in code with `ui/theme/UITheme.gd` (glass palette, Nunito font, factory helpers). The global Theme is applied to the root window in `SceneTransition._ready`. Frosted panels: `GlassPanel` (blur via `shaders/ui_glass.gdshader`); menu background: `shaders/ui_background.gdshader`. 3D previews use `CharacterShowcase` (own World3D).

### AI model generation

`tools/ai_models/` (see its README): local text/image -> GLB pipeline (LCM Dreamshaper + rembg + TripoSR), heavy files in `D:\royaltim-ai`. Editor dock: `addons/ai_model_generator`.
`--rig` / `rig.bat` runs `tools/ai_models/blender/rig_and_animate.py` in Blender (auto skeleton + idle/walk/run/jump/land/attack/hit/death clips).
Concept characters (`art/concepts/`): `--palette <name>.palette.txt --concept raw/<name>_input.png` repaints the TripoSR mesh in flat palette colors (front projected from the picture) and decimates to low-poly; the palette files are hand-editable.
Props (`models/props/`): `tools/ai_models/blender/make_props.py` builds containers (with `Lid` / `Parachute` child nodes) and pickup models. `world/loot/LootVisuals.gd` maps loot types to models and glow colors; the container opening show (`LootContainer`) runs on every peer from the seeded loot roll, and items can't be picked up until they land (`LootItem.launch`).
Landing thuds: `HexTile.shake_around(node, pos, strength)` bounces tile meshes only (collision stays put); used by the cutscene, spawn drop-in, hard landings (`CharacterAnimator`) and supply drops.

### Character animation

`core/entities/CharacterAnimator.gd` (added in `Player.spawn`): procedural squash/waddle/lean for static models; plays skeletal clips when the model has an AnimationPlayer. `ModelUtils.apply_lowpoly_look` gives vertex-colored GLBs the shared paper material (`shaders/lowpoly_paper.gdshader`); Godot's importer does not always show vertex colors on its own.

## Key Input Actions

Defined in `project.godot`: `move_up/down/left/right`, `attack`, `interact` (E), `inventory` (I), `pause` (Esc), `ability_1-4` (F/G/H/J), `weapon_slot_1-5` (1-5), `reload` (R), `sprint` (Shift)