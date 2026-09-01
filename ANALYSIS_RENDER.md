# ANALYSIS_RENDER — как устроен рендер в изученных кодовых базах

**Дата:** 2026-08-16 · **Источники:** Wiremod (`AI part 2 details.zip`), `Github DLC GRM.zip`
(MapStudio/лифты/порталы/скины), HLX_Books, и наш GRM.

> Сводка всех встреченных техник рендера в GMod (GLua). Это «меню приёмов»,
> из которого можно брать под будущие заказы (экраны, голограммы, порталы,
> редакторы, UI-скины). Каждая техника — с указанием, ГДЕ она в коде.

---

## 1. 3D2D — рисование интерфейса на энтити в мире

`cam.Start3D2D(pos, ang, scale) → draw.* → cam.End3D2D()`.

- **Лифт** `ht_elevator_floor/cl_init.lua`: табло этажа, кнопки, дисплей — всё
  рисуется в `ENT:DrawTranslucent()` через 4 блока `cam.Start3D2D(lanternPos/cbPos/inPos/signPos)`.
  Приём: **одна энтити рисует несколько независимых 2D-поверхностей** под разными
  локальными позициями/углами. Хит-детект кнопок — в `ENT:Think()` (каждый кадр),
  Ray по `EyeTrace` на локальную плоскость кнопки.
- **EGP-текст** `gmod_wire_egp/lib/objects/text.lua`: текст с поворотом рисуется не
  «поворотом 2D-канваса», а `cam.PushModelMatrix(mat)` + `mat:Translate/Rotate` →
  `surface.DrawText` → `cam.PopModelMatrix()`.
- **EGP-бокс**: `surface.DrawTexturedRectRotated(x,y,w,h,angle)` — поворот спрайта.
- Наш GRM: 3D2D-таблички в `grm_comp_*/cl_init.lua` и `grm_doc_computer` (обложка
  «нажмите E»), лента рукава — отдельный случай (см. §6).

## 2. Render-to-texture (RT) — экран/голограмма как текстура

**EGP** (`gmod_wire_egp/cl_init.lua`) — главный пример:
- `self.GPU = GPULib.WireGPU(self)` — экран-цель 1024×1024, `TEXFILTER.ANISOTROPIC`.
- `self.GPU:RenderToGPU(function() render.Clear(0,0,0,0,true); egpDraw(self) end)` —
  **рисуем голограмму в RT** (внешний кадр), флаг `NeedsUpdate` — перерисовать только
  при изменении объектов.
- `ENT:Draw`: `DrawModel` → `Wire_Render` (провода) → `self.GPU:Render(0,0,1024,1024,...)`
  — RT выводится как текстура на модель экрана. + `render.SetToneMappingScaleLinear(1)`
  на время вывода, чтобы HDR-тонмаппинг не искажал цвет голограммы.
- `framecontrol.lua`: `EGP.SaveFrame/LoadFrame` — снимок `Ent.RenderTable` (сцена как
  таблица объектов) — **кадры/анимация** голограммы.
→ Это ровно тот паттерн, что мы использовали в удалённом фотороботе
(`render.PushRenderTarget → Capture`). Wiremod доводит его до целого «экрана».

## 3. Стебель-буфер (stencil) + ClientsideModel + Matrix — порталы

**Ведьмачий портал** `witcher_gateway/shared.lua` (клиентская часть):
- `DefineClipBuffer(ref)`: `render.ClearStencil → SetStencilEnable(true) →
  SetStencilCompareFunction(STENCIL_ALWAYS) → SetStencilPassOperation(STENCIL_REPLACE)
  → SetStencilWriteMask/TestMask(254) → SetStencilReferenceValue(ref)`.
- `DrawToBuffer()`: `SetStencilCompareFunction(STENCIL_EQUAL)` — рисовать только
  внутри «дыры».
- `EndClipBuffer()`: выключить stencil, очистить.
- «Дыра»/рамка собраны из **ClientsideModel** (hunter/plates): `SetParent(self)`,
  `SetNoDraw(true)`, `EnableMatrix("RenderMultiply", matrix)` — **недеструктивное
  масштабирование/сплющивание клиентской модели** через матрицу (1,1,0.01 — тонкая
  пластина; 1.325,1.142,1 — рамка).
- **Динамический свет**: `DynamicLight(self:EntIndex())` в `Think` — свечение по цвету
  портала (`light.pos/size/style/decay/r/g/b/DieTime`).
- Свечение/рамка «чёрная дыра» — `SetMaterial("vgui/black")`.
→ Канон для любых «окон/порталов/дыр» в Source: stencil + клиентские модели + матрицы.

## 4. Ghost-превью (призрак пропа при постановке)

**MapStudio** `cl_ghost.lua`:
- `applyGhostAppearance(ent)`: `ent:SetColor(GHOST_COLOR)` + **`RenderOverride`**:
  ```
  cam.IgnoreZ(true)
  render.SetBlend(a/255)
  render.SetColorModulation(r/255, g/255, b/255)
  self:DrawModel()      -- (базовый рендер)
  render.SetColorModulation(1,1,1); render.SetBlend(1); cam.IgnoreZ(false)
  ```
  То есть полупрозрачный «сквозь стены» призрак = `IgnoreZ + Blend + ColorModulation`.
- Геометрия захвата: `GetRenderBounds()` → углы → поворот `rotatedOffset`/`worldBounds`.

## 5. Полностью кастомный Derma-скин (тема UI)

**Ciero skin** `cl_cieroskin.lua` (34 КБ):
- `SKIN.GwenTexture = Material("gwenskin/cieroskin.png")` + набор `texGradientUp/Down`.
- Переопределён **каждый** `SKIN:PaintXXX(panel,w,h)`: PaintPanel, PaintFrame,
  PaintButton, PaintTree, PaintCheckBox, PaintTextEntry, PaintMenu, PaintComboBox,
  PaintVScrollBar, PaintWindowCloseButton… (~40 методов).
- Цвета — в таблице `SKIN.Colours.*`; градиенты — `surface.SetMaterial(texGradientUp)`
  + `DrawTexturedRect`.
- Мелочь: `PaintTreeNode` рисует линии дерева вручную (`surface.DrawRect/DrawLine`).
→ Эталон того, как делается «свой вид UI» целиком (то, что владелец называет
«нормальный дизайн, а не чёрт пойми что»). Наш `GRM.UI.Track` + `frame()/btn()` в
`cl_grm_electronics` — упрощённая версия этой идеи.

## 6. Кастомная геометрия (линии/сетки/маркеры)

- **MapStudio сетка** `cl_grid.lua`: `basisFromNormal`, `sampleSurface`, сетка как
  `render.DrawLine`/3D-примитивы (линии по ячейкам).
- **MapStudio манипулятор** `cl_gizmo.lua`: гизмо (move/rotate/scale) — геометрия из
  осей/колец, хит-тест по экранному углу (`screenAngle`), снаппинг.
- **Wiremod кабели/провода**: `Wire_Render` — линии между портами (аналог нашей
  «ленты рукава»: ломаная + DrawBox/Line).
- **Консольный экран** `gmod_wire_consolescreen/cl_init.lua`: **символьный рендер** —
  `DrawSpecialCharacter(c,x,y,w,h,r,g,b)` рисует глиф полигонами, текст — по ячейкам
  (терминал Fallout-стиля). Полезно для «экранов-терминалов».

## 7. Текст-рендер с разметкой (Markdown → команды отрисовки)

**HLX_Books** `cl_book.lua` (см. `ANALYSIS_HLX_BOOKS.md`):
- `Tokenise` (инлайн) + `ParseToCommands` (блоки → список `{h, fn}`) →
  «команды отрисовки» с высотами. Рисование идёт **не в момент парсинга**, а по
  сгенерированному списку команд — это позволяет считать высоту страницы и
  разбивать на страницы. Ключевой приём: **парсер отделён от рендера**.
- Палитра `BookPalette(cfg)` с 18 слотами + 8 тем.

## 8. Выводы для GRM

1. **Экраны**: если нужен «нормальный» компьютер/терминал — RT-паттерн EGP
   (`RenderToGPU` 1024×1024 + вывод текстурой) надёжнее, чем 3D2D для «много текста».
2. **Голограммы/маркеры**: EGP-объекты (box/text/poly/line + очередь `EGP.Queue`)
   — готовая модель «сцена = таблица объектов + очередь».
3. **Порталы/двери-«дыры»**: stencil + ClientsideModel + `RenderMultiply` — для любых
   «окон» в Source (у нас есть FFD/двери — можно расширить).
4. **UI-тема**: Ciero skin — ориентир, если владелец снова попросит «красивый UI».
5. **Призрак постановки**: `IgnoreZ + SetBlend + SetColorModulation` — для тулов
   размещения (наш `grm_service_tool`/`grm_perm_tool` могут получить ghost-превью).
6. **Терминал**: character-cell рендер consolescreen — для Fallout-терминала/взлома.
