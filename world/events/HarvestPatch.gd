## Harvest event (MapEvents): a patch of dug-up earth where a rare bonus grows. A light pillar in
## the bonus color marks it from afar (and on the minimap); after `grow_time` the sprout is ripe
## and can be picked up like any loot item - through NetworkLootManager with the id the server
## chose, so exactly one player gets it. Then the patch withers.
extends Node3D
class_name HarvestPatch

var bonus: int = MapEvents.Harvest.SPEED
var item_id: int = 0
var grow_time: float = 10.0
var item: LootItem = null
var _beam: MeshInstance3D = null
var _leaves: Node3D = null
var _withering: bool = false

func _ready():
	var color = MapEvents.harvest_color(bonus)
	add_to_group("map_markers")
	set_meta("marker_color", color)

	var mound = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.75
	sphere.height = 0.5
	sphere.radial_segments = 10
	sphere.rings = 4
	mound.mesh = sphere
	mound.material_override = AbilityFX._flat(Color(0.36, 0.24, 0.15))
	mound.scale = Vector3(1.0, 0.45, 1.0)
	mound.position.y = 0.02
	add_child(mound)

	# A ring of leaves that opens up while the bonus grows
	_leaves = Node3D.new()
	add_child(_leaves)
	for i in 5:
		var leaf = MeshInstance3D.new()
		var box = PrismMesh.new()
		box.size = Vector3(0.22, 0.5, 0.05)
		leaf.mesh = box
		leaf.material_override = AbilityFX._flat(Color(0.3, 0.7, 0.25))
		var a = TAU * i / 5.0
		leaf.position = Vector3(cos(a), 0.0, sin(a)) * 0.32 + Vector3(0, 0.2, 0)
		leaf.rotation = Vector3(0.0, -a + PI / 2.0, 0.55)
		_leaves.add_child(leaf)
	_leaves.scale = Vector3.ONE * 0.2
	create_tween().tween_property(_leaves, "scale", Vector3.ONE, max(grow_time, 0.2)).set_trans(Tween.TRANS_SINE)

	_beam = LootVisuals.beam(color, 7.0, 0.35)
	(_beam.material_override as StandardMaterial3D).albedo_color.a = 0.45
	add_child(_beam)

	item = LootItem.new()
	item.item_type = LootItem.ItemType.HARVEST
	item.item_value = float(bonus)
	item.item_name = MapEvents.harvest_name(bonus)
	item.respawn_time = 0.0
	add_child(item)
	item.position = Vector3(0, LootItem.HOVER_HEIGHT + 0.1, 0)
	item.original_position = item.position
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.loot_manager:
		network_manager.loot_manager.register_item(item, item_id)  # already picked: freed right away
	if is_instance_valid(item) and not item.is_queued_for_deletion():
		item.grow_in(grow_time)

func _process(_delta: float):
	if _withering:
		return
	if not is_instance_valid(item) or item.is_queued_for_deletion() or not item.is_active:
		_wither()
		return
	if _beam:
		_beam.scale.x = 1.0 + 0.12 * sin(Time.get_ticks_msec() / 180.0)
		_beam.scale.z = _beam.scale.x

func _wither() -> void:
	_withering = true
	remove_from_group("map_markers")
	var t = create_tween().set_parallel(true)
	t.tween_property(self, "scale", Vector3(1.2, 0.05, 1.2), 0.8).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(queue_free)
