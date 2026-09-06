#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Бандл-синхронизатор grm_chat (v3, вечер-14).

Источник истины — аддон-библиотека `lua/grm_chat/` (EasyChat-style:
лоадер `lua/autorun/grm_chat.lua` + папка модулей). Для соло-установки
gamemode-зипа режим держит ВСТРОЕННУЮ КОПИЮ тех же файлов в
`gamemodes/grmrp/gamemode/lib/grm_chat/`. Копия механическая, побайтовая;
расхождение ловит `--check` (режим гейта: красные ворота).

Прежняя генерация портов `lua/autorun/*_08_grm_chat*` с namespace-конвертацией
выведена: `GRMChat` — алиас того же стола (см. sh_core), дублирующего кода
больше нет. История решений — OWNER_REPORTS.md / WIKI 7.2.
"""
import io
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "lua", "grm_chat")
DST = os.path.join(ROOT, "gamemodes", "grmrp", "gamemode", "lib", "grm_chat")
FILES = ["sh_core.lua", "sv_net.lua", "cl_hud.lua", "cl_input.lua"]


def read(p):
    with io.open(p, encoding="utf-8") as fh:
        return fh.read()


def tree(base):
    """Все .lua бандла относительными путями (веч.-21: модули в подпапках)."""
    out = []
    for root, _dirs, names in os.walk(base):
        for fn in names:
            if fn.endswith(".lua"):
                out.append(os.path.relpath(os.path.join(root, fn), base))
    return sorted(out)


FILES = tree(SRC)


def check():
    bad = []
    for name in FILES:
        s, d = os.path.join(SRC, name), os.path.join(DST, name)
        if not os.path.exists(s):
            bad.append("нет источника: " + name)
            continue
        if not os.path.exists(d) or read(s) != read(d):
            bad.append("бандл расходится с библиотекой: " + name)
    for name in tree(DST):
        if name not in FILES:
            bad.append("мёртвый файл в бандле: " + name)
    if bad:
        for b in bad:
            print("sync_chat_addon: " + b)
        return 1
    print("чат-библиотека и бандл режима идентичны (" + str(len(FILES))
          + " файлов)")
    return 0


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--check":
        sys.exit(check())
    for name in tree(SRC):
        d = os.path.join(DST, name)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copyfile(os.path.join(SRC, name), d)
        print("обновлён бандл: gamemodes/grmrp/gamemode/lib/grm_chat/" + name)
    sys.exit(check())


if __name__ == "__main__":
    main()
