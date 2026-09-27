## A bush players can hide in: whoever stands inside is invisible to others unless they come
## close or the hider shoots (see VisibilitySystem). It rustles when someone moves through it,
## which is the only hint an enemy gets.
extends Node3D
class_name Bush

const RADIUS: float = 0.85          # horizontal distance from the center that counts as inside

var _last_positions: Dictionary = {}  # player -> Vector3
var _rustle: float = 0.0
var _model: Node3D = null
var _falling: bool = false

func _ready():
	add_to_group("bushes")
	_model = CoverSpawner.load_prop("bush")
	if _model:
		add_child(_model)

## Is a world position inside this bush?
func contains(pos: Vector3) -> bool:
	return Vector2(pos.x - global_position.x, pos.z - global_position.z).length() < RADIUS

func _process(delta: float):
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not contains(p.global_position):
			_last_positions.erase(p)
			continue
		var last = _last_positions.get(p, p.global_position)
		if (p.global_position - last).length() > 0.02:
			_rustle = 1.0
		_last_positions[p] = p.global_position
	if _model and _rustle > 0.0:
		_rustle = max(_rustle - delta * 2.5, 0.0)
		var t = Time.get_ticks_msec() / 1000.0
		_model.rotation = Vector3(sin(t * 23.0) * 0.06, 0, cos(t * 19.0) * 0.06) * _rustle
		_model.scale = Vector3.ONE * (1.0 + sin(t * 17.0) * 0.03 * _rustle)

func attach_to(tile: HexTile):
	tile.tile_destroyed.connect(fall)
	tile.tree_exiting.connect(fall)

func fall():
	if _falling or not is_inside_tree() or is_queued_for_deletion():
		return
	_falling = true
	remove_from_group("bushes")
	var t = create_tween()
	t.tween_property(self, "position:y", position.y - 6.0, 0.9).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(queue_free)

## Is this position inside any bush?
static func any_contains(tree: SceneTree, pos: Vector3) -> bool:
	for bush in tree.get_nodes_in_group("bushes"):
		if bush.contains(pos):
			return true
	return false
