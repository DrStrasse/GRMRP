# GRM — аудит зависаний и производительности

Дата: 17.08.2026. Ветка: `arena/01a00b1f-drstrasse`.

## Охват и принцип

Статическим проходом `tools/performance_audit.py` проверены **все 469 Lua-файлов**:

- 419 файлов GRM и интеграций;
- 50 файлов vendored EasyChat (учтены отдельно, без рискованной переписи стороннего API);
- frame hooks (`Think`, render/HUD hooks), быстрые бесконечные timers;
- глобальные обходы entity/player;
- disk/JSON в потенциально горячих путях;
- крупные `net.WriteTable` и сочетания нескольких факторов.

Сканер намеренно консервативен: совпадение является кандидатом на ручную проверку, а не автоматическим доказательством бага. После общего прохода вручную проверены найденные горячие циклы. Массовая замена timers, persistence и публичных API не выполнялась.

Запуск:

```bash
python3 tools/performance_audit.py --top 35
python3 tools/performance_audit.py --json > performance-audit.json
```

## Исправления первой безопасной волны

1. **Augmentation DoorHack**
   - удалён глобальный `ents.GetAll()` из каждого кадра;
   - активные взломанные двери ведутся в weak-key registry;
   - очистка ограничена частотой 2 Гц.

2. **CCTV server view guard**
   - death/distance/network fail-safe сохранён;
   - полный обход игроков ограничен 5 Гц вместо каждого server frame;
   - немедленные `PlayerDeath`, `PlayerSilentDeath`, disconnect hooks сохранены.

3. **Наркотики и расширенная медицина**
   - state loops ограничены 4 Гц;
   - реальные эффекты уже имели собственные интервалы 1–5 секунд, поэтому механика и величины урона/регенерации не изменены.

4. **Наручники, клиент**
   - удалён бессмысленный frame loop по всем игрокам;
   - костяная поза в текущей версии уже была отключена из-за несовместимых моделей, но код продолжал каждый кадр вызывать полный reset костей;
   - возможный след старой версии теперь сбрасывается один раз после загрузки.

5. **Alarm**
   - срочный scan датчиков оставлен с прежней конфигурационной частотой;
   - полный reconciliation динамиков отделён и выполняется раз в секунду.

6. **Stamina**
   - серверная физика продолжает считаться каждые 0.1 секунды;
   - network sync ограничен 4 Гц и отправляется только при изменении значения;
   - начальная синхронизация остаётся принудительной.

7. **Character menu guard**
   - закрытие чужого Mobile UI во время обязательного выбора персонажа ограничено 10 Гц вместо каждого кадра;
   - блокировка мира и меню не менялась.

8. **Q-menu icon queue**
   - устранён `table.remove(queue, 1)` с O(n) сдвигом массива на каждой иконке;
   - очередь теперь снимается с хвоста за O(1), визуальная привязка иконки к своей tile не меняется.

9. **Jobs / мусоровоз v5.2**
   - topology переведён с полного прохода каждые 2 секунды на entity/point events и fallback 10 секунд;
   - одинаковые NW state/int больше не отправляются повторно, устранено переключение фазы машины дважды за tick;
   - поиск мусоровоза при G ограничен сферой 230 вместо `ents.GetAll()`;
   - canonical vehicle validation кешируется на 0.5 секунды;
   - wireframe рабочего маркера уменьшен с 384 до 128 сегментов на кадр.

## Проверенные кандидаты, оставленные без изменения

- HUD/render hooks с быстрым ранним `return` и работой только при активном интерфейсе.
- Stamina server simulation 10 Гц: нужна для движения, оптимизирован только сетевой поток.
- Handcuffs server enforcement 0.25/0.35 сек: частота является частью освобождения и запрета оружия.
- Logistics route 0.4 сек: обход идёт по активным маршрутам, а не по всему миру.
- Alarm sensor scan: отвечает за тревогу; оптимизирован только несрочный speaker reconciliation.
- Inventory/trunk/RoomTap debounce и autosave: записи выполняются по dirty-state либо редким интервалам.
- Persistence read-back: дороже обычной записи, но обязателен для защиты RP-данных от тихой потери.
- `net.WriteTable` в административных снимках: вызывается по запросу, а не в frame loop. Перевод протоколов требует отдельной совместимой миграции.
- FireTruck NW scan и крупные RadioNet/Incassation loops отмечены для live-профилирования: без данных реального сервера замена registry может сломать сторонние simfphys/LVS сущности.

## Что статический аудит не может доказать

Для окончательного подтверждения нужны замеры на dedicated server с реальной картой, количеством props, simfphys/LVS транспортом и 20–60 игроками:

- `lua_run_cl print(1/FrameTime())` недостаточно — нужен server-side profiler;
- смотреть `sv`, frame time, net channel volume и spikes во время cleanup/load/save;
- отдельно нагрузить RadioNet, CCTV, Alarm, Fire, Incassation и массовое открытие Q/TAB;
- проверить cleanup/restart persistence без дублей.

## Вторая event-driven волна

Повторный проход охватывает **469 Lua-файлов** и вводит `GRM.Perf`:

- class registry строится один раз и обновляется `OnEntityCreated/EntityRemoved`;
- готовый массив entity переиспользуется до события изменения, без аллокации каждый кадр;
- общие `Throttle` и change-only `NWString/NWInt/NWBool/NWFloat`;
- Vendor/OreBuyer/Factory/Logistics/911/Arrest world labels переведены с кадрового `FindByClass` на registry;
- Trunk полностью убрал `FindByClass("*")` из render hook: открытые крышки отслеживаются NW-событием;
- Incassation и FireTruck больше не делают `ents.GetAll()` в render frame; произвольные vehicle-классы ведутся через NW-change registry с единственным bootstrap-сканом;
- FireTruck server sync идёт по насосам, а не по всем entity карты;
- Broadcast watcher использует registry микрофонов;
- idle SlidingDoor не вызывает физическое перемещение каждый frame;
- клиентская Regeneration больше не пересоздаёт один timer каждый Think;
- F2/F4/flashlight/breath/CCTV hook-table fallback checks ограничены по частоте;
- Quest objective mutations сохраняются одним batch на tick;
- Factory scrap refill создаёт один save batch для всех изменившихся мусорок;
- бесконечные dependency installers Encumbrance/Customization останавливаются после успешной установки;
- Economy vault mirror не отправляет неизменившийся budget;
- Mobile key repeat больше не создаёт временную таблицу каждый кадр;
- Accessory opaque fallback обходит только event-tracked active loadouts, кеширует model validation/bone index и не вызывает `SetupBones` у каждой ClientsideModel;
- Quest NPC/cutscene placement tool компилирует preview-геометрию раз в 0.5 с вместо создания Vector/Angle/link maps каждый render frame;
- Duty terminal получает фракции серверным событием без polling timer; стационарная entity переведена с `base_ai` на `base_anim`, удалены AI scheduler/capabilities и watchdog Think, idle обновляется только по spawn/model/Perm/restore-событиям.

Не заменялись частоты, являющиеся частью механики: движение/стамина, освобождение из наручников, Alarm sensors, активные Logistics routes и Fire hose simulation. Крупные сетевые snapshot-протоколы должны мигрировать отдельно с сохранением публичного wire-формата.
