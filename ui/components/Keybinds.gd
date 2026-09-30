## Rebindable controls (Settings -> Controls). The defaults are project.godot's input map, captured
## once at startup; the player's choices live in user://settings.cfg (section "keys", saved by
## GameSettings) as "k<physical keycode>" or "m<mouse button>". One key per action: taking a key
## that another action has gives that action your old one (nothing is left without a key).
## Everything that shows a key reads label(action), so prompts follow the rebinding.
extends RefCounted
class_name Keybinds

## [action, what it does] in the order the settings list shows them. Esc (pause) stays fixed.
const ACTIONS = [
	["move_up", "Move forward"],
	["move_down", "Move back"],
	["move_left", "Move left"],
	["move_right", "Move right"],
	["sprint", "Sprint"],
	["jump", "Jump"],
	["attack", "Shoot"],
	["reload", "Reload"],
	["interact", "Open containers, pick up loot"],
	["inventory", "Inventory"],
	["ability_1", "Ability"],
	["use_heal", "Use a health pack"],
	["use_shield", "Drink a shield"],
	["weapon_slot_1", "Weapon 1"],
	["weapon_slot_2", "Weapon 2"],
	["weapon_slot_3", "Weapon 3"],
	["weapon_slot_4", "Weapon 4"],
	["weapon_slot_5", "Weapon 5"],
	["camera_mode", "Third-person camera on / off"],
	["camera_reset", "Reset the camera"],
]

static var _defaults: Dictionary = {}   # action -> Array[InputEvent] from project.godot

static func capture_defaults() -> void:
	if not _defaults.is_empty():
		return
	for entry in ACTIONS:
		if InputMap.has_action(entry[0]):
			_defaults[entry[0]] = InputMap.action_get_events(entry[0]).duplicate()

## Apply what the player chose (settings.cfg); unknown / broken entries are skipped
static func load_from(cfg: ConfigFile) -> void:
	capture_defaults()
	if not cfg.has_section("keys"):
		return
	for action in cfg.get_section_keys("keys"):
		var ev = _decode(String(cfg.get_value("keys", action, "")))
		if ev and InputMap.has_action(action):
			_set_event(action, ev)

static func save_to(cfg: ConfigFile) -> void:
	for entry in ACTIONS:
		var action: String = entry[0]
		if not InputMap.has_action(action) or _is_default(action):
			continue
		var events = InputMap.action_get_events(action)
		if not events.is_empty():
			cfg.set_value("keys", action, _encode(events[0]))

## Give `action` this key / mouse button; whoever had it gets `action`'s old one
static func bind(action: String, ev: InputEvent) -> void:
	var old = InputMap.action_get_events(action)
	var previous: InputEvent = old[0] if not old.is_empty() else null
	for entry in ACTIONS:
		var other: String = entry[0]
		if other == action or not InputMap.has_action(other):
			continue
		for e in InputMap.action_get_events(other):
			if _same(e, ev):
				InputMap.action_erase_event(other, e)
				if previous:
					InputMap.action_add_event(other, previous)
	_set_event(action, ev)

static func reset_all() -> void:
	capture_defaults()
	for action in _defaults:
		InputMap.action_erase_events(action)
		for e in _defaults[action]:
			InputMap.action_add_event(action, e)

## "W", "Shift", "LMB"... for prompts, chips and the guide
static func label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var events = InputMap.action_get_events(action)
	return event_label(events[0]) if not events.is_empty() else "—"

static func event_label(ev: InputEvent) -> String:
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT:
				return Locale.t("LMB")
			MOUSE_BUTTON_RIGHT:
				return Locale.t("RMB")
			MOUSE_BUTTON_MIDDLE:
				return Locale.t("MMB")
			_:
				return Locale.t("Mouse %d") % ev.button_index
	if ev is InputEventKey:
		var code = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		# The key as printed on this keyboard's layout
		var shown = code
		if ev.physical_keycode != 0 and DisplayServer.get_name() != "headless":
			shown = DisplayServer.keyboard_get_keycode_from_physical(code)
		var text = OS.get_keycode_string(shown)
		return text if text != "" else OS.get_keycode_string(code)
	return "?"

## Only real keys and mouse buttons (not the wheel, not modifier-only presses of Esc)
static func accepts(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		return ev.pressed and not ev.echo and ev.physical_keycode != KEY_ESCAPE
	if ev is InputEventMouseButton:
		return ev.pressed and ev.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	return false

## A clean copy of a pressed key / button to store in the input map
static func clean(ev: InputEvent) -> InputEvent:
	if ev is InputEventKey:
		var k = InputEventKey.new()
		k.physical_keycode = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return k
	if ev is InputEventMouseButton:
		var m = InputEventMouseButton.new()
		m.button_index = ev.button_index
		return m
	return null

## Replace the main key; the extra ones (the arrows next to WASD) stay behind it
static func _set_event(action: String, ev: InputEvent) -> void:
	var extras = InputMap.action_get_events(action).slice(1).filter(func(e): return not _same(e, ev))
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev)
	for e in extras:
		InputMap.action_add_event(action, e)

static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka = a.physical_keycode if a.physical_keycode != 0 else a.keycode
		var kb = b.physical_keycode if b.physical_keycode != 0 else b.keycode
		return ka == kb
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false

static func _is_default(action: String) -> bool:
	var now = InputMap.action_get_events(action)
	var was: Array = _defaults.get(action, [])
	if now.is_empty() or was.is_empty():
		return now.is_empty() == was.is_empty()
	return _same(now[0], was[0])  # only the main key is the player's

static func _encode(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return "k%d" % (ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode)
	if ev is InputEventMouseButton:
		return "m%d" % ev.button_index
	return ""

static func _decode(text: String) -> InputEvent:
	if text.length() < 2 or not text.substr(1).is_valid_int():
		return null
	var n = int(text.substr(1))
	if text[0] == "k":
		var k = InputEventKey.new()
		k.physical_keycode = n
		return k
	if text[0] == "m":
		var m = InputEventMouseButton.new()
		m.button_index = n
		return m
	return null
