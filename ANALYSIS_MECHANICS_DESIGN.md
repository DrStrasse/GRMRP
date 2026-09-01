# ANALYSIS_MECHANICS_DESIGN — механики, гизмо, тексты и дизайн (доскональный разбор)

**Дата:** 2026-08-16 · **Источники:** `AI part 2 details.zip` (Wiremod), `Github DLC GRM.zip`
(MapStudio/лифты/порталы/скины), HLX_Books, helix-репо.
**Цель:** понять КАК что сделано — механики, гизмо, текстовые системы и дизайн, чтобы
писать GRM-код лучше (и заимствовать приёмы).

> Дополняет `ANALYSIS_RENDER.md` (техники рендера) — здесь про архитектуру и UX-детали.

---

# 1. МЕХАНИКИ

## 1.1 MapStudio — редактор как «модель состояния + команды + предпросмотр»

### Модель «клиент-состояние»
- Всё состояние объектов — `MapStudio.ClientState.objects` (таблица id→objectData), у
  сервера — авторитет через net-каналы `ms_create_object / ms_update_object /
  ms_delete_object` (batch-версии `*_objects` для пачки).
- Объект — плоская таблица с whitelist-полями `SERIALIZABLE_OBJECT_FIELDS`
  (`type/class/model/pos/ang/scale/skin/bodygroups/color/material/submaterials/
  renderMode/renderFx/collision/frozen/gravity/motion/reactive/behavior/layer/notes/
  entityData/keyValues`). Лишние поля отбрасываются санитайзером `SanitizeSerializable`
  (NaN/Inf → nil, глубина ≤8).
- **Паттерн «клиент оптимистично применяет, сервер подтверждает»**: `applyPreview`
  сразу двигает энтити, при коммите шлётся `before/after/patch`.

### Undo/Redo — снимки
`cl_undo.lua`: стек действий `{type="update"|"batch_update"|"delete", before, after, id}`.
`Undo()` применяет `before`, `Redo()` — `after`. Максимум 80. Откат на смене профиля
чистит стек. → **Канон «отмена = before/after-снимки», а не обратные операции.**

### Умное дублирование и буфер
`CLONE_FIELDS` — список копируемых полей; `SMART_DUPLICATE` — Ctrl+D дублирует со
сдвигом по сторонам (left/right/front/back) с шагом `SMART_DUPLICATE_GAP=0.5`.
Буфер — Ctrl+C/Ctrl+V через `editor.ClipboardTemplate` + `MapStudio.DeepCopy`.

### Клавиши — конвары + edge-детекция
Каждый бинд — `CreateClientConVar("mapstudio_bind_*")`, в `Think` цикл `ACTION_BINDS`
с проверкой **фронта** нажатия (`wasDown==false and isDown==true`), модификаторы
(`requireCtrl`), подавление «залипших» клавиш (`SuppressedKeys`) пока клавиша отпущена.
Блокировка SpawnMenu/ContextMenu, когда редактор открыт (хуки возвращают `false`).
→ **Приём: назначаемые клавиши через конвары + edge-детект в Think** (у нас сейчас
почти всё — чат-команды; это альтернатива).

### Свободная камера + сетка + снаппинг
- `cl_freecam.lua` — режим камеры редактора (`Freecam.Active/Pos/Ang`).
- `cl_grid.lua` — сетка: конвары (`show_grid/snap_grid/grid_size/grid_radius/
  rotation_snap`), контекст снаппинга `ActiveContext` (поверхностный/свободный),
  `SnapVector`, `basisFromNormal` (тангент/битангент из нормали), `RotationPresets`.
- ALT временно отключает снап угла (в `snapAngle`).

### Сервер: хранение / права / защита / rate-limit
- `sv_storage.lua` — сегменты-каталоги, таймштампы, отчёт `report.issues` (skip/fallback),
  no-physics fallback, лог проблем при сейве.
- `sv_permissions.lua` — конвары прав: `mapstudio_admin_only`, `mapstudio_allow_players`,
  `mapstudio_allowed_steamids` (whitelist SteamID/64), `mapstudio_public_edit_existing`;
  `MapStudio.ServerCanUse(ply, action)` + rate-limit (`MapStudio.RateLimit`).
- `sv_protection.lua` / `sv_spawner.lua` / `sv_import_permaprops.lua` — защита и импорт.

## 1.2 Лифт (ht_elevator_floor) — «составная энтити»
- Сервер `init.lua`: этажи — отдельные энтити, **перенумеровываются по высоте**
  (`sort floors by z`, нижний = «Floor 1»), спавн частей кабины (`SpawnChamberParts`:
  пол/оболочка/двери/кнопка) отдельными пропами с `MOVETYPE_NONE`, звук движения
  (`CreateSound` + `Move`), логика телепорта/дисплея в `Think`.
- Клиент — только 3D2D-панели (см. рендер) и хит-детект в `Think`.
→ Паттерн «**одна логическая сущность = несколько физических пропов + 3D2D UI**».

## 1.3 Портал (witcher_door/gateway) — телепорт с анти-застреванием
`Touch()` — детальный алгоритм:
1. Пропуск, если подошёл «не с той стороны» (`InFront` по нормали), кулдаун `lastPort+0.4`.
2. Только игроки и физические объекты (двери/func_ — нет), без constrained к родителю.
3. Скорость/направление: не телепортирует, если движется от портала или медленно
   (`dir>0 or vel:Length()<1`).
4. `TransformOffset` пересчитывает позицию/скорость/угол между парой порталов
   (`GetOffsets/GetPortalAngleOffsets`).
5. Коррекция: высота глаз (crouch), наклонные порталы, `util.IsInWorld` поиск свободной
   клетки (цикл 0..20 по z), `TraceEntity` с hull игрока (цикл 0..30 по right) — ставят
   только в не-`AllSolid` точку, иначе `return`.
6. `ScreenFade(SCREENFADE.IN, black, 0.2, 0.03)` + звук с обоих концов.
→ **Канон «телепорт без застреваний»** (пригодится для шлюзов/точных маршрутов).

## 1.4 Wiremod — программируемая электроника (механики ядра)
- **E2**: компиляторный конвейер `tokenizer→preprocessor→parser→compiler` (см.
  `ANALYSIS_AI_PART2.md`). Валидатор `E2Lib.Validate(source)` — компиляция на клиенте.
- **ZVM/ZCPU**: регистровая VM — опкоды как таблицы (`zvm_opcodes`), ядро-интерпретатор
  (`zvm_core`), шина/прерывания (`zvm_features`), встроенный тест-харнесс (`zvm_tests`).
- **hlzasm**: клиентский ассемблер (hc_tokenizer→…→hc_output), пошаговая компиляция с
  конварами скорости, загрузка на сервер.
- **Wirenet**: шина вход/выход (`TriggerOutput`, `WriteCell/ReadCell`), лимиты.

## 1.5 Наш GRM (для сверки) — что уже применяем
- Биржа труда v2: `StartJob`/`TickJobs` (stay/goto/roundtrip/garbage/taxi), маршруты
  `points`, `needVehicle`; персист активных задач массивом.
- Лицензии: `DOC.HasValid*License` + госпошлина через `GRM.Services.Charge` + теория-
  экзамен `GRM_Doc_Exam` (банк вопросов, проходной 80%).
- Undo/снимки, rate-limit, whitelist-поля, снаппинг — **НЕ используем** (кандидаты на
  заимствование из MapStudio для тулов размещения).

---

# 2. ГИЗМО (MapStudio `cl_gizmo.lua`) — досконально

## 2.1 Данные-описания вместо хардкода
```lua
AXES  = { x={vector=Vector(1,0,0), color=Color(230,80,80)},
          y={vector=Vector(0,1,0), color=Color(80,210,95)},
          z={vector=Vector(0,0,1), color=Color(85,150,255)} }
RINGS = { rot_x={axis="x", normal=…, a=Vector(0,1,0), b=Vector(0,0,1), color=…}, … }
RING_ANGLE_FIELDS = { rot_x="r", rot_y="p", rot_z="y" }
```
Оси X/Y/Z = красный/зелёный/синий; кольца вращения — по тем же цветам, angle-поле
маппится на `r/p/y` (pitch/yaw/roll).

## 2.2 Геометрия зависит от расстояния и размера объекта
`gizmo.GetGeometry(pos, obj)`:
- `base = clamp(distance*0.13, 96, 300)` — размер гизмо растёт с дистанцией.
- `axisLength = clamp(max(base, half.x+margin), 96, 1000)` — стрелки **выносятся за
  габариты** объекта (`entityHalfExtents` из `OBBMins/Maxs × modelScale`).
- `ringRadius.rot_z = clamp(max(minRing, sqrt(half.x²+half.y²)+margin), 72, 1100)` —
  кольца охватывают объект по плоскости вращения.
- Пороги хита: `hitDistance≈base*0.08`, `centerHit`, `centerRadius`.

## 2.3 Хит-детект ручек (на экране, не в мире)
`GetHoveredHandle()`: берёт `pos:ToScreen()` и считает **расстояние от курсора до
сегмента в экранных координатах** (`distanceToSegment` + для кольца — `ringHitDistance`
по 72 сегментам окружности). Приоритет: центр → оси → кольца (минимальная дистанция).
→ **Приём: хит по гизмо считается в 2D-экране, а не рейкастом в 3D.**

## 2.4 Drag-контекст (BeginDrag → previewDrag → EndDrag)
`BeginDrag()` собирает контекст:
- `beforeById` = `DeepCopy` каждого объекта (для undo), `startById` = pos/ang,
  `filterEnts` (чтобы рейкаст не цеплял сами объекты), `mouseX/Y`, `startMouseAngle`,
  `length`, и `snapContext` (если snap включён — `CreateSurfaceContext`/`CreateFreeContext`).
- Для оси: вектор оси проецируется на экран (`screenX/screenY/screenLengthSqr`) — если
  проекция вырождена, драг отменяется.
- `previewDrag` каждый кадр: `previewAxisDrag` / `previewCenterDrag` / `previewRingDrag`.
- `applyPreview` сразу двигает и объект в `ClientState`, и живую энтити (`SetPos/SetAngles`).
- `EndDrag` формирует `updates[]` с `before/after/patch` → `pushUndoAndCommit` (одна
  undo-запись на весь драг).

## 2.5 Вращение — снап и нормализация углов
`screenAngle` (atan2 от центра), `angleDelta` (нормализация ±180), `snapAngle`
(шаг `Grid.GetRotationSnap`, ALT отключает), `applyRingDelta`/`rotateAngleAroundAxis`
(формула Родригеса через `axis:Cross/Dot`, `RotateAroundAxis` у Angle).

## 2.6 Колесо мыши = «глубина» (третья ось)
`AdjustSelectedDepth(delta)`: перемещает выбранное **вдоль направления камеры**
(`cameraDirection`), шаг = grid_size или 48, со снапом; группирует в `WheelDepth` и
коммитит через таймер 0.2 с (`CommitWheelDepth`) — чтобы не плодить undo-записей на
каждое деление колеса.

## 2.7 Двухпроходный рендер
`PostDrawTranslucentRenderables → drawGizmoPass(false) [обычный] + drawGizmoPass(true)
[xray: cam.IgnoreZ + alpha 88]`. Ручки подсвечиваются белым при hover/drag
(`handleColor`). Центр — сфера, оси — линия + «стрелка-головка» (2 линии-крыла) +
`render.DrawSphere`, кольца — 72-сегментные `render.DrawLine`-окружности.

---

# 3. ТЕКСТЫ (системы текста/локализации/редакторы)

## 3.1 MapStudio — локализация (`sh_language.lua`)
- `lang.Register(code, phrases)`, `DetectLanguage()` (`gmod_language` → ru/en),
  `NormalizeLanguage` (auto→default, незнакомый→en), `SetLanguage` (+хук
  `MapStudioLanguageChanged`), `Get(key, replacements)` c **плейсхолдерами**
  `lang.Format("{count}", {count=5})` и **фолбэком на английский**, если ключа нет в
  текущем. Короткий алиас `MapStudio.T`.
→ **Эталон системы переводов**: ключи + плейсхолдеры + fallback. У нас в GRM строки
  захардкожены по-русски — если захотим ru/en, брать эту схему.

## 3.2 Wiremod TextEditor — свой текстовый редактор (`texteditor.lua`)
Архитектура:
- **Ввод через скрытый DTextEntry** (`self.TextEntry` 0×0, multiline), события
  перехватываются (`OnKeyCodeTyped/OnTextChanged/OnLoseFocus`), **отрисовка строк —
  своя** (`Rows`, `Caret`, `Scroll`, `PaintRows`, `LineNumberWidth`, мигание курсора
  `Blink=RealTime()`), свой `DVScrollBar`.
- **Режимы подсветки** — модули в `modes/*.lua` (`WireTextEditor.Modes`), каждый:
  `SyntaxColorLine(row) → {{text, {Color, underline}}, …}`; `UseValidator` +
  `Validator` (E2: `E2Lib.Validate`, ZCPU: `CPULib.Validate`).
- **Автодополнение**: 6 стилей (`AC_STYLE_DEFAULT/VISUALCSHARP/SCROLLER/…/ECLIPSE/ATOM`),
  конвар выбора.
- **Подсветка E2** (`modes/e2.lua`): `keywords` (if/while/for/switch/function/… с
  маркером «можно перед (»), `directives` (`@name/@inputs/@outputs/@persist/@trigger…`
  с режимом FULL/VARS/PARTIAL), `colors` (directive/number/function/notfound/variable/
  string/keyword/operator/comment/ppcommand/typename/constant). Типы через
  `wire_expression_types` (`istype`).
- **Подсветка ZCPU** (`modes/zcpu.lua`): opcodeTable из инструкций, регистры, метки,
  макросы; hint-бокс по наведению (debounce 0.3 с).

## 3.3 HLX_Books — Markdown-текст (парсер отделён от рендера)
`Tokenise` (инлайн: стеки color/font/link, `earliest`) + `ParseToCommands`
(блоки: h1-h3, quote, ul/ol, table, codeblock, hr, chart, image → список `{h,fn}`).
`DrawTokens/WrapLine` — перенос по ширине шрифта. Палитра `BookPalette(cfg)`.

## 3.4 Документация E2 (`e2descriptions.lua`)
Десkriptions функций/методов для автодополнения и хелпа — «код + описание + типы»
в одном месте; редактор и `e2helper` читают это. → паттерн «самодокументируемые API».

## 3.5 GTerminal — консольный текст
Клиент хранит строки `gTerminal[index] = {text, color}`, cap 24 строки (кольцо),
`position` — вставка/замена строки, цвета по индексу (`ColorFromIndex`). Ввод — скрытый
DTextEntry-попап (каретка, обрезка по 50 симв).

---

# 4. ДИЗАЙН

## 4.1 MapStudio — минималистичная тёмная тема + свои виджеты
- `cl_theme.lua`: `theme.Colors` (10 слотов: background/panel/panelAlt/border/accent/
  accentHover/danger/text/muted/field), шрифты Roboto (`Title 22 / Label 15 / Small 13`),
  функции `PaintPanel/PaintButton/StyleLabel`.
- **Свои виджеты** (`vgui/ms_*.lua`): `MS_Panel` (Paint→Theme.PaintPanel),
  `MS_Button` (Danger/Toggled-состояния, disabled-вид), `MS_Frame` (пустой Paint —
  канвас под свой рендер), `MS_ModelCard`, `MS_PropertyRow`, `MS_TextEntry`.
- Панели раскладки: `LEFT_PANEL_WIDTH=390`, `RIGHT_PANEL_WIDTH=360`,
  `COLLAPSE_HANDLE_WIDTH=18` — константы, коллапс-ручки.
→ **Рецепт «нормального UI»**: плоская палитра + ограниченные шрифты + 6–8 своих
виджетов вместо кучи Derma-хаков. Ровно то, что владелец просил по бирже труда.

## 4.2 Ciero skin — GWEN-стиль «плоская таблица цветов + текстурный атлас»
- Все цвета — плоские поля `SKIN.bg_color/bg_color_sleep/control_color/listview_hover/
  text_normal/colPropertySheet/colTextEntryBG/…` (~30 слотов).
- **Текстурные бордюры из PNG-атласа**: `GWEN.CreateTextureBorder(x, y, w, h, l, t, r, b)`
  — 9-slice-бордюр из `materials/gwenskin/cieroskin.png` (`SKIN.tex.Selection/Panels.*`).
- Градиенты — `Material("gui/gradient_up/down")` + `DrawTexturedRect`.
- `PaintXXX` переопределяет ~40 методов скина (кнопки с 4 состояниями: down/hover/normal,
  `control_color_highlight/active`).
→ Для «своего скина на всю сборку» — за основу cieroskin; для «темы одного меню» —
  MapStudio Theme.

## 4.3 HLX_Books — 8 тем × 18 слотов + 7 стилей обложек
- `COLOR_PRESETS` (8): Parchemin Classic / Océan Profond / Forêt Sombre / Aurore
  Polaire / Crépuscule Violet / Sable Ancien / Acier Industriel / Sakura Rose —
  каждый задаёт **все 18 слотов** (coverColor, textColor, accentColor, pageColor,
  bodyColor, headColor, quoteBG/Bar, codeBG/Text, hr, tableHdr/Line, navBtn/Hover/Text,
  chartBar/Grid).
- `EDITOR_COLOR_FIELDS` — пикеры цвета по тем же 18 слотам; `CoverStyles` (7):
  classic/bordered/minimal/ornate/stamp/parchment/dark — рисование рамок/линий/штампов
  примитивами (`DrawRect/DrawOutlinedRect/DrawLine`), плюс обложка-картинка по URL.
→ **Рецепт «темы»**: пресет = полный набор слотов; стиль обложки = чистая функция от
палитры. У нас это применимо к документам (бланки) и книгам.

## 4.4 EGP — сцена как данные
Голограмма = `RenderTable` объектов (box/text/poly/line/…), каждый объект — таблица с
`Draw/Transmit/Receive/DataStreamInfo/Contains`; очередь `EGP.Queue` per-player;
фреймы `SaveFrame/LoadFrame`. → «декларативный UI в 3D».

---

# 5. ВЫВОДЫ ДЛЯ GRM (что брать)

| Где применить | Что заимствовать | Откуда |
|---|---|---|
| Тулы размещения (`grm_service_tool`, `grm_perm_tool`) | ghost-превью, гизмо (оси/кольца, hit в 2D, undo-снимки, снаппинг, ALT-отключение снапа) | MapStudio |
| Undo/Redo в редакторах | `before/after/patch`-снимки + batch | MapStudio `cl_undo` |
| Переназначаемые клавиши | бинды через `CreateClientConVar` + edge-детект в Think | MapStudio `cl_editor` |
| Переводы ru/en | ключи + `{плейсхолдеры}` + fallback на en | MapStudio `sh_language` |
| Текстовый редактор | скрытый DTextEntry + своя отрисовка строк + modes-подсветка + автодополнение | Wiremod `texteditor` |
| Документы/книги | Markdown-парсер + 8 тем + стили обложек | HLX_Books |
| UI-тема сборки | плоская палитра + шрифты + 6–8 своих виджетов (или GWEN-скин) | MapStudio Theme / cieroskin |
| Портал/шлюз | телепорт с анти-застреванием (hull-trace, кулдаун, направление) | witcher_door |
| Составная механика | одна логика = несколько пропов + 3D2D | ht_elevator_floor |
| Компьютер/электроника (если вернём) | E2-конвейер + ZVM + GTerminal OS-модули + шина Wirenet | Wiremod |

**Приоритет для следующего шага**: перенести «дизайн-паттерн» MapStudio Theme
(плоская палитра + свои виджеты) в UI биржи труда/терминалов — это прямо закрывает
прошлый запрос владельца «нормальный UI, а не чёрт пойми что».
