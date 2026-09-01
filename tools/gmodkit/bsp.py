"""BSP — скомпилированная карта Source (VBSP v19–v21, GMod v20/21).

Что достаём (то, что реально нужно агенту при работе с RP-картой):

* заголовок: версия, ревизия карты, таблица 64 ламп;
* энтити-лампа: все point/brush-энтити как KeyValues;
* список материалов (TexData + TexDataStringTable/Data);
* static props (game lump 'sprp' v4–v11) — имена моделей и их расстановка;
* модели брашей (LUMP_MODELS) — сколько brush-моделей и их габариты;
* встроенный pakfile (LUMP_PAKFILE) — обычный zip: список и распаковка;
* кубмапы, число планов/фейсов/лифов — для беглой оценки тяжести карты.

Правило разбора: ничего не падает на чужой карте. Любая лампа, которую не
удалось разобрать, даёт пустой результат и запись в `warnings`, а не
исключение — иначе один кривой мод-лумп рушит весь отчёт.
"""

from __future__ import annotations

import io
import os
import struct
import zipfile
from typing import Dict, List, Optional, Tuple

from . import kv

HEADER_LUMPS = 64

LUMP_ENTITIES = 0
LUMP_PLANES = 1
LUMP_TEXDATA = 2
LUMP_VERTEXES = 3
LUMP_NODES = 5
LUMP_TEXINFO = 6
LUMP_FACES = 7
LUMP_LIGHTING = 8
LUMP_LEAFS = 10
LUMP_EDGES = 12
LUMP_SURFEDGES = 13
LUMP_MODELS = 14
LUMP_BRUSHES = 18
LUMP_DISPINFO = 26
LUMP_ORIGINALFACES = 27
LUMP_GAME_LUMP = 35
LUMP_PAKFILE = 40
LUMP_CUBEMAPS = 42
LUMP_TEXDATA_STRING_DATA = 43
LUMP_TEXDATA_STRING_TABLE = 44
LUMP_OVERLAYS = 45

LUMP_NAMES = {
    0: "entities", 1: "planes", 2: "texdata", 3: "vertexes", 4: "visibility",
    5: "nodes", 6: "texinfo", 7: "faces", 8: "lighting", 9: "occlusion",
    10: "leafs", 11: "faceids", 12: "edges", 13: "surfedges", 14: "models",
    15: "worldlights", 16: "leaffaces", 17: "leafbrushes", 18: "brushes",
    19: "brushsides", 20: "areas", 21: "areaportals", 26: "dispinfo",
    27: "originalfaces", 28: "physdisp", 29: "physcollide", 30: "vertnormals",
    31: "vertnormalindices", 35: "game_lump", 40: "pakfile", 41: "clipportalverts",
    42: "cubemaps", 43: "texdata_string_data", 44: "texdata_string_table",
    45: "overlays", 48: "disp_verts", 54: "leafambientindex", 55: "worldlights_hdr",
    56: "leaf_ambient_lighting_hdr", 57: "leaf_ambient_lighting", 58: "xzippakfile",
    59: "faces_hdr", 60: "map_flags", 61: "overlay_fades",
}


class Lump:
    __slots__ = ("index", "offset", "length", "version", "fourcc")

    def __init__(self, index, offset, length, version, fourcc):
        self.index, self.offset, self.length = index, offset, length
        self.version, self.fourcc = version, fourcc

    @property
    def name(self) -> str:
        return LUMP_NAMES.get(self.index, f"lump_{self.index}")

    def __repr__(self) -> str:  # pragma: no cover
        return f"<Lump {self.index}:{self.name} off={self.offset} len={self.length} v={self.version}>"


class StaticProp:
    __slots__ = ("model", "origin", "angles", "skin", "solid", "flags",
                 "fade_min", "fade_max", "scale")

    def __init__(self, model, origin, angles, skin=0, solid=6, flags=0,
                 fade_min=0.0, fade_max=0.0, scale=1.0):
        self.model, self.origin, self.angles = model, origin, angles
        self.skin, self.solid, self.flags = skin, solid, flags
        self.fade_min, self.fade_max, self.scale = fade_min, fade_max, scale

    def as_dict(self) -> dict:
        return {
            "model": self.model,
            "origin": list(self.origin),
            "angles": list(self.angles),
            "skin": self.skin, "solid": self.solid, "flags": self.flags,
            "fade_min": self.fade_min, "fade_max": self.fade_max,
            "scale": self.scale,
        }


class BrushModel:
    __slots__ = ("index", "mins", "maxs", "origin", "first_face", "num_faces")

    def __init__(self, index, mins, maxs, origin, first_face, num_faces):
        self.index, self.mins, self.maxs = index, mins, maxs
        self.origin, self.first_face, self.num_faces = origin, first_face, num_faces

    def as_dict(self) -> dict:
        return {
            "index": self.index, "mins": list(self.mins), "maxs": list(self.maxs),
            "origin": list(self.origin), "first_face": self.first_face,
            "num_faces": self.num_faces,
        }


class BSP:
    """Ленивый читатель .bsp: файл читается целиком в память один раз."""

    def __init__(self, data: bytes, path: str = "<memory>"):
        self.path = path
        self.data = data
        self.warnings: List[str] = []
        if len(data) < 8 + HEADER_LUMPS * 16 + 4:
            raise ValueError("файл слишком мал для BSP")
        ident = data[:4]
        if ident not in (b"VBSP", b"PSBV"):
            raise ValueError(f"не BSP: сигнатура {ident!r}")
        self.big_endian = ident == b"PSBV"
        end = ">" if self.big_endian else "<"
        self._end = end
        self.version = struct.unpack_from(end + "i", data, 4)[0]
        self.lumps: List[Lump] = []
        for i in range(HEADER_LUMPS):
            off, ln, ver, cc = struct.unpack_from(end + "iii4s", data, 8 + i * 16)
            self.lumps.append(Lump(i, off, ln, ver, cc))
        self.revision = struct.unpack_from(end + "i", data, 8 + HEADER_LUMPS * 16)[0]
        self._entities: Optional[List[kv.Node]] = None
        self._materials: Optional[List[str]] = None
        self._props: Optional[List[StaticProp]] = None

    # ── загрузка ──────────────────────────────────────────────────────
    @classmethod
    def open(cls, path: str) -> "BSP":
        with io.open(path, "rb") as fh:
            return cls(fh.read(), path)

    @property
    def name(self) -> str:
        return os.path.splitext(os.path.basename(self.path))[0]

    def lump_data(self, index: int) -> bytes:
        lump = self.lumps[index]
        if lump.length <= 0 or lump.offset <= 0 or lump.offset + lump.length > len(self.data):
            return b""
        return self.data[lump.offset:lump.offset + lump.length]

    # ── энтити ────────────────────────────────────────────────────────
    @property
    def entities(self) -> List[kv.Node]:
        if self._entities is None:
            raw = self.lump_data(LUMP_ENTITIES)
            try:
                self._entities = kv.parse_entity_lump(raw.decode("utf-8", "replace"))
            except Exception as exc:  # noqa: BLE001 — карта чужая, падать нельзя
                self.warnings.append(f"энтити-лампа не разобрана: {exc}")
                self._entities = []
        return self._entities

    def entities_by_class(self, pattern: str) -> List[kv.Node]:
        """Фильтр по classname; поддерживает '*' в конце (info_player*)."""
        low = pattern.lower()
        star = low.endswith("*")
        stem = low[:-1] if star else low
        out = []
        for ent in self.entities:
            cls = (ent.get("classname") or "").lower()
            if (cls.startswith(stem) if star else cls == stem):
                out.append(ent)
        return out

    def entity_class_counts(self) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        for ent in self.entities:
            cls = ent.get("classname") or "<без classname>"
            counts[cls] = counts.get(cls, 0) + 1
        return counts

    @property
    def worldspawn(self) -> Optional[kv.Node]:
        got = self.entities_by_class("worldspawn")
        return got[0] if got else None

    # ── материалы ─────────────────────────────────────────────────────
    @property
    def materials(self) -> List[str]:
        if self._materials is not None:
            return self._materials
        out: List[str] = []
        try:
            table = self.lump_data(LUMP_TEXDATA_STRING_TABLE)
            blob = self.lump_data(LUMP_TEXDATA_STRING_DATA)
            end = self._end
            for i in range(len(table) // 4):
                off = struct.unpack_from(end + "i", table, i * 4)[0]
                if 0 <= off < len(blob):
                    stop = blob.find(b"\x00", off)
                    out.append(blob[off:stop if stop >= 0 else None].decode("ascii", "replace"))
        except Exception as exc:  # noqa: BLE001
            self.warnings.append(f"таблица материалов не разобрана: {exc}")
        self._materials = out
        return out

    # ── брашевые модели ───────────────────────────────────────────────
    def brush_models(self) -> List[BrushModel]:
        raw = self.lump_data(LUMP_MODELS)
        end = self._end
        out = []
        for i in range(len(raw) // 48):
            vals = struct.unpack_from(end + "9f3i", raw, i * 48)
            out.append(BrushModel(i, vals[0:3], vals[3:6], vals[6:9], vals[9], vals[10]))
        return out

    # ── static props (game lump 'sprp') ───────────────────────────────
    @property
    def static_props(self) -> List[StaticProp]:
        if self._props is None:
            self._props = self._read_static_props()
        return self._props

    def game_lumps(self) -> List[Tuple[str, int, int, int, int]]:
        """[(id, flags, version, offset, length)] из LUMP_GAME_LUMP."""
        raw = self.lump_data(LUMP_GAME_LUMP)
        if len(raw) < 4:
            return []
        end = self._end
        base = self.lumps[LUMP_GAME_LUMP].offset
        count = struct.unpack_from(end + "i", raw, 0)[0]
        out = []
        for i in range(max(0, min(count, 64))):
            pos = 4 + i * 16
            if pos + 16 > len(raw):
                break
            gid, flags, ver, ofs, ln = struct.unpack_from(end + "4sHHii", raw, pos)
            ident = gid.decode("ascii", "replace")
            if self.big_endian is False:
                ident = ident[::-1]  # в файле лежит развёрнутым ('prps')
            # Некоторые компиляторы пишут offset относительно начала лампы.
            if ofs + ln > len(self.data) and base + ofs + ln <= len(self.data):
                ofs = base + ofs
            out.append((ident.strip("\x00"), flags, ver, ofs, ln))
        return out

    def _read_static_props(self) -> List[StaticProp]:
        entry = next((g for g in self.game_lumps() if g[0] == "sprp"), None)
        if entry is None:
            return []
        _, _, version, ofs, ln = entry
        if ofs <= 0 or ln <= 0 or ofs + ln > len(self.data):
            self.warnings.append("game lump sprp вне файла")
            return []
        blob = self.data[ofs:ofs + ln]
        end = self._end
        try:
            pos = 0
            dict_count = struct.unpack_from(end + "i", blob, pos)[0]
            pos += 4
            names = []
            for _ in range(dict_count):
                names.append(blob[pos:pos + 128].split(b"\x00")[0].decode("ascii", "replace"))
                pos += 128
            leaf_count = struct.unpack_from(end + "i", blob, pos)[0]
            pos += 4 + leaf_count * 2
            prop_count = struct.unpack_from(end + "i", blob, pos)[0]
            pos += 4
            if prop_count <= 0:
                return []
            rest = len(blob) - pos
            # Версии 4..11 отличаются хвостом структуры. Размер записи
            # вычисляем делением — так парсер переживает и мод-версии.
            size = rest // prop_count
            if size < 56:
                self.warnings.append(f"sprp v{version}: запись {size} байт — слишком мала")
                return []
            props = []
            for i in range(prop_count):
                p = pos + i * size
                ox, oy, oz, ax, ay, az = struct.unpack_from(end + "6f", blob, p)
                prop_type, _first_leaf, _leaf_count = struct.unpack_from(end + "3H", blob, p + 24)
                solid, flags = struct.unpack_from(end + "2B", blob, p + 30)
                skin, fade_min, fade_max = struct.unpack_from(end + "i2f", blob, p + 32)
                scale = 1.0
                if version >= 11 and size >= 76:
                    # UniformScale — последнее поле записи в v11.
                    scale = struct.unpack_from(end + "f", blob, p + size - 4)[0]
                    if not (0.001 <= scale <= 1000.0):
                        scale = 1.0
                model = names[prop_type] if 0 <= prop_type < len(names) else f"<idx {prop_type}>"
                props.append(StaticProp(model, (ox, oy, oz), (ax, ay, az),
                                        skin, solid, flags, fade_min, fade_max, scale))
            return props
        except Exception as exc:  # noqa: BLE001
            self.warnings.append(f"sprp v{version} не разобран: {exc}")
            return []

    def prop_model_counts(self) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        for p in self.static_props:
            counts[p.model] = counts.get(p.model, 0) + 1
        return counts

    # ── встроенный pakfile ────────────────────────────────────────────
    def pakfile(self) -> Optional[zipfile.ZipFile]:
        raw = self.lump_data(LUMP_PAKFILE)
        if not raw:
            return None
        try:
            return zipfile.ZipFile(io.BytesIO(raw))
        except Exception as exc:  # noqa: BLE001
            self.warnings.append(f"pakfile не открылся: {exc}")
            return None

    def pak_list(self) -> List[Tuple[str, int, int]]:
        zf = self.pakfile()
        if zf is None:
            return []
        with zf:
            return [(i.filename, i.file_size, i.compress_size) for i in zf.infolist()]

    def pak_extract(self, dest: str, prefix: str = "") -> int:
        zf = self.pakfile()
        if zf is None:
            return 0
        count = 0
        with zf:
            for info in zf.infolist():
                if prefix and not info.filename.lower().startswith(prefix.lower()):
                    continue
                if info.is_dir():
                    continue
                target = os.path.normpath(os.path.join(dest, info.filename))
                if not target.startswith(os.path.abspath(dest)):
                    self.warnings.append(f"pakfile: пропущен путь наружу {info.filename}")
                    continue
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with open(target, "wb") as out:
                    out.write(zf.read(info))
                count += 1
        return count

    # ── сводка ────────────────────────────────────────────────────────
    def summary(self) -> dict:
        ws = self.worldspawn
        counts = self.entity_class_counts()
        return {
            "path": self.path,
            "map": self.name,
            "bsp_version": self.version,
            "map_revision": self.revision,
            "size_bytes": len(self.data),
            "entities": len(self.entities),
            "entity_classes": len(counts),
            "brush_entities": sum(1 for e in self.entities if (e.get("model") or "").startswith("*")),
            "point_entities": sum(1 for e in self.entities if not (e.get("model") or "").startswith("*")),
            "static_props": len(self.static_props),
            "unique_prop_models": len(self.prop_model_counts()),
            "materials": len(self.materials),
            "brush_models": len(self.brush_models()),
            "faces": self.lumps[LUMP_FACES].length // 56,
            "planes": self.lumps[LUMP_PLANES].length // 20,
            "leafs": self.lumps[LUMP_LEAFS].length // 32,
            "displacements": self.lumps[LUMP_DISPINFO].length // 176,
            "cubemaps": self.lumps[LUMP_CUBEMAPS].length // 16,
            "overlays": self.lumps[LUMP_OVERLAYS].length // 352,
            "pakfile_bytes": self.lumps[LUMP_PAKFILE].length,
            "pakfile_entries": len(self.pak_list()),
            "skyname": ws.get("skyname") if ws else None,
            "detailvbsp": ws.get("detailvbsp") if ws else None,
            "warnings": list(self.warnings),
        }


def _game_lump_span(src: BSP) -> Tuple[int, int]:
    """Реальный диапазон game lump: директория + данные подламп.

    Компиляторы Valve объявляют в заголовке длину, покрывающую только
    директорию (а то и её часть), а данные 'sprp' лежат следом, за
    границей лампы. Если при пересборке скопировать ровно объявленную
    длину, static props останутся за бортом — карта загрузится пустой.
    Поэтому берём диапазон от начала лампы до конца самой дальней подлампы.
    """
    lump = src.lumps[LUMP_GAME_LUMP]
    start = lump.offset
    stop = lump.offset + lump.length
    for _ident, _flags, _ver, ofs, ln in src.game_lumps():
        if ofs > 0 and ln > 0 and ofs + ln <= len(src.data):
            stop = max(stop, ofs + ln)
    return start, min(stop, len(src.data))


def _shift_game_lump(payload: bytes, src: BSP, new_offset: int) -> bytes:
    """Пересчитать абсолютные смещения внутри LUMP_GAME_LUMP на новое место."""
    if len(payload) < 4:
        return payload
    end = src._end
    old_offset = src.lumps[LUMP_GAME_LUMP].offset
    delta = new_offset - old_offset
    if delta == 0:
        return payload
    buf = bytearray(payload)
    count = struct.unpack_from(end + "i", buf, 0)[0]
    for i in range(max(0, min(count, 64))):
        pos = 4 + i * 16
        if pos + 16 > len(buf):
            break
        ofs = struct.unpack_from(end + "i", buf, pos + 8)[0]
        if ofs > 0:
            struct.pack_into(end + "i", buf, pos + 8, ofs + delta)
    return bytes(buf)


def write_entity_lump(src_path: str, dst_path: str, entities: List[kv.Node]) -> int:
    """Пересобрать .bsp с заменённой энтити-лампой.

    Лампа энтити — текст, её размер меняется, поэтому все лампы, лежащие
    после неё, съезжают: файл пересобирается целиком с новой таблицей
    смещений. Порядок ламп в файле сохраняется, выравнивание — 4 байта
    (движок этого требует).

    Возвращает размер записанного файла.
    """
    bsp = BSP.open(src_path)
    end = bsp._end
    new_ent = kv.entity_lump_text(entities).encode("utf-8")

    order = sorted(
        (l for l in bsp.lumps if l.length > 0 and l.offset > 0),
        key=lambda l: l.offset,
    )
    header_size = 8 + HEADER_LUMPS * 16 + 4
    out = bytearray(header_size)
    new_offsets: Dict[int, Tuple[int, int]] = {}
    for lump in order:
        payload = new_ent if lump.index == LUMP_ENTITIES else bsp.lump_data(lump.index)
        declared = len(payload)
        while len(out) % 4:
            out.append(0)
        if lump.index == LUMP_GAME_LUMP:
            # Директория game lump хранит АБСОЛЮТНЫЕ смещения в файле.
            # Если лампу подвинуть, не поправив их, static props уедут в
            # мусор (карта грузится, пропов нет) — правим на дельту.
            # Копируем весь реальный диапазон (директория + данные подламп),
            # но в заголовок пишем объявленную длину, как в оригинале.
            start, stop = _game_lump_span(bsp)
            payload = _shift_game_lump(bsp.data[start:stop], bsp, len(out))
        new_offsets[lump.index] = (len(out), declared)
        out += payload

    struct.pack_into(end + "4si", out, 0, b"VBSP", bsp.version)
    for i, lump in enumerate(bsp.lumps):
        off, ln = new_offsets.get(i, (0, 0))
        struct.pack_into(end + "iii4s", out, 8 + i * 16, off, ln, lump.version, lump.fourcc)
    struct.pack_into(end + "i", out, 8 + HEADER_LUMPS * 16, bsp.revision)

    with open(dst_path, "wb") as fh:
        fh.write(out)
    return len(out)
