--[[--------------------------------------------------------------------
    GRM Weapon Rack v1.0.0 — оружейная стойка с ячейками (ArcCW).

    ЗАЧЕМ. Оружейный шкаф логистики хранит оружие ПЛОСКИМ счётчиком:
    «arccw_ak74 — 3 шт». Из-за этого нельзя ни отличить один ствол от
    другого, ни запомнить вложения ArcCW, ни закрепить конкретное место
    за должностью. Ствол с оптикой и коллиматором, сданный командиром,
    возвращался безликой единицей в счётчике.

    ЧТО ЭТО. Отдельная сущность grm_weapon_rack рядом со шкафом:
      • СЕТКА ЯЧЕЕК. Один ствол = одна ячейка. В ячейке хранится
        конкретный экземпляр: класс, вложения ArcCW, прицел, износ,
        кто и когда положил.
      • ПАМЯТЬ МЕСТА. Ячейка помнит, что в ней лежало: сдал автомат —
        он вернулся на своё место, а не в общую кучу.
      • ЗАКРЕПЛЕНИЕ. Ячейку можно закрепить за должностью, званием,
        отделом или подотделом (оси v5). Пулемёт командира рядовой
        не возьмёт, даже если стойка общая.
      • 3D. Модель ствола показывается в меню (WorldModel из ArcCW).

    СВЯЗЬ СО ШКАФОМ. Стойка не заменяет grm_logistics_armory: шкаф
    остаётся складом патронов и материалов, стойка — оружейной. Обе
    живут в одной сети склада (Network ID), поэтому «Запросить со
    склада» работает и для стойки.

    ДАННЫЕ: data/grm_weapon_racks.json — ключ LogisticsID стойки.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.WeaponRack = GRM.WeaponRack or {}
local RK = GRM.WeaponRack

RK.Version = "1.0.0"
RK.File    = "grm_weapon_racks.json"
RK.Racks   = RK.Racks or {}      -- [rackID] = { cells = {...}, faction, network, ... }

RK.NET = {
    OPEN = "GRM_Rack_Open",
    ACT  = "GRM_Rack_Act",
}

--- Размеры сетки по умолчанию. Крупные ячейки: ствол виден целиком.
RK.DefaultCols = 5
RK.DefaultRows = 3
RK.MaxCols = 8
RK.MaxRows = 6
RK.UseDistance = 190

-----------------------------------------------------------------------
-- ОБЩАЯ ЧАСТЬ
-----------------------------------------------------------------------

local function trim(s, n) return string.sub(string.Trim(tostring(s or "")), 1, n or 96) end
local function low(s) return string.lower(trim(s, 128)) end

--- Человеческое имя оружия: из SWEP, иначе класс.
function RK.WeaponName(class)
    class = tostring(class or "")
    if class == "" then return "—" end
    local sw = weapons.Get(class)
    if istable(sw) then
        local n = sw.PrintName
        if isstring(n) and n ~= "" then return n end
    end
    return class
end

--- Мировая модель ствола для 3D-превью (ArcCW кладёт её в WorldModel).
function RK.WeaponModel(class)
    class = tostring(class or "")
    if class == "" then return "" end
    local sw = weapons.Get(class)
    if not istable(sw) then return "" end
    local mdl = sw.WorldModel
    if not isstring(mdl) or mdl == "" then mdl = sw.ViewModel end
    return isstring(mdl) and mdl or ""
end

--- Категория по классу: нужна для подписи и сортировки.
function RK.Category(class)
    local c = low(class)
    if c == "" then return "other" end
    local sw = weapons.Get(tostring(class))
    local cat = istable(sw) and tostring(sw.Category or "") or ""
    if cat ~= "" then return cat end
    return "other"
end

--- Нормализация одной ячейки. Пустая ячейка — законное состояние.
function RK.NormalizeCell(cell)
    if not istable(cell) then return { locked = false } end
    local out = {
        -- закрепление ячейки за областью структуры (оси v5)
        role = trim(cell.role, 96),
        position = trim(cell.position, 96),
        dept = trim(cell.dept, 64),
        label = trim(cell.label, 48),
        locked = cell.locked == true,
        --[[ ПАМЯТЬ МЕСТА переживает сохранение и рестарт: без переноса
             сюда ячейка забывала, что в ней лежало, и сданный ствол уходил
             в первую попавшуюся клетку. ]]
        lastClass = low(cell.lastClass),
    }
    if out.lastClass == "" then out.lastClass = nil end
    local class = low(cell.class)
    if class ~= "" then
        out.class = class
        out.name = trim(cell.name, 96)
        if out.name == "" then out.name = RK.WeaponName(class) end
        --[[ Вложения ArcCW: сохраняем как есть, чтобы ствол вернулся
             на полку ровно с тем обвесом, с которым его сдали. ]]
        out.attachments = istable(cell.attachments) and table.Copy(cell.attachments) or nil
        out.clip = math.max(0, math.floor(tonumber(cell.clip) or 0))
        out.storedBy = trim(cell.storedBy, 64)
        out.storedAt = math.max(0, math.floor(tonumber(cell.storedAt) or 0))
    end
    return out
end

function RK.NormalizeRack(rack)
    rack = istable(rack) and rack or {}
    rack.cols = math.Clamp(math.floor(tonumber(rack.cols) or RK.DefaultCols), 1, RK.MaxCols)
    rack.rows = math.Clamp(math.floor(tonumber(rack.rows) or RK.DefaultRows), 1, RK.MaxRows)
    rack.faction = trim(rack.faction, 96)
    rack.network = trim(rack.network, 64)
    rack.title = trim(rack.title, 64)
    rack.factionMode = rack.factionMode ~= false
    local cells = {}
    for i = 1, rack.cols * rack.rows do
        cells[i] = RK.NormalizeCell(rack.cells and rack.cells[i] or rack.cells and rack.cells[tostring(i)])
    end
    rack.cells = cells
    return rack
end

function RK.Get(rackID)
    rackID = tostring(rackID or "")
    if rackID == "" then return nil end
    RK.Racks[rackID] = RK.NormalizeRack(RK.Racks[rackID])
    return RK.Racks[rackID]
end

--- Занята ли ячейка стволом.
function RK.CellFilled(cell)
    return istable(cell) and isstring(cell.class) and cell.class ~= ""
end

--- Закреплена ли ячейка хоть за какой-то областью.
function RK.CellRestricted(cell)
    if not istable(cell) then return false end
    return (cell.role or "") ~= "" or (cell.position or "") ~= "" or (cell.dept or "") ~= ""
end

--[[ Может ли игрок взять из ячейки. Закрепление читается теми же осями,
     что модели и правила бодигрупп: должность → звание → отдел/подотдел.
     Пустое поле = «любой». Незакреплённая ячейка доступна всем своим. ]]
function RK.CanUseCell(ply, rack, cell)
    if not (IsValid(ply) and istable(rack) and istable(cell)) then return false, "Нет доступа" end
    if ply:IsSuperAdmin() then return true end

    -- Членство в организации стойки.
    local factionName = rack.faction or ""
    local member
    if factionName ~= "" then
        local f = (Factions and Factions[factionName]) or (FactionsData and FactionsData[factionName])
        if istable(f) and istable(f.Members) then
            member = GRM.Identity and GRM.Identity.FactionMember
                and GRM.Identity.FactionMember(f, ply) or nil
        end
        if rack.factionMode ~= false and not istable(member) then
            return false, "Стойка принадлежит другой организации"
        end
    end

    if not RK.CellRestricted(cell) then return true end
    if not istable(member) then return false, "Ячейка закреплена за подразделением" end

    if (cell.position or "") ~= "" then
        if tostring(member.Position or "") ~= cell.position then
            return false, "Ячейка закреплена за другой должностью"
        end
    end
    if (cell.role or "") ~= "" then
        if tostring(member.Role or "") ~= cell.role then
            return false, "Ячейка закреплена за другим званием"
        end
    end
    if (cell.dept or "") ~= "" then
        local dept = tostring(member.Department or "")
        local sub = tostring(member.Subdepartment or member.Subdept or "")
        if dept ~= cell.dept and sub ~= cell.dept then
            return false, "Ячейка закреплена за другим подразделением"
        end
    end
    return true
end

--- Подпись закрепления для интерфейса.
function RK.CellScopeText(rack, cell)
    if not RK.CellRestricted(cell) then return "" end
    local f = rack and rack.faction or ""
    local parts = {}
    if (cell.position or "") ~= "" then
        local name = cell.position
        if GRM.Positions and GRM.Positions.Get then
            local pos = GRM.Positions.Get(f, cell.position)
            if pos then name = pos.name end
        end
        parts[#parts + 1] = name
    end
    if (cell.role or "") ~= "" then
        local name = cell.role
        if GRM.Factions and GRM.Factions.RoleDisplayName then
            name = GRM.Factions.RoleDisplayName(f, cell.role)
        end
        parts[#parts + 1] = name
    end
    if (cell.dept or "") ~= "" then
        local name = cell.dept
        if GRM.Factions and GRM.Factions.DepartmentDisplayName then
            name = GRM.Factions.DepartmentDisplayName(f, cell.dept)
        end
        parts[#parts + 1] = name
    end
    return table.concat(parts, " · ")
end

--- Первая свободная ячейка, куда игрок вправе положить ствол.
function RK.FreeCellFor(ply, rack, class)
    if not istable(rack) then return nil end
    class = low(class)
    --[[ ПАМЯТЬ МЕСТА: сначала ищем ячейку, где такой ствол уже лежал.
         Сдал автомат — он вернулся на свою полку, а не в общую кучу. ]]
    for i, cell in ipairs(rack.cells) do
        if not RK.CellFilled(cell) and low(cell.lastClass or "") == class
            and RK.CanUseCell(ply, rack, cell) then
            return i
        end
    end
    for i, cell in ipairs(rack.cells) do
        if not RK.CellFilled(cell) and RK.CanUseCell(ply, rack, cell) then return i end
    end
    return nil
end

function RK.CountFilled(rack)
    local n = 0
    for _, cell in ipairs(istable(rack) and rack.cells or {}) do
        if RK.CellFilled(cell) then n = n + 1 end
    end
    return n
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(RK.NET.OPEN)
    util.AddNetworkString(RK.NET.ACT)

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    function RK.Load()
        RK.Racks = {}
        if not file.Exists(RK.File, "DATA") then return end
        local t = jsonT(file.Read(RK.File, "DATA") or "")
        if not istable(t) then return end
        for id, rack in pairs(t) do
            if isstring(id) and istable(rack) then RK.Racks[id] = RK.NormalizeRack(rack) end
        end
    end

    local saveQueued = false
    function RK.Save(reason)
        local function write()
            saveQueued = false
            local ok, txt = pcall(util.TableToJSON, RK.Racks or {}, true)
            if ok and txt then file.Write(RK.File, txt)
            else ErrorNoHalt("[GRM Rack] не удалось сохранить (" .. tostring(reason) .. ")\n") end
        end
        -- Пачка изменений схлопывается: правило порционности соблюдено.
        if GRM.Perf and GRM.Perf.Coalesce then GRM.Perf.Coalesce("grm_rack_save", 0.5, write)
        elseif not saveQueued then
            saveQueued = true
            timer.Simple(0.5, write)
        end
    end

    RK.Load()

    local function rackOf(ent)
        if not IsValid(ent) then return nil end
        local id = ent:GetRackID()
        if id == "" then
            id = "rack_" .. tostring(ent:EntIndex()) .. "_" .. tostring(math.floor(CurTime() * 100))
            ent:SetRackID(id)
        end
        local rack = RK.Get(id)
        -- Организация и сеть живут на сущности: их правит админ через меню.
        rack.faction = ent:GetFactionName()
        rack.network = ent:GetNetworkID()
        rack.factionMode = ent:GetFactionMode()
        return rack, id
    end
    RK.RackOf = rackOf

    local function nearby(ply, ent)
        return IsValid(ply) and IsValid(ent)
            and ply:GetPos():DistToSqr(ent:GetPos()) <= (RK.UseDistance ^ 2)
    end

    local function notify(ply, ok, msg)
        if not IsValid(ply) then return end
        if GRM.Notify then GRM.Notify(ply, msg, ok and 100 or 235, ok and 210 or 110, ok and 130 or 100)
        else ply:PrintMessage(HUD_PRINTTALK, "[Оружейная] " .. msg) end
    end

    --[[ Снимок ArcCW-вложений. У ArcCW обвес лежит в wep.Attachments с полем
         Installed. Копируем только имена — этого достаточно, чтобы собрать
         ствол обратно, и не тащим тяжёлые таблицы в файл. ]]
    local function grabAttachments(wep)
        if not IsValid(wep) then return nil end
        local src = wep.Attachments
        if not istable(src) then return nil end
        local out, any = {}, false
        for slot, data in pairs(src) do
            if istable(data) and isstring(data.Installed) and data.Installed ~= "" then
                out[tostring(slot)] = data.Installed
                any = true
            end
        end
        return any and out or nil
    end

    local function applyAttachments(wep, saved)
        if not (IsValid(wep) and istable(saved)) then return end
        if not istable(wep.Attachments) then return end
        -- ArcCW сам умеет ставить вложение в слот; без него молча пропускаем.
        if not isfunction(wep.Attach) then return end
        for slot, name in pairs(saved) do
            local idx = tonumber(slot) or slot
            pcall(function() wep:Attach(idx, name) end)
        end
    end

    --- Положить оружие игрока в ячейку.
    function RK.Deposit(ply, ent, cellIndex)
        local rack = rackOf(ent)
        if not rack then return false, "Стойка не найдена" end
        if not nearby(ply, ent) then return false, "Слишком далеко" end

        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then return false, "В руках нет оружия" end
        local class = low(wep:GetClass())
        if class == "" or class == "weapon_physgun" or class == "gmod_tool" or class == "gmod_camera" then
            return false, "Это оружие нельзя положить на стойку"
        end

        cellIndex = math.floor(tonumber(cellIndex) or 0)
        if cellIndex <= 0 or not rack.cells[cellIndex] then
            cellIndex = RK.FreeCellFor(ply, rack, class)
            if not cellIndex then return false, "Свободных ячеек нет" end
        end
        local cell = rack.cells[cellIndex]
        if RK.CellFilled(cell) then return false, "Ячейка занята" end
        local allowed, why = RK.CanUseCell(ply, rack, cell)
        if not allowed then return false, why end

        cell.class = class
        cell.name = RK.WeaponName(class)
        cell.attachments = grabAttachments(wep)
        cell.clip = math.max(0, wep:Clip1() or 0)
        cell.storedBy = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply))
            or ply:SteamID64() or ""
        cell.storedAt = os.time()
        cell.lastClass = class     -- память места

        ply:StripWeapon(wep:GetClass())
        RK.Save("deposit")
        hook.Run("GRM_RackDeposit", ply, ent, cellIndex, class)
        return true, "Убрано на стойку: " .. cell.name
    end

    --- Взять оружие из ячейки.
    function RK.Withdraw(ply, ent, cellIndex)
        local rack = rackOf(ent)
        if not rack then return false, "Стойка не найдена" end
        if not nearby(ply, ent) then return false, "Слишком далеко" end

        cellIndex = math.floor(tonumber(cellIndex) or 0)
        local cell = rack.cells[cellIndex]
        if not istable(cell) then return false, "Ячейка не найдена" end
        if not RK.CellFilled(cell) then return false, "Ячейка пуста" end
        local allowed, why = RK.CanUseCell(ply, rack, cell)
        if not allowed then return false, why end
        if ply:HasWeapon(cell.class) then return false, "Такое оружие уже в руках" end

        local wep = ply:Give(cell.class)
        if not IsValid(wep) then return false, "Не удалось выдать оружие" end
        applyAttachments(wep, cell.attachments)
        if (cell.clip or 0) > 0 and wep.SetClip1 then wep:SetClip1(cell.clip) end

        local name = cell.name or cell.class
        -- Ячейка помнит, что здесь лежало: ствол вернётся на своё место.
        local lastClass = cell.class
        rack.cells[cellIndex] = RK.NormalizeCell({
            role = cell.role, position = cell.position, dept = cell.dept,
            label = cell.label, locked = cell.locked,
        })
        rack.cells[cellIndex].lastClass = lastClass

        RK.Save("withdraw")
        hook.Run("GRM_RackWithdraw", ply, ent, cellIndex, lastClass)
        return true, "Выдано: " .. name
    end

    --- Настройка ячейки админом или лидером: закрепление и подпись.
    function RK.ConfigureCell(ply, ent, cellIndex, data)
        local rack = rackOf(ent)
        if not rack then return false, "Стойка не найдена" end
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return false, "Только суперадмин" end
        cellIndex = math.floor(tonumber(cellIndex) or 0)
        local cell = rack.cells[cellIndex]
        if not istable(cell) then return false, "Ячейка не найдена" end
        data = istable(data) and data or {}
        cell.role = trim(data.role, 96)
        cell.position = trim(data.position, 96)
        cell.dept = trim(data.dept, 64)
        cell.label = trim(data.label, 48)
        RK.Save("configure")
        return true, "Ячейка настроена"
    end

    --- Размер сетки.
    function RK.Resize(ply, ent, cols, rows)
        local rack, id = rackOf(ent)
        if not rack then return false, "Стойка не найдена" end
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return false, "Только суперадмин" end
        --[[ Проверяем ДО изменения размеров. Раньше cols/rows писались сразу,
             и при отказе стойка оставалась с новым размером: ближайшая
             нормализация обрезала ячейки вместе с лежащим в них оружием. ]]
        local newCols = math.Clamp(math.floor(tonumber(cols) or rack.cols), 1, RK.MaxCols)
        local newRows = math.Clamp(math.floor(tonumber(rows) or rack.rows), 1, RK.MaxRows)
        local total = newCols * newRows
        for i = total + 1, #rack.cells do
            if RK.CellFilled(rack.cells[i]) then
                return false, "Сначала освободите ячейку " .. i .. ": в ней лежит оружие"
            end
        end
        rack.cols, rack.rows = newCols, newRows
        RK.Racks[id] = RK.NormalizeRack(rack)
        RK.Save("resize")
        return true, "Размер стойки изменён"
    end

    --- Снимок для клиента.
    function RK.Snapshot(ply, ent)
        local rack = rackOf(ent)
        if not rack then return nil end
        local isAdmin = IsValid(ply) and ply:IsSuperAdmin()
        local cells = {}
        for i, cell in ipairs(rack.cells) do
            local allowed = RK.CanUseCell(ply, rack, cell)
            cells[i] = {
                index = i,
                class = cell.class,
                name = cell.name,
                model = cell.class and RK.WeaponModel(cell.class) or "",
                scope = RK.CellScopeText(rack, cell),
                label = cell.label,
                role = cell.role, position = cell.position, dept = cell.dept,
                allowed = allowed == true,
                attachments = cell.attachments and table.Count(cell.attachments) or 0,
                lastName = (not RK.CellFilled(cell)) and cell.lastClass
                    and RK.WeaponName(cell.lastClass) or nil,
            }
        end

        -- Структура организации для закрепления ячеек (оси v5).
        local scope = { roles = {}, depts = {}, positions = {} }
        if isAdmin then
            local f = Factions and Factions[rack.faction]
            if istable(f) then
                for _, roleKey in ipairs(f.Roles or {}) do
                    scope.roles[#scope.roles + 1] = { key = roleKey,
                        display = (GRM.Factions and GRM.Factions.RoleDisplayName
                            and GRM.Factions.RoleDisplayName(f, roleKey)) or roleKey }
                end
                for _, deptKey in ipairs(f.Departments or {}) do
                    scope.depts[#scope.depts + 1] = { key = deptKey,
                        display = (GRM.Factions and GRM.Factions.DepartmentDisplayName
                            and GRM.Factions.DepartmentDisplayName(f, deptKey)) or deptKey }
                end
                for subKey, sub in pairs(istable(f.Subdepartments) and f.Subdepartments or {}) do
                    if istable(sub) then
                        scope.depts[#scope.depts + 1] = { key = subKey,
                            display = "подотдел: " .. tostring(sub.name or subKey) }
                    end
                end
                if GRM.Positions and GRM.Positions.List then
                    for _, pos in ipairs(GRM.Positions.List(f)) do
                        scope.positions[#scope.positions + 1] = { key = pos.id,
                            display = pos.name .. " (" .. GRM.Positions.NodeDisplayName(f, pos.node) .. ")" }
                    end
                end
            end
        end

        local activeClass = ""
        -- Снимок могут собирать и для не-игрока (перм-восстановление, тесты),
        -- поэтому наличие метода проверяем, а не предполагаем.
        if IsValid(ply) and isfunction(ply.GetActiveWeapon) then
            local wep = ply:GetActiveWeapon()
            if IsValid(wep) then activeClass = wep:GetClass() end
        end

        return {
            cols = rack.cols, rows = rack.rows,
            title = rack.title ~= "" and rack.title or "Оружейная стойка",
            faction = rack.faction, network = rack.network,
            factionMode = rack.factionMode,
            cells = cells, admin = isAdmin == true,
            scope = scope,
            activeWeapon = activeClass,
            activeName = activeClass ~= "" and RK.WeaponName(activeClass) or "",
            filled = RK.CountFilled(rack),
        }
    end

    function RK.Open(ply, ent)
        if not (IsValid(ply) and IsValid(ent)) then return end
        if not nearby(ply, ent) then return end
        local snapshot = RK.Snapshot(ply, ent)
        if not snapshot then return end
        net.Start(RK.NET.OPEN)
            net.WriteEntity(ent)
            net.WriteTable(snapshot)
        net.Send(ply)
    end

    net.Receive(RK.NET.ACT, function(_, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard and not GRM.Net.Guard(ply, "rack.act", { rate = 0.15, burst = 6 }, {}) then return end
        local ent = net.ReadEntity()
        local action = net.ReadString()
        local index = net.ReadUInt(8)
        local data = net.ReadTable() or {}
        if not IsValid(ent) or ent:GetClass() ~= "grm_weapon_rack" then return end

        local ok, msg = false, "Неизвестное действие"
        if action == "take" then ok, msg = RK.Withdraw(ply, ent, index)
        elseif action == "put" then ok, msg = RK.Deposit(ply, ent, index)
        elseif action == "configure" then ok, msg = RK.ConfigureCell(ply, ent, index, data)
        elseif action == "resize" then ok, msg = RK.Resize(ply, ent, data.cols, data.rows)
        elseif action == "settings" then
            if ply:IsSuperAdmin() then
                ent:SetFactionName(trim(data.faction, 96))
                ent:SetNetworkID(trim(data.network, 64))
                ent:SetFactionMode(data.factionMode ~= false)
                local rack = rackOf(ent)
                rack.title = trim(data.title, 64)
                RK.Save("settings")
                ok, msg = true, "Настройки стойки сохранены"
            else
                ok, msg = false, "Только суперадмин"
            end
        elseif action == "refresh" then ok, msg = true, nil
        end

        if msg then notify(ply, ok, msg) end
        RK.Open(ply, ent)   -- окно обновляется свежим снимком
    end)

    --- Диагностика и поиск стоек на карте: grm_racks
    concommand.Add("grm_racks", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local function say(t)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, t) else print(t) end
        end
        local list = ents.FindByClass("grm_weapon_rack")
        say("[Оружейные стойки] версия " .. RK.Version .. ", на карте: " .. #list)
        for _, ent in ipairs(list) do
            if IsValid(ent) then
                local rack = rackOf(ent)
                local pos = ent:GetPos()
                say(("  %s | %s | занято %d из %d | %.0f %.0f %.0f"):format(
                    rack.title ~= "" and rack.title or "без названия",
                    rack.faction ~= "" and rack.faction or "без организации",
                    RK.CountFilled(rack), rack.cols * rack.rows,
                    pos.x, pos.y, pos.z))
            end
        end
        if #list == 0 then
            say("  Стоек нет. Поставьте «GRM: Оружейная стойка» из категории GRM Faction Logistics.")
        end
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("weapon_rack", {
            label = "Оружейные стойки",
            version = RK.Version,
            Status = function() return "стоек: " .. tostring(table.Count(RK.Racks or {})) end,
            Depends = { "factions" },
        })
    end
end
