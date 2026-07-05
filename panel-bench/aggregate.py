#!/usr/bin/env python3
"""aggregate.py — per-preset scorecards from judge verdicts.

Usage: python3 aggregate.py <verdicts_dir>   # expects <preset>.json files (judge-brief.md format)
"""
import json, sys, glob, os

vdir = sys.argv[1] if len(sys.argv) > 1 else "./verdicts"
TOTAL_FLAWS = 12  # 3 flawed fixtures x 4 planted flaws, every preset

for path in sorted(glob.glob(os.path.join(vdir, "*.json"))):
    d = json.load(open(path))
    preset = d["preset"]
    # unique catches: flaws only one model caught
    from collections import Counter
    catch_count = Counter()
    for m, s in d["models"].items():
        for f in s["caught"]:
            catch_count[f] += 1
    panel_caught = set(catch_count)
    print(f"\n== {preset} ==  (panel caught {len(panel_caught)}/{TOTAL_FLAWS} planted flaws)")
    print(f"{'model':38s} {'caught':>6s} {'uniq':>4s} {'fp':>3s} {'clean':>6s}")
    rows = []
    for m, s in d["models"].items():
        uniq = sum(1 for f in s["caught"] if catch_count[f] == 1)
        rows.append((len(s["caught"]), uniq, -s["fp"], m, s))
    for c, uniq, negfp, m, s in sorted(rows, reverse=True):
        print(f"{m:38s} {c:>3d}/{TOTAL_FLAWS:<2d} {uniq:>4d} {-negfp:>3d} {s['clean_verdict']:>6s}")
    missed = set(f"{x}" for x in []) # placeholder
    all_ids = set()
    for m, s in d["models"].items():
        all_ids |= set(s["caught"]) | set(s["missed"])
    never = sorted(all_ids - panel_caught)
    if never:
        print(f"  flaws NO model caught: {', '.join(never)}")
