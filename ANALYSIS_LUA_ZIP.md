# Разбор `lua.zip` (залит в ветку 13.08.2026, коммит `9e8de62`)

Это **не 7z и не наша сборка GRM**. Это снимок `garrysmod/lua/` с живого сервера:
ванильный Lua движка GMod + несколько своих/хостинговых файлов сверху.

**Нельзя распаковывать поверх `lua/` репозитория** — затрёт 400 GRM-модулей стоковым Sandbox.

| Метрика | Значение |
|---|---|
| Файл | `lua.zip`, 14 МБ |
| Записей | 328 (292 `.lua`, 3 `.dll`, 1 `.txt`) |
| Сумма распакованного | ~13.6 МБ, из них 11.4 МБ — `gmsv_mysqloo_linux64.dll` |

---

## 1. Состав (три слоя)

### A. Стоковый GMod (большая часть)

`includes/`, `vgui/` (весь Derma), `derma/`, `menu/`, `postprocess/`, `drive/`,
`matproxy/`, `skins/default.lua`, `weapons/weapon_fists|flechettegun|medkit`,
`entities/sent_ball` + виджеты, `autorun/base_npcs|base_vehicles|game_hl2`,
`autorun/properties/*`, `autorun/utilities_menu.lua`.

Это исходники движка. Для Q-меню важны не «все 292 файла», а узлы ниже (§3).

### B. Свои / хостинговые (читать внимательно)

| Файл | Что это |
|---|---|
| `autorun/server/handler.lua` (42 КБ) | Pterohost: анти-эксплойт + стук на `req.pterohost.com` |
| `autorun/easylua.lua` + `tinylua.lua` | ELua: `me/this/here`, массовые операции |
| `luadev/*` + `autorun/server/luadev_chatcmds.lua` | LuaDev: удалённый запуск Lua (`!l`, `!lc`, `!lm`…) |
| `autorun/sh_grm_shop_integration.lua` | Старая копия нашей интеграции дилера (268 стр. vs 272 у нас) |
| `autorun/client/cl_vehicle_hud.lua` | Старый VK-оверлей владельца машины (104 стр. vs 215 у нас) |
| `autorun/client/cl_hide_playermodels_menu.lua` | Глушит `player_manager.AddValidModel` |
| `entities/grm_money_printer/*` | Старый принтер v2.1 (187 стр. init vs 337 у нас) |
| `entities/grm_money_drop/*` | Почти как наш (56 vs 59) |
| `lua/bin/*.dll` | luasocket win32/64 + **mysqloo linux64 (11 МБ)** |

### C. Бинарники

`gmsv_mysqloo_linux64.dll` — MySQLOO. В GRM его нет: деньги живут в JSON.
На сервере, откуда снят zip, MySQL, видимо, ставили отдельно.

---

## 2. Свои модули — по существу

### `handler.lua` (Pterohost)

При входе/выходе игрока шлёт IP сервера и игрока на `https://req.pterohost.com/handler/handler.php`
с HMAC-подписью. В файле **зашит публичный modern-ключ**. Zip лежит в публичном GitHub —
ключ считать скомпрометированным, сменить в панели хостинга.

Модули: ClientFPS (`gmod_mcore_test` и т.п. через `SendLua`), NetExploitProtection
(список «дырявых» net + honeypot), опциональный HTTP-whitelist.

Net-ловушка: если имя из `legit_nets` **не** зарегистрировано за 1 с после старта —
создаётся пустой `net.Receive`, любой вызов = kick/ban. Имена GRM (`GRM_*`)
в списке нет. Совпадений вроде `phone` / `SendMoney` у нас нет.

**В аддон GRM не тащить.** Это файл хостинга, не геймплея.

### LuaDev + EasyLua

`!l` / `!ls` / `!lc` / `!lsc` / `!lm` / `!print` — выполнение произвольного Lua
на сервере/клиентах. Права через `aowl` (`developers`, `lm` — `players`).
Если на сервере есть aowl и группа developers — это полноценный RCE.
Для продакшена держать только на закрытом dev-сервере.

EasyLua пишет в `_G` (`me`, `this`, `here`, `all`) на время сессии — не пересекается
с `GRM = GRM or {}`, но пачкать глобалы любит.

### `cl_hide_playermodels_menu.lua`

```lua
player_manager.AddValidModel = function() end
player_manager.AllValidModels = function() return {} end
```

Глушит ванильный список моделей в Q. **Ломает** гардероб / `sh_grm_character` /
меню внешности, если они зовут `AllValidModels`. На GRM-сервер не ставить,
либо ограничить только ванильным spawnmenu (который мы и так закрываем).

### GRM-файлы в zip — устаревшие копии

| Модуль | Zip | Репозиторий | Вердикт |
|---|---|---|---|
| shop_integration | 268 | 272 | Наш новее |
| money_printer init | 187 | 337 | Наш новее (фиксы цепного взрыва уже внутри) |
| money_drop init | 56 | 59 | Почти то же |
| cl_vehicle_hud | 104 | 215 | Наш новее (полный VK HUD) |

Мержить из zip в `lua/` **не нужно**.

---

## 3. Что из стока важно для Q-меню

Прочитаны целиком: `spawnmenu.lua`, `controlpanel.lua`, `dscrollpanel.lua`,
`dform.lua`, `spawnicon.lua`.

### Как ваниль выбирает инструмент

`spawnmenu.ActivateTool(strName)`:

1. Ищет пункт в `g_ToolMenu` (вкладки → категории → item).
2. `RunConsoleCommand` из `item.Command` (обычно `gmod_tool <id>`).
3. `cp = controlpanel.Get(strName)` — **глобальная** скрытая `ControlPanel`.
4. Если панель ещё не строилась: `cp:FillViaTable({ CPanelFunction = item.CPanelFunction })`
   → это и есть `TOOL.BuildCPanel`.
5. Кладёт панель на правую вкладку инструментов.

Отсюда два факта для нашей Стройки:

- Вызов `BuildCPanel` в **нашем** кадре = чужой код в нашем `Paint`/`layout`. Так и висло.
- `controlpanel.Get` создаёт панель **невидимо**. Чужой код исполняется, когда
  **впервые** зовут FillViaTable / BuildCPanel, не при `Get`.

Правильный путь v4: **никогда не звать FillViaTable/BuildCPanel**.
Выдавать тул командой `gmod_tool <id>`. Настройки — только наша схема с человеческими подписями.

### Почему на скрине справа `a1, a3, b1…`

Автосхема из `TOOL.ClientConVar`. У 3D2D Textscreen конвары названы `a1`…`r3`
(строки экрана). Мы вывалили их как поля. Это не ванильная панель, а наш
авто-дамп. Лечение: автосхему в UI **не использовать**. Нет ручной схемы —
честная подсказка, без кучи нулей.

### DForm (ванильная C-панель)

`DForm:AddItem` всегда `Dock(TOP)` + `InvalidateLayout`. Подписи `SetDark(true)` —
тёмный текст под **светлый** скин. На нашей тёмной полке они сливаются.
Ещё одна причина не встраивать ControlPanel/DForm к себе.

### DScrollPanel

`GetChildren()` = холст + VBar. `Clear()` чистит **только холст**.
`PerformLayoutInternal` читает `pnlCanvas:GetTall()` — мёртвый холст = `NULL Panel`.
Это уже учтено в v4 (`:Clear()`, `AddItem`, `emptyBox`).

`AddItem` в стоке **только** `SetParent(canvas)` — **без** `Dock(TOP)`.
Dock ставит тот, кто добавляет (DForm, наш `scrollAdd`). Знать: голый `AddItem`
не раскладывает строки вертикально.

### SpawnIcon

`SetModel` → внутренний `ModelImage` (рендер в текстуру). Это и есть стопор
при пачке иконок. Порции по 8/кадр — правильное направление. Ванильный
каталог тоже создаёт иконки лениво по видимой области spawnlist.

---

## 4. Ванильная раскладка Q (к задаче «инструменты справа»)

Сток:

```
слева  — CreationMenu (пропы, вкладки)
справа — ToolMenu: категории + список тулов
         выбранный тул → ActiveControlPanel (DForm) в той же правой колонке
```

Владелец на скрине v4 увидел вкладку «Инструменты» слева и мусорные поля справа.
Нужно как в ванили / как в нашем v3:

- слева — каталог / мои объекты / настройки админа;
- справа сверху — категории инструментов;
- справа снизу — параметры **только если есть ручная схема**.

HOLD-Q не трогать.

---

## 5. Что из zip брать, чего не брать

**Брать как справочник (уже прочитано, в `lua/` не копировать):**
поведение `spawnmenu.ActivateTool`, `controlpanel.Get`, DForm, DScrollPanel, SpawnIcon.

**Не класть в аддон GRM:**
`handler.lua`, LuaDev/EasyLua, `cl_hide_playermodels_menu.lua`, `*.dll`, весь `includes/`/`vgui/`/`menu/`.

**Не заменять наши файлы копиями из zip:**
shop_integration, money_printer, money_drop, cl_vehicle_hud — у нас новее.

---

## 6. Заметки по безопасности (владельцу)

1. В `handler.lua` зашит ключ Pterohost — сменить, zip публичный.
2. LuaDev на бою = выполнение Lua от группы developers.
3. `cl_hide_playermodels_menu` убивает список моделей персонажа.
4. 11 МБ mysqloo в zip — к GRM не относится; если на хосте крутится свой MySQL,
   это отдельный контур, не наш JSON.

Прочитаны все 292 lua: сток классифицирован, все нестоковые файлы разобраны целиком,
ключевые модули Q-меню (spawnmenu, controlpanel, dform, dscrollpanel, spawnicon) —
построчно.
