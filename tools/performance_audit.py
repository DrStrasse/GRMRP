#!/usr/bin/env python3
"""Static performance-risk inventory for every Lua module in the addon.

This is deliberately conservative: it reports candidates, not bugs. Third-party
code is inventoried separately so an audit does not silently rewrite vendored APIs.
"""
from __future__ import annotations
import argparse, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / "lua"
PATTERNS = {
    "frame_hook": re.compile(r'hook\.Add\s*\(\s*["\'](?:Think|Tick|HUDPaint|HUDPaintBackground|PostDraw\w*|PreDraw\w*|RenderScreenspaceEffects)["\']'),
    "entity_scan": re.compile(r'ents\.(?:GetAll|FindByClass|FindInSphere)\s*\('),
    "player_scan": re.compile(r'player\.GetAll\s*\('),
    "disk_io": re.compile(r'file\.(?:Read|Write|Append|Open|Delete|Rename)\s*\('),
    "json_work": re.compile(r'util\.(?:TableToJSON|JSONToTable)\s*\('),
    "large_net_table": re.compile(r'net\.WriteTable\s*\('),
}
TIMER = re.compile(r'timer\.Create\s*\([^,]+,\s*(\d+(?:\.\d+)?)\s*,\s*0\s*,')

def line_hits(text: str, pattern: re.Pattern[str]) -> list[int]:
    return [text.count("\n", 0, m.start()) + 1 for m in pattern.finditer(text)]

def audit(path: Path) -> dict:
    text = path.read_text("utf-8", errors="replace")
    rel = path.relative_to(ROOT).as_posix()
    hits = {name: line_hits(text, rx) for name, rx in PATTERNS.items()}
    fast = []
    for m in TIMER.finditer(text):
        if float(m.group(1)) <= 0.5:
            fast.append(text.count("\n", 0, m.start()) + 1)
    hits["fast_timer"] = fast
    frame = bool(hits["frame_hook"] or hits["fast_timer"])
    expensive = bool(hits["entity_scan"] or hits["player_scan"] or hits["disk_io"] or hits["json_work"] or hits["large_net_table"])
    score = sum(len(v) for v in hits.values()) + (8 if frame and expensive else 0)
    return {"file": rel, "third_party": rel.startswith("lua/easychat/"), "score": score,
            "hot_combination": frame and expensive, "hits": hits}

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--top", type=int, default=30)
    args = ap.parse_args()
    rows = [audit(p) for p in sorted(LUA.rglob("*.lua"))]
    if args.json:
        print(json.dumps({"files": len(rows), "rows": rows}, ensure_ascii=False, indent=2))
        return 0
    first = [r for r in rows if not r["third_party"]]
    third = [r for r in rows if r["third_party"]]
    hot = [r for r in first if r["hot_combination"]]
    print(f"Lua files: {len(rows)}; GRM: {len(first)}; third-party: {len(third)}")
    print(f"Hot-loop + expensive-operation candidates: {len(hot)}")
    print("Top candidates (static score):")
    for r in sorted(first, key=lambda x: (-x["score"], x["file"]))[:max(0, args.top)]:
        labels = ", ".join(f"{k}:{len(v)}" for k, v in r["hits"].items() if v)
        print(f"{r['score']:3d}  {r['file']}  [{labels}]")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
