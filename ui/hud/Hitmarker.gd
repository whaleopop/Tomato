extends Control
class_name Hitmarker
## Hitmarker at the crosshair: four diagonal ticks. Shown at once on the predicted hit
## (CombatComponent.hit_marker), a server confirm only refreshes it; a kill is bigger and red.

const GAP := 8.0
const HIT_LEN := 9.0
const KILL_LEN := 14.0
const HIT_TIME := 0.22
const KILL_TIME := 0.45
const PUNCH_TIME := 0.12
const CONFIRM_WINDOW := 0.3

var player: Node:
	set(value):
		_disconnect_player()
		player = value
		_connect_player()

var _age: float = 99.0
var _kill: bool = false
var _last_predicted: float = -99.0  # seconds (Time) of the last predicted marker

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and not nm.player_killed.is_connected(_on_killed):
		nm.player_killed.connect(_on_killed)
	_connect_player()

func _combat():
	if player and is_instance_valid(player) and player.has_method("get_component"):
		return player.get_component("CombatComponent")
	return null

func _connect_player() -> void:
	if not is_inside_tree():
		return
	var c = _combat()
	if c and not c.hit_marker.is_connected(_on_hit):
		c.hit_marker.connect(_on_hit)

func _disconnect_player() -> void:
	var c = _combat()
	if c and c.hit_marker.is_connected(_on_hit):
		c.hit_marker.disconnect(_on_hit)

func _on_hit(_amount: float, confirmed: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not confirmed:
		_last_predicted = now
	elif now - _last_predicted < CONFIRM_WINDOW:
		return  # already shown on the prediction
	if _kill and _age < KILL_TIME:
		return  # don't downgrade a running kill marker
	_kill = false
	_start()

func _on_killed(victim_id: int, killer_id: int, _info: Dictionary) -> void:
	if not player or not is_instance_valid(player):
		return
	if killer_id != int(player.entity_id) or victim_id == killer_id:
		return
	_kill = true
	_start()

func _start() -> void:
	_age = 0.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	if _age >= (KILL_TIME if _kill else HIT_TIME):
		set_process(false)
	queue_redraw()

func _draw() -> void:
	var life := KILL_TIME if _kill else HIT_TIME
	if _age >= life:
		return
	var center := CameraController.aim_screen_point(get_viewport()) - global_position
	var t := _age / life
	var punch := lerpf(1.3, 1.0, clampf(_age / PUNCH_TIME, 0.0, 1.0))
	var alpha := 1.0 - maxf(0.0, (t - 0.4) / 0.6)
	var len := (KILL_LEN if _kill else HIT_LEN) * punch
	var gap := GAP * punch
	var width := 3.5 if _kill else 2.5
	var col := UITheme.ACCENT_DANGER if _kill else Color.WHITE
	col.a = alpha
	var shadow := Color(0, 0, 0, 0.6 * alpha)
	for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var d: Vector2 = dir.normalized()
		var a := center + d * gap
		var b := center + d * (gap + len)
		draw_line(a, b, shadow, width + 2.0, true)
		draw_line(a, b, col, width, true)
