"""Valve KeyValues: разбор и запись (VMF, VMT, entity-лампа BSP, GameInfo).

Формат один и тот же везде:

    classname
    {
        "key" "value"
        subblock
        {
            "key" "value"
        }
    }

Особенности, которые тут учтены (иначе VMF ломается):

* ключи повторяются (несколько `solid`, несколько `side`, `connections`
  с одинаковым `OnTrigger`) — поэтому хранилище это СПИСОК пар, а не dict;
* строки бывают и в кавычках, и без (BSP-энтити почти всегда в кавычках);
* комментарии `// ...` вне кавычек;
* экранирование внутри кавычек в VMF Valve НЕ применяет, поэтому кавычка
  внутри значения просто закрывает строку — так же ведёт себя движок.

Node — узел дерева: имя, свои пары ключ-значение, дочерние узлы.
"""

from __future__ import annotations

import io
from typing import Iterable, Iterator, List, Optional, Tuple


class KVError(ValueError):
    """Синтаксическая ошибка KeyValues с указанием строки."""


class Node:
    """Узел KeyValues: `name { pairs... children... }`."""

    __slots__ = ("name", "pairs", "children")

    def __init__(self, name: str = "", pairs=None, children=None):
        self.name: str = name
        self.pairs: List[Tuple[str, str]] = list(pairs or [])
        self.children: List["Node"] = list(children or [])

    # ── доступ к значениям ────────────────────────────────────────────
    def get(self, key: str, default: Optional[str] = None) -> Optional[str]:
        """Первое значение ключа (регистр не важен — как в движке)."""
        low = key.lower()
        for k, v in self.pairs:
            if k.lower() == low:
                return v
        return default

    def get_all(self, key: str) -> List[str]:
        low = key.lower()
        return [v for k, v in self.pairs if k.lower() == low]

    def set(self, key: str, value: str) -> None:
        """Заменить первое вхождение ключа либо дописать в конец."""
        low = key.lower()
        for i, (k, _) in enumerate(self.pairs):
            if k.lower() == low:
                self.pairs[i] = (k, str(value))
                return
        self.pairs.append((key, str(value)))

    def add(self, key: str, value: str) -> None:
        self.pairs.append((key, str(value)))

    def remove(self, key: str) -> int:
        low = key.lower()
        before = len(self.pairs)
        self.pairs = [(k, v) for k, v in self.pairs if k.lower() != low]
        return before - len(self.pairs)

    # ── доступ к детям ────────────────────────────────────────────────
    def find(self, name: str) -> List["Node"]:
        low = name.lower()
        return [c for c in self.children if c.name.lower() == low]

    def first(self, name: str) -> Optional["Node"]:
        got = self.find(name)
        return got[0] if got else None

    def walk(self) -> Iterator["Node"]:
        """Обход поддерева, включая сам узел."""
        yield self
        for c in self.children:
            yield from c.walk()

    # ── сериализация ──────────────────────────────────────────────────
    def dump(self, indent: int = 0, tab: str = "\t") -> str:
        pad = tab * indent
        out = [f"{pad}{self.name}\n{pad}{{\n"]
        inner = tab * (indent + 1)
        for k, v in self.pairs:
            out.append(f'{inner}"{k}" "{v}"\n')
        for c in self.children:
            out.append(c.dump(indent + 1, tab))
        out.append(f"{pad}}}\n")
        return "".join(out)

    def __repr__(self) -> str:  # pragma: no cover - отладочное
        return f"<Node {self.name!r} pairs={len(self.pairs)} children={len(self.children)}>"


# ─────────────────────────────── лексер ──────────────────────────────
_WS = " \t\r\n\f\v"


def _tokens(text: str) -> Iterator[Tuple[str, str, int]]:
    """Поток токенов: ('str'|'{'|'}', значение, номер строки)."""
    i, line, n = 0, 1, len(text)
    while i < n:
        c = text[i]
        if c in _WS:
            if c == "\n":
                line += 1
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c in "{}":
            yield (c, c, line)
            i += 1
            continue
        if c == '"':
            i += 1
            start = i
            while i < n and text[i] != '"':
                if text[i] == "\n":
                    line += 1
                i += 1
            if i >= n:
                raise KVError(f"строка {line}: незакрытая кавычка")
            yield ("str", text[start:i], line)
            i += 1
            continue
        start = i
        while i < n and text[i] not in _WS and text[i] not in '{}"':
            i += 1
        yield ("str", text[start:i], line)


def parse(text: str) -> List[Node]:
    """Разобрать текст KeyValues в список корневых узлов."""
    roots: List[Node] = []
    stack: List[Node] = []
    pending: Optional[str] = None
    pending_line = 0

    for kind, val, line in _tokens(text):
        if kind == "{":
            if pending is None:
                raise KVError(f"строка {line}: '{{' без имени блока")
            node = Node(pending)
            pending = None
            if stack:
                stack[-1].children.append(node)
            else:
                roots.append(node)
            stack.append(node)
        elif kind == "}":
            if pending is not None:
                raise KVError(f"строка {pending_line}: ключ '{pending}' без значения")
            if not stack:
                raise KVError(f"строка {line}: лишняя '}}'")
            stack.pop()
        else:  # строка
            if pending is None:
                pending, pending_line = val, line
            else:
                if not stack:
                    # пара на верхнем уровне (например, VMT-подобный файл)
                    roots.append(Node("", [(pending, val)]))
                else:
                    stack[-1].pairs.append((pending, val))
                pending = None

    if stack:
        raise KVError("файл кончился, а блок не закрыт")
    if pending is not None:
        raise KVError(f"строка {pending_line}: ключ '{pending}' без значения")
    return roots


def parse_file(path: str, encoding: str = "utf-8") -> List[Node]:
    with io.open(path, "r", encoding=encoding, errors="replace") as fh:
        return parse(fh.read())


def dump(nodes: Iterable[Node], tab: str = "\t") -> str:
    return "".join(n.dump(0, tab) for n in nodes)


def parse_entity_lump(text: str) -> List[Node]:
    """Разбор энтити-лампы BSP (тот же KeyValues, но блоки без имени).

        {
        "classname" "worldspawn"
        }

    Возвращает узлы с именем 'entity' — чтобы форма совпала с VMF.
    """
    text = text.split("\x00", 1)[0]
    out: List[Node] = []
    cur: Optional[Node] = None
    pending: Optional[str] = None
    for kind, val, line in _tokens(text):
        if kind == "{":
            cur = Node("entity")
        elif kind == "}":
            if cur is not None:
                out.append(cur)
            cur = None
        else:
            if cur is None:
                continue  # мусор между блоками игнорируем
            if pending is None:
                pending = val
            else:
                cur.pairs.append((pending, val))
                pending = None
    return out


def entity_lump_text(entities: Iterable[Node]) -> str:
    """Обратная сборка энтити-лампы (с завершающим нулём, как в движке)."""
    buf = []
    for ent in entities:
        buf.append("{\n")
        for k, v in ent.pairs:
            buf.append(f'"{k}" "{v}"\n')
        buf.append("}\n")
    buf.append("\x00")
    return "".join(buf)


def vec(value: Optional[str], default=(0.0, 0.0, 0.0)) -> Tuple[float, float, float]:
    """'128 -64 8.5' → (128.0, -64.0, 8.5). Терпит скобки и запятые."""
    if not value:
        return default
    cleaned = value.replace("[", " ").replace("]", " ").replace(",", " ")
    parts = cleaned.split()
    try:
        nums = [float(p) for p in parts[:3]]
    except ValueError:
        return default
    while len(nums) < 3:
        nums.append(0.0)
    return (nums[0], nums[1], nums[2])
