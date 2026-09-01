# ARCHITECTURE — детальный инвентарь GRM

Этот документ — справочник по всем модулям, энтити, оружию, тулзам, контрактам
ядра, сетевому слою и data-файлам. Для понимания «как всё связано» и для
безопасных правок.

---

## 1. Ядро (GRM Core v1) — `lua/autorun/sh_00..sh_06`

| Файл | Namespace | Назначение |
|---|---|---|
| `sh_00_grm_ui.lua` | `GRM.UI` | lifecycle-гвард окон (`Track/Close/IsOpen`), UTF-8 безопасная обрезка (`Utf8Sub`, `Utf8Ellipsis`) |
| `sh_01_grm_core.lua` | `GRM.Core`, `GRM.Lang` | версии, правила, локализация ru/en |
| `sh_02_grm_persistence.lua` | `GRM.Persistence` | безопасный JSON (version → decode → normalize → quarantine → write → read-back → verify), реестр backend |
| `sh_03_grm_access.lua` | `GRM.Access` | capability registry, назначения everyone/faction/role/department/account/character |
| `sh_04_grm_net.lua` | `GRM.Net` | guard (rate/burst/maxBits/дистанция/capability), нормализация String/Number |
| `sh_05_grm_audit.lua` | `GRM.Audit` | append-only JSONL-журнал `data/grm_core/audit/YYYY-MM-DD.jsonl` |
| `sh_06_grm_performance.lua` | `GRM.Perf` | event-реестры entity (`Entities/ForEach`), `Throttle`, change-only NW (`NWString/NWInt/NWBool/NWFloat`) |

**Идентификаторы:** capability `domain.resource.action`; net guard key и audit
action — `resource.action`; hook — `GRM_<Domain><PastTense>`; backend — короткое имя
(`perm`, `vendor`, `cctv`, `radionet`).

---

## 2. Модули (180 файлов в `lua/autorun/`)

### Фракции
| Файл | Назначение |
|---|---|
| `sh_factions.lua` | Ядро фракций: ранги, отделы, приглашения v2, госволна `/dep` `/depb`, меню `/factions`, создание/переименование |
| `sh_faction_fixes.lua` | Расширение: комендантский час `/kom_hour`, модели+bodygroups, оружие по рангам, маскировка V2, `/gnews`, арсенал/гардероб |
| `sh_grm_faction_duty.lua` | Служба фракций (`/duty`, NPC `grm_duty_npc`) |
| `sh_grm_faction_economy.lua` | Фасад доступов по ролям к экономике |
| `sh_grm_faction_perms.lua` | Доступы по ролям (бюджеты, налоги, штрафы, законы, инкассация, перм) — сетевая синхронизация v2.1 |
| `sh_grm_faction_personnel.lua` | Кадровые дела (досье, взыскания, благодарности, испытательный срок) |
| `sh_grm_faction_roster.lua` | `/members` `/состав`, `/leaders` `/лидеры`, live-sync |
| `sh_grm_factions_bridge.lua` | Мост доступов доска/эфир/оповещения/биржа (`GRM_FAcc_*`) |
| `sh_grm_factions_core_v4.lua` | Структура v5.0 «Отделы ➔ Подотделы», кадровая история |

### Экономика и финансы
| Файл | Назначение |
|---|---|
| `sh_grm_currency.lua` | Валюта: `GRM.GiveMoney/TakeMoney/HasMoney/GetBalance/SetBalance/Format/Notify` |
| `sh_grm_economy.lua` | Единая экономика: бюджеты/налоги/зарплаты, банк, штрафы, `/salary_admin`, импорт legacy |
| `sh_grm_atm.lua` | Банкоматы |
| `sh_grm_incassation.lua` | Инкассация (рейсы, хранилища, терминалы) |
| `sh_grm_feco_admin.lua` | Панель экономики (`grm_feco`) |
| `sh_grm_admin_menu.lua` | Эконом-админ панель (`!grmmenu`/`!econadmin`) |
| `sh_grm_admin_hub.lua` | Единая админ-панель (Экономика/Сервер/Доступы/Инструменты/Биржа/Игроки) |

### Документы и удостоверения
| Файл | Назначение |
|---|---|
| `sh_grm_documents.lua` | Паспорта, удостоверения, военник, права, медкарты |
| `sh_grm_physical_documents.lua` | Физические бланки, `/docrestore`, поколения |
| `sh_grm_diplomas.lua` | Дипломы об образовании |
| `sh_grm_education.lua` | Дипломы v2.0 (бланк, показ, `/showdiploma`) |
| `sh_grm_ctx.lua` | Показ/приём документов |

### Розыск и штрафы
| Файл | Назначение |
|---|---|
| `sh_grm_wanted_config.lua` | Каталог статей, уровни |
| `sh_grm_wanted_access.lua` | Доступы к розыску |
| `sh_grm_wanted_fines.lua` | Штрафы |
| `sh_grm_wanted_board.lua` | Лист розыска, `/grm_wantedlist` |
| `sh_grm_wanted_bulletins.lua` | Ориентировки |
| `sh_grm_wanted_exchange.lua` | Обмен сведениями между ведомствами |
| `sh_grm_special_service.lua` | Спецслужбы |

### Связь и наблюдение
| Файл | Назначение |
|---|---|
| `sh_grm_broadcast.lua` | Радиоэфиры у микрофонов, оповещения `/alert`, `/bcast` |
| `sh_grm_radionet.lua` | Радиосеть |
| `sh_grm_board.lua` | Доска набора (`/board`) |
| `sh_grm_news.lua` | Новости (`/gnews`) |
| `sh_grm_phone_config.lua` / `sh_grm_phone_shop.lua` / `sh_grm_phone_access.lua` | Телефония, магазин, доступ |
| `sh_grm_cctv_config.lua` / `sh_grm_cctv_access.lua` | CCTV |
| `sh_grm_roomtap_config.lua` | Прослушка RoomTap |
| `sh_grm_chip_control.lua` | Чипы слежения |

### Службы и работы
| Файл | Назначение |
|---|---|
| `sh_grm_jobs.lua` + `_config` + `_v4`/`_v5` | Биржа труда (курьер/мусоровоз/таксист) |
| `sh_grm_industry_core.lua` | Производство и логистика: справочник, рецепты, качество, награды (чистые функции) |
| `sh_grm_industry_container.lua` | Единая ёмкость: станок, склад, грузовик, инвентарь игрока |
| `sh_grm_industry_entities.lua` | Узлы цеха и логистики (7 ролей, регистрация) |
| `server/sv_grm_industry.lua` | Задачи, мини-игра, износ, рынок, сырьё |
| `server/sv_grm_industry_logistics.lua` | Заказы складов, рейсы, грузовые отсеки |
| `weapons/gmod_tool/stools/grm_industry.lua` | Инструмент установки и наладки узлов |
| `sh_grm_911.lua` | Система 911 (ранения, реанимация, морг) |
| `sh_grm_medical.lua` / `sh_grm_medical_full.lua` | Медицина |

### Прочее
| Файл | Назначение |
|---|---|
| `sh_grm_inventory.lua` | Инвентарь v1.7 |
| `sh_grm_identity.lua` | AccountKey/CharacterKey |
| `sh_grm_doors.lua` / `sh_grm_doors_access.lua` | Двери v4.0, доступ |
| `sh_grm_property.lua` | Недвижимость |
| `sh_grm_qmenu.lua` | Q-меню «Стройка» v5.1 |
| `sh_grm_character.lua` / `sh_grm_customization.lua` | Персонаж, аксессуары |
| `sh_grm_fire*.lua` | Пожарная служба |
| `sh_grm_achievements.lua` / `sh_grm_quests.lua` | Ачивки, квесты |
| `sh_grm_augmentation*.lua` | Аугментации/импланты |
| `sh_grm_movement.lua` | Стамина |
| `sh_grm_minimap.lua` | GPS-точки и навигация |
| `sh_grm_prop_protect.lua` / `sh_grm_perm_entities.lua` | Защита/перм объектов |
| `sh_grm_rootguard.lua` | Root Guard (подтверждение владельца на опасные действия) |
| `sh_grm_tickets.lua` | Тикеты |
| `sh_grm_laws.lua` | Законы |
| `sh_grm_arrest.lua` | Аресты |
| `sh_grm_handcuffs_config.lua` | Наручники |
| `sh_grm_narcotics.lua` / `sh_grm_mining.lua` / `sh_grm_ore_*` | Наркотики, шахта, руда |
| `sh_grm_food_config.lua` / `sh_grm_food_kitchen.lua` | Еда |
| `sh_grm_trunk.lua` | Багажники |
| `sh_grm_vehicle_access.lua` / `sh_grm_vehicle_dealer.lua` / `sh_vehicle_keys.lua` | Транспорт |
| `zz_grm_vehicle_antistuck.lua` | Антистак/антиколлизия транспорта |
| `sh_grm_vendor.lua` | Торговцы |
| `sh_grm_chat_config.lua` / `sh_grm_rp_chat.lua` / `sh_grm_rpdesc.lua` | Чат и RP-описания |

> Клиентские панели — в `lua/autorun/client/` (35 файлов): `cl_grm_factions_unified_ui.lua`,
> `cl_grm_inventory_ui.lua`, `cl_grm_cctv.lua`, `cl_grm_phone.lua`, `cl_grm_quests.lua` и т.д.
> Серверные — в `lua/autorun/server/` (23 файла): `sv_grm_industry.lua`,
> `sv_grm_industry_logistics.lua`, `sv_grm_phone.lua`, `sv_grm_cctv.lua` и т.д.

---

## 3. Энтити (`lua/entities/`, ~76 классов)

`grm_alarm_hub`, `grm_alarm_sensor`, `grm_alarm_speaker`, `grm_alarm_terminal`,
`grm_antenna`, `grm_arrest_camera`, `grm_augmentation_chip`, `grm_augmentation_pod`,
`grm_augmentation_station`, `grm_bank_computer`, `grm_bank_terminal`, `grm_bank_vault`,
`grm_board`, `grm_broadcast_mic`, `grm_cctv_camera`, `grm_cctv_monitor`, `grm_cctv_server`,
`grm_chip_terminal`, `grm_citadel_core`, `grm_citadel_core_terminal`, `grm_comp_cityhall`,
`grm_comp_court`, `grm_comp_education`, `grm_comp_fire`, `grm_comp_medical`,
`grm_comp_military`, `grm_comp_military_police`, `grm_comp_police`, `grm_comp_security`,
`grm_comp_traffic`, `grm_depot`, `grm_doc_computer`, `grm_duty_npc`, `grm_food_fridge`,
`grm_food_planter`, `grm_food_stove`, `grm_garbage_bin`, `grm_garbage_box`, `grm_item_drop`,
`grm_jobcenter`, `grm_keypad`, `grm_loudspeaker`, `grm_med_lab`, `grm_mobile_line`,
`grm_money_drop`, `grm_money_launderer`, `grm_money_press`, `grm_money_press_terminal`,
`grm_money_printer`, `grm_narc_lab`, `grm_net_console`, `grm_ore_buyer`, `grm_ore_chunk`,
`grm_ore_node`, `grm_payphone`, `grm_pbx_station`, `grm_phone`, `grm_phone_terminal`,
`grm_phone_wiretap`, `grm_quest_npc`, `grm_radio`, `grm_radio_station`, `grm_roomtap_chip`,
`grm_roomtap_server`, `grm_roomtap_terminal`, `grm_scanner`, `grm_server_rack`,
`grm_vault_cash`, `grm_vendor`, `grm_wardrobe`, `sent_vehicle_dealer`.

---

## 4. Оружие и тулзы (`lua/weapons/`)

**SWEP:** `ds_battering_ram`, `ds_key_swep`, `ds_lockpick`, `grm_cuffed`,
`grm_handcuffs`, `weapon_grm_electro_baton`, `weapon_grm_incass_bag`,
`weapon_grm_megaphone`, `weapon_grm_search`.

**Тулзы (`gmod_tool/stools/`):** `fading_door`, `ffd_fading_door`, `ffd_keypad`,
`ffd_link`, `ffd_scanner`, `grm_arrest_zone`, `grm_augmentation`, `grm_bank_tool`,
`grm_citadel_core`, `grm_door_admin`, `grm_duty_npc`, `grm_jobs`, `grm_lab_tool`,
`grm_minimap`, `grm_perm_tool`, `grm_property`, `grm_quest_tool`, `grm_service_tool`,
`grm_sliding_door`, `grm_vendor_tool`, `vehicle_dealer_tool`.

---

## 4.5. Отдельные аддоны (`addons/`)

Ставятся рядом с `addons/grm` (основным) и собираются в свои архивы.

| Папка | Архив | Что это |
|---|---|---|
| `addons/grm_addon_studio/` | `dist/grm_addon_studio.zip` | Студия аддона: каталог узлов (34 шт.), манифест, виджеты/шаблоны макета (`A.SnapRect`/`A.GrowRect`/`A.MoveRect`, `A.Validate`, `A.CheckSyntax`), генератор GLua + тул размещения (sh); сервер: права, net (чанки 8 КБ), сохранение проектов/снимков в `data/grm_studio/` (sv); клиент: граф, палитра, инспектор, 3D-вьюпорт с гизмо («СЦЕНА»), конструктор окон (12 виджетов), предпросмотр, проверка, компиляция (cl) |
| `addons/grm_fire/` | (вручную) | Пожарный аддон: vFire-пак, рукава, гидранты, насосы |
| `addons/grm_textscreens/` | `dist/grm_textscreens.zip` | 3D2D Textscreens (сторонний аддон, только пакуется) |

В `lua/` студии нет — она не входит в `grm_single_addon.zip`. Зависимости от
основного GRM (шрифты темы, `GRM.Persistence`, `GRM.Gizmo`) опциональны:
без основного аддона студия открывается, сохранение честно отказывает
`no_grm_persistence`.

---

## 5. Файлы данных (garrysmod/data)

```
factions.json                  — фракции (члены, роли, отделы, подотделы, казна, кадры)
invites.json                   — приглашения v2
factions_extended.json         — маскировка/модели/оружие/комендантский час
fw_faction_extras.json         — extras фракций
default_models.json            — модели по умолчанию
default_weapons.json           — оружие по умолчанию
grm_inventories.json           — инвентари
grm_economy.json               — экономика (бюджеты, налоги, зарплаты, счета)
grm_currency.json              — валюта/кошельки
grm_faction_perms.json         — доступы по ролям
grm_faction_duty.json          — статус службы по CharacterKey
grm_wallet.json                — внешний писатель (безвреден, см. HANDOVER)
gnews_log.txt                  — лог госновостей
grm_industry/                  — узлы, задачи, заказы: map_<map>.json + orders_<map>.json
grm_studio/                    — проекты студии аддонов: <slug>.json
grm_studio/shots/              — снимки студии: <slug>_<nnn>.jpg
grm_admin_log.json             — админ-лог
grm_player_taxes.json          — налоги игроков
spawn_points_global_<map>.json — глобальные спавнпоинты
spawn_points_factions_<map>.json
grm_vehicle_purchases.json     — купленный транспорт
grm_vehicle_prices.json
grm_faction_vehicle_access.json
vd_spawn_log.txt
grm_phone/                     — access, shop_catalog, shop_purchases, player_equipment, <map>.json
grm_phone_records/<date>.txt   — записи звонков
grm_fire/log.json              — журнал тушения пожаров
grm_core/access_grants.json    — назначения прав ядра
grm_core/audit/YYYY-MM-DD.jsonl — общий аудит
```

---

## 6. Команды (сводка)

**Игрок:** `/inv`, `/store`, `/fjoin`, `/fleave`, `/fr`, `/dep`, `/depb`, `/mask`,
`/model`, `/gnews`, `/kom_hour`, `/logistics_start`, `/logistics_crates`, `!fbudget`,
`!fpay`, `!fwithdraw`, `!fpayall`, `!fsettax`, `/mysalary`, `/fine <сумма> [причина]`,
`/vlist`, `/myvehicles`, `/vshop`, `/phoneshop` (`/teleshop`), `/phone_remove`,
`/duty`, `/members` `/состав`, `/leaders` `/лидеры`, `/time` `/время`, `/911`.

**Лидер фракции:** `/vaccess`.

**Админ:** `/factions`, `/fmenu` `/фракция`, `/door_access`, `/door`, `/warrant`,
`/salary_admin`, `/logistics_admin`, `/models_admin`, `/weapons_admin`, `/mask_admin`,
`!grmmenu`/`!grmadmin`/`!econadmin`, `/scanvehicles`, `/spawnmenu`, `/vshop_admin`,
`/phoneshop_admin`, `/phone_access`, `/phone_admin_remove`, `/grm_access` `/доступы`,
`/faction_perms`, `/grm_wanted`, `/grm_cctv_access`, `/roomtap_access`, `/roomtap_shop`,
`/studio` `/адонстудия` `/addonstudio` — студия аддонов (суперадмин).

**Консольные (админ):** `grm_logistics_place_*`, `grm_logistics_save/load`,
`grm_logistics_admin_menu`, `grm_logistics_crates`, `grm_fc_save/load`,
`grm_weapon_buyer_admin`, `grm_adminmenu`, `econadmin`, `grm_antistuck_vehicle`,
`grm_phone_save/load`, `grm_phone_shop_admin`, `grm_phone_access_reload`,
`grm_money <give|take|set|info|list|save>`, `grm_balance`, `grm_economy <save|list>`,
`grm_factions_menu`, `grm_faction_perms`, `grm_cctv_access`, `grm_wanted_access`,
`grm_augmentations_admin`, `grm_augmentation_access_admin`, `grm_phone_shop_admin`.

---

## 7. Сетевой слой (основные сообщения)

| Канал | Направление | Назначение |
|---|---|---|
| `Factions_GetData` / `Factions_SendData` / `Factions_SyncAll` / `Factions_Action` / `Factions_ActionResult` | C↔S | данные и действия фракций |
| `FactionsExt_Action` / `FactionsExt_Result` / `FactionsExt_Sync` / `FactionsExt_Curfew` | C↔S | расширение фракций (маскировка, комендантский час, госновости) |
| `GRM_FAcc_Get` / `GRM_FAcc_Set` / `GRM_FAcc_Data` | C↔S | мост доступов (доска/эфир/оповещения/биржа) |
| `GRM_FPerm_Get` / `GRM_FPerm_Set` / `GRM_FPerm_Data` | C↔S | доступы по ролям |
| `GRM_FactionDuty_*` | C↔S | служба фракций |
| `GRM_Jobs_Tracker` / `GRM_Jobs_*` | S→C | биржа труда (маршрут, маркеры) |
| `GRM_News_*` / `GNews_*` | C↔S | новости |

> **Важно:** клиент шлёт только намерение; сервер повторно проверяет право,
> дистанцию и валидность. Все имена должны быть зарегистрированы через
> `util.AddNetworkString` (сервер), иначе `net.Start` даст «unpooled message».

---

## 8. Производительность (краткий конспект)

- Покадровые хуки (`HUDPaint`, `Think`, `PostDraw*`, `CalcView`) — главный источник
  микрофризов. `ents.FindByClass`/`ents.GetAll`/`player.GetAll`/`util.Trace*` там —
  оборачивать в `GRM.Perf.Entities()` или троттлить.
- `broadcastFactionData()` коалесцирован (один пакет за тик).
- `ShouldCollide` — всегда ранний выход при пустой таблице пар.
- `Material()` в `HUDPaint` — кэшировать.
- Полный аудит всех файлов — `PERFORMANCE_AUDIT_2026.md` (в основной ветке).
