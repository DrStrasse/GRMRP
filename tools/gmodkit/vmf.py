"""VMF — исходник карты Hammer поверх kv.

VMF это KeyValues: корневые блоки versioninfo/visgroups/world/entity/cameras.
Браши (`solid`) лежат внутри `world` и внутри брашевых энтити.

Модуль даёт:
* чтение/запись без потери структуры (round-trip);
* перечисление энтити и брашей, материалов, моделей;
* добавление/удаление точечных энтити (расстановка спавнов, банкоматов,
  таксофонов GRM прямо в исходник карты);
* сдвиг/поворот выбранных энтити;
* конвертацию энтити-лампы BSP в VMF (декомпиляция «точек», без геометрии) —
  чтобы посмотреть в Hammer, где что стоит на готовой карте.
"""

from __future__ import annotations

import io
import math
import os
from typing import Dict, Iterable, List, Optional, Tuple

from . import kv
from .bsp import BSP


class VMF:
    def __init__(self, roots: Optional[List[kv.Node]] = None, path: str = "<memory>"):
        self.path = path
        self.roots: List[kv.Node] = roots if roots is not None else _blank_roots()

    # ── ввод/вывод ────────────────────────────────────────────────────
    @classmethod
    def open(cls, path: str) -> "VMF":
        return cls(kv.parse_file(path), path)

    @classmethod
    def parse(cls, text: str, path: str = "<memory>") -> "VMF":
        return cls(kv.parse(text), path)

    def dumps(self) -> str:
        return kv.dump(self.roots)

    def save(self, path: Optional[str] = None) -> str:
        target = path or self.path
        with io.open(target, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(self.dumps())
        return target

    # ── структура ─────────────────────────────────────────────────────
    @property
    def world(self) -> kv.Node:
        node = next((n for n in self.roots if n.name == "world"), None)
        if node is None:
            node = kv.Node("world", [("id", str(self.next_id())), ("classname", "worldspawn")])
            self.roots.append(node)
        return node

    @property
    def entities(self) -> List[kv.Node]:
        return [n for n in self.roots if n.name == "entity"]

    def entities_by_class(self, pattern: str) -> List[kv.Node]:
        low = pattern.lower()
        star = low.endswith("*")
        stem = low[:-1] if star else low
        out = []
        for ent in self.entities:
            cls = (ent.get("classname") or "").lower()
            if (cls.startswith(stem) if star else cls == stem):
                out.append(ent)
        return out

    def solids(self) -> List[kv.Node]:
        out = list(self.world.find("solid"))
        for ent in self.entities:
            out.extend(ent.find("solid"))
        return out

    def sides(self) -> List[kv.Node]:
        return [s for solid in self.solids() for s in solid.find("side")]

    def materials(self) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        for side in self.sides():
            mat = (side.get("material") or "").upper()
            if mat:
                counts[mat] = counts.get(mat, 0) + 1
        return counts

    def models(self) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        for ent in self.entities:
            mdl = ent.get("model")
            if mdl and mdl.lower().endswith(".mdl"):
                key = mdl.lower().replace("\\", "/")
                counts[key] = counts.get(key, 0) + 1
        return counts

    def entity_class_counts(self) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        for ent in self.entities:
            cls = ent.get("classname") or "<без classname>"
            counts[cls] = counts.get(cls, 0) + 1
        return counts

    # ── идентификаторы ────────────────────────────────────────────────
    def next_id(self) -> int:
        top = 0
        for root in self.roots:
            for node in root.walk():
                try:
                    top = max(top, int(node.get("id") or 0))
                except ValueError:
                    pass
        return top + 1

    # ── правки ────────────────────────────────────────────────────────
    def add_point_entity(self, classname: str, origin: Tuple[float, float, float],
                         angles: Tuple[float, float, float] = (0.0, 0.0, 0.0),
                         **keys) -> kv.Node:
        """Добавить точечную энтити (spawn, банкомат, таксофон…)."""
        ent = kv.Node("entity", [
            ("id", str(self.next_id())),
            ("classname", classname),
            ("angles", "%g %g %g" % angles),
            ("origin", "%g %g %g" % origin),
        ])
        for k, v in keys.items():
            ent.add(k, str(v))
        ent.children.append(kv.Node("editor", [
            ("color", "220 30 220"),
            ("visgroupshown", "1"),
            ("visgroupautoshown", "1"),
            ("logicalpos", "[0 0]"),
        ]))
        self.roots.append(ent)
        return ent

    def remove_entities(self, pattern: str) -> int:
        victims = set(id(e) for e in self.entities_by_class(pattern))
        before = len(self.roots)
        self.roots = [n for n in self.roots if id(n) not in victims]
        return before - len(self.roots)

    def translate_entities(self, pattern: str, delta: Tuple[float, float, float]) -> int:
        n = 0
        for ent in self.entities_by_class(pattern):
            x, y, z = kv.vec(ent.get("origin"))
            ent.set("origin", "%g %g %g" % (x + delta[0], y + delta[1], z + delta[2]))
            n += 1
        return n

    def rotate_entities_yaw(self, pattern: str, degrees: float,
                            pivot: Tuple[float, float, float] = (0.0, 0.0, 0.0)) -> int:
        """Повернуть выбранные энтити вокруг оси Z (yaw), включая их angles."""
        rad = math.radians(degrees)
        cos_a, sin_a = math.cos(rad), math.sin(rad)
        n = 0
        for ent in self.entities_by_class(pattern):
            x, y, z = kv.vec(ent.get("origin"))
            dx, dy = x - pivot[0], y - pivot[1]
            ent.set("origin", "%g %g %g" % (
                pivot[0] + dx * cos_a - dy * sin_a,
                pivot[1] + dx * sin_a + dy * cos_a,
                z,
            ))
            p, yaw, r = kv.vec(ent.get("angles"))
            ent.set("angles", "%g %g %g" % (p, (yaw + degrees) % 360.0, r))
            n += 1
        return n

    # ── сводка ────────────────────────────────────────────────────────
    def summary(self) -> dict:
        vi = next((n for n in self.roots if n.name == "versioninfo"), None)
        solids = self.solids()
        return {
            "path": self.path,
            "map": os.path.splitext(os.path.basename(self.path))[0],
            "editor_version": vi.get("editorversion") if vi else None,
            "map_version": vi.get("mapversion") if vi else None,
            "entities": len(self.entities),
            "entity_classes": len(self.entity_class_counts()),
            "world_solids": len(self.world.find("solid")),
            "solids_total": len(solids),
            "sides": len(self.sides()),
            "displacements": sum(1 for s in self.sides() if s.first("dispinfo")),
            "materials": len(self.materials()),
            "models": len(self.models()),
            "visgroups": len(next((n for n in self.roots if n.name == "visgroups"), kv.Node()).children),
        }


def _blank_roots() -> List[kv.Node]:
    return [
        kv.Node("versioninfo", [
            ("editorversion", "400"), ("editorbuild", "8600"),
            ("mapversion", "1"), ("formatversion", "100"), ("prefab", "0"),
        ]),
        kv.Node("visgroups"),
        kv.Node("viewsettings", [
            ("bSnapToGrid", "1"), ("bShowGrid", "1"),
            ("bShowLogicalGrid", "0"), ("nGridSpacing", "64"),
            ("bShow3DGrid", "0"),
        ]),
        kv.Node("world", [
            ("id", "1"), ("mapversion", "1"), ("classname", "worldspawn"),
            ("skyname", "sky_day01_01"),
        ]),
    ]


def new() -> VMF:
    """Пустой VMF (только служебные блоки и worldspawn)."""
    return VMF()


def from_bsp_entities(bsp_path: str, classes: Optional[Iterable[str]] = None,
                      include_props: bool = False) -> VMF:
    """Собрать VMF из энтити-лампы карты .bsp.

    Геометрия мира не восстанавливается (это дело декомпилятора), но все
    точечные энтити попадают в файл — можно открыть в Hammer, посмотреть
    расстановку, подвинуть спавны и выгрузить обратно в JSON GRM.
    `include_props=True` добавит static props как prop_static.
    """
    src = BSP.open(bsp_path)
    out = new()
    out.path = os.path.splitext(bsp_path)[0] + "_entities.vmf"
    wanted = None
    if classes:
        wanted = set(c.lower() for c in classes)

    ws = src.worldspawn
    if ws is not None:
        world = out.world
        for k, v in ws.pairs:
            if k.lower() not in ("classname", "id", "mapversion"):
                world.set(k, v)

    for ent in src.entities:
        cls = (ent.get("classname") or "").lower()
        if cls in ("worldspawn", ""):
            continue
        if wanted is not None and cls not in wanted:
            continue
        node = kv.Node("entity", [("id", str(out.next_id()))])
        for k, v in ent.pairs:
            if k.lower() == "id":
                continue
            node.add(k, v)
        node.children.append(kv.Node("editor", [
            ("color", "220 30 220"), ("visgroupshown", "1"),
            ("visgroupautoshown", "1"), ("logicalpos", "[0 0]"),
        ]))
        out.roots.append(node)

    if include_props:
        for prop in src.static_props:
            out.add_point_entity(
                "prop_static", tuple(prop.origin), tuple(prop.angles),
                model=prop.model, skin=prop.skin, solid=prop.solid,
                fademindist=prop.fade_min, fademaxdist=prop.fade_max,
                uniformscale=prop.scale,
            )
    return out
