## The server's record of hit registration, to see where shots get lost (GameServer.hit_log).
## Every client-reported hit gets a verdict (`claim`: ok / early / cooldown / reloading / no_ammo /
## range / wall / ...), every server-resolved shot its hit or miss (`shot`), every hit its damage
## (`damage`, also from abilities, weeds, the zone), and each player's connection is sampled
## (`sample`: ENet round trip, packet loss) along with how unevenly their inputs arrive (`input`).
## With a `log_dir` (DedicatedServer) the events go to <log_dir>/hits_<match>.jsonl and `finish`
## appends one summary line per player to <log_dir>/hitreg.jsonl (every match: the history
## tools/server/hitreg_report.py reads) and prints a table into the match log.
extends RefCounted
class_name HitLog

var log_dir: String = ""   # "" = keep counting, write nothing
var match_id: int = 0
var mode: String = ""
var _file: FileAccess = null
var _t0: int = Time.get_ticks_msec()
var players: Dictionary = {}  # player id -> counters (_p)

func enabled() -> bool:
	return log_dir != ""

func _p(id: int) -> Dictionary:
	if not players.has(id):
		players[id] = {
			"name": "", "hero": "", "shots": 0, "shot_hits": 0, "claims": 0, "verdicts": {},
			"dealt": 0.0, "taken": 0.0, "taken_by": {}, "weapons": {},
			"rtt_sum": 0.0, "rtt_n": 0, "rtt_max": 0.0, "loss_max": 0.0,
			"inputs": 0, "gap_max": 0.0, "gaps_over_100": 0, "early_sum": 0.0,
		}
	return players[id]

func _weapon(id: int, weapon: int) -> Dictionary:
	var w: Dictionary = _p(id).weapons
	if not w.has(str(weapon)):
		w[str(weapon)] = {"shots": 0, "hits": 0, "claims": 0, "ok": 0, "dealt": 0.0}
	return w[str(weapon)]

func _write(event: Dictionary) -> void:
	if not enabled():
		return
	if _file == null:
		DirAccess.make_dir_recursive_absolute(log_dir)
		_file = FileAccess.open(log_dir.path_join("hits_%d.jsonl" % match_id), FileAccess.WRITE)
		if _file == null:
			log_dir = ""
			return
	event["t"] = snappedf((Time.get_ticks_msec() - _t0) / 1000.0, 0.01)
	_file.store_line(JSON.stringify(event))

## A client said its bullet hit `target`; `verdict` is what the server made of it
func claim(shooter: int, target: int, weapon: int, verdict: String, extra: Dictionary = {}) -> void:
	var p = _p(shooter)
	p.claims += 1
	p.verdicts[verdict] = int(p.verdicts.get(verdict, 0)) + 1
	var w = _weapon(shooter, weapon)
	w.claims += 1
	if verdict == "ok" or verdict == "early":
		w.ok += 1
	if verdict == "early":
		p.early_sum += float(extra.get("early", 0.0))
	var e = {"ev": "claim", "by": shooter, "to": target, "gun": weapon, "v": verdict}
	e.merge(extra)
	_write(e)

## A shot the server resolved itself (pellets, pierce, fire, grenades, unreported bullets)
func shot(shooter: int, weapon: int, hit: bool) -> void:
	var p = _p(shooter)
	p.shots += 1
	var w = _weapon(shooter, weapon)
	w.shots += 1
	if hit:
		p.shot_hits += 1
		w.hits += 1
	_write({"ev": "shot", "by": shooter, "gun": weapon, "hit": hit})

## Damage that landed (after shields); attacker 0 = the world (zone, events, weeds: `kind` says)
func damage(attacker: int, victim: int, amount: float, kind: String, weapon: int = -1) -> void:
	if attacker > 0:
		_p(attacker).dealt += amount
		if weapon >= 0:
			_weapon(attacker, weapon).dealt += amount
	var v = _p(victim)
	v.taken += amount
	v.taken_by[kind] = snappedf(float(v.taken_by.get(kind, 0.0)) + amount, 0.1)
	_write({"ev": "dmg", "by": attacker, "to": victim, "amt": snappedf(amount, 0.1), "kind": kind, "gun": weapon})

## An input arrived `gap` seconds after the previous one (the client sends ~30 a second)
func input(id: int, gap: float) -> void:
	var p = _p(id)
	p.inputs += 1
	p.gap_max = maxf(p.gap_max, gap)
	if gap > 0.1:
		p.gaps_over_100 += 1

## The connection right now: round trip (ms) and packet loss (0..1)
func sample(id: int, rtt: float, loss: float) -> void:
	var p = _p(id)
	p.rtt_sum += rtt
	p.rtt_n += 1
	p.rtt_max = maxf(p.rtt_max, rtt)
	p.loss_max = maxf(p.loss_max, loss)
	_write({"ev": "net", "id": id, "rtt": int(rtt), "loss": snappedf(loss, 0.001)})

## The match is over: a table in the log, one summary line per player into hitreg.jsonl
func finish(names: Dictionary, heroes: Dictionary) -> void:
	var lines: Array = []
	print("[HitLog] ---- hit registration, match %d (%s) ----" % [match_id, mode])
	print("[HitLog] %-16s %6s %6s %7s %7s %7s %6s %6s  %s" % ["player", "claims", "ok%", "srvshot", "srvhit%", "rtt", "rttmax", "gap", "rejected"])
	for id in players:
		var p: Dictionary = players[id]
		p.name = String(names.get(id, str(id)))
		p.hero = String(heroes.get(id, ""))
		var ok = int(p.verdicts.get("ok", 0)) + int(p.verdicts.get("early", 0))
		var rejected = p.verdicts.duplicate()
		rejected.erase("ok")
		rejected.erase("early")
		print("[HitLog] %-16s %6d %5.0f%% %7d %6.0f%% %6.0fms %5.0fms %5.0fms  %s" % [
			p.name.left(16), p.claims, 100.0 * ok / maxf(p.claims, 1), p.shots, 100.0 * p.shot_hits / maxf(p.shots, 1),
			p.rtt_sum / maxf(p.rtt_n, 1), p.rtt_max, p.gap_max * 1000.0, rejected])
		var summary = p.duplicate(true)
		summary["match"] = match_id
		summary["mode"] = mode
		summary["id"] = id
		summary["rtt_avg"] = snappedf(p.rtt_sum / maxf(p.rtt_n, 1), 0.1)
		summary.erase("rtt_sum")
		lines.append(JSON.stringify(summary))
	if _file:
		_file.close()
		_file = null
	if not enabled() or lines.is_empty():
		return
	var path = log_dir.path_join("hitreg.jsonl")
	var f = FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.seek_end()
		for l in lines:
			f.store_line(l)
		f.close()
