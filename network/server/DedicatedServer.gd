## Headless dedicated server: no host player, no menu. MainMenu hands over to it when the process
## runs with `--server` (or is exported with the "dedicated_server" feature). Two ways to run:
## - standalone (a VPS without the backend), one match after another in the same process:
##     godot --headless -- --server --port=7777 --mode=br --min-players=2
##   The lobby works as with a host: everyone picks a hero and a landing spot, all ready (and at
##   least min_players) -> the countdown. After a match (or when everyone left a running one) whoever
##   is still connected is told why and the server starts over with a fresh map.
## - matchmade (`--match=<id> --roster=<file> --backend=<url> --key=<secret>`, started by the
##   backend tools/server/backend for one match): only the players of the roster get in (tickets,
##   GameServer.claim_ticket), they come with their hero and pick a landing spot until
##   LANDING_TIME runs out (LobbyManager.force_start), every player's coins and mastery XP go to the
##   backend (/match/report, the same numbers the HUD shows: PlayerProfile.match_reward, Mastery),
##   and the process quits after the match.
extends Node
class_name DedicatedServer

const SCENE: String = "res://scenes/server/DedicatedServerScene.tscn"
const RESTART_AFTER_END: float = 45.0  # the result screen, then a new map
const RESTART_WHEN_EMPTY: float = 5.0  # everyone left a running match
const STATUS_EVERY: float = 60.0  # a status line in the log
# Matchmade games
const LANDING_TIME: float = 45.0  # from "ready": connecting, loading and picking the landing spot
const TICKET_TIME: float = 15.0   # a peer that shows no ticket by then is dropped
const NOBODY_CAME: float = 90.0   # nobody connected: the match is off

var port: int = GameServer.PORT
var mode: String = GameModes.BR
var min_players: int = -1  # -1: 1 for the co-op survivors, 2 for the rest
var match_id: int = 0
var roster_path: String = ""
var backend_url: String = ""
var server_key: String = ""

var _wait: float = 0.0
var _status_timer: float = 0.0
var _matches: int = 0
var _restarting: bool = false
var _ready_sent: bool = false
var _ready_time: float = 0.0
var _forced: bool = false
var _connected_at: Dictionary = {}  # peer -> seconds (ticket check)
var _reported: Dictionary = {}      # player_id -> true
var _pending_http: int = 0

static func requested() -> bool:
	return OS.has_feature("dedicated_server") or _args().has("--server")

static func _args() -> PackedStringArray:
	return OS.get_cmdline_user_args() + OS.get_cmdline_args()

func _ready():
	_read_args()
	# Headless runs flat out otherwise: a frame per physics tick is plenty
	Engine.max_fps = Engine.physics_ticks_per_second
	print("[DedicatedServer] ROYALTIM-3 %s: port %d, mode %s, %d+ players to start%s" % [
		ProjectSettings.get_setting("application/config/version", "?"), port, mode, min_players,
		", match %d" % match_id if match_id > 0 else ""])
	_start()

func _read_args():
	for arg in _args():
		var kv = arg.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"port":
				port = int(kv[1])
			"mode":
				mode = kv[1]
			"min-players":
				min_players = int(kv[1])
			"match":
				match_id = int(kv[1])
			"roster":
				roster_path = kv[1]
			"backend":
				backend_url = kv[1].trim_suffix("/")
			"key":
				server_key = kv[1]
	if not GameModes.INFO.has(mode):
		push_warning("[DedicatedServer] Unknown mode '%s', using %s" % [mode, GameModes.BR])
		mode = GameModes.BR
	if port <= 0 or port > 65535:
		port = GameServer.PORT
	if min_players < 1:
		min_players = 1 if mode == GameModes.SURVIVORS else 2

func _matchmade() -> bool:
	return match_id > 0

func _start():
	_restarting = false
	_wait = 0.0
	_status_timer = 0.0
	get_node("/root/GameManager").game_mode = mode
	var nm = get_node("/root/NetworkManager")
	if not nm.start_server(port, true):
		push_error("[DedicatedServer] Could not open port %d" % port)
		get_tree().quit(1)  # the service manager (systemd / the backend) deals with it
		return
	nm.game_server.lobby_manager.min_players_to_start = min_players
	_matches += 1
	if _matchmade():
		_setup_match(nm)
	print("[DedicatedServer] Lobby #%d open" % _matches)

func _setup_match(nm):
	var f = FileAccess.open(roster_path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	if not data is Dictionary or not data.get("players") is Dictionary or data.players.is_empty():
		push_error("[DedicatedServer] No roster at %s" % roster_path)
		get_tree().quit(1)
		return
	nm.game_server.roster = data.players
	nm.game_server.lobby_manager.min_players_to_start = data.players.size()  # all of them -> no waiting
	nm.game_server.player_connected.connect(func(id): _connected_at[id] = _now())
	nm.game_server.player_disconnected.connect(func(id):
		_connected_at.erase(id)
		if nm.game_server.game_started:
			_report(id, false))  # left: what they had so far
	nm.player_killed.connect(func(victim, _killer, _info):
		if not GameModes.respawns(mode):
			_report(victim, false))  # out: the HUD shows the death card with the coins now
	nm.match_ended.connect(_on_match_ended)

func _server() -> GameServer:
	var nm = get_node_or_null("/root/NetworkManager")
	return nm.game_server if nm and nm.game_server and nm.game_server.is_running else null

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _process(delta: float):
	var server = _server()
	if server == null or _restarting:
		return
	var peers = server.multiplayer.get_peers().size()

	_status_timer += delta
	if _status_timer >= STATUS_EVERY:
		_status_timer = 0.0
		var phase = "match over" if server.match_over else ("match %ds" % int(server.match_time()) if server.game_started else "lobby")
		print("[DedicatedServer] %s, %d connected" % [phase, peers])

	if _matchmade():
		_process_match(server, peers, delta)
		return

	if server.match_over:
		_wait += delta
		if _wait >= RESTART_AFTER_END or peers == 0:
			_restart("The match is over - the server is starting a new one")
	elif server.game_started and peers == 0:
		_wait += delta
		if _wait >= RESTART_WHEN_EMPTY:
			_restart("")
	else:
		_wait = 0.0

func _process_match(server: GameServer, peers: int, delta: float):
	var lobby = server.lobby_manager
	if not _ready_sent:
		if server.server_world.is_map_ready:
			_ready_sent = true
			_ready_time = _now()
			lobby.landing_deadline = Time.get_ticks_msec() + int(LANDING_TIME * 1000.0)
			_post("/match/ready", {"match": match_id})  # now the players get "found"
		return
	# Strangers (no ticket) are shown the door
	for id in _connected_at.keys():
		if not server.accounts.has(id) and _now() - _connected_at[id] > TICKET_TIME:
			_connected_at.erase(id)
			server._refuse_join(id, "This match is not yours - find a match from the menu")

	if server.match_over:
		_wait += delta
		if _wait >= RESTART_AFTER_END or peers == 0:
			_finish("The match is over")
	elif server.game_started:
		_wait = _wait + delta if peers == 0 else 0.0
		if _wait >= RESTART_WHEN_EMPTY:
			_finish("")
	elif not _forced and Time.get_ticks_msec() >= lobby.landing_deadline:
		_forced = true
		var with_hero = 0
		for id in server.accounts:
			if lobby.get_player_character(id) != "":
				with_hero += 1
		for id in server.players.keys():
			if lobby.get_player_character(id) == "":
				server._refuse_join(id, "You took too long - find a new match")
		if with_hero == 0:
			_finish("")
			return
		lobby.min_players_to_start = 1  # whoever made it
		lobby.force_start()
	elif peers == 0 and _now() - _ready_time > NOBODY_CAME:
		_finish("")

func _on_match_ended(winner_id: int, _winner_name: String):
	var server = _server()
	if server == null:
		return
	for id in server.accounts.keys():
		var won = id == winner_id
		var entity = server.server_world.get_player(id)
		if winner_id < 0 and entity and entity.has_meta("team"):
			won = int(entity.get_meta("team")) == -1 - winner_id  # team modes
		_report(id, won)

## Coins and XP of one player to the backend, once (PlayerHUD._reward_row shows the same numbers)
func _report(player_id: int, won: bool):
	var server = _server()
	if server == null or _reported.has(player_id) or not server.accounts.has(player_id) or not server.players.has(player_id):
		return
	_reported[player_id] = true
	var sp: ServerPlayer = server.players[player_id]
	var stats = sp.stats()
	if sp.place == 0:
		stats["time"] = int(server.match_time())
	if won:
		stats["place"] = 1
	var coins = 0
	for line in PlayerProfile.match_reward(stats):
		coins += int(line[2])
	var body = {
		"match": match_id, "account": int(server.accounts[player_id].account), "coins": coins,
		"hero": sp.character_name, "hero_xp": Mastery.hero_xp(stats), "weapon_xp": Mastery.weapon_xp(stats),
	}
	print("[DedicatedServer] Report %s: %s" % [server.accounts[player_id].nickname, body])
	_post("/match/report", body)

func _post(path: String, body: Dictionary):
	if backend_url == "":
		return
	var http = HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	_pending_http += 1
	http.request_completed.connect(func(result, code, _headers, _data):
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			push_warning("[DedicatedServer] %s failed (%d / %d)" % [path, result, code])
		_pending_http -= 1
		http.queue_free())
	var headers = PackedStringArray(["Content-Type: application/json", "X-Server-Key: " + server_key])
	if http.request(backend_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		_pending_http -= 1
		http.queue_free()

## Matchmade: the match is done - tell whoever is left, let the reports out, quit
func _finish(reason: String):
	_restarting = true
	var server = _server()
	if server and server.game_started:
		for id in server.accounts.keys():
			_report(id, false)  # anyone not reported yet (should not happen)
	var nm = get_node("/root/NetworkManager")
	if reason != "" and nm.network_lobby and not multiplayer.get_peers().is_empty():
		nm.network_lobby._receive_join_refused.rpc(reason)
	print("[DedicatedServer] Match %d done" % match_id)
	var waited = 0.0
	while (_pending_http > 0 and waited < 10.0) or waited < 1.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	nm.stop_all()
	get_tree().quit(0)

func _restart(reason: String):
	_restarting = true
	print("[DedicatedServer] Starting over")
	var nm = get_node("/root/NetworkManager")
	# Shown on their main menu instead of "connection lost" (see NetworkManager.refusal_reason)
	if reason != "" and nm.network_lobby and not multiplayer.get_peers().is_empty():
		nm.network_lobby._receive_join_refused.rpc(reason)
	await get_tree().create_timer(1.0).timeout
	_start()  # start_server tears the old one down first
