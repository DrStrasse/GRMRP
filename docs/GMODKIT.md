# GMODKIT — инструментарий для карт и моделей Source/GMod

Свой парсер форматов Valve на чистом Python 3 (без зависимостей), чтобы
работать с картами и моделями прямо в репозитории: посмотреть, что внутри
чужой карты, вытащить из неё точки спавна в формат GRM, проверить, не
ссылается ли Lua на несуществующие модели, поправить SMD перед компиляцией.

Точка входа: `tools/gmodkit.py`. Пакет: `tools/gmodkit/`.
Стенд: `python3 tools/gmodkit.py selftest` (21 проверка, ~0.5 с).

```
python3 tools/gmodkit.py <группа> <команда> [файл] [опции]
группы: bsp  vmf  mdl  smd  grm  selftest
везде:  --json  (машинный вывод)   --limit N  (сколько строк печатать)
```

## Что поддержано

| Формат | Чтение | Запись |
|---|---|---|
| `.bsp` (VBSP v19–v21, GMod v20/21) | заголовок, 64 лампы, энтити, материалы, brush-модели, static props (`sprp` v4–v11), pakfile, кубмапы/дисплейсменты | перезапись энтити-лампы с корректным переносом game lump |
| `.vmf` | KeyValues-дерево целиком (браши, стороны, дисплейсменты, connections с дублями ключей) | round-trip без потерь, правки энтити |
| `.mdl` (v44–v49) | заголовок, кости, секвенции, бодипарты, аттачменты, текстуры + cdmaterials, скины, includemodels, масса и surfaceprop | — |
| `.vvd` / `.vtx` / `.phy` | заголовки: LOD и вершины, версия/бодипарты, солиды + текстовый блок (масса, surfaceprop) | — |
| `.smd` | скелет, кадры, треугольники, веса | запись, масштаб, сдвиг, переименования, нарезка анимации, экспорт `.obj`, заготовка `.qc` |

## Карты

```bash
# сводка: версия, сколько энтити/пропов/материалов, что в pakfile
python3 tools/gmodkit.py bsp info maps/rp_city.bsp

# что за энтити стоят на карте и сколько их
python3 tools/gmodkit.py bsp classes maps/rp_city.bsp
python3 tools/gmodkit.py bsp entities maps/rp_city.bsp -c info_player_start

# модели static props (сводка) и поштучно с координатами
python3 tools/gmodkit.py bsp props maps/rp_city.bsp
python3 tools/gmodkit.py bsp props maps/rp_city.bsp --list --json

# встроенный в карту контент: посмотреть и распаковать
python3 tools/gmodkit.py bsp pak maps/rp_city.bsp
python3 tools/gmodkit.py bsp pak maps/rp_city.bsp --extract /tmp/pak

# что карте нужно из моделей и чего нет ни в паке, ни в репозитории
python3 tools/gmodkit.py bsp content maps/rp_city.bsp

# энтити карты → .vmf, чтобы открыть расстановку в Hammer
python3 tools/gmodkit.py bsp tovmf maps/rp_city.bsp -o /tmp/rp_city_ents.vmf --props
```

Правка энтити прямо в скомпилированной карте:

```bash
python3 tools/gmodkit.py bsp entities maps/rp_city.bsp --json > ents.json
# ... правим ents.json (массив объектов ключ-значение) ...
python3 tools/gmodkit.py bsp setent maps/rp_city.bsp ents.json -o maps/rp_city_v2.bsp
```

**Осторожно с game lump.** Энтити-лампа текстовая, её размер меняется, и
все последующие лампы съезжают. Директория game lump хранит АБСОЛЮТНЫЕ
смещения, а данные `sprp` у настоящего vbsp обычно лежат за объявленной
границей лампы. Инструмент это учитывает (переносит весь диапазон и правит
смещения), но проверка «пропы на месте» после пересборки обязательна —
в стенде она есть (`bsp: sprp за границей лампы`).

## Исходники карт

```bash
python3 tools/gmodkit.py vmf info map.vmf
python3 tools/gmodkit.py vmf materials map.vmf        # что натянуто на браши
python3 tools/gmodkit.py vmf entities map.vmf -c prop_static

# расстановка энтити GRM в исходник
python3 tools/gmodkit.py vmf add map.vmf grm_bank_terminal \
    --origin "1024 -512 16" --angles "0 90 0" --key model=models/starless/atm.mdl

python3 tools/gmodkit.py vmf move map.vmf info_player_start "0 0 8"
python3 tools/gmodkit.py vmf rotate map.vmf grm_payphone 90 --pivot "0 0 0"
python3 tools/gmodkit.py vmf remove map.vmf prop_ragdoll -o map_clean.vmf
```

## Модели

```bash
python3 tools/gmodkit.py mdl info models/starless/atm.mdl
python3 tools/gmodkit.py mdl materials models/starless/atm.mdl   # пути .vmt + есть/нет
python3 tools/gmodkit.py mdl bones models/player/kleiner.mdl
python3 tools/gmodkit.py mdl sequences models/player/kleiner.mdl
python3 tools/gmodkit.py mdl attachments models/weapons/w_pistol.mdl
python3 tools/gmodkit.py mdl scan models                          # обход каталога
```

`mdl materials` — первое, чем стоит проверять чужую модель: она печатает
ожидаемые пути `materials/<cdmaterials><texture>.vmt` и помечает, каких
нет в репозитории. Фиолетовая модель в игре — почти всегда именно это.

## SMD

```bash
python3 tools/gmodkit.py smd info ref.smd
python3 tools/gmodkit.py smd check ref.smd                 # веса вершин ≠ 1.0
python3 tools/gmodkit.py smd scale ref.smd 0.75 -o ref_small.smd
python3 tools/gmodkit.py smd move ref.smd "0 0 -4"
python3 tools/gmodkit.py smd rename-material ref.smd old_mat grm_mat
python3 tools/gmodkit.py smd rename-bone anim.smd ValveBiped.Bip01 bip01
python3 tools/gmodkit.py smd obj ref.smd                   # посмотреть меш чем угодно
python3 tools/gmodkit.py smd anim walk.smd 0 30 -o walk_short.smd
python3 tools/gmodkit.py smd qc ref.smd grm/atm.mdl --cdmaterials models/grm
python3 tools/gmodkit.py smd cube /tmp/test.smd --size 32   # фикстура/шаблон
```

## Мост в GRM

```bash
# точки спавна карты → spawn_points_global_<map>.json (sh_spawn_points.lua)
python3 tools/gmodkit.py grm spawns maps/rp_city.bsp --z-offset 2

# точки фракций по targetname → spawn_points_factions_<map>.json
python3 tools/gmodkit.py grm faction-spawns maps/rp_city.bsp \
    --map "spawn_police*=Полиция" --map "spawn_army*=Армия"

# метки карты → data/grm_perm_entities.json (Код 50, массив записей)
python3 tools/gmodkit.py grm perms maps/rp_city.bsp \
    --map "grm_atm_*=grm_bank_terminal" --map "grm_payphone_*=grm_payphone"

# аудит: какие модели/материалы упоминает Lua и чего нет в репозитории
python3 tools/gmodkit.py grm content

# полнота моделей репозитория: .vvd/.vtx на месте, все ли .vmt найдены
python3 tools/gmodkit.py grm models
```

Форматы выгрузки повторяют то, что читает аддон:

* глобальные точки — массив `{pos={x,y,z}, ang={p,y,r}}`;
* фракционные — `{Фракция = {points, roles, departments, subdepartments, positions}}`
  (единый формат, находка 157);
* пермы — **массив** записей `{map, class, model, pos, ang}` (Код 50; массив,
  а не карта с числовыми ключами — урок находки 65 про `util.JSONToTable`).

Файлы пишутся с read-back-проверкой, как и в Lua-персистентности.
Результаты по умолчанию складываются в `tools/gmodkit/out/` (в git не
попадают) — оттуда их кладут в `garrysmod/data/` на сервере.

## Устройство

```
tools/gmodkit.py          точка входа
tools/gmodkit/kv.py       KeyValues: лексер, дерево Node, запись
tools/gmodkit/bsp.py      BSP: лампы, энтити, материалы, sprp, pakfile
tools/gmodkit/vmf.py      VMF поверх kv + конвертация из BSP
tools/gmodkit/mdl.py      MDL/VVD/VTX/PHY
tools/gmodkit/smd.py      SMD: разбор, правки, OBJ, QC
tools/gmodkit/grmx.py     экспорт в данные GRM и аудит контента
tools/gmodkit/cli.py      разбор аргументов и печать
tools/gmodkit/selftest.py стенд (синтетический BSP + настоящие модели репо)
```

Правила модуля, выстраданные на форматах Valve:

1. **Ничего не падает на чужом файле.** Непонятная секция → пустой
   результат и строка в `warnings`, а не исключение: иначе одна кривая
   модель рушит отчёт по целому паку.
2. **Размер записи вычислять делением**, если версия структуры плавает
   (так сделано для `sprp` v4–v11): парсер переживает и мод-версии.
3. **Смещения в studiohdr считать по полному списку полей.** Между
   аттачментами и массой лежат три поля `localnode` — сдвиг на одно поле
   даёт «массу 1.97e-42» и сотню несуществующих includemodels. Стенд
   сверяет массу и surfaceprop из `.mdl` с теми же полями из `.phy` —
   это самый дешёвый детектор такого сдвига.
4. **Абсолютные смещения при пересборке файла надо править.** См. game lump.
5. Каждое изменение парсера — прогон `selftest`; на настоящих файлах
   (модели репозитория) он проверяется автоматически.

## Чего пока нет

Геометрия карты не декомпилируется (браши/дисплейсменты в VMF из BSP —
это отдельная большая задача уровня BSPSource), `.vtf` не разбирается,
`.vvd`/`.vtx` читаются только заголовками (вершины не извлекаются),
запись `.mdl` не поддерживается — компиляция моделей остаётся за
`studiomdl`, инструмент готовит для неё `.smd` и `.qc`.
