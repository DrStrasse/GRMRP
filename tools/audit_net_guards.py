#!/usr/bin/env python3
"""Сплошной разбор серверных точек входа GRM.

ЗАЧЕМ. Клиент может прислать в net-сообщение что угодно и когда угодно.
Каждый серверный net.Receive — это дверь, и у неё должен быть замок:
проверка прав, владельца, дистанции или хотя бы лимита частоты.

Ручным чтением 357 обработчиков это не проверить, а забыть проверку в
новом модуле легко. Скрипт находит двери без замка.

ВАЖНО ПРО ЛОЖНЫЕ СРАБАТЫВАНИЯ. Проверка часто живёт во вспомогательной
функции (inRange, rateOK, canManage), а не прямо в теле обработчика.
Поэтому скрипт ищет ШИРОКИЙ набор признаков и всё равно ошибается в
сторону «подозрительно». Его вывод — это СПИСОК ДЛЯ ЧТЕНИЯ ГЛАЗАМИ,
а не приговор: при аудите 31.08 из 158 находок реальными оказались 3.

Запуск:
    python3 tools/audit_net_guards.py            # сводка
    python3 tools/audit_net_guards.py --all      # весь список
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIRS = ("lua", "addons")
SKIP = ("easychat",)

# Признаки любой валидации: права, владелец, дистанция, лимит частоты.
AUTH = re.compile(
    r"IsSuperAdmin|IsAdmin\s*\(|IsUserGroup|Access\.Can|Guard\s*\("
    r"|\bcan[A-Z]\w*\s*\(|\.Can[A-Z]\w*\s*\("
    r"|inRange\s*\(|rateOK\s*\(|DistToSqr|Distance\s*\("
    r"|hasAdminAccess|IsListenServerHost"
    r"|GetOwner\s*\(\)|OwnerKey|CharacterKey\s*\(\s*ply|charKey\s*\(\s*ply"
    r"|lastGive|NextUse|_next|Cooldown|cooldown|CurTime\(\)\s*<"
)

# Что обработчик делает с данными — по этому расставляем приоритет.
RISK = {
    "деньги": re.compile(r"GiveMoney|AddMoney|SetMoney|BudgetAdd|TakeMoney"),
    "спавн": re.compile(r"ents\.Create"),
    "запись": re.compile(r"file\.Write|SaveDefinitions|SaveCfg|SaveAll"),
    "энтити": re.compile(r"net\.ReadEntity"),
    "таблица": re.compile(r"net\.ReadTable"),
}


def iter_files():
    for base in SCAN_DIRS:
        root = os.path.join(ROOT, base)
        if not os.path.isdir(root):
            continue
        for dirpath, _dirs, names in os.walk(root):
            if any(s in dirpath for s in SKIP):
                continue
            for name in sorted(names):
                if name.endswith(".lua"):
                    yield os.path.relpath(os.path.join(dirpath, name), ROOT)


def handlers(src):
    """Серверные net.Receive: у них вторым аргументом идёт игрок."""
    for m in re.finditer(r"net\.Receive\(\s*([^,]+?),\s*function\s*\(([^)]*)\)", src):
        args = [a.strip() for a in m.group(2).split(",") if a.strip()]
        if len(args) < 2:
            continue                      # клиентский приёмник — не дверь
        start = m.end()
        nxt = src.find("net.Receive", start)
        body = src[start: nxt if nxt > 0 else min(len(src), start + 4000)]
        yield m.group(1).strip(), body


def main():
    show_all = "--all" in sys.argv
    total, naked = 0, []
    for rel in iter_files():
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        for msg, body in handlers(src):
            total += 1
            if AUTH.search(body):
                continue
            tags = [k for k, rx in RISK.items() if rx.search(body)]
            naked.append((rel, msg, tags))

    print("серверных обработчиков: %d" % total)
    print("без явных признаков валидации: %d" % len(naked))
    print()

    # Сначала то, что трогает деньги, спавнит или пишет на диск.
    hot = [r for r in naked if {"деньги", "спавн", "запись"} & set(r[2])]
    print("--- ТРЕБУЮТ ЧТЕНИЯ В ПЕРВУЮ ОЧЕРЕДЬ (%d) ---" % len(hot))
    for rel, msg, tags in hot:
        print("  [%-18s] %-34s %s" % (",".join(tags), msg[:34], rel))

    if show_all:
        print()
        print("--- ОСТАЛЬНЫЕ (%d) ---" % (len(naked) - len(hot)))
        for rel, msg, tags in naked:
            if {"деньги", "спавн", "запись"} & set(tags):
                continue
            print("  [%-18s] %-34s %s" % (",".join(tags), msg[:34], rel))

    print()
    print("Напоминание: список — повод прочитать код, а не готовый диагноз.")
    print("Проверка нередко живёт во вспомогательной функции.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
