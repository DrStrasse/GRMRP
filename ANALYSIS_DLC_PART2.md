# ANALYSIS — «DLC GRM Part 2.zip» (фотокамера + параметрический строитель)

**Дата:** 2026-08-16 · **Источник:** коммит `fc88f61` «Add files via upload» на `arena/01a00565-drstrasse`
**Архив:** `DLC GRM Part 2.zip` (5.5 МБ, 74 файла)

> Второй DLC-аддон. Два крупных блока: **PhotoCamera** (камера → фото → печать →
> архив → доска расследования) и **Parametric Builder** (конструктор пропов на
> графах). Плюс металлоискатель и повтор witcher-порталов.

---

## 1. PhotoCamera — «камера и печать фото» (прямо под заказ владельца)

### 1.1 Захват фото (`lua/photocamera/cl_capture.lua`) — САМОЕ ценное
```
GetRenderTarget("PhotoCamera_CaptureRT", W, H)
render.PushRenderTarget(rtTexture)
render.Clear(0,0,0,255, true, true)
render.RenderView({ origin=eyePos, angles=eyeAng, x=0,y=0, w=W,h=H,
                    fov=captureFOV, drawviewmodel=false, drawhud=false })
local data = render.Capture({ format="jpeg", quality=JpegQuality, x=0,y=0,w=W,h=H })
render.PopRenderTarget()
```
- **RT-захват через `render.RenderView`** (полноценная 3D-сцена без HUD/вьюмодели),
  а не скриншот экрана — это канон для нашего «печать любых фото».
- **FOV под рамку видоискателя**: `vfHalfAngle = atan(vfFrac * (scrH/scrW) * tan(screenFOV/2))`,
  затем `captureFOV` под aspect RT — чтобы квадратная рамка видоискателя целиком
  попала в кадр. Читает `BaseFOV/SmoothedZoom/ViewfinderFraction` с оружия
  `weapon_photo_camera`.
- **Чанковая загрузка на сервер**: JPEG → сжатие (`Utils.CompressData`) → разбивка
  на `ChunkSize`, отправка `PhotoCam_PhotoDataChunk` (photoID, i, chunks, len, data)
  с таймерами 0.05 с — обход net-лимита размера сообщения.
- **Локальный кеш**: `file.Write("photocamera/<id>.jpg")` + `Material("../data/…")`.

### 1.2 Photomode — свободная камера (`cl_photomode.lua`)
- `net.Receive("Photomode_Toggle")` вкл/выкл; движение W/S/A/D/Space/Ctrl в `Think`,
  мышь через `InputMouseApply` (yaw/pitch с clamp ±89), **`CalcView`** подменяет
  origin/angles камеры (`drawviewer=true`), `CreateMove` блокирует ввод, `HUDShouldDraw`
  прячет HUD, `PlayerBindPress` глушит бинды, `ChatText` прячет спам-конвар.
→ Эталон «фото-режима»/свободной камеры.

### 1.3 Печать/архив/доска (сущности)
- `ent_photo` — фото в мире (материал `PhotoCamera.Capture.GetMaterial` + рамка
  polaroid через 3D2D).
- `ent_photo_printer` — принтер фото; `ent_photo_archive` — архив (серверный `sv_archive`,
  клиент `cl_archive`); `ent_photo_board` — **«Investigation Board»** (доска
  расследования, `cl_board_ui`) — прямо про «фотороботы + фото-архив полиции».
- `weapon_photo_camera` (SWEP) + `weapon_photo_archive` (предмет архива).
- Сервер: `sv_photo/sv_printer/sv_board/sv_archive/sv_networking`.

### 1.4 Металлоискатель `ddv_metal_detector`
Энтити + тул `ddv_metal_detector_tool.lua` (рамка/проверка — аналогична нашему FFD-сканеру).

---

## 2. Parametric Builder (PB v18) — конструктор пропов

`lua/weapons/gmod_tool/stools/parametric_builder/` (~16к строк):
- **Модульный загрузчик** `PB.MODULES = { {name, side}, … }` + `ModulePath` — файлы
  подключаются списком (`pb_core/pb_config/pb_trace/pb_graph/pb_constraints/
  pb_solver/pb_tool/pb_project/pb_net/pb_ui`).
- **pb_graph.lua** (2964) — граф постройки; **pb_constraints.lua** (1582) —
  ограничения; **pb_solver.lua** (1508) — решатель; **pb_project.lua** (1749) —
  проект; **pb_net.lua** (2603) — серверная сеть; **pb_ui.lua** (4567) — клиентский UI.
- Логирование `PB.Log` с уровнями (Trace/Info/Warn/Error), `PB.Util` (CopyVec/CopyAng/ShallowCopy).
→ Образец «тяжёлого» инструмента строительства: граф + ограничения + солвер. Для GRM
  не переносить целиком — только паттерн «модули списком + лог-уровни + отдельный net/ui».

---

## 3. Что применимо к GRM

| Задача GRM | Заимствовать | Файл |
|---|---|---|
| «Печать фото» (фоторобот/любые фото) | RT-захват `render.RenderView` + FOV-под рамку + чанковая отправка + локальный Material | `cl_capture.lua` |
| Фото-режим/свободная камера | CalcView + InputMouseApply + блок HUD/binds | `cl_photomode.lua` |
| Фото-архив полиции / доска расследования | `ent_photo_board` + `cl_board_ui` + `sv_board` | photocamera |
| Строительный тул (если понадобится) | модули списком, граф/солвер, лог-уровни | parametric_builder |

## 4. Предупреждения
- Код с `\r\n` и старыми стилями (`!=` в witcher). Часть файлов — повтор из первого DLC.
- `render.RenderView` доступен только на клиенте — сервер получает только JPEG.
- Чанковая отправка `ChunkSize` надо проверять под net-лимит сервера.
- Архив в git **не распаковывался** — только анализ.
