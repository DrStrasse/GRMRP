# ANALYSIS — Helix-фреймворк (helix-hl2rp / helix-plugins / helix-skeleton)

**Дата:** 2026-08-16 · **Источники:**
- https://github.com/NebulousCloud/helix-plugins (202 файла, 1.2 МБ)
- https://github.com/nebulouscloud/helix-hl2rp (114 файлов, 592 КБ)
- https://github.com/NebulousCloud/helix-skeleton (49 файлов, 190 КБ)

> Helix (`github.com/nebulouscloud/helix`) — модульный фреймворк для GMod RP:
> **схема (schema) + плагины (plugins)**. GRM — НЕ Helix, но эти репозитории —
> справочник по организации кода и готовым механикам (разрешения/пермиты,
> документы, крафт). Анализ под наши задачи.

---

## 1. helix-skeleton — минимальный шаблон схемы

```
gamemode/{init.lua (DeriveGamemode("helix")), cl_init.lua}
schema/
  sh_schema.lua / sv_schema.lua / cl_schema.lua   — разное по доменам
  sh_hooks.lua / sv_hooks.lua / cl_hooks.lua       — игровые хуки
  classes/    (FACTION-классы: рекрут, офицер…)
  factions/   (гражданин, полиция, ОТА…)
  items/      (предметы)
  attributes/ (атрибуты персонажа, напр. medical)
  meta/       (мета-методы character/player — включаются вручную)
  languages/  (локализация)
  libs/       (библиотеки — грузятся автоматически)
```

**Конвенция:** `ix.util.Include("cl_schema.lua")` сам делает `AddCSLuaFile`,
если у файла правильный префикс `cl_/sh_/sv_`. Хуки в `*_hooks.lua`, логика в
`libs/`. Идея «разнести по доменам + авто-подключение libs» — хороший ориентир
для укрупнения нашего монолитного `sh_grm_documents.lua` / `sh_grm_jobs.lua`.

---

## 2. helix-hl2rp — HL2 RP схема (механики-референсы)

### 2.1 Permits (разрешения) — АНАЛОГ наших лицензий
- У предмета поле `ITEM.permit = "consumables"` (база `items/base/sh_permits.lua`).
- Хук покупки (`schema/sh_hooks.lua`):
  `inventory:HasItem("permit_"..itemTable.permit)` → нет пермита = нельзя купить.
- Предметы-пермиты: `items/permits/sh_permit_consumables.lua` (`ITEM.permit`).
- Команды `PermitGive` / `PermitTake` (админ/схема).
→ **Паттерн:** «лицензия — это предмет в инвентаре, а покупка проверяет наличие
пермита». В GRM у нас лицензии — записи `DOC.Registry`, не предметы. Стоит
рассмотреть мост: физическая «лицензия на оружие/бизнес» как предмет + проверка
в момент покупки товара/открытия лавки через `DOC.HasValidWeaponLicense/
HasValidBusinessLicense` (наш следующий заказ — интеграция проверок).

### 2.2 Factions / Classes
- Фракция = файл `FACTION.name/description/color/pay/models/weapons` + хуки
  `OnCharacterCreated / GetDefaultName / OnTransferred / OnNameChanged`.
- Класс = `CLASS.name/faction/isDefault` + `CanSwitchTo` (по рангу имени).
→ Соответствует нашему `sh_factions.lua`; полезна идея **«класс привязан к рангу
в имени персонажа»** (`Schema:IsCombineRank(name, "RCT")`).

### 2.3 Writing (документы на бумаге)
`plugins/writing/`: предмет `sh_writing` (бумага) + `cl_paper.lua` (derma-просмотр)
+ `sh_plugin/sv_hooks`. Простейшая «бумага с текстом» — минимальный аналог нашего
документа; полезна как запасной вариант «лёгкого документа».

---

## 3. helix-plugins — каталог готовых плагинов (идеи для GRM)

~50 плагинов. Отбираю релевантное:

| Плагин | Что делает | Зачем GRM |
|---|---|---|
| `assistance_terminal` | терминал помощи | образец «терминал с экраном» |
| `crafting` + `ixcraft` | крафт: рецепты + станции + derma | аналог нашего завода/наркокрафта |
| `customitem` / `itemspawner` | кастомные предметы/выдача | админ-выдача предметов |
| `mynotes` | личные заметки персонажа | «заметки» в C-меню |
| `waypoints` | точки на карте | маршруты (наш такси/мусоровоз) |
| `whitelist` / `rankmanager` | вайтлист/ранги | доступы фракций |
| `protectionteams` | защитные команды | доверенные фракции |
| `weight` / `warmth` | вес/температура | наш `GRM.Encumbrance` |
| `bodygroupmanager` | бодигруппы | скин персонажа |
| `persistent_corpses` | трупы | RP-механика |
| `door_saver` / `doorextensions` | двери | наш модуль дверей |
| `class_whitelists` / `menu_perms` | доступы меню | права |
| `antiafk` / `tempflags` / `offlinebans` | серверные утилиты | админ-хелперы |

(полный список — в чате не нужен, каталог в репо `helix-plugins`).

---

## 4. Выводы для GRM

1. **Пермиты → лицензии.** Helix-паттерн «предмет-пермит гейтит покупку» ложится
   на наш следующий заказ: физическая лицензия + `DOC.HasValid*License` в момент
   покупки/ношения оружия и открытия бизнеса.
2. **Организация кода.** Разбиение «схема → классы/фракции/предметы/атрибуты/
   мета/языки» — ориентир, если будем дробить `sh_grm_documents.lua` (4к строк)
   и `sh_grm_jobs.lua` (1.7к строк) на модули.
3. **Документы/книги.** writing = минимум, HLX_Books = максимум (см.
   `ANALYSIS_HLX_BOOKS.md`). Оба — референсы для нашего «документного» задела.
4. **Крафт/терминал/заметки** — готовые идеи, если владелец попросит аналог.
