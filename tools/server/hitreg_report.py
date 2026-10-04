#!/usr/bin/env python3
"""Hit registration report from the game servers' logs (network/server/HitLog.gd).

On the VPS:   python3 /opt/royaltim/hitreg_report.py            (all matches)
              python3 /opt/royaltim/hitreg_report.py --last 10  (the last 10 matches)
Locally:      python tools/server/hitreg_report.py --file <hitreg.jsonl>

Reads <logs>/hitreg.jsonl (one line per player per match) and prints:
- how many client-reported hits the server took, and why it threw the others away;
- the same per gun (the guns whose hits get lost most);
- hit rate against the player's ping and input jitter (does lag cost hits?);
- where damage came from (guns, abilities, weeds, the zone).
"""
import argparse
import json
import os
from collections import Counter, defaultdict

GUNS = ["Pistol", "Shotgun", "Sniper", "Rifle", "Flamethrower", "SMG", "Hand Cannon", "Marksman",
        "Minigun", "Double Barrel", "Jam Blaster", "Grenade Launcher"]
OK = ("ok", "early", "server")  # "server": a pellet / flame / grenade gun, the server shot it itself


def pct(a, b):
    return "%5.1f%%" % (100.0 * a / b) if b else "    - "


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="/opt/royaltim/data/logs/hitreg.jsonl")
    ap.add_argument("--last", type=int, default=0, help="only the last N matches")
    a = ap.parse_args()
    if not os.path.exists(a.file):
        print("no log yet:", a.file)
        return
    rows = [json.loads(l) for l in open(a.file, encoding="utf-8") if l.strip()]
    if a.last:
        keep = sorted({r["match"] for r in rows})[-a.last:]
        rows = [r for r in rows if r["match"] in keep]
    matches = sorted({r["match"] for r in rows})
    print("%d matches, %d player records" % (len(matches), len(rows)))

    verdicts = Counter()
    for r in rows:
        verdicts.update(r.get("verdicts", {}))
    claims = sum(verdicts.values())
    taken = sum(verdicts[v] for v in OK)
    print("\n== Client-reported hits: %d, taken %s (early but taken: %s)" % (claims, pct(taken, claims), pct(verdicts["early"], claims)))
    for v, n in verdicts.most_common():
        if v not in OK:
            print("   thrown away: %-10s %6d  %s" % (v, n, pct(n, claims)))
    early = sum(r.get("early_sum", 0.0) for r in rows)
    if verdicts["early"]:
        print("   an early shot came %.0f ms early on average" % (1000.0 * early / verdicts["early"]))

    print("\n== Per gun            claims  taken  | server shots  hit")
    per = defaultdict(lambda: Counter())
    for r in rows:
        for t, w in r.get("weapons", {}).items():
            per[int(t)].update(w)
    for t in sorted(per):
        w = per[t]
        name = GUNS[t] if 0 <= t < len(GUNS) else str(t)
        print("   %-17s %6d %s  | %6d %s   dealt %.0f" % (name, w["claims"], pct(w["ok"], w["claims"]), w["shots"], pct(w["hits"], w["shots"]), w["dealt"]))

    print("\n== Ping vs hits taken")
    buckets = defaultdict(lambda: [0, 0, 0])  # claims, taken, players
    for r in rows:
        rtt = r.get("rtt_avg", 0)
        b = "<50 ms" if rtt < 50 else "50-100 ms" if rtt < 100 else "100-200 ms" if rtt < 200 else ">200 ms"
        v = r.get("verdicts", {})
        buckets[b][0] += sum(v.values())
        buckets[b][1] += sum(v.get(k, 0) for k in OK)
        buckets[b][2] += 1
    for b in ["<50 ms", "50-100 ms", "100-200 ms", ">200 ms"]:
        if b in buckets:
            c, t, n = buckets[b]
            print("   %-11s %3d players  %6d claims  taken %s" % (b, n, c, pct(t, c)))
    gaps = [r.get("gap_max", 0) for r in rows]
    bumpy = [r for r in rows if r.get("inputs") and r.get("gaps_over_100", 0) / r["inputs"] > 0.05]
    if gaps:
        print("   input gaps: worst %.0f ms; %d of %d players had >5%% of inputs arrive 100+ ms apart" % (
            1000.0 * max(gaps), len(bumpy), len(rows)))
    loss = [r.get("loss_max", 0) for r in rows]
    if loss:
        print("   packet loss: worst %.1f%%" % (100.0 * max(loss)))

    print("\n== Damage by source")
    by = Counter()
    for r in rows:
        by.update(r.get("taken_by", {}))
    total = sum(by.values())
    for k, v in by.most_common():
        print("   %-8s %8.0f  %s" % (k, v, pct(v, total)))


if __name__ == "__main__":
    main()
