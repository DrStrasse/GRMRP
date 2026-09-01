# АУДИТ ПРОИЗВОДИТЕЛЬНОСТИ И КАЧЕСТВА — 2026-08-17

Полный скан всех 472 Lua-файлов (AST-анализ + проверка компиляции LuaJIT).
Цель — исключить микрофризы на сервере и клиенте, найти слабые места и
подозрительные паттерны.

> Формат замечаний: **[ИСПРАВЛЕНО]** / **[ЗАМЕЧАНИЕ]** / **[ПОДОЗРЕНИЕ]** /
> **[НАБЛЮДЕНИЕ]** с файлом, сутью и рекомендацией.

---

## 1. Исправлено в этой сессии

### 1.1 broadcastFactionData — коалесцинг
**[ИСПРАВЛЕНО]** `lua/autorun/sh_factions.lua`
Полная рассылка (синк NW всех игроков + сериализация всех фракций + broadcast всем +
клиентская пересборка UI) дёргалась при каждом действии фракции и раз в 10 с.
Одно действие тянуло цепочку вызовов. Теперь коалесцируется в ОДИН пакет за тик.

### 1.2 Factions_HUD — вложенный цикл
**[ИСПРАВЛЕНО]** `lua/autorun/sh_factions.lua`
HUD надписей над игроками для каждого ближнего игрока делал вложенный обход
ВСЕХ фракций (`O(игроки × фракции)` каждый кадр). Заменён на кэшируемый
обратный индекс `CharacterKey → {фракция, роль, цвет, тег}`, который строится
один раз при изменении `FactionsData` (O(1) на кадр).

### 1.3 fire_status — ents.FindByClass("vfire")
**[ИСПРАВЛЕНО]** `lua/autorun/sh_grm_fire_status.lua`
`countAround()` и проверка `#ents.FindByClass("vfire")` сканировали ВСЕ энтити
карты на каждом тике (и по одному разу на каждый активный инцидент). Заменены
на `GRM.Perf.Entities("vfire")` (event-реестр по OnEntityCreated/EntityRemoved).

### 1.4 rpdesc — wrapText каждый кадр
**[ИСПРАВЛЕНО]** `lua/autorun/sh_grm_rpdesc.lua`
`wrapText()` делал `surface.GetTextSize` на каждое слово текста описания — на
60 FPS × N ближних игроков это заметный оверхед. Добавлен кэш по
(текст, ширина) с ограничением размера (256 записей).

### 1.5 prop_protect — GetEyeTrace каждый кадр
**[ИСПРАВЛЕНО]** `lua/autorun/sh_grm_prop_protect.lua`
`lp:GetEyeTrace()` в HUDPaint выполнялся 60 раз/сек. Троттлен до ~10 Гц с
кэшированием результата между тиками.

### 1.6 Material() в кутсценах квестов
**[ИСПРАВЛЕНО]** `lua/autorun/client/cl_grm_quests.lua`
`Material()` создавался заново каждый кадр во время активной кутсцены.
Кэширован по пути картинки.

### 1.7 Антистак — ShouldCollide
**[ИСПРАВЛЕНО]** `lua/autorun/zz_grm_vehicle_antistuck.lua`
`ShouldCollide` вызывается движком для КАЖДОЙ пары сталкивающихся объектов
каждый тик; раньше всегда делался `pairKey()` (2×EntIndex + конкатенация) даже
при пустой таблице. Добавлен ранний выход `next() == nil` + периодическая
чистка истёкших no-collide пар.

### 1.8 goto как ключ таблицы
**[ИСПРАВЛЕНО]** `lua/autorun/sh_grm_jobs.lua`
`{ goto = "Доставка" }` — синтакс-ошибка LuaJIT («goto is a keyword»), из-за
которой модуль работ целиком не загружался. Закавычен: `{ ["goto"] = ... }`.

### 1.9 Сортировка селектора фракций
**[ИСПРАВЛЕНО]** `lua/autorun/client/cl_grm_factions_unified_ui.lua`
Селектор организаций в шапке и выбор первой фракции использовали `pairs(data)`
(недетерминированный порядок). Теперь сортировка по публичному имени.

---

## 2. Оставшиеся покадровые хуки (клиент, низкий/средний приоритет)

Ниже — полный список HUDPaint/Think/PostDraw/CalcView хуков с дорогими вызовами,
найденный сканом. Большинство уже обёрнуто в `GRM.Perf.Entities` или троттлится;
помечаю, что ещё стоит доработать при желании.

### 2.1 sv_grm_alarm — GRM_Alarm_Scan
**[НАБЛЮДЕНИЕ]** `lua/autorun/server/sv_grm_alarm.lua` (сервер)
Каждые 0.35 с для каждого АКТИВНОГО сенсора обходит `player.GetAll()` и делает
`util.TraceLine` на каждого игрока в радиусе. При многих сенсорах × многих
игроках — самый тяжёлый серверный периодический цикл.
Рекомендация: coarse-проверка `DistToSqr` уже есть (TraceLine вызывается только
для игрока в радиусе), но можно дополнительно кэшировать активные сенсоры в
массив и обновлять его событийно (как GRM.Perf), а не через `pairs(A.Devices)`.

### 2.2 sh_grm_rpdesc — player.GetAll + текст
**[НАБЛЮДЕНИЕ]** `lua/autorun/sh_grm_rpdesc.lua` (клиент)
Осталось: обход `player.GetAll()` + `GetPos():Distance` + отрисовка текста каждый
кадр (wrapText уже закэширован — см. 1.4). Некритично при малом числе игроков,
но можно добавить throttle обновления позиций (например, пересчёт каждые 0.1 с).

### 2.3 sh_factions — player.GetAll в HUD (частично)
**[НАБЛЮДЕНИЕ]** `lua/autorun/sh_factions.lua` (клиент)
Вложенный цикл убран (1.2), но `player.GetAll()` + distance-проверка остаются
покадрово. Допустимо.

### 2.4 cl_grm_handcuffs — PostDrawOpaqueRenderables
**[НАБЛЮДЕНИЕ]** `lua/autorun/client/cl_grm_handcuffs.lua` (клиент)
Обход `player.GetAll()` каждый кадр, но реальную работу делает только для
закованных игроков (редко). Можно кэшировать список закованных через NW-хук.

### 2.5 Прочие уже оптимизированные (не трогать)
`cl_grm_faction_logistics.lua`, `cl_grm_factory_fullcycle.lua`, `sh_grm_911.lua`,
`sh_grm_arrest.lua`, `sh_grm_incassation.lua`, `sh_grm_fire_truck.lua`,
`grm_ore_buyer/cl_init.lua`, `grm_vendor/cl_init.lua` — уже обёрнуты в
`GRM.Perf.Entities`. `sh_grm_cctv.lua`, `sh_grm_medical_full.lua`,
`sh_grm_narcotics.lua` — троттлены (0.2–0.25 с).

---

## 3. Периодические таймеры сервера (сводка)

| Интервал | Таймер | Файл | Оценка |
|---|---|---|---|
| 0.1 с | GRM_Weight_Update | sv_grm_encumbrance.lua | обход игроков, change-only NW — ок |
| 0.1 с | GRM_StaminaTick | sh_grm_movement.lua | обход игроков, sync троттлен 0.25с — ок |
| 0.25 с | GRM_MedFull_Tick / GRM_Narc_Tick | medical_full / narcotics | ок |
| 0.35 с | GRM_Alarm_Scan | sv_grm_alarm.lua | см. 2.1 |
| 0.35 с | GRM_Handcuffs_EnforceNoWeapons | sv_grm_handcuffs.lua | ок |
| 0.35 с | GRM_RN_FxWatch | sh_grm_radionet.lua | обход игроков — ок |
| 0.4 с | GRML_RouteThink | sv_grm_logistics.lua | ок |
| 0.5 с | GRM_BC_LiveWatch / GRM_Trunk_Watch / GRM_RN_Crackle | broadcast/trunk/radionet | ок |
| 0.8 с | GRM_Fire_StatusTick | sh_grm_fire_status.lua | исправлено (1.3) |
| 10 с | GRM_Roster_LiveSync | sh_grm_faction_roster.lua | намеренный full-sync |

---

## 4. Подозрения и слабые места (требуют проверки, не обязательно баги)

### 4.1 PlayerCanHearPlayersVoice — ents.FindByClass
**[ПОДОЗРЕНИЕ]** `lua/autorun/sh_grm_broadcast.lua`
Хук `PlayerCanHearPlayersVoice` внутри делает `ents.FindByClass("grm_radio")`.
Этот хук может вызываться часто (на каждый голосовой пакет). Хотя есть ранний
выход (`if not IsValid(mic) ... return`), при активном эфире через микрофон
сканирование всех радио происходит часто. Рекомендация: обернуть в
`GRM.Perf.Entities("grm_radio")`.

### 4.2 countAround — обход vfire на инцидент
**[ПОДОЗРЕНИЕ]** `lua/autorun/sh_grm_fire_status.lua` (частично исправлено в 1.3)
`countAround(origin)` вызывается по разу на каждый активный инцидент каждые
0.8 с. С кэшированным списком vfire это уже дешевле, но при большом пожаре
(много инцидентов) всё ещё O(инциденты × vfire). Приемлемо, но можно
дополнительно сгруппировать vfire в пространственные бакеты.

### 4.3 broadcastFactionData раз в 10 с
**[НАБЛЮДЕНИЕ]** `lua/autorun/sh_grm_faction_roster.lua`
`GRM_Roster_LiveSync` раз в 10 с вызывает `broadcastFactionData()` — намеренно
(чтобы `/members` показывал актуальные локации). Теперь, после коалесцинга,
это единичная рассылка, но сам `buildSyncData()` сериализует ВСЕ фракции и
ВСЕХ членов. Если фракций/членов много — стоит слать только изменившиеся
локации (инкрементальный синк), а не полную таблицу.

### 4.4 refreshAllUI пересобирает всё
**[НАБЛЮДЕНИЕ]** `lua/autorun/sh_factions.lua` (клиент)
`refreshAllUI` при каждом SYNC_ALL перестраивает комбобоксы, списки рангов,
отделов, участников, волну, инкассацию. Даже с коалесцингом серверной рассылки
клиент делает много работы. Рекомендация: пересобирать только реально открытые
вкладки (часть уже так и сделана — «живые» вкладки), но комбобоксы пересоздаются
полностью.

### 4.5 nameCache без ограничения
**[НАБЛЮДЕНИЕ]** `lua/autorun/sh_factions.lua` (клиент)
`nameCache[steamID]` растёт бесконечно (кеш имён через steamworks). При долгой
сессии с множеством игроков — незначительная утечка памяти. Не критично.

### 4.6 Material в HUDPaint (квесты) — остаточный
**[НАБЛЮДЕНИЕ]** `lua/autorun/client/cl_grm_quests.lua`
Кэш добавлен (1.6), но сам вызов `Material()` в ветке кэша — редкий (раз на
новую картинку). Ок.

---

## 5. Стилистические / структурные замечания

### 5.1 Имена net-сообщений в cl_grm_factions_unified_ui
**[ЗАМЕЧАНИЕ]** `lua/autorun/client/cl_grm_factions_unified_ui.lua`
`sendAction` слал несуществующее имя `Factions_AdminAction` — ИСПРАВЛЕНО на
`Factions_Action`. Рекомендация на будущее: вынести имена в shared-константы,
а не хардкодить строки по обе стороны.

### 5.2 Дублирование логики «лидер ли фракции»
**[ЗАМЕЧАНИЕ]** `sh_factions.lua`, `sh_faction_fixes.lua`, `sh_grm_faction_perms.lua`,
`sh_grm_factions_bridge.lua`
Проверка «является ли игрок лидером фракции X» реализована в 4+ местах
(локальные `isCharacterLeaderOfFaction`, `isFactionLeader`, `isLeaderOfFaction`,
`FactionsAPI.IsLeader`). Рекомендация: оставить один канонический через
`FactionsAPI.IsLeader` и использовать его везде — иначе правки лидер-логики
придётся синхронизировать в нескольких файлах.

### 5.3 GRM.FactionDuty.State на клиенте
**[ЗАМЕЧАНИЕ]** `cl_grm_factions_unified_ui.lua` (ИСПРАВЛЕНО ранее)
Клиент читал `GRM.FactionDuty.State[key]`, но эта таблица существует только на
сервере. Исправлено на `rec._dutyStatus` (сервер синхронизирует). Оставлен
fallback на `onDuty` — теперь мёртвая ветка, но безопасная.

---

## 6. Итог

- **Серверные микрофризы:** главные источники устранены (broadcastFactionData,
  fire_status, alarm отмечен как точка роста).
- **Клиентские микрофризы:** устранены вложенный цикл HUD фракций, wrapText,
  GetEyeTrace, Material в кутсценах.
- **Критичные баги:** ключ `goto` (блокировал jobs), несуществующее net-имя,
  мёртвая система доступов по ролям (исправлено ранее).
- **Рекомендуемые доработки:** инкрементальный синк `broadcastFactionData`,
  event-реестр сенсоров alarm, кэш радио в `PlayerCanHearPlayersVoice`,
  консолидация лидер-логики.
