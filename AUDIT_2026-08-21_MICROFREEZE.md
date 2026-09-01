# АУДИТ 21.08.2026 — микрофризы, порядок выполнения и синхронизация

Заказ владельца: «синхронизация, разбитие на части и порядок выполнения кода,
проверка всех модулей ещё раз, чтобы ничего не вызывало микрофризы. Это
главное при написании любого последующего кода. Код должен выполняться по
степени важности, порционно».

## 1. Что уже держит нагрузку (было сделано ранее)

| Слой | Файл | За что отвечает |
|---|---|---|
| `GRM.Boot` v1.1 | `sh_00_grm_boot.lua` | СТАРТ по важности: `critical → early → normal → late → idle`, порциями по бюджету `grm_boot_budget_ms` на тик, зависимости, ленивые подсистемы по требованию |
| `GRM.Net` v1.1 | `sh_04_grm_net.lua` | `Guard` (лимиты на приём), `Stream` (большие таблицы уходят кусками, а не одним пакетом) |
| `GRM.Perf` v1.3 | `sh_06_grm_performance.lua` | `Queue`/`Spread` (рантайм-работа порциями по `grm_perf_budget_ms`), `Coalesce`, кэши игроков/сущностей/трейсов, детектор фризов |

## 2. Что добавлено этим ходом

### 2.1 `GRM.Save` v1.0.0 — очередь записи на диск (`sh_05_grm_save.lua`)

**Реальная причина микрофризов, которую он закрывает.** `file.Write` в GMod
синхронный: сервер стоит, пока файл пишется. Реестры сохранялись «на каждое
изменение» — вход игрока, выдача номера, каждое знакомство, каждый запрос по
госбазе. На заполненном сервере это очередь синхронных записей в одном тике.

Как теперь: модуль один раз регистрирует файл и функцию сборки, а в горячем
пути зовёт `GRM.Save.Mark(id)` — это установка флага. Писатель раз в секунду
берёт ОДИН просроченный грязный файл, сериализует и пишет; больше одной
записи за тик не делает. Дорогой реестр (сериализация дороже бюджета) сам
получает увеличенную задержку. При `ShutDown` и `PreCleanupMap` всё
сбрасывается. Статистика — `grm_save_status`, принудительная запись —
`grm_save_flush`.

Переведены: реестр номеров `ГР/ИГ`, знакомства и особые приметы шапки над
головой, журнал и доступы госбазы `/pcboard`.

### 2.2 Синхронизация: рассылки сведены в пачки

Широковещательные снимки уходят ВСЕМ игрокам сразу, и раньше они шли на
каждое изменение (галочка в панели прав, каждая точка на карте, каждый вход):

* `sh_factions.lua` — список персонажей (`GRM.Perf.Coalesce`, 0.5 с);
* `sh_grm_admin_core.lua` — снимок прав и групп (0.5 с);
* `sh_grm_qmenu.lua` — настройки Q-меню (0.5 с);
* `sh_grm_minimap.lua` — данные карты (0.25 с, важно при захвате точек).

Протокол не менялся — клиенты получают тот же пакет, просто один вместо
двадцати.

### 2.3 Точечные правки нагрузки

* `sh_grm_movement.lua` — тик стамины был 0.1 с (обход всех игроков 10 раз в
  секунду) при том, что клиенту значение уходит не чаще 4 раз в секунду.
  Теперь 0.25 с и расчёт по РЕАЛЬНОЙ дельте времени: скорости трат и
  восстановления не изменились, работы вдвое с лишним меньше.
* `sv_grm_handcuffs.lua` — второй таймер наручников (0.35 с) обходил всех
  игроков всегда; теперь, как и соседний, выходит сразу, если закованных нет.

### 2.4 Аудит стал воротами

`tools/audit_perf.py` дополнен проверками:

* **запись на диск в горячем пути** — `file.Write` внутри `net.Receive`,
  чат-команд, `PlayerUse`, `KeyPress`, `PlayerDeath` и таймеров чаще 30 с;
* **крупные синхронизации** — `net.WriteTable` + `net.Broadcast`, а также
  пакеты, склеенные из трёх и более таблиц;
* **тяжёлый вход игрока** — `PlayerInitialSpawn` с чтением файлов и полными
  снимками.

Исправлены и две ошибки самого аудита, из-за которых он врал:
* тело хука/таймера обрезалось по литералу `"\nend)"`, а в реальном коде
  закрывающая строка с отступом — в тело попадал соседний код и аудит
  показывал `file.Write` там, где его нет;
* тяжёлый вызов ПОСЛЕ раннего выхода (`if dt < порог then return end`)
  считался покадровым, хотя выполняется по редкому событию.

Режим ворот: `python3 tools/audit_perf.py --gate` — ненулевой код возврата,
если в коде появились запись на диск в горячем пути, старт мимо `GRM.Boot`,
`ENT:Think` без троттлинга или покадровый тяжеловес. **Это и есть правило
для любого последующего кода.**

## 3. Порядок действий при написании нового кода (памятка)

1. **Старт подсистемы** — только через `GRM.Boot.OnMapStart(id, tier, fn)`.
   Тир по важности: `critical` — ядро, `early` — до входа игроков, `normal` —
   игровая логика, `late` — журналы и чистки, `idle` — по требованию.
2. **Тяжёлый обход** (сотни дверей, все энтити, пересборка кэша) — через
   `GRM.Perf.Spread(id, list, fn)`, не одним куском.
3. **Событие пачкой** (галочки, точки, входы) — `GRM.Perf.Coalesce(key, delay, fn)`.
4. **Диск** — только `GRM.Save.Register` + `GRM.Save.Mark`. Прямой
   `file.Write` в обработчике события — ошибка, ворота её ловят.
5. **Большая таблица по сети** — `GRM.Net.Stream`, приём `GRM.Net.Receive`.
   Приём любого пакета от игрока — через `GRM.Net.Guard`.
6. **Покадровые хуки** — никаких `ents.FindByClass`, `player.GetAll`,
   `Material`, трейсов: есть `GRM.Perf.Entities/Players/Material/EyeTrace`.
   Своя работа в кадре — за ранним выходом по `CurTime()`.
7. **`ENT:Think`** — обязательный `SetNextThink` или проверка `CurTime()`.

## 4. Текущее состояние (вывод аудита на момент коммита)

```

=== ПОКАДРОВЫЕ ХУКИ С ТЯЖЁЛЫМИ ВЫЗОВАМИ (0) ===

=== ТАЙМЕРЫ ЧАЩЕ РАЗА В СЕКУНДУ (11) ===
   30  lua/autorun/server/sv_grm_handcuffs.lua                        строка 371: интервал 0.2 c
   17  lua/autorun/sh_grm_radionet.lua                                строка 437: интервал 0.35 c
   12  lua/autorun/sh_grm_arrest.lua                                  строка 468: интервал 0.5 c
   12  lua/autorun/sh_grm_broadcast.lua                               строка 309: интервал 0.5 c
   12  lua/autorun/sh_grm_radionet.lua                                строка 1324: интервал 0.5 c
   12  lua/entities/grm_citadel_core_terminal/cl_init.lua             строка 17: интервал 0.5 c
    8  lua/autorun/sh_grm_radionet.lua                                строка 952: интервал 0.7 c
    8  lua/autorun/server/sv_grm_handcuffs.lua                        [есть ранний выход] строка 1313: интервал 0.25 c
    5  lua/autorun/server/sv_grm_handcuffs.lua                        [есть ранний выход] строка 1327: интервал 0.35 c
    5  lua/autorun/server/sv_grm_logistics.lua                        [есть ранний выход] строка 629: интервал 0.4 c
    4  lua/autorun/sh_grm_trunk.lua                                   [есть ранний выход] строка 278: интервал 0.5 c

=== ЗАПИСЬ НА ДИСК В ГОРЯЧЕМ ПУТИ (0) ===

=== КРУПНЫЕ СИНХРОНИЗАЦИИ ОДНИМ ПАКЕТОМ (30) ===
    5  lua/autorun/sh_factions.lua                                    строка 500: net.WriteTable×1 + net.Broadcast — слать через GRM.Net.Stream
    5  lua/autorun/sh_grm_admin_core.lua                              строка 498: net.WriteTable×1 + net.Broadcast — слать через GRM.Net.Stream
    5  lua/autorun/sh_grm_customization.lua                           строка 439: net.WriteTable×1 + net.Broadcast — слать через GRM.Net.Stream
    5  lua/autorun/sh_grm_documents.lua                               строка 420: net.WriteTable×1 + net.Broadcast — слать через GRM.Net.Stream
    5  lua/autorun/sh_grm_faction_menu_access.lua                     строка 189: net.WriteTable×1 + net.Broadcast — слать через GRM.Net.Stream
    5  lua/autorun/sh_grm_qmenu.lua                                   строка 528: net.WriteTable×1 + net.Broadcast — слать через GRM.Net.Stream
    5  lua/autorun/sh_grm_minimap.lua                                 строка 60: net.WriteTable×1 + net.Broadcast — слать через GRM.Net.Stream
    5  lua/entities/grm_money_launderer/init.lua                      строка 288: net.WriteTable×1 + net.Broadcast — слать через GRM.Net.Stream
    3  lua/autorun/sh_03_grm_access.lua                               строка 240: 3 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_augmentations.lua                           строка 501: 3 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_cctv_access.lua                             строка 163: 3 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_doors.lua                                   строка 1775: 3 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_doors_access.lua                            строка 337: 3 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_factions_bridge.lua                         строка 59: 5 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_factions_bridge.lua                         строка 102: 5 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_fire_truck.lua                              строка 496: 4 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_jobs.lua                                    строка 888: 5 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_jobs_config.lua                             строка 241: 4 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_phone_access.lua                            строка 152: 3 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_special_service.lua                         строка 808: 7 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/sh_grm_vehicle_dealer.lua                          строка 407: 4 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/server/sv_grm_comp_terminal.lua                    строка 328: 7 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/server/sv_grm_comp_terminal.lua                    строка 537: 3 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/autorun/server/sv_grm_wanted.lua                           строка 182: 5 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/entities/grm_comp_cityhall/init.lua                        строка 113: 3 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/entities/grm_comp_court/init.lua                           строка 116: 7 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/entities/grm_comp_military/init.lua                        строка 76: 4 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/entities/grm_comp_security/init.lua                        строка 123: 7 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/entities/grm_comp_traffic/init.lua                         строка 76: 3 таблицы в одном пакете — разбить или слать через GRM.Net.Stream
    3  lua/entities/grm_doc_computer/init.lua                         строка 103: 3 таблицы в одном пакете — разбить или слать через GRM.Net.Stream

=== ТЯЖЁЛЫЙ ВХОД ИГРОКА (0) ===

=== ENT:Think БЕЗ ТРОТТЛИНГА (0) ===

=== СТАРТЫ ПОДСИСТЕМ МИМО GRM.Boot (0) ===

Всего находок: 41
```

Оставшиеся находки — не микрофризы, а осознанные компромиссы:
* таймеры 0.2–0.7 с у наручников, ареста, рации, логистики — короткие циклы
  с ранним выходом, работают только когда есть кого обслуживать;
* «крупные синхронизации» уровня 3 — это разовые снимки при открытии
  служебных терминалов (пакет одному игроку, а не всем); переводить их на
  `Stream` имеет смысл, если в базе появятся действительно большие объёмы.
