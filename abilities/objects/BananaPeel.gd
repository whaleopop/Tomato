## A banana peel on the ground (PeelTrap). On the server (`authority`) the first enemy of its
## owner to step on it slips: stunned, slides on and takes DAMAGE; then the peel is gone everywhere
## (NetworkManager.broadcast_map_event "peel_gone" -> MapEvents removes the copies near that spot).
extends Node3D
class_name BananaPeel

const LIFETIME: float = 25.0
const TRIGGER_RADIUS: float = 0.8
const DAMAGE: float = 10.0
const STUN_TIME: float = 1.1
const SLIDE_SPEED: float = 8.5
const SLIDE_TIME: float = 0.5
const ARM_TIME: float = 0.4          # can't catch anybody while still settling

var owner_entity: Node3D = null
var authority: bool = false
var _age: float = 0.0
var _gone: bool = false

func _ready():
	add_to_group("banana_peels")
	var yellow = AbilityFX._flat(Color(1.0, 0.86, 0.25))
	var brown = AbilityFX._flat(Color(0.45, 0.32, 0.12))
	var center = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.14
	center.mesh = sphere
	center.material_override = yellow
	center.position.y = 0.05
	add_child(center)
	for i in 4:  # four flaps of peel lying open
		var flap = MeshInstance3D.new()
		var box = PrismMesh.new()
		box.size = Vector3(0.18, 0.42, 0.04)
		flap.mesh = box
		flap.material_override = yellow
		var a = TAU * i / 4.0 + 0.4
		flap.position = Vector3(cos(a), 0.0, sin(a)) * 0.2 + Vector3(0, 0.04, 0)
		flap.rotation = Vector3(-PI / 2.0 + 0.25, -a + PI / 2.0, 0.0)
		add_child(flap)
	var tip = MeshInstance3D.new()
	var stem = CylinderMesh.new()
	stem.top_radius = 0.03
	stem.bottom_radius = 0.04
	stem.height = 0.12
	tip.mesh = stem
	tip.material_override = brown
	tip.position = Vector3(0, 0.12, 0)
	add_child(tip)
	scale = Vector3.ONE * 0.3
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float):
	if _gone:
		return
	_age += delta
	if _age >= LIFETIME:
		rot()
		return
	if not authority or _age < ARM_TIME:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p == owner_entity or not is_instance_valid(p) or not p is Node3D or not p.has_method("get_component"):
			continue
		var off: Vector3 = p.global_position - global_position
		if abs(off.y) > 1.0 or Vector2(off.x, off.z).length() > TRIGGER_RADIUS:
			continue
		var health = p.get_component("HealthComponent")
		if not health or health.is_dead:
			continue
		_slip(p)
		return

## Server: `victim` slips on it
func _slip(victim: Node3D) -> void:
	var health = victim.get_component("HealthComponent")
	health.take_damage(DAMAGE, owner_entity if is_instance_valid(owner_entity) else null)
	var status = victim.get_component("StatusComponent")
	if status:
		var movement = victim.get_component("MovementComponent")
		var dir = Vector3.ZERO
		if movement:
			dir = Vector3(movement.velocity.x, 0.0, movement.velocity.z)
		if dir.length() < 0.3:
			dir = victim.global_position - global_position
			dir.y = 0.0
		if dir.length() < 0.05:
			dir = Vector3.FORWARD
		status.apply("stun", STUN_TIME)
		status.push(dir.normalized() * SLIDE_SPEED, SLIDE_TIME)
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_method("broadcast_map_event"):
		network_manager.broadcast_map_event("peel_gone", {"pos": global_position, "owner": owner_entity.get("entity_id") if is_instance_valid(owner_entity) else 0})
	squash()

## Stepped on: flattens and flies off
func squash() -> void:
	if _gone:
		return
	_gone = true
	remove_from_group("banana_peels")
	var t = create_tween().set_parallel(true)
	t.tween_property(self, "scale", Vector3(1.6, 0.1, 1.6), 0.25)
	t.tween_property(self, "position:y", position.y + 0.3, 0.25)
	t.chain().tween_callback(queue_free)

## Too old, or the banana dropped a newer one
func rot() -> void:
	if _gone:
		return
	_gone = true
	remove_from_group("banana_peels")
	var t = create_tween()
	t.tween_property(self, "scale", Vector3(0.9, 0.05, 0.9), 0.6)
	t.tween_callback(queue_free)

## Remove this client's copy of the peel the server says is gone (MapEvents "peel_gone")
static func remove_near(tree: SceneTree, pos: Vector3, owner_id: int) -> void:
	var best: BananaPeel = null
	var best_d = 1.6
	for peel in tree.get_nodes_in_group("banana_peels"):
		if not peel is BananaPeel or peel.authority:
			continue
		if owner_id != 0 and is_instance_valid(peel.owner_entity) and peel.owner_entity.get("entity_id") != owner_id:
			continue
		var d = Vector2(peel.global_position.x - pos.x, peel.global_position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = peel
	if best:
		best.squash()
