# CONCEPT — Служебные компьютеры и оборудование (аудит)

**Дата:** 2026-08-16 · **Статус:** аудит «что есть / чего не хватает»
**База:** ветка `arena/01a00565-drstrasse`, находки 134–136

---

## 1. Служебные компьютеры (есть)

Все — энтити в `lua/entities/`, ставятся тулом `grm_service_tool` (STool «GRM
Служебное оборудование»), пермятся через `sh_grm_perm_entities.lua`
(`PERM_CLASSES`).

| Класс | Ведомство | Что делает |
|---|---|---|
| `grm_comp_police` | OrdnungPolizei (полиция порядка) | розыск, штрафы, паспорта, ксивы `POL-`, фото к делу |
| `grm_comp_military_police` | Feldgendarmerie (полевая жандармерия) | военный розыск (дезертиры/СОЧ), взыскания, военники, ксивы `FELD-` |
| `grm_comp_security` | Gestapo / Komitet (спецслужбы) | надзор, сводное досье, Cover Lab прикрытия, ксивы `GST-` |
| `grm_comp_military` | Военкомат | военные билеты, призыв/мобрезерв, ВВК |
| `grm_comp_traffic` | Автоинспекция (ГАИ + ВАИ) | права A–E+СПЕЦ и ВАИ, **теперь + теория-экзамен ПДД** (находка 135) |
| `grm_comp_medical` | Госпиталь | медкарты, категории годности, приёмы, справки |
| `grm_comp_education` | Учреждение образования (деканат) | гос. дипломы |
| `grm_doc_computer` | Универсальный отдел кадров | паспорта/ксивы/права/военники/прикрытие/лицензии/реестр |
| `grm_bank_computer` | Банк | хранилище ↔ казна ↔ станок, распределение |
| `grm_bank_terminal` | Банкомат (для всех) | счёт/наличные/переводы/инкассация |

`grm_net_console` — пульт **радиосети** (не компьютер, но служебный терминал).

---

## 2. Служебное оборудование (есть, не компьютеры)

- **Связь:** `grm_phone`, `grm_payphone`, `grm_pbx_station` (АТС), `grm_phone_terminal`, `grm_phone_wiretap`, `grm_roomtap_server/terminal/chip`, `grm_mobile_line`.
- **Радио/оповещение:** `grm_radio`, `grm_radio_station`, `grm_server_rack`, `grm_antenna`, `grm_loudspeaker`, `grm_broadcast_mic`, `grm_net_console`.
- **CCTV:** `grm_cctv_camera/monitor/server`.
- **Сигнализация:** `grm_alarm_hub/sensor/speaker/terminal`.
- **Банк/деньги:** `grm_bank_vault`, `grm_vault_cash`, `grm_money_press/printer/press_terminal`, `grm_money_launderer`.
- **Аугментации/чипы:** `grm_augmentation_station/pod/chip`, `grm_chip_terminal`.
- **Прочее:** `grm_keypad`, `grm_scanner`, `grm_arrest_camera`, `grm_wardrobe`, `grm_vendor`, `grm_jobcenter`, `grm_board`, `grm_depot`, `grm_med_lab`, `grm_narc_lab`, `grm_citadel_core(+terminal)`.

Тулы размещения: `grm_service_tool` (8 компьютеров), `grm_bank_tool` (банк),
`grm_perm_tool` (пермы), `grm_door_admin`/`grm_sliding_door`/`ffd_*` (двери),
`grm_minimap`, `grm_quest_tool`, `grm_vendor_tool`, `grm_lab_tool`,
`grm_augmentation`, `grm_citadel_core`, `grm_arrest_zone`.

---

## 3. Чего НЕ хватает (по существующим системам)

| # | Пробел | Обоснование | Предлагаемый класс | Статус |
|---|---|---|---|---|
| 1 | **Компьютер пожарной службы** | Система пожаров (Код 58) есть полностью — машины, `grm_fire_*`, `/fire_access`, `/fire_trucks`, `/fire_log`, очаги, — но управляется только чат-командами; своего терминала нет | `grm_comp_fire` | ✅ сделано (находка 137) |
| 2 | **Компьютер юстиции (суд/прокуратура)** | В госуслугах есть категория `legal`, в документах тиснение «[Суд] Весы правосудия»; компьютера юстиции нет | `grm_comp_court` / `grm_comp_justice` | ✅ сделано (находка 139) |
| 3 | **Компьютер мэрии / городской администрации** | Бизнес-лицензии выдаёт Department of Labour and Social Protection через общий `grm_doc_computer`; отдельной станции администрации нет | `grm_comp_cityhall` | ✅ сделано (находка 137) |
| 4 | **ОЛРР (лицензионно-разрешительная работа)** | Лицензия на оружие сейчас — вкладка «Оружие» `grm_doc_computer`. Отдельный компьютер ОЛРР — опционально, не критично | `grm_comp_olrr` | 🔜 опц. |
| 5 | **Аптека / медлаборатория** | `grm_med_lab` (лаборатория) есть, но терминал аптеки/рецептов не выделен (медкарты — в `grm_comp_medical`) | `grm_comp_pharmacy` (опц.) | 🔜 опц. |

Инкассация отдельного компьютера не требует — покрыта банком
(`grm_bank_terminal` + `grm_bank_vault` + `grm_bank_computer`).

---

## 4. Рекомендация по приоритету

1. **`grm_comp_fire`** — самый явный пробел: целая подсистема без UI-станции.
2. **`grm_comp_cityhall`** — вывести выдачу бизнес-лицензий/госуслуг из
   универсального `grm_doc_computer` в профильный компьютер администрации.
3. **`grm_comp_court`** — если нужна полноценная юридическая ветка
   (дела, приговоры, штрафы по суду).
4. ОЛРР/аптека — по желанию, закрывается `grm_doc_computer`/`grm_comp_medical`.
