#!/usr/bin/env python3
"""ROYALTIM-3 backend: accounts and profiles (SQLite), matchmaking, one game server process per match.

Python 3 standard library only. Clients talk JSON over HTTP (network/online/Online.gd):
  POST /login {device, version}            -> account + profile (a new device gets a new account)
  GET  /profile                            -> profile
  POST /profile/name {name}                -> nickname
  POST /profile/starters {heroes}          -> the free heroes of a new account
  POST /profile/buy {id}                   -> coins -> cosmetic / hero (prices from catalog.json)
  POST /profile/equip {id, hero, weapon_type}
  POST /queue/join {mode, hero}            -> into the queue of that mode
  GET  /queue/status                       -> searching / starting / found {port, ticket} / idle
  POST /queue/leave                        (a party leaves together)
  GET  /friends                            -> friends (with what they are doing), requests in / out
  POST /friends/add {id} | /friends/accept {id} | /friends/decline {id} | /friends/remove {id}
  POST /users/search {q}                   -> players by nickname
  POST /users/profile {id}                 -> a player's public profile (hero, what they own, mastery)
  POST /profile/hero {hero}                -> the hero you play (others see it; party members queue with it)
  GET  /party                              -> your party, invites to you, its queue state
  POST /party/invite {id} | /party/accept {from} | /party/decline {from} | /party/leave
  Parties are PARTY_MAX (2) friends; the leader's /queue/join queues them together and the
  matchmaker never splits them (CTF puts them in one team: "party" in the roster).
  GET  /status                             -> registered / online players, queues, matches (the main menu
                                              asks every few seconds: with the Bearer it also counts as "seen")
  GET  /leaderboard?limit=N (default 20, max 100) -> public top players by coins earned, no auth, for the website
Game servers (DedicatedServer.gd, localhost + X-Server-Key):
  POST /match/ready {match}                -> its players get "found"
  POST /match/report {match, account, coins, hero, hero_xp, weapon_xp} -> applied once per player
Authorization for clients: "Authorization: Bearer <device key>" (the key never leaves the device and
this server, only its hash is stored).

catalog.json comes from the game (tools/server/export_catalog.gd): prices, kinds, heroes, mastery.
The rules below mirror ui/profile/PlayerProfile.gd and Mastery.gd - keep them in step.
"""
import argparse
import hashlib
import json
import os
import re
import secrets
import sqlite3
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# mode -> players: min to start, max per match, seconds the oldest waits for more before starting
MODES = {
    "br": {"min": 2, "max": 12, "fill": 20.0},
    "survivors": {"min": 1, "max": 4, "fill": 8.0},
    "ctf": {"min": 2, "max": 8, "fill": 20.0},
    "koth": {"min": 2, "max": 8, "fill": 20.0},
}
QUEUE_STALE = 15.0      # a queued client that stopped asking is gone
FOUND_KEEP = 30 * 60.0  # how long "found" is kept (a crashed client can come back to its match)
MATCH_MAX_TIME = 45 * 60.0  # a game server running longer than this is stopped
ONLINE_WINDOW = 60.0    # seen this recently (the menu asks /status every 15 s) or in a match = online
MAX_COINS_PER_MATCH = 3000
MAX_XP_PER_MATCH = 30000

ARGS = None
CATALOG = {}
SERVER_KEY = ""
DB = None
LOCK = threading.RLock()  # DB + queue + matches
QUEUE = {}    # account -> {mode, hero, nickname, wear, joined, polled}
FOUND = {}    # account -> {match, port, ticket, at}
MATCHES = {}  # match id -> {mode, port, proc, accounts, ready, started}
PARTIES = {}    # party id -> {"leader": account, "members": [accounts]}
ACC_PARTY = {}  # account -> party id
INVITES = {}    # invited account -> {inviting account: time}
PARTY_MAX = 2
INVITE_TTL = 120.0
_next_party = [1]


def now():
    return time.time()


def log(*parts):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *parts, flush=True)


# ------------------------------------------------------------------ database

def open_db(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("""CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT, token_hash TEXT UNIQUE NOT NULL,
        profile TEXT NOT NULL, created REAL NOT NULL, seen REAL NOT NULL)""")
    db.execute("""CREATE TABLE IF NOT EXISTS matches (
        id INTEGER PRIMARY KEY AUTOINCREMENT, mode TEXT, port INTEGER, players TEXT,
        started REAL, ended REAL, exit_code INTEGER)""")
    db.execute("""CREATE TABLE IF NOT EXISTS rewards (
        match INTEGER NOT NULL, account INTEGER NOT NULL, coins INTEGER, hero TEXT, hero_xp INTEGER,
        weapon_xp TEXT, at REAL, PRIMARY KEY (match, account))""")
    db.execute("""CREATE TABLE IF NOT EXISTS friends (
        a INTEGER NOT NULL, b INTEGER NOT NULL, status TEXT NOT NULL, created REAL,
        PRIMARY KEY (a, b))""")  # a asked b; status "pending" / "accepted"
    db.execute("""CREATE TABLE IF NOT EXISTS purchases (
        account INTEGER NOT NULL, item TEXT NOT NULL, price INTEGER, at REAL)""")
    return db


def new_profile():
    return {
        "nickname": "", "coins": int(CATALOG.get("start_coins", 300)), "owned": [],
        "hero_skin": {}, "hero_hat": {}, "weapon_skin": "default", "weapon_skin_by_type": {},
        "hero_xp": {}, "weapon_xp": {},
    }


def token_hash(device):
    return hashlib.sha256(("royaltim:" + device).encode()).hexdigest()


def load_account(account_id):
    row = DB.execute("SELECT profile FROM accounts WHERE id=?", (account_id,)).fetchone()
    if not row:
        return None
    p = new_profile()
    p.update(json.loads(row[0]))
    return p


def save_account(account_id, profile):
    DB.execute("UPDATE accounts SET profile=?, seen=? WHERE id=?", (json.dumps(profile), now(), account_id))


# ------------------------------------------------------------------ rules (PlayerProfile / Mastery)

def item(id_):
    return CATALOG["items"].get(id_)


def price_of(id_):
    it = item(id_)
    return int(it["price"]) if it else -1


def mastery_progress(xp, weapon):
    m = CATALOG["mastery"]
    base, step = (m["weapon_base"], m["weapon_step"]) if weapon else (m["hero_base"], m["hero_step"])
    level, left = 1, max(int(xp), 0)
    while level < m["max_level"] and left >= base + step * (level - 1):
        left -= base + step * (level - 1)
        level += 1
    tier = -1
    for i, start in enumerate(m["tier_levels"]):
        if level >= start:
            tier = i
    return tier


def owns(p, id_):
    it = item(id_)
    if not it or it["rank"] >= 0:
        return False
    return it["price"] == 0 or id_ in p["owned"]


def owns_for(p, id_, hero="", weapon_type=-1):
    it = item(id_)
    if not it:
        return False
    if it["rank"] < 0:
        return owns(p, id_)
    if it["kind"] == "weapon":
        return weapon_type >= 0 and mastery_progress(p["weapon_xp"].get(str(weapon_type), 0), True) >= it["rank"]
    return hero != "" and mastery_progress(p["hero_xp"].get(hero, 0), False) >= it["rank"]


def owns_hero(p, hero):
    return ("hero:" + hero) in p["owned"]


# ------------------------------------------------------------------ matches

def free_port():
    used = {m["port"] for m in MATCHES.values()}
    for port in range(ARGS.port_first, ARGS.port_last + 1):
        if port not in used:
            return port
    return None


def start_match(mode, entries):
    port = free_port()
    cur = DB.execute("INSERT INTO matches (mode, port, players, started) VALUES (?,?,?,?)",
                     (mode, port, json.dumps([e["account"] for e in entries]), now()))
    match_id = cur.lastrowid
    roster = {}
    for e in entries:
        ticket = secrets.token_hex(12)
        roster[ticket] = {"account": e["account"], "nickname": e["nickname"], "hero": e["hero"], "party": e.get("party", 0)}
        FOUND[e["account"]] = {"match": match_id, "port": port, "ticket": ticket, "at": now()}
        QUEUE.pop(e["account"], None)
    os.makedirs(os.path.join(ARGS.data, "matches"), exist_ok=True)
    os.makedirs(os.path.join(ARGS.data, "logs"), exist_ok=True)
    roster_path = os.path.join(ARGS.data, "matches", "%d.json" % match_id)
    with open(roster_path, "w") as f:
        json.dump({"mode": mode, "players": roster}, f)
    out = open(os.path.join(ARGS.data, "logs", "match_%d.log" % match_id), "w")
    cmd = [ARGS.server_bin, "--headless", "--", "--server", "--port=%d" % port, "--mode=%s" % mode,
           "--min-players=%d" % len(entries), "--match=%d" % match_id, "--roster=%s" % roster_path,
           "--backend=http://127.0.0.1:%d" % ARGS.port, "--key=%s" % SERVER_KEY]
    proc = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT, cwd=os.path.dirname(ARGS.server_bin),
                            start_new_session=True)
    MATCHES[match_id] = {"mode": mode, "port": port, "proc": proc, "log": out, "ready": False,
                         "started": now(), "accounts": [e["account"] for e in entries]}
    log("match %d (%s) on port %d: %s" % (match_id, mode, port, ", ".join(e["nickname"] for e in entries)))


def end_match(match_id, m, code):
    m["log"].close()
    DB.execute("UPDATE matches SET ended=?, exit_code=? WHERE id=?", (now(), code, match_id))
    for acc in m["accounts"]:
        f = FOUND.get(acc)
        if f and f["match"] == match_id:
            FOUND.pop(acc, None)
    MATCHES.pop(match_id, None)
    try:
        os.remove(os.path.join(ARGS.data, "matches", "%d.json" % match_id))
    except OSError:
        pass
    log("match %d ended (exit %s)" % (match_id, code))


def matchmaker_loop():
    while True:
        time.sleep(1.0)
        try:
            with LOCK:
                t = now()
                for match_id, m in list(MATCHES.items()):
                    code = m["proc"].poll()
                    if code is None and t - m["started"] > MATCH_MAX_TIME:
                        m["proc"].kill()
                        code = m["proc"].wait()
                    if code is not None:
                        end_match(match_id, m, code)
                for acc, q in list(QUEUE.items()):
                    if t - q["polled"] > QUEUE_STALE:
                        QUEUE.pop(acc, None)
                for acc, f in list(FOUND.items()):
                    if t - f["at"] > FOUND_KEEP:
                        FOUND.pop(acc, None)
                for mode, rule in MODES.items():
                    units = queue_units(mode)  # a party is one unit: never split
                    while units:
                        count = sum(len(u) for u in units)
                        enough = count >= rule["max"] or (count >= rule["min"] and t - units[0][0]["joined"] >= rule["fill"])
                        if not enough or len(MATCHES) >= ARGS.max_matches or free_port() is None:
                            break
                        group, rest, size = [], [], 0
                        for u in units:
                            if size + len(u) <= rule["max"]:
                                group.append(u)
                                size += len(u)
                            else:
                                rest.append(u)
                        start_match(mode, [e for u in group for e in u])
                        units = rest
        except Exception as ex:  # keep matching whatever happened
            log("matchmaker error:", repr(ex))


# ------------------------------------------------------------------ HTTP

class Handler(BaseHTTPRequestHandler):
    server_version = "royaltim"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _send(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > 65536:
            return {}
        try:
            data = json.loads(self.rfile.read(n))
            return data if isinstance(data, dict) else {}
        except ValueError:
            return {}

    def _query_int(self, key, default, lo, hi):
        qs = self.path.split("?", 1)[1] if "?" in self.path else ""
        for part in qs.split("&"):
            k, _, v = part.partition("=")
            if k == key:
                try:
                    return max(lo, min(hi, int(v)))
                except ValueError:
                    return default
        return default

    def _account(self):
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return None
        row = DB.execute("SELECT id FROM accounts WHERE token_hash=?", (token_hash(auth[7:].strip()),)).fetchone()
        return row[0] if row else None

    def _internal(self):
        return self.client_address[0] in ("127.0.0.1", "::1") and secrets.compare_digest(
            self.headers.get("X-Server-Key", ""), SERVER_KEY)

    def do_GET(self):
        self._route("GET", {})

    def do_POST(self):
        self._route("POST", self._body())

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _route(self, method, body):
        path = self.path.split("?")[0]
        try:
            with LOCK:
                if path == "/status":
                    account = self._account()
                    if account is not None:
                        DB.execute("UPDATE accounts SET seen=? WHERE id=?", (now(), account))
                    return self._send(200, status())
                if path == "/leaderboard" and method == "GET":
                    return self._send(200, leaderboard(self._query_int("limit", 20, 1, 100)))
                if path == "/login" and method == "POST":
                    return self._send(200, login(body))
                if path.startswith("/match/"):
                    if not self._internal():
                        return self._send(403, {"ok": False, "error": "forbidden"})
                    if path == "/match/ready":
                        return self._send(200, match_ready(body))
                    if path == "/match/report":
                        return self._send(200, match_report(body))
                account = self._account()
                if account is None:
                    return self._send(401, {"ok": False, "error": "Not logged in"})
                DB.execute("UPDATE accounts SET seen=? WHERE id=?", (now(), account))
                p = load_account(account)
                handler = ROUTES.get((method, path))
                if handler is None:
                    return self._send(404, {"ok": False, "error": "Unknown request"})
                result = handler(account, p, body)
                return self._send(200, result)
        except Exception as ex:
            log("error on", path, repr(ex))
            return self._send(500, {"ok": False, "error": "Server error"})


def reply(p, ok=True, error="", **extra):
    out = {"ok": ok, "profile": p}
    if error:
        out["error"] = error
    out.update(extra)
    return out


def status():
    t = now()
    online = {row[0] for row in DB.execute("SELECT id FROM accounts WHERE seen > ?", (t - ONLINE_WINDOW,))}
    online.update(QUEUE.keys())
    for m in MATCHES.values():
        online.update(m["accounts"])
    registered = DB.execute("SELECT COUNT(*) FROM accounts WHERE json_extract(profile, '$.nickname') != ''").fetchone()[0]
    queues = {mode: sum(1 for q in QUEUE.values() if q["mode"] == mode) for mode in MODES}
    return {"ok": True, "version": CATALOG.get("version", ""), "online": len(online), "registered": registered, "queues": queues,
            "matches": [{"id": i, "mode": m["mode"], "players": len(m["accounts"])} for i, m in MATCHES.items()]}


def leaderboard(limit):
    """Public top players by coins earned across all matches, for the website (no auth)."""
    rows = DB.execute(
        "SELECT account, SUM(coins) AS total, COUNT(*) AS matches FROM rewards GROUP BY account ORDER BY total DESC LIMIT ?",
        (limit,)).fetchall()
    players = []
    for account, total, matches in rows:
        p = load_account(account)
        if p is None or not p["nickname"]:
            continue
        hero = member_hero(p)
        players.append({
            "id": account, "nickname": p["nickname"], "hero": hero,
            "skin": p["hero_skin"].get(hero, "classic"), "hat": p["hero_hat"].get(hero, "no_hat"),
            "coins": int(total or 0), "level": mastery_level(p["hero_xp"].get(hero, 0), False),
            "matches": matches,
        })
    return {"ok": True, "players": players}


def login(body):
    device = str(body.get("device", ""))
    if not re.fullmatch(r"[0-9a-f]{32,128}", device):
        return {"ok": False, "error": "Bad device key"}
    version = str(body.get("version", ""))
    if CATALOG.get("version") and version != CATALOG["version"]:
        return {"ok": False, "error": "Update the game: the server runs v%s" % CATALOG["version"], "server_version": CATALOG["version"]}
    h = token_hash(device)
    row = DB.execute("SELECT id FROM accounts WHERE token_hash=?", (h,)).fetchone()
    if row:
        account = row[0]
    else:
        account = DB.execute("INSERT INTO accounts (token_hash, profile, created, seen) VALUES (?,?,?,?)",
                             (h, json.dumps(new_profile()), now(), now())).lastrowid
        log("new account", account)
    p = load_account(account)
    save_account(account, p)
    return reply(p, account=account)


def get_profile(account, p, body):
    save_account(account, p)  # "seen"
    return reply(p)


def set_name(account, p, body):
    name = str(body.get("name", "")).strip()
    if not (CATALOG.get("name_min", 3) <= len(name) <= CATALOG.get("name_max", 16)):
        return reply(p, False, "The name must be 3 to 16 characters long")
    p["nickname"] = name
    save_account(account, p)
    return reply(p)


def set_starters(account, p, body):
    heroes = body.get("heroes", [])
    if any(i.startswith("hero:") for i in p["owned"]):
        return reply(p, False, "Starting heroes are already picked")
    if not isinstance(heroes, list) or len(set(heroes)) != CATALOG.get("starter_picks", 2) \
            or any(h not in CATALOG["heroes"] for h in heroes):
        return reply(p, False, "Pick %d heroes" % CATALOG.get("starter_picks", 2))
    p["owned"] += ["hero:" + h for h in heroes]
    save_account(account, p)
    return reply(p)


def buy(account, p, body):
    id_ = str(body.get("id", ""))
    if owns(p, id_):
        return reply(p)
    price = price_of(id_)
    it = item(id_)
    if price < 0 or (it and it["rank"] >= 0):
        return reply(p, False, "Not for sale")
    if p["coins"] < price:
        return reply(p, False, "Not enough coins")
    p["coins"] -= price
    p["owned"].append(id_)
    save_account(account, p)
    DB.execute("INSERT INTO purchases (account, item, price, at) VALUES (?,?,?,?)", (account, id_, price, now()))
    return reply(p)


def equip(account, p, body):
    id_ = str(body.get("id", ""))
    hero = str(body.get("hero", ""))
    wt = int(body.get("weapon_type", -1))
    it = item(id_)
    if not it or not owns_for(p, id_, hero, wt):
        return reply(p, False, "Not owned")
    if wt >= 0 and it["kind"] == "weapon":  # PlayerProfile.equip_weapon
        if it["rank"] >= 0:
            p["weapon_skin_by_type"][str(wt)] = id_
        else:
            p["weapon_skin"] = id_
            p["weapon_skin_by_type"].pop(str(wt), None)
    elif it["kind"] == "skin":
        p["hero_skin"][hero] = id_
    elif it["kind"] == "hat":
        p["hero_hat"][hero] = id_
    elif it["kind"] == "weapon":
        p["weapon_skin"] = id_
    save_account(account, p)
    return reply(p)


def queue_join(account, p, body):
    mode = str(body.get("mode", ""))
    hero = str(body.get("hero", ""))
    if mode not in MODES:
        return reply(p, False, "Unknown mode")
    if not p["nickname"]:
        return reply(p, False, "Pick a name first")
    if hero not in CATALOG["heroes"] or not owns_hero(p, hero):
        return reply(p, False, "You don't own this hero")
    pid = ACC_PARTY.get(account)
    if pid:
        party = PARTIES[pid]
        if party["leader"] != account:
            return reply(p, False, "Only the party leader starts the search")
        for m in party["members"]:
            if any(m in mm["accounts"] for mm in MATCHES.values()) and FOUND.get(m):
                return reply(p, False, "Your friend is still in a match")
    p["selected_hero"] = hero
    save_account(account, p)
    t = now()
    for member in (PARTIES[pid]["members"] if pid else [account]):
        mp = p if member == account else load_account(member)
        mhero = hero if member == account else member_hero(mp)
        FOUND.pop(member, None)
        QUEUE[member] = {"account": member, "mode": mode, "hero": mhero, "nickname": mp["nickname"] or ("Player %d" % member),
                         "joined": t, "polled": t, "party": pid or 0}
    return queue_status(account, p, body)


def queue_status(account, p, body):
    f = FOUND.get(account)
    if f:
        m = MATCHES.get(f["match"])
        if m:
            if not m["ready"]:
                return reply(p, state="starting", mode=m["mode"])
            return reply(p, state="found", port=f["port"], ticket=f["ticket"], match=f["match"], mode=m["mode"])
    q = QUEUE.get(account)
    if not q:
        return reply(p, state="idle")
    q["polled"] = now()
    rule = MODES[q["mode"]]
    same = sum(1 for o in QUEUE.values() if o["mode"] == q["mode"])
    busy = len(MATCHES) >= ARGS.max_matches
    return reply(p, state="searching", mode=q["mode"], waited=int(now() - q["joined"]), in_queue=same,
                 need=rule["min"], busy=busy)


def queue_leave(account, p, body):
    pid = ACC_PARTY.get(account)
    for member in (PARTIES[pid]["members"] if pid else [account]):
        QUEUE.pop(member, None)
    return reply(p, state="idle")


# ------------------------------------------------------------------ friends, parties, profiles

def queue_units(mode):
    """The queue of a mode as units in the order they joined: a party is one unit"""
    units, by_key = [], {}
    for q in sorted((q for q in QUEUE.values() if q["mode"] == mode), key=lambda q: q["joined"]):
        key = ("p", q["party"]) if q.get("party") else ("s", q["account"])
        if key not in by_key:
            by_key[key] = []
            units.append(by_key[key])
        by_key[key].append(q)
    return units


def member_hero(p):
    """The hero a party member queues with: the one they picked last, else one they own"""
    hero = p.get("selected_hero", "")
    if hero and owns_hero(p, hero):
        return hero
    owned = [i[5:] for i in p["owned"] if i.startswith("hero:")]
    return owned[0] if owned else CATALOG["heroes"][0]


def activity(account):
    """offline / online (in the menus) / searching / match"""
    if any(account in m["accounts"] for m in MATCHES.values()) and FOUND.get(account):
        return "match"
    if account in QUEUE:
        return "searching"
    row = DB.execute("SELECT seen FROM accounts WHERE id=?", (account,)).fetchone()
    return "online" if row and now() - row[0] < ONLINE_WINDOW else "offline"


def card(account, p=None):
    p = p or load_account(account)
    if p is None:
        return None
    hero = member_hero(p)
    return {"id": account, "nickname": p["nickname"] or ("Player %d" % account), "hero": hero,
            "skin": p["hero_skin"].get(hero, "classic"), "hat": p["hero_hat"].get(hero, "no_hat"),
            "level": mastery_level(p["hero_xp"].get(hero, 0), False), "state": activity(account)}


def mastery_level(xp, weapon):
    m = CATALOG["mastery"]
    base, step = (m["weapon_base"], m["weapon_step"]) if weapon else (m["hero_base"], m["hero_step"])
    level, left = 1, max(int(xp), 0)
    while level < m["max_level"] and left >= base + step * (level - 1):
        left -= base + step * (level - 1)
        level += 1
    return level


def relation(me, other):
    row = DB.execute("SELECT a, status FROM friends WHERE (a=? AND b=?) OR (a=? AND b=?)", (me, other, other, me)).fetchone()
    if not row:
        return "none"
    if row[1] == "accepted":
        return "friend"
    return "requested" if row[0] == me else "incoming"


def friends_list(account, p, body):
    out = {"friends": [], "incoming": [], "outgoing": []}
    for a, b, st in DB.execute("SELECT a, b, status FROM friends WHERE a=? OR b=?", (account, account)).fetchall():
        other = b if a == account else a
        c = card(other)
        if c is None:
            continue
        if st == "accepted":
            out["friends"].append(c)
        elif a == account:
            out["outgoing"].append(c)
        else:
            out["incoming"].append(c)
    order = {"match": 0, "searching": 1, "online": 2, "offline": 3}
    out["friends"].sort(key=lambda c: (order[c["state"]], c["nickname"].lower()))
    return reply(p, **out)


def friend_add(account, p, body):
    other = int(body.get("id", 0))
    if other == account or load_account(other) is None:
        return reply(p, False, "No such player")
    rel = relation(account, other)
    if rel == "incoming":
        return friend_accept(account, p, body)
    if rel == "none":
        DB.execute("INSERT INTO friends (a, b, status, created) VALUES (?,?,?,?)", (account, other, "pending", now()))
    return friends_list(account, p, body)


def friend_accept(account, p, body):
    other = int(body.get("id", 0))
    DB.execute("UPDATE friends SET status='accepted' WHERE a=? AND b=?", (other, account))
    return friends_list(account, p, body)


def friend_decline(account, p, body):
    other = int(body.get("id", 0))
    DB.execute("DELETE FROM friends WHERE a=? AND b=? AND status='pending'", (other, account))
    return friends_list(account, p, body)


def friend_remove(account, p, body):
    other = int(body.get("id", 0))
    DB.execute("DELETE FROM friends WHERE (a=? AND b=?) OR (a=? AND b=?)", (account, other, other, account))
    return friends_list(account, p, body)


def user_search(account, p, body):
    q = str(body.get("q", "")).strip().lower()
    found = []
    if len(q) >= 2:
        for acc, prof in DB.execute("SELECT id, profile FROM accounts").fetchall():
            nick = json.loads(prof).get("nickname", "")
            if acc != account and nick and q in nick.lower():
                c = card(acc)
                c["relation"] = relation(account, acc)
                found.append(c)
            if len(found) >= 15:
                break
    return reply(p, players=found)


def user_profile(account, p, body):
    other = int(body.get("id", account))
    op = load_account(other)
    if op is None:
        return reply(p, False, "No such player")
    owned = op["owned"]
    rows = DB.execute("SELECT COUNT(*), COALESCE(SUM(coins), 0) FROM rewards WHERE account=?", (other,)).fetchone()
    view = card(other, op)
    view.update({
        "relation": "self" if other == account else relation(account, other),
        "heroes": [i[5:] for i in owned if i.startswith("hero:")],
        "skins": [i for i in owned if item(i) and item(i)["kind"] == "skin"],
        "hats": [i for i in owned if item(i) and item(i)["kind"] == "hat"],
        "finishes": [i for i in owned if item(i) and item(i)["kind"] == "weapon"],
        "hero_levels": {h: mastery_level(x, False) for h, x in op["hero_xp"].items()},
        "weapon_levels": {t: mastery_level(x, True) for t, x in op["weapon_xp"].items()},
        "weapon_skin": op["weapon_skin"], "matches": rows[0], "earned": rows[1],
    })
    return reply(p, player=view)


def set_hero(account, p, body):
    hero = str(body.get("hero", ""))
    if hero in CATALOG["heroes"] and owns_hero(p, hero):
        p["selected_hero"] = hero
        save_account(account, p)
    return reply(p)


def party_view(account):
    pid = ACC_PARTY.get(account)
    party = None
    if pid:
        pt = PARTIES[pid]
        party = {"id": pid, "leader": pt["leader"], "members": [card(m) for m in pt["members"]]}
    t = now()
    mine = INVITES.get(account, {})
    for frm in [f for f, at in mine.items() if t - at > INVITE_TTL]:
        mine.pop(frm, None)
    invites = [{"from": f, "nickname": (load_account(f) or {}).get("nickname", "")} for f in mine]
    return party, invites


def party_get(account, p, body):
    party, invites = party_view(account)
    q = queue_status(account, p, body)
    return reply(p, party=party, invites=invites, queue=q.get("state"), mode=q.get("mode", ""))


def party_invite(account, p, body):
    other = int(body.get("id", 0))
    if relation(account, other) != "friend":
        return reply(p, False, "Only friends can be invited")
    if activity(other) == "offline":
        return reply(p, False, "Your friend is offline")
    pid = ACC_PARTY.get(account)
    if pid and len(PARTIES[pid]["members"]) >= PARTY_MAX:
        return reply(p, False, "The party is full")
    if ACC_PARTY.get(other) and ACC_PARTY.get(other) == pid:
        return reply(p, False, "Already in your party")
    INVITES.setdefault(other, {})[account] = now()
    return party_get(account, p, body)


def _leave_party(account):
    pid = ACC_PARTY.pop(account, None)
    if not pid:
        return
    pt = PARTIES[pid]
    for m in pt["members"]:
        QUEUE.pop(m, None)  # a party that changes leaves the queue
    pt["members"].remove(account)
    if len(pt["members"]) < 2:
        for m in pt["members"]:
            ACC_PARTY.pop(m, None)
        PARTIES.pop(pid, None)
    elif pt["leader"] == account:
        pt["leader"] = pt["members"][0]


def party_accept(account, p, body):
    frm = int(body.get("from", 0))
    if frm not in INVITES.get(account, {}) or now() - INVITES[account][frm] > INVITE_TTL:
        return reply(p, False, "The invitation has expired")
    INVITES[account].pop(frm, None)
    pid = ACC_PARTY.get(frm)
    if pid and len(PARTIES[pid]["members"]) >= PARTY_MAX:
        return reply(p, False, "The party is full")
    _leave_party(account)
    QUEUE.pop(account, None)
    if not pid:
        pid = _next_party[0]
        _next_party[0] += 1
        PARTIES[pid] = {"leader": frm, "members": [frm]}
        ACC_PARTY[frm] = pid
        QUEUE.pop(frm, None)
    PARTIES[pid]["members"].append(account)
    ACC_PARTY[account] = pid
    log("party %d: %s" % (pid, PARTIES[pid]["members"]))
    return party_get(account, p, body)


def party_decline(account, p, body):
    INVITES.get(account, {}).pop(int(body.get("from", 0)), None)
    return party_get(account, p, body)


def party_leave(account, p, body):
    _leave_party(account)
    return party_get(account, p, body)


def match_ready(body):
    m = MATCHES.get(int(body.get("match", 0)))
    if m:
        m["ready"] = True
        log("match %s ready" % body.get("match"))
    return {"ok": True}


def match_report(body):
    match_id = int(body.get("match", 0))
    account = int(body.get("account", 0))
    coins = max(0, min(int(body.get("coins", 0)), MAX_COINS_PER_MATCH))
    hero = str(body.get("hero", ""))
    hero_xp = max(0, min(int(body.get("hero_xp", 0)), MAX_XP_PER_MATCH))
    weapon_xp = {str(int(k)): max(0, min(int(v), MAX_XP_PER_MATCH)) for k, v in dict(body.get("weapon_xp", {})).items()}
    p = load_account(account)
    if p is None:
        return {"ok": False, "error": "no such account"}
    if DB.execute("SELECT 1 FROM rewards WHERE match=? AND account=?", (match_id, account)).fetchone():
        return {"ok": True, "duplicate": True}
    DB.execute("INSERT INTO rewards (match, account, coins, hero, hero_xp, weapon_xp, at) VALUES (?,?,?,?,?,?,?)",
               (match_id, account, coins, hero, hero_xp, json.dumps(weapon_xp), now()))
    p["coins"] += coins
    if hero in CATALOG["heroes"]:
        p["hero_xp"][hero] = int(p["hero_xp"].get(hero, 0)) + hero_xp
    for t, xp in weapon_xp.items():
        p["weapon_xp"][t] = int(p["weapon_xp"].get(t, 0)) + xp
    save_account(account, p)
    log("match %d: account %d +%d coins, %s +%d xp" % (match_id, account, coins, hero, hero_xp))
    return {"ok": True}


ROUTES = {
    ("GET", "/profile"): get_profile,
    ("POST", "/profile/name"): set_name,
    ("POST", "/profile/starters"): set_starters,
    ("POST", "/profile/buy"): buy,
    ("POST", "/profile/equip"): equip,
    ("POST", "/queue/join"): queue_join,
    ("GET", "/queue/status"): queue_status,
    ("POST", "/queue/leave"): queue_leave,
    ("GET", "/friends"): friends_list,
    ("POST", "/friends/add"): friend_add,
    ("POST", "/friends/accept"): friend_accept,
    ("POST", "/friends/decline"): friend_decline,
    ("POST", "/friends/remove"): friend_remove,
    ("POST", "/users/search"): user_search,
    ("POST", "/users/profile"): user_profile,
    ("POST", "/profile/hero"): set_hero,
    ("GET", "/party"): party_get,
    ("POST", "/party/invite"): party_invite,
    ("POST", "/party/accept"): party_accept,
    ("POST", "/party/decline"): party_decline,
    ("POST", "/party/leave"): party_leave,
}


def main():
    global ARGS, CATALOG, SERVER_KEY, DB
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--data", default=os.path.join(here, "data"))
    ap.add_argument("--catalog", default=os.path.join(here, "catalog.json"))
    ap.add_argument("--server-bin", default=os.path.join(here, "royaltim_server.x86_64"))
    ap.add_argument("--port-first", type=int, default=7777)
    ap.add_argument("--port-last", type=int, default=7786)
    ap.add_argument("--max-matches", type=int, default=3)
    ARGS = ap.parse_args()
    with open(ARGS.catalog) as f:
        CATALOG = json.load(f)
    os.makedirs(ARGS.data, exist_ok=True)
    key_path = os.path.join(ARGS.data, "server.key")
    if not os.path.exists(key_path):
        with open(key_path, "w") as f:
            f.write(secrets.token_hex(24))
        os.chmod(key_path, 0o600)
    with open(key_path) as f:
        SERVER_KEY = f.read().strip()
    DB = open_db(os.path.join(ARGS.data, "royaltim.db"))
    threading.Thread(target=matchmaker_loop, daemon=True).start()
    log("backend v%s on :%d, game servers %d-%d (max %d), %s" % (
        CATALOG.get("version"), ARGS.port, ARGS.port_first, ARGS.port_last, ARGS.max_matches, ARGS.server_bin))
    ThreadingHTTPServer(("0.0.0.0", ARGS.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
