# GRM Faction Core v4

## Цель

Развивать фракции без дальнейшего разрастания монолитов `sh_factions.lua` и
`sh_faction_fixes.lua`, сохраняя `Factions`, CharacterKey, существующие JSON,
net-протоколы и публичные API.

## Стабильные ключи отделов

`f.Departments` по-прежнему содержит системные ключи. Публичные названия лежат
отдельно:

```lua
f.Departments = { "patrol", "detectives" }
f.DepartmentDisplayNames = {
    patrol = "Патрульная служба",
    detectives = "Уголовный розыск"
}
```

Изменение публичного названия **не изменяет**:

- `member.Department`;
- `DepartmentModels`;
- `DepartmentWeapons`;
- department spawn points;
- access matrices;
- документы, транспорт и имущество.

Удаление отдела остаётся отдельной деструктивной операцией. В UI системный ключ
показывается подсказкой, а редактируется только публичное имя.

## Domain events и revisions

`GRM.FactionCore.Touch` увеличивает общую и фракционную ревизию и публикует
`GRM_FactionCoreChanged`. Legacy-мутации ядра транслируются событиями:

- `GRM_FactionMemberJoined`;
- `GRM_FactionMemberRemoved`;
- `GRM_FactionMemberRoleChanged`;
- `GRM_FactionMemberDepartmentChanged`;
- `GRM_FactionLeaderChanged`;
- `GRM_FactionDutyChanged`;
- `GRM_FactionDepartmentDisplayChanged`.

Старые функции остаются источником истины; Core v4 пока выступает безопасным
слоем нормализации и событий, а не вторым backend.

## Кадровое дело

Кадровые данные хранятся внутри записи участника в `factions.json`:

```lua
member.Personnel = {
    characterKey = "SteamID64:char1",
    joinedAt = 0,
    hiredBy = "CharacterKey",
    source = "invite",
    status = "active", -- active / probation / dismissed
    probationUntil = 0,
    notes = {},
    history = {}
}
```

История ограничена 200 событиями. При увольнении запись переносится в
`f.PersonnelArchive`, поэтому увольнение не уничтожает кадровую историю.

Автоматически фиксируются:

- вступление и пригласивший;
- назначение/смена должности;
- перевод между системными отделами;
- начало и завершение службы;
- испытательный срок;
- увольнение;
- ручные заметки, благодарности и взыскания.

## UI

В админское и лидерское меню через существующий
`GRM_FactionsAdmin_BuildTabs` добавляется вкладка **«Кадровые дела»**:

- список сотрудников;
- публичные названия фракции и отдела;
- текущая должность, служба и статус;
- дата приёма;
- хронология кадровых событий;
- заметка;
- благодарность;
- взыскание;
- испытательный срок.

Чтение разрешено SuperAdmin, лидеру/уполномоченному сотруднику и самому
сотруднику для собственного дела. Изменение — SuperAdmin, лидер либо capability
`faction.personnel.manage`. Net receivers защищены `GRM.Net.Guard`, действия
пишутся в `GRM.Audit`.

## Следующие этапы

1. Вынести member/structure/invite/comms UI из `sh_factions.lua` в отдельные
   клиентские модули, сохранив старые глобальные точки входа.
2. Добавить заявки на вступление и собеседования.
3. Добавить штатное расписание и квоты должностей.
4. Добавить кадровые приказы с физическими документами.
5. Перевести ранги на стабильный key + DisplayName по той же модели отделов.
6. Добавить архивный просмотр уволенных сотрудников и восстановление.
