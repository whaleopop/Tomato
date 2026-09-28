## A wall segment on a hex edge: blocks movement, bullets (environment layer) and sight
## (CoverSpawner.COVER_LAYER, used by VisibilitySystem and line-of-fire checks).
## Falls into the void together with either tile it stands between.
extends StaticBody3D
class_name CoverWall

enum Kind { STONE, WOOD, SANDBAG }

const LENGTH: float = HexTile.HEX_RADIUS  # a whole hex edge (edge length = hex radius)
const PROP_LENGTH: float = 1.0           # the wall models are one unit long: repeated along the edge
const HEIGHT: float = 1.3
const THICKNESS: float = 0.3
const MODELS = {Kind.STONE: "wall_stone", Kind.WOOD: "wall_wood", Kind.SANDBAG: "wall_sandbag"}

var kind: int = Kind.STONE
var extra_height: float = 0.0  # on a step: taller by the step height
var _falling: bool = false

func _ready():
	add_to_group("cover")
	collision_layer = HitscanSystem.LAYER_ENVIRONMENT | CoverSpawner.COVER_LAYER
	collision_mask = 0

	var height = HEIGHT + extra_height
	var shape = BoxShape3D.new()
	shape.size = Vector3(LENGTH, height, THICKNESS)
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = height / 2.0
	add_child(collision)

	var pieces = max(1, int(round(LENGTH / PROP_LENGTH)))
	var model = CoverSpawner.load_prop(MODELS.get(kind, "wall_stone"))
	if model:
		for i in pieces:
			var piece = model if i == 0 else CoverSpawner.load_prop(MODELS.get(kind, "wall_stone"))
			piece.scale.y = height / HEIGHT
			piece.position.x = (i + 0.5) * PROP_LENGTH - LENGTH / 2.0
			add_child(piece)
	else:
		var mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = shape.size
		mesh.mesh = box
		mesh.position.y = height / 2.0
		add_child(mesh)

## Topple when a tile under the wall is destroyed (or removed without animation)
func attach_to(tiles: Array):
	for tile in tiles:
		tile.tile_destroyed.connect(fall)
		tile.tree_exiting.connect(fall)

func fall():
	if _falling or not is_inside_tree() or is_queued_for_deletion():
		return
	_falling = true
	collision_layer = 0
	var t = create_tween().set_parallel()
	t.tween_property(self, "rotation:x", rotation.x + randf_range(1.0, 1.6) * (1.0 if randf() > 0.5 else -1.0), 0.7).set_ease(Tween.EASE_IN)
	t.tween_property(self, "position:y", position.y - 6.0, 0.9).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.chain().tween_callback(queue_free)
