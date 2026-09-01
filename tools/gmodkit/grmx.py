"""Мост между форматами Source и данными GRM.

Здесь всё, ради чего инструментарий вообще заводился: превратить карту
или модель в то, что понимает аддон, и проверить, что аддон не ссылается
на несуществующий контент.

Экспорт:
    spawn_points_global_<map>.json    — массив {pos={x,y,z}, ang={p,y,r}}
                                        (формат sh_spawn_points.lua)
    spawn_points_factions_<map>.json  — {фракция = {points, roles,
                                        departments, subdepartments,
                                        positions}} — единый формат,
                                        находка 157
    grm_perm_entities.json            — МАССИВ записей
                                        {map, class, model, pos, ang}
                                        (Код 50; массив, а не карта —
                                        урок находки 65 про числовые ключи)

Аудит:
    check_content — какие models/*.mdl и materials/*.vmt упоминает Lua-код
                    и чего из этого нет в репозитории;
    check_models  — у каждой модели репозитория есть ли .vvd/.vtx и все ли
                    её материалы на месте (иначе модель фиолетовая).
"""

from __future__ import annotations

import json
import os
import re
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

from . import kv
from .bsp import BSP
from .mdl import MDL, scan_models
from .vmf import VMF

# Классы, которые в Source означают «тут появляется игрок».
SPAWN_CLASSES = (
    "info_player_start", "info_player_terrorist", "info_player_counterterrorist",
    "info_player_rebel", "info_player_combine", "info_player_deathmatch",
    "info_player_teamspawn", "gmod_player_start", "info_player_allies",
    "info_player_axis",
)

# Точка + угол — общий вид записи GRM.
def _point(origin: Sequence[float], angles: Sequence[float]) -> dict:
    return {
        "pos": {"x": round(float(origin[0]), 3),
                "y": round(float(origin[1]), 3),
                "z": round(float(origin[2]), 3)},
        "ang": {"p": round(float(angles[0]), 3),
                "y": round(float(angles[1]), 3),
                "r": round(float(angles[2]), 3)},
    }


def _entities_from(path: str, classes: Iterable[str]) -> Tuple[str, List[kv.Node]]:
    """Достать энтити нужных классов из .bsp или .vmf (единый вход)."""
    wanted = tuple(c.lower() for c in classes)
    ext = os.path.splitext(path)[1].lower()
    if ext == ".bsp":
        src = BSP.open(path)
        name = src.name
        pool = src.entities
    elif ext == ".vmf":
        src = VMF.open(path)
        name = os.path.splitext(os.path.basename(path))[0]
        pool = src.entities
    else:
        raise ValueError(f"нужен .bsp или .vmf, получено: {path}")
    out = []
    for ent in pool:
        cls = (ent.get("classname") or "").lower()
        if any(cls == w or (w.endswith("*") and cls.startswith(w[:-1])) for w in wanted):
            out.append(ent)
    return name, out


def _origin_angles(ent: kv.Node, z_offset: float = 0.0) -> Tuple[Tuple[float, float, float], Tuple[float, float, float]]:
    origin = kv.vec(ent.get("origin"))
    angles = kv.vec(ent.get("angles"))
    return (origin[0], origin[1], origin[2] + z_offset), angles


# ── точки спавна ──────────────────────────────────────────────────────
def export_global_spawns(map_path: str, classes: Iterable[str] = SPAWN_CLASSES,
                         z_offset: float = 0.0) -> Tuple[str, List[dict]]:
    """Все спавн-точки карты в формате GlobalSpawnPoints."""
    name, ents = _entities_from(map_path, classes)
    points = []
    for ent in ents:
        origin, angles = _origin_angles(ent, z_offset)
        points.append(_point(origin, angles))
    return name, points


def export_faction_spawns(map_path: str, mapping: Dict[str, str],
                          z_offset: float = 0.0) -> Tuple[str, Dict[str, dict]]:
    """Точки фракций по правилу «targetname энтити → фракция».

    mapping: {'spawn_police': 'Полиция', 'spawn_army*': 'Армия'} — ключ
    сравнивается с targetname (поддерживается '*' в конце).
    """
    name, ents = _entities_from(map_path, ("info_player_*", "gmod_player_start", "info_target"))
    data: Dict[str, dict] = {}
    for ent in ents:
        target = (ent.get("targetname") or "").lower()
        if not target:
            continue
        faction = None
        for pattern, fname in mapping.items():
            pat = pattern.lower()
            if (target.startswith(pat[:-1]) if pat.endswith("*") else target == pat):
                faction = fname
                break
        if faction is None:
            continue
        origin, angles = _origin_angles(ent, z_offset)
        bundle = data.setdefault(faction, {"points": [], "roles": {},
                                           "departments": {}, "subdepartments": {},
                                           "positions": {}})
        bundle["points"].append(_point(origin, angles))
    return name, data


def spawn_files(map_name: str) -> Dict[str, str]:
    return {
        "global": f"spawn_points_global_{map_name}.json",
        "factions": f"spawn_points_factions_{map_name}.json",
    }


# ── пермы энтити (Код 50) ─────────────────────────────────────────────
def export_perm_entities(map_path: str, class_map: Dict[str, str],
                         z_offset: float = 0.0,
                         default_model: str = "") -> Tuple[str, List[dict]]:
    """Собрать data/grm_perm_entities.json из расставленных в карте меток.

    class_map: {'grm_atm_marker': 'grm_bank_terminal', ...} — какой
    targetname/classname карты превращается в какой класс GRM.
    Записи пишутся МАССИВОМ (Код 50), поле map заполняется именем карты.
    """
    name, ents = _entities_from(map_path, list(class_map.keys()) + ["info_target", "prop_static", "prop_dynamic"])
    out: List[dict] = []
    for ent in ents:
        cls = (ent.get("classname") or "").lower()
        target = (ent.get("targetname") or "").lower()
        grm_class = None
        for pattern, mapped in class_map.items():
            pat = pattern.lower()
            for candidate in (cls, target):
                if not candidate:
                    continue
                if (candidate.startswith(pat[:-1]) if pat.endswith("*") else candidate == pat):
                    grm_class = mapped
                    break
            if grm_class:
                break
        if grm_class is None:
            continue
        origin, angles = _origin_angles(ent, z_offset)
        rec = _point(origin, angles)
        rec_out = {
            "map": name,
            "class": grm_class,
            "model": ent.get("model") or default_model,
            "pos": rec["pos"],
            "ang": rec["ang"],
        }
        out.append(rec_out)
    return name, out


def dedupe_perms(records: List[dict], radius: float = 6.0) -> List[dict]:
    """Убрать дубли класс+точка (тот же радиус 6 юнитов, что в Коде 50)."""
    kept: List[dict] = []
    for rec in records:
        clash = False
        for other in kept:
            if other["class"] != rec["class"] or other.get("map") != rec.get("map"):
                continue
            dx = other["pos"]["x"] - rec["pos"]["x"]
            dy = other["pos"]["y"] - rec["pos"]["y"]
            dz = other["pos"]["z"] - rec["pos"]["z"]
            if dx * dx + dy * dy + dz * dz <= radius * radius:
                clash = True
                break
        if not clash:
            kept.append(rec)
    return kept


def write_json(path: str, payload) -> str:
    """Запись с read-back — то же правило, что в Lua-персистентности."""
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    with open(path, "r", encoding="utf-8") as fh:
        if fh.read() != text:
            raise IOError(f"read-back не совпал: {path}")
    return path


# ── аудит контента ────────────────────────────────────────────────────
MODEL_RE = re.compile(r"[\"']((?:models/)[^\"'\n]+?\.mdl)[\"']", re.IGNORECASE)
MATERIAL_RE = re.compile(r"Material\s*\(\s*[\"']([^\"'\n]+)[\"']", re.IGNORECASE)


def _plausible(path: str) -> bool:
    """Отсеять то, что регулярка выдрала из склейки строк.

    В Lua полно `Material("materials/" .. name)` и заглушек вида
    `models/.../model.mdl` в комментариях — такие «пути» не файлы, и
    таскать их в отчёт значит утопить настоящие пропажи в шуме.
    """
    if not path or ".." in path or " " in path or path.endswith("/"):
        return False
    return not any(ch in path for ch in "()%,\t")


def _iter_lua(root: str) -> Iterable[str]:
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in (".git", "dist", ".luabuild")]
        for fname in files:
            if fname.lower().endswith(".lua"):
                yield os.path.join(base, fname)


def check_content(repo_root: str, lua_dirs: Sequence[str] = ("lua", "addons")) -> dict:
    """Модели и материалы, которые упоминает Lua, против того, что в репо.

    Отсутствие файла не всегда ошибка (модель может приходить с игры или
    из воркшопа), поэтому итог делится на «есть локально» и «внешние» —
    решение принимает человек, инструмент только показывает.
    """
    models_used: Dict[str, List[str]] = {}
    materials_used: Dict[str, List[str]] = {}
    for lua_dir in lua_dirs:
        root = os.path.join(repo_root, lua_dir)
        if not os.path.isdir(root):
            continue
        for path in _iter_lua(root):
            rel = os.path.relpath(path, repo_root)
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
            except OSError:
                continue
            for match in MODEL_RE.finditer(text):
                model = match.group(1).lower().replace("\\", "/")
                if _plausible(model):
                    models_used.setdefault(model, []).append(rel)
            for match in MATERIAL_RE.finditer(text):
                mat = match.group(1).lower().replace("\\", "/")
                if _plausible(mat) and not mat.startswith("http"):
                    materials_used.setdefault(mat, []).append(rel)

    def local(rel_path: str) -> bool:
        return os.path.isfile(os.path.join(repo_root, rel_path))

    models_local, models_external = [], []
    for mdl_path in sorted(models_used):
        (models_local if local(mdl_path) else models_external).append(mdl_path)

    mats_local, mats_external = [], []
    for mat in sorted(materials_used):
        candidates = [mat]
        if not mat.startswith("materials/"):
            candidates.append("materials/" + mat)
        stem = candidates[-1]
        found = any(local(c) or local(os.path.splitext(c)[0] + ext)
                    for c in candidates for ext in (".vmt", ".vtf", ".png", ".jpg", ""))
        (mats_local if found else mats_external).append(stem)

    return {
        "models_referenced": len(models_used),
        "models_in_repo": models_local,
        "models_external": models_external,
        "materials_referenced": len(materials_used),
        "materials_in_repo": mats_local,
        "materials_external": mats_external,
        "usage_models": models_used,
        "usage_materials": materials_used,
    }


def check_models(repo_root: str, models_dir: str = "models") -> dict:
    """Полнота каждой модели репозитория: спутники и материалы."""
    root = os.path.join(repo_root, models_dir)
    report = {"checked": 0, "problems": [], "models": []}
    if not os.path.isdir(root):
        report["problems"].append(f"нет каталога {models_dir}/")
        return report

    for path in scan_models(root):
        rel = os.path.relpath(path, repo_root).replace("\\", "/")
        entry = {"model": rel, "issues": []}
        try:
            m = MDL.open(path)
        except Exception as exc:  # noqa: BLE001
            entry["issues"].append(f"не читается: {exc}")
            report["models"].append(entry)
            report["problems"].append(f"{rel}: {exc}")
            report["checked"] += 1
            continue

        entry["version"] = m.version
        entry["bones"] = m.bone_count
        entry["static_prop"] = m.is_static_prop
        if m.sibling(".vvd") is None:
            entry["issues"].append("нет .vvd")
        if m.sibling(".vtx") is None:
            entry["issues"].append("нет .vtx (модель не отрисуется)")

        variants = m.material_paths()
        by_texture: Dict[str, List[str]] = {}
        for tex in m.texture_names():
            by_texture[tex] = [p for p in variants if p.lower().endswith("/" + tex.lower().replace("\\", "/") + ".vmt")]
        missing = []
        for tex, paths in by_texture.items():
            if not any(os.path.isfile(os.path.join(repo_root, p)) for p in paths):
                missing.append(tex)
        if missing:
            entry["issues"].append("нет .vmt: " + ", ".join(sorted(missing)))
        entry["materials_expected"] = variants
        report["models"].append(entry)
        report["checked"] += 1
        if entry["issues"]:
            report["problems"].append(f"{rel}: " + "; ".join(entry["issues"]))
    return report


def map_content_report(map_path: str, repo_root: Optional[str] = None) -> dict:
    """Что карте нужно от контента: модели пропов, материалы, встроенный pak."""
    src = BSP.open(map_path)
    props = src.prop_model_counts()
    ent_models: Dict[str, int] = {}
    for ent in src.entities:
        model = (ent.get("model") or "").lower().replace("\\", "/")
        if model.endswith(".mdl"):
            ent_models[model] = ent_models.get(model, 0) + 1

    packed = set()
    for name, _size, _csize in src.pak_list():
        packed.add(name.lower().replace("\\", "/"))

    needed = sorted(set(list(props) + list(ent_models)))
    missing_local = []
    if repo_root:
        for model in needed:
            rel = model if model.startswith("models/") else "models/" + model
            if rel.lower() in packed:
                continue
            if not os.path.isfile(os.path.join(repo_root, rel)):
                missing_local.append(rel)

    return {
        "map": src.name,
        "static_prop_models": props,
        "entity_models": ent_models,
        "models_total": len(needed),
        "packed_files": len(packed),
        "packed_models": sorted(p for p in packed if p.endswith(".mdl")),
        "not_packed_not_in_repo": missing_local,
        "materials": len(src.materials),
        "warnings": src.warnings,
    }
