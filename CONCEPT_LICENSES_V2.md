# GRM Лицензии v2.0 — водительские удостоверения, категории, сроки, баллы, экзамены

**Дата:** 2026-08-14 (обновлено 2026-08-15) · **Код 60** · **Статус:** водительские v2 сделаны (находка 128); **лицензии на оружие и бизнес сделаны (находка 134)**; остаток — госпошлина + экзамены  
**База:** `sh_grm_documents.lua` v1.4.1 + v2 фото, `grm_doc_computer`, `grm_comp_traffic`, `PlayerEnteredVehicle` хук, `sh_grm_electronics` OS 2.0

## 1. Что есть сейчас (v1.4.1)

- Гражданские ГАИ: категории A,B,C,D,E,СПЕЦ + префикс ВУ-, особые отметки, статус Действительно / Аннулировано / Лишён
- Военные ВАИ: A-В…СПЕЦ-В + 6 допусков (sirens/convoy/march/passengers/hazmat/armor) + ВУС + звание + часть + префикс ВАИ-
- Выдача через `grm_doc_computer` вкладка Автошкола/ВАИ + `grm_comp_traffic` экзаменационный ПК (но экзамена нет, только выдача)
- Проверка при посадке: `PlayerEnteredVehicle` → определяет reqCat по модели/классу ТС (мото→A, bus→D, btr/bmp→СПЕЦ-В, truck→C, иначе B) → `hasCiv` / `hasMil` по `categories[req]` → тост, чат предупреждение, но нет проверки срока/баллов
- Хранение: `DOC.Registry.licenses[charKey]` и `milLicenses[charKey]` = {fullName, birthDate, number, categories={A=true...}, categoriesStr, restrictions, issuedBy, issueDate, validUntil="10 лет"/"Бессрочно", status, steamID64, photoPath?, created, updated}
- Нет: срока, баллов, приостановки, госпошлины, экзамена

## 2. Цели v2.0

1. **Срок действия:** 10 лет гражданские, на срок службы военные, но с датой истечения timestamp. Видно в документе (лицевая + оборот), проверка при посадке.
2. **Балльная система:** 0-12 баллов, за нарушения +1..3, при 12 → приостановка 30 дней. Баллы хранятся в лицензии, видны в досье.
3. **Статусы:** Действителен | Истёк | Приостановлен до ДД.ММ.ГГГГ | Лишён | Аннулирован. Приостановка — временная, после срока автоматом возвращается в Действителен (при входе или при проверке).
4. **Госпошлина:** выдача/перевыпуск через `GRM.Services.Charge` (уже есть) — банк/счёт/наличные, 80% в бюджет фракции-автошколы, 20% в казну.
5. **Экзамены (минимально):**
   - Теория: в `grm_comp_traffic` и `grm_doc_computer` вкладка «Экзамен» — 10 вопросов из пула (json), проход 80%.
   - Практика: чекпоинты на карте (3-5 точек), время, без ДТП — команда `/drive_exam`.
   Без экзамена права не выдаются (кроме SuperAdmin bypass).
6. **Фото:** уже сделано в v2 — путь из фоторобота.

## 3. Формат данных v2

```lua
{
  fullName, birthDate, number, categories={B=true, C=true}, categoriesStr="B C",
  endorsements={sirens=true...}, -- только ВАИ
  rank, formation, vus, -- ВАИ
  issuedBy, issueDate="14.08.2026",
  validUntil="14.08.2036", -- строка для печати
  expiry=1783977600, -- timestamp, для проверки
  status="Действителен", -- Действителен | Истёк | Приостановлен до ... | Лишён ВАИ/права | Аннулирован
  suspendedUntil=0, -- timestamp если приостановлен
  points=0, -- 0..12
  maxPoints=12,
  restrictions="Очки, АКПП",
  photoPath="grm_computer/images/xxx.jpg",
  steamID64, created, updated
}
```

Миграция: старые записи без expiry → expiry = created + 10 лет, points=0, status как был.

## 4. Логика сервера

- `DOC.CanIssueLicenses(ply)` остаётся, но выдача теперь проверяет `examPassed[charKey]` (таблица в `data/grm_driving_exams.json`).
- `DOC.EnsureLicense` / `EnsureMilLicense` при загрузке чинит старые записи (добавляет expiry, points).
- `PlayerEnteredVehicle` хук расширяется:
  - найти лицензию, проверить categories, статус, expiry (если os.time() > expiry → expired, тост "Срок истёк"), suspendedUntil (если now < suspendedUntil → "Приостановлен до..."), points (если >= maxPoints → приостановка).
  - Логика: hasCiv / hasMil теперь + проверка срока + статуса.
- Новая команда `/license_points` — свои баллы, `/license_check <ник>` — чужие для полиции.
- Новая таблица `data/grm_driving_exams.json` = { [charKey] = { theory={passed=true, date, score}, practice={passed} } }

## 5. UI

- `grm_doc_computer` вкладка Автошкола: 
  - Поля: фото путь (уже есть), срок действия (дефолт +10 лет, редактируемо), баллы (только чтение при выдаче, 0), ограничения
  - Кнопка «Назначить экзамен» → открывает окно теории (вопросы) — пока заглушка, можно сразу отметить как сданный для SuperAdmin
- `grm_comp_traffic`:
  - Вкладка «Экзамены»: теория 10 вопросов, практика — маркеры на карте
  - Вкладка «Выдача»: как раньше + срок + баллы + фото
- Рендер ВУ: на лицевой добавить строку «4b. Действительно до: ДД.ММ.ГГГГ», на обороте «12. Баллы: 2/12», цвет статуса красный если не действителен

## 6. Сеть и безопасность

- `GRM_Doc_ComputerIssue` уже принимает произвольный table — новые поля expiry/points/photoPath пройдут автоматически, т.к. pack сохраняется целиком.
- Проверка экзамена на сервере: `examPassed[charKey]` должен быть установлен через `GRM_Doc_ComputerIssue` с `exam Theorie` action (отдельный net).
- Баллы начисляются через новый хук `GRM_LicenseAddPoints(ply, points, reason)` — вызывается из `/fine` с категорией ПДД или из ДТП.

## 7. Тесты

- `sim_licenses_v2.lua`: 
  - создание лицензии с expiry > now, points 0
  - проверка протухшей лицензии (expiry < now) → expired
  - добавление баллов до 12 → статус Приостановлен
  - проверка категории: B лицензия не проходит C ТС
  - фотоPath сохраняется и рендерится

## 8. Этапы

1. CONCEPT_LICENSES_V2.md (этот файл)
2. Миграция данных + поля expiry/points/status/suspendedUntil в sh_grm_documents.lua + PlayerEnteredVehicle проверка срока
3. UI doc_computer + comp_traffic добавление полей срока/баллов/фото
4. Экзамен теория (пул вопросов json) + практика чекпоинты (опционально, можно заглушкой)
5. Команды /license_points, начисление баллов через штрафы
6. Тесты + dist + README + ANALYSIS

Объём: ~300 строк сервер + ~200 клиент.

---

## 9. Лицензия на оружие (находка 134, сделано)

- **Категории** `DOC.WeaponCategories`: `smooth` (гладкоствольное), `rifled` (нарезное), `short` (короткоствольное), `traumatic` (ограниченного поражения), `hunting` (охотничье).
- **Шаблон** `weaponLicense`: «Отдел лицензионно-разрешительной работы», префикс `ЛО-`, цвет тёмно-зелёный, тиснение gold.
- **Данные** `DOC.Registry.weaponLicenses[charKey] = { number, fullName, birthDate, categories, categoriesStr, restrictions, issuedBy, issueDate, validUntil, expiry, status, suspendedUntil, steamID64 }`.
- **Доступ к выдаче** `access.weaponLicenses` (по умолчанию OrdnungPolizei + SuperAdmin) → `DOC.CanIssueWeaponLicenses`.
- **Проверка** `DOC.HasValidWeaponLicense(charKey, cat)` → bool, причина, запись (статус/срок/категория). Точка интеграции для продажи/ношения оружия.
- **Команды**: `/weaponlicense` `/оружие` / `/showweaponlicense` / `/check_weapon <ник>`.
- **Выдача**: `grm_doc_computer` вкладка «Оружие»; реестр и архив — аннулирование.

## 10. Лицензия на ведение бизнеса (находка 134, сделано)

- **Виды деятельности** `DOC.BusinessTypes`: `retail`, `logistics`, `factory`, `food`, `pharmacy`, `service`, `other`.
- **Шаблон** `businessLicense`: «Экономическое управление», префикс `БЛ-`, цвет тёмно-бирюзовый, тиснение silver.
- **Данные** `DOC.Registry.businessLicenses[charKey] = { number, businessName, fullName, businessType, businessTypeName, address, restrictions, issuedBy, issueDate, validUntil, expiry, status, steamID64 }`.
- **Доступ к выдаче** `access.businessLicenses` (по умолчанию Department of Labour and Social Protection + SuperAdmin) → `DOC.CanIssueBusinessLicenses`.
- **Проверка** `DOC.HasValidBusinessLicense(charKey, bizType)` → bool, причина, запись.
- **Команды**: `/businesslicense` `/бизнес` / `/showbusinesslicense` / `/check_business <ник>`.
- **Выдача**: `grm_doc_computer` вкладка «Бизнес»; реестр и архив — отзыв.

## 11. Госпошлины и теория-экзамены (сделано, находка 135)

- **Госпошлина** через `GRM.Services.Charge` (авто: банк → наличные) — сделано.
  Размеры в шаблонах `DOC.Templates.fees` (`license`/`weaponLicense`/`businessLicense`),
  по умолчанию 500/1500/3000, `milLicense` = 0. Распределение: 80% — в бюджет
  фракции-выдающей, 20% — в казну (`GRM.Economy.StateAdd`). Редактируется в
  `/doc_admin` (вкладки прав/оружия/бизнеса).
- **Теория-экзамен на компьютере** — сделано, **практики НЕТ** («это не вождение»).
  Банк вопросов `DOC.ExamBank` (ПДД / оружие / бизнес, по 5 вопросов, проходной 80%).
  Сдача через `grm_doc_computer` (кнопки «Экзамен») и `grm_comp_traffic` (ПДД).
  Результат хранится в `DOC.Registry.exams[charKey][licType]`. Выдача лицензии
  без сданного экзамена отклоняется (кроме SuperAdmin); пошлина списывается при
  выдаче (игрок должен быть онлайн).
- **Осталось (не сделано):**
  - Интеграция оружия: хук на покупку/выдачу оружия → `DOC.HasValidWeaponLicense`.
  - Интеграция бизнеса: проверка при открытии лавок/заводов → `DOC.HasValidBusinessLicense`.
