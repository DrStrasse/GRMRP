# ANALYSIS — «AI part 2 details.zip» (Wiremod + CPU-чипы + GTerminal + TerminalR)

**Дата:** 2026-08-16 · **Источник:** коммит `f527b95` «Для кода. Важная часть.» на `arena/01a00565-drstrasse`
**Архив:** `AI part 2 details.zip` (18.8 МБ, распаковано 64 МБ, **2965 файлов**)

> Это **Wiremod** (Apache-2.0, github.com/wiremod) — эталонная GMod-система
> «электроника/провода/программируемые чипы + внутриигровая ОС». Кладём как
> справочник по паттернам: свой скриптовый язык (E2), своя виртуальная машина
> (ZVM/ZCPU), свой ассемблер (hlzasm), своя ОС (GTerminal), свой файловый
> браузер/редактор. В репозиторий GRM **код не копировался** — только анализ.

---

## 1. Карта аддона

| Путь | Что это | Размер |
|---|---|---|
| `lua/wire/` | ядро Wiremod: проводная сеть, гейты, `WireLib`, cpulib/gpulib | 17 файлов |
| `lua/wire/client/` | клиент: редактор текста, node-editor, hlzasm, браузеры E2 | 18 файлов |
| `lua/wire/zvm/` | **Zyelios VM** (виртуальная машина CPU/GPU-чипов) | 5 файлов |
| `lua/wire/stools/` | ~110 инструментов Toolgun (гейты, чипы, экраны, сенсоры…) | 106 файлов |
| `lua/wire/{cpu_gates,fpga_gates,gates}/` | наборы гейтов для CPU/FPGA/обычных | — |
| `lua/entities/gmod_wire_expression2/` | **E2 (Expression 2)** — свой скриптовый язык | 58 core-модулей, ~26к строк |
| `lua/entities/gmod_wire_{cpu,gpu,spu,fpga}/` | чипы: CPU (ZVM), GPU (шейдер-подобный), SPU (звук), FPGA (потоковый) | — |
| `lua/entities/gmod_wire_egp{,_hud}/` | EGP — рисовалка голограмм (свой объектный движок `egplib`) | — |
| `lua/entities/gmod_wire_*screen/keyboard/…` | экраны: character LCD, console, digital, HUD-indicator | — |
| `lua/gterminal/` | **GTerminal** — внутриигровая ОС компьютера | 1592 строки |
| `lua/terminalr/` + `trm_*` | **TerminalR (Terminal Mod 2)** — Fallout-терминал, дискеты, взлом | 8 программ |
| `lua/autorun/{netstream,wire_load,hl2_entities_plus,pb_init,trm_shared}.lua` | автозагрузка | — |
| `data_static/` | тесты E2-компилятора, примеры/библиотеки cpuchip/gpuchip/spuchip, E2-тесты | — |

---

## 2. Ключевые архитектурные паттерны (что стоит перенять в GRM)

### 2.1 E2 — свой язык целиком (компиляторный конвейер)
`gmod_wire_expression2/base/` — это настоящий конвейер:
`tokenizer.lua → preprocessor.lua → parser.lua → compiler.lua` (+ `debug.lua`).
Функциональность разбита на **core-модули по одному на тему** (player, vector,
table, string, array, hologram, wirelink, files, timer, sound, quaternion…).
Это канон для задачи владельца «свои языки»: разделение **токенизатор /
препроцессор / парсер / компилятор / рантайм**, а не один монолит.

### 2.2 ZVM — своя виртуальная машина (регистровая)
`lua/wire/zvm/`:
- `zvm_data.lua` — таблицы регистров/лимитов (IP, EAX, EBX, ECX…), RAM/ROM,
  paging (PCAP), очереди запросов (RQCAP), CPUID.
- `zvm_opcodes.lua` (1849 строк) — таблица опкодов по `CPULib.InstructionTable`.
- `zvm_features.lua` (1148) — шина данных, прерывания, память.
- `zvm_core.lua` (827) — ядро исполнения, цикл, обработка опкодов.
- `zvm_tests.lua` — **встроенный тестовый харнесс** (`ZVMTestSuite`, бенчмарки).
Образец того, как делать «свой процессор» внутри Lua: **опкоды = данные,
ядро = интерпретатор**. Полезно для «компьютерного» заказа, если он вернётся.

### 2.3 hlzasm — ассемблер как клиентский компилятор
`lua/wire/client/hlzasm/`: `hc_tokenizer → hc_preprocess → hc_expression →
hc_syntax → hc_codetree → hc_optimize → hc_output` + `hc_opcodes` + `hc_compiler`.
Компиляция на клиенте (пошаговая, с конварами скорости `wire_cpu_compile_speed`),
загрузка на сервер — паттерн «тяжёлый парсинг на клиенте, лёгкое исполнение на сервере».

### 2.4 GTerminal — ОС как плагинная система (САМОЕ ценное)
- `gTerminal` — глобальная таблица; **ОС = модуль** в `gTerminal.os[id]`:
  `GetName() / GetUniqueID() / GetWarmUpText() / ShutDown(ent) / GetCommands()`.
- Диспетчер `gTerminal.os:Call(entity, name, ...)` → берёт `entity:GetOS()`,
  вызывает метод системы через `pcall`.
- **Файловая система per-entity** (`gTerminal.file`): дерево таблиц
  `fileCurrentDir` с `_parent`, `isFile`; `ChangeDir / Write / …` — в памяти,
  не на диске.
- **Аутентификация**: `entity.password` + `client["pass_authed_"..index]`.
- **Ввод**: `gTerminal:GetInput(ent, callback)` — асинхронный ввод с колбэком;
  вывод `gTerminal:Broadcast(ent, text, colorType, position)` чанками по 50.
- **Команды** пишутся через `OS:NewCommand(":help", fn)`; ввод с `:`.
- Три стоковых ОС: `server` (сеть/ISP), `personal`, `default`. Команды:
  `:help :cls :gid :setpass :gnet :f (файлы) :math :gg :isp :x`.
Это готовый рецепт «нормальной ОС компьютера» без мега-зависимости:
**OS-модули + per-entity ФС в памяти + пароль + net-консоль**. Если владелец
вернётся к идее «компьютер со своей ОС» — брать за основу эту схему, а не
писать с нуля (наш удалённый GRM NET OS был ровно про это, но слабее).

### 2.5 TerminalR (TRM) — терминал с дискетами и «взломом»
`lua/terminalr/` + энтити `trm_terminal / trm_disk / trm_hackkit / trm_repairkit / trm_stock`.
Fallout-стиль: программы `menu / loading / hacking / disk_read / disk_write /
disk_eject / password_check / password_save`. Автозагрузка программ из папки
(`file.Find("terminalr/programs/*")`). Паттерн «программы = файлы в папке,
подключаются списком» — удобно расширять.

### 2.6 Wirenet — событийная шина
`lua/wire/wirenet.lua`: регистрация входа/выхода, `TriggerOutput`, запись/чтение
ячеек (`WriteCell/ReadCell`), лимиты. Образец «провода»: **связность энтити через
именованные входы/выходы**, а не прямые вызовы.

---

## 3. Что из этого применимо к GRM прямо сейчас

| Задача GRM | Чем зацепить из аддона |
|---|---|
| Документы/книги (наш GRMML удалён) | E2-редактор + **GTerminal файловый браузер** + см. `ANALYSIS_HLX_BOOKS.md` |
| Лицензии/разрешения | паттерн «предмет-пермит гейтит покупку» (см. `ANALYSIS_HELIX.md`, helix permits) |
| Компьютер (если вернём) | **GTerminal OS-модули** + ZVM как «программируемый чип» |
| Свои языки/форматы | E2-конвейер и hlzasm — канон разделения стадий компилятора |
| Тесты | `zvm_tests.lua` / `data_static/expression2/tests` — тест-файлы рядом с кодом |

## 4. Ограничения / предупреждения

- Wiremod — это Workshop-аддон (свои модели/материалы). Полный перенос в GRM
  не имеет смысла; брать **только паттерны**, не тащить 64 МБ контента.
- Лицензия Wiremod — Apache-2.0 (копирование с сохранением заголовков легально).
- GTerminal использует `!=` и `\r\n` — код старый, но рабочий (GLua допускает `!=`).
- `netstream.lua`, `pb_init.lua` — внутренние зависимости Wiremod, не самоценны.
