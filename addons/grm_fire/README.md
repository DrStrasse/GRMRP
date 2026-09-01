# GRM Fire Addon — заготовка под отдельный аддон

Это **не** код GRM-сервера. Папка кладётся в `garrysmod/addons/grm_fire/` (или заливается как workshop-аддон).  
Серверный скрипт (права, рандом, перм, фракции, рукав↔гидрант) пишется **отдельно** в GRM и смотрит на флаги ниже.

Собранный архив: `dist/grm_fire_addon.zip`.

## Что внутри

| Слой | Откуда | Зачем |
|---|---|---|
| vFire (Vioxtar) | `vFire PACK.zip` | огонь, спред, урон, частицы |
| Рукав / огнетушитель | Milk + Rubat, модели в паке | SWEP, вода, тушение |
| GRM-сущности | наши заготовки | гидрант, точка очага, шкаф, насос |

vFire **не переписываем**. GRM потом зовёт его API.

## Как залить на сервер

1. Скачать `dist/grm_fire_addon.zip`.
2. Распаковать в `garrysmod/addons/grm_fire/` так, чтобы рядом лежали `addon.json`, `lua/`, `models/`, `materials/`, `particles/`, `sound/`.
3. Рестарт. В консоли: `[GRM Fire Addon] loaded` и `[vFire]`.
4. Официальный workshop vFire **не обязателен** — файлы уже в аддоне. Второй vFire в `addons/` не ставить (дубль энтити).

Проверка: `lua_run print(vFireInstalled, GRM_FireAddon)` → `true true`.

## Сущности аддона (Q → Entities → GRM Fire)

| Класс | Модель (CSS / фолбэк) | E |
|---|---|---|
| `grm_fire_hydrant` | `cs_assault/FireHydrant` / `valvewheel001` | открыть / закрыть |
| `grm_fire_spot` | невидима (оверлей только с тулом у суперадмина) | — |
| `grm_fire_cabinet` | `cs_office/fire_extinguisher` / `canister01a` | выдать огнетушитель, долить |
| `grm_fire_pump` | `props_lab/tpplugholder_single` (голограмма, без коллизии) | 4 рукава, бак, напор |
| `grm_fire_hose` | невидимый менеджер | один размотанный рукав |
| `grm_fire_hose_node` | якоря невидимы; тройник/ствол видны | укладка, стык, брошенный ствол |
| `grm_fire_ladder` | `de_train/ladderaluminium` | E взять / выдвинуть; W лезть |

Тул `GRM Пожарное железо` (категория **GRM**, не отдельная вкладка): гидрант / насос / шкаф / точка / лестница. ЛКМ по машине в режиме насоса или лестницы — навесить сбоку.

### Рукав (как должно выглядеть)

1. Машина приехала. Насос на борту, слотов **4**.
2. E на насос — взял рукав, в руках ствол (`weapon_grm_hose`, модель из пака).
3. Идёшь к огню — по земле красный кабель (`cable/redcable` + `constraint.Rope`), тянется от катушки к руке. Макс. **2200** юн. Дальше — натяг, не пускает. Узлы укладки невидимы.
4. **Смотка:** идёшь назад по рукаву — сегменты исчезают. E на свой гидрант/насос — свернуть целиком (и брошенный тоже).
5. Либо E на **гидрант** (сначала открыть) — рукав от колонки, 2 порта.
6. ПКМ — бросил ствол, линия лежит, напарник поднимает E.
7. R — узел-тройник. С него можно взять второй рукав или стыковать чужой.
8. E с рукавом на **другой** гидрант/насос — стык (питание машины от колонки).
9. Лить можно только при **напоре** (открытый гидрант в цепи или насос вкл и бак > 0). Тушит vFire.

Права фракций хуком `GRM_FireAddon_CanHose` наложит скрипт GRM. Сейчас — все.

### Пожарная машина (сервер GRM)

Какой транспорт считать пожарным (как инкассация):

1. spawn-name / класс в `/fire_trucks` у включённой фракции;
2. или на машине уже висит `grm_fire_pump`;
3. или суперадмин сел и написал `/firetruck`.

Как поставить:

- SuperAdmin: тул «GRM Пожарное железо» → Насос → ЛКМ по машине.
- Пожарный (галочка FightPro + роль): сел в ТС из списка → `/firetruck` — насос, 4 рукава, бак 2000.
- Снять с дежурства: `/firetruck_off` (сначала вернуть рукава).

У открытого гидранта бак доливается сам.

## Оружие (из пака)

Модели оружия (воркшоп): `c_firehose_grm`, `w_firehose_grm`, `c_fire_extinguisher_grm`, `w_fire_extinguisher_grm`.

- `weapon_extinguisher` — баллон, 500, долив в воде.
- `weapon_extinguisher_infinite` — админ.
- `weapon_firehose` — рукав-SWEP, 500, **не привязан к гидранту** (это сделает GRM).
- `weapon_firehose_infinite` — админ.

## Контракт для будущего скрипта GRM

Флаги: `vFireInstalled`, `vFireVersion`, `GRM_FireAddon`, `GRM.FireAddon.Version`.

Огонь:

- `CreateVFire(parent, pos, normal, feed, spreader)`
- `CreateVFireBall(life, feed, pos, vel, owner)`
- `ent:Ignite()` / `ent:Extinguish()` / `ent:IsOnFire()` — уже перехвачены vFire
- `fire:SoftExtinguish(amount)` / `fire:ChangeLife(n)` / `fire:GetFireState()` (1 Tiny … 7 Inferno)
- `vFireGetFires(ent)`, `vFireGetBurningEntities()`, `vFiresCount`
- хуки: `vFireCreated`, `vFireRemoved`, `vFireEntityStartedBurning`, `vFireEntityStoppedBurning`
- тушение SWEP: хук `ExtinguisherDoExtinguish(ent)` → `true` = своя логика

Наши энтити:

- `GRM.FireAddon.IsWaterSource(ent)` — гидрант открыт **или** насос включён и бак > 0
- `GRM.FireAddon.GiveHose(ply)` / `GiveExtinguisher(ply)`
- `GRM.FireAddon.Refill(ply, amount)` — долив `firehose_water` / `rb655_extinguisher`
- хуки: `GRM_FireAddon_HydrantUse`, `GRM_FireAddon_PumpUse`, `GRM_FireAddon_CabinetUse`, `GRM_FireAddon_SpotIgnite`

Серверный скрипт **не** класть в этот аддон: иначе двойная загрузка с `lua/` GRM.

## Чего в аддоне нет (намеренно)

Прав фракций, перма, рандома, плиты, принтера, Q-меню, дверей. Это GRM.
