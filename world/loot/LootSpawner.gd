## Spawns loot containers across the map
extends Node3D
class_name LootSpawner

signal containers_spawned(count: int)

@export var container_density: float = 0.15  # Chance per tile to spawn container
@export var min_containers: int = 10
@export var max_containers: int = 50
@export var supply_drop_interval: float = 60.0  # Seconds between supply drops
@export var enable_supply_drops: bool = true

var spawned_containers: Array[LootContainer] = []
var hex_grid: HexGrid = null
var supply_drop_timer: float = 0.0

# Container type weights
var container_weights: Dictionary = {
	LootContainer.ContainerType.CRATE: 50,
	LootContainer.ContainerType.CHEST: 25,
	LootContainer.ContainerType.BARREL: 20,
	LootContainer.ContainerType.SUPPLY_DROP: 5
}

func _ready():
	pass

func _process(delta: float):
	if enable_supply_drops:
		supply_drop_timer += delta
		if supply_drop_timer >= supply_drop_interval:
			supply_drop_timer = 0.0
			_spawn_supply_drop()

func setup(grid: HexGrid):
	hex_grid = grid
	spawn_initial_containers()

func spawn_initial_containers():
	if not hex_grid:
		print("[LootSpawner] ERROR: No hex grid set")
		return

	var spawn_positions: Array[Vector3] = []
	var tiles = hex_grid.get_all_tiles()

	# Collect valid spawn positions
	for tile in tiles:
		if tile.is_destroyed:
			continue
		if tile.biome_type == HexTile.BiomeType.WATER:
			continue

		# Random chance to spawn
		if randf() < container_density:
			var world_pos = hex_grid.hex_to_world(tile.hex_coords)
			world_pos.y = tile.height * HexTile.HEX_HEIGHT + HexTile.HEX_HEIGHT
			spawn_positions.append(world_pos)

	# Clamp to min/max
	spawn_positions.shuffle()
	var count = clampi(spawn_positions.size(), min_containers, max_containers)
	spawn_positions.resize(count)

	# Spawn containers
	for pos in spawn_positions:
		var container = _create_container(_roll_container_type())
		container.position = pos
		add_child(container)
		spawned_containers.append(container)

		# Connect signals
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

	var roll = randi() % total_weight
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
		if tile.is_destroyed or tile.biome_type == HexTile.BiomeType.WATER:
			continue
		valid_tiles.append(tile)

	if valid_tiles.is_empty():
		return

	var tile = valid_tiles[randi() % valid_tiles.size()]
	var world_pos = hex_grid.hex_to_world(tile.hex_coords)
	world_pos.y = tile.height * HexTile.HEX_HEIGHT + HexTile.HEX_HEIGHT + 20.0  # Start high

	# Create supply drop
	var container = _create_container(LootContainer.ContainerType.SUPPLY_DROP)
	container.position = world_pos
	add_child(container)
	spawned_containers.append(container)
	container.container_destroyed.connect(_on_container_destroyed)

	# Animate drop
	_animate_supply_drop(container, world_pos.y - 20.0)

	print("[LootSpawner] Supply drop incoming at %s!" % world_pos)

func _animate_supply_drop(container: LootContainer, target_y: float):
	# Create parachute effect (particles)
	var particles = GPUParticles3D.new()
	particles.name = "ParachuteEffect"
	particles.amount = 30
	particles.lifetime = 2.0
	particles.explosiveness = 0.0

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.5
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, 1, 0)  # Float up relative to container
	mat.scale_min = 0.1
	mat.scale_max = 0.2
	mat.color = Color(1.0, 1.0, 1.0, 0.5)

	particles.process_material = mat

	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.2, 0.2)
	particles.draw_pass_1 = mesh

	particles.position = Vector3(0, 1, 0)
	container.add_child(particles)

	# Animate fall
	var tween = create_tween()
	tween.tween_property(container, "position:y", target_y, 3.0).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)

func _on_container_destroyed(container: LootContainer):
	spawned_containers.erase(container)

func get_container_count() -> int:
	return spawned_containers.size()
