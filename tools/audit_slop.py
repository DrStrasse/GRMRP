#!/usr/bin/env python3
"""Детектор «нейрослопа» в Lua-коде GRM.

Ищет ровно те классы мусора, которые накапливаются при генерации кода
пачками, и которые дороже всего обходятся на живом сервере:

1. cond-chain   — лестница `if x == "a" ... elseif x == "b" ...` из N веток
                  по одной и той же переменной. Просится таблица-диспетчер:
                  вместо N сравнений на каждый вызов — один хэш-лукап.
2. dup-block    — одинаковые блоки кода (>= 6 значащих строк), повторённые
                  в одном или разных файлах. Копипаста: правишь в одном
                  месте — забываешь в трёх.
3. dup-func     — функции с идентичным телом (разные имена).
4. dead         — `if false then`, код после `return`/`break` в блоке,
                  пустые ветки `else end`, `elseif` с тем же условием.
5. long-func    — функции длиннее порога (по умолчанию 150 строк).
6. deep-nest    — вложенность управляющих конструкций глубже 6.
7. repeat-lit   — один и тот же строковый литерал >= 8 раз в файле
                  (просится константа/таблица).
8. hot-alloc    — создание таблиц/строк в цикле рендера: `Color(`, `Vector(`,
                  `Material(`, `string.format(` внутри HUDPaint/Think/Paint.
9. hook-dup     — несколько hook.Add с одним и тем же именем хука И
                  одинаковым идентификатором (последний молча затирает
                  предыдущий — классический источник «модуль не работает»).

Запуск:
    python3 tools/audit_slop.py                 # сводка по репозиторию
    python3 tools/audit_slop.py --top 40        # худшие файлы
    python3 tools/audit_slop.py --kind cond-chain --min 6
    python3 tools/audit_slop.py --file lua/autorun/sh_factions.lua
    python3 tools/audit_slop.py --json out.json

Инструмент только показывает. Решение — за человеком: некоторые лестницы
осмысленны (разнотипные условия), некоторые дубли — намеренные копии в
разных аддонах.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", ".luabuild", "dist", "__pycache__", "node_modules"}

# ── нормализация ──────────────────────────────────────────────────────
STR_RE = re.compile(r'"(?:[^"\\]|\\.)*"' + r"|'(?:[^'\\]|\\.)*'")
COMMENT_RE = re.compile(r"--\[\[.*?\]\]|--\[=\[.*?\]=\]", re.S)
LINE_COMMENT_RE = re.compile(r"--(?!\[\[).*$", re.M)
NUM_RE = re.compile(r"\b\d+(\.\d+)?\b")
WS_RE = re.compile(r"\s+")

# ── шаблоны ───────────────────────────────────────────────────────────
IF_RE = re.compile(r"^\s*if\s+(.+?)\s+then\b")
ELSEIF_RE = re.compile(r"^\s*elseif\s+(.+?)\s+then\b")
CMP_RE = re.compile(r"^\s*([\w\.\:\[\]\"']+)\s*==\s*(\"[^\"]*\"|'[^']*'|[\w\.]+)\s*$")
FUNC_RE = re.compile(r"^(\s*)(?:local\s+)?function\s+([\w\.\:]*)\s*\(|^(\s*)(?:local\s+)?([\w\.]+)\s*=\s*function\s*\(")
HOOK_RE = re.compile(r"""hook\.Add\s*\(\s*["']([^"']+)["']\s*,\s*["']([^"']+)["']""")
HOT_HOOKS = ("HUDPaint", "Think", "Tick", "PostDrawOpaqueRenderables", "PreDrawHalos",
             "HUDPaintBackground", "RenderScreenspaceEffects", "CalcView", "PostDrawHUD")
# Конструкторы — только самостоятельные вызовы: obj:Angle( и a.b.Vector( это
# методы, их аллокации лежат вне контроля модуля (движок сам решает, что
# вернуть). Квалифицированные помощники (table.Copy и т.п.) — наоборот, их
# пишет автор, и они всегда аллоцируют.
HOT_CALL_RE = re.compile(
    r"(?<![:.\w])(Color|Vector|Angle|Material)\s*\("
    r"|\b(table\.Copy|util\.TableToJSON|string\.format)\s*\(")
BLOCK_OPEN_RE = re.compile(r"^\s*(if\b|for\b|while\b|repeat\b|function\b|local function\b)")


def strip_comments(text: str) -> str:
    text = COMMENT_RE.sub("", text)
    return LINE_COMMENT_RE.sub("", text)


def normalize(line: str) -> str:
    """Убрать различия, не влияющие на смысл: строки, числа, пробелы."""
    line = STR_RE.sub('"S"', line)
    line = NUM_RE.sub("N", line)
    return WS_RE.sub(" ", line).strip()


def significant(line: str) -> bool:
    stripped = line.strip()
    if not stripped or stripped.startswith("--"):
        return False
    return stripped not in ("end", "end)", "end,", "})", "}", "else", "then", "do", "),")


def iter_lua(root: str, only: str | None = None):
    if only:
        yield os.path.join(root, only) if not os.path.isabs(only) else only
        return
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in sorted(files):
            if name.endswith(".lua"):
                yield os.path.join(base, name)


# ── детекторы ─────────────────────────────────────────────────────────
def find_cond_chains(lines: list[str], min_branches: int) -> list[dict]:
    """Лестницы if/elseif по одной переменной с равенством констант."""
    out = []
    i = 0
    while i < len(lines):
        m = IF_RE.match(lines[i])
        if not m:
            i += 1
            continue
        first = CMP_RE.match(m.group(1))
        if not first:
            i += 1
            continue
        subject = first.group(1)
        branches = [(i + 1, first.group(2))]
        j = i + 1
        depth = 0
        while j < len(lines):
            line = lines[j]
            stripped = line.strip()
            # считаем вложенность, чтобы elseif внутреннего if не съел цепочку
            if BLOCK_OPEN_RE.match(line) and not stripped.startswith("elseif"):
                if re.search(r"\bthen\b|\bdo\b", stripped) or stripped.startswith("function") \
                        or stripped.startswith("local function"):
                    depth += 1
            if re.match(r"^\s*end\b", line):
                if depth == 0:
                    break
                depth -= 1
            if depth == 0:
                em = ELSEIF_RE.match(line)
                if em:
                    cmp_m = CMP_RE.match(em.group(1))
                    if cmp_m and cmp_m.group(1) == subject:
                        branches.append((j + 1, cmp_m.group(2)))
                    else:
                        break
                elif re.match(r"^\s*else\b", line):
                    pass
            j += 1
        if len(branches) >= min_branches:
            out.append({
                "kind": "cond-chain",
                "line": i + 1,
                "end_line": j + 1,
                "subject": subject,
                "branches": len(branches),
                "values": [b[1] for b in branches][:12],
                "note": f"{len(branches)} веток по `{subject}` → таблица-диспетчер",
            })
            i = j
        i += 1
    return out


def find_long_funcs(lines: list[str], limit: int) -> list[dict]:
    out = []
    stack = []
    for idx, line in enumerate(lines):
        stripped = line.strip()
        m = FUNC_RE.match(line)
        if m:
            name = m.group(2) or m.group(4) or "<аноним>"
            stack.append((idx, name, len(line) - len(line.lstrip())))
            continue
        if re.match(r"^\s*end\b", line) and stack:
            start, name, indent = stack[-1]
            if (len(line) - len(line.lstrip())) == indent:
                stack.pop()
                length = idx - start + 1
                if length >= limit:
                    out.append({"kind": "long-func", "line": start + 1, "end_line": idx + 1,
                                "name": name, "length": length,
                                "note": f"функция `{name}` длиной {length} строк"})
    return out


def find_deep_nesting(lines: list[str], limit: int) -> list[dict]:
    out = []
    depth = 0
    worst = 0
    worst_line = 0
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if re.match(r"^(if|for|while|repeat|function|local function)\b", stripped) and \
                (re.search(r"\bthen\s*$|\bdo\s*$", stripped) or stripped.endswith(")")):
            depth += 1
            if depth > worst:
                worst, worst_line = depth, idx + 1
        elif re.match(r"^(end|until)\b", stripped):
            depth = max(0, depth - 1)
    if worst > limit:
        out.append({"kind": "deep-nest", "line": worst_line, "depth": worst,
                    "note": f"вложенность {worst} уровней"})
    return out


def find_dead_code(lines: list[str]) -> list[dict]:
    out = []
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if re.match(r"^if\s+false\s+then\b", stripped) or re.match(r"^while\s+false\s+do\b", stripped):
            out.append({"kind": "dead", "line": idx + 1, "note": "ветка `if false then`"})
        if re.match(r"^else\s*$", stripped) and idx + 1 < len(lines) and \
                re.match(r"^\s*end\b", lines[idx + 1]):
            out.append({"kind": "dead", "line": idx + 1, "note": "пустая ветка else"})
        if re.match(r"^(return\b.*|break)$", stripped) and idx + 1 < len(lines):
            nxt = lines[idx + 1].strip()
            if nxt and not re.match(r"^(end|until|else|elseif|\)|\}|,)", nxt) and not nxt.startswith("--"):
                out.append({"kind": "dead", "line": idx + 2,
                            "note": "код сразу после return/break"})
    return out


def find_repeated_literals(text: str, threshold: int) -> list[dict]:
    counts = Counter()
    for match in STR_RE.finditer(text):
        value = match.group(0)
        if len(value) > 6 and not value.startswith('"http'):
            counts[value] += 1
    out = []
    for value, count in counts.most_common(6):
        if count >= threshold:
            out.append({"kind": "repeat-lit", "line": 0, "value": value[:60], "count": count,
                        "note": f"литерал {value[:40]} повторён {count} раз"})
    return out


def find_hot_allocs(lines: list[str]) -> list[dict]:
    out = []
    current = None
    depth = 0
    for idx, line in enumerate(lines):
        hook_match = re.search(r'hook\.Add\s*\(\s*["'"'"'](\w+)["'"'"']', line)
        if hook_match and hook_match.group(1) in HOT_HOOKS:
            current, depth = (hook_match.group(1), idx), 0
            continue
        if current is None:
            continue
        if re.match(r"^\s*end\s*\)", line):
            current = None
            continue
        for call in HOT_CALL_RE.finditer(line):
            name = call.group(1)
            # Color/Material с константными аргументами в рендере — самый
            # частый и самый дешёвый в исправлении случай.
            if name in ("Material", "Color", "Vector", "Angle"):
                out.append({"kind": "hot-alloc", "line": idx + 1,
                            "note": f"{name}( в {current[0]} — вынести в верхний уровень"})
    return out


def find_hook_dups(text: str) -> list[dict]:
    seen = defaultdict(list)
    for line_no, line in enumerate(text.splitlines(), 1):
        m = HOOK_RE.search(line)
        if m:
            seen[(m.group(1), m.group(2))].append(line_no)
    out = []
    for (hook_name, ident), lines_at in seen.items():
        if len(lines_at) > 1:
            out.append({"kind": "hook-dup", "line": lines_at[0],
                        "note": f"hook.Add(\"{hook_name}\", \"{ident}\") повторён на строках "
                                f"{', '.join(map(str, lines_at))} — последний затирает предыдущие"})
    return out


def block_hashes(rel: str, lines: list[str], window: int):
    """Скользящее окно нормализованных значащих строк → хэши."""
    sig = [(i, normalize(l)) for i, l in enumerate(lines) if significant(l)]
    for start in range(0, max(0, len(sig) - window + 1)):
        chunk = sig[start:start + window]
        body = "\n".join(c[1] for c in chunk)
        if len(body) < window * 12:
            continue
        digest = hashlib.blake2b(body.encode("utf-8"), digest_size=12).hexdigest()
        yield digest, rel, chunk[0][0] + 1, chunk[-1][0] + 1


def analyze(paths, args):
    per_file = {}
    dup_index = defaultdict(list)
    func_bodies = defaultdict(list)

    for path in paths:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                raw = fh.read()
        except OSError:
            continue
        text = strip_comments(raw)
        lines = text.splitlines()
        findings = []
        findings += find_cond_chains(lines, args.min)
        findings += find_long_funcs(lines, args.long)
        findings += find_deep_nesting(lines, args.nest)
        findings += find_dead_code(lines)
        findings += find_repeated_literals(text, args.lit)
        findings += find_hot_allocs(lines)
        findings += find_hook_dups(text)
        per_file[rel] = {"lines": len(raw.splitlines()), "findings": findings}

        for digest, r, start, end in block_hashes(rel, lines, args.window):
            dup_index[digest].append((r, start, end))

        # тела функций для поиска клонов
        stack = []
        for idx, line in enumerate(lines):
            m = FUNC_RE.match(line)
            if m:
                stack.append((idx, m.group(2) or m.group(4) or "<аноним>",
                              len(line) - len(line.lstrip())))
            elif re.match(r"^\s*end\b", line) and stack:
                start, name, indent = stack[-1]
                if (len(line) - len(line.lstrip())) == indent:
                    stack.pop()
                    body = [normalize(l) for l in lines[start + 1:idx] if significant(l)]
                    if len(body) >= args.window:
                        digest = hashlib.blake2b("\n".join(body).encode("utf-8"),
                                                 digest_size=12).hexdigest()
                        func_bodies[digest].append((rel, start + 1, name, len(body)))

    dups = []
    for digest, places in dup_index.items():
        uniq = []
        for rel, start, end in places:
            if not any(rel == u[0] and abs(start - u[1]) < args.window for u in uniq):
                uniq.append((rel, start, end))
        if len(uniq) >= 2:
            dups.append({"kind": "dup-block", "copies": len(uniq),
                         "places": [f"{r}:{s}-{e}" for r, s, e in uniq[:8]]})

    func_clones = []
    for digest, places in func_bodies.items():
        names = {p[2] for p in places}
        if len(places) >= 2 and len(names) >= 1:
            func_clones.append({"kind": "dup-func", "copies": len(places),
                                "size": places[0][3],
                                "places": [f"{r}:{ln} {name}" for r, ln, name, _s in places[:8]]})

    dups.sort(key=lambda d: -d["copies"])
    func_clones.sort(key=lambda d: (-d["copies"], -d["size"]))
    return per_file, dups, func_clones


def main() -> int:
    ap = argparse.ArgumentParser(description="детектор нейрослопа в Lua GRM")
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--file", help="проверить один файл")
    ap.add_argument("--dirs", default="lua,addons")
    ap.add_argument("--kind", help="фильтр по виду находки")
    ap.add_argument("--min", type=int, default=5, help="минимум веток для cond-chain")
    ap.add_argument("--long", type=int, default=150, help="порог длинной функции")
    ap.add_argument("--nest", type=int, default=6, help="порог вложенности")
    ap.add_argument("--lit", type=int, default=10, help="порог повторов литерала")
    ap.add_argument("--window", type=int, default=8, help="окно дубликатов, значащих строк")
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--json", help="выгрузить полный отчёт в файл")
    args = ap.parse_args()

    if args.file:
        paths = [os.path.join(args.root, args.file)]
    else:
        paths = []
        for d in args.dirs.split(","):
            root = os.path.join(args.root, d.strip())
            if os.path.isdir(root):
                paths += list(iter_lua(root))

    per_file, dups, clones = analyze(paths, args)

    totals = Counter()
    for rel, info in per_file.items():
        for f in info["findings"]:
            totals[f["kind"]] += 1
    totals["dup-block"] = len(dups)
    totals["dup-func"] = len(clones)

    print(f"── файлов: {len(per_file)}, строк: {sum(i['lines'] for i in per_file.values())}")
    print("── находки по видам:")
    for kind, count in totals.most_common():
        print(f"   {kind:<12} {count}")

    def weight(info):
        w = 0
        for f in info["findings"]:
            w += {"cond-chain": 5, "long-func": 3, "dup-func": 4, "dead": 2,
                  "deep-nest": 2, "repeat-lit": 1, "hot-alloc": 2, "hook-dup": 4}.get(f["kind"], 1)
        return w

    ranked = sorted(per_file.items(), key=lambda kvp: -weight(kvp[1]))
    print(f"\n── худшие файлы (вес = сумма находок):")
    for rel, info in ranked[:args.top]:
        if weight(info) == 0:
            break
        kinds = Counter(f["kind"] for f in info["findings"])
        summary = ", ".join(f"{k}×{v}" for k, v in kinds.most_common())
        print(f"   {weight(info):4d}  {rel:<58} {info['lines']:>6} стр.  {summary}")

    if args.kind:
        print(f"\n── находки вида {args.kind}:")
        shown = 0
        for rel, info in ranked:
            for f in info["findings"]:
                if f["kind"] == args.kind:
                    print(f"   {rel}:{f['line']}  {f['note']}")
                    shown += 1
                    if shown >= args.top * 4:
                        break
            if shown >= args.top * 4:
                break

    print(f"\n── копипаста: блоков {len(dups)}, функций-клонов {len(clones)}")
    for d in dups[:8]:
        print(f"   ×{d['copies']}  {'; '.join(d['places'][:4])}")
    for c in clones[:8]:
        print(f"   ×{c['copies']} ({c['size']} стр.)  {'; '.join(c['places'][:4])}")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump({"files": per_file, "dup_blocks": dups, "dup_funcs": clones,
                       "totals": dict(totals)}, fh, ensure_ascii=False, indent=1)
        print(f"\nполный отчёт: {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
