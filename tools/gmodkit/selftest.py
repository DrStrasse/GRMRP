"""Самопроверка gmodkit: python3 tools/gmodkit.py selftest.

Фикстуры синтетические (BSP собирается тут же байт в байт), плюс, если в
репозитории есть настоящие .mdl — они тоже прогоняются. Стенд обязателен
к запуску после любой правки парсеров: форматы Valve прощают мало.
"""

from __future__ import annotations

import io
import json
import os
import struct
import tempfile
import zipfile
from typing import Callable, List, Tuple

from . import bsp as bsp_mod
from . import grmx, kv, smd as smd_mod
from .mdl import MDL, scan_models
from .vmf import VMF, from_bsp_entities, new as new_vmf

# tools/gmodkit/<файл> → корень репозитория на три уровня выше.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

ENT_TEXT = """{
"classname" "worldspawn"
"skyname" "sky_day01_01"
"detailvbsp" "detail.vbsp"
}
{
"classname" "info_player_start"
"origin" "128 -64 16"
"angles" "0 90 0"
"targetname" "spawn_police_1"
}
{
"classname" "info_player_start"
"origin" "256 64 16"
"angles" "0 180 0"
"targetname" "spawn_army_1"
}
{
"classname" "prop_dynamic"
"model" "models/props_c17/atm01.mdl"
"origin" "10 20 30"
"angles" "0 45 0"
"targetname" "grm_atm_lobby"
}
{
"classname" "func_door"
"model" "*1"
"origin" "0 0 0"
}
"""


def _build_bsp(path: str, short_gamelump: bool = False) -> None:
    """Собрать минимальный, но настоящий VBSP v20 со всем, что мы читаем."""
    end = "<"
    header_size = 8 + bsp_mod.HEADER_LUMPS * 16 + 4
    payloads = {}

    payloads[bsp_mod.LUMP_ENTITIES] = ENT_TEXT.encode("utf-8") + b"\x00"

    materials = ["TOOLS/TOOLSNODRAW", "CONCRETE/CONCRETEFLOOR001A", "METAL/METALWALL001A"]
    blob = bytearray()
    offsets = []
    for mat in materials:
        offsets.append(len(blob))
        blob += mat.encode("ascii") + b"\x00"
    payloads[bsp_mod.LUMP_TEXDATA_STRING_DATA] = bytes(blob)
    payloads[bsp_mod.LUMP_TEXDATA_STRING_TABLE] = b"".join(struct.pack(end + "i", o) for o in offsets)

    # Две brush-модели (worldspawn + func_door).
    models = bytearray()
    for i in range(2):
        models += struct.pack(end + "9f3i",
                              -512.0, -512.0, -128.0, 512.0, 512.0, 512.0,
                              0.0, 0.0, 0.0, 0, i * 4, 4)
    payloads[bsp_mod.LUMP_MODELS] = bytes(models)

    # game lump 'sprp' версии 10 с двумя пропами.
    names = ["models/props_c17/lamppost03a.mdl", "models/props_c17/bench01a.mdl"]
    sprp = bytearray()
    sprp += struct.pack(end + "i", len(names))
    for name in names:
        sprp += name.encode("ascii").ljust(128, b"\x00")
    sprp += struct.pack(end + "i", 2)          # leaf count
    sprp += struct.pack(end + "2H", 0, 1)      # leafs
    sprp += struct.pack(end + "i", 3)          # prop count
    entry_size = 72
    for i, prop_type in enumerate((0, 1, 1)):
        rec = bytearray(entry_size)
        struct.pack_into(end + "6f", rec, 0, 100.0 * i, 50.0 * i, 8.0, 0.0, 90.0 * i, 0.0)
        struct.pack_into(end + "3H", rec, 24, prop_type, 0, 1)
        struct.pack_into(end + "2B", rec, 30, 6, 0)
        struct.pack_into(end + "i2f", rec, 32, 0, 0.0, 0.0)
        struct.pack_into(end + "3f", rec, 40, 0.0, 0.0, 0.0)   # lighting origin
        struct.pack_into(end + "f", rec, 52, 1.0)              # forced fade scale
        struct.pack_into(end + "f", rec, entry_size - 4, 1.0)  # uniform scale (v11+)
        sprp += rec

    game_lump = bytearray(struct.pack(end + "i", 1))
    # Смещение sprp считаем от начала файла — как делает vbsp.
    sprp_ofs_placeholder = len(game_lump)
    game_lump += struct.pack(end + "4sHHii", b"prps", 0, 10, 0, len(sprp))

    pak_buf = io.BytesIO()
    with zipfile.ZipFile(pak_buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("materials/custom/test.vmt", '"UnlitGeneric" { "$basetexture" "custom/test" }')
        zf.writestr("models/custom/thing.mdl", b"IDST" + b"\x00" * 64)
    payloads[bsp_mod.LUMP_PAKFILE] = pak_buf.getvalue()

    # Раскладка: сначала всё, кроме game lump, потом game lump и его данные.
    out = bytearray(header_size)
    table = {}
    for index in sorted(payloads):
        while len(out) % 4:
            out.append(0)
        table[index] = (len(out), len(payloads[index]))
        out += payloads[index]

    while len(out) % 4:
        out.append(0)
    game_lump_offset = len(out)
    sprp_offset = game_lump_offset + len(game_lump)
    struct.pack_into(end + "i", game_lump, sprp_ofs_placeholder + 8, sprp_offset)
    # short_gamelump=True воспроизводит поведение vbsp: в заголовке
    # объявлена только директория, а данные 'sprp' лежат ЗА границей лампы.
    declared = len(game_lump) if short_gamelump else len(game_lump) + len(sprp)
    table[bsp_mod.LUMP_GAME_LUMP] = (game_lump_offset, declared)
    out += game_lump
    out += sprp

    struct.pack_into(end + "4si", out, 0, b"VBSP", 20)
    for i in range(bsp_mod.HEADER_LUMPS):
        off, ln = table.get(i, (0, 0))
        struct.pack_into(end + "iii4s", out, 8 + i * 16, off, ln, 0, b"\x00\x00\x00\x00")
    struct.pack_into(end + "i", out, 8 + bsp_mod.HEADER_LUMPS * 16, 42)

    with open(path, "wb") as fh:
        fh.write(out)


VMF_TEXT = """versioninfo
{
	"editorversion" "400"
	"mapversion" "7"
	"formatversion" "100"
	"prefab" "0"
}
visgroups
{
}
world
{
	"id" "1"
	"classname" "worldspawn"
	"skyname" "sky_day01_01"
	solid
	{
		"id" "2"
		side
		{
			"id" "3"
			"plane" "(0 0 0) (0 64 0) (64 64 0)"
			"material" "TOOLS/TOOLSNODRAW"
			"uaxis" "[1 0 0 0] 0.25"
		}
		side
		{
			"id" "4"
			"plane" "(0 0 64) (64 0 64) (64 64 64)"
			"material" "CONCRETE/CONCRETEFLOOR001A"
			"uaxis" "[1 0 0 0] 0.25"
		}
	}
}
entity
{
	"id" "10"
	"classname" "info_player_start"
	"origin" "0 0 16"
	"angles" "0 90 0"
	editor
	{
		"color" "220 30 220"
	}
}
entity
{
	"id" "11"
	"classname" "prop_static"
	"model" "models/props_c17/atm01.mdl"
	"origin" "64 0 0"
	"angles" "0 0 0"
	connections
	{
		"OnUser1" "relay1,Trigger,,0,-1"
		"OnUser1" "relay2,Trigger,,0.5,-1"
	}
}
"""


def model_mass_check(model) -> float:
    return float(model.mass)


def run() -> int:
    checks: List[Tuple[str, Callable[[], str]]] = []
    tmp = tempfile.mkdtemp(prefix="gmodkit_")
    bsp_path = os.path.join(tmp, "rp_test.bsp")
    _build_bsp(bsp_path)

    # ── KeyValues ─────────────────────────────────────────────────────
    def kv_roundtrip() -> str:
        roots = kv.parse(VMF_TEXT)
        again = kv.parse(kv.dump(roots))
        assert len(roots) == len(again), "число корневых блоков изменилось"
        ent = [n for n in again if n.name == "entity"][1]
        conn = ent.first("connections")
        assert conn is not None and len(conn.get_all("OnUser1")) == 2, "повторяющиеся ключи потеряны"
        return "round-trip без потерь, дубли ключей сохранены"

    def kv_errors() -> str:
        for bad in ('foo {', 'foo { "a" }', '}'):
            try:
                kv.parse(bad)
            except kv.KVError:
                continue
            raise AssertionError(f"не поймана ошибка: {bad!r}")
        return "битый KeyValues отбит с понятной ошибкой"

    # ── BSP ───────────────────────────────────────────────────────────
    def bsp_header() -> str:
        b = bsp_mod.BSP.open(bsp_path)
        assert b.version == 20 and b.revision == 42, "заголовок разобран неверно"
        s = b.summary()
        assert s["entities"] == 5, f"энтити: {s['entities']}"
        assert s["brush_entities"] == 1, "brush-энтити не распознана"
        assert s["materials"] == 3, "материалы не собраны"
        assert s["brush_models"] == 2, "brush-модели не собраны"
        assert s["skyname"] == "sky_day01_01", "worldspawn не прочитан"
        return f"v{b.version}, энтити {s['entities']}, материалы {s['materials']}"

    def bsp_props() -> str:
        b = bsp_mod.BSP.open(bsp_path)
        props = b.static_props
        assert len(props) == 3, f"пропов: {len(props)} (ждали 3): {b.warnings}"
        counts = b.prop_model_counts()
        assert counts["models/props_c17/bench01a.mdl"] == 2, "тип пропа определён неверно"
        assert abs(props[1].origin[0] - 100.0) < 1e-3, "origin пропа съехал"
        assert abs(props[1].scale - 1.0) < 1e-6, "uniform scale не прочитан"
        return f"sprp v10: {len(props)} пропов, {len(counts)} моделей"

    def bsp_pak() -> str:
        b = bsp_mod.BSP.open(bsp_path)
        names = [n for n, _s, _c in b.pak_list()]
        assert "materials/custom/test.vmt" in names, "pakfile не прочитан"
        dest = os.path.join(tmp, "unpacked")
        count = b.pak_extract(dest)
        assert count == 2 and os.path.isfile(os.path.join(dest, "materials/custom/test.vmt")), "распаковка не сработала"
        return f"pakfile: {len(names)} файлов, распаковка ок"

    def bsp_gamelump_outside() -> str:
        """Данные sprp за границей объявленной лампы — как у настоящего vbsp."""
        short_path = os.path.join(tmp, "rp_short.bsp")
        _build_bsp(short_path, short_gamelump=True)
        b = bsp_mod.BSP.open(short_path)
        assert len(b.static_props) == 3, f"пропы не найдены: {b.warnings}"
        patched = os.path.join(tmp, "rp_short_patched.bsp")
        ents = list(b.entities) + [kv.Node("entity", [("classname", "grm_payphone"), ("origin", "5 5 5")])]
        bsp_mod.write_entity_lump(short_path, patched, ents)
        b2 = bsp_mod.BSP.open(patched)
        assert len(b2.entities) == 6, "энтити не дописалась"
        assert len(b2.static_props) == 3, f"пропы потеряны при пересборке: {b2.warnings}"
        assert b2.prop_model_counts() == b.prop_model_counts(), "модели пропов поехали"
        return "sprp за границей лампы: пропы пережили пересборку"

    def bsp_entity_rewrite() -> str:
        b = bsp_mod.BSP.open(bsp_path)
        ents = list(b.entities)
        ents.append(kv.Node("entity", [("classname", "grm_bank_terminal"), ("origin", "1 2 3")]))
        out_path = os.path.join(tmp, "rp_test_patched.bsp")
        bsp_mod.write_entity_lump(bsp_path, out_path, ents)
        b2 = bsp_mod.BSP.open(out_path)
        assert len(b2.entities) == 6, "энтити не дописалась"
        assert len(b2.static_props) == 3, "после пересборки потерялись пропы"
        assert b2.materials == b.materials, "после пересборки поехали материалы"
        assert [n for n, _s, _c in b2.pak_list()] == [n for n, _s, _c in b.pak_list()], "pakfile поехал"
        return "лампа энтити переписана, остальные лампы целы"

    # ── VMF ───────────────────────────────────────────────────────────
    def vmf_parse() -> str:
        v = VMF.parse(VMF_TEXT, os.path.join(tmp, "rp_test.vmf"))
        s = v.summary()
        assert s["entities"] == 2 and s["world_solids"] == 1 and s["sides"] == 2, s
        assert v.materials()["TOOLS/TOOLSNODRAW"] == 1, "материалы брашей не собраны"
        assert "models/props_c17/atm01.mdl" in v.models(), "модели энтити не собраны"
        text = v.dumps()
        again = VMF.parse(text)
        left = {k: val for k, val in s.items() if k not in ("path", "map")}
        right = {k: val for k, val in again.summary().items() if k not in ("path", "map")}
        assert left == right, "round-trip изменил содержимое"
        return f"энтити {s['entities']}, браши {s['solids_total']}, стороны {s['sides']}"

    def vmf_edit() -> str:
        path = os.path.join(tmp, "edit.vmf")
        v = new_vmf()
        v.add_point_entity("info_player_start", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))
        v.add_point_entity("grm_bank_terminal", (100.0, 0.0, 0.0), (0.0, 90.0, 0.0), model="models/starless/atm.mdl")
        v.save(path)
        again = VMF.open(path)
        assert len(again.entities) == 2, "энтити не записались"
        moved = again.translate_entities("grm_bank_terminal", (0.0, 0.0, 32.0))
        rotated = again.rotate_entities_yaw("grm_bank_terminal", 90.0)
        ent = again.entities_by_class("grm_bank_terminal")[0]
        x, y, z = kv.vec(ent.get("origin"))
        assert moved == 1 and rotated == 1, "правки не применились"
        assert abs(z - 32.0) < 1e-6 and abs(x) < 1e-4 and abs(y - 100.0) < 1e-4, f"поворот неверен: {x} {y} {z}"
        assert abs(kv.vec(ent.get("angles"))[1] - 180.0) < 1e-6, "yaw не докручен"
        removed = again.remove_entities("info_player_start")
        assert removed == 1 and len(again.entities) == 1, "удаление не сработало"
        return "создание/сдвиг/поворот/удаление энтити ок"

    def bsp_to_vmf() -> str:
        v = from_bsp_entities(bsp_path, include_props=True)
        classes = v.entity_class_counts()
        assert classes.get("info_player_start") == 2, classes
        assert classes.get("prop_static") == 3, "пропы не перенесены"
        assert v.world.get("skyname") == "sky_day01_01", "worldspawn не перенесён"
        ids = [n.get("id") for n in v.entities]
        assert len(ids) == len(set(ids)), "id энтити задвоились"
        return f"BSP → VMF: {len(v.entities)} энтити, id уникальны"

    # ── SMD ───────────────────────────────────────────────────────────
    def smd_roundtrip() -> str:
        model = smd_mod.cube(32.0, "models/grm/test")
        text = model.dumps()
        again = smd_mod.SMD.parse(text, "<cube>")
        assert len(again.triangles) == 12, f"треугольников: {len(again.triangles)}"
        assert len(again.nodes) == 1 and again.frames, "скелет потерян"
        assert not again.warnings, again.warnings
        mins, maxs = again.bounds()
        assert abs(maxs[0] - 16.0) < 1e-3 and abs(mins[2] + 16.0) < 1e-3, (mins, maxs)
        return "куб 12 треугольников: разбор → запись → разбор совпал"

    def smd_edit() -> str:
        model = smd_mod.cube(10.0, "old_material")
        model.scale(2.0)
        model.translate((0.0, 0.0, 5.0))
        renamed = model.rename_material("old_material", "new_material")
        mins, maxs = model.bounds()
        assert renamed == 12 and "new_material" in model.materials(), "материал не переименован"
        assert abs(maxs[0] - 10.0) < 1e-3, f"масштаб не применился: {maxs}"
        assert abs(mins[2] + 5.0) < 1e-3, f"сдвиг не применился: {mins}"
        obj = model.to_obj()
        assert obj.count("\nv ") >= 7 and "f " in obj, "OBJ пустой"
        return "масштаб/сдвиг/переименование/OBJ ок"

    def smd_weights() -> str:
        bad = smd_mod.SMD.parse(
            "version 1\nnodes\n0 \"root\" -1\nend\nskeleton\ntime 0\n0 0 0 0 0 0 0\nend\n"
            "triangles\nmat\n"
            "0 0 0 0 0 0 1 0 0 2 0 0.4 0 0.4\n"
            "0 1 0 0 0 0 1 1 0 1 0 1.0\n"
            "0 0 1 0 0 0 1 0 1 1 0 1.0\n"
            "end\n")
        problems = bad.weight_problems()
        assert len(problems) == 1, f"недовес не найден: {problems}"
        assert not bad.warnings, bad.warnings
        return "вершина с суммой весов 0.8 поймана"

    def smd_qc() -> str:
        text = smd_mod.make_qc("grm/atm.mdl", "atm_ref.smd", ["models/grm"], "metal", 40.0)
        for needle in ("$modelname", "$body", "$cdmaterials", "$sequence", "$staticprop"):
            assert needle in text, f"в QC нет {needle}"
        return "QC-заготовка содержит обязательные директивы"

    # ── MDL ───────────────────────────────────────────────────────────
    def mdl_real() -> str:
        models = scan_models(os.path.join(REPO_ROOT, "models"))
        if not models:
            return "пропуск: в репозитории нет .mdl"
        ok = 0
        details = []
        for path in models:
            m = MDL.open(path)
            assert m.version in range(44, 50), f"{path}: версия {m.version}"
            assert m.internal_name, f"{path}: пустое внутреннее имя"
            info = m.summary()
            assert not m.warnings, f"{path}: {m.warnings}"
            assert info["textures"], f"{path}: не нашлись текстуры"
            bones = m.bones()
            assert len(bones) == m.bone_count, f"{path}: костей {len(bones)} против {m.bone_count}"
            if bones:
                assert bones[0].name, f"{path}: имя кости пустое"
            ok += 1
            if len(details) < 2:
                details.append(f"{os.path.basename(path)}: v{m.version}, кости {m.bone_count}, "
                               f"мат {len(info['textures'])}")
        return f"настоящих моделей разобрано {ok} ({'; '.join(details)})"

    def mdl_companions() -> str:
        models = scan_models(os.path.join(REPO_ROOT, "models"))
        if not models:
            return "пропуск: в репозитории нет .mdl"
        m = MDL.open(models[0])
        comp = m.companions()
        assert comp["vvd"] and comp["vvd"].get("lods"), f"vvd не прочитан: {comp['vvd']}"
        assert comp["vtx"] and comp["vtx"].get("bodyparts") is not None, f"vtx не прочитан: {comp['vtx']}"
        note = ""
        phy = comp["phy"]
        if phy and phy.get("mass"):
            # Масса в заголовке MDL и в .phy должны совпадать — это лучший
            # индикатор того, что хвост studiohdr_t разобран без сдвига на
            # поле (там три подряд идущих localnode-поля, на которых легко
            # уехать и получить мусорную массу/includemodels).
            assert abs(model_mass_check(m) - float(phy["mass"])) < 0.01, (
                f"масса MDL {m.mass} против PHY {phy['mass']} — сдвиг в заголовке")
            assert m.surfaceprop == phy.get("surfaceprop"), (
                f"surfaceprop MDL {m.surfaceprop!r} против PHY {phy.get('surfaceprop')!r}")
            note = f"; масса {m.mass} = phy, surfaceprop {m.surfaceprop}"
        assert m.includemodel_count < 64, f"includemodels {m.includemodel_count} — явный сдвиг заголовка"
        return (f"vvd: lod {comp['vvd']['lods']}, вершин {comp['vvd']['lod_vertices'][0]}; "
                f"vtx v{comp['vtx']['version']}{note}")

    # ── мост в GRM ────────────────────────────────────────────────────
    def grm_spawns() -> str:
        name, points = grmx.export_global_spawns(bsp_path, z_offset=1.0)
        assert name == "rp_test" and len(points) == 2, (name, points)
        first = points[0]
        assert first["pos"] == {"x": 128.0, "y": -64.0, "z": 17.0}, first
        assert first["ang"] == {"p": 0.0, "y": 90.0, "r": 0.0}, first
        out = os.path.join(tmp, grmx.spawn_files(name)["global"])
        grmx.write_json(out, points)
        assert json.load(open(out, encoding="utf-8"))[0]["pos"]["x"] == 128.0, "JSON не совпал"
        return f"{len(points)} точек в формате sh_spawn_points.lua"

    def grm_faction_spawns() -> str:
        _name, data = grmx.export_faction_spawns(bsp_path, {"spawn_police*": "Полиция",
                                                            "spawn_army*": "Армия"})
        assert set(data) == {"Полиция", "Армия"}, data
        for bundle in data.values():
            assert set(bundle) == {"points", "roles", "departments", "subdepartments", "positions"}, bundle
            assert len(bundle["points"]) == 1
        return "формат фракций совпадает с находкой 157 (points/roles/departments/…)"

    def grm_perms() -> str:
        _name, recs = grmx.export_perm_entities(bsp_path, {"grm_atm_*": "grm_bank_terminal"})
        assert isinstance(recs, list) and len(recs) == 1, recs
        rec = recs[0]
        assert set(rec) == {"map", "class", "model", "pos", "ang"}, rec
        assert rec["class"] == "grm_bank_terminal" and rec["map"] == "rp_test"
        assert rec["model"] == "models/props_c17/atm01.mdl"
        doubled = grmx.dedupe_perms(recs + [dict(rec)])
        assert len(doubled) == 1, "дедуп 6 юнитов не сработал"
        return "перм-запись массивом, дедуп работает"

    def grm_content() -> str:
        report = grmx.check_content(REPO_ROOT)
        assert report["models_referenced"] > 0, "в Lua не нашлось ни одной модели — регулярка сломана"
        return (f"модели: {report['models_referenced']} (локальных {len(report['models_in_repo'])}), "
                f"материалы: {report['materials_referenced']}")

    def grm_map_content() -> str:
        report = grmx.map_content_report(bsp_path, REPO_ROOT)
        assert report["models_total"] == 3, report
        assert report["packed_files"] == 2, report
        return f"карте нужно моделей: {report['models_total']}, в паке {report['packed_files']} файлов"

    checks += [
        ("kv: round-trip VMF", kv_roundtrip),
        ("kv: ошибки синтаксиса", kv_errors),
        ("bsp: заголовок и энтити", bsp_header),
        ("bsp: static props", bsp_props),
        ("bsp: pakfile", bsp_pak),
        ("bsp: перезапись энтити-лампы", bsp_entity_rewrite),
        ("bsp: sprp за границей лампы", bsp_gamelump_outside),
        ("vmf: разбор", vmf_parse),
        ("vmf: правки", vmf_edit),
        ("vmf: из bsp", bsp_to_vmf),
        ("smd: round-trip", smd_roundtrip),
        ("smd: правки и OBJ", smd_edit),
        ("smd: контроль весов", smd_weights),
        ("smd: заготовка QC", smd_qc),
        ("mdl: настоящие модели репо", mdl_real),
        ("mdl: vvd/vtx/phy", mdl_companions),
        ("grm: точки спавна", grm_spawns),
        ("grm: точки фракций", grm_faction_spawns),
        ("grm: пермы энтити", grm_perms),
        ("grm: аудит контента Lua", grm_content),
        ("grm: контент карты", grm_map_content),
    ]

    failed = 0
    for title, fn in checks:
        try:
            note = fn()
            print(f"  OK   {title} — {note}")
        except AssertionError as exc:
            failed += 1
            print(f"  FAIL {title} — {exc}")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"  ERR  {title} — {type(exc).__name__}: {exc}")

    print(f"\nитого: {len(checks) - failed}/{len(checks)} проверок пройдено")
    print(f"фикстуры: {tmp}")
    return 1 if failed else 0
