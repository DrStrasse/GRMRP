# ANALYSIS — «Github DLC GRM.zip»

**Дата:** 2026-08-16 · **Источник:** коммит `f5017c5` «Add files via upload» на `arena/01a00565-drstrasse`
**Архив:** `Github DLC GRM.zip` (11 МБ → 22 МБ, 296 файлов)

> DLC-аддон для GRM: **MapStudio** (внутриигровой картостроитель) + **лифты**
> (Hightower) + **ведьмачьи двери/порталы** + **кастомный скин UI** + **stacker**.
> Отдельно разбор рендер-техник — в `ANALYSIS_RENDER.md`.

---

## 1. MapStudio — полноценный картостроитель на Lua

Загрузчик `lua/autorun/mapstudio_loader.lua` подключает по спискам:

| Слой | Файлы | Что делает |
|---|---|---|
| shared | `sh_config/sh_language/sh_net/sh_permissions/sh_objects/sh_placement/sh_core` | конфиг, локализация (ru/en), сеть, права, модель «объектов», размещение |
| tools | `sh_registry + sh_{select,prop,move,rotate,scale,delete}_tool` | реестр инструментов + 6 тулов редактирования |
| server | `sv_permissions/sv_storage/sv_spawner/sv_protection/sv_import_permaprops/sv_net/sv_init` | права, хранение объектов, спавн, защита, импорт пропов карты |
| client | `cl_theme/cl_grid/cl_ghost/cl_gizmo/cl_freecam/cl_asset_browser/cl_object_list/cl_inspector/cl_undo/cl_settings/cl_spawnmenu/cl_notifications/cl_editor/cl_init` | тема, сетка, призрак, гизмо, свободная камера, браузер ассетов, список объектов, инспектор, undo, настройки, спавн-меню |
| vgui | `ms_panel/ms_button/ms_textentry/ms_frame/ms_model_card/ms_property_row` | **свой набор виджетов** (заменяет Derma там, где нужен свой вид) |

Плюс `lua/vgui/dproperties.lua` — панель свойств.

**Ценность для GRM:**
- Это готовый референс «редактор карты в игре» (ракурс, сетка, гизмо, undo, список
  объектов). Если владелец захочет «строительный» инструментарий — брать структуру
  отсюда, а не писать с нуля.
- Паттерн **своих VGUI-виджетов** (`ms_*`) + `sh_language.lua` с переводами ru/en —
  ровно «нормальный UI с кнопками», о котором владелец говорил по бирже труда.
- Рендер: ghost-превью, сетка, гизмо — см. `ANALYSIS_RENDER.md` §4–6.

## 2. ht_elevator_floor — лифт (Hightower)

`lua/entities/ht_elevator_floor/{shared,init,cl_init}.lua` + тул `ht_elevator.lua` +
много моделей/материалов (`models/hightower/construction/elevator*` и
`models/mark2580/.../office_elevator*`).

- **Клиент** (`cl_init.lua` 22 КБ): `ENT:DrawTranslucent()` рисует 3D2D-панели
  (табло этажа, кнопки вызова, дисплей уровня) — см. `ANALYSIS_RENDER.md` §1.
  Хит-детект кнопок в `Think` каждый кадр (комментарий «Force Think to run every
  frame so 3D2D hit detection NEVER lags»).
- **Сервер** (`init.lua` 27 КБ): логика этажей, движение кабины, вызовы.
- Шрифты экрана: `HT_Lantern_Small/Large`, `HT_Level_Label/Number`, `HT_Chevron`.

## 3. witcher_door / witcher_gateway — порталы

`lua/entities/witcher_{door,gateway}/shared.lua` + тул `witchergate.lua` +
`lua/effects/portal_inhale/init.lua` + звуки `sound/portal/*`.

- **Серверная часть**: `Enable/Disable`, `SetColour`, телепорт-логика в
  `StartTouch/Touch` (кто вошёл — переносится), `TransformOffset/GetFloorOffset/
  GetOffsets/GetPortalAngleOffsets` — расчёт точки выхода/поворота между парой порталов.
- **Клиентская часть**: stencil-дыра + ClientsideModel-рамка + DynamicLight
  (см. `ANALYSIS_RENDER.md` §3). `SetMaterial("vgui/black")` — чёрная «дыра».
- `sh_witcherdoorutil.lua`: `HSLToColor`, регистрация звуков, `resource.AddWorkshop("727161410")`.
- Эффект `portal_inhale` — частицы «втягивания» при активации.
→ Полезно для «проходов/шлюзов» (в GRM есть FFD-двери — можно добавить «портал»).

## 4. cieroskin — кастомный Derma-скин

`cl_cieroskin.lua` (35 КБ) + `cl_cieroskint.lua` (34 КБ) + `cl_swapskin.lua`.
Полный переопределённый скин (см. `ANALYSIS_RENDER.md` §5). `swapskin` — переключение
между скинами.

## 5. stacker + debug-хелперы

- `stacker.lua` — тул «стопка пропов» (стак пропов с фризом/сваркой/ноколлайдом,
  ghost-превью стопки).
- `ht_debug_rotation.lua` / `ht_debug_position.lua` — служебные дебаг-хелперы лифта.

---

## 6. Что из DLC применимо к GRM

1. **MapStudio** — источник идей для «строительных» тулов GRM (наш `grm_service_tool`,
   `grm_perm_tool`): ghost-превью, гизмо, undo, список объектов.
2. **Лифт** — готовый образец «энтити с 3D2D-панелью и кнопками» (полезно для
   панелей лифтов/шлюзов в RP).
3. **Портал** — образец «прохода» со stencil-рендером; можно сделать «FFD-портал».
4. **Ciero skin** — если владелец снова попросит «красивый UI» — за основу скин целиком.
5. **Свои VGUI-виджеты + локализация ru/en** — паттерн для переработки UI биржи/терминалов.

## 7. Предупреждения
- В аддоне много дублей материалов (`welker/...`, `hightower/...`, `... - copy.vmt`) —
  признак сборки «как есть», без чистки.
- `resource.AddWorkshop("727161410")` — внешняя зависимость портала.
- Код стиля старых аддонов (`!=`, `\r\n`) — работает, но это не образец стиля.
- В git положен только сам архив `Github DLC GRM.zip`; код не копировался.
