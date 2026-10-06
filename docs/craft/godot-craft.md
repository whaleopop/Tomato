# Godot craft: quality code for 3D, performance and networking

Practices for ROYALTIM-3 (Godot 4.7, GDScript). Project rules (invariants, tick rates) are in CLAUDE.md; this is how to write code that holds up.

## GDScript
- Static types everywhere: `var speed: float`, `:=` for inferred, typed arrays `Array[Weed]`, return types. Faster and the compile hook catches more.
- Constants for tuning numbers, at the top, named with units: `const BURN_DAMAGE := 4.0  # per tick`. No magic numbers in the body.
- Early returns over nested ifs. Short functions named for what they do.
- After every `await` the node may be gone: `if not is_instance_valid(self): return`. Same for stored references to other nodes.
- Signals for "something happened", direct calls for "do this". No `get_node("../../..")` chains; pass references or use groups.
- Comments say why, not what. Match the surrounding file's style.

## Performance (60 Hz physics, low-end laptops)
- Nothing allocates in `_process` / `_physics_process` that could be cached: no `get_nodes_in_group`, `find_children`, new arrays / dictionaries / strings per frame in hot loops.
- Cache node refs (`@onready`). Turn off what's idle: `set_process(false)`, `set_physics_process(false)`.
- Repeated geometry: MultiMesh (decor, grass). Shared materials; per-instance looks via instance uniforms (`set_instance_shader_parameter`), never `material.duplicate()` per object per frame.
- Physics queries (raycasts, shape casts) are not free: limit per frame, reuse `PhysicsRayQueryParameters3D`, use the right collision masks.
- Visibility ranges / LOD for far decor; lights without shadows unless they matter.
- Measure before optimizing: Godot profiler / `Performance.get_monitor`. Say the numbers.

## 3D look (low-poly paper)
- Vertex-colored meshes get `ModelUtils.apply_lowpoly_look` (shared `lowpoly_paper.gdshader`); MultiMesh / StandardMaterial vertex colors are sRGB (`vertex_color_is_srgb`).
- Readable from top-down: strong silhouettes, value contrast between hero / ground / cover, no thin details that vanish at game zoom.
- Shader noise uses integer `hash()`; never write ALPHA in opaque ground shaders (the fog pass needs depth).
- Feedback is half of feel: hit = sound + flash + number in the same frame; a small hitstop / shake for big hits only; telegraph enemy attacks before they land.

## Networking (decide authority first)
- For every feature write down: who simulates (server), who predicts (owning client), who replays (other clients), what goes over the wire and how often.
- Server validates everything a client sends: ranges, cooldowns, distances, line of sight, rate. A client message is a request, never a fact.
- Reliable RPCs for events (kill, pickup, cast), `unreliable_ordered` state for continuous values. Send ids, not node paths or objects.
- Shared generation is seeded with its own RNG (`RandomNumberGenerator` with the map seed), never the global one, so all peers match.
- Cases to walk through before calling it done: listen-server host (both server and client in one process - don't apply things twice), dedicated server (no player 1, headless: no visuals, no sound), remote client, late joiner, spectator / dead player, disconnect in the middle of the action, the fog (does a hidden player leak through this?).
- Headless: guard visuals / audio so a dedicated server doesn't build them (`DisplayServer.get_name() == "headless"`, or the project's existing guards like `Sfx`).

## Quality bar for any change
- It compiles (hook), it runs (tester), and it was looked at (screenshot for visuals, numbers for gameplay).
- No dead code, debug prints or commented-out blocks left behind.
- Content changes update the guide, LocaleRu and the area doc.
