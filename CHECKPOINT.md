# CHECKPOINT — контрольная точка для следующего ИИ-агента

**Дата:** 2026-08-17 (вечер)  
**Ветка сессии:** `arena/01a010c8-drstrasse`  
**Состояние:** кодекс законов v2.0.0 (разделы общие/уголовные/административные/воинские/экономические, статьи с номером, заголовком и наказанием, редактор в окне, право `laws.edit`, синк частями), TAB-меню с аватарками Steam и пингом отдельной колонкой; потоковая передача больших синков частями (`GRM.Net.Stream`/`Receive`, сжатие + куски по 8 КБ: `factions.full`, `factions.ext`), метка взлома живёт 60 с и сама снимается (единая шкала `os.time()` + сторож карты), дедуп диспетчеров трогает только копии с одинаковым идентификатором; дельта-синк организаций (`Factions_SyncDelta`: только изменившиеся организации и только тем, кому нужны; было 45 КБ полного снимка всем на каждое изменение), диспетчеры службы больше не клонируются; валюта везде GRM (рублей в меню больше нет), список игроков в `/admin` строится из серверного среза + локального `player.GetAll()` и не моргает при синке; полное удаление документов (`/doc_wipe`, `/докстереть`, `grm_doc_wipe`, кнопки в `/admin`: чистит паспорта, удостоверения, прикрытие, военники, права, лицензии, экзамены, легенды спецслужбы и дипломы; право `docs.wipe`, подтверждение, аудит); модуль анализа нагрузки `GRM.Analytics` (сущности/двери/игроки/события/net, профили хуков и сети, выгрузка среза, раздел «Анализ нагрузки» в `/admin`), детектор фризов больше не считает фоновый клиент за рывки; вкладки `/factions` больше не сбрасываются в пустой экран (автосинк паркует панели модулей, разделы `ext:*` обновляют себя сами), цвета каналов по заказу (`/fr` — золотой текст + красный тэг, `/dep|/d|/depb|/db` — сплошной бордовый), `GRM.Perf` v1.3.0 с очередью фоновых задач (`Queue`/`Spread`, бюджет `grm_perf_budget_ms`, `grm_perf_queue`) и детектором фризов (`grm_perf_report` со срезом по simfphys/LVS); собственная админ-платформа GRM (`/admin`: игроки и модерация, привилегии с матрицей полномочий, назначения, сохранения карты, фракционный контроль, модули, раздел суперадмина; группы/права/иммунитет, синхронизация с ULX/ULib и CAMI — описание в `ADMIN_PLATFORM.md`), пожарные вызовы с принятием (Fire Dispatch v1.0.0: карточка «ПРИНЯТЬ / ОТКАЗАТЬСЯ», метка принявшему, напоминания, журнал вызовов), компьютер пожарной станции — только журналы; пожарные настройки добавлены в админ-хаб и единый центр управления, вкладки access-модулей (пожарные, сигнализация, двери/ордера, розыск, CCTV, телефония) переведены с подмены `OpenAdminMenu` на хук `GRM_FactionsAdmin_BuildTabs` и теперь видны в новом меню, боковое меню `/factions` прокручивается и уходит в два столбца; права разделов меню организаций (`GRM.MenuAccess`: чувствительное — суперадмину, он раздаёт лидерам, раздел «Права меню» в `/factions`, исключения по организациям, серверный гейт), кадровая вкладка починена (выбор организации не слетает, сотрудник выбирается, рядовому — личное дело), `/doc_admin` сохраняет шаблоны и умеет перекрашивать уже выданные удостоверения и документы прикрытия; навесные вкладки (в т.ч. «Доступ к аресту» и «Категории ареста», «Экономика», «Кадровые дела», «Логистика») вернулись в `/factions` — Unified UI теперь зовёт хук `GRM_FactionsAdmin_BuildTabs`; дилер авто v3.3/клиент v4.0 (каталог по категориям и организациям, стиль GRM, фракция выбирается из списка); торговец телефонами «Салон связи» (тип `phone` в GRM.Vendor, ассортимент из реестра телефонов); аудит нагрузки (`tools/audit_perf.py`, `AUDIT_2026-08-18_LOAD_ORDER.md`) — 30 стартов подсистем переведены на `GRM.Boot.OnMapStart` с тирами early/normal/late, шесть холостых таймеров усыплены; биндер больше не режет длинные `/me` `/do` `/it` (чат-шаг уходит через `EasyChat.SendGlobalMessage`, лимит 3000 символов; без EasyChat — авторазбиение по словам с повтором команды в каждом куске, `BD.SplitChat`), биндер действий `/binder` со сценами и радиальным меню на одну клавишу, формат `/dep` и `/fr` как у `/gnews`, форма регистрации организации не теряет ввод при автосинке, меню экипировки фракций переделано под GRM и подтянуто к структуре (ранги/отделы/подотделы, `/models_admin` + `/weapons_admin`), GRM Boot v1.0.0 (приоритетная загрузка + ленивые подсистемы + `grm_boot_status`), доступы фракций больше не прыгают вверх при клике по чекбоксу (Perms UI v3.0.0 + сохранение скролла в /fmenu), меню комендантского часа `/kom_hour` (кнопки/ползунок/причина/валидация), GRM Sound v1.0.0 (прекэш звуков + фолбэки + `grm_sound_check`), GRM Time v2.0.0 (эпоха вместо строки каждую секунду), вторая волна антифризов (двери/огонь/раздвижные), GRM Perf v1.2.0 (общий слой против микрофризов), Двери v5.0.0 (пространственный хэш + пересборка `/door_rebuild` + групповая ликвидация фантомов), мусоровоз 3 пакета / метки по очереди / полигон только с полным кузовом, цвет удостоверений запоминается в `/doc_admin`. Ранее: Door Integrity v4.0 (Дедупликатор фантомов + Master-Slave Double Doors + /door_audit), Warrant Core v2.0 (Судебные ордера в grm_comp_court, таран ds_battering_ram v2.0 с прогресс-баром), Суверенитет спецслужб (иммунитет судей wiretap_judge), Faction Core v5.0 (Иерархия «Отделы ➔ Подотделы» + Unified UI v1.1.0).  
**Репо:** `https://github.com/DrStrasse/GRMRP` (перенесён 01.09.2026 из `DrStrasse/DrStrasse`)  

Читать этот файл ПЕРВЫМ. Затем `HANDOVER.md`, `ROADMAP_GRM_2026.md`, `GRM_CORE.md`
и актуализации в `ANALYSIS.md`. Не начинать с master — он пустой.

> **ЕДИНОЕ РУКОВОДСТВО ПО НАПИСАНИЮ МОДУЛЕЙ — `GRM_ADDON_GUIDE.md`**
> (правила по рендеру, дублированию, оптимизации, сети, UI, данным, стендам;
> чеклист нового модуля + справочник «симптом → причина → правило»).
> Читать перед ЛЮБЫМ новым модулем/аддоном. Обновлять при новых багах.

> **Новые материалы-референсы (16.08.2026, режим анализа):** владелец подгрузил
> `AI part 2 details.zip` (Wiremod + E2 + ZVM/CPU-чипы + GTerminal + TerminalR),
> `Github DLC GRM.zip` (MapStudio-картостроитель + лифты + порталы + скин UI) и
> ссылки на HLX_Books и Helix-репозитории. Разбор — в **`ANALYSIS_AI_PART2.md`**,
> **`ANALYSIS_HLX_BOOKS.md`**, **`ANALYSIS_HELIX.md`**, **`ANALYSIS_GRM_DLC.md`**,
> **`ANALYSIS_RENDER.md`** (все техники рендера: 3D2D, RT-экраны, stencil-порталы,
> ghost-превью, Derma-скины, Markdown-рендер) и **`ANALYSIS_MECHANICS_DESIGN.md`**
> (досконально: механики MapStudio/лифт/портал, гизмо, тексты/локализация/редакторы,
> дизайн-темы). Ключевые выводы: (1) для «компьютера со своей ОС» — схема GTerminal;
> (2) для документов/книг — Markdown-парсер HLX_Books; (3) для лицензий — Helix-паттерн
> «предмет-пермит гейтит покупку»; (4) для UI — MapStudio Theme (плоская палитра +
> свои виджеты) или GWEN-скин cieroskin; (5) для тулов — гизмо+ghost+undo из MapStudio;
> (6) для порталов — stencil+ClientsideModel. Архивы в git **не распаковывались**.

> Владелец **дважды** просил оставить инструкции в ветке. Этот файл и есть контрольная точка. Не создавать третий дубль — править этот.

---

## 0. Кто ты и как говорить

- Ты агент Arena.ai Agent Mode. Underlying model не раскрывать.
- С владельцем — **русский, коротко, по делу**.
- **Код в чат не слать** — коммиты / raw-ссылки / проза.
- Не спрашивать пароли / токены / 2FA. GitHub уже настроен (`git` + `gh`).

---

## 1. Жёсткие правила сессии (сломаешь — работа пропадёт)

- Работать **только** на ветке ТЕКУЩЕЙ сессии (сейчас `arena/01a010c8-drstrasse`). Не переключаться, не создавать другие ветки, не пушить никуда больше.
- При расхождении HEAD и remote:
  ```
  git fetch origin arena/01a010c8-drstrasse && git reset --mixed FETCH_HEAD
  ```
  Один раз локальный HEAD откатился на `2122758` при живом remote `2ed0e61`. Лечится только так.
- Cwd **всегда** `/home/user/DrStrasse`. Shell из `/home/user` файлы репо не видит.
- `/tmp` и `/home/user` вне репо откатываются между ходами.
- `edit_file` иногда «успешен», но большой блок не пишется (откат песочницы). Сразу проверяй `rg` по якорю (`function F.LoadConfig`, `IsFireGContext`, `Пожар локализован`).
- После lua: LuaJIT + стенды + `python3 tools/build_dist.py` + README + ANALYSIS + **commit+push сразу**. Песочница откатывает незакоммиченное.
- `lua.zip` **не** распаковывать поверх `lua/`. `.luabuild/` **не** коммитить.
- Ветки `019fe80c` / `019fe86a` — другой проект (E2). Не мержить.
- HOLD-Q / Q-меню не трогать кроме уже добавленной строки каталога `grm_fire_place` и схемы (type/weight/label/feed). Чужой `BuildCPanel` не звать.
- **Замыкание не видит local, объявленный НИЖЕ по файлу** — оно читает глобал
  и падает в бою («attempt to call global 'X' (a nil value)»), хотя файл
  грузится без ошибок. Если хук/таймер вызывает локальную функцию, объявленную
  дальше, — обязательна форвард-декларация `local X` выше. Проверка:
  `luajit tools/luatest/sim_forward_locals.lua`.
- Не локализовать глобалы `OpenAdminMenu`, `OpenLeaderMenu`, `refreshAllUI`, `Factions`.
- `sh_factions.lua` **не трогать** для пожарных машин — настройки в `data/grm_fire/trucks.json`, не IncassoSettings.
- FFD не трогать без просьбы. Принтер/пресс — не источники огня.
- EasyChat: команды через `PlayerSay` **и** `PlayerSayTransform` (SkipPlayerSay).
- JSON: `util.JSONToTable(txt, false, true)`. CharacterKey = `SteamID64:charN`.
- `SweepOrphanGear` на удаление **одной** ТС **не звать** — он сносит ВСЕ рукава карты. Только `ClearOrphanHoses` / `ClearHosesOn` / `DropTruckGear`.
- `grm_fire_addon.zip` патчить **точечно** (в дереве нет всего vFire-пака). Не zip'ить только `addons/grm_fire/` — потеряется пак.
- luaparser паковых `weapon_extinguisher.lua` / `weapon_firehose.lua` ругается на GMod `!` / `continue` — не чинить парсером.
- `dist/grm_economy.zip` после build часто modified только из‑за timestamp — не коммитить специально, если контент не менялся.
- LuaJIT `-bl` в этой сборке нет — синтаксис через `loadstring`.
- Бинарь LuaJIT: `.luabuild/lj/src/luajit`. Иногда пропадает — `make -s -C .luabuild/lj`. Сборка с нуля:
  ```
  mkdir -p .luabuild && cd .luabuild && curl -fsSL -o lj.tar.gz \
    https://codeload.github.com/LuaJIT/LuaJIT/tar.gz/refs/heads/v2.1 && \
    tar xzf lj.tar.gz && mv LuaJIT-2.1 lj && cd lj && make -s
  ```
- `pip install -q --break-system-packages luaparser` каждый ход (исчезает).
- `lua.org` заблокирован; github / pypi / codeload работают.

### Dist raw (владелец качает отсюда)

- https://github.com/DrStrasse/GRMRP/raw/arena/01a05de8-grmrp/dist/grm_single_addon.zip
- https://github.com/DrStrasse/GRMRP/raw/arena/01a05de8-grmrp/dist/grm_addon_studio.zip
- https://github.com/DrStrasse/GRMRP/raw/arena/01a05de8-grmrp/dist/grm_full_code.zip
- https://github.com/DrStrasse/GRMRP/raw/arena/01a05de8-grmrp/dist/grm_economy.zip
- https://github.com/DrStrasse/GRMRP/raw/arena/01a05de8-grmrp/dist/grm_fix_hud_tab_currency.zip
- https://github.com/DrStrasse/GRMRP/raw/arena/01a05de8-grmrp/dist/grm_fire_addon.zip

Для пожаров на сервере нужны **оба**: `grm_single_addon.zip` (ядро) + `grm_fire_addon.zip` (vFire + сущности) + рестарт.
Студия аддона — **отдельный** аддон: `grm_single_addon.zip` (ядро) + `grm_addon_studio.zip` (студия).

---

## 2. Где остановились

Владелец **трижды** прислал `+учёт тушения пожара, уведомление - Пожар локализован/потушен.`

- v1.4.0 (`3430a00`) — первый вариант, условия строгие.
- **v1.4.1 (эта сессия, `arena/019ffd5c-drstrasse`) — усиленный:** мягче локализован (2.5с, peak≥1), peak=min 1 если видели vfire, скан на boot, оба события при тушении после ствола, toast+ChatPrint, получатели SuperAdmin+Dispatch+FightPro+notify-фракции+бойцы+рядом 1500, журнал `/fire_log` + UI.

### Что уже есть (`sh_grm_fire_status.lua` v1.4.1)

- Кластер vFire **480** юн. = один инцидент, peak минимум 1.
- `F.BuildFromExisting()` скан на `InitPostEntity` 1-2с + первый Think + PostCleanupMap.
- Ствол/огнетушитель пишет бойца `NoteFight`, `fought` флаг.
- Сжатие ≤50% пика + 2.5с без роста, peak≥1 → **«Пожар локализован»**.
- 0 клеток при peak≥1 → **«Пожар потушен»**, если до этого не было локализован и `fought` — шлёт оба.
- Получатели: фракции из `/grm_fire_notify` + SuperAdmin + `CanDispatch` + `CanFightPro` + бойцы (по CharacterKey) + рядом 1500, дедуп + чат-дубль.
- Журнал массив `data/grm_fire/log.json` (кап 80) + сеть `GRM_FireLog_Req/Data` + команда `/fire_log` `/журнал_пожаров` `/firelog` + конвар `grm_fire_log`, клиент `GRM.Fire.OpenLogPanel` DListView, кнопка во вкладке «Пожарные».
- Хуки `GRM_FireLocalized` / `GRM_FireExtinguished`.
- Think 0.8 с + `vFireCreated` / `vFireRemoved` (recount через timer.Simple(0)).

### Что закрыто в v1.4.1

1. peak=0 на remove → теперь `max(peak,1)` и `peak=1` при создании.
2. Скан живых vfire на boot — `BuildFromExisting`.
3. UI журнала + команда — сделано.
4. Тост+чат + расширенные получатели — сделано.
5. Крошечный очаг 1-2 клетки — теперь всегда потушен, а при fought — сначала локализован.
6. Стенды: `sim_fire.lua` + `sim_fire_rewind.lua` — 0 fails (версия 1.4.1, новые якоря).

### Следующий заказ владельца (после пожаров)

> «Доделываем пожарку, затем делаем систему лицензий, документы соответственно и нужно будет переработать компьютеры, электронику. Там был полноценный компьютерный модуль с полноценной операционной системой, но я всё никак не мог сделать там фоторобот + печать фоторобота + печать любых фоток и т.д.»

То есть Код 59+ — лицензии/документы + компьютерный модуль v2.0 + фоторобот и печать.

Стенды на HEAD: `sim_fire.lua` + `sim_fire_rewind.lua` — 0 fails, single/full zip пересобраны.

---

## 3. Карта пожаров (Код 58) — что уже сделано

Готовой системы пожаров в GRM lua не было. Контент — `addons/grm_fire/` на базе `vFire PACK.zip` (коммит владельца `23dd53c`).

### Версии

| Что | Версия | Файл |
|---|---|---|
| Ядро | **v1.4.1** | `lua/autorun/sh_grm_fire.lua` |
| Доступ / notify | v1.4.1 + журнал | `sh_grm_fire_access.lua` |
| Машина | — | `sh_grm_fire_truck.lua` |
| G-меню насоса | — | `sh_grm_fire_pump_ui.lua` |
| Точки очага | — | `sh_grm_fire_spots.lua` |
| Учёт тушения | **v1.4.1** | `sh_grm_fire_status.lua` — мягче, скан, оба события, toast+chat, 1500, /fire_log |
| Аддон | **0.5.0** | `addons/grm_fire/lua/autorun/sh_grm_fire_addon.lua` |
| Инкассация | **v2.2.2** | `lua/autorun/sh_grm_incassation.lua` |
| HUD | **v10.3** | `lua/autorun/client/cl_grm_hud.lua` |

### vFire API (не ломать)

`CreateVFire` / `CreateVFireBall`; `ent:Ignite()` / `Extinguish()` / `IsOnFire()` перехвачены; `SoftExtinguish` / `ChangeLife` / `GetFireState`; хуки `vFireCreated` / `vFireRemoved` / `vFireEntityStartedBurning` / `vFireEntityStoppedBurning`; флаги `vFireInstalled`, `vFireVersion=1`, `GRM_FireAddon`, `GRM.FireAddon.Version`.  
Workshop `1525218777` и `104607228` сняты.  
`hook.Run("vFireRemoved", self, parent)` — сущность ещё часто валидна; recount через `timer.Simple(0)`.

### Модели оружия `_grm`

`models/weapons/c_firehose_grm.mdl`, `w_firehose_grm.mdl`, `c_fire_extinguisher_grm.mdl`, `w_fire_extinguisher_grm.mdl`.

### CSS/HL2 фолбэки

| Что | Модель | Заметка |
|---|---|---|
| Гидрант | `cs_assault/FireHydrant` / `valvewheel001` | — |
| Шкаф | `cs_office/fire_extinguisher` / `canister01a` | — |
| Насос | `models/props_lab/tpplugholder_single.mdl` | голограмма, SOLID_BBOX, COLLISION_GROUP_WEAPON, без phys |
| Лестница | `models/props/de_train/ladderaluminium.mdl` / `metalladder002` | — |
| Точка очага | `models/props_junk/PopCan01a.mdl` | маркер рисует тул, не модель |

### Кто пожарный / какая ТС

- Spawn-name в `/fire_trucks` у включённой фракции; или висит `grm_fire_pump`; или SuperAdmin `/firetruck`.
- Доступ: SuperAdmin всегда; иначе `F.CanFightPro` (галочка Control в `/fire_access`) + фракция enabled + роль если список не пуст.
- `F.AttachPump` offset `Vector(0,-46,16)` ang `Angle(0,90,0)`, 4 рукава, бак вода **4000** / пена **500** / порошок **250**.
- NW: `GRM_FireTruck`, `GRM_FireFaction`, `GRM_FireSpawnName`, `GRM_FireHoses`, `GRM_FireTank`/`Foam`/`Powder` + Max, `GRM_FireAgent`, игрок `GRM_FireMyTruck`.
- Команды: `/firetruck` `!firetruck` `/feuer` `/пожарка` `/пм`; стоп `/firetruck_off` `/пожарка_стоп` `/feuer_off`; админ `/fire_trucks`; рукав `/рукав` `/hose` `/ствол`.

### Бак / напор

Автозаливки нет (Think насоса больше не льёт +25/с). Рукав от насоса списывает агент: вода **8** / пена **4** / порошок **2** за тик 0.09 с. Прямая подача с гидранта — тумблер в G-меню. Закачка только кнопкой при связанном гидранте (вода/пена) или шкафе (порошок). Связь: открытый гидрант в **380** юн. или кнопка «Связать» → `A.LaySupplyLine` до 2200.

### G-меню насоса

После `/firetruck` или посадки KEY_G у машины/насоса. XUI-стиль. Полосы с NetworkVar насоса, **не** net-спам Think. G тогглит. ShowCloseButton(false). Антидребезг 0.2 с сервер / 0.35 с G.  
Кнопки: **ВЗЯТЬ РУКАВ / СТВОЛ С МАШИНЫ**, Смотать, Связать с гидрантом, вода/пена/порошок, насос вкл/выкл, закачка, прямая подача, слить.  
G насоса **только** в `F.IsFireGContext`, не «везде на дежурстве».

### Рукав (визуал + физика укладки)

- Сервер шлёт ломаную `GRM_FireHose_Path` (векторы узлов).
- Клиент: толстая красная лента `render.SetColorMaterial` + `DrawBox` + `DrawLine` (`GRM_FireHose_Vis`). **DrawBeam не основа** (UnlitGeneric в Source не рисует пикселей).
- Узлы и менеджер `TRANSMIT_ALWAYS`.
- `NetworkVar Vector SrcPos/TailPos` + `SyncAnchors` каждый Think — лента едет с машиной без PVS насоса.
- При выдаче сразу LAY на земле (`GroundSnap`). Машина уехала — `PayoutFromSource` / `InsertLayAt(2)` досевает колышки у катушки, готовый путь не двигает.
- Клиент: насос → `dropGround` → колышки → ноги → рука. Плоская лента `HoseBeamHalfW=1.35` / `HoseBeamHalfH=0.28`.
- MaxLength 2200, LayStep 40.
- Смотка: `TryRewind` / `IsWalkingBack` / `ReelIn` (ALT) / `A.HoseMoveHint` (проекция t≤0.93, S/`IN_BACK`). Всё на **сервере** в `grm_fire_hose/init.lua`.
- E на свой насос / кнопка «Смотать» = `A.RewindAtSource` / `A.ReturnHose`.

### Удаление ТС

`EntityRemoved` **без** `IsValid`-барьера (движок уже помечает ТС невалидным). `looksLikeTruck` (NW `GRM_FireTruck` + IsVehicle + simfphys_/lvs_/glide_/gmod_sent_vehicle/prop_vehicle_/`vehicle` в классе). `A.ClearHosesOn` / `A.HoseTouches` / `A.ClearOrphanHoses` на том же и следующем тике. Насос `OnRemove`. Рукав без `StartEnt` в Think → `Rewind`. Клиент `DrawAllHoses` выкидывает путь если `Entity(id)` мёртв.

### Лестница

Entity `grm_fire_ladder` + SWEP `weapon_grm_ladder`. E взять, ЛКМ поставить, ПКМ по машине закрепить, E на борту выдвинуть, Shift+E снять, W/прыжок лезть (`SetupMove`).

### Тул `grm_fire_place`

`TOOL.Category = "GRM"` + строка в `QM.ToolCatalog` / Schema. Типы: hydrant/pump/cabinet/spot/ladder. Cvars: `grm_fire_place_type`, `grm_fire_place_weight`, `grm_fire_place_label`, `grm_fire_place_feed`.

### Перм-классы

`grm_fire_hydrant`, `grm_fire_pump`, `grm_fire_cabinet`, `grm_fire_spot`, `grm_fire_ladder`. Hose / hose_node **не** пермятся. Бортовое железо `_grmTruckGear` / NW `GRM_TruckGear` AutoPerm не берёт.

### Точки очага

SOLID_BBOX / COLLISION_GROUP_WEAPON / TRANSMIT_ALWAYS, без NoDraw. Клиент `GRM_FireSpot_Vis` рисует столб+метку **только SuperAdmin с `gmod_tool` mode=`grm_fire_place`**. ЛКМ поставить/обновить; ПКМ `IgniteSpot`; R удалить (сфера 80 юн.). NetworkVar: Weight, LastIgnite, CoolSec, Feed, SpotOn, SpotLabel.  
`/fire_spots` `/очаги` `/пожары_очаги`. Конфиг `data/grm_fire/config.json` (version=1, random/stove/min_sec/max_sec/cooldown/max_incidents/ttl; jsonT false/true, карантин, read-back). Дефолт: RandomEnabled, RandomMinSec=480, RandomMaxSec=900, SpotCooldownSec=2700, MaxIncidents=8, PersistTTL=1800. Выключенная точка в рандом не берётся.

### Данные

`data/grm_fire/trucks.json`, `access.json`, `notify.json`, `active_<map>.json`, `config.json`, `log.json`.

---

## 4. Журнал ошибок и граблей (пожары + среда)

Каждая строка = реальный репорт владельца. Не повторять фикс, который уже откатили/усиливали.

| # | Симптом | Корень | Фикс / коммит | Не делать снова |
|---|---|---|---|---|
| 105 | `weapon_extinguisher.lua:286: 'end' expected` | `if ( SERVER ) then` без end после снятия AddWorkshop | убрать строку целиком `b400829` | не комментировать `if SERVER` |
| 106 | фиолетовые ERROR-столбы; насос толкает ТС; длина 850; тул не в GRM | hunter cube нет на сервере; SOLID_VPHYSICS на борту | без модели на узлах; насос BBOX/tpplugholder; 2200; Category=GRM | не ставить hunter cube |
| 107 | бак 19645 / не падает | Think +25/с + SupplyPump nil + SprayCost=1 | нет автозаливки; Consume всегда; 8/4/2 | не возвращать Fill(25) |
| 108 | G-меню рябит, кнопки через раз, окна множатся | NET_DATA каждый раз Remove+Create + Think 2/с | одно окно, NetworkVar, антидребезг `370e166` | не звать openUI на каждый пакет |
| 109 | краш `getMyIncassCarClient` nil на G по гидранту | local функция ниже хука G | поднять выше; skip `grm_fire_*` `56bb854` | local ниже hook.Add |
| 110 | колесо физгана роняет проп | HUD selectorTimeout=3 → SelectWeapon | `IsPropToolBusy` `2ed0e61` | не путать с HOLD-Q |
| 111–112 | рукав только с гидранта; нет кнопки; кабель не виден | насос NotSolid; кнопок не рисовали; alpha=0; redcable нет | EnsureTruckPump; кнопки; свой материал `a70f6a2` | — |
| 113 | кабель всё равно не виден | DrawBeam+UnlitGeneric = 0 пикселей; узлы вне PVS | Path-net + ColorMaterial+DrawBox `e498cef` | не возвращать DrawBeam как основу |
| 114 | насосы в воздухе после рестарта | AutoPerm писал бортовой насос по миру | TruckGear; SweepOrphanGear boot `5ab55b2` | AttachPump не шлёт Placed |
| 115–116 | назад не сматывает | лимит 87 юн. + условие «ближе к prev» | HoseMoveHint + ReelIn ALT `de2aac3` | не возвращать LayStep*1.25 |
| 117–118 | машина уехала — лента на месте | снимок пути; StartEnt вне PVS | SrcPos NetworkVar `f18bd5e` | не брать конец с GetStartEnt на клиенте |
| 119 | прямая балка по воздуху | FollowHost тащил все колышки + pts[1]=насос | PayoutFromSource, dropGround `7271d32` | не DragNode held-рукава в FollowHost |
| 120–121 | удалили ТС — рукава остались | EntityRemoved + IsValid-барьер | без IsValid + ClearOrphanHoses `4321922` | **не** SweepOrphanGear на одну ТС |
| 122–123 | G у пожарки орёт инкассацией | хук смотрел только `grm_fire_*`; без рейса term_use орёт | IsFireGContext; без рейса G no-op `063d76d` | не подвязывать G насоса к инкассу |
| 124 | точка очага невидима, R/ПКМ мимо | SetNoDraw+SetNotSolid | BBOX + Vis только с тулом `a75e032` | не возвращать NoDraw на spot |
| 125 | нет «локализован/потушен» | vFireRemoved только снимал маркер | status.lua `3430a00` | см. §2 — условия ещё слишком строгие |

### Прочие грабли среды

- HEAD локально откатился на старый коммит при живом remote — `fetch` + `reset --mixed`.
- `edit_file` врёт об успехе на больших блоках — проверяй `rg`.
- LuaJIT бинарь пропадает из `.luabuild/lj/src/` — `make -s -C .luabuild/lj`.
- `19645` литров в коде не воспроизводится (баки 4000/500/250, clamp max 20000). Скорее мусор NW до фикса Initialize.
- `/incass_off` без рейса по-прежнему орёт — это чат, не G. Не чинить без просьбы.

---

## 5. Заказы владельца по пожарам (порядок)

1. «Пиши серверную часть… подсмотреть incassation» + модели `_grm`.
2. Синтаксис extinguisher (`end` expected).
3. Квадраты/точки невидимы; насос не коллизионный; рукав 2000+; смотка; лестница; тул в GRM. Скрин: фиолетовые ERROR = missing hunter cube.
4. Меню насоса на G: баки, закачка, связь с гидрантом; расход должен падать; лестница aluminium.
5. Кнопки насоса «не функциональны» / рябит / наслоение.
6. Краш `getMyIncassCarClient` + G по гидранту = инкассация + невидимый рукав + кнопка ствола.
7. Скролл / бар выбора оружия vs физган.
8. Рукав только с гидранта; нет кнопки с машины; цвет кабеля.
9. Визуал кабеля на земле (дважды).
10. После рестарта насосы в воздухе.
11. Назад не сматывает (серверная сторона?).
12. Машина уехала — линии на месте; шланг огромный (дважды).
13. Прямая балка по воздуху, скрин `20260814011930_1.jpg` (дважды).
14. Удалили машину — рукава/насос сразу (дважды).
15. G меню опять к инкассации (трижды, злой тон).
16. Точки очага: воспламенение, таймеры, видимость с тулом (дважды).
17. Учёт тушения — локализован/потушен (**повторил после `3430a00`** — см. §2).

Скрин (13): игрок «Александр Фон Грённер» (Полевая Жандармерия) у красной FD-машины; оранжевая прямая балка торс→насос; HUD `НАПОР вода 3996/4000  0 / 2200 юн`. laid=0 был **до** `7271d32`.

---

## 6. Диагностика, если владелец снова орёт

| Жалоба | Что спросить / проверить |
|---|---|
| Ствол не выдаётся | Тост: «нет доступа» = нет FightPro в `/fire_access`; «нет свободных рукавов» = 4 слота; «аддон рукава не загружен» = нет `grm_fire_addon.zip` |
| Кабель не виден / опять балка | Оба zip + рестарт; после шага HUD laid > 0; доходит ли `GRM_FireHose_Path` |
| Удалил машину — рукава остались | Класс ТС (looksLikeTruck) + оба zip + рестарт. Не звать SweepOrphanGear |
| Точка не видна | Суперадмин? В руках именно `gmod_tool` mode `grm_fire_place`? Оба zip |
| G → «нет рейса инкассации» | `grm_single_addon.zip` + рестарт (инкассация в нём, не в fire-аддоне) |
| Нет «локализован/потушен» | Рестарт single zip; `/grm_fire_notify` (фракции); тушили ли стволом; см. §2 — условия строгие |
| Насос в воздухе после рестарта | Должно быть закрыто `5ab55b2`. Если нет — перм-JSON, класс, mounted |

---

## 7. Файлы, которые трогать / не трогать

### Трогать при работе над пожарами

```
lua/autorun/sh_grm_fire.lua
lua/autorun/sh_grm_fire_access.lua
lua/autorun/sh_grm_fire_truck.lua
lua/autorun/sh_grm_fire_pump_ui.lua
lua/autorun/sh_grm_fire_spots.lua
lua/autorun/sh_grm_fire_status.lua
lua/autorun/sh_grm_incassation.lua          # только G-контекст, не логику рейса
addons/grm_fire/lua/autorun/sh_grm_fire_addon.lua
addons/grm_fire/lua/autorun/sh_grm_fire_hose.lua
addons/grm_fire/lua/entities/grm_fire_*
addons/grm_fire/lua/weapons/weapon_grm_hose.lua
addons/grm_fire/lua/weapons/weapon_grm_ladder.lua
addons/grm_fire/lua/weapons/gmod_tool/stools/grm_fire_place.lua
tools/luatest/sim_fire.lua
tools/luatest/sim_fire_rewind.lua
README.md  (строка модуля 58)
ANALYSIS.md (новая находка 126+)
HANDOVER.md / этот CHECKPOINT.md
```

Q-меню: **только** каталог/схема `grm_fire_place`, не логика HOLD-Q.

### Не трогать без прямой просьбы

- `sh_factions.lua`
- `sh_grm_qmenu.lua` логика HOLD-Q
- FFD / keypad
- двери v3
- принтер / пресс
- валюта / экономика / банк (кроме если сам сломал)
- ветки E2

---

## 8. Чеклист хода после любой правки lua

1. Правка + сразу `rg` что текст на месте.
2. Синтаксис: LuaJIT `loadstring` (не `-bl`).
3. Стенды: как минимум `sim_fire.lua` и `sim_fire_rewind.lua`. Если ядро валюты/пермов — ещё `roundtrip_test.lua`.
4. `python3 tools/build_dist.py` (все zip).
5. README строка модуля + ANALYSIS новая находка + HANDOVER/CHECKPOINT.
6. `git add` нужное (не `.luabuild/`, не случайный economy.zip если только timestamp).
7. `git commit` + `git push origin arena/019ffaa2-drstrasse`.
8. Владельцу — проза + raw-ссылки на zip. Код в чат не слать.

---

## 9. Что делать сразу после прочтения (обновлено 2026-08-14)

1. `git fetch origin arena/019ffd5c-drstrasse && git reset --mixed FETCH_HEAD` (ветка этой сессии) + `git log -1`. HEAD теперь **v1.4.1**.
2. Пожары **закрыты v1.4.1** — стенды 0 fails, zip пересобраны. Если владелец подтвердит — переходить к Коду 59.
3. Если новый репорт по пожарам — таблица §6, потом код.
4. Код 59 — лицензии/документы + компьютеры/электроника v2.0 + фоторобот (см. §11). Не начинать без концепта.

---

## 10. Старые открытые нитки (не пожары)

- Финансовая сага закрыта (наличка и счёт переживают рестарт). Корень был `JSONToTable` без `ignoreConversions` (находка 65).
- Не сделано из старых хотелок: entity `sent_vehicle_dealer`, `grm_item_drop`, радио (RadioFrequencies global).
- SteamID64 владельца для белого списка econadmin так и не предоставлен.
- Название внешнего «писателя» `grm_wallet.json` (массив name/balance) не вскрыто — ныне безвреден, всеядный загрузчик его жрёт.

---

## 11. Следующий этап — Код 59/60: лицензии и документы (ОС/фоторобот УДАЛЕНЫ)

> **АКТУАЛЬНО (2026-08-15):** компьютер со своей ОС (GRM NET OS), сетевые устройства,
> принтер и фоторобот **снесены из сборки** по требованию владельца («сделаем проще»,
> находка 133). Ведомственные компьютеры (`grm_doc_computer`, `grm_comp_*`) остались.
> Фокус — лицензии: водительские v2 (сроки/баллы, находка 128) + **лицензия на оружие**
> и **лицензия на ведение бизнеса** (находка 134). Остаток: госпошлина через
> `GRM.Services.Charge`, экзамены на права, интеграция проверок оружия/бизнеса.
> Подробно — `CONCEPT_LICENSES_V2.md` §9–11.

## 11a. (историческое) Код 59: лицензии, документы, компьютеры, электроника, фоторобот

**Заказ владельца (после пожаров):**
> Доделываем пожарку, затем делаем систему лицензий, документы соответственно и нужно будет переработать компьютеры, электронику. Там был полноценный компьютерный модуль с полноценной операционной системой, но я всё никак не мог сделать там фоторобот + печать фоторобота + печать любых фоток и т.д.

### Что есть сейчас

- **Документы v1.4.1** (`sh_grm_documents.lua`): паспорт, ксива, военник, водительские (ГАИ гражданские A-E+СПЕЦ, ВАИ военные A-В…СПЕЦ-В + 6 допусков), прикрытие, двухфазный рендер, C-меню, `/show*`, проверка при посадке, `grm_doc_computer` 6 вкладок.
- **Компьютеры:** 6 ведомственных `grm_comp_*` (police/military_police/security/military/traffic/medical) + `grm_doc_computer` + `grm_bank_computer` + **GRM NET OS v1.5.1** (`sh_grm_electronics.lua` + cl): роутеры, компы `grm_net_computer`, принтеры `grm_net_printer`, файлы per-device `data/grm_electronics/`, почта, аккаунты, модули (faction/arrest/fines/cctv/roomtap/services), `grm_net_document` entity для печати.
- **Фоторобот:** в `cl_grm_electronics.lua` есть `photoPage()` + `photoEditor()` — база частей лица (face/hair/eyes/brows/nose/mouth/chin/extras), цвета кожи/волос/глаз, эффекты (bw/sepia/vintage/grain/highcontrast), `render.Capture` JPEG, сохранение в `data/grm_photos/*.jpg`, галерея `photoGallery()`, кнопки Сохранить/Печать/Рассылка. Но печать через `image_save` категорию `photo_print`, а не через `print` op принтера; `print` op ждёт `fileID + printerID` и создаёт `grm_net_document` с DHTML `file://` (ломается), нет превью, нет печати любых фоток (только composite).

### Что делать — концепт Кода 59 v2.0

**59.1. Лицензии v2.0:** 
- Переработать категории под реальные: добавить подкатегории BE/CE/DE, стаж, очки, мед.ограничения, срок действия прав, приостановка/лишение через терминал ГИБДД/ВАИ.
- Связка с банком: госпошлина через `GRM.Services.Charge` (уже есть).
- Экзамен: теория (тест в компе) + практика (чекпоинт на маршруте).

**59.2. Документы v2.0:**
- Фото из фоторобота как аватар в паспорте/ксиве (сейчас `AvatarImage` Steam).
- Watermark/QR на документах для проверки подлинности через терминал.
- Реестр утерь/краж.

**59.3. Компьютеры / Электроника v2.0 — главный блок:**
- **OS:** оставить GRM NET OS, добавить оконный менеджер (drag, minimize), файл-менеджер с разделением по категориям photo/doc.
- **Фоторобот 2.0:** сохранить текущий редактор, починить `render.Capture` (делать в `PostRender` или `RT` + `GetTexture`), сохранять как `data/grm_computer/images/*.jpg`, добавить `imagePath` в `E.Files` + бинд к `grm_net_document:SetDocumentImage(path)`, печать через существующий `print` op: `fileID + printerID + paperSize + copies`. Добавить импорт фото игрока (из `data/` или URL) — «любая фотка».
- **Печать:** универсальная: любой файл категории photo/doc/drawing может печататься. Принтер entity `grm_net_printer` спавнит `grm_net_document` с `SetModel("models/props_lab/clipboard.mdl")` + `SetDocumentImage` для фото + `DocumentContent` для текста. Preview в OS уже есть (`preview` panel в printPanel), починить превью альбом/книжная.
- **Фото-архив полиции:** комп `grm_comp_police` вкладка «Фотороботы» — список сохранённых из OS, поиск по приметам, привязка к делу розыска (`GRM.Wanted.AddCustomCharge` с фото).
- **Интеграция:** `grm_net_computer` OS Type `lawenforcement` получает доступ к `photorobot` + `CCTV` + `fines`. Тип `civilian` — без фоторобота.
- **Сеть:** уже есть `GRM_Net_PrintJob`, `GRM_Net_Document`, `image_save` — оставить, добавить rate-limit и проверку дистанции (UseRange 200 уже есть).

**Тех-долг перед Кодом 59:**
- Убрать дубли фото-логики: `cl_grm_electronics.lua` имеет два пути сохранения (photo и photo_print) — унифицировать.
- Проверка `file.Exists` + `../data/` для DImage — заменить на `Material("data/...")` или `DHTML` с base64.
- Добавить `PERM_CLASSES` для `grm_net_printer` и `grm_net_computer` если нет.

**Тесты для 59:**
- `sim_photorobot.lua`: creation, save JPEG non-empty, file registered in `E.Files`, print spawns `grm_net_document` with imagePath, access by OS type.
- `sim_documents_v2.lua`: license expiry, photo from photorobot linked.

Начать с CONCEPT_59.md потом код. Следующий номер после — Код 60.

Конец чекпоинта. Следующий агент стартует отсюда.

---

## Ход 19.08 (теги отделов, окно /factions, мусоровоз, уборка ТС у дилера)

* `/factions`: окно 0.95×0.92 экрана (до 1920×1120), кнопки структуры докнуты.
* Теги отделов (`DepartmentTags`) и подотделов редактируются в «Структуре» и
  печатаются в `/fr`, `/frb`, `/dep`, `/d`, `/depb`, `/db` и над игроком через
  `GRM.Factions.ChannelTag`.
* На игроке: `GRM_Subdepartment`, `GRM_DepartmentTag`, `GRM_SubdepartmentTag`,
  `GRM_ChannelTag` (+ display-варианты).
* Мусоровоз: маршрут по точкам, мусорка опциональна, сверка не переписывает
  рейс, сбор на точке клавишей G, `JB.BinForPoint`, `JB.CollectAtPoint`.
* Дилер v3.4.0: раздел «На карте (убрать)», операция `remove`.
* Не проверено вживую: теги в эфире на полном сервере, сбор без контейнера,
  уборка служебного ТС из меню дилера.

## Ход 19.08 (2) — модуль гаражей

* `GRM.Garage` v1.0.0 (`sh_grm_garage.lua`): зоны, места, стойки, типы,
  плата, привязка дилеров, `data/grm_garage/<карта>.json`.
* Тул «GRM: гаражи», энтити `grm_garage_terminal`, окно `cl_grm_garage_ui`.
* Дилер v3.5.0: общий слой `VD.IssueRecord / VD.StoreRecord`,
  `VD.Spawn(class, dealer, ply, place)`; конвар `grm_garage_strict`.
* Документ: `CONCEPT_GARAGE.md`. Стенды: `sim_garage_runtime`, `sim_garage_module`.
* Не проверено вживую: разметка тулом на карте, поведение стоек после
  PostCleanupMap, выдача крупных simfphys/LVS машин в тесных боксах.

## Ход 19.08 (3)

* Гараж ↔ двери: `G.LinkDoor`, `G.ByDoor`, `GRM_DoorAccessOverride`,
  `G.ApplyDoorState`, `G.ToggleDoors`; режим тула «Ворота гаража».
* Гараж ↔ дом: `G.LinkProperty`, `G.SyncWithProperty`, `baseKind`; в
  недвижимости появился хук `GRM_PropertyOwnerChanged` (5 точек).
* Фракции: `setRoleKey` + действие + кнопка «Ключ»; хук
  `GRM_FactionRoleKeyRenamed`; подписчики в perms, doors_access, doors.
* Стенды: `sim_role_key_runtime` (25), `sim_garage_runtime` (58),
  `sim_garage_module` (60), `sim_dept_tags` (45).
* Не проверено вживую: привязка ворот на реальной карте, продажа дома с
  гаражом на живом сервере, смена ключа ранга при большом составе.

## Ход 19.08 (4) — категории дверей

* Категории дверей v4: `factions/departments/subdepartments/roles` + флаги
  `everyone/noFaction/canLock/lockAdminOnly/keepLocked/allowBuy`.
* `D.CategoryMatch`, `D.CategoryCanLock`, `D.CategoryOfDoor`, `D.FactionTree`,
  `D.NormalizeCategory`; действия `cat_create/rename/delete/flag/member`,
  `clear_owner`.
* Окно двери → `lua/autorun/client/cl_grm_doors_menu.lua` v2.0.0 (стиль GRM,
  боковое меню, редактор категорий, ширина до 1480).
* Стенды: `sim_door_categories` (30), `sim_door_menu_ui` (39); обновлены
  `sim_doors_admin`, `sim_doors_v3`.
* Не проверено вживую: миграция старого categories.json на живом сервере,
  поведение keepLocked с парными дверями.

## Ход 19.08 (5) — шахта и торгаши

* `GRM.Mining` v2.0.0: цены в `data/grm_mining/prices.json`, `M.Sell`,
  `M.CountOres`, `M.GiveTool/ReturnTool` (залог `grm_mining_deposit`),
  `M.ToolClass`, `M.PushProgress`.
* Окно скупщика и вывески торгашей/скупщика — стиль GRM, 3D2D.
* Убран дубль `net.Receive("grm_ore_sell")` (две регистрации затирали друг друга).
* Стенды: `sim_mining_runtime` (23), `sim_mining_ui` (44).
* Не проверено вживую: наличие аддона бура на сервере, залог на живой
  экономике, подбор кучки руды при полном инвентаре.

## Ход 19.08 (6) — лимит машин по классу

* Дилер v3.6.0: `grm_vd_class_limit` (2), `VD.CountClass`, `VD.CanOwnMore`,
  `VD.TagVehicle`, `VD.IsDealerVehicle`; каталог отдаёт `owned`/`classLimit`.
* Клиент дилера v4.2.0: «У вас: N из 2», кнопка «ЛИМИТ» на пределе.
* Стенд: `sim_vehicle_class_limit` (32).
* Не проверено вживую: поведение с машинами, выданными до обновления (у них
  метки появятся при следующей выдаче из гаража).

## Ход 19.08 (7) — выдача покупок и выкуп государством

* Дилер v3.7.0: настройки `delivery` (dealer/garage/both) и `showRetrieve`
  в админке дилера, проверки на сервере.
* Дилер v3.8.0: `grm_vd_state_buyback` (93%), `VD.StateBuybackPrice`,
  кнопка «ПРОДАТЬ ГОСУДАРСТВУ · сумма», списание из казны, аудит.
* Клиент дилера v4.5.0.
* Не проверено вживую: списание из казны при пустом бюджете (сейчас уходит
  в минус по модулю экономики — при необходимости добавим отказ).

## Ход 19.08 (8) — концепция ID / шапки / pcboard

* Написан `CONCEPT_PCBOARD_IDENTITY.md`: реестр PID/CID, объединение двух
  HUD над головой, ID в чате и фракциях, планшет `/pcboard` с уровнями
  допуска и провайдерами данных, вкладка «Госбаза» в /factions, антиабьюз.
* Код НЕ писался — ждём ответов владельца на 6 вопросов из раздела 7.

## Ход 19.08 (9) — реестр ID

* `GRM.Registry` v1.0.0: ГР-#### (персонаж) и ИГ-#### (игрок),
  `data/grm_identity/registry.json`, `Resolve`, `R.Lower`, `/id`.
* Номера: служебные каналы, колонка ID в составе, админ-панель.
* Новое действие админки `ban_id` (офлайн-бан по номеру) и `id_lookup`.
* Стенды: `sim_registry_runtime` (31), `sim_registry_ui` (29).
* Дальше по концепции: шапка над головой v3 («Неизвестный» до документа),
  затем /pcboard с уровнями допуска и вкладка «Госбаза» в /factions.

## Ход 20.08 (1) — планшет госслужб /pcboard

* `GRM.PCBoard` v1.0.0 (`sh_grm_pcboard.lua`): уровни допуска
  (правоохранительный / комендатура / медицинский / спецслужбы /
  администрация) по цепочке организация → отдел → подотдел → должность,
  поверх — галочки блоков в трёх состояниях.
* 13 провайдеров данных из существующих модулей: личность (паспорт + номер
  ГР), розыск, штрафы, удостоверения и лицензии, воинский учёт, место службы,
  транспорт (гараж дилера), недвижимость, образование, медкарта, легенды,
  «кто пробивал раньше», служебные данные аккаунта (только администрации).
* Антиабьюз: два РП-действия через систему, справка только запросившему,
  кулдаун (8 с), лимит (3/мин), журнал `data/grm_pcboard/log.json` +
  `GRM.Audit`, право `pcboard.audit`, скрытый запрос только спецслужбам и
  всё равно в журнал.
* Команды: `/pcboard` (по прицелу), `/pcboard ГР-1042`, `/pcboard <имя>`,
  `/pcboard авто <номер>`, `/pcboard я`, `/pcboard журнал`,
  `/pcboard скрытно …`, псевдоним `/пробить`, консоль `grm_pcboard`,
  `grm_pcboard_log`, `grm_pcboard_access`, `grm_pcboard_window`.
* Вкладка «Госбаза» в `/factions` (`cl_grm_pcboard_ui.lua`): дерево узлов
  организации, уровень узла, галочки блоков, лимиты и переключатели.
  Хранение `data/grm_pcboard/access.json`.
* Стенды: `sim_pcboard_runtime` (89), `sim_pcboard_ui` (48).
* Ловушка Lua, найденная прогоном: `overrides[key] or nil` съедает `false` —
  «принудительно выключенный блок» переставал выключаться.
* Не проверено вживую: реальные поля военного билета и медкарты на сервере
  владельца (в справку выводятся те, что есть в реестрах модулей).
* Дальше по концепции: шапка над головой v3 («Неизвестный» до предъявления
  документа) и кнопки /pcboard в служебных компьютерах.

## Ход 20.08 (2) — шапка над головой v3 и кнопки /pcboard в терминалах

* `GRM.Nameplate` v1.0.0 (`sh_grm_nameplate.lua`): ОДИН `HUDPaint` вместо
  двух (`Factions_HUD` + `GRM_RPDesc` снимаются после загрузки), одна
  плашка «имя · номер / тег и должность / описание», общий радиус
  `grm_cl_nameplate_dist`, кэш переноса строк.
* Имя незнакомым скрыто: «Неизвестный (муж.)» — пол берётся из паспорта.
  Знакомство: `/представиться` (все в радиусе), `/паспорт` (цель в прицеле),
  успешное `/pcboard` (сотрудник запомнил лицо). Знакомства односторонние,
  живут в `data/grm_identity/acquaintance.json`, есть `/знакомые`.
* Под легендой (маскировка) показывается прикрытие и знакомство НЕ пишется.
* Тег организации и должность — только на службе; номер ГР по настройке
  `grm_nameplate_cid` (never / gov / all); режим имени `grm_nameplate_mode`
  (open / acquainted / docs, по умолчанию docs).
* Особые приметы: `/приметы` (редактор), хранение
  `data/grm_identity/marks.json`, показ — только в справке `/pcboard`
  (новый блок «Внешность и особые приметы»).
* Вкладка «Госбаза» добавлена в 9 служебных компьютеров: поле запроса,
  «Пробить», «Моя карточка», «Журнал», живая карточка справки.
* Стенды: `sim_nameplate_runtime` (57), `sim_nameplate_ui` (44).
* Ловушка, пойманная стендом состава: помощник `mkButton` объявлялся НИЖЕ
  функции, которая его вызывает — перенесён выше (правило форвард-локалов).
* Не проверено вживую: снятие старых HUD на живом сервере (если чей-то
  аддон вешает свой `HUDPaint` с другим именем — пришлите скрин).

## Ход 21.08 (1) — окно «Госбаза» крупнее и читаемее

* Заказ владельца по скриншоту: «меню настроек побольше бы в размере».
* Окно доступов теперь тянется под экран (86% ширины / 88% высоты, но не
  меньше 1020×700) и меняется мышью (`SetSizable`); окно справки — 42%/78%.
* Левая колонка шире (30% окна, до 460 px), строки узлов выше (34 px),
  длинные названия отделов обрезаются с многоточием по фактической ширине
  и по границам UTF-8 — раньше «Подотдел: Управление Начальника ВАИ
  Гарнизона» налезал на метку уровня.
* Нижняя панель: подпись поля рисуется НАД вводом (раньше «Кулдаун, с»
  уезжал под сам DNumberWang), галочки получили явную ширину и видимый
  текст (у DCheckBoxLabel в Dock ширина от текста не считается), появилась
  подсказка «изменения применяются после Сохранить».
* Стенд `sim_pcboard_ui` дополнен разделом про размер и читаемость (56).

## Ход 21.08 (2) — микрофризы: очередь записи, пачки синхронизаций, ворота аудита

* Заказ: «синхронизация, разбитие на части и порядок выполнения кода,
  проверка всех модулей, чтобы ничего не вызывало микрофризы; код должен
  выполняться по степени важности, порционно».
* Новый слой `GRM.Save` v1.0.0 (`sh_05_grm_save.lua`): модуль регистрирует
  файл и сборщик, в горячем пути зовёт `Mark` (флаг), писатель пишет не
  более ОДНОГО файла за тик, дорогой реестр сам получает большую задержку,
  сброс при `ShutDown`/`PreCleanupMap`, `grm_save_status`/`grm_save_flush`.
* На очередь переведены: реестр номеров ГР/ИГ, знакомства и приметы шапки,
  журнал и доступы `/pcboard`.
* Синхронизации сведены в пачки через `GRM.Perf.Coalesce`: список персонажей
  (факции, 0.5 c), снимок прав администрации (0.5 c), настройки Q-меню
  (0.5 c), данные карты (0.25 c). Протокол не менялся.
* Стамина: тик 0.1 c → 0.25 c с расчётом по реальной дельте (поведение то же,
  работы вдвое меньше). Второй таймер наручников получил ранний выход.
* `tools/audit_perf.py`: три новые проверки (диск в горячем пути, крупные
  синхронизации, тяжёлый вход игрока), исправлены две ошибки самого аудита
  (обрезка тела хука по отступу; тяжёлый вызов за ранним выходом), добавлен
  режим ворот `--gate` — ненулевой код возврата на критичных находках.
* Полный отчёт: `AUDIT_2026-08-21_MICROFREEZE.md` (там же памятка, как писать
  последующий код: Boot-тиры, Spread, Coalesce, Save, Stream, Guard).
* Стенды: `sim_save_queue` (23 живых), `sim_perf_order` (37).
* Ворота аудита сейчас проходятся; находки, что остались, — осознанные
  (короткие таймеры с ранним выходом, разовые снимки терминалов).

## Ход 21.08 (3) — уровни «Юстиция» и «Пожарная служба» в госбазе

* `PB.Levels` дополнен: `justice` (Юстиция, ранг 3, метка ЮСТ) и `fire`
  (Пожарная служба, ранг 1, метка ПОЖ); оба появились в списке выбора
  редактора «Госбаза».
* Юстиция видит: личность, приметы, розыск и статьи, штрафы, удостоверения,
  воинский учёт, место службы, транспорт, недвижимость, образование, журнал
  пробитий. Медкарта и легенды — только галочкой.
* Пожарная служба видит: личность, приметы, недвижимость (владелец объекта),
  медкарта. Розыск, штрафы, воинский учёт, транспорт — закрыты.
* Скрытый запрос по-прежнему только у спецслужб и администрации.
* Стенды: `sim_pcboard_runtime` (120), `sim_pcboard_ui` (62).

## Ход 21.08 (4) — две плашки над головой и клетка в админ-меню

* Жалоба по скриншоту: над головой рисуются ДВЕ подписи сразу (старая
  плашка описания + старая шапка организации поверх новой).
  Реальная причина: `hook.Remove` не помогает — `sh_grm_rpdesc.lua`
  грузится ПОСЛЕ модуля шапки (алфавит autorun) и вешает свой `HUDPaint`
  заново. Теперь старые отрисовки гасятся В ИСТОЧНИКЕ: обе проверяют флаг
  `GRM.Nameplate.Active` и молчат, пока новая шапка включена. Выключил
  `grm_cl_nameplate 0` — старые вернулись (`cvars.AddChangeCallback`).
* Плашка в транспорте считается от габаритов машины, а не от костей игрока
  (раньше уезжала в кузов).
* Диагностика `grm_nameplate_debug`: режим, радиус, число знакомых и список
  старых отрисовок в `HUDPaint`.
* Клетка (`A.jail`) переписана. Что было не так: стенки ставились на
  фиксированные 48 юнитов при другой ширине модели (щели в углах — человек
  выходил боком), клетка строилась без выравнивания по земле, ничто не
  держало внутри (ноклип, физган, тулган), на каждого заводился свой
  `timer.Simple`. Теперь: расстояние из габаритов модели (OBB), центр по
  трейсу вниз, игрок ставится в центр, «поводок» возвращает вышедшего,
  ноклип/физган/тулган/урон по решёткам запрещены, сроки ведёт ОДИН общий
  таймер 0.5 c, прежняя позиция возвращается при освобождении.
* Стенды: `sim_admin_jail` (28 живых прогонов), `sim_nameplate_ui` (50).

## Ход 21.08 (5) — объявления администрации и живые ранги в TAB

* Новый общий слой `GRM.Admin.Announce(text, kind)`: красная строка ВСЕМ
  игрокам (`[АДМИНИСТРАЦИЯ]` для групп, `[МОДЕРАЦИЯ]` для наказаний) со
  звуком. Один канал на всё, без копий по модулям.
* Смена группы (`AD.ApplyGroup`) объявляется: «кто, кому, из какой группы в
  какую» — названиями групп, а не их id.
* Наказания: формулировки собраны ОДНОЙ таблицей `PUNISH` рядом с
  действиями, объявление уходит из общего приёмника после успешного
  действия. Различается «посадил / выпустил», «закрыл чат / вернул чат» —
  состояние читается ДО выполнения (кнопка одна и та же). В тексте срок
  (клетка, бан) и причина (кик, бан, предупреждение).
* Кнопки наказаний в самом TAB (заглушить, кик, бан, ULX-мут) — отдельный
  путь, их тоже подключили к тому же слою.
* TAB: ранг берётся из `GRM.Admin.GroupOf` (раньше смотрел только в ULib и
  флаги движка — назначение через админ-панель не отражалось вообще),
  группа висит на игроке NW-строкой `GRM_AdminGroup`, в список уходят
  название и цвет группы (свои группы больше не показываются обрубком из
  трёх букв), а по хуку `GRM_AdminGroupChanged` таблица обновляется сразу,
  а не через 5 секунд автообновления.
* Стенды: `sim_admin_announce` (29 живых прогонов), `sim_admin_core` (127).

## Ход 21.08 (6) — пожар: спам «потушен» и лишние вызовы во время тушения

* Реальная причина обоих багов одна: `RefreshIncidents(pos)` вызывался на
  КАЖДУЮ погашенную ячейку vFire и внутри звал `OpenIncident`. Инцидент
  рядом уже был помечен `out` (findInc его не видит) — открывался НОВЫЙ
  инцидент с peak=1 и cells=0, который тут же признавался потушенным
  («Пожар потушен» ещё раз) и по пути дёргал `GRM_FireIncidentOpened`,
  из-за чего диспетчер создавал новый вызов прямо во время тушения.
* Правки: обновление больше НЕ открывает инциденты; `OpenIncident`
  отказывается создавать очаг там, где нет живого огня (кроме
  принудительного скана карты, и у такого «призрака» peak = 0, он молчит);
  вспышка на месте только что потушенного очага (45 с) оживляет ТОТ ЖЕ
  инцидент без нового вызова; `MarkExtinguished` молчит при peak < 1.
* Диспетчер: минуту после закрытия вызова новый вызов рядом (600 юн.) не
  создаётся — `D.RecallGuard`.
* Сообщения: убран безусловный дубль тоста строкой в чат — теперь по
  конвару `grm_fire_chat_dupe` (по умолчанию 0, чат остаётся фолбэком, если
  модуль уведомлений не загружен).
* Журнал пожаров писался «прочитать файл целиком + записать обратно» на
  каждое событие — переведён на очередь `GRM.Save` (память + запись раз в
  10 с).
* Стенд: `sim_fire_incidents` (20 живых прогонов).

## Ход 21.08 (7) — живой пинг в TAB

* Жалоба: пинг меняется только при повторном открытии TAB.
  Причина: строка рисовала значение из СНИМКА сервера, который приходил при
  открытии и раз в 5 секунд; сам пинг доступен на клиенте бесплатно.
* Теперь строка списка берёт `Player:Ping()` у живой entity каждый кадр
  (список игроков кэшируется на секунду, `player.GetAll()` в отрисовке не
  зовётся), а в карточке игрока подпись обновляет себя два раза в секунду.
* Снимок с сервера больше не пересобирает список целиком: при неизменном
  составе поля обновляются на месте (пропали мигание и сброс прокрутки),
  пересборка — только когда кто-то зашёл или вышел. Интервал снимка 5 → 2 с,
  поэтому баланс, фракция и группа тоже свежие.
* Стенд: `sim_tab_menu` (33).

## Ход 21.08 (8) — помощь пострадавшему: вернулась реанимация

* Жалоба: у игрока в окне помощи одна кнопка «Стабилизировать».
  Причина: клиент рисовал «Реанимировать» только при флаге medic, а сервер
  считал его цепочкой, которая ОБРЫВАЛАСЬ на первом источнике —
  `GRM.MedicalFull.IsMedic` (там жёстко зашита фракция «Медики», которой на
  сервере нет) возвращал false, и ни медицинский допуск фракции, ни аптечка
  дальше не проверялись.
* `EM.IsMedic` переписан цепочкой ИЛИ: суперадмин, `MedicalFull.IsMedic`,
  `Medical.CanTreat`, уровень госбазы «Медицинский» или «Пожарная служба»,
  предмет из `EM.ReviveItems` (адреналин, аптечка, дефибриллятор, бинт).
  Возвращает ещё и ПРИЧИНУ отказа.
* Окно пострадавшего переписано: видны все действия — «Стабилизировать»,
  «Реанимировать» (заблокирована с причиной, если нет допуска), «Осмотреть»
  (доступно всем, печатает состояние и даёт РП-действие рядом), «Вызвать
  медицинскую службу (911)». Внизу подсказка, что делать дальше.
* В пакет карточки добавлены кровопотеря, боль и причина отказа.
* Стенд: `sim_911_aid` (23 живых прогона).

## Ход 21.08 (9) — «восстановлено 0 бланков»: причина теперь видна

* Жалоба: C-меню показывает «Восстановить бланки (4)», а восстанавливается 0.
* Реальная причина молчания: команда `/docrestore all` собирала ошибки в
  таблицу и ВЫБРАСЫВАЛА её — игрок видел только счётчик. Сама же выдача чаще
  всего падала на общей блокировке записи: если инвентарь (или реестр
  документов) загрузился из повреждённого файла, любое сохранение
  запрещается на всю сессию, бланк выдаётся и тут же откатывается.
* Теперь: `DOC.StorageBlockedReason()` проверяется ДО выдачи и объясняет
  человеку, что именно заблокировано; `/docrestore all` печатает причины
  (сгруппированные) и счётчик «N из M»; появилась диагностика
  `/docrestore диаг` — состояние хранилища, занятость инвентаря и построчно
  по каждому типу (есть ли запись, копии, статус, кулдаун).
* Инвентарь: добавлены `grm_inv_health` и `grm_inv_unblock confirm`
  (суперадмин) — раньше выйти из блокировки записи было нечем, кроме
  рестарта с ручной правкой файла; при старте в консоль печатается
  громкое предупреждение.
* Стенд: `sim_doc_restore` (17 живых прогонов).

## Ход 21.08 (10) — два вида бана: на сервере и глобальный

* Новый модуль `GRM.ServerBan` v1.0.0 (`sh_grm_ban.lua`).
* **Бан на сервере**: модель `models/player/skeleton.mdl`, материал
  `debugwhite`, красная подсветка, плашка «ЗАБАНЕН» над головой (через общий
  слой шапки, хук `GRM_NameplateOverride`), памятка на экране самому
  наказанному. Оружие изымается, самоубийство, меню F1-F4, физган, тулган,
  транспорт, подбор предметов, спавн и команды в чате закрыты; обычный чат
  оставлен, чтобы человек мог объясниться. Урон по нему и от него не идёт.
* **Зона отбывания**: суперадмин ставит точку по своей позиции
  (`grm_ban_point [радиус]` или кнопка в админ-меню), точка своя на каждую
  карту, хранится в `data/grm_admin/serverban_zone.json`. Сторож 0.5 с
  возвращает вышедшего за радиус и дожимает вид (другие модули любят вернуть
  модель), он же снимает истёкшие баны.
* **Глобальный бан** остался прежним (ULib/ULX, иначе `banid`), рядом
  появилось снятие — действие `unban` по SteamID64 или номеру ИГ-####.
* Админ-меню: «Бан на сервере 60 мин» / «Снять бан сервера», «Глобальный бан
  60 мин», «Глобальный бан навсегда», «РАЗБАНИТЬ» в блоке по ID, блок «Бан на
  сервере · зона отбывания» (радиус, «поставить здесь», «где точка»,
  «кто отбывает»). В карточке игрока появился флаг «БАН НА СЕРВЕРЕ».
* Всё объявляется в чат красной строкой общим слоем `GRM.Admin.Announce`.
* Стенды: `sim_server_ban` (45 живых прогонов), `sim_admin_core` (148).

## Ход 21.08 (11) — бан на сервере: причина, эфир и голод

* В админ-меню отдельный блок «Бан на сервере (деморган)»: поле срока, поле
  ПРИЧИНЫ (без причины кнопка не сработает) и две кнопки — «ЗАБАНИТЬ НА
  СЕРВЕРЕ» и «РАЗБАНИТЬ НА СЕРВЕРЕ». Причина уходит игроку, в объявление и
  в запись бана; автоподстановки «Нарушение правил» больше нет.
* Эфир: единый запрет `SB.SpeechBlocked` / `SB.DenySpeech` с текстом «Вы
  отбываете административное наказание (деморган), поэтому <волна>
  недоступна. Осталось: N мин.». Волны организаций (`/fr`, `/frb`, `/dep`,
  `/d`, `/depb`, `/db`) закрыты В ПРИЁМНИКАХ net, а не только в чате —
  команды туда уходят с клиента пакетом, чат-блокировка их не ловила.
  Радиоэфир (`GRM.RadioNet.VoiceRoute`) наказанного тоже не слышен.
* Чат-команды дают конкретный текст: для волн — про волну и рацию, для
  остальных — общий; обычный чат остался.
* Голод: отбывающие наказание всегда сыты — смерть от голода в деморгане
  это баг, а не наказание.
* Стенды: `sim_server_ban` (61 живой прогон), `sim_admin_core` (160).

## Ход 21.08 (12) — бан: живой таймер, блокировка окон, список и память

* Таймер в памятке наказанного идёт вживую (как пинг в TAB): значение
  считается в самой отрисовке — «Осталось: 12:47», меньше минуты подсвечено
  жёлтым, бессрочный так и подписан.
* Инвентарь закрыт: одна проверка на все действия (открытие, использование,
  выброс, перенос, разделение, уборка оружия) с текстом про наказание.
* «Ничего не открывать»: C-меню и спавн-меню закрыты хуками, а окна, которые
  успел открыть сторонний модуль, закрывает сторож (раз в 0.5 с, не в кадре).
* Список забаненных: `SB.List()` + окно «БАНЫ НА СЕРВЕРЕ» (кнопка «СПИСОК
  ЗАБАНЕННЫХ» в админ-меню, консоль `grm_serverban_menu`): кто, за что, кем
  выдан, сколько осталось, в сети ли, и кнопка «РАЗБАНИТЬ» на каждой строке.
* Память: сами баны и ИСТОРИЯ (последние 200 записей: выдача и снятие с
  причиной и автором) лежат в `data/grm_admin/serverbans.json` и переживают
  перезапуск; при входе бан применяется автоматически.
* Стенды: `sim_server_ban` (71 живой прогон), `sim_admin_core` (174).

## Ход 21.08 (13) — забаненные «звучат»: зомби-стоны

* От отбывающего наказание идут звуки зомби
  (`npc/zombie/zombie_voice_idle1..6.wav`): один стон сразу при бане, дальше
  с паузой 4–9 с. У каждого свой момент следующего звука — толпа скелетов не
  воет в унисон.
* Звук идёт из ОБЩЕГО сторожа банов (без таймера на каждого игрока), по
  каналу `CHAN_VOICE`, со случайной высотой тона.
* Прекэш — через общий звуковой слой `sh_07_grm_sound.lua` (реестр + фолбэк
  на отсутствующий файл), своей копии логики в модуле банов нет.
* Конвары: `grm_ban_zombie_sound` (0 — тишина), `grm_ban_zombie_min`,
  `grm_ban_zombie_max` — пауза между звуками.
* Стенды: `sim_server_ban` (81), `sim_admin_core` (181), `sim_sound_time` (27).

## Ход 21.08 (14) — точка отбывания бана больше не слетает

* Причина: точка хранилась как `Vector`, а `Vector` — это userdata, и
  `util.TableToJSON` пишет его пустышкой. На диск уходило `pos: {}`, после
  рестарта координаты читались нулями и зона считалась незаданной.
* Точка теперь хранится числами `{x, y, z}`, Vector собирается при
  использовании (`SB.ZonePos`). Нулевые координаты из битого файла точкой
  не считаются.
* Запись идёт сразу (`GRM.Save.Flush`), не дожидаясь очереди: точку ставят
  редко, а теряют обидно.
* При загрузке модуль печатает в консоль, есть ли точка на этой карте и
  какой радиус.
* Стенды: `sim_server_ban` (89 живых прогонов, в том числе «рестарт» с
  чтением только с диска), `sim_admin_core` (187). В стенде заменил заглушку
  JSON на настоящий кодировщик — с «{}» эта ошибка была бы не видна.

## Ход 21.08 (15) — фикс: после разбана человек «ничего не мог»

* Две настоящие причины, обе мои:
  1. клиентский сторож окон делал `panel:Remove()` — вместе с чужими окнами
     сносил панель чата (EasyChat). После удаления она уже не создавалась
     заново, поэтому и чат, и меню оставались мёртвыми даже после разбана.
     Теперь сторож только ЗАКРЫВАЕТ окна (`Close`/`SetVisible(false)`), а чат
     и HUD не трогает вовсе (проверка по классу и имени панели);
  2. `SB.Clear` вызывал `ply:Spawn()` — принудительный респавн ломал РП-поток
     модуля персонажей. Теперь снятие возвращает вид и подвижность на месте
     (`Freeze(false)`, `MOVETYPE_WALK`), а снаряжение выдаётся штатным хуком
     `PlayerLoadout`.
* Дополнительно: повторный бан больше не затирает запомненную модель
  скелетом (иначе после разбана человек оставался скелетом); сторож сам
  снимает следы наказания с уже свободного игрока; появилась аварийная
  команда `grm_serverban_fix [SteamID64|me|all]`.
* Стенды: `sim_server_ban` (101 живой прогон), `sim_admin_core` (195).

## Ход 21.08 (16) — фикс: unpooled message name у списка банов

* `grm_serverban_menu` падал с «Calling net.Start with unpooled message
  name»: в модуле банов регистрировался только канал SYNC, а каналы списка
  (LIST_REQ / LIST) добавили позже и строку сети для них — нет.
* Теперь имена регистрируются проходом по таблице `SB.Net` — добавил канал,
  он сразу в пуле.
* В аудит добавлена проверка `net_unpooled`: если в таблице `X.Net` каналов
  больше, чем вызовов `util.AddNetworkString`, и нет прохода по таблице —
  находка попадает в ворота (`--gate` вернёт ошибку). Проверено на
  синтетическом файле: ловится.
* Стенды: `sim_perf_order` (41), `sim_server_ban` (101).

## Ход 21.08 (17) — возврат на исходное место после разбана

* При бане запоминается точка, откуда игрока забрали (числами, в записи
  бана — поэтому переживает рестарт сервера).
* Снятие наказания — ручное, по истечении срока и через аварийную команду —
  возвращает человека ровно туда, откуда он «улетел в бан», и пишет ему
  «Вы возвращены на прежнее место».
* Если игрок перезашёл или сервер перезапускался, точка подхватывается из
  записи при применении бана (`ply.GRM_BanReturn`).
* Стенды: `sim_server_ban` (106 живых прогонов), `sim_admin_core` (200).

## Ход 21.08 (18) — законы: доступы, обновление и рекурсия CAMI

* **`[ULib] stack overflow`**: `AD.Can` спрашивал CAMI → CAMI звал наш хук
  `CAMI.PlayerHasAccess` → хук снова звал `AD.Can` → бесконечный круг.
  Любое действие, где проверялось право (публикация закона в том числе),
  обрывалось на середине — отсюда и «законы не обновляются».
  Разделено: `AD.CanLocal` (наши группы и права, без CAMI) и `AD.Can`
  (локальная проверка + один запрос к CAMI со сторожем глубины). Ответчик
  CAMI отвечает `CanLocal`.
* **Доступы к кодексу**: право `laws.edit` было `minAccess = "admin"` — его
  автоматически получал любой админ/модератор. Теперь `superadmin`, то есть
  только явная выдача (группой или должностью `law_publish`). Удаление —
  отдельное право `laws.remove` / `law_remove`: публикация больше не даёт
  права сносить статьи.
* **Интерфейс кодекса**: у зрителя больше нет ни полей, ни кнопок —
  показывается текст статьи и подпись «правка доступна только уполномоченным
  должностям»; в шапке честный статус «Режим просмотра · правка недоступна».
* **Раздел настроек законов в /factions**: без права управления показывает
  только текущее состояние ролей, галочек нет; сервер при попытке без права
  отвечает сообщением и пересинхронизирует состояние (раньше молчал).
* **Обновление у игроков**: помимо адресной рассылки «зрителям» уходит
  крошечный сигнал `GRM_Laws_Changed` всем — у кого окно открыто, тот сам
  запрашивает свежий список. Расхождение списка зрителей с реальностью
  больше не оставляет людей со старым кодексом.
* Стенды: `sim_laws_access` (35 живых прогонов, включая воспроизведение
  рекурсии CAMI), `sim_admin_core` (200).

## Ход 21.08 (19) — инструмент «GRM Сканер фракций» переработан

* Причина «списка нет»: панель строила чекбоксы из клиентского кэша
  `FactionsData`, которого в момент открытия инструмента может не быть
  (публичный синк приходит позже). Теперь список запрашивается У СЕРВЕРА
  (`GRM_ScannerTool_ListReq` / `GRM_ScannerTool_List`, с `GRM.Net.Guard`).
* В списке человеческие названия, тег организации и число сотрудников,
  сортировка по названию; есть строка поиска, счётчик «показано/выбрано»,
  кнопки «Все», «Снять», «Обновить список»; пока список не пришёл — поле
  ручного ввода, как раньше.
* Отметки складываются в конвар списком через запятую (сканер это и ждёт),
  добавление и снятие не затирают остальной выбор.
* Сообщение сканера об отказе показывает названия организаций, а не
  внутренние ключи.
* Ловушка, найденная стендом Q-меню: у `TOOL` метатаблица-заглушка, поэтому
  `TOOL.FactionRows or {}` возвращал ФУНКЦИЮ и `ipairs` падал. Список теперь
  в локальной переменной файла.
* Стенды: `sim_scanner_tool` (17 живых прогонов), `sim_qmenu_toolpanel` (37).

## Ход 21.08 (20) — приглашение во фракцию не приходило

* Главная причина: меню организаций НЕ слушало канал ответа
  `Factions_ActionResult`. Сервер честно отвечал «Недостаточно прав»,
  «Недопустимая стартовая должность», «Персонаж уже состоит во фракции»,
  «У персонажа уже есть активное приглашение», а меню само рисовало
  «Приглашение отправлено» — лидер был уверен, что отправил, а приглашения
  не существовало. Теперь ответ сервера показывается уведомлением и строкой
  в чат.
* Вторая причина: приглашение сохранялось даже когда персонажа нет в сети
  (или человек играет другим персонажем) — окно доставить некому. Теперь
  такой случай — честный отказ с объяснением, а выдача пишется в консоль.
* Окно приглашения: должность и отдел выбраны заранее, должность лидера в
  список не попадает (сервер её всё равно отклоняет).
* Приглашение возвращается не только при входе и смене персонажа, но и
  после респавна.
* Диагностика `grm_faction_invites`: кому, от кого, из какой организации,
  в сети ли персонаж и сколько осталось.
* Стенд: `sim_faction_invite` (21 проверка).

## Ход 21.08 (21) — антистак транспорта: без столкновений и выход сбоку

* Настоящая причина, почему «сталкивало корпусом»: в распознавании
  транспорта стояла строка «sim_fphys», а классы simfphys называются
  `simfphys_*` (например `simfphys_btr80`). Ни одна машина simfphys под
  проверку не попадала — ни no-collide, ни поиск базы под сиденьем не
  работали. Теперь список подсказок расширен (simfphys, lvs, glide,
  prop_vehicle, gmod_sent_vehicle) и дополнен признаками самих аддонов
  (`IsSimfphysCar`, `LVS`).
* Постоянное отсутствие столкновения «игрок ↔ транспорт»: отдельный хук
  `ShouldCollide` с быстрым выходом (сначала дешёвый IsPlayer). Временный
  no-collide на 1.25 с остался как был — он про другое.
* Выход сбоку от КОРПУСА: точка считается по габаритам базовой машины,
  сторона выбирается та, где игрок, отступ — полшины корпуса плюс
  `SideExitOffset` (10 юнитов). Занят борт — пробуем другой, потом корму и
  нос; свободного места нет — не двигаем вовсе.
* Настройки: `AlwaysNoCollideWithVehicles`, `SideExitOnLeave`,
  `SideExitOffset`.
* Стенд: `sim_vehicle_exit` (20 живых прогонов).

## Ход 21.08 (22) — В/У больше не проверяются при посадке в транспорт

* Убрана автоматическая инспекция водительских прав на хуке
  `PlayerEnteredVehicle` (`sh_grm_documents.lua`). Сообщений вида
  «ВАИ проверено (Категория С)», «В/У проверено», «Нет В/У категории…»,
  «ВУ просрочено» при посадке в машину или на кресло больше нет.
* Проверка не удалена совсем, а переведена в ручной режим: конвар
  `grm_doc_vehicle_check` (по умолчанию 0). Значение 1 возвращает старое
  поведение целиком, если оно когда-нибудь понадобится.
* Проверка документов по требованию (ГАИ/ВАИ, `/pcboard`, досмотр) работает
  как раньше — трогали только автоспам при посадке.
* Стенд: `sim_vehicle_license_notice` (11 живых проверок: тишина по
  умолчанию, грузовик, водитель без прав, кресло, пассажир, включение
  конвара и обратно).

## Ход 21.08 (23) — меню точек спавна переделано: отделы, подотделы, стиль GRM

* Меню `/spawnmenu` больше не «вкладка на каждую организацию с тремя
  подвкладками». Слева — дерево: «Глобальные точки», затем организации,
  внутри — «Точки организации», ОТДЕЛЫ (с вложенными ПОДОТДЕЛАМИ),
  ДОЛЖНОСТИ. У каждого узла счётчик точек, у организации — сумма по всем
  уровням. Есть поиск по организациям, отделам, подотделам и должностям
  (кириллица ищется без учёта регистра), раскрытие/сворачивание узлов.
* Добавлены ТОЧКИ ПОДОТДЕЛОВ — раньше их не было вовсе, хотя подотделы в
  структуре организаций есть. Хранение `subdepartments` в том же файле
  карты, валидация ключа по `f.Subdepartments`.
* Приоритет выдачи точки игроку: подотдел → должность → отдел →
  организация → глобальные (совпадает с логикой выдачи экипировки).
* Справа — карточки точек: номер, координаты, поворот, расстояние до вас,
  кнопки «Телепорт» и «Удалить». Панель действий: «Поставить здесь»,
  «Куда смотрю» (точка по прицелу), «Обновить», «Экспорт», «Очистить узел»
  (с подтверждением). Пустой узел показывает подсказку, а не пустоту.
* Стиль приведён к общему GRM: палитра и шрифты как в едином центре
  организаций, иконки icon16 (мир, здание, папка, подпапка, пользователь,
  стрелки раскрытия, корзина, обновление), скруглённые карточки, свои
  скроллбары, окно масштабируется под разрешение.
* Команда работает и через ванильный чат (`PlayerSay` на сервере), и через
  EasyChat, плюс алиасы `/точкиспавна` и консольная `grm_spawnmenu`.
* Точки узлов, которых уже нет в структуре (удалённый отдел/должность),
  показываются с пометкой «вне структуры» — иначе их нельзя было удалить.
* Стенд: `sim_spawn_menu` (48 проверок), старый `sim_spawn_points` (25) —
  зелёный.

## Ход 21.08 (24) — двери: перестали запираться сами, ключи проверены

* НАСТОЯЩАЯ ПРИЧИНА «дверь сама заперлась через несколько секунд»:
  двустворчатая дверь — это ДВА полотна с ДВУМЯ записями. `LockDoor` писала
  новое состояние только в запись того полотна, по которому кликнули, а
  сторож замков (каждые 2 с) приводил каждую запись к её собственному
  значению — вторая створка возвращала замок и дёргала общий сетевой флаг.
* Теперь у физической двери одно состояние: `D.DoorGroup` собирает полотно,
  его дубли, вторую створку и её дубли; `LockDoor` пишет состояние во ВСЕ
  записи группы и ставит метку времени `lock_at`. Сторож сверяет группу
  целиком (`D.ResolveGroupLock` — побеждает самая свежая запись) и лечит
  старый рассинхрон вместо того, чтобы воевать сам с собой.
* Автоблокировка стала ЯВНОЙ и по умолчанию выключена: конвар
  `grm_door_autolock` (0 — никогда, например 8 — дверь сама запирается через
  8 секунд после отпирания). Выбитые тараном и вскрытые отмычкой двери под
  автоблокировку не попадают.
* Ключи (`ds_key_swep`): раньше проверяли только «есть ли доступ» — замком
  щёлкал любой, у кого есть проход, даже на общественных дверях и там, где
  замок оставлен администрации. Теперь общая проверка `D.CanToggleLock`
  (право на замок + профиль категории), отказ с внятной причиной, «дверь и
  так заперта/открыта» вместо холостого срабатывания, а режим «дверь всегда
  заперта» больше не рапортует «разблокировано» — честно говорит, что дверь
  не отпирается.
* Запись реестра дверей переведена на очередь `GRM.Save` (`grm_doors`,
  задержка 3 с): замок дёргается часто, а каждый щелчок писал JSON на диск.
  Немедленная запись осталась отдельной функцией `D.SaveDoorsNow`.
* Стенд: `sim_door_lock_sync` (33 живые проверки), обновлён `sim_door_menu_ui`.

## Ход 21.08 (25) — категории дверей не прыгают вверх, покупка ≠ выдача

* Список в категориях дверей улетал вверх после КАЖДОЙ галочки, потому что
  на ответ сервера окно двери создавалось ЗАНОВО, а восстановление
  прокрутки не поспевало за раскладкой. Теперь окно живёт дальше: приходит
  свежий снимок той же двери — оно обновляется на месте (`GRMPatch`).
  Если поменялись только галочки (подпись данных `D.MenuSignature` та же) —
  правится состояние чекбоксов, вкладка не пересобирается вообще, прокрутка
  не двигается. Если состав категорий или структура организаций изменились —
  пересобирается только вкладка, а прокрутка запоминается ДО очистки.
  Программная установка галочки не шлёт действие на сервер (не зацикливается).
* Дилер транспорта: «КУПИТЬ» больше НЕ равно «ВЫДАТЬ». Покупка личного
  транспорта только оформляет его в собственность — машина встаёт на
  хранение (и приписывается к выбранному гаражу). На карту она выходит
  отдельной кнопкой «ВЫДАТЬ» во вкладке «Мой транспорт», где игрок выбирает:
  выдать здесь у дилера или подать в гараж (список гаражей с числом мест).
  Служебный транспорт покупкой не является — выдаётся сразу («ПОЛУЧИТЬ»).
* Новое в модуле гаражей: `GRM.Garage.IssueRemote` — подача машины на
  свободное место выбранного гаража издалека (с платой за подачу, проверкой
  доступа и мест).
* Режим дилера теперь ограничивает только выдачу НА МЕСТЕ («Отправлять в
  гараж» = этот дилер машины не отдаёт); подача в гараж доступна всегда,
  пока есть доступный гараж.
* Стенды: `sim_dealer_buy_issue` (20 живых проверок покупки и выдачи),
  дополнены `sim_door_menu_ui` (62), `sim_door_lock_sync` (38),
  обновлены `sim_garage_module`, `sim_vehicle_class_limit`.

## Ход 21.08 (26) — регистрационные номерные знаки

* Новый модуль `GRM.Plates` (`sh_grm_plates.lua`) + сущность `grm_plate`.
* Жизненный цикл знака: регистрация в Полиции / Дорожной инспекции / ВАИ →
  получение физического бланка → установка руками на машину → проверка по
  базе → аннулирование или заявление об утере.
* Физический знак: модель `models/hunter/plates/plate025x075.mdl`, материал
  `models/debug/debugwhite`, номер печатается поверх (3D2D по габаритам
  модели, поэтому надпись не вылезает за края даже при смене модели).
  Ставится физганом куда нужно и крепится нажатием [E] — можно повесить
  и спереди, и сзади. Повторное [E] снимает; сотрудник может изъять.
* Реестр `data/grm_plates/registry.json` через очередь `GRM.Save`: номер,
  тип, владелец, организация, транспорт, статус, кто и когда выдал, история.
* Шесть типов серий со своими шаблонами и цветом знака: гражданский
  (А000ВС), коммерческий, государственный, полицейский, военный,
  транзитный. Буквы — только «читаемые» (АВЕКМНОРСТУХ), латиница при вводе
  автоматически приводится к кириллице.
* Выдача: вкладка «Номерные знаки» в терминалах Полиции, Военной полиции и
  Автоинспекции, окно `/номера`. Проверка: `/номер А123ВС` и та же вкладка.
  Номер видно над машиной и над самим знаком (HUD, трассировка раз в 0.2 с).
* В госбазе (`/pcboard`) появился блок «Транспорт и номерные знаки».
* Знаки помнят своё место: раскладка пишется в запись гаража, после выдачи
  машины из гаража знаки возвращаются на бампера сами.
* Конвары: `grm_plates_limit` (сколько номеров на персонажа, по умолчанию 6),
  `grm_plates_blanks` (сколько физических бланков одного номера, по умолчанию 2).
* Стенд: `sim_plates` (58 живых проверок).

## Ход 21.08 (27) — номера: надпись встала на место, знак крепится

* НАДПИСЬ НЕ БЫЛО ВИДНО и номер стоял поперёк, потому что плоскость 3D2D
  строилась вручную поворотами углов «на глазок». Теперь геометрия лица
  считается чистой функцией `PL.FaceGeometry`: самая тонкая ось габаритов —
  толщина знака (её направление = нормаль), из двух оставшихся ДЛИННАЯ
  всегда идёт вдоль строки номера, короткая — вверх. Угол собирается через
  `Vector:AngleEx`, надпись подгоняется по ширине поля. Номер печатается с
  ОБЕИХ сторон — как знак ни поверни, он читается.
* ЗНАК НЕ КРЕПИЛСЯ: поиск транспорта мерил расстояние до ЦЕНТРА машины и
  требовал 90 юнитов, а у «Москвича» от бампера до центра больше сотни —
  система машину «не видела» и молчала. Теперь меряем до ПОВЕРХНОСТИ
  (`NearestPoint`), ищем в радиусе 400 и дополнительно простреливаем в шесть
  сторон от знака. Если машины действительно нет — игрок получает внятную
  подсказку, а не тишину.
* Добавлен самый естественный жест: держите знак физганом и нажмите [E] по
  бамперу — знак закрепится, а в салон вас не посадит.
* Запасные пути на случай, если [E] перехватывает что-то ещё: команды
  `/прикрепить` и `/снятьномер` (плюс консольные `grm_plate_attach` и
  `grm_plate_detach`) — берут ближайший ваш знак.
* Вся обработка [E] сведена в одну функцию `PL.HandlePlateUse` — один слой
  логики на все три пути (знак, машина в руках физгана, команда).
* Стенд `sim_plates` дополнен: 75 проверок (ориентация надписи для трёх
  разных габаритов, крепление при далёком центре машины, снятие, чужой знак,
  отсутствие транспорта рядом, [E] со знаком в руках).

## Ход 21.08 (28) — номер стало видно, привязка к конкретной машине, F4

* НАСТОЯЩАЯ ПРИЧИНА пустого знака: масштаб надписи делался через
  `cam.PushModelMatrix(m)` — а он БЕЗ второго аргумента ЗАМЕНЯЕТ матрицу
  3D2D, а не домножает её. Номер уезжал в мировые координаты, на знаке
  оставалась только заливка. Матрицы убраны: поле знака рисуется одним
  проходом, номер — вторым 3D2D с уменьшенным масштабом. Печать с обеих
  сторон сохранена.
* Знак теперь привязан к КОНКРЕТНОЙ машине: в реестр пишется
  `mount.vehicleID` (запись гаража — она переживает удаление машины и
  рестарт), название машины и точное место установки на кузове.
  Удалили машину — физический знак исчез вместе с ней, но привязка цела:
  при следующей выдаче ЭТОЙ машины знак сам встаёт на своё место.
  Восстановление идёт из двух источников (раскладка в записи гаража и сам
  реестр по vehicleID), дубли исключаются по номеру. У служебных и
  карт-машин записи нет — там знак живёт, пока живёт машина.
* В F4 добавлен раздел «Номерные знаки»: `/номера`, выдача через терминал,
  [E] по знаку, [E] по машине со знаком в руках, `/прикрепить`,
  `/снятьномер`, `/номер А123ВС`, куда ставить и как работает возврат.
* Стенд `sim_plates` — 85 проверок (добавлено 10 на привязку к машине:
  идентификатор, место установки, удаление машины, возврат после выдачи,
  отсутствие дублей, чужая машина знак не получает).

## Ход 21.08 (29) — автопарк организаций и единый тул транспорта

* Новый модуль `GRM.Fleet` (`sh_grm_fleet.lua`): техника больше не берётся
  «из воздуха» по факту принадлежности к организации, а ЗАКУПАЕТСЯ.
  Путь машины: рынок (суперадмин) → закупка руководством за счёт бюджета
  организации → приписка к гаражу → выдача сотруднику по месту стоянки →
  возврат → списание с возвратом части стоимости.
* РЫНОК. Суперадмин собирает каталог закупок: класс, название, цена,
  уровень допуска (гражданская / государственная / полицейская / военная /
  спецтехника), поимённый список организаций (сильнее уровня) и лимит
  единиц одного класса на организацию. Вкладка «Рынок» в том же окне.
* ДОСТУП. Закупает лидер организации, роль с правом «Закупка транспорта»
  (`fleet_buy`) или суперадмин; приписывать к гаражу и списывать может роль
  с правом «Распоряжение автопарком» (`fleet_manage`); брать машину —
  любой сотрудник организации. Права добавлены в общий список доступов
  фракций, поэтому настраиваются в уже существующем интерфейсе.
* ДЕНЬГИ. Стоимость списывается с бюджета организации, доля уходит в
  государственную казну (`grm_fleet_state_share`, по умолчанию 100%).
  Списание возвращает `grm_fleet_scrap` процентов (по умолчанию 60%).
* ГАРАЖ И ВЫДАЧА — ОДИН ЭКРАН. Служебная техника, приписанная к гаражу,
  видна в его окне отдельным блоком «Служебный автопарк организации»,
  выдаётся и возвращается там же и встаёт НА СВОБОДНЫЕ МЕСТА стоянки
  (то самое, что нравится: машины разъезжаются по разным точкам).
* ЕДИНЫЙ ТУЛ «GRM: транспорт» вместо двух разрозненных: зона гаража →
  места выдачи → стойка вызова → ворота → дилер → связать дилера с гаражом.
  Один порядок работы и одна панель настроек; старые тулы остались
  рабочими, чтобы не ломать привычку.
* Вкладка «Автопарк» добавлена в терминалы мэрии, полиции, военной полиции,
  армии, медицины и охраны; команда `/автопарк` (`/fleet`, `/закупка`).
* Стенд: `sim_fleet` (64 живые проверки на настоящих модулях парка и гаража).

## Ход 21.08 (30) — единый слой транспорта, техника по должностям, старые тулы

* Появился ДИСПЕТЧЕР `GRM.Vehicles` (`sh_grm_vehicles.lua`): один слой между
  интерфейсами и двумя хранилищами (личные записи гаража и автопарк
  организации). `V.Rows / V.Issue / V.Store / V.SetHome` — одинаковые
  правила и сообщения для любой машины. Окно гаража и его операции
  переведены на него: копий логики больше нет.
* ТЕХНИКА ПО ДОЛЖНОСТЯМ. Единицу автопарка можно закрепить за должностями
  и/или отделами (кнопка «ДОСТУП» в окне автопарка, выбор из структуры
  организации — руками ключи не набираются). Пустой список = доступна всем
  сотрудникам. В гараже посторонний видит машину, но кнопка подписана
  «НЕ ПОЛОЖЕНА», а выдача отклоняется и на сервере.
* Проверка закрепления — чистая функция `FL.UnitAllowedFor(unit, actor)`,
  поэтому гоняется в стенде на всех сочетаниях должность/отдел/подотдел.
* Старые тулы («GRM: гаражи», «Точка выдачи транспорта») помечены как
  устаревшие прямо в названии и панели — работать продолжают, но вся
  разметка теперь одним «GRM: транспорт». Подсказка в окне гаража тоже
  указывает на новый тул.
* Стенд `sim_fleet` — 89 проверок (добавлено 25: закрепление за должностью и
  отделом, отказ выдачи, суперадмин, смена закрепления, диспетчер —
  нормализация источника, общий список, выдача/возврат/приписка, честный
  отказ по несуществующей записи).

## Ход 21.08 (31) — окна терминалов шире, вкладки везде, поля подписаны

* ОКНА. Терминалы стояли на фиксированных 960×700 (мэрия — 780×620), из-за
  чего верхний ряд вкладок уезжал за край со стрелкой «ещё». Все девять
  терминалов теперь тянутся под экран: `ScrW()*0.86` (не меньше 1180 и не
  больше 1720) на `ScrH()*0.88` (760…1080). Пожарный пульт — своё, поменьше.
* ВКЛАДКИ ВЕЗДЕ. «Автопарк» и «Номерные знаки» добавлены во ВСЕ терминалы,
  где есть госбаза: мэрия, суд, медицина, армия, военная полиция, полиция,
  охрана, автоинспекция, документный ПК (было — в половине).
* ПОДПИСИ ПОЛЕЙ. Со своим `Paint` движок НЕ рисует подсказку `DTextEntry` —
  поэтому в окне рынка стояли четыре безымянных прямоугольника. Теперь
  подсказка рисуется вручную, а у формы рынка и панели закупки над каждым
  полем стоит заголовок: КЛАСС ТРАНСПОРТА, НАЗВАНИЕ В КАТАЛОГЕ, ЦЕНА ЗА
  ЕДИНИЦУ, ЛИМИТ НА ОРГАНИЗАЦИЮ, УРОВЕНЬ ДОПУСКА, КОМУ ПРОДАЁМ, ГАРАЖ
  ПРИПИСКИ, СКОЛЬКО ЕДИНИЦ.
* Стенд: `sim_terminal_layout` (54 проверки: размеры окон всех терминалов,
  наличие обеих вкладок рядом с госбазой, названия и иконки вкладок,
  ручная отрисовка подсказок, заголовки полей).

## Ход 21.08 (32) — тул транспорта переписан, старые файлы удалены

* УДАЛЕНЫ файлы старых тулов `stools/grm_garage.lua` и
  `stools/vehicle_dealer_tool.lua`. Всё их полезное перенесено в единый
  «GRM: транспорт»: превью разметки, привязка ворот, привязка гаража к
  объекту недвижимости (ПКМ по двери дома), удаление стойки по самой стойке
  («Стойка без записи удалена с карты»), личная точка выдачи дилера с
  направлением и высотой. Q-меню и админ-хаб больше не предлагают удалённые
  тулы, стенды переведены на новый файл.
* ПОНЯТНАЯ РАЗМЕТКА ЗОНЫ. Первый угол подсвечивается шаром, будущая зона
  рисуется прямо по курсору с размерами и предупреждением «МАЛО: нужна
  сторона от 200» — видно, что получится, ДО второго клика. R отменяет
  начатую разметку.
* ПОДПИСИ ВЕЗДЕ. В мире: гаражи (название, тип, счётчики), места выдачи
  («свободно / занято», стрелка направления), стойки, дилеры (и линия к
  гаражу, куда идут их покупки), точка выдачи дилера с высотой. На экране —
  панель «ЛКМ / ПКМ / R» под текущий режим. В панели тула настройки разбиты
  на блоки ГАРАЖ / МЕСТО ВЫДАЧИ / ДИЛЕР.
* Режимы: зона, место выдачи, стойка, ворота, дилер, связать дилера с
  гаражом, точка выдачи у дилера. Направление машины — по взгляду, по
  сторонам света и относительно дилера (вперёд/назад/влево/вправо).
* Стенд: `sim_transport_tool` (35 проверок), обновлены `sim_garage_module`,
  `sim_vehicle_dealer_v3`, `sim_vehicle_class_limit`, `sim_dealer_phone_boot`.

## Ход 21.08 (33) — места выдачи наконец работают

* НАСТОЯЩАЯ ПРИЧИНА «транспорт спавнится перед дилером»: выдача у дилера
  ВООБЩЕ не смотрела на гаражи — место бралось только из точки/площадки
  самого дилера, а размеченные места использовались лишь в окне гаража.
  Появился единый выбор места `VD.ResolveDeliveryPlace`: 1) явное место,
  2) свободное МЕСТО ГАРАЖА, связанного с этим дилером, 3) место домашнего
  гаража машины, если он рядом с дилером, 4) собственная точка дилера,
  5) перед дилером. В ответе игроку теперь пишется, куда именно подали
  («Транспорт выдан: место «Бокс 2» гаража «Автобаза»»).
* ВТОРАЯ ПРИЧИНА: `G.FreeSlot` отбраковывал место одним жёстким хуллом
  размером с машину — в тесном боксе (потолок, стены, колонна) заняты были
  ВСЕ места, и система молча уезжала к дилеру. Проверка стала ступенчатой:
  полный габарит → уменьшенный → «есть земля и рядом нет машины»
  (место отдаётся с пометкой «тесно»). Свободные места всегда идут раньше
  тесных.
* ДИАГНОСТИКА: `grm_garage_slots` (суперадмин) печатает по гаражу, где вы
  стоите: сколько мест, сколько связанных дилеров, по каждому месту —
  свободно / занято (и кем) / тесно, и куда пойдёт следующая машина.
* Стенды: `sim_fleet` — 93 проверки (добавлен тесный бокс и диагностика),
  `sim_dealer_buy_issue` — 25 (выдача у дилера уходит на место связанного
  гаража; без гаражей остаётся площадка дилера).

## Ход 21.08 (34) — места выдачи работают без привязок и объясняют отказ

* «Ноль реакции» объяснился охватом правила: место искалось только у гаража,
  СВЯЗАННОГО с дилером, или у домашнего гаража машины. Если админ просто
  разметил зону и места (а привязку дилера не делал) — правило не срабатывало
  ни разу. Теперь первым делом берётся гараж, В КОТОРОМ СТОИТ ИГРОК, затем
  гараж дилера и ближайший в пределах 1200 юнитов, и только потом связанный
  и домашний. Разметил места — машины на них появляются, без настроек.
* Служебный транспорт («ПОЛУЧИТЬ» у дилера) и админский спавн из ТАБ теперь
  идут через то же правило: раньше они спавнились строго у дилера мимо всех
  мест.
* Отказ больше не молчит: система собирает ПРИЧИНЫ по каждому кандидату
  («не размечено ни одного места», «нет доступа», «все места заняты»),
  показывает их суперадмину в чате после выдачи и печатает в консоль при
  `grm_vd_slot_debug 1`. Плюс уже есть `grm_garage_slots`.
* Стенд `sim_dealer_buy_issue` — 27 проверок (места без привязки дилера,
  дилер в чистом поле, объяснение отказа).

## Ход 21.08 (35) — надпись на знаке настраивается прямо в игре

* Гадать по габаритам модели оказалось ненадёжно: у plate025x075 «тонкая»
  ось OBB не совпала с видимой плоскостью, и поле знака рисовалось поперёк.
  Теперь раскладка НЕ угадывается, а настраивается и хранится на сервере
  (`data/grm_plates/render.json`), рассылается всем игрокам:
    - `/номер_поворот` — повернуть надпись на 90° (0/90/180/270);
    - `/номер_ось` — какая ось модели смотрит наружу (auto → x → y → z);
    - `/номер_зеркало` — отзеркалить (если читается с изнанки);
    - `/номер_масштаб 1.2` — размер поля относительно габаритов модели.
  Консольные аналоги: `grm_plate_yaw/axis/flip/scale`. Только суперадмин.
  Изменения видны сразу: у живых знаков сбрасывается кэш геометрии.
* По умолчанию поворот 90° — под текущую модель. Если модель заменят,
  подгонка занимает пару команд, а не правку кода.
* HUD с номером переделан: не «текст в воздухе», а маленькая табличка со
  цветным полем и полосой, как настоящий знак; под ней — статус, если номер
  аннулирован или заявлен утерянным.
* Стенд `sim_plates` — 99 проверок (повороты, оси, зеркало, масштаб, права
  на настройку, сохранение файла). Попутно `sim_forward_locals` поймал
  обращение к local-функции до объявления — исправлено форвард-декларацией.

## Ход 21.08 (36) — база номеров не теряется, надпись не тонет в пропе

* БАЗА НОМЕРОВ. Реестр читался при старте карты, а очередь записи работает
  с первой секунды: любой Save до загрузки (выключение, смена карты, чужой
  вызов) писал на диск ПУСТУЮ таблицу поверх выданных номеров. Теперь и
  сборка данных, и запись молчат, пока файл не прочитан (`PL._loaded`), а
  сам реестр читается сразу при загрузке модуля, а не только на старте
  карты. Та же защита поставлена автопарку и рынку закупок.
* НАДПИСЬ НЕ ТОНЕТ. Раньше номер рисовался в 0.15 юнита от ЦЕНТРА модели,
  то есть фактически внутри пропа. Появился «вынос» — насколько надпись
  вынесена наружу от поверхности: по умолчанию 1.5, настраивается командой
  `/номер_вынос 2.5` (консольная `grm_plate_offset`).
* ЗЕРКАЛО УБРАНО. Рисовалась и передняя, и задняя сторона; задняя
  просвечивала сквозь тонкую модель, и номер выглядел зеркальным. Теперь
  рисуется ТОЛЬКО та сторона, что смотрит на игрока — заодно вдвое меньше
  отрисовки.
* Стенды: `sim_plates` — 104 проверки (защита базы от затирания, вынос
  надписи), `sim_fleet` — 95 (та же защита для парка и рынка).

## Ход 21.08 (37) — вынос надписи идёт вперёд, а не вверх

* «Вынос» считался вдоль ВЫБРАННОЙ ОСИ модели (`/номер_ось`), а она может
  не совпадать с направлением взгляда на надпись — у владельца надпись
  уезжала вверх. Теперь вынос идёт строго по нормали САМОЙ ПЛОСКОСТИ
  надписи (векторное произведение её осей) и всегда в сторону игрока:
  «вперёд от текста» при любой оси и повороте.
* Заодно сторона и строка разворачиваются вместе, поэтому зеркальной
  изнанки не бывает даже на тонкой модели.
* Стенд `sim_plates` — 107 проверок (добавлены три на способ выноса).

## Ход 21.08 (38) — плашка номера только при взгляде на знак

* Плашка с номером посреди экрана появлялась при взгляде на ЛЮБУЮ машину с
  номером и висела поверх всего. Теперь она показывается, только когда
  прицел наведён НА САМ ЗНАК (энтити `grm_plate`), не дальше 400 юнитов.
  Трассировка по-прежнему троттлится (раз в 0.2 с), покадровых трейсов нет.
* Стенд `sim_plates` — 110 проверок.

## Ход 21.08 (39) — 3D2D-плашка, полная подгонка знака, порционные снимки

* НОМЕР НАД ЗНАКОМ теперь рисуется 3D2D прямо в мире, лицом к игроку, и
  только когда прицел наведён на сам знак. Экранная плашка посреди монитора
  убрана. В кадре — только математика билборда и две операции рисования,
  трассировка раз в 0.2 с, дальше 400 юнитов не рисуем.
* ПОЛНАЯ ПОДГОНКА ЗНАКА. К повороту, оси, зеркалу, масштабу и выносу
  добавлены доворот плоскости по ТРЁМ осям и сдвиг вдоль осей самой надписи:
    - `/номер_наклон p|y|r 15` — наклон / рыскание / крен;
    - `/номер_сдвиг x|y 2` — вправо-влево и вверх-вниз ПО ЗНАКУ;
    - `/номер_сброс`, `/номер_настройки` — вернуть базовую и показать текущие.
  Консольные: `grm_plate_tilt`, `grm_plate_move`, `grm_plate_reset`,
  `grm_plate_show`. Все значения нормализуются и зажимаются в пределах
  (`PL.NormalizeRender`), хранятся в `data/grm_plates/render.json` и
  рассылаются всем.
* ПОРЦИОННОСТЬ И ПОРЯДОК. Снимки окон номеров и автопарка уходили одним
  пакетом (3 и 5 таблиц) — теперь через `GRM.Net.Stream` кусками по кадрам,
  а серия действий подряд схлопывается в одну отправку через
  `GRM.Perf.Coalesce` (`PL.PushSoon`, `FL.PushSoon`). Приём — общим
  `GRM.Net.Receive`, окно собирается один раз.
* Находок аудита: 46 → 44, ворота проходятся.
* Стенд `sim_plates` — 125 проверок (нормализация раскладки, три оси
  наклона, сдвиг, сброс, 3D2D-плашка, потоковый снимок).

## Ход 21.08 (40) — система ареста стала «по картам»

* НАСТОЯЩАЯ ПРИЧИНА чужих точек: камеры, точки содержания и зоны тюрьмы
  лежали в ОДНОМ файле `grm_arrest.json` вместе с категориями и доступами.
  Файл общий для всех карт — поэтому на новой карте показывались и
  срабатывали точки, размеченные в другом городе.
* Данные разделены: общее (категории, модели, доступы) остаётся в
  `grm_arrest.json`, а привязанное к карте (камеры, точки, зоны) — в
  `grm_arrest/<карта>.json`. У каждой записи есть поле `map`: даже если файл
  подменят руками, чужие записи не загрузятся (фильтр `ofThisMap`).
  Проверка «игрок в зоне тюрьмы» тоже сверяет карту.
* МИГРАЦИЯ: старый общий файл один раз переносится в текущую карту, из
  общего точки убираются, категории остаются. В консоль пишется, сколько
  камер, точек и зон перенесено.
* ОБСЛУЖИВАНИЕ: `grm_arrest_points` (отчёт по карте: что размечено и какие
  камеры без точки), `grm_arrest_maps` (карты с разметкой),
  `grm_arrest_import <карта>` (перенести разметку), `grm_arrest_map_clear`.
  В окне ареста появился раздел «Карта и разметка» с выбором карты-источника,
  кнопками «ПЕРЕНЕСТИ СЮДА» и «ОЧИСТИТЬ ЭТУ КАРТУ», а в шапке — имя карты и
  счётчики камер/точек/зон.
* Тул «GRM: зона тюрьмы» переписан в стиле GRM: рамки зон с названием,
  размером и картой, живое превью будущей зоны с первого угла, подсказка
  ЛКМ/ПКМ/R на экране, удаление зоны по R, название зоны в панели.
* Снимок окна ареста уходит через `GRM.Net.Stream` (порциями), а не одним
  пакетом.
* Стенд: `sim_arrest_maps` (35 живых проверок: своя карта, смена карты,
  возврат, чужая запись в файле, список карт, перенос, очистка, миграция
  старого файла, права на команды). Старый `sim_arrest` — 28/28.

## Ход 21.08 (41) — призрачные пропы, защита от спама, строка пожарки

* ПРОП ПРИ СПАВНЕ — ПРИЗРАК. Новый проп появляется полупрозрачным, без
  коллизии с игроками и пропами и с выключенной физикой: он никого не
  толкает и никуда не улетает. Поставили физганом и ЗАМОРОЗИЛИ (ПКМ) —
  проп становится обычным: сплошной, с физикой и коллизией. Сняли с
  заморозки физганом — снова призрак, можно двигать сквозь всё. При взгляде
  на призрак висит подсказка «ЗАМОРОЗЬТЕ ФИЗГАНОМ (ПКМ)».
  Выключается конваром `grm_prop_ghost 0`, прозрачность — `grm_prop_ghost_alpha`.
* СПАМ ПРОПАМИ. Очередь пропов (по умолчанию 10 штук за 8 секунд) закрывает
  игроку спавн на 60 секунд: в чат пишется, сколько осталось, событие уходит
  в аудит и в консоль сервера. Считается ОКНО времени, поэтому спокойная
  стройка под правило не попадает. Правило распространяется и на рагдоллы,
  эффекты и SENT. Суперадмины по умолчанию свободны
  (`grm_prop_spam_admins 1` включает и для них). Команды: `grm_prop_status`
  (лимиты и кто заблокирован), `grm_prop_unblock [ник]`.
* СТРОКА ПОЖАРКИ. Внизу экрана счётчики воды, пены, порошка и рукавов
  висели ВСЕГДА после приёма машины на дежурство — хоть на другом конце
  карты. Теперь строка показывается, только если боец сидит в машине, стоит
  рядом с ней (`grm_fire_hud_dist`, по умолчанию 350) или держит в руках
  ствол/рукав.
* Стенды: `sim_prop_guard` (34 живые проверки: окно спама, блокировка и её
  снятие, рагдоллы и SENT, суперадмин, призрак при спавне, материализация
  по заморозке, возврат в призрак, отключение конваром, права на команды),
  `sim_fire_truck_hud` (7 проверок контракта строки).

## Ход 21.08 (42) — чужие аватарки в документах, категории и ключи, прокрутка

* АВАТАРКА В ЧУЖОМ УДОСТОВЕРЕНИИ. Каждый бланк сам решал, что рисовать, и
  при отсутствии поля `steamID64` подставлял `LocalPlayer()` — поэтому в
  ПРЕДЪЯВЛЕННОМ документе человек видел собственное фото. Теперь:
    - сервер перед отправкой копирует запись и подписывает её владельцем
      (`forView`: steamID64, ключ и имя персонажа) — для всех семи типов;
    - клиент определяет владельца по данным записи (steamID64 → ключ
      персонажа), а `LocalPlayer` берёт ТОЛЬКО для своего бланка;
    - если владельца установить нельзя — рисуется нейтральная карточка
      «ФОТО» с инициалом, но никогда не лицо смотрящего.
  Все семь бланков переведены на один помощник `docPhoto` — копий больше нет.
* КАТЕГОРИИ И КЛЮЧИ. Принадлежность к фракции для дверей бралась только из
  таблицы состава; если состав ключуется иначе или игрок ещё не подтянулся,
  функция возвращала пустоту — и категории с фракциями просто не работали
  (ключи не открывали ведомственные двери). Добавлен запасной путь через
  NW-поля (`GRM_Faction`, `GRM_Role`, `GRM_Department`, `GRM_Subdepartment`),
  на которые смотрит весь остальной GRM.
* ПРОКРУТКА В КАТЕГОРИЯХ. В окне `/door_access` возврат позиции делался
  одной попыткой через `timer.Simple(0)`, а DScrollPanel зажимает `SetScroll`
  по высоте холста, известной только после раскладки — список прыгал наверх
  после каждой галочки. Теперь попытка повторяется до восьми кадров с
  пересчётом раскладки, пока позиция реально не встанет.
* Стенды: `sim_doc_avatar` (17), `sim_door_categories_ui` (13); обновлён
  `sim_document_show_ctx` (10). `sim_forward_locals` снова поймал обращение
  к local-функции до объявления — исправлено форвард-декларацией.

## Ход 21.08 (43) — зона постановки пропа, РП-имена без абуза, вывески скупщиков

* ЗОНА ПОСТАНОВКИ ПРОПА. Проп-призрак больше не может стать твёрдым, пока
  в его габаритах стоит ДРУГОЙ игрок: заморозка физганом принимается, но
  переход откладывается — проп остаётся полупрозрачным и без коллизии,
  хозяину пишут, кто именно мешает, а на самом пропе висит надпись
  «ЗОНА ЗАНЯТА — ОТОЙДИТЕ, ПРОП ВСТАНЕТ САМ». Сторож (`timer` 0.5 c, живёт
  только пока очередь не пуста) проверяет зону и материализует проп сам,
  как только она освободилась. Себя самого хозяин не блокирует, игроки в
  ноклипе и мёртвые не считаются. Конвары: `grm_prop_zone_guard` (1),
  `grm_prop_zone_margin` (6 юнитов запаса). Чистая логика вынесена в
  `PG.BoxesOverlap` / `PG.ZoneBlockers` / `PG.ZoneFree` — гоняется стендом.
* РП-ИМЕНА. `CH.ValidateName` переписана: длина считается СИМВОЛАМИ utf-8
  (3…32), разрешены только буквы кириллицы и латиницы, пробел, дефис и
  апостроф — эмодзи, цифры, скобки и служебные знаки отсекаются. Требуется
  2…4 слова, каждая часть 2…20 букв, не больше трёх частей через дефис,
  запрет двойных разделителей и «Ааааа». Первая буква каждой части
  поднимается автоматически. Свои utf-8 upper/lower — `string.lower`
  кириллицу не знает. «Александр Фон Грённер», «Мария Готтен-Фон-Штоцкая»,
  «Пётр О'Брайен», «Jean-Luc Picard» проходят.
* ИМЯ ЗАНИМАЕТСЯ ПЕРВЫМ. `CH.FindNameOwner` ищет владельца по ключу
  (`CH.NameKey`: регистр, Ё/ё и дефисы не спасают), `CH.SetName` отказывает
  с понятной причиной. Окно персонажа больше не закрывается, если сервер
  имя не принял (раньше при отказе персонаж мог остаться без имени).
  Конвар `grm_name_unique` (1), команда суперадмина `grm_name_owner <имя>`.
* ВЫВЕСКИ ТОРГАШЕЙ И СКУПЩИКОВ. Заголовок «пропадал», а плашка оставалась,
  потому что у обоих энтити `RenderGroup = RENDERGROUP_BOTH`: `ENT:Draw`
  вызывался дважды за кадр, второй проход клал подложку поверх уже
  нарисованного текста, а его собственный текст ложился в ту же плоскость
  глубины. Вывеска вынесена в общий слой `GRM.Sign`
  (`lua/autorun/client/cl_grm_sign.lua`) и рисуется ОДИН раз за кадр в
  `ENT:DrawTranslucent`. Плюс: ширина плашки считается по фактической
  ширине строк (длинные названия не вылезают), шрифты проверяются замером
  и падают на DermaLarge, тело завёрнуто в `pcall` при гарантированном
  `cam.End3D2D` (ошибка внутри больше не роняет матрицу 3D2D всего кадра),
  `grm_sign_debug 1` печатает причину.
* Стенды: `sim_prop_guard` (55, было 34), `sim_char_names` (40, новый),
  `sim_sign` (18, новый); обновлены `sim_mining_ui` и `sim_performance_v2`
  под новый слой вывесок.

## Ход 22.08 (44) — падение сервера на goto: «'=' expected near 'continue'»

* СИМПТОМ. `addons/grm/lua/autorun/sh_grm_arrest.lua:285: '=' expected near
  'continue'` — файл ареста не грузился целиком, вместе с ним отваливались
  зоны тюрьмы и всё, что за ними.
* ПРИЧИНА. В коде стояли `goto continue` и метка `::continue::`. Это
  синтаксис Lua 5.2/LuaJIT, и обычный LuaJIT (на котором гоняются стенды)
  их спокойно принимает — поэтому проверка компиляции была зелёной. Парсер
  GMod goto НЕ поддерживает, а `continue` у него своё ключевое слово, так
  что `goto continue` рвёт файл при загрузке.
* ИСПРАВЛЕНО. `A.IsInPrisonZone` переписана обычным условием (фильтр карты
  через `if ... == here then`), в `sh_faction_fixes.lua` (вкладка доступов
  к законам) `goto continueRole` разведён на `if not canManageLaws then …
  else … end`. Больше goto в сборке нет.
* ЧТОБЫ НЕ ПОВТОРИЛОСЬ. Новый стенд `tools/luatest/sim_gmod_syntax.lua`
  (4 проверки) обходит ВСЕ lua-файлы сборки и краснеет на любом `goto` и
  любой метке `::label::`. Ошибка такого рода видна теперь на стендах, а не
  на живом сервере.

## Ход 22.08 (45) — строка пожарки: только по взгляду и только своим

* СИМПТОМ (скриншот владельца). Счётчики «вода 4000 · пена 500 · порошок
  250 · рукава 0/4» висели внизу экрана, когда игрок смотрел вообще в
  другую сторону, а после `/firetruck` строка загоралась у всех подряд —
  в том числе у тех, у кого нет доступа к системе тушения.
* ПРИЧИНЫ (две). (1) Условием показа была БЛИЗОСТЬ (`grm_fire_hud_dist`) —
  достаточно оказаться рядом с машиной. (2) Доступ вообще не проверялся:
  ветка «сижу в машине» показывала строку любому, кто занял кабину, потому
  что клиент не знает прав — менеджер доступа живёт на сервере.
* ИСПРАВЛЕНО. Правило вынесено в чистую `F.TruckHUDVisible(crew, seated,
  looking, dist, maxDist)`: строка видна, только если у игрока есть право
  пожарного И он либо сидит в машине, либо СМОТРИТ на неё (трассировка,
  а не радиус) не дальше `grm_fire_hud_dist`. Взгляд считается через
  `GRM.Perf.EyeTrace` не чаще пяти раз в секунду. Правила «ствол в руках»
  и «просто рядом» убраны.
* ФЛАГ ДОСТУПА. Сервер публикует право одним NW-флагом `GRM_FireCrew`
  (`F.PublishCrewFlag` по `F.CanUseFireTruck`): на спавне, при постановке
  и снятии с дежурства, при смене персонажа, при сохранении доступов в
  `/fire_access` (там добавлен `hook.Run("GRM_FireAccessChanged")`) и раз в
  20 секунд фоном. В кадре ничего не считается.
* Стенд `sim_fire_truck_hud` переписан с проверки текста на живой прогон
  правила: 21 проверка (было 7), включая «в кабине без доступа — не видно».

## Ход 22.08 (46) — координаты, антисёрф, автоматический номер, ячейки у дилера

* ИНСТРУМЕНТ «GRM КООРДИНАТЫ» (`stools/grm_measure.lua`, новый). ЛКМ —
  замер объекта под прицелом: класс, модель, позиция, углы, габарит
  (мин/макс/размеры сторон), тонкая и длинная ось, точка и нормаль
  поверхности, локальные координаты попадания и локальные углы этой
  поверхности, дистанция, материал. ПКМ — метки: две дают расстояние по
  прямой, по земле, разницу по осям и курс. R — сброс. Всё видно панелью
  на экране и уходит в консоль. Команда `/координаты` (`/замер`,
  `grm_coords`). Чистая часть (`GRM.Measure.Round/SideList/Delta/Describe`)
  считает на обычных таблицах и целиком покрыта стендом.
* ПРОПЫ: АНТИСЁРФ И АНТИТОЛКАНИЕ вместо запрета брашей. По решению
  владельца проталкивать пропы сквозь браши карты РАЗРЕШЕНО — сторож
  геометрии убран. Вместо него: пока проп в физгане, он проходит сквозь
  игроков (толкать им людей нельзя), а тех, кто стоит сверху, снимает с
  пропа в момент захвата — кататься на пропах не выйдет. Конвары
  `grm_prop_antisurf`, `grm_prop_antipush`.
* ПОДСКАЗКА О ЗАМОРОЗКЕ — ЛИЧНАЯ. Табличка над пропом убрана совсем: она
  висела в мире и её видели все. Теперь строка внизу СВОЕГО экрана и
  только для своего пропа (владелец пишется в `GRM_PropGhostOwner`),
  плюс личные сообщения с антиспамом (`PG.Tell`).
* НОМЕР НА ЗНАКЕ — АВТОМАТИКА. Раньше строка ложилась по общей настройке
  оси/поворота, одной на весь сервер, и висела отдельной плашкой впереди
  знака на ручном «выносе». Теперь плоскость читается из габаритов модели,
  а какая из осей идёт вдоль строки — решается по тому, как знак реально
  стоит в мире (строка на более горизонтальную ось, верх — вверх). Надпись
  лежит НА поверхности и автоматически вписывается в поле знака по ширине
  и высоте. Отрисовка ровно одна за кадр: модель в `ENT:Draw`, номер в
  `ENT:DrawTranslucent` (раньше DrawTranslucent звал Draw — двойной проход).
* НОМЕР ПОМНИТ КОНКРЕТНУЮ МАШИНУ. В единый слой транспорта добавлен UID
  (`GRM.Vehicles.UID/EnsureUID`): `veh:<запись гаража>`, `fleet:<единица
  автопарка>` или выданный `map:<crc>`, он же в NW `GRM_VehicleUID`.
  Крепление знака хранится полной записью (`PL.NormalizeMount`:
  `parentType/parentKey/parentClass/parentName`, локальные позиция и углы,
  нормаль) и переживает уборку в гараж и удаление машины — запись
  помечается `offMap`, а при следующей выдаче знак возвращается на ту же
  машину по UID. Правка крепления — чистая `PL.NudgeMount`.
* У ДИЛЕРА — ЯЧЕЙКИ. Гараж показан сеткой карточек (инвентарь машин):
  превью, название, класс, НОМЕРНОЙ ЗНАК отдельной табличкой, где стоит
  машина, приписка к гаражу, цена и выкуп; кнопка «ВЫДАТЬ / УБРАТЬ»,
  ПКМ — подробности и продажа государству. Старые строки-карточки удалены.
  Номер попадает в карточку двумя путями: пишется в запись
  (`rec.plate`) и добирается по UID (`PL.PlateOfVehicleKey`).
* Стенды: `sim_measure` (27, новый), `sim_prop_guard` (64, было 55),
  `sim_plates` (144, было 125); поправлен `sim_vehicle_class_limit`.

## Ход 22.08 (47) — 3D2D Textscreens, родные панели инструментов, меню персонажа v2

* 3D2D TEXTSCREENS. Аддон Cherry/3D2D-Textscreens добавлен в сборку как
  `addons/grm_textscreens` (lua, материалы, локализации, лицензия — без
  правок логики). Единственная адаптация: загрузка сохранённых экранов
  переведена с `InitPostEntity` на `GRM.Boot.OnMapStart(..., "idle", ...)`,
  чтобы десятки энтити не создавались одним куском на старте карты (без
  GRM аддон работает как оригинал).
* НАСТРОЙКИ ИНСТРУМЕНТОВ — РОДНЫЕ. Q-меню v5.2.0: панель настроек строит
  САМ инструмент. `QM.ToolTable` берёт инструмент из тулгана
  (`weapons.GetStored("gmod_tool").Tool[id]`), `QM.NativePanel` создаёт
  настоящий `ControlPanel` со скином Default и отдаёт его в `BuildCPanel`.
  Возвращаются родные виджеты: выбор материала плитками, списки шрифтов,
  цвета, пресеты — то, что схема-описание показать не могла (у владельца
  3D2D Textscreen и «Материал» выглядели не так, как задумано авторами).
  Наша схема осталась страховкой: если у инструмента нет `BuildCPanel` или
  он упал, показываем свою панель, а если и её нет — честную подсказку.
  Чужой код зовётся в `pcall`, меню от его ошибки не падает.
* МЕНЮ ПЕРСОНАЖА v2 — ПОЛНАЯ ПЕРЕРАБОТКА ОКНА.
    - окно на ВЕСЬ экран, без крестика; при обязательном выборе не
      закрывается ни мышью, ни ESC (`OnPauseMenuShow` тоже блокируется), а
      если окно всё же пропало — сторож просит его заново;
    - три зоны: слева персонажи карточками, по центру живая модель
      (крутится мышью, камера сама подгоняется по габаритам), справа
      настройки вкладками ВНЕШНОСТЬ / ТЕЛОСЛОЖЕНИЕ / ИМЯ И ОПИСАНИЕ;
    - любое изменение (модель, скин, бодигруппа) видно на модели сразу:
      одна функция `applyPreview`, окно не пересобирается и не наслаивается;
    - бодигруппы и скин — отдельная вкладка со стрелками ◀ ▶ вместо
      ползунков, читаются с реальной модели;
    - описание персонажа редактируется прямо в окне и уходит в RPDesc
      (`RD.SetFor`), хранится в записи ПЕРСОНАЖА (сменил слот — сменилось
      описание), длина считается символами (`CH.CleanDesc`, 300).
* ДО ВЫБОРА ПЕРСОНАЖА ИГРОКА НЕТ В МИРЕ. `CH.SendToLimbo`: игрок уносится
  за карту (0,0,15500) без модели, без коллизии, без оружия, неуязвимым и
  замороженным. После подтверждения `CH.ReleaseFromLimbo` возвращает всё,
  спавнит игрока и `CH.PlaceOnSpawnPoint` ставит его на точку из системы
  точек спавна (`GetSpawnPointForPlayer` — фракционная, если состоит во
  фракции, иначе общая; запасной вариант — `info_player_start`).
  HUD, выбор оружия, хот-бары, Q- и C-меню, чат и движение до выбора
  по-прежнему заблокированы.
* Кнопка в F4 переименована в «МЕНЮ ПЕРСОНАЖА».
* Стенды: `sim_character_menu` (32, новый); обновлены `sim_qmenu_v5` (16),
  `sim_qmenu_v4_access` (17), `sim_qmenu_v4_budget` (16),
  `sim_character_roster_accessories` (19).

## Ход 22.08 (48) — оружие только после появления, окно закрывается само

* ОРУЖИЕ ДО ВЫБОРА ПЕРСОНАЖА. Лимб снимал оружие один раз, но через 3 и 10
  секунд после входа `FactionsExt` сам звал `ApplyWeaponsToPlayer` — набор
  возвращался прямо в лимбе. Теперь `ApplyWeaponsToPlayer` сначала смотрит
  на `GRM_CharacterPending`: персонаж не подтверждён — снять оружие и
  патроны и выйти. Плюс добавлен `PlayerLoadout`-гейт в ядре персонажей:
  пока идёт выбор, не выдаётся и стандартный сэндбокс-набор (физган,
  тулган, камера). Набор из `/weapons_admin` выдаётся один раз — сразу
  после постановки игрока на точку спавна (`CH.PlaceOnSpawnPoint`).
* ОКНО НЕ ЗАКРЫВАЛОСЬ. Сервер слал закрытие, а клиент звал `:Close()` —
  который у обязательного окна специально отключён (чтобы игрок не закрыл
  его сам). Меню оставалось висеть после выбора персонажа. Теперь по
  команде сервера панель сносится напрямую (`Remove`), состояние окна
  чистится, а сторож «окно должно быть на экране» получает паузу на 2
  секунды, чтобы не открыть меню обратно.
* Стенд `sim_character_menu` — 37 проверок (было 32).

## Ход 22.08 (49) — где регистрировать номера: раздел выдачи стал видимым

* ВОПРОС ВЛАДЕЛЬЦА. Во вкладке «Номерные знаки» он видел только свои
  номера и проверку по базе — раздела регистрации не было, и было
  непонятно, где номера вообще создаются.
* ПРИЧИНА. Раздел «РЕГИСТРАЦИЯ НОВОГО ЗНАКА» показывался только при
  `officer == true`, а само право считалось молча: не совпал ни один
  признак — и блок просто исчезал, без единого слова почему.
* ЧТО СДЕЛАНО.
    - `PL.IssueReason(ply)` возвращает не только «да/нет», но и ОСНОВАНИЕ
      (суперадмин, право `plates.issue`, право организации `plates_issue`,
      название организации из списка органов, уровень госбазы). Признаков
      стало больше — добавлены права фракций.
    - В окне всегда есть строка статуса: «ВЫ МОЖЕТЕ РЕГИСТРИРОВАТЬ НОМЕРА»
      или «РЕГИСТРАЦИЯ ВАМ НЕДОСТУПНА» с основанием, а гражданскому —
      карточка «КАК ПОЛУЧИТЬ НОМЕР» с порядком действий.
    - У сотрудника в блоке выдачи владелец теперь предвыбран (он сам), а
      рядом кнопка «СЕБЕ» — зарегистрировать номер на себя одним нажатием.
    - Команды: `/номер_выдать <ник> [тип] [номер]` (`grm_plate_issue`) —
      выдача без терминала, и `/номер_статус` (`grm_plate_status`) —
      печатает право, организацию и число своих номеров.
* Стенд `sim_plates` — 153 проверки (было 144).

## Ход 22.08 (50) — размер модели в меню, ячейки везде, честный подсчёт мест

* МОДЕЛЬ В МЕНЮ ПЕРСОНАЖА НЕ ВЛЕЗАЛА. Камера ставилась по формуле «от
  размера модели», без учёта угла обзора — высоким моделям срезало голову.
  Теперь дистанция считается честно: половина габарита делится на тангенс
  половины FOV, сверху 35% запаса; учитывается и ширина (шинели, рюкзаки).
* ЯЧЕЙКИ ВЕЗДЕ, А НЕ ТОЛЬКО У ДИЛЕРА. Появился общий слой
  `GRM.VehicleCells` (`lua/autorun/client/cl_grm_vehicle_cells.lua`):
  `Grid(parent)` + `Cell(grid, info)`. На него переведены ВСЕ окна:
    - дилер, раздел «Гараж» (свой инлайновый код удалён);
    - окно гаража — и личный транспорт, и СЛУЖЕБНАЯ техника организации;
    - вкладка «Автопарк» организации (закрепление за должностями и отделами
      переехало в меню по ПКМ и в кнопку «ДОСТУП И СПИСАНИЕ»).
  В каждой ячейке: превью, название, класс, НОМЕРНОЙ ЗНАК, состояние
  (в гараже / на карте / на линии), приписка к гаражу и ограничения.
  Номер служебной единицы берётся по UID `fleet:<id>`, личной — `veh:<id>`.
* СЧИТЫВАНИЕ МЕСТ БЫЛО НЕВЕРНЫМ. Занятость места определялась
  `ents.FindInSphere(pos, 150)` — то есть по РАССТОЯНИЮ ДО ORIGIN машины.
  У седана от бампера до центра ~110 юнитов, у грузовика больше: машина
  стоит кузовом на месте, а origin за радиусом — место считалось свободным,
  и следующая машина выдавалась в неё. Обратная ошибка тоже была: origin
  соседней машины попадал в радиус, и свободное место числилось занятым.
  Теперь у места есть свой габарит (`G.SlotBox`, `G.SlotBounds`), кандидаты
  ищутся широким радиусом, а решение принимает `G.BoxesOverlap` —
  пересечение кузова (`WorldSpaceAABB`) с коробкой места.
* Стенды: `sim_plates` (157), `sim_garage_module` (80), `sim_garage_runtime`
  (69, мок машины получил габариты).

## Ход 22.08 (51) — выносливость в машине и предзагрузка моделей транспорта

* ВЫНОСЛИВОСТЬ В МАШИНЕ. В тике стамины стояло условие
  `if IsValid(ply) and not ply:InVehicle()` — сидящий в машине выпадал из
  расчёта целиком, поэтому шкала стояла на месте (и не восстанавливалась, и
  не синхронизировалась). Теперь посадка считается ОТДЫХОМ: стамина растёт
  со своей скоростью `StaminaRegenSeated` (12 против 8 на земле), синк идёт
  как обычно. Расход в машине по-прежнему не считается — бежать сидя нельзя.
* ПРЕДЗАГРУЗКА МОДЕЛЕЙ ТРАНСПОРТА (`sh_grm_vehicle_precache.lua`, новый).
  DModelPanel и SpawnIcon рисуют только уже загруженную движком модель —
  поэтому у дилера машины появлялись лишь после того, как их впервые
  заспавнили на карте. Теперь на старте карты собирается весь список
  (source + simfphys + LVS, плюс то, что реально выставлено у дилеров и
  закуплено в автопарки) и грузится заранее:
    - старт висит на `GRM.Boot.OnMapStart(..., "idle", ...)` — после всего
      важного;
    - обход идёт `GRM.Perf.Spread` порциями по `grm_vehicle_precache_chunk`
      (4 по умолчанию) и с отрицательным приоритетом, то есть уступает
      игровым задачам;
    - на клиенте модель «прогревается» временной `ClientsideModel`, иначе
      иконка всё равно осталась бы пустой;
    - при сохранении ассортимента дилера (`GRM_VehicleDealerSaved`) список
      обновляется с задержкой через `Coalesce`.
  Конвары `grm_vehicle_precache`, `grm_vehicle_precache_chunk`; команды
  `grm_vehicles_precache` (принудительно) и `grm_vehicles_precache_status`.
* Стенд `sim_vehicle_precache` (16 проверок, новый).

## Ход 22.08 (52) — право на регистрацию номеров стало ВЫДАВАЕМЫМ

* ВОПРОС ВЛАДЕЛЬЦА: «как выдавать доступ для регистрации номеров сотрудникам
  и фракциям?». Ответ был неутешительный: никак. Код спрашивал capability
  `plates.issue` и право организации `plates_issue`, но НИГДЕ их не объявлял,
  поэтому в списках `/admin` → «Привилегии» и `/factions` → «Доступы» этих
  пунктов просто не было — отметить их было негде.
* ИСПРАВЛЕНО.
    - `GRM.Access.Register("plates.issue")` и `("plates.check")` — теперь
      привилегии видны в админ-платформе и выдаются группам/игрокам;
    - `plates_issue` и `plates_check` добавлены в
      `GRM.FactionPerms.Permissions` — появляются чекбоксами в «Доступах»
      организации и выдаются должностям и отделам;
    - `PL.CanCheck` тоже уважает право организации `plates_check`
      (раньше проверка по базе зависела только от уровня госбазы).
    - В окне, если права нет, прямо написано, ГДЕ его дать.
* ТРИ ПУТИ ПОЛУЧИТЬ ПРАВО (по убыванию «настроечности»):
    1) `/factions` → «Доступы» → «Регистрация номерных знаков» — должности
       или отделу организации;
    2) `/admin` → «Привилегии» → `plates.issue` — группе или конкретному
       игроку;
    3) без настройки: суперадмин и органы из списка `PL.IssueHints`
       (полиция, жандармерия, ВАИ, военная полиция) плюс уровень госбазы
       police/military/admin.
* Стенд `sim_plates` — 161 проверка (было 157).

## Ход 22.08 (53) — экран входа GROENNERLAND2036, чистка худов, борьба с рывками

* ЭКРАН ВХОДА (`sh_grm_loading.lua`, новый). Первое, что видит игрок —
  чёрный экран, золотая надпись **GROENNERLAND2036**, ниже «ДОБРО
  ПОЖАЛОВАТЬ НА ПРОЕКТ!» и полоса загрузки. Полоса честная: этапы —
  соединение, приём настроек сервера, готовность подсистем (доля считается
  по `GRM.Boot.Status`), прогрев моделей транспорта, данные персонажа.
  Когда всё готово, полоса сменяется кнопкой «НАЧАТЬ ИГРАТЬ», и только по
  ней открывается окно выбора/регистрации персонажа. Экран не закрывается
  ни крестиком, ни ESC; страховка — через 45 секунд молчания сервера
  кнопка появляется всё равно, плюс серверный таймер на 60 секунд шлёт
  меню персонажа, если клиент завис.
  Прогресс сервер шлёт раз в полсекунды и ТОЛЬКО тем, кто грузится;
  таймер живёт, пока такие есть. В кадре ничего не считается: этапы
  сверяются 4 раза в секунду.
* СТАНДАРТНЫЕ ХУДЫ ВЫКЛЮЧЕНЫ (`cl_grm_hud_clean.lua`, новый). Список
  скрываемых элементов HL2/Sandbox собран в ОДНОМ месте (раньше был
  размазан по `cl_grm_hud.lua` и `cl_grm_cctv.lua`): здоровье, броня,
  патроны, выбор оружия, индикаторы урона и отравления, костюм, зум,
  гейгер. Отдельно убрана стандартная подпись «ник + здоровье» над игроком
  (`HUDDrawTargetID`) — её место занимает GRM.Nameplate. Прицел оставлен.
  Возврат — `grm_hud_hl2 1`.
* МИКРОФРИЗЫ: убраны три крупных рассылки одним пакетом.
    - список персонажей организаций (`sh_factions.lua`) уходит
      `GRM.Net.Stream` (куски по кадрам), приём добавлен на клиент;
    - снимок GPS/миникарты (`sh_grm_minimap.lua`) — так же потоком;
    - шаблоны документов после сохранения БОЛЬШЕ НЕ РАССЫЛАЮТСЯ вовсе:
      это был не только пакет каждому игроку, но и открытие окна
      `/doc_admin` у всех подряд (клиент на этот канал отвечает открытием
      окна). Клиент запрашивает шаблоны сам.
* Стенд `sim_loading` (24 проверки, новый).

### Что из заказа НЕ сделано этим ходом (следующая цель)
* Переработка старых модулей: мобильные телефоны, прослушка помещений и
  телефонов, сигнализация (жалоба «не работает»), охранные системы — и их
  дизайн под GRM.
* Дальнейшая оптимизация: остаются 6 крупных broadcast-рассылок и 15
  частых таймеров (см. `tools/audit_perf.py`), плюс идея адаптивного
  бюджета кадра в `GRM.Perf`.

## Ход 22.08 (54) — экран входа и меню персонажа больше не спорят за экран

* КОНФЛИКТ ДВУХ ПОЛНОЭКРАННЫХ ОКОН. Экран входа и окно персонажа могли
  оказаться на экране одновременно (наслаивание и «двоение»). Введено
  правило одного хозяина экрана, и оно держится с ОБЕИХ сторон:
    - сервер: `sendMenu` не отправляет окно, пока `GRM.Loading.IsLoading(ply)`
      — запрос запоминается в `ply.GRMCharMenuPending` и уходит по хуку
      `GRM_LoadingFinished` (то есть после кнопки «НАЧАТЬ ИГРАТЬ»);
    - клиент: снимок, пришедший при видимом экране входа, не строит окно, а
      ложится в `CH._afterLoading` и разворачивается по `GRM_LoadingClosed`;
    - экран входа, в свою очередь, не открывается поверх уже живого окна
      персонажа.
* КНОПКА «ЗАКРЫТЬ» ИЗ МЕНЮ ПЕРСОНАЖА УБРАНА (требование владельца).
  Обязательное окно не закрывается вообще; добровольно открытое (F4 →
  «МЕНЮ ПЕРСОНАЖА», `/char`) закрывается по ESC, как любое окно GRM.
* Стенд `sim_character_menu` — 45 проверок (было 37).

## Ход 22.08 (55) — сигнализация «не работает», адаптивный бюджет, ещё три рассылки

* ПОЧЕМУ СИГНАЛИЗАЦИЯ МОЛЧАЛА. `GRM.Doors.IsFriendlyForAlarm` первым же
  условием возвращала true для суперадмина — то есть владелец, проверяя
  сигнализацию сам, всегда был «своим», и датчики его не замечали.
  Теперь решение принимает `A.IsFriendly(ply, netID)`: по умолчанию
  сигнализация срабатывает и на администрацию (иначе её невозможно
  проверить), а конвар `grm_alarm_ignore_admins 1` возвращает прежнее
  поведение. Своими остаются те, у кого есть доступ к объекту по дверной
  системе.
* ДИАГНОСТИКА ВМЕСТО ДОГАДОК. `grm_alarm_status` печатает все сети карты:
  есть ли блок коммутации, в каком он режиме, сколько датчиков и сколько
  из них включено, есть ли динамики и пульты — и отдельной строкой пишет,
  если ИМЕННО ВЫ считаетесь своим для этой сети. Для каждой проблемы —
  подсказка, что сделать. `grm_alarm_test <сеть>` запускает сирену вручную.
* АДАПТИВНЫЙ БЮДЖЕТ ФОНА (`GRM.Perf`). Фоновые задачи больше не берут
  фиксированные 1.5 мс на кадр: `P.TrackFrame` считает среднюю длину кадра
  (сглаживание 0.9/0.1), `P.BudgetScale` даёт множитель — свободный сервер
  ×1.5, норма ×1, затяжка ×0.5, провал ×0.15. То есть при рывках фон сам
  ужимается, а не добавляет к ним. Текущие цифры видно в `grm_perf_report`.
* ЕЩЁ ТРИ КРУПНЫЕ РАССЫЛКИ УБРАНЫ ИЗ ОДНОГО ПАКЕТА: админ-платформа
  (группы/права/назначения), доступы меню организаций и синк Q-меню теперь
  уходят через `GRM.Net.Stream`, приём добавлен на клиент. Осталось три
  (деньги-прачечная, кастомизация, чужой аддон текстовых экранов).
* Стенды: `sim_alarm` (30, контракт перевёрнут под новое поведение),
  `sim_performance_v2` (29), плюс в трёх стендах сигнализации появилась
  заглушка конваров.

## Ход 22.08 (56) — выданный доступ наконец доходит до модулей и до окна

* ЖАЛОБА: «выдача доступа никак не обновляет компьютер, номерные знаки как
  были недоступны, так и остались». Причин оказалось ТРИ, и все разные.
* 1. ДВА РЕЕСТРА ПРАВ НЕ ЗНАЛИ ДРУГ О ДРУГЕ. Модули спрашивают capability
  `GRM.Access.Can(ply, "plates.issue")`, а `/admin` → «Привилегии» пишет
  права в свою админ-платформу. Провайдеров у `GRM.Access` не было ни
  одного, поэтому отметка в `/admin` не значила ничего. Добавлен мост:
  `GRM.Access.RegisterProvider("grm_admin_platform", 50, ...)` — capability
  сначала ищется в группах платформы. Зовём `AD.CanLocal`, а НЕ `AD.Can`:
  `Can` ходит в CAMI, CAMI зовёт наш хук — это уже давало
  «[ULib] stack overflow».
* 2. СОСТАВ ОРГАНИЗАЦИИ МОГ НЕ НАЙТИСЬ. `PERMS.PlayerHasPermission`
  перебирала только `Factions[*].Members`; если состав ключован иначе или
  игрок ещё не подтянулся, выданное роли право «не работало». Добавлен
  запасной путь по NW-полям (`GRM_Faction`, `GRM_Role`, `GRM_Department`,
  `GRM_Subdepartment`) — ровно как раньше чинили дверные категории.
  Заодно право теперь ищется и у отдела с подотделом, не только у роли.
* 3. ОКНО НЕ ОБНОВЛЯЛОСЬ. Снимок вкладки «Номерные знаки» уходил только по
  кнопке «Обновить». Теперь оба реестра прав поднимают событие
  `GRM_AccessChanged`, а модуль знаков рассылает свежий снимок всем
  игрокам; пачка галочек подряд схлопывается в одну рассылку
  (`GRM.Perf.Coalesce`, 0.5 c). Отдельно снимок уходит игроку при смене
  должности (`GRM_FactionRoleChanged`).
* Стенд `sim_plates` — 167 проверок (было 161).

## Ход 22.08 (57) — все модули знают друг друга: реестр и единая точка права

* РЕЕСТР МОДУЛЕЙ `GRM.Modules` (`sh_03b_grm_modules.lua`, новый).
  Модуль объявляет себя один раз: имя, версия, зависимости, как обновить
  свои окна (`Refresh`), что показать в отчёте (`Status`). Другие модули
  спрашивают `GRM.Modules.Has("fleet")` вместо догадок «загружено ли».
  Зарегистрированы: `access`, `doors`, `plates`, `fleet`, `garage`,
  `vehicles`, `alarm` — список будет расти по мере переработки старых
  модулей.
* ШИНА ОБНОВЛЕНИЙ. Семь источников изменений (`GRM_AccessChanged`,
  `GRM_AdminDataUpdated`, `GRM_FPermDataUpdated`, `GRM_FactionRoleChanged`,
  `GRM_FactionsUpdated`, `GRM_CharacterChanged`, `GRM_DutyChanged`) сведены
  в ОДНО событие: реестр сам зовёт `Refresh` у всех подписанных модулей.
  Пачка событий схлопывается (`Coalesce` 0.4 c), обход идёт порциями по 4
  через `GRM.Perf.Spread` с низким приоритетом — правило порционности
  соблюдено. Модуль больше не обязан знать чужие хуки.
* ЕДИНАЯ ТОЧКА ПРАВА. У `GRM.Access` появились штатные провайдеры:
  `/admin` (мост из прошлого хода), ДОСТУПЫ ОРГАНИЗАЦИЙ по правилу имени
  (`plates.issue` ↔ `plates_issue`, либо явное поле `factionPerm`) и
  УРОВЕНЬ ГОСБАЗЫ, если capability объявила `levels = { police = true }`.
  Теперь модулю достаточно одного вопроса `GRM.Access.Can`, а владельцу —
  выдать право в любом из привычных мест.
* ОБЪЯСНЯЮЩАЯ ДИАГНОСТИКА: `grm_access_check <право> [ник]` печатает ответ,
  причину и все источники, откуда это право могло бы прийти;
  `grm_modules` — реестр с версиями, статусами и недостающими
  зависимостями; `grm_modules_refresh [ник]` — принудительная рассылка.
* Стенд `sim_modules` (25 проверок, новый).

## Ход 22.08 (58) — старые модули в общем реестре, права связи и наблюдения, минус три холостых цикла

* В РЕЕСТР `GRM.Modules` ДОБАВЛЕНЫ: `mobile` (мобильная связь),
  `phone_access` (доступ к оборудованию связи), `cctv` (видеонаблюдение),
  `wanted` (розыск), `arrest` (арест и содержание), `minimap` (карта и GPS),
  `spawnpoints` (точки спавна). Каждый объявляет версию, зависимости и
  строку статуса — `grm_modules` теперь показывает живую картину сервера.
* СВЯЗЬ И НАБЛЮДЕНИЕ ПОДКЛЮЧЕНЫ К ЕДИНОМУ ПРАВУ. Объявлены capability
  `phone.equipment`, `phone.wiretap`, `cctv.view`, `cctv.manage` — с полями
  `factionPerm` и `levels`, то есть право можно выдать тремя штатными
  путями (`/admin`, доступы организации, уровень госбазы). Проверка доступа
  к оборудованию связи теперь спрашивает и свою таблицу, и общий слой —
  раньше знала только себя. Соответствующие пункты добавлены в
  `/factions` → «Доступы».
* ОПТИМИЗАЦИЯ (микрофризы).
    - Оглушение электродубинкой держало таймер на КАЖДОГО оглушённого с
      опросом 5 раз в секунду. Время окончания известно заранее — остался
      один отложенный вызов, который сам продлевается, если оглушение
      повторили.
    - Сторож радиосети обходил пять реестров сущностей каждые 0.7 c, в том
      числе на картах без единой рации. Реальные изменения и так зовут
      пересчёт напрямую, поэтому сторож стал редким (3 c) и молча выходит,
      когда радиооборудования нет.
    - Клиентский «треск помех» крутился постоянно; теперь таймер создаётся
      на время разговора и снимается, когда говорящих не осталось.
* Стенд `sim_modules` — 39 проверок (было 25).

## Ход 22.08 (59) — терминалы обновляются сами, знаки переработаны, каталог дилера ячейками

* ТЕРМИНАЛ ОБНОВЛЯЕТСЯ САМ. Раньше снимок учёта уходил только тому, кто
  нажал кнопку: коллега зарегистрировал номер — у остальных на экране
  старые данные (жалоба владельца). Теперь модуль знает своих зрителей:
    - клиент при открытии панели шлёт `watch on`, при закрытии — `watch off`;
    - `PL.Save` (любая правка реестра: выдача, статус, монтаж, утеря)
      рассылает свежий снимок ВСЕМ зрителям;
    - пачка правок схлопывается в одну рассылку (`Coalesce` 0.35 c) —
      микрофриза не будет;
    - раз в 10 секунд окно тихо подтверждает подписку: страховка от
      потерянного пакета, без опроса каждую секунду.
* НОМЕРНЫЕ ЗНАКИ ПЕРЕРАБОТАНЫ. Длинные серые строки заменены на СЕТКУ
  ЯЧЕЕК: каждая — как настоящая табличка (поле нужного цвета, боковая
  полоса серии, крупный номер), под ней тип серии, состояние, машина
  (с пометкой «в гараже», если машина не на карте) и владелец. Действия
  переехали в саму карточку: «ПОЛУЧИТЬ БЛАНК» и «ЗАЯВИТЬ ОБ УТЕРЕ» у своих
  номеров, «АННУЛИРОВАТЬ» и «ВОССТАНОВИТЬ» — у найденного по базе (только
  службе). Отдельная нижняя панель «Действия с номером» больше не нужна и
  удалена.
* КАТАЛОГ ДИЛЕРА — ТОЖЕ ЯЧЕЙКИ. Сеткой стали ВСЕ разделы каталога, включая
  «Служебный по организациям» (там ячеек и не было). Карточка — общая из
  `GRM.VehicleCells`: превью, название, категория, цена или тип службы,
  организация, счётчик лимита, кнопка «КУПИТЬ/ПОЛУЧИТЬ», по ПКМ — класс и
  система. Строками остался только раздел «На карте»: там важны дистанция
  и владелец, а не витрина.
* Стенды: `sim_plates` — 178 проверок (было 167), поправлен
  `sim_vehicle_class_limit` под новую карточку.

## Ход 22.08 (60) — служебная техника поштучно, класс не исчезает из настроек дилера

* КАЖДАЯ СЛУЖЕБНАЯ МАШИНА ОТДЕЛЬНО. В каталоге дилера стоял КЛАСС («что
  можно получить»), поэтому все седаны выглядели одной ячейкой и своей
  машины с номером там не было. Добавлен раздел «Служебный парк →
  Техника организации»: сервер отдаёт ЕДИНИЦЫ автопарка поштучно
  (`FL.UnitsOf`), у каждой своя ячейка с номерным знаком, состоянием
  (в гараже / на линии), гаражом приписки и ограничением по должности.
  Кнопка «ВЫДАТЬ / ВЕРНУТЬ В ГАРАЖ» работает по КОНКРЕТНОЙ единице и идёт
  через единый диспетчер `GRM.Vehicles` (новые операции дилера
  `fleet_issue` / `fleet_store`) — те же правила, что в окне гаража.
* ПОЗИЦИЯ КАТАЛОГА ≠ МАШИНА. Ячейки каталога больше не рисуют табличку
  «БЕЗ НОМЕРА»: у класса номера быть не может (поле `noPlate`).
* КЛАСС МОЖНО НАЗНАЧИТЬ НЕСКОЛЬКИМ ОРГАНИЗАЦИЯМ. В настройках дилера
  кнопка добавления гасла, если класс уже был в ассортименте — из-за этого
  `sim_fphys_wolfpolice`, отданный одной фракции, «исчезал» и второй раз
  его назначить было нельзя. Теперь позиций с одним классом может быть
  сколько угодно: у каждой своя цена, категория и организация, а рядом
  видно «уже в списке: N». Серверный поиск позиции (`findEntry`) стал
  учитывать игрока: выбирается та позиция, которой он вправе
  воспользоваться, а не первая попавшаяся.
* Стенд `sim_vehicle_dealer_v3` — 45 проверок (было 36).

## Ход 22.08 (61) — единая панель состояния, служебные номера сами, окно дилера крупнее

* HUD ПЕРЕРАБОТАН В ОДНУ ПАНЕЛЬ. Было: здоровье и броня в своём файле,
  сытость — по АБСОЛЮТНЫМ координатам (`x = ScrW() - 1066, y = 1044`,
  то есть на любом другом разрешении уезжала), вес — по центру снизу,
  выносливость — там же и налезала. Стало: реестр полос
  `GRM.HUD.RegisterBar(id, { label, order, Get })` — модуль объявляет свою
  полосу и отдаёт значение, а панель сама решает раскладку, ширину и
  порядок и растёт по высоте под содержимое.
  Порядок: 10 здоровье, 20 броня (только когда есть), 30 выносливость,
  40 дыхание, 50 сытость, 60 вес, внизу — наличные и счёт. Чужая полоса
  зовётся через `pcall`: ошибка модуля не роняет HUD.
  Переведены: выносливость и НОВОЕ дыхание (`sh_grm_movement.lua`),
  сытость (`cl_grm_food_hud.lua`), вес (`cl_grm_encumbrance.lua`).
  Предупреждения о перегрузе остались отдельной строкой — это сообщение,
  а не индикатор.
* СЛУЖЕБНЫЕ НОМЕРА СТАВЯТСЯ САМИ. При первой выдаче единицы автопарка
  модуль знаков регистрирует ведомственный номер и вешает его на задний
  борт по габаритам машины: серия выбирается по организации
  (`PL.ServiceKind`: полиция и жандармерия → полицейская, комендатура и
  военные → военная, остальные ведомства → государственная). Номер
  закрепляется за UID единицы (`fleet:<id>`), поэтому при следующей выдаче
  возвращается на ту же машину. Выключается `grm_plates_auto_service 0`.
* ОКНО УЧЁТА ОБНОВЛЯЕТСЯ САМО. Добавлено сердцебиение: пока окно открыто,
  сервер шлёт снимок раз в 5 секунд (таймер живёт только при наличии
  зрителей). Права, выданные в обход событий (правка файла, чужой аддон,
  импорт из ULX), теперь тоже подхватываются без ручного «пробить».
* ОКНО ДИЛЕРА КРУПНЕЕ: 0.92 экрана вместо 0.84, минимум 1240×780,
  максимум 1860×1120 — ячейки помещаются в несколько рядов без тесноты.
* Стенды: `sim_hud_bars` (19, новый), `sim_plates` — 189 проверок.

## Ход 22.08 (62) — НАЙДЕНА ПРИЧИНА «САМО НЕ ОБНОВЛЯЕТСЯ»: перепутанные аргументы Coalesce

* КОРЕНЬ. У слоя схлопывания сигнатура `GRM.Perf.Coalesce(key, delay, fn)`,
  а шесть мест звали его как `(key, fn, delay)`. Внутри стоит проверка
  `if not isfunction(fn) then return false end` — то есть вызов молча
  проваливался и запланированная работа НЕ ВЫПОЛНЯЛАСЬ НИКОГДА.
  Пострадали ровно те места, на которые жаловался владелец:
    - `PL.PushSoon` — снимок учёта номеров после `refresh`/`watch`
      (поэтому окно на старте писало «доступа нет», а после ручного
      «пробить» — который шлёт снимок НАПРЯМУЮ — всё появлялось);
    - `plates.viewers.push` и `plates.access.push` — самообновление окна и
      рассылка после выдачи прав;
    - `FL.PushSoon` — то же самое в автопарке;
    - `modules.bus` — вся шина обновлений модулей (её вызовы не доходили);
    - `vehicles.precache.resave` — обновление списка моделей после правки
      ассортимента.
* ИСПРАВЛЕНО. Все шесть вызовов приведены к правильному порядку. Сам слой
  стал терпимым: если вторым аргументом пришла функция, он меняет их
  местами и ОДИН раз пишет об этом в консоль — чтобы ошибку чинили в
  исходнике, а не жили с ней молча.
* Первый снимок окна учёта теперь уходит СРАЗУ (без схлопывания): окно
  только что открылось, ждать нечего.
* СТОРОЖ В СТЕНДЕ. `sim_performance_v2` обходит всю сборку и краснеет,
  если где-то снова появится `Coalesce(key, function() ... end)`.
* Стенды: `sim_performance_v2` — 32 проверки, `sim_modules` — 39 (мок
  Coalesce приведён к настоящей сигнатуре).

## Ход 22.08 (63) — крепление знака по замерам модели, живое окно автопарка

* КРЕПЛЕНИЕ ЗНАКА ИСПРАВЛЕНО ПО ЗАМЕРАМ ВЛАДЕЛЬЦА (инструмент
  «GRM Координаты»): `plate025x075.mdl` — мин `-6.2 -18 -1.7`, макс
  `6.2 18 1.8`, габарит `12.4 × 36.1 × 3.5`, ТОНКАЯ ось **z**, ДЛИННАЯ
  **y**, КОРОТКАЯ **x**. Значит нормаль лицевой стороны — локальная +Z,
  строка идёт вдоль +Y, высота таблички по +X.
  Раньше `MountOnRear` просто разворачивал углы МАШИНЫ на 180° по рысканью:
  наружу оказывалась локальная X, и знак вставал ребром/плашмя — отсюда
  вечная ручная подгонка. Теперь угол строится одной операцией
  `up:AngleEx(normal)` (Forward = верх таблички, Up = нормаль), а сам знак
  отодвигается от поверхности ровно на половину толщины (1.75).
  Зафиксировано в `PL.ModelGeometry`, поставлены стенды.
* КУДА ВЕШАТЬ. По [E] знак встаёт РОВНО в точку, куда смотрит игрок, лицом
  наружу по нормали поверхности (`PL.PlaceOnSurface`). Если игрок не
  смотрит на кузов — знак уходит на задний борт по габаритам машины
  (`PL.MountOnRear`, точка `mins.x + 1`, центр ширины, 32% высоты).
  Вырожденные случаи (знак на полу или потолке) обработаны: «верх»
  подбирается заново, составляющая вдоль нормали вычитается.
* АВТОПАРК: ЖИВОЕ ОКНО И ДИАГНОСТИКА ХРАНЕНИЯ. Та же схема, что у номеров:
  подписка `watch`, мгновенный первый снимок, сердцебиение раз в 5 секунд,
  рассылка зрителям при добавлении позиции на рынок. Плюс команды
  `grm_fleet_status` (что в памяти, что реально на диске, сколько окон
  открыто, прочитаны ли файлы) и `grm_fleet_save` (принудительная запись с
  проверкой результата).
* Стенды: `sim_plates` — 199 проверок, `sim_fleet` — 103.

## Ход 22.08 (64) — окна не мерцают и не сбивают ввод, дилер и автопарк — один механизм

* ОБНОВЛЕНИЕ БОЛЬШЕ НЕ РЯБИТ. Снимок приходит каждые несколько секунд, но
  данные в нём чаще всего те же — а окно пересобиралось на КАЖДЫЙ пакет:
  список мигал, набранный текст пропадал, вкладка и прокрутка слетали.
  Теперь у снимка есть подпись (`snapshotSignature` / `stateSignature`):
  совпала с прошлой — окно не трогаем вообще. И даже при изменениях
  пересборка откладывается, пока игрок ПЕЧАТАЕТ (`vgui.GetKeyboardFocus`);
  как только он уходит из поля, отложенное изменение применяется. Сделано
  и для учёта номеров, и для автопарка.
* ДИЛЕР И АВТОПАРК — ОДНА ЗАКУПКА. Ассортимент дилеров теперь попадает в
  рынок автопарка автоматически: `FL.DealerMarket()` собирает служебные
  позиции всех дилеров карты (цена, организация, категория дилера) под
  устойчивым идентификатором `dealer:<класс>:<организация>`, а `FL.Entry`
  и `FL.MarketList` работают с обоими источниками одинаково.
* СЛУЖЕБНАЯ ПОЗИЦИЯ БОЛЬШЕ НЕ «ПОЛУЧИТЬ СРАЗУ». В каталоге дилера у неё
  кнопка «ЗАКУПИТЬ В АВТОПАРК · цена»: деньги идут из бюджета организации,
  а на карте появляется ОТДЕЛЬНАЯ ЕДИНИЦА техники со своим номером и своим
  слотом. Выдаётся она потом — в разделе «Техника организации» (одна
  машина = одна ячейка). Закупка идёт через единый `FL.Buy`: право,
  бюджет, лимит на организацию, обязательный гараж приписки.
* Стенды: `sim_vehicle_dealer_v3` — 57 проверок, `sim_fleet` — 103,
  поправлен `sim_vehicle_class_limit`.

## Ход 22.08 (65) — окно помнит ввод, прокрутку и выбор; связка дилер ↔ автопарк доведена

* ПРОШЛЫЙ ХОД РЕШАЛ ЗАДАЧУ НАПОЛОВИНУ. Подпись снимка убрала лишние
  пересборки, но при РЕАЛЬНОМ изменении данных окно всё равно собиралось
  заново — и вместе с ним обнулялись поля ввода, выбор в списках и
  прокрутка. Теперь состояние живёт ОТДЕЛЬНО от виджетов:
    - `PL.Form` / `FL.Form` — значения полей по ключу: поле при создании
      читает сохранённое, при вводе пишет обратно (`find`, `issue_number`,
      `issue_vehicle`, `mk_class`, `mk_name`, `mk_price`, `mk_limit`,
      `buy_count`);
    - выбор в списках тоже запоминается: владелец и серия у номеров, гараж
      приписки и уровень допуска у автопарка;
    - `PL.RestoreScroll` / `FL.RestoreScroll` возвращают прокрутку каждой
      секции — циклом до восьми кадров, потому что `DScrollPanel` зажимает
      `SetScroll` по высоте холста, известной только после раскладки.
  Вместе с подписью снимка и паузой на время печати это убирает и рябь, и
  «слетающие страницы».
* СВЯЗКА ДИЛЕР ↔ АВТОПАРК (доведено). Ассортимент дилеров попадает в рынок
  закупок автопарка (`FL.DealerMarket`, id `dealer:<класс>:<организация>`),
  служебная позиция у дилера закупается кнопкой «ЗАКУПИТЬ В АВТОПАРК» через
  единый `FL.Buy` (право, бюджет организации, лимит, гараж приписки), а на
  карте появляется ОТДЕЛЬНАЯ единица: одна машина — один слот — одна
  ячейка, со своим номером. Выдача — отдельное действие в разделе
  «Техника организации» (и у дилера, и в терминале служебного
  оборудования — панель одна и та же).
* Стенды: `sim_plates` — 204, `sim_fleet` — 107, `sim_vehicle_dealer_v3` — 57.

## Ход 22.08 (66) — уборка в гараж для личного и служебного, автономера автопарка отключены

* «УБРАТЬ В ГАРАЖ» — ДЛЯ ЛИЧНОЙ И СЛУЖЕБНОЙ МАШИНЫ. Раньше в разделе
  «На карте» у дилера были видны только личные машины из `VD.Active`, а
  активные единицы автопарка (`FL.Active`) в списке не появлялись — и
  служебное фракционное авто «убрать в гараж» у дилера было невозможно.
  Теперь `VD.ActiveRows` добавляет и активную технику организации: строка
  помечается `fleet=true`, а кнопка в окне дилера зовёт `fleet_store` через
  единый диспетчер `GRM.Vehicles` (возвращает единицу в её гараж).
  У личной машины остаётся `store`, у дилера — та же команда, что и в
  терминале/гараже, поэтому поведение везде одинаковое.
* АВТОНОМЕРА ЗА ТЕХНИКОЙ АВТОПАРКА НЕ ВЕШАЮТСЯ САМИ. Хук
  `GRM_Plates_ServiceAuto` убран: закупленные в автопарк единицы больше не
  получают ни гражданский, ни ведомственный номер автоматически при
  выдаче. Номер таким машинам ставится вручную, как и личным. Ручной
  инструмент `PL.EnsureServicePlate` оставлен, конвар
  `grm_plates_auto_service` по умолчанию `0`.
* Стенды: `sim_plates` — 204, `sim_fleet` — 107, `sim_vehicle_dealer_v3` — 61.

## Ход 22.08 (67) — ценник закупки: карточка и списание теперь одна позиция

* КОРЕНЬ. У дилера карточка показывала цену конкретной позиции
  (`dealer.VD_Vehicles[i].price`), а кнопка «ЗАКУПИТЬ В АВТОПАРК» слала
  только класс. Сервер в `fleet_buy` искал `FL.MarketList()` по классу и
  брал первую подходящую позицию. Если тот же класс был у другого дилера
  или в собственном рынке с другой ценой — списывалась и сохранялась
  ЧУЖАЯ цена, не та, что была на карточке.
* ИДЕНТИФИКАТОР ПОЗИЦИИ ДИЛЕРА. Добавлен `FL.DealerEntryID(dealer, entry)`:
  `dealer:<класс>:<организация>:<CRC дилера+класса+организации+цены+категории+имени>`.
  У двух карточек одного класса с разным ценником теперь РАЗНЫЕ позиции;
  `FL.DealerMarket()` больше не схлопывает их в одну запись.
* ТОЧНАЯ ЗАКУПКА. Каталог дилера отдаёт `marketID` в карточку, клиент шлёт
  его вместе с классом и гаражом, сервер получает `marketID` и берёт запись
  через `FL.Entry(marketID)`. Если позиция с этим id пропала или цена
  изменилась — сервер отказывает и просит обновить окно, а не подменяет
  карточку другой ценой.
* РУЧНОЙ НОМЕР ЗА ЕДИНИЦЕЙ АВТОПАРКА ВОЗВРАЩАЕТСЯ. Автогенерация
  отключена, но если номер зарегистрирован вручную (`fleet:<id>`), при
  выдаче машины он возвращается на неё (`PL.RestoreFleetPlate`, хук
  `GRM_Plates_FleetRestore`). Новый номер при этом не создаётся.
* СТЕНДЫ. `sim_fleet` — 113 (новый блок: два дилера, один класс, разные
  цены — две позиции, цены не путаются), `sim_vehicle_dealer_v3` — 64,
  `sim_plates` — 206.

## Ход 22.08 (68) — табличный список транспорта, честное запоминание базы закупок

* ТАБЛИЧНЫЙ СПИСОК ВМЕСТО ЯЧЕЕК. Все окна реальных машин переведены на
  общий слой `GRM.VehicleCells.TableHeader/TableRow`: окно дилера («Гараж»
  и «Техника организации»), окно гаража (личный и служебный) и вкладка
  «Автопарк организации». Одна реальная машина = одна строка: название,
  класс, номер, гараж, статус, кнопки. Служебные и гражданские — отдельные
  разделы, каждая единица отдельно. Каталог (что можно купить) остаётся
  витриной-ячейками.
* БАЗА ЗАКУПОК ПИШЕТСЯ НА ТЕКУЩУЮ КАРТУ. `fleet_<карта>.json`
  регистрировался в `GRM.Save` один раз при старте. При смене карты
  реестр продолжал писать в файл старой карты — покупки на новой «терялись».
  Теперь `FL.Load` перерегистрирует `grm_fleet_units` и `grm_fleet_market`
  под текущий `fleetFile()`/`MARKET_FILE`.
* ЧЕСТНЫЙ СТАТУС ПОСЛЕ РЕСТАРТА. `FL.NormalizeLoadedUnits` переводит
  единицы со статусом `active` в `stored` при чтении базы: после рестарта
  живых машин нет, поэтому показывать «на линии» нечего. Иначе база
  выглядела «на линии» без машины.
* ЗАПОМИНАНИЕ ТРАНСПОРТА И НОМЕРОВ. Личные записи (`grm_vehicle_garages.json`),
  единицы парка (`fleet_<карта>.json`), реестр номеров
  (`grm_plates/registry.json`) и привязка `veh:<id>`/`fleet:<id>` — отдельные
  записи; номера за автопарком возвращаются на ту же единицу при выдаче.
* Стенды: `sim_fleet` — 119, `sim_vehicle_dealer_v3` — 64,
  `sim_plates` — 206, `sim_vehicle_class_limit` — 64.

## Ход 22.08 (69) — «Ценники не фиксятся»: правки цен позиций дилеров сохраняются

* КОРЕНЬ. Админская вкладка «Рынок» показывала позиции дилеров по цене из
  ассортимента (часто 0 GRM), а кнопка «ЦЕНА» звала `FL.MarketUpdate`. Для
  `id = dealer:*` она меняла таблицу, которую `FL.DealerMarket()` каждый раз
  собирает заново из энтити — правка пропадала и в закупку уходил 0.
* ИСПРАВЛЕНО. Появился `FL.DealerOverrides` — переопределения цены/названия/
  лимита для `id = dealer:*`. `FL.MarketUpdate` теперь пишет их туда,
  `FL.DealerMarket()` применяет их после сборки (потому и окно, и закупка
  видят одну цену), а `market.json` хранит `overrides` (version=2), поэтому
  правка переживает рестарт. `FL.MarketRemove` для дилерской позиции
  сбрасывает только правку, саму позицию из ассортимента дилера не удаляет.
* Свой рынок правила не затронуты: `mk:*` по-прежнему обновляется напрямую.
* Стенды: `sim_fleet` — 131 (новый блок: правка цены дилерской позиции,
  сохранение overrides в market.json, сброс без удаления позиции, правка
  собственной позиции).

## Ход 22.08 (70) — номер прикрепляется физически, но НЕ привязывается в БД

* КОРЕНЬ. `PL.VehicleIdentity` полагался на `GRM.Vehicles.EnsureUID`, а при
  его отсутствии возвращал голый `GRMGarageID` и полностью игнорировал
  `GRMFleetID`. Привязка в реестре (`mount.parentKey`) получала не тот ключ,
  который ищут окна (`"veh:<id>"` / `"fleet:<id>"`), — номер висел на
  машине, но «в базе машины» его не было.
* ИСПРАВЛЕНО.
  1. `PL.VehicleIdentity` теперь сам строит канонический ключ:
     `veh:<GRMGarageID>` или `fleet:<GRMFleetID>`, а имя ищет по сырому
     ID записи гаража (иначе картотека отдавала `sim_car`).
  2. `PL.Attach` дополнительно пишет `vehicleUID` в запись гаража и в
     единицу автопарка, а `rememberLayout` теперь сохраняет раскладку и
     номер и для личного транспорта, и для служебного (раньше у
     служебного — только энтити).
  3. `PL.PlateOfVehicleKey` ищет и `mount`, и `rec.vehicleUID` — привязка
     находится даже если mount потерялся.
  4. Окна дилера/гаража/автопарка читают номер сначала из базы
     (`PlateOfVehicleKey`), а не только из поля `plate` записи.
  5. `RestoreFleetPlate` восстанавливает номер по раскладке единицы
     автопарка (`unit.plates`), не только по mount реестра.
* Стенды: `sim_plates` — 211 (новый блок: личная и служебная привязка в
  базе после `Attach`, mount + vehicleUID, канонический `veh:`/`fleet:` ключ).

## Ход 22.08 (71) — дилер/база не видят закреплённый номер у служебной машины

* КОРЕНЬ. `FL.Issue` ставил на энтити только `GRMFleetUnit`, а
  `GRM.Vehicles.UID()`, `PL.VehicleIdentity()` и `FL.Unit` искали именно
  `GRMFleetID`. Поэтому «личность» служебной машины получала случайный
  `map:...`; `mount.parentKey` в реестре не совпадал с `fleet:<id>`, и
  дилер/автопарк/гараж не находили номер.
* ИСПРАВЛЕНО.
  1. `FL.Issue` теперь ставит `ent.GRMFleetID = unit.id` (плюс прежний
     `GRMFleetUnit` для совместимости).
  2. `V.UID()`/`V.EnsureUID()` и `PL.VehicleIdentity()`/`fleetRecordOf()`
     учитывают и `GRMFleetID`, и `GRMFleetUnit` — старые выданные машины
     тоже распознаются.
  3. `PL.Attach` пишет `vehicleUID` в единицу автопарка по `GRMFleetID`
     или `GRMFleetUnit`.
  4. Окна дилера (`VD.Push`) и окно гаража (`V.Rows`) дополнительно
     показывают номер с **физически закреплённого знака** активной машины
     (`GRM.Plates.VehiclePlates`), если запись в базе ещё не успела
     синхронизироваться. Значит «факт закрепления» виден сразу.
* ДОБАВЛЕНО к прошлому ходу: `FL.DealerHash` — детерминированный id
  позиции дилера без `util.CRC` (иначе после рестарта override цены мог
  не находиться); `FL.FlushMarket()` — немедленная запись цены рынка на
  диск; `grm_fleet_status` показывает `цены_overrides` в памяти и на диске.
* Стенды: `sim_fleet` — 136 (новая проверка: у выданной служебной машины
  есть `GRMFleetID`; «цена после рестарта»), `sim_plates` — 211.

## Ход 22.08 (72) — закупленный транспорт пропадал после рестарта

* КОРЕНЬ. Две причины:
  1. Парк писался только отложенным `GRM.Save.Mark` (задержка 3 с). При
     быстром рестарте/падении сервера запись не успевала, и на диске
     оставался старый (пустой/без новых единиц) файл.
  2. `boot()` вызывался и сразу, и повторно через `GRM.Boot.OnMapStart`.
     Второй `FL.Load` очищал `FL.Units={}` и перечитывал файл, который ещё
     не был записан, — закупка «исчезала» в памяти до сохранения.
* ИСПРАВЛЕНО.
  1. `FL.FlushFleet(why)` — синхронная запись `fleet_<карта>.json`.
     Вызывается сразу после закупки, выдачи, возврата, приписки, списания,
     закрепления техники. Отложенный `GRM.Save.Mark` остаётся как страховка.
  2. Убран повторный `boot()` при наличии `GRM.Boot` (планировщик зовёт
     загрузку один раз). Если планировщика нет — оставлен fallback.
  3. `FL.Load()` перед сбросом памяти сохраняет текущий парк
     (`FlushFleet("перед сменой карты")`), чтобы смена карты не потеряла
     ещё не записанные единицы.
* Стенды: `sim_fleet` — 141 (новый блок: «закупили → выдали → рестарт →
  единицы вернулись из файла, выданная честно в гараже»).

## Ход 22.08 (73) — принудительный сброс автопарка на выключение/смену карты + диагностика

* ДОБАВЛЕНО СВЕРХ 72. `FL.SaveFleetNow`/`SaveMarketNow` теперь пишут в
  консоль путь и количество (`grm_fleet_debug 1`), `boot()` логирует
  количество и `file.Exists(fleetFile())`. Это позволяет сразу увидеть,
  существует ли `data/grm_fleet/fleet_<карта>.json` и сколько в нём единиц.
* ЯВНЫЙ СБРОС. Добавлены хуки `ShutDown` и `PreCleanupMap`, которые
  вызывают `FL.FlushFleet`/`FL.FlushMarket` напрямую, независимо от очереди
  `GRM.Save` (страховка, если очередь не успела).
* ВАЖНО ДЛЯ ПРОВЕРКИ НА ЖИВОМ: после установки аддона нужно перезапустить
  сервер, закупить технику, затем выполнить `/grm_fleet_status` (видно
  в памяти и на диске), после чего сделать рестарт и снова
  `/grm_fleet_status`. Если на диске 0 единиц — на сервере лежит старый
  аддон/файл не пишется из-за прав data/; если на диске >0, а в памяти 0 —
  читается не тот `map` (см. путь в статусе).

## Ход 22.08 (74) — «данные прочитаны: НЕТ, парк 1»: загрузка автопарка не выполнялась

* КОРЕНЬ. В ходе 72 я убрал немедленный `boot()` при наличии `GRM.Boot`,
  рассчитывая, что `GRM.Boot.OnMapStart` вызовет `FL.Load`. На сервере
  владельца планировщик этого не сделал: `grm_fleet_status` показывал
  `данные прочитаны: НЕТ`, в памяти «парк 1» (закупка создалась), на диске 0.
  `FL._loaded` оставался false → запись заблокирована, парк жил только в
  памяти и терялся при рестарте.
* ИСПРАВЛЕНО. `boot()` теперь вызывается СРАЗУ при загрузке модуля.
  Планировщик `GRM.Boot.OnMapStart` перечитывает базу только при смене
  карты (сравнение `FL._mapLoaded` с текущим `game.GetMap()`), поэтому
  повторного стирания парка нет. Если `GRM.Boot` нет — fallback `InitPostEntity`.
* Стенды: `sim_fleet` — 143 (новые проверки: `FL._loaded==true` сразу после
  загрузки модуля; `FL._mapLoaded` заполнен).

## Ход 22.08 (75) — закупка только из каталога суперадмина; HUD полоски

* ЗАКУПКА. Раньше `FL.MarketList` автоматически добавлял служебные позиции
  дилеров фракций, поэтому игрок мог закупить машину, которую суперадмин
  для закупки не выставлял. Теперь:
    - `MarketList()` включает только позиции, добавленные суперадмином
      во вкладке «Рынок» (`FL.Market`);
    - в каталоге дилера служебная карточка получает `marketReady=false`
      и кнопку «НЕТ В КАТАЛОГЕ ЗАКУПКИ», пока класс не добавлен;
    - сервер `fleet_buy` принимает только `FL.Market[marketID]` (или поиск
      только по собственному рынку) — дилерская позиция не закупается,
      пока суперадмин её не внесёт.
* HUD. Панель состояния слева внизу поправлена:
    - броня показывается всегда (даже 0), а не только при >0;
    - панель не уходит за верх экрана при большом числе полос
      (`ph = min(ph, sh-32)`, `py = max(16, ...)`);
    - ширина/высота полос чуть увеличены для читаемости; сытость и
      остальные полосы по-прежнему через `GRM.HUD.RegisterBar`.
* Стенды: `sim_vehicle_dealer_v3` — 64 (обновлены ожидания: дилер не
  добавляет в закупку автоматически, кнопка «НЕТ В КАТАЛОГЕ»).

## Ход 22.08 (76) — изучение всей документации и дизайн HUD в стиле GRM/XUI

* ИЗУЧЕНО: все MD текущей ветки + ветки `019fcf9e` (PROJECT_MEMORY,
  HANDOVER, FULL_ANALYSIS, ANALYSIS_MODULES, ANALYSIS_ALL_LUA,
  CHARACTER_ARCHITECTURE, QMENU_ANALYSIS), Facepunch commits и wiki
  (HUDPaint/HUDShouldDraw, surface.CreateFont, OptimizationTips). Ключевое
  из записей предшественников: не работать от master; ядро — `GRM = GRM or {}`
  и `Factions`; JSON с SID/CharacterKey только `util.JSONToTable(raw,false,true)`;
  дизайн-канон — палитра GRM/XUI, Roboto extended, rounded 8/4, тонкая
  обводка; «порядок загрузки autorun» и «не ломать глобальные контракты».
* HUD ПЕРЕДЕЛАН В СТИЛЕ GRM/XUI (`cl_grm_hud.lua`):
  - палитра приведена к cl_grm_ui_theme: bg(8,14,23), panel(10,22,37),
    line(55,117,151), text(225,238,247), muted(132,160,178), cyan/green/
    amber/red акценты;
  - добавлена шапка «СОСТОЯНИЕ» (RoundedBoxEx, скруглены только верхние
    углы) + неоновая линия под ней, тонкая обводка корпуса;
  - полосы: подложка panel2 (22,37,56), заливка неоновым цветом с
    скруглением 4, не выходит за панель;
  - здоровье/броня/сытость/вес/выносливость в одном списке, панель не
    уходит за верх экрана, броня видна всегда;
  - API `GRM.HUD.RegisterBar/BarList` сохранён (модули по-прежнему
    объявляют свои полосы).
* Стенды: `sim_hud_bars` — 19/19, `sim_hud_selector` — 0 failures,
  `sim_fleet` — 143, `sim_plates` — 211, `sim_vehicle_dealer_v3` — 64.

## Ход 22.08 (77) — HUD доделан; номера: положение фиксируется; ничего не пропадает

* HUD. Панель в стиле GRM/XUI завершена: шапка «СОСТОЯНИЕ»,
  неоновая обводка, полосы здоровья/брони/сытости/веса/выносливости,
  наличные/счёт, патроны. `GRM.HUD.RegisterBar` сохранён.
* НОМЕРА — ПОЛОЖЕНИЕ НА МОДЕЛИ. `MountOnRear` больше не берёт нормаль
  из `veh:GetForward()` (у simfphys/LVS это не корпус), а считает
  локальный задний борт `-X`. Добавлены:
  - `PL.Layouts` + `PL.NormalizeLayout`, `PL.LayoutFor`, `PL.SetLayout`;
  - `PL.MountPointFor(veh)` — layout класса → автоматика OBB;
  - команда `/номер_layout` (суперадмин): без аргументов запоминает
    положение знака по машине под прицелом; с `x y z [nx ny nz] [ux uy uz]`
    задаёт вручную; `/номер_layout_сброс` возвращает автоматику;
  - layout сохраняется в `data/grm_plates/render.json` (с новым форматом
    `{render=..., layouts=...}`, старый формат читается).
* НИЧЕГО НЕ ПРОПАДАЕТ. В `GRM.Save` добавлен `FlushExternal(reason)`:
  на `ShutDown` и `PreCleanupMap` поверх очереди GRM.Save вызываются
  через pcall публичные Save* модулей с прямой записью (дилер, гараж,
  документы, услуги, вендор, штрафы, шахта, вещание, новости). Это
  страховка, если модуль использовал `file.Write` в обход очереди.
* Стенды: `sim_plates` — 217, `sim_hud_bars` — 19/19,
  `sim_fleet` — 143, `sim_dealer_buy_issue` — 30/30,
  `sim_vehicle_dealer_v3` — 64/64, `sim_money` — все проверки OK.
