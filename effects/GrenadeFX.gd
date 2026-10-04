## Grenade launcher shots: a grenade (Blaster Kit grenade-a) on an arc and the blast where it lands.
## Visual only - CombatComponent deals the blast damage on the server; other clients replay remote
## shots with the same look (NetworkManager._create_remote_shot_effects).
extends RefCounted
class_name GrenadeFX

const ARC_HEIGHT: float = 1.8

static func flight_time(from: Vector3, to: Vector3) -> float:
	return 0.35 + from.distance_to(to) * 0.03

static func lob(parent: Node3D, from: Vector3, to: Vector3, radius: float) -> void:
	if not parent or not parent.is_inside_tree():
		return
	var holder = Node3D.new()
	holder.name = "Grenade"
	var grenade = LootVisuals._instance("res://models/grenade-a.glb")
	if grenade:
		LootVisuals.fit(grenade, 0.3)
		holder.add_child(grenade)
	else:
		var ball = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		ball.mesh = sphere
		holder.add_child(ball)
	parent.add_child(holder)
	holder.global_position = from
	var time = flight_time(from, to)
	var peak = ARC_HEIGHT + from.distance_to(to) * 0.08
	var t = holder.create_tween()
	t.tween_method(func(k: float):
		if is_instance_valid(holder):
			var p = from.lerp(to, k)
			p.y += sin(k * PI) * peak
			holder.global_position = p
			holder.rotation = Vector3(k * 9.0, k * 4.0, 0.0), 0.0, 1.0, time)
	t.tween_callback(func():
		if is_instance_valid(holder):
			explode(holder.get_parent(), to, radius)
			holder.queue_free())

static func explode(parent: Node, pos: Vector3, radius: float) -> void:
	if not parent or not parent.is_inside_tree():
		return
	LandingImpact.create_at(parent, pos, Color(1.0, 0.6, 0.25), 1.3)
	Sfx.at("explosion", pos)
	var sparks = LootVisuals.sparkles(Color(1.0, 0.55, 0.15), 40, 8.0, 0.7)
	parent.add_child(sparks)
	sparks.global_position = pos + Vector3(0, 0.3, 0)
	sparks.emitting = true
	sparks.get_tree().create_timer(1.2).timeout.connect(sparks.queue_free)
	var fire = FireTrail.new()  # the look of it: the blast itself is instant
	fire.tick_damage = 0.0
	fire.lifetime = 0.9
	fire.with_light = true
	fire.flame_scale = 1.6
	parent.add_child(fire)
	fire.global_position = pos
	var points: Array = [pos]
	for i in 6:
		var a = TAU * i / 6.0
		points.append(pos + Vector3(cos(a), 0.0, sin(a)) * radius * 0.45)
	fire.lay_points(points, 0.1)
	if parent is Node3D:
		HexTile.shake_around(parent, pos, 0.8, 1.5)
	ScreenEffects.shake(0.25, 6.0)
