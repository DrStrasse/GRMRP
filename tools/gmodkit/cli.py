"""CLI инструментария: python3 tools/gmodkit.py <группа> <команда> ...

Группы: bsp, vmf, mdl, smd, grm, selftest.
Везде есть --json — машинный вывод для дальнейшей обработки.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import List, Optional

from . import __version__, grmx, kv
from .bsp import BSP, write_entity_lump
from .mdl import MDL, scan_models
from .smd import SMD, cube, make_qc
from .vmf import VMF, from_bsp_entities, new as new_vmf

# tools/gmodkit/<файл> → корень репозитория на три уровня выше.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _out(data, as_json: bool, title: str = "") -> None:
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return
    if title:
        print(f"── {title}")
    if isinstance(data, dict):
        width = max((len(str(k)) for k in data), default=0)
        for key, value in data.items():
            if isinstance(value, (list, tuple)) and len(value) > 12:
                value = f"{len(value)} шт. (--json для полного списка)"
            elif isinstance(value, dict) and len(value) > 12:
                value = f"{len(value)} записей (--json для полного списка)"
            print(f"  {str(key).ljust(width)} : {value}")
    elif isinstance(data, list):
        for item in data:
            print(f"  {item}")
    else:
        print(data)


def _counts(mapping: dict, limit: int, as_json: bool, title: str) -> None:
    if as_json:
        print(json.dumps(mapping, ensure_ascii=False, indent=2))
        return
    print(f"── {title} ({len(mapping)})")
    for name, count in sorted(mapping.items(), key=lambda kvp: (-kvp[1], kvp[0]))[:limit]:
        print(f"  {count:6d}  {name}")
    if len(mapping) > limit:
        print(f"  … ещё {len(mapping) - limit}, полностью — с --json")


# ───────────────────────────── bsp ───────────────────────────────────
def cmd_bsp(args) -> int:
    src = BSP.open(args.file)
    if args.cmd == "info":
        _out(src.summary(), args.json, f"BSP {src.name}")
    elif args.cmd == "lumps":
        rows = [
            {"index": l.index, "name": l.name, "offset": l.offset,
             "length": l.length, "version": l.version}
            for l in src.lumps if l.length > 0
        ]
        if args.json:
            print(json.dumps(rows, ensure_ascii=False, indent=2))
        else:
            print(f"── лампы с данными ({len(rows)}/64)")
            for row in rows:
                print(f"  {row['index']:2d} {row['name']:<26} {row['length']:>10} байт  v{row['version']}")
    elif args.cmd == "entities":
        ents = src.entities_by_class(args.classname) if args.classname else src.entities
        if args.json:
            print(json.dumps([{k: v for k, v in e.pairs} for e in ents], ensure_ascii=False, indent=2))
        else:
            print(f"── энтити: {len(ents)}")
            for ent in ents[:args.limit]:
                cls = ent.get("classname")
                name = ent.get("targetname") or ""
                origin = ent.get("origin") or ""
                print(f"  {cls:<32} {name:<24} {origin}")
            if len(ents) > args.limit:
                print(f"  … ещё {len(ents) - args.limit}")
    elif args.cmd == "classes":
        _counts(src.entity_class_counts(), args.limit, args.json, "классы энтити")
    elif args.cmd == "props":
        counts = src.prop_model_counts()
        if args.list:
            rows = [p.as_dict() for p in src.static_props]
            if args.json:
                print(json.dumps(rows, ensure_ascii=False, indent=2))
            else:
                for row in rows[:args.limit]:
                    o = row["origin"]
                    print(f"  {row['model']:<60} {o[0]:.0f} {o[1]:.0f} {o[2]:.0f}")
        else:
            _counts(counts, args.limit, args.json, "модели static props")
    elif args.cmd == "materials":
        mats = src.materials
        if args.json:
            print(json.dumps(mats, ensure_ascii=False, indent=2))
        else:
            print(f"── материалы: {len(mats)}")
            for mat in mats[:args.limit]:
                print(f"  {mat}")
            if len(mats) > args.limit:
                print(f"  … ещё {len(mats) - args.limit}")
    elif args.cmd == "pak":
        entries = src.pak_list()
        if args.extract:
            count = src.pak_extract(args.extract, args.prefix or "")
            print(f"распаковано файлов: {count} → {args.extract}")
        elif args.json:
            print(json.dumps([{"name": n, "size": s, "packed": c} for n, s, c in entries],
                             ensure_ascii=False, indent=2))
        else:
            total = sum(s for _n, s, _c in entries)
            print(f"── pakfile: {len(entries)} файлов, {total / 1024:.1f} КБ распакованного")
            for name, size, _c in entries[:args.limit]:
                print(f"  {size:>9}  {name}")
            if len(entries) > args.limit:
                print(f"  … ещё {len(entries) - args.limit}")
    elif args.cmd == "content":
        _out(grmx.map_content_report(args.file, REPO_ROOT), args.json, "контент карты")
    elif args.cmd == "tovmf":
        out = from_bsp_entities(args.file, args.classes.split(",") if args.classes else None,
                                include_props=args.props)
        target = args.out or out.path
        out.save(target)
        print(f"VMF записан: {target} (энтити: {len(out.entities)})")
    elif args.cmd == "setent":
        with open(args.entities, "r", encoding="utf-8") as fh:
            payload = json.load(fh)
        ents = [kv.Node("entity", list(item.items())) for item in payload]
        size = write_entity_lump(args.file, args.out, ents)
        print(f"BSP пересобран: {args.out} ({size} байт, энтити: {len(ents)})")
    if src.warnings and not args.json:
        print("предупреждения: " + "; ".join(src.warnings))
    return 0


# ───────────────────────────── vmf ───────────────────────────────────
def cmd_vmf(args) -> int:
    src = VMF.open(args.file) if args.cmd != "new" else new_vmf()
    if args.cmd == "info":
        _out(src.summary(), args.json, f"VMF {os.path.basename(args.file)}")
    elif args.cmd == "classes":
        _counts(src.entity_class_counts(), args.limit, args.json, "классы энтити")
    elif args.cmd == "entities":
        ents = src.entities_by_class(args.classname) if args.classname else src.entities
        if args.json:
            print(json.dumps([{k: v for k, v in e.pairs} for e in ents], ensure_ascii=False, indent=2))
        else:
            print(f"── энтити: {len(ents)}")
            for ent in ents[:args.limit]:
                print(f"  {ent.get('classname'):<32} {ent.get('targetname') or '':<24} {ent.get('origin') or ''}")
    elif args.cmd == "materials":
        _counts(src.materials(), args.limit, args.json, "материалы брашей")
    elif args.cmd == "models":
        _counts(src.models(), args.limit, args.json, "модели в энтити")
    elif args.cmd == "add":
        origin = tuple(kv.vec(args.origin))
        angles = tuple(kv.vec(args.angles))
        extra = {}
        for pair in args.key or []:
            if "=" in pair:
                k, v = pair.split("=", 1)
                extra[k] = v
        src.add_point_entity(args.classname, origin, angles, **extra)
        src.save(args.out or args.file)
        print(f"добавлено {args.classname} в {args.out or args.file}")
    elif args.cmd == "remove":
        n = src.remove_entities(args.classname)
        src.save(args.out or args.file)
        print(f"удалено энтити: {n}")
    elif args.cmd == "move":
        n = src.translate_entities(args.classname, tuple(kv.vec(args.delta)))
        src.save(args.out or args.file)
        print(f"сдвинуто энтити: {n}")
    elif args.cmd == "rotate":
        n = src.rotate_entities_yaw(args.classname, args.degrees, tuple(kv.vec(args.pivot)))
        src.save(args.out or args.file)
        print(f"повёрнуто энтити: {n}")
    elif args.cmd == "new":
        src.save(args.out)
        print(f"пустой VMF: {args.out}")
    return 0


# ───────────────────────────── mdl ───────────────────────────────────
def cmd_mdl(args) -> int:
    if args.cmd == "scan":
        paths = scan_models(args.file)
        rows = []
        for path in paths:
            try:
                m = MDL.open(path)
                rows.append({"model": os.path.relpath(path, args.file), "version": m.version,
                             "bones": m.bone_count, "sequences": m.localseq_count,
                             "static": m.is_static_prop,
                             "materials": len(m.texture_names())})
            except Exception as exc:  # noqa: BLE001
                rows.append({"model": os.path.relpath(path, args.file), "error": str(exc)})
        if args.json:
            print(json.dumps(rows, ensure_ascii=False, indent=2))
        else:
            print(f"── моделей: {len(rows)}")
            for row in rows[:args.limit]:
                if "error" in row:
                    print(f"  ! {row['model']}: {row['error']}")
                else:
                    print(f"  v{row['version']:<3} кости:{row['bones']:<4} секв:{row['sequences']:<4} "
                          f"мат:{row['materials']:<3} {'static ' if row['static'] else '       '}{row['model']}")
        return 0

    model = MDL.open(args.file)
    if args.cmd == "info":
        _out(model.summary(), args.json, f"MDL {os.path.basename(args.file)}")
    elif args.cmd == "bones":
        bones = model.bones()
        if args.json:
            print(json.dumps([{"index": b.index, "name": b.name, "parent": b.parent,
                               "pos": list(b.pos), "surfaceprop": b.surfaceprop} for b in bones],
                             ensure_ascii=False, indent=2))
        else:
            print(f"── кости: {len(bones)}")
            for b in bones[:args.limit]:
                parent = bones[b.parent].name if 0 <= b.parent < len(bones) else "—"
                print(f"  {b.index:3d} {b.name:<34} ← {parent}")
    elif args.cmd == "sequences":
        seqs = model.sequences()
        if args.json:
            print(json.dumps([{"index": s.index, "name": s.name, "activity": s.activity} for s in seqs],
                             ensure_ascii=False, indent=2))
        else:
            print(f"── секвенции: {len(seqs)}")
            for s in seqs[:args.limit]:
                print(f"  {s.index:3d} {s.name:<34} {s.activity}")
    elif args.cmd == "materials":
        data = {"textures": model.texture_names(), "cdmaterials": model.cdmaterials(),
                "expected_paths": model.material_paths()}
        if args.json:
            print(json.dumps(data, ensure_ascii=False, indent=2))
        else:
            print("── текстуры:", ", ".join(data["textures"]) or "нет")
            print("── cdmaterials:", ", ".join(data["cdmaterials"]) or "нет")
            print("── ожидаемые пути:")
            for path in data["expected_paths"]:
                mark = "есть" if os.path.isfile(os.path.join(REPO_ROOT, path)) else "НЕТ "
                print(f"  [{mark}] {path}")
    elif args.cmd == "bodyparts":
        parts = model.bodyparts()
        rows = [{"name": bp.name, "models": [{"name": m.name, "meshes": m.num_meshes,
                                              "vertices": m.num_vertices} for m in bp.models]}
                for bp in parts]
        if args.json:
            print(json.dumps(rows, ensure_ascii=False, indent=2))
        else:
            for bp in parts:
                print(f"  {bp.name}")
                for m in bp.models:
                    print(f"      {m.name:<28} меши:{m.num_meshes:<3} вершины:{m.num_vertices}")
    elif args.cmd == "attachments":
        att = model.attachments()
        if args.json:
            print(json.dumps([{"index": a.index, "name": a.name, "bone": a.bone} for a in att],
                             ensure_ascii=False, indent=2))
        else:
            print(f"── аттачменты: {len(att)}")
            for a in att:
                print(f"  {a.index:3d} {a.name:<28} кость {a.bone}")
    return 0


# ───────────────────────────── smd ───────────────────────────────────
def cmd_smd(args) -> int:
    if args.cmd == "cube":
        model = cube(args.size, args.material)
        model.save(args.out)
        print(f"тестовый куб: {args.out} ({len(model.triangles)} треугольников)")
        return 0

    model = SMD.open(args.file)
    if args.cmd == "info":
        _out(model.summary(), args.json, f"SMD {os.path.basename(args.file)}")
    elif args.cmd == "bones":
        if args.json:
            print(json.dumps([{"index": n.index, "name": n.name, "parent": n.parent}
                              for n in model.nodes], ensure_ascii=False, indent=2))
        else:
            for n in model.nodes[:args.limit]:
                parent = next((x.name for x in model.nodes if x.index == n.parent), "—")
                print(f"  {n.index:3d} {n.name:<34} ← {parent}")
    elif args.cmd == "check":
        problems = model.weight_problems()
        _out({"warnings": model.warnings, "weight_problems": problems,
              "triangles": len(model.triangles), "nodes": len(model.nodes)},
             args.json, "проверка SMD")
    elif args.cmd == "scale":
        model.scale(args.factor)
        model.save(args.out or args.file)
        print(f"масштаб ×{args.factor} → {args.out or args.file}")
    elif args.cmd == "move":
        model.translate(tuple(kv.vec(args.delta)))
        model.save(args.out or args.file)
        print(f"сдвиг {args.delta} → {args.out or args.file}")
    elif args.cmd == "rename-material":
        n = model.rename_material(args.old, args.new)
        model.save(args.out or args.file)
        print(f"материал переименован в {n} треугольниках")
    elif args.cmd == "rename-bone":
        n = model.rename_bone(args.old, args.new)
        model.save(args.out or args.file)
        print(f"переименовано костей: {n}")
    elif args.cmd == "obj":
        target = args.out or (os.path.splitext(args.file)[0] + ".obj")
        with open(target, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(model.to_obj())
        print(f"OBJ записан: {target}")
    elif args.cmd == "anim":
        model.keep_frames(args.first, args.last)
        model.strip_geometry()
        model.save(args.out)
        print(f"анимация {args.first}–{args.last} → {args.out} (кадров: {len(model.frames)})")
    elif args.cmd == "qc":
        text = make_qc(args.modelname, os.path.basename(args.file),
                       args.cdmaterials.split(",") if args.cdmaterials else [],
                       args.surfaceprop, args.mass, not args.dynamic)
        if args.out:
            with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
            print(f"QC записан: {args.out}")
        else:
            print(text)
    return 0


# ───────────────────────────── grm ───────────────────────────────────
def cmd_grm(args) -> int:
    if args.cmd == "spawns":
        name, points = grmx.export_global_spawns(args.file, z_offset=args.z_offset)
        target = args.out or os.path.join(REPO_ROOT, "tools", "gmodkit", "out",
                                          grmx.spawn_files(name)["global"])
        grmx.write_json(target, points)
        print(f"точек спавна: {len(points)} → {target}")
        print("положить в garrysmod/data/ на сервере")
    elif args.cmd == "faction-spawns":
        mapping = {}
        for pair in args.map or []:
            if "=" in pair:
                k, v = pair.split("=", 1)
                mapping[k] = v
        if not mapping:
            print("нужен хотя бы один --map targetname=Фракция", file=sys.stderr)
            return 2
        name, data = grmx.export_faction_spawns(args.file, mapping, z_offset=args.z_offset)
        target = args.out or os.path.join(REPO_ROOT, "tools", "gmodkit", "out",
                                          grmx.spawn_files(name)["factions"])
        grmx.write_json(target, data)
        total = sum(len(v["points"]) for v in data.values())
        print(f"фракций: {len(data)}, точек: {total} → {target}")
    elif args.cmd == "perms":
        class_map = {}
        for pair in args.map or []:
            if "=" in pair:
                k, v = pair.split("=", 1)
                class_map[k] = v
        if not class_map:
            print("нужен хотя бы один --map метка=grm_класс", file=sys.stderr)
            return 2
        _name, records = grmx.export_perm_entities(args.file, class_map, z_offset=args.z_offset)
        records = grmx.dedupe_perms(records)
        target = args.out or os.path.join(REPO_ROOT, "tools", "gmodkit", "out",
                                          "grm_perm_entities.json")
        grmx.write_json(target, records)
        print(f"пермов: {len(records)} → {target}")
        print("положить в garrysmod/data/grm_perm_entities.json (или /permload)")
    elif args.cmd == "content":
        report = grmx.check_content(REPO_ROOT)
        if args.json:
            print(json.dumps(report, ensure_ascii=False, indent=2))
        else:
            print(f"── модели в Lua: {report['models_referenced']} "
                  f"(в репо {len(report['models_in_repo'])}, внешних {len(report['models_external'])})")
            for path in report["models_external"][:args.limit]:
                who = report["usage_models"][path]
                print(f"  внешняя: {path}  ({who[0]}{'…' if len(who) > 1 else ''})")
            print(f"── материалы в Lua: {report['materials_referenced']} "
                  f"(в репо {len(report['materials_in_repo'])}, внешних {len(report['materials_external'])})")
            for path in report["materials_external"][:args.limit]:
                print(f"  внешний: {path}")
    elif args.cmd == "models":
        report = grmx.check_models(REPO_ROOT)
        if args.json:
            print(json.dumps(report, ensure_ascii=False, indent=2))
        else:
            print(f"── проверено моделей: {report['checked']}, с замечаниями: {len(report['problems'])}")
            for line in report["problems"][:args.limit]:
                print(f"  ! {line}")
    return 0


# ─────────────────────────── парсер ──────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gmodkit",
        description="Инструментарий Source/GMod: карты bsp/vmf и модели mdl/smd.",
    )
    p.add_argument("--version", action="version", version=f"gmodkit {__version__}")
    sub = p.add_subparsers(dest="group", required=True)

    def common(sp):
        sp.add_argument("--json", action="store_true", help="машинный вывод")
        sp.add_argument("--limit", type=int, default=30, help="сколько строк печатать")

    # bsp
    b = sub.add_parser("bsp", help="скомпилированные карты .bsp")
    bs = b.add_subparsers(dest="cmd", required=True)
    for name, help_text in (("info", "сводка"), ("lumps", "таблица ламп"),
                            ("classes", "классы энтити"), ("materials", "материалы"),
                            ("content", "нужный карте контент")):
        sp = bs.add_parser(name, help=help_text)
        sp.add_argument("file")
        common(sp)
    sp = bs.add_parser("entities", help="список энтити")
    sp.add_argument("file"); sp.add_argument("--classname", "-c"); common(sp)
    sp = bs.add_parser("props", help="static props")
    sp.add_argument("file"); sp.add_argument("--list", action="store_true", help="каждый проп, а не сводка")
    common(sp)
    sp = bs.add_parser("pak", help="встроенный pakfile")
    sp.add_argument("file"); sp.add_argument("--extract", metavar="DIR")
    sp.add_argument("--prefix", help="только пути с этим префиксом"); common(sp)
    sp = bs.add_parser("tovmf", help="энтити карты → .vmf")
    sp.add_argument("file"); sp.add_argument("--out", "-o")
    sp.add_argument("--classes", help="через запятую: только эти классы")
    sp.add_argument("--props", action="store_true", help="добавить static props")
    common(sp)
    sp = bs.add_parser("setent", help="заменить энтити-лампу из JSON")
    sp.add_argument("file"); sp.add_argument("entities"); sp.add_argument("--out", "-o", required=True)
    common(sp)

    # vmf
    v = sub.add_parser("vmf", help="исходники карт .vmf")
    vs = v.add_subparsers(dest="cmd", required=True)
    for name, help_text in (("info", "сводка"), ("classes", "классы энтити"),
                            ("materials", "материалы брашей"), ("models", "модели")):
        sp = vs.add_parser(name, help=help_text)
        sp.add_argument("file"); common(sp)
    sp = vs.add_parser("entities", help="список энтити")
    sp.add_argument("file"); sp.add_argument("--classname", "-c"); common(sp)
    sp = vs.add_parser("add", help="добавить точечную энтити")
    sp.add_argument("file"); sp.add_argument("classname")
    sp.add_argument("--origin", default="0 0 0"); sp.add_argument("--angles", default="0 0 0")
    sp.add_argument("--key", action="append", metavar="K=V"); sp.add_argument("--out", "-o")
    common(sp)
    sp = vs.add_parser("remove", help="удалить энтити класса")
    sp.add_argument("file"); sp.add_argument("classname"); sp.add_argument("--out", "-o"); common(sp)
    sp = vs.add_parser("move", help="сдвинуть энтити класса")
    sp.add_argument("file"); sp.add_argument("classname"); sp.add_argument("delta")
    sp.add_argument("--out", "-o"); common(sp)
    sp = vs.add_parser("rotate", help="повернуть энтити класса вокруг Z")
    sp.add_argument("file"); sp.add_argument("classname"); sp.add_argument("degrees", type=float)
    sp.add_argument("--pivot", default="0 0 0"); sp.add_argument("--out", "-o"); common(sp)
    sp = vs.add_parser("new", help="создать пустой .vmf")
    sp.add_argument("out"); sp.add_argument("file", nargs="?", default=None); common(sp)

    # mdl
    m = sub.add_parser("mdl", help="модели .mdl (+vvd/vtx/phy)")
    ms = m.add_subparsers(dest="cmd", required=True)
    for name, help_text in (("info", "сводка"), ("bones", "кости"), ("sequences", "секвенции"),
                            ("materials", "текстуры и пути vmt"), ("bodyparts", "бодипарты"),
                            ("attachments", "аттачменты"), ("scan", "рекурсивный обход каталога")):
        sp = ms.add_parser(name, help=help_text)
        sp.add_argument("file"); common(sp)

    # smd
    s = sub.add_parser("smd", help="исходники моделей .smd")
    ss = s.add_subparsers(dest="cmd", required=True)
    for name, help_text in (("info", "сводка"), ("bones", "скелет"), ("check", "проверка весов")):
        sp = ss.add_parser(name, help=help_text)
        sp.add_argument("file"); common(sp)
    sp = ss.add_parser("scale", help="масштабировать")
    sp.add_argument("file"); sp.add_argument("factor", type=float); sp.add_argument("--out", "-o"); common(sp)
    sp = ss.add_parser("move", help="сдвинуть")
    sp.add_argument("file"); sp.add_argument("delta"); sp.add_argument("--out", "-o"); common(sp)
    sp = ss.add_parser("rename-material", help="переименовать материал")
    sp.add_argument("file"); sp.add_argument("old"); sp.add_argument("new")
    sp.add_argument("--out", "-o"); common(sp)
    sp = ss.add_parser("rename-bone", help="переименовать кость")
    sp.add_argument("file"); sp.add_argument("old"); sp.add_argument("new")
    sp.add_argument("--out", "-o"); common(sp)
    sp = ss.add_parser("obj", help="экспорт меша в .obj")
    sp.add_argument("file"); sp.add_argument("--out", "-o"); common(sp)
    sp = ss.add_parser("anim", help="вырезать кадры в SMD-анимацию")
    sp.add_argument("file"); sp.add_argument("first", type=int); sp.add_argument("last", type=int)
    sp.add_argument("--out", "-o", required=True); common(sp)
    sp = ss.add_parser("qc", help="сгенерировать заготовку .qc")
    sp.add_argument("file"); sp.add_argument("modelname")
    sp.add_argument("--cdmaterials", default=""); sp.add_argument("--surfaceprop", default="metal")
    sp.add_argument("--mass", type=float, default=10.0); sp.add_argument("--dynamic", action="store_true")
    sp.add_argument("--out", "-o"); common(sp)
    sp = ss.add_parser("cube", help="сделать тестовый куб")
    sp.add_argument("out"); sp.add_argument("--size", type=float, default=16.0)
    sp.add_argument("--material", default="debug/debugempty"); common(sp)

    # grm
    g = sub.add_parser("grm", help="мост к данным GRM")
    gs = g.add_subparsers(dest="cmd", required=True)
    sp = gs.add_parser("spawns", help="точки спавна карты → JSON GRM")
    sp.add_argument("file"); sp.add_argument("--out", "-o")
    sp.add_argument("--z-offset", type=float, default=0.0); common(sp)
    sp = gs.add_parser("faction-spawns", help="точки фракций по targetname")
    sp.add_argument("file"); sp.add_argument("--map", action="append", metavar="TARGET=Фракция")
    sp.add_argument("--out", "-o"); sp.add_argument("--z-offset", type=float, default=0.0); common(sp)
    sp = gs.add_parser("perms", help="метки карты → grm_perm_entities.json")
    sp.add_argument("file"); sp.add_argument("--map", action="append", metavar="МЕТКА=grm_класс")
    sp.add_argument("--out", "-o"); sp.add_argument("--z-offset", type=float, default=0.0); common(sp)
    sp = gs.add_parser("content", help="аудит ссылок на модели/материалы в Lua")
    sp.add_argument("file", nargs="?", default=REPO_ROOT); common(sp)
    sp = gs.add_parser("models", help="полнота моделей репозитория")
    sp.add_argument("file", nargs="?", default=REPO_ROOT); common(sp)

    st = sub.add_parser("selftest", help="самопроверка на синтетических фикстурах")
    st.add_argument("--json", action="store_true")
    st.add_argument("--limit", type=int, default=30)
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.group == "selftest":
        from .selftest import run
        return run()
    handler = {"bsp": cmd_bsp, "vmf": cmd_vmf, "mdl": cmd_mdl, "smd": cmd_smd, "grm": cmd_grm}[args.group]
    try:
        return handler(args)
    except FileNotFoundError as exc:
        print(f"файл не найден: {exc.filename}", file=sys.stderr)
        return 2
    except ValueError as exc:
        print(f"ошибка формата: {exc}", file=sys.stderr)
        return 2
