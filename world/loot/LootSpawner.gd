## Spawns loot containers across the map
extends Node3D
class_name LootSpawner

signal containers_spawned(count: int)
signal supply_drop_spawned(container: LootContainer)

@export var container_density: float = 0.05  # Chance per tile to spawn a stray container (most loot is at landmarks)
@export var min_containers: int = 8
@export var max_containers: int = 20
@export var supply_drop_interval: float = 60.0  # Seconds between supply drops
## Supply drops are decided by the server only (see start_supply_drops) and replicated
## to clients through spawn_supply_drop_at(), otherwise every peer would drop its own.
@export var enable_supply_drops: bool = false

var spawned_containers: Array[LootContainer] = []
var hex_grid: HexGrid = null
var supply_drop_timer: float = 0.0

# Own RNG seeded from the map seed: server and clients place identical containers
# with identical loot, independent of whatever else consumed the global RNG.
var rng := RandomNumberGenerator.new()

# Container type weights
const DEFAULT_CONTAINER_WEIGHTS = {
	LootContainer.ContainerType.CRATE: 50,
	LootContainer.ContainerType.CHEST: 25,
	LootContainer.ContainerType.BARREL: 20,
	LootContainer.ContainerType.SUPPLY_DROP: 5
}
var container_weights: Dictionary = DEFAULT_CONTAINER_WEIGHTS.duplicate()

func _ready():
	pass

func _process(delta: float):
	if enable_supply_drops:
		supply_drop_timer += delta
		if supply_drop_timer >= supply_drop_interval:
			supply_drop_timer = 0.0
			_spawn_supply_drop()

var map_seed: int = 0

func setup(grid: HexGrid, seed_value: int = -1):
	hex_grid = grid
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	map_seed = seed_value if seed_value >= 0 else int(rng.seed)
	spawn_initial_containers()

func start_supply_drops():
	enable_supply_drops = true
	supply_drop_timer = 0.0

func spawn_initial_containers():
	if not hex_grid:
		print("[LootSpawner] ERROR: No hex grid set")
		return

	var spawn_positions: Array[Vector3] = []
	var tiles = hex_grid.get_all_tiles()
	var plan = Landmark.plan(hex_grid, map_seed)  # most chests stand at the landmarks
	var taken = Landmark.footprint(plan)

	# Collect valid spawn positions
	for tile in tiles:
		if not tile.is_playable():
			continue
		if tile.biome_type == HexTile.BiomeType.WATER or tile.is_ramp():
			continue  # nothing stands on a slope
		if taken.has(tile.hex_coords):
			continue

		# Random chance to spawn
		if rng.randf() < container_density:
			var world_pos = hex_grid.hex_to_world(tile.hex_coords)
			world_pos.y = tile.height * HexTile.HEX_HEIGHT + HexTile.HEX_HEIGHT * 0.5  # top of the tile
			spawn_positions.append(world_pos)

	# Clamp to min/max
	_shuffle(spawn_positions)
	var count = mini(clampi(spawn_positions.size(), min_containers, max_containers), spawn_positions.size())
	spawn_positions.resize(count)

	# Spawn containers
	for pos in spawn_positions:
		var container = _create_container(_roll_container_type())
		container.loot_seed = rng.randi()
		container.position = pos
		add_child(container)
		spawned_containers.append(container)

		# Connect signals
		container.container_destroyed.connect(_on_container_destroyed)

	# The landmarks' chests (the greenhouse and the windmill hold the good stuff)
	for entry in plan:
		for c in entry.chests:
			var tile = hex_grid.get_tile(c)
			var container = _create_container(LootContainer.ContainerType.CHEST)
			container.loot_seed = rng.randi()
			container.rich = Landmark.RICH[entry.kind]
			container.position = hex_grid.hex_to_world(c) + Vector3(0, CoverSpawner.tile_top(tile), 0)
			add_child(container)
			spawned_containers.append(container)
			container.container_destroyed.connect(_on_container_destroyed)

	print("[LootSpawner] Spawned %d containers" % spawned_containers.size())
	containers_spawned.emit(spawned_containers.size())

func _create_container(type: LootContainer.ContainerType) -> LootContainer:
	var container = LootContainer.new()
	container.container_type = type

	# Adjust properties based on type
	match type:
		LootContainer.ContainerType.CRATE:
			container.health = 30.0
			container.loot_count = 1
		LootContainer.ContainerType.CHEST:
			container.health = 50.0
			container.loot_count = 2
			container.guaranteed_health = true
		LootContainer.ContainerType.BARREL:
			container.health = 20.0
			container.loot_count = 1
			container.guaranteed_health = false
		LootContainer.ContainerType.SUPPLY_DROP:
			container.health = 100.0
			container.loot_count = 4
			container.guaranteed_health = true

	return container

func _roll_container_type() -> LootContainer.ContainerType:
	var total_weight = 0
	for weight in container_weights.values():
		total_weight += weight

	var roll = rng.randi() % total_weight
	var current = 0

	for container_type in container_weights:
		current += container_weights[container_type]
		if roll < current:
			return container_type

	return LootContainer.ContainerType.CRATE

func _spawn_supply_drop():
	if not hex_grid:
		return

	# Find random valid position
	var tiles = hex_grid.get_all_tiles()
	var valid_tiles: Array = []

	for tile in tiles:
		# Check if tile is still valid (not freed)
		if not is_instance_valid(tile):
			continue
		if not tile.is_playable() or tile.biome_type == HexTile.BiomeType.WATER:
			continue
		valid_tiles.append(tile)

	if valid_tiles.is_empty():
		return

	var tile = valid_tiles[rng.randi() % valid_tiles.size()]
	var world_pos = hex_grid.hex_to_world(tile.hex_coords)
	world_pos.y = CoverSpawner.tile_top(tile)  # top of the tile (the middle of a ramp)

	var container = spawn_supply_drop_at(world_pos, rng.randi())
	supply_drop_spawned.emit(container)

## Server: a supply drop at a chosen spot (the zone drop, MapEventDirector), announced like the
## periodic ones (ServerWorld broadcasts supply_drop_spawned)
func drop_supplies_at(ground_pos: Vector3, rich: bool = false) -> LootContainer:
	var container = spawn_supply_drop_at(ground_pos, rng.randi(), false, rich)
	supply_drop_spawned.emit(container)
	return container

## Spawn a supply drop landing at ground_pos (also used by clients to mirror the server).
## landed: it came down before we joined - place it on the ground right away.
## rich: the zone drop's better loot (LootContainer.rich)
func spawn_supply_drop_at(ground_pos: Vector3, loot_seed: int, landed: bool = false, rich: bool = false) -> LootContainer:
	var container = _create_container(LootContainer.ContainerType.SUPPLY_DROP)
	container.loot_seed = loot_seed
	if rich:
		container.rich = true
		container.loot_count = 5
	container.position = ground_pos if landed else ground_pos + Vector3(0, 20.0, 0)  # Start high
	add_child(container)
	spawned_containers.append(container)
	container.container_destroyed.connect(_on_container_destroyed)

	if not landed:
		_animate_supply_drop(container, ground_pos.y)

	print("[LootSpawner] Supply drop incoming at %s!" % ground_pos)
	return container

func _animate_supply_drop(container: LootContainer, target_y: float):
	# Floats down under its parachute, then lands with a thud (see LootContainer.land)
	container.start_falling()
	var tween = create_tween()
	tween.tween_property(container, "position:y", target_y, 4.0)  # steady descent
	tween.tween_callback(func():
		if is_instance_valid(container):
			container.land()
	)

func _on_container_destroyed(container: LootContainer):
	spawned_containers.erase(container)

func get_container_count() -> int:
	return spawned_containers.size()

## Fisher-Yates shuffle driven by our own RNG (Array.shuffle() uses the global one)
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
