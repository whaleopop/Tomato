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
2. Override `_on_activate()` for active or `_on_apply()` / `update()` for passive
3. Reference in character data (every hero has its own active and passive: keep them unique)

An active runs on the caster's client (prediction), on the server (the real one) and as a visual replay on the clients that see the caster (`replay = true`): visuals everywhere, gameplay only where it counts - damage via `take_damage`, states via `StatusComponent` (both only count on the server anyway). Passives mostly set an entity meta that the rules read (`hot_temper`, `cc_immune`, `cooldown_factor`, `small_target`, `heal_bonus`, `thorns`).

`StatusComponent` (on every Player): `apply(kind, seconds, value)` for stun / slow / blind / stealth and `push(velocity, seconds)` for knockback, server-authoritative; the states reach clients in the player state (`ServerPlayer.get_sync_data` "fx" -> `NetworkingComponent` -> `from_sync`), so the victim's own client stops / slides / sees less like its server copy. Stealth and blindness feed `ServerVisibility` (and the host's `VisibilitySystem`).

Heroes move on the 60 Hz physics tick but are drawn between the last two physics positions (`Player.visual_position`, the "Model" / "WeaponVisual" nodes are offset in `_process`): with VSync off they used to hop. Don't move a hero's body in `_process`.

Heroes face +Z (`PlayerInputHandler`: `rotation.y = atan2(x, z)`), so "forward" is `basis.z` and the right hand is at -X - not Godot's usual -Z.

### Network Architecture

Server-authoritative multiplayer using ENet:
- **Server** (`network/server/`): `GameServer`, `ServerWorld`, `ServerPlayer`, `TickSystem`
- **Client** (`network/client/`): `GameClient`, `ClientWorld`
- **Sync** (`network/sync/`): `NetworkSync`

**Online** (see `tools/server/README.md`, live at 159.194.255.184): `tools/server/backend/royaltim_backend.py` (Python stdlib: SQLite accounts / profiles / rewards, matchmaking `MODES`, one game server process per match) + autoload `Online` (`network/online/Online.gd`: device key in `user://account.cfg`, `request()`; every answer's "profile" goes to `PlayerProfile.apply_remote`). While `PlayerProfile.online` the profile is the server's: no local saves, `buy` / `equip` / `register` / `choose_starters` also go to the server (`_remote`), match coins / XP are credited by the game server's report, the HUD only shows them. The backend checks prices against `catalog.json` (exported from the game by `tools/server/export_catalog.gd`, its rules mirror PlayerProfile / Mastery - keep them in step) and refuses clients of another `config/version`. PLAY = `ModeSelect` -> `CharacterSelect` (`GameManager.matchmaking`) -> `MatchmakingScreen` (queue, then connects and `NetworkLobby.client_present_ticket`) -> SpawnSelect; HOST LAN keeps the old listen server.
**Dedicated server** (`network/server/DedicatedServer.gd`): `MainMenu` hands over to it with `--server` (after `--`) or the `dedicated_server` feature (export presets "Linux Server (x86_64)" / "(arm64)"); `NetworkManager.start_server(port, true)` -> `GameServer.dedicated`: no host player 1, only clients play. Standalone (`--port`, `--mode`, `--min-players`): lobby after lobby in one process. Matchmade (`--match --roster --backend --key`, started by the backend): `GameServer.roster` tickets (`claim_ticket`: name and hero come from the roster), `LobbyManager.landing_deadline` / `force_start`, `/match/ready` and per-player `/match/report`, quits after the match. Anything the host did for the server must also work without a host.

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
- The zone runs on the server from match start (`DestructionSystem`) and every step goes out via `NetworkManager.broadcast_zone` (kinds warn / burn / rise / calm / core_warn / core_burn); the host's tiles are the server's own, remote clients apply it in `ClientWorld.apply_zone` and shove their own predicted player with the same `DestructionSystem.shove` / `unstick` the server uses. Raised tiles go to late joiners in the map info (`destroyed_tiles`), the step in progress via `send_zone_state_to`.
- `SceneTransition.fade_to_scene` queues requests made during a running fade; don't bypass it with bare `change_scene_to_file` in menus.
- Returning to `MainMenu` calls `NetworkManager.stop_all()`.
- Only the server applies gameplay damage: `HealthComponent.take_damage` returns 0 on clients (they get health from the sync via `_apply_damage`). Clients killing their copy of a player left unhittable "ghosts".
- Kills: `ServerPlayer._on_died` -> `NetworkManager.broadcast_kill(victim, killer, info)` (killer 0 = the zone / events / yourself) -> `player_killed` on every peer: `KillFeed` (top right), the victim's death card with the killer's hero card (`PlayerHUD._fill_killer_card`) and `Spectator` (the camera follows the killer, then any survivor; A / D switch; the eliminated see the whole map already).
- Match end: `GameServer._check_match_end` (last one standing among the players at match start, 2+ players) -> `NetworkManager.match_ended(winner_id, winner_name)` on every peer -> `PlayerHUD` result screen. The dead send no input (`PlayerInputHandler._input_blocked`, `ServerPlayer.process_input`).
- Input: one-shot actions are latched every frame and sent on the 30 Hz tick; visible nodes in group `blocks_game_input` (pause menu, inventory, result screen) stop gameplay input. Menu actions (inventory use/drop) go to the server via `PlayerInputHandler.send_ui_action`.
- Server-side fog (anti-wallhack): `TickSystem` sends each client its own world state; players it can't see (`ServerVisibility.can_see`: sight radius, cover walls, bushes) arrive as `{"hidden": true, health, max_health}` - clients keep a frozen invisible copy (`net_hidden` meta) or none at all, so count things like "alive" from `ClientWorld.last_player_states`, not from player nodes. Shots and ability casts only go to clients that can hear / see them.
- Ability casts are replicated: `AbilityComponent.ability_cast` -> `ServerPlayer` -> `NetworkManager.broadcast_ability_cast` -> `play_remote_cast` on the other clients' copies with `Ability.replay = true` (visuals only: no movement, no heals; damage is server-side anyway).
- Dropping (inventory menu DROP): `InventoryComponent.drop_weapon` / `drop_item` remove the thing on both sides; only the authority throws it on the ground - `NetworkLootManager.drop_from` (item described by `describe`, rebuilt by `make_item`, ids from `DROP_ID_START`, fanned out in front, `_client_spawn_drop` to everyone, `dropped` for late joiners). The dropper can't walk it back up for 2 s (`LootItem.no_auto_pickup_*`). `remove_weapon_from_slot` always emits `weapon_slot_changed` (the HUD slots) and empties the hands with `equip_ranged_weapon(null)`.
- Late joiners: the map info carries the loot history (`NetworkLootManager.get_late_join_state`: opened containers, picked items, supply drops); containers / items that register later are opened / removed then. Late join is only allowed for `GameServer.LATE_JOIN_WINDOW` seconds and never twice per `NetworkManager.client_token` (an eliminated player can't come back as a fresh one); refused clients get the reason via `NetworkLobby._receive_join_refused`.

### World Generation

Located in `world/generation/`. Tiles are big: `HexTile.HEX_RADIUS` = 2 (edge 2, centers 3.46 apart), `MapGenerator.MATCH_MAP_RADIUS` = 21 (1387 tiles, twice the old 15; the zone takes two rings per step above `DestructionSystem.WIDE_RADIUS`). Paths, huts (`MapGenerator._area_factor`) and stray containers (`LootSpawner`) scale with the map area; landmarks with the radius. The generator's noise and lake sizes are per tile (tuned for that); cover walls span a whole edge (`CoverWall.LENGTH`). Sight distances (weapon `visibility_range`, `VisibilitySystem` constants) are world units, converted with `VisibilitySystem.to_hexes()` - don't compare them with hex distances directly.
- `HexGenerator.gd` - Generates hexagonal grid structure
- `HexGrid.gd` - Grid management
- `HexTile.gd` - Individual tile representation
- `MapGenerator.gd` - Orchestrates map generation

Seamless ground: tile materials are shared (one per biome, one for all water, `ShaderHelper`); per-tile data goes in instance uniforms. `HexTile.update_edges` tells each tile what lies across its six edges (joined neighbour of the same kind and level -> colors blend; step / shore / void -> rim or foam) and moves its top corners to the height the joined tiles share (visual only, collision stays flat). `HexGrid.update_tile_edges` runs after generation; destroyed / removed tiles refresh their neighbours (`refresh_edges_around`). Shader noise must use the integer `hash()` - the old `fract(p * big)` hash drew the noise cells as a grid of lines.
Water (`shaders/water.gdshader`): height-field normals, shore foam, SSR reflections (`GameEnvironment`), and player ripples uploaded by `WaterRipples` (added by `MapGenerator`; `WaterRipples.splash` for landings). Terraces (`HexGenerator._build_terraces`, seeded, after the rim): land on `HexTile.level` 0-2, `TERRACE_STEP` (1.4) apart - a jump clears one; water / beach / swamp stay at 0, neighbours differ by at most one, the rim mountains stand at the height of the land inside. The level is baked into `tile.height` (so everything using the tile top works); every tile is a column down to `COLUMN_BOTTOM` (the shader paints steep faces as cliffs). Ramps: a lower tile with `ramp_dir` slopes up onto the plateau (tilted top and collision, `surface_offset()` for its middle; no loot, spawns, walls or huts on it). Higher ground sees further (`VisibilitySystem.high_ground_factor`, also in `ServerVisibility`); the zone's shove hops over ledges. Sprinting costs stamina (`MovementComponent.stamina`, drain / regen / `STAMINA_RESTART` after running dry), simulated on server and client alike, the server's value corrects the owner (player state "stamina", only to the owner) and the HUD shows it under the health bar. Water and swamp slow walking: `MovementComponent.terrain_multiplier` from `HexTile.speed_factor` (ray down to the tile), identical on server and client.

### Atmosphere (looks only, never synced)

- Ground: `hex_tile.gdshader` has a `grassy` look (sunlit swathes, blade grain) for grass biomes and drifting cloud shadows (the same field in `water.gdshader`). Water lies below its banks (`HexGenerator.WATER_TOP` / `SHALLOW_TOP`); `MovementComponent._step_up` climbs ledges up to `STEP_HEIGHT` (0.5) on server and client alike, and in the air (a jump into a wall) pulls up onto ledges up to `MANTLE_HEIGHT` above - that is how you climb out of the water under a terrace; cliffs otherwise need a jump or a ramp. The water has bank turquoise, caustics, foam lines and glints.
- `BiomeDecor` decorates every biome (tufts, dandelions, ferns, reeds, lilies, boulders, fences and vegetable beds along the paths - path tiles carry meta "path" from `MapGenerator._drunk_path`). MultiMesh instance colors are sRGB: `foliage_sway.gdshader` converts them, StandardMaterials use `vertex_color_is_srgb`.
- Trees (`GardenTree`, placed by `CoverSpawner` with its own RNG): the trunk is cover, the canopy dithers away around the local hero (global shader uniform `hero_position` in project.godot, set by `Player`).
- `Waterfalls` (from `MapGenerator`): where water meets a terrace, a spring arcs out of a rocky crack under the lip into a foam ring (`waterfall.gdshader`, `pool` = the ring). `GameEnvironment` turns the day into a sunset as the zone closes (`dusk`, `day_light()`; `MapEvents` returns to it after a night) and adds `AmbientLife` (pollen, leaves, butterflies, fireflies at night) and `AmbientSound` (wind, water near lakes / waterfalls, birds, crickets - synthesized with an AudioStreamGenerator, the project has no audio files).

### Special biomes and landmarks

- Biomes 9-13 (`HexTile.BiomeType` MEADOW, FROST, TALL_GRASS, MUSHROOM, THORNS; appended, the numbers go over the network) come in patches (`HexGenerator._add_special_biomes`: mask noise + cellular noise into `SPECIAL_BAG`). Effects live in `BiomeRules`: speed via `HexTile.speed_factor`, grip (frost) in `MovementComponent` from `terrain_biome` (identical on server and client), meadow healing / bramble damage / mushroom recharge in `StatusComponent._update_biome` (health only on the server), tall grass hides like a bush and mushroom spores cut sight in `VisibilitySystem` and `ServerVisibility`. The HUD status pill names the ground you stand on. Looks: `BiomeDecor` (MultiMesh "Decor" on the tile, `shaders/foliage_sway.gdshader`), rebuilt on `set_biome`.
- Landmarks (`world/landmarks/Landmark.gd`: windmill, greenhouse, watering can, scarecrow, compost heap): `Landmark.plan(grid, seed)` is pure (own RNG, keeps clear of huts via grid meta "huts"), so `LootSpawner` puts the chests around them (`RICH` ones at the greenhouse and the windmill; stray containers are few) and `CoverSpawner` builds them and keeps walls / bushes off. They block walking and bullets (greenhouse glass not sight), fall with their tile, show on the minimap (group `map_landmarks`) and on the landing map (tile meta "landmark").

### Map Destruction System

`world/destruction/DestructionSystem.gd` (server): the island closes in on a random tile near the middle, ring by ring. Each phase: the tiles outside the new radius are marked (`HexTile.set_zone_state` WARNED: glowing cracks, minimap, HUD countdown) -> BURNING (zone fire, `BURN_DAMAGE` per tick) -> `HexTile.raise_mountain` (a rock wall rises, players on it are shoved to the center, anyone still inside is thrown out and hurt). The outer ring is mountains from generation (`HexGenerator._raise_rim`), so nobody can fall off. When only the 7-tile core is left it catches fire every `CORE_WAIT` seconds. Mountains (`BiomeType.MOUNTAIN`) have a tall collision on `COVER_LAYER` (block walking, bullets and sight); `HexTile.is_playable()` = walkable tile. `time_scale` fast-forwards it in tests.

### Map events

`world/events/`: `MapEventDirector` (server, in `ServerWorld`) fires one every `GAP_MIN..GAP_MAX` s from a shuffled bag (meteors, harvest, quake, night / fog, flood, rift; flood and rift once per match), plus the zone's own: a rich supply drop into the next safe area on `ZONE_DROP_PHASES` (`DestructionSystem.phase_warned` -> `LootSpawner.drop_supplies_at(pos, true)`, `LootContainer.rich`) and the final center shift (`DestructionSystem.center_shift_announced`, applied at the next warning). It plans the data (spots, wall names, tiles) and hands it to `MapEvents.play` on the host and `NetworkManager.broadcast_map_event` -> `ClientWorld.apply_map_event` on clients; the HUD listens to `NetworkManager.map_event`. `MapEvents` (one per world) does the visuals and the world changes that must match (fallen walls by name, `HexTile.flood`, rift tiles -> `raise_mountain`, the harvest `LootItem` with the server's id); with `authority` it deals the damage and moves every player, a client only its own (like the zone). Global modifiers are static on `MapEvents` (`sight_factor`, `bush_factor`, `spread_factor`, read by `VisibilitySystem`, `ServerVisibility`, `CombatComponent`). Late joiners get `MapEventDirector.history_for_late_join()` (replayed with `elapsed`). New map-visible markers: put the node in group `map_markers` with meta `marker_color` (the minimap draws it). Update the guide's Events tab (`Encyclopedia._event_entries`) when events change.

### Hostile weeds (NPCs)

`world/enemies/`: `Weed` (Dandelion throws seed puffs from range, Hogweed is a slow brute whose sap burns and slows, Nettle is fast and stings; numbers in `Weed.KINDS`, models `models/enemies/*.glb` from `art/concepts/` through the AI pipeline) and `WeedSpawner` (server, in `ServerWorld`: at match start every land tile has `START_CHANCE` x a biome weight, up to `CAP`; a `WAVE_CHANCE` every `WAVE_EVERY` s away from heroes). On the server (`authority`) a weed picks the nearest visible, unstealthed hero in `aggro` (training dummies carry meta `training_dummy` and are ignored), chases within `LEASH` of home, strikes, goes home to heal, withers on burning / raised tiles, sometimes drops ammo or a health pack (`NetworkLootManager.drop_from`). It is shot like a player (`get_component("HealthComponent")`, `entity_id` = -npc id: `ServerPlayer._find_npc` resolves client-reported hits). Clients: `TickSystem` sends each one `WeedSpawner.states_for(viewer)` as "npcs", `ClientWorld._apply_npcs` keeps non-authority copies (`Weed.apply_state`); the host sees the server's own weeds. Seed throws go out via `NetworkManager.broadcast_npc_seed`. A weed kill goes out with `info.npc` (kill feed, death card); no player gets the kill. The fog hides weeds like players. The training ground has one of each up the field (they regrow); the guide's Events tab lists them.

### Game modes

The host picks the mode in `ModeSelect` (main menu PLAY: tall tilting `ModeCard`s with drawn `ModeEmblem`s, a details strip and PLAY) -> `GameManager.game_mode`; it reaches clients in the lobby state ("mode"). `network/modes/GameModes.gd` is the catalog (ids `br` / `survivors` / `ctf` / `koth` go over the network; `INFO`: names, card lines, color, whether the zone / map events / weeds run, teams, `respawn` seconds or -1). Server rules: `network/server/modes/ModeRules.gd` (base = battle royale: `check_end` last one standing) made by `ModeRules.make` in `GameServer._ready`; hooks `on_map_ready`, `start_position` (via `LobbyManager.mode_spawn`), `on_match_start`, `on_player_died`, `respawn_position`, `check_end`, `state_for(viewer)`, `on_choice`, `announce` (alert lines in the state).
- `KothRules`: platform at the land tile nearest the middle, a point a second when alone on it, `WIN_POINTS` / `TIME_LIMIT`.
- `CtfRules`: two teams dealt alternately (meta `team`, no friendly fire in `HealthComponent`, teammates and flag carriers always visible in `ServerVisibility` / `VisibilitySystem`), bases left / right, `CAPTURES_TO_WIN`, dropped flags return after `RETURN_TIME`; a team win is `winner_id = -1 - team`.
- `SurvivorsRules` (vampire-survivors-like co-op): `WAVE_TIME` waves of hunter weeds from `WeedSpawner.spawn` (bursts, tougher every wave), then the rest `Weed.wither` (no loot, no kill) and every hero standing gets a pick: the server deals two perk cards (`network/modes/SwarmPerks.gd`: each a buff over a debuff, never the same stat; ids go over the network) into that hero's mode state ("offer", "seq"); `ModeView` pops them up as holographic `PerkCard`s (`shaders/holo_card.gdshader`; click / 1 / 2, Tab later) and sends the card index (`send_ui_action({"mode_choice"})`), `SwarmPerks.apply` runs on the server and the owner's copy. Perks are metas / component values the game reads everywhere: `fire_rate_factor` / `range_factor` (`CombatComponent.shot_interval` / `reach` - use those, not the raw weapon numbers), `reload_factor`, `stamina_factor`, `crit_chance` / `lifesteal` (attacker side of `HealthComponent.take_damage`), `thorns`, `cooldown_factor`, `heal_bonus`, `sv_regen` / `wave_shield` (SurvivorsRules). Heroes get metas `auto_fire` (`PlayerInputHandler`: nearest visible weed in reach without a wall between, the hero turns to it and fires; holding attack aims by hand) and `endless_ammo` (reloads don't touch the reserve); everyone down ends it (`winner_name` "m:ss|wave|kills").
Respawn modes: `GameServer.on_player_died` -> `respawn_player` -> `Player.respawn_at` + `NetworkManager.broadcast_respawn`; the HUD shows a countdown instead of the death card. The mode state goes out per client in the world state ("mode") and on the host straight from `TickSystem` -> `NetworkManager.mode_state` -> `ui/hud/ModeView.gd` (score panel, hill ring, flags and bases, XP bar, upgrade picker; added by `GameSceneController` for every mode but BR). `PlayerHUD` result screen has a sub text per mode.

### Cover and fog of war

- `world/cover/CoverSpawner.gd`: wall pieces (`CoverWall`, 1-3 hex edges, stone / wood / sandbags by biome) and `Bush`es, seeded from the map seed with its own RNG (server, clients and the client cutscene build identical cover). Walls stand on edges so tile centers stay free for spawns and containers; they are on the environment layer (movement, bullets) and `COVER_LAYER` (16: sight and line of fire). A client-reported hit through a wall is turned into a real shot at the wall (`ServerPlayer._process_client_hit`).
- `world/visibility/VisibilitySystem.gd`: per-tile sight (weapon range, rays against `COVER_LAYER`) + explored memory for the local player; enemies in a bush are hidden unless close or shooting. `FogOverlay` (`shaders/fog_overlay.gdshader`) is a full-screen pass that rebuilds world positions from the depth buffer, so everything it should fog must be opaque (tiles and water are; don't write ALPHA in `hex_tile.gdshader`). The minimap only shows explored tiles and never other players (no giving enemies away).

### Weapons

12 guns (`RangedWeapon.WeaponType`, new ones appended: the number goes over the network): the original five keep their models (`models/pistol_1.glb`...), the other seven (SMG, Hand Cannon, Marksman, Minigun, Double Barrel, Jam Blaster, Grenade Launcher) use the Kenney Blaster Kit (`models/blaster-*.glb`, texture `models/Textures/colormap.png`, CC0). `fire_mode` decides how `CombatComponent` fires (single / spread / pierce / flame / lob) - add a gun by giving it stats and a mode, not a new branch; `effect_style`, `move_factor`, `slow_on_hit`, `blast_radius` are the extras. Only "single" shots are resolved by the client (`ServerPlayer._process_client_hit`), the rest by the server. Loot: `LootContainer.LOOT_TABLES` (one table per container type) + `GUARANTEED` (chests: a gun; supply drops: gun, shield, heal) + `loot_count` rolls; every gun drops with a pack of its own ammo, loose packs follow `ammo_weights()` (as common as the guns using them, from `WEAPON_WEIGHTS` - also the guide's rarity), pack sizes `AMMO_PER_PICKUP`, `HEALTH_PACK_HEAL`. The guide reads it all (`loot_summary`). All models have barrels along -Z: `WeaponVisualComponent` fits them to `RangedWeapon.hold_length` (metres for a 1.2 m hero) whatever the file's size, turns them to face the hero's +Z and holds them in the right hand at the front of the body. Reload: `CombatComponent.start_reload` takes the rounds from the reserve, `_complete_reload` puts them into the magazine; switching weapons calls `cancel_reload` (refund). The last round starts the reload on its own. Ammo pickups use the kit's clips and foam darts (`LootVisuals._ammo_file`).

### Cosmetics, shop, training ground

- `ui/profile/PlayerProfile.gd` (user://profile.cfg): coins (earned at match end in `PlayerHUD._reward_row`: match / kill / win; kills are counted on the server from `HealthComponent.last_attacker` -> `ServerPlayer.kills`, sent in the player state), bought cosmetics, what each hero wears.
- `ui/profile/Cosmetics.gd`: the catalog (patterns: `shaders/patterns.gdshaderinc`, shared by the hero shader and `shaders/weapon_finish.gdshader`; hats ride the `head` bone through a `BoneAttachment3D`) (hero skins, hats, weapon finishes - ids go over the network, weapon finish ids are `w_<name>`) and how they are applied: skins through instance uniforms of `shaders/lowpoly_paper.gdshader` (`skin_hsv`, `skin_tint`, `skin_metal`, `skin_glow`; the material stays shared), hats as small procedural models on the hero mesh, finishes as tinted copies of the gun's materials (`WeaponVisualComponent`).
- Mastery (`ui/profile/Mastery.gd`): XP per hero and per gun type from real matches (`PlayerProfile.add_match_xp` in `PlayerHUD._mastery_rows`; gun XP from the server's per-weapon stats `ServerPlayer.weapon_damage / weapon_kills`, credited only within `CombatComponent.WEAPON_CREDIT_MSEC` of a shot so abilities don't count) -> levels (max 25) and ranks Bronze / Silver / Gold / Obsidian / Diamond (`TIER_LEVELS`). Each rank unlocks a free skin for that hero (`Cosmetics.SKINS` "m_<rank>") and a camo for that gun (`WEAPON_SKINS` "m_<rank>", put on that gun only: `PlayerProfile.weapon_skin_by_type`, wear "weapons"); check ownership with `PlayerProfile.owns_for(id, hero, weapon_type)` (`owns` is false for mastery ids). Cards show it: `ParallaxCard.level` / `.mastery` (`show_hero_mastery`, `show_weapon_mastery`, `show_wear_mastery` for other players - the wear carries "level" / "mastery"), backdrop `shaders/card_background.gdshader` (rays, honeycomb, rank materials). The main menu's backdrop is `MenuDiorama` (own World3D: real game hex tiles, trees and cover walls in the golden hour, the arsenal rack with all 12 guns in the finishes they wear and a mastery plate under each, loot props around; `show_hero` puts the heroes you own, in what they wear, on the dais in turn).
- Sync: `NetworkLobby.client_set_character` sends the wear with the hero -> `LobbyManager.players_cosmetics` -> `ServerPlayer.cosmetics` -> player state "cosmetics" -> `Player.cosmetics` on every peer (the local player takes its own from the profile in `setup_character`).
- `ui/menus/Shop.gd` (main menu SHOP): heroes, skins, hats and gun finishes as `ParallaxCard`s (the card is drawn in its own SubViewport; `shaders/card_tilt.gdshader` tilts it in perspective towards the mouse while its layers slide, and cuts the rounded corners - the layers under the frame are plain rectangles). The middle of the shop is a big `CharacterShowcase` with `interactive = true` (drag to turn / tilt, wheel to zoom, double click to reset) showing the chosen hero / skin / hat / gun finish; above it chips pick the hero (skins, hats) or gun (finishes) the cards are tried on, the arrows at its sides step through them, and the header says what to do on each tab (`Shop.STEPS`). Card pictures come from `ItemRenderer` (one hidden 3D viewport, a queue, a cache; wait two `frame_post_draw` before reading the picture). The inventory menu, the HUD weapon slots and `ConsumableBar` show item pictures from `ItemRenderer.icon_for(item)` (guns in their finish, true to size between guns: `LootVisuals.weapon_scale` from `hold_length`, fitted by the barrel with `fit_length`, all in one `gun_frame`; pickups cropped to the model by `cropped`). Cosmetics are looks only - never stats.
- First start (`ui/menus/Onboarding.gd`, from the main menu): a local nickname (no online accounts) and one of `PlayerProfile.STARTER_HEROES`; other heroes are bought (`Cosmetics.HERO_PRICES`, ids `hero:<Name>`), `CharacterSelect` (laid out like the shop: `HeroChips` portraits over an interactive `CharacterShowcase`, the hero's `ParallaxCard` on the right) only lets you play owned ones and sells the others on the spot (the training ground has them all). The landing map is a 3D diorama (`ui/components/HexMap3DView.gd`: columns at the real tile heights, ramps from the map data's `ramp`, rim mountains, landmarks; orbit camera, ray-marched picking) with the flat `HexMapView` behind a 2D / 3D button - both take the same tiles / reserved / selection. The landing lobby (`SpawnSelectMenu`) lists each player with the hero's portrait (lobby state carries `players_characters` / `players_cosmetics`) and pops the hero's card on hover. Coins per match come from the server's stats (`ServerPlayer.kills / damage_dealt / place / alive_time` -> player state "stats" -> `PlayerProfile.match_reward`).
- Training ground (main menu TRAINING GROUND): `GameManager.training_mode` makes `GameSceneController` build `scenes/training/TrainingGround.gd` offline - every gun on racks (respawning pickups), ammo, dummies that never go down, target boards, a damage meter; Tab opens `HeroPicker` (every hero as a shop card), [ ] step through the heroes.

### Resource Types

Located in `core/resources/`:
- `CharacterData` - Character stats (health, speed) and ability references
- `WeaponData` - Weapon properties
- `ItemData` - Item definitions
- `AbilityData` - Ability configuration

### Adding New Content

**New character** (all 13 heroes are built from concept art, see `tools/ai_models/README.md`):
1. Concept picture `art/concepts/<name>.png` -> `generate.bat --image ... --out art/concepts/raw/<name>.glb`, palette file, then `rig_and_animate.py --palette ... --concept ...` -> `models/characters/<Name>.glb`
2. Data class in `characters/data/` extending `CharacterData` (`model_path`, `model_scale = 1.0`, `model_origin_at_feet = true`, stats, abilities) and an entry in both lists of `CharacterRegistry`
3. Russian names / descriptions of the hero and both abilities in `LocaleRu.STRINGS`; the guide picks the hero up from the registry

**New item:**
1. Create class in `inventory/items/` extending `ItemData`
2. Add to loot tables in `inventory/loot/`

### UI

All menus/HUD are built in code with `ui/theme/UITheme.gd` (glass palette, Nunito font, factory helpers). The global Theme is applied to the root window in `SceneTransition._ready`. Frosted panels: `GlassPanel` (blur via `shaders/ui_glass.gdshader`); menu background: `shaders/ui_background.gdshader`. 3D previews use `CharacterShowcase` (own World3D; `show_character` or `show_model` for any prop).
The main menu's guide (`ui/menus/Encyclopedia.gd`) lists heroes, weapons, pickups and containers with the real numbers from the game data (`CharacterRegistry`, `RangedWeapon.create_weapon`, `LootContainer.DEFAULT_LOOT_WEIGHTS` / `WEAPON_WEIGHTS`, `LootSpawner.DEFAULT_CONTAINER_WEIGHTS`) plus controls and rules - update it when content changes.

**Localization** (`ui/i18n/`): code keeps English source strings; `Locale.setup` installs the Russian catalogue `LocaleRu.STRINGS` (default language, `GameSettings.language`, switchable in Settings) and Godot auto-translates every Control / Label3D text that matches a key. So:
- every new player-visible string needs a key in `LocaleRu.STRINGS`;
- formatted text must translate the pattern first: `tr("%d  ALIVE") % n` (`Locale.t()` in static / RefCounted code);
- uppercase with `Label.uppercase = true` or `tr(x).to_upper()`, never `x.to_upper()` before translating;
- character, ability and item names are ids too (registry lookups, network, model paths): keep them English in code and translate only for display; `tr(name, "short")` gives the short forms in `LocaleRu.SHORT` (weapon slots).

### AI model generation

`tools/ai_models/` (see its README): local text/image -> GLB pipeline (LCM Dreamshaper + rembg + TripoSR), heavy files in `D:\royaltim-ai`. Editor dock: `addons/ai_model_generator`.
`--rig` / `rig.bat` runs `tools/ai_models/blender/rig_and_animate.py` in Blender (auto skeleton + idle/walk/run/jump/land/attack/hit/death clips).
Concept characters (`art/concepts/`): `--palette <name>.palette.txt --concept raw/<name>_input.png` repaints the TripoSR mesh in flat palette colors (front projected from the picture) and decimates to low-poly; the palette files are hand-editable.
Pickups: health packs (`HealthPack`) and shields (`ShieldPack`) go into the bag and take time to use (`InventoryComponent.start_use` / `USE_TIMES`, keys `use_heal` Q / `use_shield` E, input "use_consumable" to the server; walking halved, shooting or casting cancels, the heal / shield counts only on the server; HUD `ConsumableBar`); the shield (`HealthComponent.add_shield`, max `MAX_SHIELD`) absorbs damage before health on the server and reaches clients in the player state (`shield`); the ability crystal calls `AbilityComponent.boost_cooldowns`. Pickup effects run on the server entity and on the picker's own client.
Props (`models/props/`): `tools/ai_models/blender/make_props.py` builds containers (with `Lid` / `Parachute` child nodes) and pickup models. `world/loot/LootVisuals.gd` maps loot types to models and glow colors; the container opening show (`LootContainer`) runs on every peer from the seeded loot roll, and items can't be picked up until they land (`LootItem.launch`).
Landing thuds: `HexTile.shake_around(node, pos, strength)` bounces tile meshes only (collision stays put); used by the cutscene, spawn drop-in, hard landings (`CharacterAnimator`) and supply drops.

### Trailers

`dev/trailers/` (see its README): `TrailerDirector.gd` stages the real game offline (heroes + abilities, weapons, loot, zone, map events) with a scripted camera and captions; `record_all.ps1` records the reels with Godot's Movie Maker and converts them to `trailers/*.mp4` (git-ignored); `highlights.py` cuts `trailers/trailer.mp4` from the `MARK` lines in the reel logs. Shared visuals used there and in the game: `effects/AbilityFX.gd` (juice blobs and splashes, slash arcs, floating damage / heal numbers over players).

### Character animation

`core/entities/CharacterAnimator.gd` (added in `Player.spawn`): procedural squash/waddle/lean for static models; plays skeletal clips when the model has an AnimationPlayer. `ModelUtils.apply_lowpoly_look` gives vertex-colored GLBs the shared paper material (`shaders/lowpoly_paper.gdshader`); Godot's importer does not always show vertex colors on its own.

## Key Input Actions

Defined in `project.godot`: `move_up/down/left/right`, `attack`, `interact` (X), `inventory` (I), `pause` (Esc), `ability_1-4` (F/G/H/J), `weapon_slot_1-5` (1-5), `reload` (R), `sprint` (Shift), `camera_mode` (V); players rebind them in Settings -> Controls (`Keybinds`)

Camera (`world/CameraController.gd`): top-down by default at a fixed zoom (`min_zoom`, the closest; no wheel / +/- zoom in either mode; locked behind the hero by default (`locked` / `GameSettings.camera_locked`, a Settings checkbox): the mouse is captured, left / right turns hero and view together, up / down sets `aim_distance` (up to `aim_distance_max()`: the gun's range, capped by what the screen shows; the view runs ahead by the gun's `_look_ahead_reach` times how far you aim), the crosshair is `locked_aim_point()` ahead of the hero - `locked_active()` is false while spectating / dead, then the free cursor comes back; it looks at the hero almost straight down, `DEFAULT_PITCH`, and follows as a rigid rig: one focus point = `Player.visual_position()` + a look-ahead towards the cursor (dead zone, smoothstep, eased), camera at a fixed offset looking at it, all exponential-decay smoothing - it never turns on its own and no keys or mouse buttons turn it; the OS cursor is hidden while playing, `_update_cursor_hidden`); V switches to third person (`third_person`, saved in `GameSettings.third_person`): captured mouse turns the view, RMB aims closer over the shoulder, the hero faces `tps_forward()` and aims at the screen center - use `CameraController.aim_screen_point(viewport)` instead of the raw mouse position for anything aimed. The mouse is freed while a `blocks_game_input` node is visible.

Aim HUD (`ui/hud/`): `AimOverlay` draws, projected onto the ground at the hero's feet, a ring under the hero, the gun's reach (aim line up to `RangedWeapon.range`, red past it; spread / flame cones; the launcher's blast circle), the ability being aimed and an edge arrow back to the hero when the view ran ahead of them. The top-down look-ahead grows with the gun's `visibility_range` (`CameraController._look_ahead_reach`). Abilities are hold-to-aim, release-to-cast (`PlayerInputHandler.aiming_ability`; RMB cancels); each active ability describes its area in `aim_preview()` (circle / cone / line / self) - keep it next to the numbers when an ability changes. The crosshair (`PlayerHUD.Crosshair`) changes with `fire_mode`. `DamageIndicator` draws red arcs towards whoever hit you from `HealthComponent.hit_from`: the server emits it in `take_damage`, `ServerPlayer` keeps the last second of hits in the player state ("hits", stripped by `TickSystem` for everyone but the victim) and `NetworkingComponent` re-emits them on the victim's client. Tracers (`WeaponEffects.create_tracer`) are a thick core plus a soft glow.
