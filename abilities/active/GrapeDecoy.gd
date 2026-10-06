## Grape Decoy (Grape): a puff of smoke, and the grape slips out of sight for a few seconds while a
## decoy grape runs on the way you aimed. Nobody sees you unless right next to you
## (StatusComponent "stealth", ServerVisibility) - and a shot gives you away (ServerPlayer).
extends ActiveAbility
class_name GrapeDecoy

var stealth_time: float = 3.5
var decoy_time: float = 2.6
var decoy_speed: float = 6.0

func aim_preview() -> Dictionary:
	return {"shape": "line", "range": decoy_speed * decoy_time, "width": 0.8}

func _init():
	ability_name = "Grape Decoy"
	cast_pose = "cast_raise"
	icon = "swap"
	cooldown = 12.0
	duration = 0.2

func _on_activate(entity, target_position: Vector3) -> bool:
	var parent = AbilityFX._parent(entity)
	if not parent:
		return false
	var forward = SourSpray._aim(entity, target_position)
	_puff(parent, entity.global_position)
	_decoy(entity, parent, forward)
	if not replay:
		var status = entity.get_component("StatusComponent")
		if status:
			status.apply("stealth", stealth_time)
	return true

## A copy of the hero's model that runs straight on (stops before a wall), then goes up in smoke
func _decoy(entity: Node3D, parent: Node, forward: Vector3) -> void:
	var model = entity.get_node_or_null("Model")
	if not model:
		return
	var copy: Node3D = model.duplicate()
	var runner = Node3D.new()
	runner.name = "GrapeDecoy"
	runner.add_child(copy)
	parent.add_child(runner)
	runner.global_transform = entity.global_transform
	runner.look_at(runner.global_position + forward, Vector3.UP)
	runner.rotate_object_local(Vector3.UP, PI)  # heroes face +Z (Player.rotation.y = atan2(x, z))
	var distance = decoy_speed * decoy_time
	var space = entity.get_world_3d().direct_space_state
	var from = entity.global_position + Vector3(0, 0.6, 0)
	var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + forward * distance, CoverSpawner.COVER_LAYER | 1, [entity.get_rid()]))
	if hit:
		distance = max(from.distance_to(hit.position) - 0.6, 0.5)
	var start = runner.global_position
	var end = start + forward * distance
	var t = runner.create_tween()
	t.tween_method(_run.bind(runner, start, end), 0.0, 1.0, decoy_time)
	t.tween_callback(_vanish.bind(runner))

## The decoy at `k` of its run: straight on, bobbing like a walking hero
func _run(k: float, runner: Node3D, start: Vector3, end: Vector3) -> void:
	if is_instance_valid(runner):
		var p = start.lerp(end, k)
		p.y += abs(sin(k * decoy_time * 12.0)) * 0.08
		runner.global_position = p

func _vanish(runner: Node3D) -> void:
	if is_instance_valid(runner):
		_puff(runner.get_parent(), runner.global_position)
		runner.queue_free()

func _puff(parent: Node, pos: Vector3) -> void:
	if not parent:
		return
	var smoke = LootVisuals._instance("res://models/smoke.glb")
	if smoke:
		parent.add_child(smoke)
		smoke.global_position = pos + Vector3(0, 0.6, 0)
		smoke.scale = Vector3.ONE * 0.4
		var t = smoke.create_tween().set_parallel(true)
		t.tween_property(smoke, "scale", Vector3.ONE * 2.2, 0.6).set_ease(Tween.EASE_OUT)
		t.tween_property(smoke, "position:y", smoke.position.y + 0.8, 0.6)
		t.chain().tween_property(smoke, "scale", Vector3.ONE * 0.01, 0.35)
		t.chain().tween_callback(smoke.queue_free)
	LandingImpact.create_at(parent, pos, Color(0.7, 0.55, 0.95), 0.5)
