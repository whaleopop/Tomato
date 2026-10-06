# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ROYALTIM-3 is a 3D top-down battle royale game built with **Godot 4.7** (Steam build 4.7.2) featuring anthropomorphic vegetables and fruits as characters. The game uses a procedurally generated hexagonal map with a destruction system instead of a shrinking zone.

## Agents (`.claude/agents/`)

**The main session is the orchestrator - always, for every task.** It talks with the user, splits the work, hands each part to an agent, checks what comes back and reports. It does not write or edit code itself (game code, shaders, tools) and does not do long reading itself: that is `coder` and `reader`. It may edit only CLAUDE.md, `docs/arch/`, memory and `.claude/` directly. Context economy: CLAUDE.md holds only what every change needs; area details live in `docs/arch/` (skills `network`, `world`, `gameplay`, `meta-ui`, `content`, `controls` load them) - tell each agent which area docs to read instead of pasting them. Model split (the user's rule): **Opus only plans and accepts; Sonnet does all the work and checks itself.** Run the main session on Sonnet (`/model sonnet`); Opus appears only as `planner` and `reviewer`.
Flow:
1. Understand: `reader` (code), `docs` (APIs) - in parallel.
2. Plan (Opus): `planner` for anything that touches more than one system, networking, or isn't obvious; show the plan to the user when they asked to see it first.
3. Build + verify (Sonnet): `builder` with the goal, the plan, the files and the facts already found - it codes, tests headless and self-reviews in a loop (max 3 rounds) until clean. Independent file-disjoint parts may go to several builders in parallel, never two on the same file.
4. Accept (Opus): `reviewer` once on the finished diff, starting from the builder's "open doubts"; findings go back to the same builder (SendMessage, context kept), then the reviewer re-checks only those findings.
Small tasks skip 2; tiny ones (a string, an icon) may skip 4. `coder` / `tester` stay for one-off edits or a test on its own.
Token economy (measured on a real session - each spawn costs ~35-45k tokens before it does anything, each extra turn re-sends its whole context):
- Batch: one coder per coherent work package; don't split small edits (a few icon swaps) over several coders. Parallel coders only for big, file-disjoint parts.
- Test after the wave: start `tester` when the coders it depends on have finished, not while files are still changing.
- Ask every agent for a short hand-back (about 15 lines: what changed / found, paths, open issues) - long reports fill the orchestrator's context for the rest of the session.
- Large screenshots (4K) are expensive in the orchestrator's context; prefer a tester describing them, or crop.
- A new big task is a new session; don't run several jobs in one context. The orchestrator is the biggest cost (6-9M per session at 56-71 turns, every turn re-sends everything): one dense brief beats several small follow-ups, and when the task is done say so and suggest a fresh session for the next one.
- One `planner` per task, not per sub-step: pure UI / visual work usually needs none, a network / multi-system change needs one plan covering all of it (3 planners in one session cost 2.7M).
- Size a coder package for ~15-20 turns; a coder's context grows every turn too (one 37-turn coder cost 2.85M). Bigger work = split into file-disjoint packages.
- In briefs, point at code by `path:line`, don't paste code blocks for the coder to match - quoted code loses tabs and broke 11 Edits in one session.

Briefing an agent - dense, in English (Russian costs ~2x the tokens), no pleasantries, no restating CLAUDE.md (they have it):
```
GOAL: one sentence, the outcome the user wants.
KNOWN: facts already found - paths:lines, APIs, decisions - so it doesn't search again.
DO: steps / files. Parallel agents: which files are theirs, which are someone else's.
DON'T: out of scope, files not to touch.
READ: the area docs / craft docs that apply (docs/arch/*.md, docs/craft/ui-design.md, docs/craft/godot-craft.md).
DONE WHEN: the concrete check.
REPORT: <=15 lines - changed / found, paths, open issues, and SNAGS: one line on what cost time (wrong guess, failed command, missing info in this brief).
```
Coder cookbook: `docs/craft/cookbook.md` (real snippets: state field, fog-aware broadcast, UI action to the server, server-only gameplay, active / passive ability, a screen, translation, icons, HiResView, Sfx, tweens) - put it in READ for coder tasks that match.

Retro after every task that used agents (the user wants it; keep it short):
1. `python .claude/tools/session_report.py` - tokens per agent and flags (BASH-EDITS, POLLING, REPEATS, ERRORS).
2. Add the agents' SNAGS lines from their hand-backs.
3. Append 3-6 lines to `.claude/retro.md`: date, task, cost by model, what went wrong, what was changed.
4. A mistake seen twice becomes a fix in the agent prompt / cookbook / craft doc at once - don't just log it.
5. Tell the user in 2-3 lines in Russian.

Quality docs (`docs/craft/`, skills `ui-design` / `godot-craft`): any screen, HUD or visual polish -> ui-design; gameplay, 3D, effects, networked code -> godot-craft. Name them in READ. Commits stay with the orchestrator, only when the user asks.

Agents (each model is fixed in its file, whatever the main session runs on):
- `builder` (sonnet): the default worker - code + headless test + self-review against the invariants, looped until clean, then hands back for the Opus `reviewer`.
- `coder` (sonnet): one-off edits; the only one besides `builder` that changes code; follows the plan, the invariants and the compile hook, reports changed files and what to test.
- `reader` (haiku): code search / "where is X" / collecting excerpts - use it instead of reading many files yourself.
- `docs` (haiku): current docs from the web (Godot 4.7 class reference, Blender API, ...) - ask it whenever an API detail matters; don't trust memory for Godot APIs.
- `planner` (opus): plans for features that touch server + client + UI, networking, tricky bugs - before writing code; it checks the plan against the invariants below.
- `asset-scout` (haiku): free low-poly models / textures / sounds / icons in the game's style, CC0 first, judged from preview pictures; downloads only into `art/incoming/` (git-ignored, `.gdignore`) with a `SOURCE.txt`.
- `asset-import` (haiku): `art/incoming/` -> game-ready GLB with `tools/ai_models/blender/asset_tool.py` (convert, scale to the 1.2 m hero, barrels along -Z, origin at the feet, preview render next to a hero stand-in); into `models/` only when asked.
- `tester` (haiku): runs the change headless in Godot (scratch tests, offline backend, profile backup) and reports PASS / FAIL with output - use it before calling a change done.
- `reviewer` (opus): checks the diff against the invariants below (network, fog, appended enums, LocaleRu keys, dedicated server) before a commit / release.
Run independent agents in parallel; give each the context it needs (they start cold).
Hook (`.claude/settings.local.json`): every Edit / Write of a `.gd` is compiled in headless Godot (`.claude/hooks/check_gd.py` -> `check_scripts.gd`, after the autoloads, offline backend); errors come back at once - the agent that edited fixes them before moving on.

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
- Keep the state small (it goes to every client 20 times a second; over ~1.4 KB a packet is split and one lost piece drops it all): `TickSystem.SLOW_KEYS` (character_name, cosmetics, stats) go to a client only when they change or once a second, `ClientWorld.apply_world_state` keeps the last ones; weeds travel as a `PackedInt32Array` (`Weed.get_state`, 40 bytes). A visible player is still ~440 bytes (string keys) - new per-tick fields cost every client.

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
- Hit registration: "single" bullets are judged by the client with the gun's spread and checked by the server (`ServerPlayer._process_client_hit`, rewind, `SHOT_GRACE`); details in `docs/arch/network.md`.
- Ability casts are replicated: `AbilityComponent.ability_cast` -> `ServerPlayer` -> `NetworkManager.broadcast_ability_cast` -> `play_remote_cast` on the other clients' copies with `Ability.replay = true` (visuals only: no movement, no heals; damage is server-side anyway).
- Dropping (inventory menu DROP): `InventoryComponent.drop_weapon` / `drop_item` remove the thing on both sides; only the authority throws it on the ground - `NetworkLootManager.drop_from` (item described by `describe`, rebuilt by `make_item`, ids from `DROP_ID_START`, fanned out in front, `_client_spawn_drop` to everyone, `dropped` for late joiners). The dropper can't walk it back up for 2 s (`LootItem.no_auto_pickup_*`). `remove_weapon_from_slot` always emits `weapon_slot_changed` (the HUD slots) and empties the hands with `equip_ranged_weapon(null)`.
- Late joiners: the map info carries the loot history (`NetworkLootManager.get_late_join_state`: opened containers, picked items, supply drops); containers / items that register later are opened / removed then. Late join is only allowed for `GameServer.LATE_JOIN_WINDOW` seconds and never twice per `NetworkManager.client_token` (an eliminated player can't come back as a fresh one); refused clients get the reason via `NetworkLobby._receive_join_refused`.

### Area docs (`docs/arch/`, read the one for the area before working there)

- `network.md` - online backend / accounts / shop on the server, friends and parties, dedicated server, self-update, snapshot smoothness, hit registration details.
- `world.md` - map generation, terraces, water, atmosphere, special biomes, landmarks, the zone (DestructionSystem), map events, cover and fog of war.
- `gameplay.md` - hostile weeds (NPCs), game modes (KotH, CTF, Weed Swarm, perks), the 12 weapons and loot, resource types.
- `meta-ui.md` - cosmetics, shop, mastery, menu diorama, onboarding, training ground, the UI template, the guide.
- `content.md` - adding a hero / item, AI model pipeline, pickups, props, sound files, trailers, character animation.
- `controls.md` - input actions, camera modes, aim HUD, damage indicator.

### UI scale and icons (every UI change)

- The UI is laid out on a virtual 1920x1080 canvas (`canvas_items` / `expand`): 1080p x1, 1440p x1.33, 4K x2; `UIScale.apply` (+ `GameSettings.ui_scale`, Settings -> Video) sets `content_scale_factor`. Positions / sizes are virtual units; mouse look uses `event.screen_relative`, never `relative`.
- 3D previews inside the UI extend `HiResView` (viewport rendered at size x `UIScale.render_scale`, max x2); convert picking / unproject with `to_vp` / `from_vp`; a subclass `_init` must call `super()` first.
- Icons: `UITheme.icon(name)` / `create_icon` / `create_icon_label` / `create_icon_chip(..., tooltip)` (white SVGs in `art/ui/icons/`, Kenney PNGs in `art/ui/kenney/`). Never put symbol glyphs in UI text - Nunito has only `‹ › » · • —`, the rest fall back to OS fonts or tofu.

### Localization

**Localization** (`ui/i18n/`): code keeps English source strings; `Locale.setup` installs the Russian catalogue `LocaleRu.STRINGS` (default language, `GameSettings.language`, switchable in Settings) and Godot auto-translates every Control / Label3D text that matches a key. So:
- every new player-visible string needs a key in `LocaleRu.STRINGS`;
- formatted text must translate the pattern first: `tr("%d  ALIVE") % n` (`Locale.t()` in static / RefCounted code);
- uppercase with `Label.uppercase = true` or `tr(x).to_upper()`, never `x.to_upper()` before translating;
- character, ability and item names are ids too (registry lookups, network, model paths): keep them English in code and translate only for display; `tr(name, "short")` gives the short forms in `LocaleRu.SHORT` (weapon slots).
