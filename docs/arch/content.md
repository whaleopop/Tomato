# Content pipeline: adding heroes / items, AI models, props, sound, trailers, animation

(Split out of CLAUDE.md; CLAUDE.md keeps the rules every change needs.)

### Adding New Content

**New character** (all 13 heroes are built from concept art, see `tools/ai_models/README.md`):
1. Concept picture `art/concepts/<name>.png` -> `generate.bat --image ... --out art/concepts/raw/<name>.glb`, palette file, then `rig_and_animate.py --palette ... --concept ...` -> `models/characters/<Name>.glb`
2. Data class in `characters/data/` extending `CharacterData` (`model_path`, `model_scale = 1.0`, `model_origin_at_feet = true`, stats, abilities) and an entry in both lists of `CharacterRegistry`
3. Russian names / descriptions of the hero and both abilities in `LocaleRu.STRINGS`; the guide picks the hero up from the registry

**New item:**
1. Create class in `inventory/items/` extending `ItemData`
2. Add to loot tables in `inventory/loot/`

### Sound

`effects/Sfx.gd`: `Sfx.at(id, pos)` (3D, where it happens), `Sfx.own(id)` (your own hero, flat), `Sfx.ui(id)` (menus), `Sfx.shot(weapon_type, pos)`; per-sound range / pitch spread / max copies in `TUNE`; nothing plays headless. The files are `audio/sfx/<id>.ogg`, cut from FL Studio's factory packs (`D:/flstud/Data/Patches/Packs`, many .wav there are Ogg inside RIFF - `unwrap`) by `tools/audio/make_sfx.py` (table: sample, cut, pitch, mean loudness; rerun it after changing). Buses "SFX" / "UI" / "Ambient" under Master (`Sfx.ensure_buses`, volumes in `GameSettings`, four sliders in Settings). The listener is at the hero turned like the view (`CameraController._update_listener`), not up with the camera. Every peer plays what it sees: shots in `CombatComponent._perform_hitscan_attack` and `NetworkManager._create_remote_shot_effects` (one or the other, never both), blasts in `GrenadeFX.explode`, thuds in `HexTile.shake_around`; new sounds = a row in make_sfx.py + a call at the event.

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
