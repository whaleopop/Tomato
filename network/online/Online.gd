## The online backend (tools/server/backend): the account, the profile kept on the server and the
## matchmaking queue. The account is this device's random key (user://account.cfg); the server
## creates the account on the first login. While logged in PlayerProfile mirrors the server's
## profile (PlayerProfile.online: no local saves, purchases / equipment / names go to the server,
## coins and mastery XP of matches are credited by the game server's report).
## Command line (after --): --backend=http://host:port, --account=<name> (another key file, to
## run two clients on one computer).
extends Node

signal login_finished(ok: bool)
signal profile_changed
## The party and the invitations to us changed (poll_party: the main menu asks every few seconds)
signal party_changed(data: Dictionary)

const DEFAULT_URL = "http://159.194.255.184:8080"
const TIMEOUT: float = 8.0

var base_url: String = DEFAULT_URL
var device: String = ""
var account_id: int = 0
var logged_in: bool = false
var login_done: bool = false  # tried (logged in or not)
var last_error: String = ""
var _key_path: String = "user://account.cfg"
## The last /party answer: {"party": {id, leader, members: [{id, nickname, hero, skin, hat, level,
## state}]} or null, "invites": [{from, nickname}], "queue": our queue state, "mode"}
var party_data: Dictionary = {}

func _ready():
	if DedicatedServer.requested():
		return  # a game server has no account
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--backend="):
			base_url = arg.substr(10).trim_suffix("/")
		elif arg.begins_with("--account="):
			_key_path = "user://account_%s.cfg" % arg.substr(10).validate_filename()
	_load_device()
	login()

## The backend's host: the game servers it starts run there too
func host() -> String:
	var h = base_url.trim_prefix("http://").trim_prefix("https://")
	return h.split("/")[0].split(":")[0]

func _load_device():
	var cfg = ConfigFile.new()
	if cfg.load(_key_path) == OK:
		device = String(cfg.get_value("account", "device", ""))
	if device.length() < 32:
		device = Crypto.new().generate_random_bytes(24).hex_encode()
		cfg.set_value("account", "device", device)
		cfg.save(_key_path)

func login() -> bool:
	login_done = false
	var res = await request(HTTPClient.METHOD_POST, "/login", {"device": device, "version": String(ProjectSettings.get_setting("application/config/version", ""))})
	logged_in = bool(res.get("ok", false))
	account_id = int(res.get("account", 0))
	last_error = "" if logged_in else String(res.get("error", "No connection to the game server"))
	if res.has("server_version"):  # the server is fine, this game is too old (UpdateDialog fetches the new one)
		last_error = tr("Update the game: the server runs v%s") % String(res.server_version)
	login_done = true
	print("[Online] %s" % ("logged in as account %d" % account_id if logged_in else "offline: " + last_error))
	login_finished.emit(logged_in)
	return logged_in

## Await this before reading the profile at start (the menu decides on onboarding from it)
func wait_login() -> bool:
	if not login_done:
		await login_finished
	return logged_in

## Fresh numbers from the server (back in the menu after a match)
func refresh() -> void:
	if logged_in:
		await request(HTTPClient.METHOD_GET, "/profile")

# ---------------------------------------------------------------- friends and the party

func poll_party() -> Dictionary:
	if not logged_in:
		return {}
	var res = await request(HTTPClient.METHOD_GET, "/party")
	if res.get("ok", false):
		party_data = res
		party_changed.emit(res)
	return res

func party() -> Dictionary:
	return party_data.get("party") if party_data.get("party") is Dictionary else {}

func in_party() -> bool:
	return not party().is_empty()

func is_party_leader() -> bool:
	return in_party() and int(party().get("leader", 0)) == account_id

## Our own entry in the party (its hero is the one we queue with when the leader starts)
func my_party_member() -> Dictionary:
	for m in party().get("members", []):
		if int(m.id) == account_id:
			return m
	return {}

## Whatever we answer comes back as the new party state
func party_action(path: String, body: Dictionary = {}) -> Dictionary:
	var res = await request(HTTPClient.METHOD_POST, path, body)
	if res.has("invites"):
		party_data = res
		party_changed.emit(res)
	return res

## One JSON request; always returns a Dictionary with "ok" (and "error" when not ok).
## A "profile" in the answer replaces the mirrored one.
func request(method: int, path: String, body: Dictionary = {}) -> Dictionary:
	var http = HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var headers = PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + device])
	var payload = "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	if http.request(base_url + path, headers, method, payload) != OK:
		http.queue_free()
		return {"ok": false, "error": "No connection to the game server"}
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "No connection to the game server"}
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not data is Dictionary:
		return {"ok": false, "error": "The game server answered nonsense"}
	if data.get("profile") is Dictionary:
		PlayerProfile.apply_remote(data.profile)
		profile_changed.emit()
	return data
