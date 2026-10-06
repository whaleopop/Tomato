## Full-screen touch control layer (mobile-port): a move stick (bottom-left), an aim/fire stick
## (bottom-right), ability/utility buttons around it, and a few top-area menu buttons. Only built
## when Platform.touch_mode() is true; a no-op (queue_free) otherwise. Added to group
## "touch_controls" so PlayerInputHandler / CameraController can find it without a hard reference
## (same pattern as the "player_hud" group lookup).
extends Control
class_name TouchControls

const FIRE_THRESHOLD: float = 0.6  # share of the aim stick's radius that starts auto-fire

var move_vector: Vector2 = Vector2.ZERO
var aim_vector: Vector2 = Vector2.ZERO
var aim_active: bool = false
## True while the aim stick's own push-past-threshold fire logic wants the gun firing. The only
## attack signal PlayerInputHandler trusts in touch mode (emulate_mouse_from_touch makes every
## touch - including the move stick - look like a left click otherwise; see bug 1).
var firing: bool = false

var _player: Node = null
var _ability_component: AbilityComponent = null
var _move_stick: VirtualStick = null
var _aim_stick: VirtualStick = null
var _ability_buttons: Array[TouchActionButton] = []
## Weapon slots are driven through action_press/release like any other button: only two slots
## exist (InventoryComponent.MAX_WEAPON_SLOTS), so each tap toggles to "the other one".
var _other_slot: int = 1

func _ready():
	if not Platform.touch_mode():
		queue_free()
		return
	add_to_group("touch_controls")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)
	_build()

func setup(player: Node) -> void:
	_player = player
	if player and player.has_method("get_component"):
		_ability_component = player.get_component("AbilityComponent")
	var ability_count = _ability_component.active_abilities.size() if _ability_component else 0
	for i in _ability_buttons.size():
		var btn = _ability_buttons[i]
		btn.ability_component = _ability_component
		# Only as many buttons are shown/active as the hero actually has abilities for (usually
		# 1, per CLAUDE.md): the rest would show empty and send dead "ability_N" input (bug 9).
		if i < ability_count:
			btn.ability = _ability_component.active_abilities[i]
			btn.visible = true
		else:
			btn.visible = false
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if _move_stick:
		move_vector = _move_stick.vector
	if _aim_stick:
		aim_vector = _aim_stick.vector
		aim_active = _aim_stick.active and _aim_stick.vector.length() > 0.0
		var should_fire = _aim_stick.vector.length() >= FIRE_THRESHOLD
		firing = should_fire and _aim_stick.active

## The swap button has no InputMap action of its own (it alternates between two), so it is wired
## through TouchActionButton's "tapped" signal instead of the usual press/release action.
func _on_weapon_swap_tapped() -> void:
	var action = "weapon_slot_%d" % (_other_slot + 1)
	_other_slot = 1 - _other_slot
	# PlayerInputHandler polls is_action_just_pressed on its own _process; releasing in the very
	## same call (before that poll ever runs) could lose the just-pressed edge, so the release
	## waits one process frame (see bug 4).
	Input.parse_input_event(_action_event(action, true))
	await get_tree().process_frame
	Input.parse_input_event(_action_event(action, false))

func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	return ev

func _build() -> void:
	_move_stick = VirtualStick.new()
	_move_stick.name = "MoveStick"
	_move_stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_move_stick.offset_left = 60
	_move_stick.offset_top = -340
	_move_stick.offset_right = 60 + 260
	_move_stick.offset_bottom = -60
	add_child(_move_stick)

	_aim_stick = VirtualStick.new()
	_aim_stick.name = "AimStick"
	_aim_stick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_aim_stick.offset_left = -60 - 280
	_aim_stick.offset_top = -360
	_aim_stick.offset_right = -60
	_aim_stick.offset_bottom = -60
	add_child(_aim_stick)

	for i in 4:
		var btn = TouchActionButton.new()
		btn.name = "Ability%d" % (i + 1)
		btn.action = "ability_%d" % (i + 1)
		btn.radius = 52.0
		btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		var angle = deg_to_rad(200.0 + i * 24.0)
		var cx = -60 - 140 + cos(angle) * 190.0
		var cy = -200 + sin(angle) * 190.0
		btn.offset_left = cx - 52
		btn.offset_top = cy - 52
		btn.offset_right = cx + 52
		btn.offset_bottom = cy + 52
		add_child(btn)
		_ability_buttons.append(btn)

	_add_button("Reload", "reload", Control.PRESET_BOTTOM_RIGHT, -360, -420, 42)
	_add_button("Heal", "use_heal", Control.PRESET_BOTTOM_RIGHT, -440, -360, 42)
	_add_button("Shield", "use_shield", Control.PRESET_BOTTOM_RIGHT, -440, -280, 42)
	_add_button("Interact", "interact", Control.PRESET_BOTTOM_LEFT, 360, -300, 42)

	var swap = TouchActionButton.new()
	swap.name = "WeaponSwap"
	swap.radius = 42.0
	swap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	swap.offset_left = 360 - 42
	swap.offset_top = -380 - 42
	swap.offset_right = 360 + 42
	swap.offset_bottom = -380 + 42
	add_child(swap)
	swap.tapped.connect(_on_weapon_swap_tapped)

	_add_button("Inventory", "inventory", Control.PRESET_TOP_RIGHT, -100, 40, 38)
	_add_button("Pause", "pause", Control.PRESET_TOP_RIGHT, -180, 40, 38)

func _add_button(node_name: String, action: StringName, preset: int, ox: float, oy: float, radius: float) -> void:
	var btn = TouchActionButton.new()
	btn.name = node_name
	btn.action = action
	btn.radius = radius
	btn.set_anchors_preset(preset)
	btn.offset_left = ox - radius
	btn.offset_top = oy - radius
	btn.offset_right = ox + radius
	btn.offset_bottom = oy + radius
	add_child(btn)
