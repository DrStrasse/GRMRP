# GRM Doors v3 — перепись с нуля

**Дата:** 2026-08-13 · **Статус:** принято, код в `sh_grm_doors.lua` v3.0.0  
**Не трогает:** FFD, Q-меню. Матрица `/door_access` — отдельно, `sh_grm_doors_access.lua` v3.0.0 (CONCEPT_DOORS_ACCESS_V3.md).

## 1. Зачем

Старый модуль (v2.0.7) — палимпсест патчей. Дыры, которые нельзя лечить ещё одним if:

- `not ownable` считалось «публичный доступ» → ведомственная дверь без приватизации открывалась всем;
- незапертая чужая дверь блокировалась вторым `PlayerUse`-гардом;
- запись создавалась на каждый взгляд — база карты распухала дефолтами;
- ACL хранился картами (риск ключей) и уезжал клиенту целиком;
- админка R-меню путалась с `AM.CanManage`.

## 2. Слои допуска (единственный источник — `D.EvaluateAccess`)

| Слой | Кто | Что можно |
|---|---|---|
| 0 SuperAdmin | `IsSuperAdmin` | всё, включая назначение владельца карты |
| 1 Проход | любой | пройти через **незапертую** дверь |
| 2 Ключ | владелец / совладелец / фракция-владелец / категория-владелец / ACL / ордер+CanWarrant | пройти через **запертую**, закрыть/открыть замок |
| 3 Хозяйство | владелец-игрок или SuperAdmin | имя, совладельцы, ACL |
| 4 Покупка | никто не владеет **и** `ownable` | аренда 7 суток / навечно |
| 5 Карта | только SuperAdmin | фракция / категория / снять с продажи |
| 6 Сила | CanForceDoor или ордер | таран; не даёт ключ на E |

`ownable=false` значит «не продаётся», **не** «всем можно».  
`AM.CanManage` — только `/door_access`, не R-меню.

## 3. Владение

- `none` — ничья. Если ownable — купить/арендовать. Замок без хозяина ставит только SuperAdmin.
- `player` — `CharacterKey` (`SteamID64:charN`) + массив совладельцев.
- `faction` / `category` — назначает SuperAdmin. Члены ходят и запирают.
- Аренда истекает → `none`, замок снят, ACL/совладельцы чистятся.

## 4. Идентичность и персист

- Одна физическая дверь = один ID (MapCreationID + AABB-склейка дублей, **не** радиус).
- Соседние двери коридора не сливаются (пороги overlap).
- Пара — только `GetParent()`, без `FindInSphere`.
- На диск — **только изменённые** записи, массив, `version=3`, `jsonT(..., false, true)`.
- Битый файл → карантин, не затирать. Read-back после записи.

## 5. Сеть и UI

- Приём: дистанция, rate-limit, повторная проверка слоя.
- Клиенту обычного игрока не уходит ACL/списки фракций.
- Вкладка «Администрирование» — SuperAdmin.
- HUD один; при `ds_key_swep` не дублируется.
- `GRM.UI.Track` — одно окно. Вкладка и скролл переживают refresh.

## 6. Контракт наружу (не ломать)

`IsDoor`, `GetDoorID`, `GetRecord`, `GetEquivalentDoors`, `IsSamePhysicalDoor`, `RebuildDoorIdentityCache`, `GetPartnerDoor`, `IsDoorLocked`, `LockDoor`, `CanAccessDoor`, `CanAdminDoors`, `OpenDoorMenu`, `ClaimDoor`, `ReleaseDoor`, `HasWarrant`, `IssueWarrant`, `RevokeWarrant`, `IsFriendlyForAlarm`, `CreateCategory`/`Rename`/`Delete`/`CategorySetFaction`, `Save*`/`Load*`, `Data`, `Config`.
