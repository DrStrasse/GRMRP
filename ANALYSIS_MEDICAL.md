# ANALYSIS — Медицинские карты и медицинские модули (аудит)

**Дата:** 2026-08-16 · **Статус:** аудит выполнен, расхождения ИСПРАВЛЕНЫ (находка 138) — единая медкарта
**База:** ветка `arena/01a00565-drstrasse`

---

## 1. Карта модулей

| Модуль | Файл | Роль | Версия |
|---|---|---|---|
| Медкарты (ядро) | `lua/autorun/sh_grm_medical.lua` | карты пациентов, доступ, выдача на руки, `/medcards` `/mycard` | **2.0.0** |
| Лечение/препараты | `lua/autorun/sh_grm_medical_full.lua` | статусы (bleed/pain/infection/poison/addiction), препараты, `/diagnose` | **2.1.0** |
| Компьютер госпиталя | `lua/entities/grm_comp_medical/` | редактор карт, реестр пациентов, выдача физ. карты | — |
| Медицинская лаборатория | `lua/entities/grm_med_lab/` | крафт препаратов (через `GRM.NarcCraft.OpenLab`) | — |
| Документ «медкарта» | `sh_grm_documents.lua` (docType `medcard`) | двухфазный рендер медкарты, `/medcard` `/showmedcard` | — |
| Обыск (досье) | `lua/weapons/weapon_grm_search/init.lua` | строка «Медкарта» в сводном досье | — |
| Образование (смежное) | `sh_grm_education.lua` + `sh_grm_diplomas.lua` + `grm_comp_education` | дипломы (не мед., но рядом по «соцблоку») | — |

---

## 2. Что делает каждый модуль

### 2.1 `sh_grm_medical.lua` (ядро медкарт, `GRM.Medical`)
- **Хранение:** `data/grm_medcards.json` — карты, ключ = `CharacterKey` (`SteamID64:charN`),
  чтение через `jsonT(..., ignoreConversions=true)` (урок находки 65). Карантин при битом файле,
  миграция старых ключей.
- **Поля карты:** `name, blood, allergies, chronic, fitnessCategory, entries[]`.
- **Записи (`EntryKinds`):** diagnosis / note / vitals / prescription / operation / issue
  (служебная «выдача карты»).
- **Доступ (`MD.CanTreat`):** суперадмин; иначе фракция из `MD.Cfg.factions`
  (enabled + роли + отделы) — настраивается в `/medcards → Доступ`.
- **API:** `MD.CardOf(key)` (авто-создание пустой карты), `MD.SaveCards`, `MD.CanTreat`,
  `MD.ViewIssued`, `MD.HandleChat`, `MD.BloodTypes`, `MD.FitnessCategories`, `MD.EntryKinds`.
- **Физическая карта (v1.1.0):** кнопка «Выдать карту на руки» → предмет `medcard` в инвентарь
  (модель clipboard, дропается/подбирается, `issued` в карте + запись kind=issue).
- **Команды:** `/medcards` `/mycard` (и консоль `grm_medcards`).

### 2.2 `sh_grm_medical_full.lua` (лечение, `GRM.MedicalFull`)
- **Статусы пациента:** bleed / pain / infection / poison / addiction (тикер Think,
  кровотечение наносит урон, инфекция растёт).
- **Препараты (крафт):** painkillers / antibiotics / adrenaline / detox / advanced kit —
  регистрируются в `GRM.Inventory` + use-обработчики.
- **`/diagnose`** — медик сканирует цель и видит статусы.
- **Зависимость:** `GRM.Narcotics.ClearAddiction` (детокс), `GRM.Inventory`.

### 2.3 `grm_comp_medical` (компьютер госпиталя)
- `CanManage` — медики (по имени фракции или `GRM.Medical.CanTreat`).
- Вкладки: **«Картотека пациентов»** (редактор: ФИО, группа крови, ВВК, аллергии, хронические,
  журнал приёмов, «Сохранить», «Выдать физ. карту»), **«Реестр пациентов госпиталя»** (поиск).
- Сохранение через авторитарный `MD.SaveCards`.

### 2.4 `grm_med_lab` (лаборатория)
- Энтити «Медицинская лаборатория» (`LabType="med"`), `Use → GRM.NarcCraft.OpenLab(ply, "med", self)` —
  крафт препаратов из `GRM.MedicalFull.Recipes`.

### 2.5 Документ «медкарта» + обыск
- `sh_grm_documents.lua`: `sendOwnDoc(ply, "medcard")` → `GRM.Medical.CardOf(cardKey)` →
  двухфазный рендер `openMedCardUI` (обложка Минздрава ⇄ разворот: группа, ВВК, аллергии,
  хронические, журнал). Команды `/medcard` `/showmedcard`.
- `weapon_grm_search`: строка «Медкарта: группа/категория» в досье.

---

## 3. Ключи и потоки данных

- **Единый ключ — CharacterKey** (`GRM.Identity.CharacterKey`), одинаково в `sh_grm_medical.lua`
  (`identityKey`), `grm_comp_medical` (передаёт `GRM.Identity.CharacterKey`) и `sh_grm_documents.lua`
  (`getCharKey`). **Совпадает — рассинхрона по ключу нет.**
- Поток: врач (`/medcards` или `grm_comp_medical`) → `MD.Cards[key]` → `data/grm_medcards.json`
  → документ/обыск читают ту же карту.

---

## 4. Найденные проблемы и расхождения — ВСЕ ИСПРАВЛЕНЫ (находка 138)

1. **Группа крови — два несовместимых справочника.** → Исправлено: `grm_comp_medical`
   берёт список из `GRM.Medical.BloodTypes`; `MD.NormalizeBlood` приводит любой старый
   формат (`I (0) Rh+`, `IV (AB) Rh-`, `0(I)…`) к каноническому `O(I) Rh+`/`AB(IV) Rh−`.
2. **Категория годности ВВК — расходящиеся формулировки.** → Исправлено: компьютер
   использует `GRM.Medical.FitnessCategories`; `MD.NormalizeFitness` приводит по букве А–Д.
3. **Обыск читает карту с легаси-фолбэком.** → Исправлено: `weapon_grm_search` и
   `sh_grm_ctx.lua` (C-меню) читают по CharacterKey через `MD.HasCard`.
4. **Пустая карта создаётся автоматически.** → Исправлено: `MD.HasCard(key)` без
   авто-создания; документ/обыск показывают «не заведена», а не создают пустышку.
5. **Двойной UI редактирования.** → Оба UI теперь поверх ОДНОЙ модели `MD` с ОДНИМИ
   справочниками (компьютер — основной редактор, `/medcards` — мобильный); функционал
   пересекается, но данные едины.
6. **Дубли записей (голый `sid64` + `sid64:charN`).** → Исправлено: компьютер больше не
   пишет дубль по голому `SteamID64`; при загрузке `MD.LoadCards` мигрирует голые `sid64`
   и SteamID в `sid64:charN`, схлопывая дубли в ОДНУ запись.

---

## 5. Что сделано (единая медкарта)

- `MD.NormalizeBlood` / `MD.NormalizeFitness` — общие канонизаторы (shared).
- Миграция при загрузке: ключи → CharacterKey (дедуп дублей), справочники → канонические,
  авто-сохранение при изменениях.
- `MD.HasCard(key)` — проверка без авто-создания.
- Компьютер госпиталя: справочники из ядра, без дублей, канонизация при сохранении.
- Обыск + C-меню: чтение по CharacterKey, «не заведена» ≠ «пустая карта».
- Документ «медкарта»: уведомление «карта не заведена» вместо пустышки.
- Стенд `sim_medical.lua` 23/23 (канонизация крови/ВВК, HasCard, миграция ключей, дедуп).
