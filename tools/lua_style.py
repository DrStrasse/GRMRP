#!/usr/bin/env python3
"""Единый стиль исходников Lua в lua/.

ЗАЧЕМ. Код сборки писался годами и разными руками: часть файлов на табах,
часть на четырёх пробелах, местами хвостовые пробелы и отсутствие финального
перевода строки. Diff'ы из-за этого шумят, а поиск по коду («найди строку с
таким отступом») даёт разные результаты в разных файлах.

ЧТО ДЕЛАЕТ. Приводит наши файлы к одному виду:
  * отступ — 4 пробела, табов в начале строки нет;
  * нет хвостовых пробелов;
  * файл заканчивается ровно одним переводом строки;
  * перевод строки — LF, без BOM.

ЧТО НЕ ТРОГАЕТ. Сторонний код (см. VENDORED). EasyChat и подобное живёт по
своим правилам, переформатирование чужого файла ломает сверку с апстримом.
Табы ВНУТРИ строки (например, выравнивание в литерале) тоже не трогаем —
меняем только отступ, чтобы не портить содержимое строковых констант.

ПОЧЕМУ ЗДЕСЬ ЛЕКСЕР. Внутри длинного литерала [[...]] пробелы значимы: это
данные, а не оформление. Сорвать там хвостовой пробел или заменить таб —
значит молча изменить текст, который увидит игрок (подсказки, ASCII-рамки,
шаблоны писем). Поэтому строки внутри [[...]] помечаются и пропускаются.
Длинные КОММЕНТАРИИ --[[...]] пропускаются только по отступу: хвостовые
пробелы в них чистить безопасно, они всё равно не попадают в игру.

Запуск:
    python3 tools/lua_style.py --check   # только отчёт, код возврата 1 при находках
    python3 tools/lua_style.py --fix     # исправить на месте
"""
import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Основной модуль + отдельные аддоны (grm_addon_studio, grm_textscreens…).
SCAN_DIRS = ("lua", "addons")

# Сторонние библиотеки: форматируются апстримом, у нас — как есть.
# Паковые файлы пожарного аддона владелец просил парсером не чинить.
VENDORED = (
    "lua/easychat/",
    "lua/autorun/easychat_init.lua",
    "addons/grm_fire/lua/weapons/weapon_extinguisher.lua",
    "addons/grm_fire/lua/weapons/weapon_firehose.lua",
    "addons/grm_textscreens/",
)

INDENT = "    "


def is_vendored(rel: str) -> bool:
    rel = rel.replace(os.sep, "/")
    return any(rel == v or rel.startswith(v) for v in VENDORED)


def iter_files():
    for scan in SCAN_DIRS:
        for base, _dirs, names in os.walk(os.path.join(ROOT, scan)):
            for name in sorted(names):
                if not name.endswith(".lua"):
                    continue
                path = os.path.join(base, name)
                rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                if is_vendored(rel):
                    continue
                yield rel, path


def expand_indent(line: str) -> str:
    """Табы в ОТСТУПЕ -> 4 пробела. Остальная часть строки не трогается."""
    i = 0
    while i < len(line) and line[i] in " \t":
        i += 1
    head, tail = line[:i], line[i:]
    if "\t" not in head:
        return line
    # Ширина таба = 4, с выравниванием по сетке: так вложенность сохраняется
    # и при смешанных «пробел+таб» отступах.
    width = 0
    for ch in head:
        if ch == "\t":
            width += 4 - (width % 4)
        else:
            width += 1
    return " " * width + tail


def classify_lines(text: str):
    """Для каждой строки: (внутри_длинного_литерала, внутри_длинного_комментария).

    Простейший проход по символам, которого достаточно для наших файлов:
    отслеживаем короткие строки '..'/".."; длинные скобки [[ / [=[ и парные
    закрывающие; однострочные комментарии. Открывающая и закрывающая строки
    длинной скобки считаются «граничными» — их отступ править можно, а вот
    строки ВНУТРИ трогать нельзя.
    """
    lines = text.split("\n")
    in_literal = [False] * len(lines)
    in_comment = [False] * len(lines)

    long_level = None      # длина '=' в открытой длинной скобке, иначе None
    long_is_comment = False
    for idx, line in enumerate(lines):
        if long_level is not None:
            # Строка целиком внутри длинной скобки, пока не встретим закрытие.
            closing = "]" + "=" * long_level + "]"
            pos = line.find(closing)
            if pos < 0:
                in_literal[idx] = not long_is_comment
                in_comment[idx] = long_is_comment
                continue
            # Строка с закрывающей скобкой: остаток разбираем обычным образом.
            in_literal[idx] = not long_is_comment
            in_comment[idx] = long_is_comment
            rest_at = pos + len(closing)
            long_level, long_is_comment = None, False
        else:
            rest_at = 0

        i, n = rest_at, len(line)
        quote = None
        while i < n:
            ch = line[i]
            if quote:
                if ch == "\\":
                    i += 2
                    continue
                if ch == quote:
                    quote = None
                i += 1
                continue
            if ch in "'\"":
                quote = ch
                i += 1
                continue
            if line.startswith("--", i):
                # Комментарий: либо длинный --[[, либо до конца строки.
                j = i + 2
                if j < n and line[j] == "[":
                    k = j + 1
                    while k < n and line[k] == "=":
                        k += 1
                    if k < n and line[k] == "[":
                        long_level, long_is_comment = k - j - 1, True
                        i = k + 1
                        continue
                break
            if ch == "[":
                k = i + 1
                while k < n and line[k] == "=":
                    k += 1
                if k < n and line[k] == "[":
                    long_level, long_is_comment = k - i - 1, False
                    i = k + 1
                    continue
            i += 1
    return in_literal, in_comment


def normalize(text: str) -> str:
    if text.startswith("\ufeff"):
        text = text[1:]
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    raw = text.split("\n")
    in_literal, _in_comment = classify_lines(text)

    out_lines = []
    for idx, line in enumerate(raw):
        if in_literal[idx]:
            out_lines.append(line)      # данные — как есть
        else:
            out_lines.append(expand_indent(line).rstrip())
    out = "\n".join(out_lines).rstrip("\n")
    return out + "\n" if out else ""


def describe(rel: str, before: str, after: str):
    """Причины правки считаем по РЕАЛЬНОЙ разнице before/after.

    Так в отчёт не попадают находки внутри длинных литералов, которые мы
    сознательно не трогаем: сообщать о том, что не исправляем, — вводить в
    заблуждение.
    """
    reasons = []
    if before.startswith("\ufeff"):
        reasons.append("BOM")
    if "\r" in before:
        reasons.append("CRLF")

    body_before = before.replace("\ufeff", "").replace("\r\n", "\n").replace("\r", "\n")
    src = body_before.split("\n")
    dst = after.split("\n")
    tabs = trail = False
    for i, line in enumerate(src):
        fixed = dst[i] if i < len(dst) else None
        if fixed is None or fixed == line:
            continue
        head = line[: len(line) - len(line.lstrip(" \t"))]
        if "\t" in head:
            tabs = True
        if line != line.rstrip():
            trail = True
    if tabs:
        reasons.append("таб в отступе")
    if trail:
        reasons.append("хвостовые пробелы")
    if body_before and not body_before.endswith("\n"):
        reasons.append("нет финального перевода строки")
    elif body_before.endswith("\n\n"):
        reasons.append("лишние пустые строки в конце")
    return "%s: %s" % (rel, ", ".join(reasons) or "различие форматирования")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="только отчёт")
    mode.add_argument("--fix", action="store_true", help="исправить на месте")
    args = ap.parse_args()

    dirty = []
    for rel, path in iter_files():
        with open(path, "r", encoding="utf-8", errors="strict") as fh:
            before = fh.read()
        after = normalize(before)
        if before == after:
            continue
        dirty.append(describe(rel, before, after))
        if args.fix:
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(after)

    if not dirty:
        print("стиль: все файлы в порядке")
        return 0

    verb = "исправлено" if args.fix else "требуют правки"
    print("стиль: %s файлов %s" % (len(dirty), verb))
    for line in dirty:
        print("  " + line)
    return 0 if args.fix else 1


if __name__ == "__main__":
    sys.exit(main())
