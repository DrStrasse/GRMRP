# vFire PACK — разбор (2026-08-13)

Источник: `vFire PACK.zip` (коммит владельца `23dd53c`). Код GRM не менялся.  
Аддон-заготовка: `addons/grm_fire/` + архив `dist/grm_fire_addon.zip`.

## Состав пака

159 файлов: lua 14, mdl рукава/огнетушителя (c_ / w_), частицы 35 pcf, декали, 2 wav.

Автор огня — Vioxtar. Рукав — Milk (на базе огнетушителя Rubat). `addon.json` в зипе **пустой**.

## Как устроен огонь

Не сетка. Энтити `vfire` липнет к миру / пропу / кости персонажа.

- `life` → стадия 1 Tiny … 7 Inferno (`vFireLifeToState`)
- `feed` — топливо, растёт из материала родителя (`vFireTakeFuel`: дерево много, металл мало)
- рядом сливается (`mergeDist² = 500`)
- кластер `vfire_cluster` на одного родителя + тип материала
- шар `vfire_ball` летит и липнет
- ванильный `entityflame` глушится (подмена класса + хук)

Публичный старт:

```
CreateVFire(parent, pos, normal, newFeed, spreader) → fire|nil
CreateVFireBall(life, feedCarry, pos, vel, owner) → ball
ent:Ignite() / Extinguish() / IsOnFire()   -- перехвачены
fire:SoftExtinguish(amount)
fire:ChangeLife(n)
fire:GetFireState()
```

Хуки: `vFireCreated`, `vFireRemoved`, `vFireEntityStartedBurning`, `vFireEntityStoppedBurning`.  
Флаг: `vFireInstalled = true`.

Тушение SWEP идёт через хук `ExtinguisherDoExtinguish(ent)`. vFire уже вешает на него `SoftExtinguish(2)`.

## Рукав в паке — не размотка

`weapon_firehose` = большой огнетушитель:

- модель `models/weapons/c_firehose.mdl` / `w_firehose.mdl` (есть в паке)
- патроны `firehose_water`, 500, долив если `WaterLevel() > 1`
- сфера 100 у прицела, 50% шанс тика погасить
- **нет** гидранта, длины рукава, укладки, машины

Привязка к гидранту/насосу — задача **серверного скрипта GRM**, не пака.

## Чего паку не хватает для нашего ТЗ

Гидрант, точка очага, шкаф, насос, персист, рандом, фракции, перм. Это либо заготовки в аддоне (сделаны), либо скрипт GRM (потом).

`resource.AddWorkshop(1525218777)` и `104607228` в собранном аддоне **сняты**: клиент берёт файлы из папки аддона, не с мастерской.

## Схема на двоих

```
addons/grm_fire/          ← этот аддон (контент + сущности)
   vFire + SWEP + модели
   grm_fire_hydrant / _spot / _cabinet / _pump
   GRM_FireAddon = true

lua/ GRM (ещё не пишем)
   права, /fire_access, рандом по spot, перм, плита
   рукав: патроны только у открытого сокета, лимит длины
```
