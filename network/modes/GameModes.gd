## The match modes and what each one switches on. The host picks one in the main menu
## (ModeSelect -> GameManager.game_mode); it reaches clients in the lobby state ("mode") and
## decides the server's rules (network/server/modes/*Rules.gd), the island (zone, events, weeds)
## and the HUD (ui/hud/ModeView.gd). Ids go over the network: keep them.
extends RefCounted
class_name GameModes

const BR := "br"
const SURVIVORS := "survivors"
const CTF := "ctf"
const KOTH := "koth"
const ORDER = [BR, SURVIVORS, CTF, KOTH]

const INFO = {
	BR: {"name": "Battle Royale", "short": "Last one standing on a shrinking island",
		"lines": ["The island closes in ring by ring", "Map events, loot, supply drops", "One life: the last veggie wins"],
		"color": Color(0.52, 0.91, 0.42), "zone": true, "events": true, "weeds": false, "teams": false, "respawn": -1.0},
	SURVIVORS: {"name": "Weed Swarm", "short": "Hold out against endless waves of weeds together",
		"lines": ["Your gun aims and fires on its own", "After every wave: a card with a buff and a debuff", "Everyone down: the weeds win"],
		"color": Color(1.0, 0.75, 0.25), "zone": false, "events": false, "weeds": false, "teams": false, "respawn": -1.0},
	CTF: {"name": "Capture the Flag", "short": "Two teams, two flags: bring theirs home",
		"lines": ["Red against blue, no friendly fire", "Grab their flag, carry it to your base", "First to 3 captures; respawn after 5 s"],
		"color": Color(0.45, 0.65, 1.0), "zone": false, "events": false, "weeds": false, "teams": true, "respawn": 5.0},
	KOTH: {"name": "King of the Hill", "short": "Hold the platform alone to score",
		"lines": ["Stand on the platform in the middle", "Alone on it: a point a second; shared: nobody scores", "First to 100 points; respawn after 5 s"],
		"color": Color(0.85, 0.5, 1.0), "zone": false, "events": false, "weeds": false, "teams": false, "respawn": 5.0},
}

const TEAM_NAMES = ["Red team", "Blue team"]
const TEAM_COLORS = [Color(1.0, 0.36, 0.33), Color(0.36, 0.6, 1.0)]

static func info(mode: String) -> Dictionary:
	return INFO.get(mode, INFO[BR])

static func current() -> String:
	var gm = Engine.get_main_loop().root.get_node_or_null("/root/GameManager") if Engine.get_main_loop() else null
	return String(gm.game_mode) if gm and "game_mode" in gm else BR

static func respawns(mode: String) -> bool:
	return float(info(mode).respawn) >= 0.0
