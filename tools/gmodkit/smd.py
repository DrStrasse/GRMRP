"""SMD — текстовый исходник модели/анимации Source.

Структура файла:

    version 1
    nodes
    0 "root" -1
    end
    skeleton
    time 0
    0  0 0 0  0 0 0
    end
    triangles
    material.vmt
    0  x y z  nx ny nz  u v  [links...]
    ...
    end

Модуль умеет: разобрать, посчитать статистику, переименовать кости и
материалы, масштабировать/сдвинуть, вырезать анимацию в отдельный SMD,
собрать обратно (round-trip) и выгрузить меш в .obj — чтобы можно было
глянуть геометрию любым просмотрщиком, не запуская Source.
"""

from __future__ import annotations

import io
import math
import os
from typing import Dict, Iterable, List, Optional, Tuple


class Node:
    __slots__ = ("index", "name", "parent")

    def __init__(self, index: int, name: str, parent: int):
        self.index, self.name, self.parent = index, name, parent


class BoneFrame:
    __slots__ = ("bone", "pos", "rot")

    def __init__(self, bone: int, pos: Tuple[float, float, float], rot: Tuple[float, float, float]):
        self.bone, self.pos, self.rot = bone, pos, rot


class Vertex:
    __slots__ = ("parent", "pos", "normal", "uv", "links")

    def __init__(self, parent, pos, normal, uv, links=None):
        self.parent, self.pos, self.normal, self.uv = parent, pos, normal, uv
        self.links: List[Tuple[int, float]] = list(links or [])


class Triangle:
    __slots__ = ("material", "verts")

    def __init__(self, material: str, verts: List[Vertex]):
        self.material, self.verts = material, verts


class SMD:
    def __init__(self, path: str = "<memory>"):
        self.path = path
        self.version = 1
        self.nodes: List[Node] = []
        self.frames: Dict[int, List[BoneFrame]] = {}
        self.triangles: List[Triangle] = []
        self.warnings: List[str] = []

    # ── разбор ────────────────────────────────────────────────────────
    @classmethod
    def parse(cls, text: str, path: str = "<memory>") -> "SMD":
        smd = cls(path)
        section = None
        time = 0
        pending_material: Optional[str] = None
        tri_verts: List[Vertex] = []

        for lineno, raw in enumerate(text.splitlines(), 1):
            line = raw.split("//")[0].split(";")[0].strip()
            if not line:
                continue
            low = line.lower()
            if low.startswith("version"):
                parts = line.split()
                smd.version = int(parts[1]) if len(parts) > 1 else 1
                continue
            if low in ("nodes", "skeleton", "triangles", "vertexanimation"):
                section = low
                continue
            if low == "end":
                section = None
                pending_material, tri_verts = None, []
                continue

            if section == "nodes":
                try:
                    idx_str, rest = line.split(None, 1)
                    name = rest[rest.index('"') + 1:rest.rindex('"')] if '"' in rest else rest.split()[0]
                    parent = int(rest.rsplit(None, 1)[-1])
                    smd.nodes.append(Node(int(idx_str), name, parent))
                except Exception:  # noqa: BLE001
                    smd.warnings.append(f"строка {lineno}: не разобран узел: {line}")
            elif section == "skeleton":
                if low.startswith("time"):
                    try:
                        time = int(line.split()[1])
                    except Exception:  # noqa: BLE001
                        smd.warnings.append(f"строка {lineno}: битый time")
                    smd.frames.setdefault(time, [])
                    continue
                parts = line.split()
                if len(parts) >= 7:
                    try:
                        vals = [float(p) for p in parts[1:7]]
                        smd.frames.setdefault(time, []).append(
                            BoneFrame(int(parts[0]), tuple(vals[0:3]), tuple(vals[3:6])))
                    except ValueError:
                        smd.warnings.append(f"строка {lineno}: битый кадр кости")
            elif section == "triangles":
                if pending_material is None:
                    pending_material = line
                    tri_verts = []
                    continue
                parts = line.split()
                if len(parts) < 9:
                    smd.warnings.append(f"строка {lineno}: короткая вершина")
                    continue
                try:
                    parent = int(parts[0])
                    nums = [float(p) for p in parts[1:9]]
                    links: List[Tuple[int, float]] = []
                    if len(parts) > 9:
                        count = int(parts[9])
                        for i in range(count):
                            bone = int(parts[10 + i * 2])
                            weight = float(parts[11 + i * 2])
                            links.append((bone, weight))
                    tri_verts.append(Vertex(parent, tuple(nums[0:3]), tuple(nums[3:6]),
                                            (nums[6], nums[7]), links))
                except (ValueError, IndexError):
                    smd.warnings.append(f"строка {lineno}: битая вершина")
                    continue
                if len(tri_verts) == 3:
                    smd.triangles.append(Triangle(pending_material, tri_verts))
                    pending_material, tri_verts = None, []
        return smd

    @classmethod
    def open(cls, path: str) -> "SMD":
        with io.open(path, "r", encoding="utf-8", errors="replace") as fh:
            return cls.parse(fh.read(), path)

    # ── сборка ────────────────────────────────────────────────────────
    def dumps(self) -> str:
        out = [f"version {self.version}\n", "nodes\n"]
        for node in self.nodes:
            out.append(f'{node.index} "{node.name}" {node.parent}\n')
        out.append("end\n")

        out.append("skeleton\n")
        for time in sorted(self.frames):
            out.append(f"time {time}\n")
            for bf in self.frames[time]:
                out.append("  %d  %f %f %f  %f %f %f\n" % (
                    bf.bone, bf.pos[0], bf.pos[1], bf.pos[2],
                    bf.rot[0], bf.rot[1], bf.rot[2]))
        out.append("end\n")

        if self.triangles:
            out.append("triangles\n")
            for tri in self.triangles:
                out.append(f"{tri.material}\n")
                for v in tri.verts:
                    line = "  %d  %f %f %f  %f %f %f  %f %f" % (
                        v.parent, v.pos[0], v.pos[1], v.pos[2],
                        v.normal[0], v.normal[1], v.normal[2], v.uv[0], v.uv[1])
                    if v.links:
                        line += "  %d" % len(v.links)
                        for bone, weight in v.links:
                            line += " %d %f" % (bone, weight)
                    out.append(line + "\n")
            out.append("end\n")
        return "".join(out)

    def save(self, path: Optional[str] = None) -> str:
        target = path or self.path
        with io.open(target, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(self.dumps())
        return target

    # ── правки ────────────────────────────────────────────────────────
    def scale(self, factor: float) -> None:
        """Масштаб модели и всех кадров скелета (частая беда чужих моделей)."""
        for frames in self.frames.values():
            for bf in frames:
                bf.pos = (bf.pos[0] * factor, bf.pos[1] * factor, bf.pos[2] * factor)
        for tri in self.triangles:
            for v in tri.verts:
                v.pos = (v.pos[0] * factor, v.pos[1] * factor, v.pos[2] * factor)

    def translate(self, delta: Tuple[float, float, float]) -> None:
        """Сдвиг геометрии и корневых костей (bone 0 и все без родителя)."""
        roots = {n.index for n in self.nodes if n.parent < 0} or {0}
        for frames in self.frames.values():
            for bf in frames:
                if bf.bone in roots:
                    bf.pos = (bf.pos[0] + delta[0], bf.pos[1] + delta[1], bf.pos[2] + delta[2])
        for tri in self.triangles:
            for v in tri.verts:
                v.pos = (v.pos[0] + delta[0], v.pos[1] + delta[1], v.pos[2] + delta[2])

    def rename_material(self, old: str, new: str) -> int:
        n = 0
        low = old.lower()
        for tri in self.triangles:
            if tri.material.lower() == low:
                tri.material = new
                n += 1
        return n

    def rename_bone(self, old: str, new: str) -> int:
        n = 0
        low = old.lower()
        for node in self.nodes:
            if node.name.lower() == low:
                node.name = new
                n += 1
        return n

    def prefix_bones(self, prefix: str) -> int:
        for node in self.nodes:
            node.name = prefix + node.name
        return len(self.nodes)

    def keep_frames(self, first: int, last: int) -> int:
        """Оставить диапазон кадров (нарезка анимации)."""
        kept = {t: f for t, f in self.frames.items() if first <= t <= last}
        base = min(kept) if kept else 0
        self.frames = {t - base: f for t, f in kept.items()}
        return len(self.frames)

    def strip_geometry(self) -> None:
        """Превратить в чистый SMD-анимацию (без треугольников)."""
        self.triangles = []

    # ── экспорт ───────────────────────────────────────────────────────
    def to_obj(self) -> str:
        """Wavefront .obj — быстрый способ посмотреть меш чем угодно."""
        out = [f"# из {os.path.basename(self.path)} (gmodkit)\n"]
        index: Dict[Tuple[float, float, float], int] = {}
        verts: List[Tuple[float, float, float]] = []
        faces: Dict[str, List[Tuple[int, int, int]]] = {}
        for tri in self.triangles:
            ids = []
            for v in tri.verts:
                key = v.pos
                if key not in index:
                    verts.append(key)
                    index[key] = len(verts)
                ids.append(index[key])
            faces.setdefault(tri.material, []).append(tuple(ids))
        for v in verts:
            out.append("v %f %f %f\n" % v)
        for material, tris in faces.items():
            out.append(f"g {os.path.splitext(material)[0]}\n")
            for a, b, c in tris:
                out.append(f"f {a} {b} {c}\n")
        return "".join(out)

    # ── сводка ────────────────────────────────────────────────────────
    def materials(self) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        for tri in self.triangles:
            counts[tri.material] = counts.get(tri.material, 0) + 1
        return counts

    def bounds(self) -> Tuple[Tuple[float, float, float], Tuple[float, float, float]]:
        if not self.triangles:
            return ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0))
        xs, ys, zs = [], [], []
        for tri in self.triangles:
            for v in tri.verts:
                xs.append(v.pos[0]); ys.append(v.pos[1]); zs.append(v.pos[2])
        return ((min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs)))

    def weight_problems(self, tolerance: float = 0.01) -> List[str]:
        """Вершины, у которых сумма весов не равна 1 — типичная причина
        «модель рвётся при анимации»."""
        bad = []
        for ti, tri in enumerate(self.triangles):
            for vi, v in enumerate(tri.verts):
                if not v.links:
                    continue
                total = sum(w for _b, w in v.links)
                if abs(total - 1.0) > tolerance:
                    bad.append(f"треугольник {ti} вершина {vi}: сумма весов {total:.3f}")
        return bad

    def summary(self) -> dict:
        mins, maxs = self.bounds()
        return {
            "path": self.path,
            "version": self.version,
            "nodes": len(self.nodes),
            "root_bones": sum(1 for n in self.nodes if n.parent < 0),
            "frames": len(self.frames),
            "frame_range": [min(self.frames), max(self.frames)] if self.frames else [],
            "triangles": len(self.triangles),
            "materials": self.materials(),
            "bounds_min": [round(v, 3) for v in mins],
            "bounds_max": [round(v, 3) for v in maxs],
            "size": [round(maxs[i] - mins[i], 3) for i in range(3)],
            "weight_problems": len(self.weight_problems()),
            "warnings": self.warnings,
            "type": "анимация" if not self.triangles else "меш",
        }


def make_qc(model_path: str, reference: str, materials: Iterable[str],
            surfaceprop: str = "metal", mass: float = 10.0,
            staticprop: bool = True, idle_smd: Optional[str] = None,
            scale: float = 1.0) -> str:
    """Скелет .qc для компиляции — заготовка, а не догма.

    Пишем ровно те строки, без которых studiomdl ругается: $modelname,
    $body, $cdmaterials, $surfaceprop, $sequence idle. Коллизию оставляем
    комментарием — её всегда правят руками под конкретную модель.
    """
    cds = "\n".join(f'$cdmaterials "{c.strip("/")}/"' for c in materials) or '$cdmaterials "models/"'
    lines = [
        f'$modelname "{model_path}"',
        f'$body "studio" "{reference}"',
        cds,
        f'$surfaceprop "{surfaceprop}"',
    ]
    if scale != 1.0:
        lines.append(f"$scale {scale:g}")
    if staticprop:
        lines.append("$staticprop")
    lines.append(f'$sequence "idle" "{idle_smd or reference}" fps 1')
    lines.append("")
    lines.append("// Коллизия: раскомментировать и подправить под модель")
    lines.append(f'// $collisionmodel "{reference}" {{ $mass {mass:g} $concave }}')
    lines.append("")
    return "\n".join(lines)


def cube(size: float = 16.0, material: str = "debug/debugempty") -> SMD:
    """Тестовый куб — фикстура для самопроверки и шаблон нового меша."""
    smd = SMD("<cube>")
    smd.nodes.append(Node(0, "static_prop", -1))
    smd.frames[0] = [BoneFrame(0, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))]
    h = size / 2.0
    corners = [(x, y, z) for x in (-h, h) for y in (-h, h) for z in (-h, h)]
    faces = [
        (0, 1, 3, 2, (-1, 0, 0)), (4, 6, 7, 5, (1, 0, 0)),
        (0, 4, 5, 1, (0, -1, 0)), (2, 3, 7, 6, (0, 1, 0)),
        (0, 2, 6, 4, (0, 0, -1)), (1, 5, 7, 3, (0, 0, 1)),
    ]
    for a, b, c, d, normal in faces:
        for tri in ((a, b, c), (a, c, d)):
            verts = []
            for i, corner in enumerate(tri):
                pos = corners[corner]
                uv = ((math.cos(i) + 1) / 2, (math.sin(i) + 1) / 2)
                verts.append(Vertex(0, pos, normal, uv, [(0, 1.0)]))
            smd.triangles.append(Triangle(material, verts))
    return smd
