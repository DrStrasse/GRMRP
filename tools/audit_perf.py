#!/usr/bin/env python3
"""
tools/audit_perf.py — аудит нагрузки и порядка выполнения GRM.

Ищет в lua-файлах:
  1) покадровые хуки (Think, Tick, HUDPaint, PostDraw*, RenderScene, Move,
     SetupMove, CreateMove, PreDrawOpaqueRenderables) и внутри них —
     дорогие вызовы (ents.FindByClass/FindInSphere, player.GetAll,
     util.TraceLine/TraceHull, GetEyeTrace, Material, file.Read/Write,
     util.JSONToTable, table.Copy, string.find в цикле);
  2) частые таймеры (timer.Create с интервалом < 1 c);
  3) старты подсистем (InitPostEntity / Initialize / timer.Simple на старте),
     которые ещё не переведены на GRM.Boot;
  4) ent:Think без NextThink-троттлинга;
  5) синхронная запись на диск в горячем пути (net.Receive, чат-команды,
     покадровые хуки, частые таймеры) — микрофриз на каждое действие;
  6) большие синхронизации одним пакетом (net.WriteTable + net.Broadcast)
     вместо порционного GRM.Net.Stream;
  7) тяжёлый вход игрока (PlayerInitialSpawn с чтением файлов и полными
     снимками) — фриз в момент присоединения;
  8) незарегистрированные сетевые каналы: таблица имён Net заполнена, а
     util.AddNetworkString зовётся не на все — «unpooled message name».

Вывод: таблица «файл — тип — деталь», сгруппированная по тяжести.
Использование: python3 tools/audit_perf.py [--json]
"""
import os, re, sys, json, math
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIRS = ["lua", "addons"]
SKIP_PARTS = ("/easychat/", "/luatest/", "/.luabuild/")

FRAME_HOOKS = ("Think", "Tick", "HUDPaint", "HUDPaintBackground", "PostDrawTranslucentRenderables",
               "PostDrawOpaqueRenderables", "PreDrawOpaqueRenderables", "RenderScene",
               "SetupMove", "CreateMove", "Move", "DrawOverlay", "PostRender", "PreRender")

HEAVY = {
    "ents.FindByClass": 4, "ents.FindInSphere": 4, "ents.FindInBox": 4, "ents.GetAll": 5,
    "player.GetAll": 3, "util.TraceLine": 3, "util.TraceHull": 3, "GetEyeTrace": 3,
    "file.Read": 5, "file.Write": 5, "file.Find": 5, "util.JSONToTable": 4, "util.TableToJSON": 4,
    "Material(": 2, "surface.GetTextSize": 1, "table.Copy": 2, "net.Start": 2,
    "SetNWString": 1, "SetNWInt": 1, "SetNWFloat": 1, "SetNWBool": 1,
}

# перф-слой GRM: эти обёртки уже кэшируют, их не считаем нарушением
SAFE_PREFIX = ("GRM.Perf.", "GRM.Boot.")


def strip_comments(src: str) -> str:
    """Вырезает комментарии, СОХРАНЯЯ переносы строк — иначе номера строк
    в отчёте уезжают и указывают не на тот код."""
    def keep_newlines(m):
        return "\n" * m.group(0).count("\n")
    src = re.sub(r"--\[\[.*?\]\]", keep_newlines, src, flags=re.S)
    src = re.sub(r"--[^\n]*", "", src)
    return src


def block_of(src: str, start: int) -> str:
    """Грубое выделение тела функции от позиции start до баланса end."""
    depth = 0
    i = start
    n = len(src)
    began = False
    while i < n:
        m = re.compile(r"\b(function|if|for|while|do|end)\b").search(src, i)
        if not m:
            break
        word = m.group(1)
        if word in ("function", "if", "for", "while", "do"):
            depth += 1
            began = True
        elif word == "end":
            depth -= 1
        i = m.end()
        if began and depth <= 0:
            return src[start:i]
    return src[start:start + 4000]


CLOSE_RE = re.compile(r"\n[ \t]*end\)")


def cut_body(body: str) -> str:
    """Обрезает тело хука/таймера по его закрывающей строке.

    Раньше резали по literal "\nend)" — в реальном коде закрывающая строка
    почти всегда с отступом, поэтому обрезка НЕ срабатывала и в тело
    попадал соседний код: аудит показывал file.Write там, где его нет.
    """
    m = CLOSE_RE.search(body)
    return body[:m.start()] if m else body


def scan_file(path: str):
    rel = os.path.relpath(path, ROOT)
    try:
        raw = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    src = strip_comments(raw)
    findings = []

    # 1) покадровые хуки
    for m in re.finditer(r'hook\.Add\(\s*"([A-Za-z_]+)"\s*,\s*"([^"]*)"', src):
        hook_name, hook_id = m.group(1), m.group(2)
        if hook_name not in FRAME_HOOKS:
            continue
        body = cut_body(block_of(src, m.end()))
        score = 0
        hits = []
        # Построчно: строка, где уже используется перф-слой GRM (кэш сущностей,
        # игроков, change-only NW), нарушением не считается — там ents.FindByClass
        # стоит лишь как фолбэк.
        # Склеиваем перенос логического «or» с предыдущей строкой: фолбэк
        # вида «GRM.Perf.Entities(c)\n or ents.FindByClass(c)» — не нарушение.
        merged, lines = [], body.split("\n")
        for line in lines:
            if merged and line.lstrip().startswith(("or ", "and ")):
                merged[-1] = merged[-1] + " " + line.strip()
            else:
                merged.append(line)
        # Тяжёлый вызов ПОСЛЕ раннего выхода («if dt < порог then return end»)
        # выполняется не каждый кадр, а по редкому событию — вес делим.
        passed_guard = False
        for line in merged:
            if any(p in line for p in SAFE_PREFIX):
                continue
            stripped = line.strip()
            if ("then return" in stripped or stripped == "return"
                    or stripped.startswith("return ") and " end" in stripped):
                passed_guard = True
            for call, weight in HEAVY.items():
                cnt = line.count(call)
                if cnt:
                    score += (weight * cnt) / (3 if passed_guard else 1)
                    hits.append(call)
        score = math.floor(score)
        # Хук с собственным троттлингом (ранний выход по CurTime) считается
        # вдвое легче: тяжёлая работа выполняется не каждый кадр.
        head = body[:260]
        throttled = ("CurTime()" in head and "return" in head) or ("RealTime()" in head and "return" in head)
        if throttled:
            score = math.floor(score / 2)
        if score >= 3:
            findings.append({
                "file": rel, "kind": "frame_hook", "score": score,
                "detail": ("[троттлинг есть] " if throttled else "") +
                    f"{hook_name} / {hook_id}: " + ", ".join(sorted(set(hits))),
            })

    # 2) частые таймеры
    for m in re.finditer(r'timer\.Create\(\s*[^,]+,\s*([0-9.]+)', src):
        try:
            period = float(m.group(1))
        except ValueError:
            continue
        if period < 1.0:
            line = src[:m.start()].count("\n") + 1
            # Фолбэк-ветка «если GRM.Boot нет — крутим таймер» не выполняется
            # на живом сервере: Boot есть всегда. Такие места не считаем.
            window = src[max(0, m.start() - 400):m.start()]
            # Фолбэк-ветка «если перф-слоя нет — крутим таймер» на живом
            # сервере не выполняется: и Boot, и Coalesce есть всегда.
            if "GRM.Boot" in window or "GRM.Perf.Coalesce" in window:
                continue
            body = cut_body(block_of(src, m.end()))
            head = body[:400]
            guarded = ("== nil then return" in head or "next(" in head and "return" in head
                       or "#" in head and "== 0 then return" in head)
            score = int(6 / max(period, 0.05))
            if guarded:
                score = int(score / 3)
            findings.append({
                "file": rel, "kind": "fast_timer", "score": score,
                "detail": (("[есть ранний выход] " if guarded else "") +
                           f"строка {line}: интервал {period} c"),
            })

    # 3) старты не через Boot
    boot_used = "GRM.Boot" in src
    for m in re.finditer(r'hook\.Add\(\s*"(InitPostEntity|Initialize|PostGamemodeLoaded)"\s*,\s*"([^"]*)"', src):
        if boot_used:
            continue
        findings.append({
            "file": rel, "kind": "eager_start", "score": 3,
            "detail": f"{m.group(1)} / {m.group(2)} — не переведён на GRM.Boot",
        })

    # 4) ENT:Think без троттлинга
    for m in re.finditer(r'function\s+ENT:Think\s*\(', src):
        # block_of на минифицированном коде обрывается раньше времени —
        # смотрим фиксированное окно после объявления.
        body = src[m.end():m.end() + 4000]
        if "NextThink" not in body and "CurTime()" not in body:
            findings.append({
                "file": rel, "kind": "ent_think", "score": 4,
                "detail": "ENT:Think без SetNextThink/троттлинга по CurTime",
            })

    return findings


HOTPATH_PATTERNS = (
    (r'net\.Receive\(\s*[^,]+,', "net.Receive"),
    (r'hook\.Add\(\s*"PlayerSay(?:Transform)?"\s*,', "чат-команда"),
    (r'hook\.Add\(\s*"PlayerUse"\s*,', "PlayerUse"),
    (r'hook\.Add\(\s*"KeyPress"\s*,', "KeyPress"),
    (r'hook\.Add\(\s*"PlayerDeath"\s*,', "PlayerDeath"),
)


def scan_extra(rel: str, src: str):
    """Проверки 5-7: диск и сеть в горячем пути."""
    findings = []
    uses_save_queue = "GRM.Save" in src

    # 5) синхронная запись на диск в горячем пути
    for pattern, label in HOTPATH_PATTERNS:
        for m in re.finditer(pattern, src):
            body = cut_body(block_of(src, m.end()))
            if "file.Write" not in body:
                continue
            if uses_save_queue and "GRM.Save" in body:
                continue
            line = src[:m.start()].count("\n") + 1
            findings.append({
                "file": rel, "kind": "disk_hotpath", "score": 6,
                "detail": f"строка {line}: file.Write внутри {label} — писать через GRM.Save.Mark",
            })

    # 5b) запись на диск в частом таймере
    for m in re.finditer(r'timer\.Create\(\s*[^,]+,\s*([0-9.]+)', src):
        try:
            period = float(m.group(1))
        except ValueError:
            continue
        if period >= 30:
            continue
        body = cut_body(block_of(src, m.end()))
        if "file.Write" not in body:
            continue
        if "GRM.Save" in body:
            continue
        line = src[:m.start()].count("\n") + 1
        findings.append({
            "file": rel, "kind": "disk_hotpath", "score": 5,
            "detail": f"строка {line}: file.Write в таймере {period} c",
        })

    # 6) крупная синхронизация одним пакетом
    #    Обычный «открыли меню — прислали данные» не считаем: это разовый
    #    пакет одному игроку. Ловим ШИРОКОВЕЩАТЕЛЬНЫЕ снимки (их получают все
    #    и одновременно) и пакеты, склеенные из трёх и более таблиц.
    for m in re.finditer(r'net\.Start\(', src):
        window = src[m.end():m.end() + 1200]
        stop = window.find("net.Start(")
        if stop > 0:
            window = window[:stop]
        tables = window.count("net.WriteTable")
        if tables == 0:
            continue
        broadcast = "net.Broadcast()" in window
        if not broadcast and tables < 3:
            continue
        if "GRM.Net.Stream" in src[max(0, m.start() - 300):m.end()]:
            continue
        line = src[:m.start()].count("\n") + 1
        findings.append({
            "file": rel, "kind": "big_sync",
            "score": 5 if broadcast else 3,
            "detail": (f"строка {line}: net.WriteTable×{tables} + net.Broadcast — слать через GRM.Net.Stream"
                       if broadcast else
                       f"строка {line}: {tables} таблицы в одном пакете — разбить или слать через GRM.Net.Stream"),
        })

    # 8) сетевые каналы: объявили имя — зарегистрируй строку
    for m in re.finditer(r'([A-Za-z_][\w.]*\.Net)\s*=\s*\{(.*?)\}', src, re.S):
        table_name, body = m.group(1), m.group(2)
        fields = re.findall(r'(\w+)\s*=\s*"', body)
        if len(fields) < 2:
            continue
        loop = re.search(r'for\s+_?,?\s*\w+\s+in\s+pairs\(\s*' + re.escape(table_name) +
                         r'\s*\)\s*do\s*util\.AddNetworkString', src)
        if loop:
            continue
        registered = len(re.findall(r'util\.AddNetworkString\(', src))
        if registered < len(fields):
            line = src[:m.start()].count("\n") + 1
            findings.append({
                "file": rel, "kind": "net_unpooled", "score": 6,
                "detail": (f"строка {line}: в {table_name} каналов {len(fields)}, "
                           f"а util.AddNetworkString вызван {registered} раз — часть имён не в пуле"),
            })

    # 7) тяжёлый вход игрока
    for m in re.finditer(r'hook\.Add\(\s*"PlayerInitialSpawn"\s*,\s*"([^"]*)"', src):
        body = cut_body(block_of(src, m.end()))
        weight, hits = 0, []
        for call in ("file.Read", "file.Write", "util.JSONToTable", "util.TableToJSON",
                     "net.WriteTable", "ents.FindByClass", "ents.GetAll"):
            cnt = body.count(call)
            if cnt:
                weight += 3 * cnt
                hits.append(call)
        # timer.Simple внутри — работа уже отложена, это уже мягче
        if "timer.Simple" in body:
            weight = math.floor(weight / 2)
        if weight >= 3:
            findings.append({
                "file": rel, "kind": "join_heavy", "score": weight,
                "detail": f"PlayerInitialSpawn / {m.group(1)}: " + ", ".join(sorted(set(hits))),
            })

    return findings


def main():
    all_findings = []
    for d in SCAN_DIRS:
        base = os.path.join(ROOT, d)
        for dirpath, _dirs, files in os.walk(base):
            for fn in files:
                if not fn.endswith(".lua"):
                    continue
                full = os.path.join(dirpath, fn)
                rel = "/" + os.path.relpath(full, ROOT).replace(os.sep, "/")
                if any(p in rel for p in SKIP_PARTS):
                    continue
                all_findings.extend(scan_file(full))
                try:
                    raw = open(full, encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                all_findings.extend(scan_extra(os.path.relpath(full, ROOT), strip_comments(raw)))

    if "--json" in sys.argv:
        print(json.dumps(all_findings, ensure_ascii=False, indent=1))
        return

    by_kind = defaultdict(list)
    for f in all_findings:
        by_kind[f["kind"]].append(f)

    titles = {
        "frame_hook": "ПОКАДРОВЫЕ ХУКИ С ТЯЖЁЛЫМИ ВЫЗОВАМИ",
        "fast_timer": "ТАЙМЕРЫ ЧАЩЕ РАЗА В СЕКУНДУ",
        "eager_start": "СТАРТЫ ПОДСИСТЕМ МИМО GRM.Boot",
        "ent_think": "ENT:Think БЕЗ ТРОТТЛИНГА",
        "disk_hotpath": "ЗАПИСЬ НА ДИСК В ГОРЯЧЕМ ПУТИ",
        "big_sync": "КРУПНЫЕ СИНХРОНИЗАЦИИ ОДНИМ ПАКЕТОМ",
        "join_heavy": "ТЯЖЁЛЫЙ ВХОД ИГРОКА",
        "net_unpooled": "СЕТЕВЫЕ КАНАЛЫ БЕЗ РЕГИСТРАЦИИ ИМЕНИ",
    }
    for kind in ("frame_hook", "fast_timer", "disk_hotpath", "net_unpooled", "big_sync",
                 "join_heavy", "ent_think", "eager_start"):
        rows = sorted(by_kind.get(kind, []), key=lambda r: -r["score"])
        print("\n=== %s (%d) ===" % (titles[kind], len(rows)))
        for r in rows[:40]:
            print("  %3d  %-62s %s" % (r["score"], r["file"], r["detail"]))
        if len(rows) > 40:
            print("  … ещё %d" % (len(rows) - 40))

    print("\nВсего находок: %d" % len(all_findings))

    # Ворота качества: то, что НЕ должно появляться в новом коде вообще.
    # Запуск: python3 tools/audit_perf.py --gate  (ненулевой код возврата)
    if "--gate" in sys.argv:
        blocking = []
        for f in all_findings:
            if f["kind"] in ("disk_hotpath", "eager_start", "ent_think", "net_unpooled"):
                blocking.append(f)
            elif f["kind"] == "frame_hook" and f["score"] >= 8:
                blocking.append(f)
            elif f["kind"] == "fast_timer" and f["score"] >= 40:
                blocking.append(f)
        if blocking:
            print("\n!!! ВОРОТА НЕ ПРОЙДЕНЫ: %d критичных находок" % len(blocking))
            for f in blocking:
                print("   %-62s %s" % (f["file"], f["detail"]))
            sys.exit(1)
        print("\nВорота пройдены: запись на диск в горячем пути, старты мимо Boot,")
        print("нетроттленные Think и покадровые тяжеловесы отсутствуют.")


if __name__ == "__main__":
    main()
