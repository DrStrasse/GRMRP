--[[--------------------------------------------------------------------
    GRM Garage v1.0.0 — гаражи: зоны, места стоянки, выдача и уборка

    Заказ владельца (19.08): «модуль гаража и стыковка с дилером. Гараж
    личный уже есть, но не хватает инструмента создания зоны гаражей и
    точек спавна транспорта. Нужна полноценная механика: точки спавна,
    направление купленного транспорта в личный гараж, вызов меню гаража,
    спавн из гаража, тулы и энтити».

    МОДЕЛЬ ДАННЫХ (data/grm_garage/<карта>.json)
      гараж = { id, name, kind, baseKind, faction, owner, zone{min,max},
                slots[{id,name,pos,ang,lift}], terminals[{id,pos,ang}],
                doors[doorID], propertyID, linkedDealers[dealerID],
                fee, created }
      kind: public   — общий городской гараж (любой игрок),
            faction  — ведомственный (члены организации),
            private  — личный (владелец по CharacterKey).

    ИЕРАРХИЯ И ПОРЯДОК
      • ядро (этот файл) не знает про UI и тулы, только данные + правила;
      • спавн/уборка машины делегируются дилеру (VD.IssueRecord /
        VD.StoreRecord) — одна реализация на сборку;
      • привязка покупки к гаражу идёт ХУКОМ GRM_VehicleDealerSpawned,
        то есть дилер про гаражи ничего не знает;
      • загрузка карты — через GRM.Boot.OnMapStart (tier normal), тяжёлые
        обходы — через GRM.Perf (Spread/Throttle);
      • все net-приёмы под GRM.Net.Guard.

    КОМАНДЫ
      /garage, /гараж           — меню гаража (в зоне или у стойки)
      grm_garage_menu           — то же из консоли
      grm_garages               — список гаражей карты (суперадмин)
      grm_garage_reload         — перечитать файл карты (суперадмин)
      Конвар grm_garage_strict  — 1: личный транспорт выдаётся ТОЛЬКО в гараже
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Garage = GRM.Garage or {}
local G = GRM.Garage
G.Version = "1.0.0"

G.Kinds = {
    public  = "Городской (для всех)",
    faction = "Ведомственный",
    private = "Личный",
}

G.MinZone      = 200      -- минимальная сторона зоны
G.SlotRadius   = 150      -- радиус ПОИСКА кандидатов рядом с местом
--[[ Габарит самого места стоянки: по нему решается, занято оно или нет.
     Проверять расстояние до ORIGIN машины нельзя — у седана от бампера до
     центра около 110 юнитов, у грузовика больше: машина стоит поперёк
     соседнего места, а место считается свободным (заказ владельца 22.08 —
     «считывание мест в гараже верное?»). ]]
G.SlotBox      = { x = 190, y = 110, z = 100 }
G.UseDistance  = 220      -- дальность стойки гаража
G.MaxSlots     = 24
G.MaxGarages   = 64

G.Garages = G.Garages or {}   -- id -> запись

local NET_OPEN   = "GRM_Garage_Open"
local NET_ACT    = "GRM_Garage_Act"
local NET_RESULT = "GRM_Garage_Result"
local NET_ADMIN  = "GRM_Garage_Admin"

-----------------------------------------------------------------------
-- ОБЩИЕ ХЕЛПЕРЫ (обе стороны)
-----------------------------------------------------------------------
local function vd(v) return { x = v.x, y = v.y, z = v.z } end
local function ad(a) return { p = a.p, y = a.y, r = a.r } end
local function vec(t) return Vector(tonumber(t and t.x) or 0, tonumber(t and t.y) or 0, tonumber(t and t.z) or 0) end
local function ang(t) return Angle(tonumber(t and t.p) or 0, tonumber(t and t.y) or 0, tonumber(t and t.r) or 0) end
local function trim(v, n) return string.sub(string.Trim(tostring(v or "")), 1, n or 64) end

G.Vec, G.Ang, G.VecTbl, G.AngTbl = vec, ang, vd, ad

function G.KindName(kind) return G.Kinds[tostring(kind or "")] or G.Kinds.public end

-- Точка внутри зоны гаража? Зона всегда AABB — дёшево и предсказуемо.
function G.PosInZone(garage, pos)
    if not (istable(garage) and istable(garage.zone) and pos) then return false end
    local mn, mx = vec(garage.zone.min), vec(garage.zone.max)
    return pos.x >= mn.x and pos.x <= mx.x
       and pos.y >= mn.y and pos.y <= mx.y
       and pos.z >= mn.z - 32 and pos.z <= mx.z + 96
end

function G.ZoneCenter(garage)
    if not (istable(garage) and istable(garage.zone)) then return Vector(0, 0, 0) end
    return (vec(garage.zone.min) + vec(garage.zone.max)) * 0.5
end

function G.List()
    local out = {}
    for _, rec in pairs(G.Garages) do out[#out + 1] = rec end
    table.sort(out, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
    return out
end

function G.Get(id) return G.Garages[tostring(id or "")] end

-- Гараж, в зоне которого стоит точка (первый подходящий по площади — меньший).
function G.FindByPos(pos)
    local best, bestArea = nil, math.huge
    for _, rec in pairs(G.Garages) do
        if G.PosInZone(rec, pos) then
            local mn, mx = vec(rec.zone.min), vec(rec.zone.max)
            local area = math.abs((mx.x - mn.x) * (mx.y - mn.y))
            if area < bestArea then best, bestArea = rec, area end
        end
    end
    return best
end

function G.Nearest(pos, maxDist)
    local best, bestD = nil, (tonumber(maxDist) or 4096) ^ 2
    for _, rec in pairs(G.Garages) do
        local d = G.ZoneCenter(rec):DistToSqr(pos)
        if d < bestD then best, bestD = rec, d end
    end
    return best
end

-- Кто может пользоваться гаражом.
function G.CanUse(ply, garage)
    if not (IsValid(ply) and istable(garage)) then return false, "Гараж не найден" end
    local kind = tostring(garage.kind or "public")
    if ply:IsSuperAdmin() then return true end
    if kind == "public" then return true end
    if kind == "faction" then
        local own = ply:GetNWString("GRM_Faction", "")
        if own ~= "" and own == tostring(garage.faction or "") then return true end
        return false, "Гараж принадлежит другой организации"
    end
    if kind == "private" then
        local key = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply))
            or (ply.SteamID64 and ply:SteamID64() .. ":char1") or ""
        if key ~= "" and key == tostring(garage.owner or "") then return true end
        return false, "Это чужой личный гараж"
    end
    return true
end

-- Гараж, которым игрок пользуется прямо сейчас (зона или стойка рядом).
function G.GarageAt(ply)
    if not IsValid(ply) then return nil end
    local pos = ply:GetPos()
    local inZone = G.FindByPos(pos)
    if inZone then return inZone, "zone" end
    for _, rec in pairs(G.Garages) do
        for _, term in ipairs(rec.terminals or {}) do
            if vec(term.pos):DistToSqr(pos) <= G.UseDistance * G.UseDistance then return rec, "terminal" end
        end
    end
    return nil
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    for _, n in ipairs({ NET_OPEN, NET_ACT, NET_RESULT, NET_ADMIN }) do util.AddNetworkString(n) end

    local STRICT = CreateConVar("grm_garage_strict", "0", bit.bor(FCVAR_ARCHIVE),
        "1 — личный транспорт выдаётся только в его гараже, у дилера выдача закрыта")

    local DIR = "grm_garage"
    local function ensureDir() if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end end
    local function mapFile() ensureDir() return DIR .. "/" .. string.lower(game.GetMap() or "unknown") .. ".json" end
    local function jsonT(s) local ok, t = pcall(util.JSONToTable, s or "", false, true) return ok and istable(t) and t or nil end

    local function notify(ply, msg, ok)
        if not IsValid(ply) then return end
        if GRM.Notify then GRM.Notify(ply, msg, ok == false and 255 or 110, ok == false and 130 or 220, ok == false and 100 or 145)
        else ply:ChatPrint("[Гараж] " .. tostring(msg)) end
    end
    local function audit(action, actor, target, details)
        if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("garage", action, actor, target or {}, details or {}) end
    end
    local function charKey(ply)
        return (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply))
            or (IsValid(ply) and ply:SteamID64() .. ":char1") or ""
    end
    local function makeID(prefix)
        return prefix .. "_" .. util.CRC(table.concat({ game.GetMap(), SysTime(), math.random() }, ":"))
    end

    ------------------------------------------------------------------
    -- ХРАНЕНИЕ
    ------------------------------------------------------------------
    local function normalizeSlot(raw, index)
        if not istable(raw) then return nil end
        return {
            id   = trim(raw.id ~= nil and raw.id or ("slot_" .. index), 48),
            name = trim(raw.name ~= "" and raw.name or ("Место " .. index), 48),
            pos  = vd(vec(raw.pos)),
            ang  = ad(ang(raw.ang)),
            lift = math.Clamp(math.floor(tonumber(raw.lift) or 10), 0, 100),
        }
    end

    local function normalize(raw)
        if not (istable(raw) and raw.id and istable(raw.zone)) then return nil end
        local rec = {
            id      = trim(raw.id, 48),
            name    = trim(raw.name ~= "" and raw.name or "Гараж", 64),
            kind    = G.Kinds[tostring(raw.kind or "")] and tostring(raw.kind) or "public",
            -- baseKind — тип, заданный админом. Когда гараж уходит вместе с
            -- домом, kind временно становится private/faction, а при
            -- освобождении дома возвращается к baseKind.
            baseKind = G.Kinds[tostring(raw.baseKind or "")] and tostring(raw.baseKind) or nil,
            propertyID = trim(raw.propertyID, 48),
            faction = trim(raw.faction, 64),
            owner   = trim(raw.owner, 64),
            fee     = math.max(0, math.floor(tonumber(raw.fee) or 0)),
            created = tonumber(raw.created) or os.time(),
            zone    = { min = vd(vec(raw.zone.min)), max = vd(vec(raw.zone.max)) },
            slots   = {},
            terminals = {},
            linkedDealers = {},
            doors   = {},
        }
        rec.baseKind = rec.baseKind or rec.kind
        for _, doorID in ipairs(raw.doors or {}) do
            local d = trim(doorID, 64)
            if d ~= "" then rec.doors[#rec.doors + 1] = d end
        end
        for _, dealerID in ipairs(raw.linkedDealers or {}) do
            local d = trim(dealerID, 48)
            if d ~= "" then rec.linkedDealers[#rec.linkedDealers + 1] = d end
        end
        for i, slot in ipairs(raw.slots or {}) do
            local s = normalizeSlot(slot, i)
            if s and #rec.slots < G.MaxSlots then rec.slots[#rec.slots + 1] = s end
        end
        for i, term in ipairs(raw.terminals or {}) do
            if istable(term) then
                rec.terminals[#rec.terminals + 1] = { id = trim(term.id ~= nil and term.id or ("term_" .. i), 48), pos = vd(vec(term.pos)), ang = ad(ang(term.ang)) }
            end
        end
        return rec
    end

    function G.Save(why)
        local rows = {}
        for _, rec in pairs(G.Garages) do rows[#rows + 1] = rec end
        local ok, raw = pcall(util.TableToJSON, { version = 1, map = game.GetMap(), garages = rows }, true)
        if not ok or not isstring(raw) then print("[GRM Garage] SAVE FAIL: сериализация") return false end
        file.Write(mapFile(), raw)
        local back = file.Read(mapFile(), "DATA")
        if not back or back == "" then print("[GRM Garage] SAVE read-back ПУСТ — проверьте права data/") return false end
        print(("[GRM Garage] SAVE ok: %d гаражей [%s]"):format(#rows, tostring(why or "-")))
        return true
    end

    function G.Load()
        G.Garages = {}
        local raw = file.Read(mapFile(), "DATA") or ""
        local data = jsonT(raw)
        if raw ~= "" and not data then
            file.Write(mapFile() .. ".broken", raw)
            print("[GRM Garage] файл гаражей повреждён — отложен в .broken")
        end
        for _, row in ipairs((data and data.garages) or {}) do
            local rec = normalize(row)
            if rec then G.Garages[rec.id] = rec end
        end
        print(("[GRM Garage] загружено гаражей: %d"):format(table.Count(G.Garages)))
        G.ReindexDoors()
        G.SpawnTerminals()
        return true
    end

    ------------------------------------------------------------------
    -- РЕДАКТИРОВАНИЕ (тул и админ-панель)
    ------------------------------------------------------------------
    function G.Create(actor, first, second, opts)
        opts = istable(opts) and opts or {}
        if table.Count(G.Garages) >= G.MaxGarages then return false, "Достигнут лимит гаражей на карте" end
        local mn = Vector(math.min(first.x, second.x), math.min(first.y, second.y), math.min(first.z, second.z))
        local mx = Vector(math.max(first.x, second.x), math.max(first.y, second.y), math.max(first.z, second.z))
        if (mx.x - mn.x) < G.MinZone or (mx.y - mn.y) < G.MinZone then
            return false, ("Зона слишком мала: минимум %d×%d юнитов"):format(G.MinZone, G.MinZone)
        end
        if (mx.z - mn.z) < 100 then mx.z = mn.z + 220 end
        local rec = normalize({
            id = makeID("garage"), name = opts.name, kind = opts.kind, faction = opts.faction,
            owner = opts.owner, fee = opts.fee, zone = { min = vd(mn), max = vd(mx) },
        })
        if not rec then return false, "Не удалось создать запись" end
        G.Garages[rec.id] = rec
        G.Save("создан гараж " .. rec.id)
        audit("garage.create", actor, { id = rec.id }, { name = rec.name, kind = rec.kind })
        return true, rec
    end

    function G.Remove(id, actor)
        local rec = G.Get(id)
        if not rec then return false, "Гараж не найден" end
        for _, ent in ipairs(ents.FindByClass("grm_garage_terminal")) do
            if IsValid(ent) and ent:GetGarageID() == rec.id then ent:Remove() end
        end
        G.ApplyDoorState(rec, false)
        G.Garages[rec.id] = nil
        G.ReindexDoors()
        G.Save("удалён гараж " .. rec.id)
        audit("garage.remove", actor, { id = rec.id }, { name = rec.name })
        return true, "Гараж «" .. rec.name .. "» удалён"
    end

    function G.Update(id, fields, actor)
        local rec = G.Get(id)
        if not rec then return false, "Гараж не найден" end
        fields = istable(fields) and fields or {}
        if fields.name    ~= nil then rec.name = trim(fields.name ~= "" and fields.name or rec.name, 64) end
        if fields.kind    ~= nil and G.Kinds[tostring(fields.kind)] then rec.kind = tostring(fields.kind) rec.baseKind = rec.kind end
        if fields.faction ~= nil then rec.faction = trim(fields.faction, 64) end
        if fields.owner   ~= nil then rec.owner = trim(fields.owner, 64) end
        if fields.fee     ~= nil then rec.fee = math.max(0, math.floor(tonumber(fields.fee) or 0)) end
        G.ApplyDoorState(rec)
        G.Save("правка гаража " .. rec.id)
        audit("garage.update", actor, { id = rec.id }, fields)
        return true, "Настройки гаража сохранены"
    end

    function G.AddSlot(id, pos, angle, lift, name)
        local rec = G.Get(id)
        if not rec then return false, "Гараж не найден" end
        if #rec.slots >= G.MaxSlots then return false, "Достигнут лимит мест в гараже" end
        if not G.PosInZone(rec, pos) then return false, "Место должно быть внутри зоны гаража" end
        local slot = normalizeSlot({
            id = makeID("slot"), name = name, pos = vd(pos), ang = ad(angle or Angle(0, 0, 0)), lift = lift,
        }, #rec.slots + 1)
        rec.slots[#rec.slots + 1] = slot
        G.Save("место в гараже " .. rec.id)
        return true, slot
    end

    function G.RemoveNearestSlot(pos, maxDist)
        local bestRec, bestIndex, bestD = nil, nil, (tonumber(maxDist) or 200) ^ 2
        for _, rec in pairs(G.Garages) do
            for i, slot in ipairs(rec.slots or {}) do
                local d = vec(slot.pos):DistToSqr(pos)
                if d < bestD then bestRec, bestIndex, bestD = rec, i, d end
            end
        end
        if not bestIndex then return false, "Рядом нет места стоянки" end
        local removed = table.remove(bestRec.slots, bestIndex)
        G.Save("удалено место гаража " .. bestRec.id)
        return true, removed
    end

    -- Привязка дилера к гаражу: купленное у него уезжает именно сюда.
    function G.LinkDealer(id, dealerID)
        local rec = G.Get(id)
        if not rec then return false, "Гараж не найден" end
        dealerID = trim(dealerID, 48)
        if dealerID == "" then return false, "Дилер без идентификатора" end
        rec.linkedDealers = rec.linkedDealers or {}
        for i, linked in ipairs(rec.linkedDealers) do
            if linked == dealerID then
                table.remove(rec.linkedDealers, i)
                G.Save("отвязан дилер от " .. rec.id)
                return true, "Дилер отвязан от гаража «" .. rec.name .. "»"
            end
        end
        rec.linkedDealers[#rec.linkedDealers + 1] = dealerID
        G.Save("привязан дилер к " .. rec.id)
        return true, "Дилер привязан к гаражу «" .. rec.name .. "»"
    end

    function G.AddTerminal(id, pos, angle)
        local rec = G.Get(id)
        if not rec then return false, "Гараж не найден" end
        local term = { id = makeID("term"), pos = vd(pos), ang = ad(angle or Angle(0, 0, 0)) }
        rec.terminals[#rec.terminals + 1] = term
        G.Save("стойка гаража " .. rec.id)
        G.SpawnTerminals()
        return true, term
    end

    --- Удалить конкретную стойку (когда игрок целится прямо в неё).
    function G.RemoveTerminalByID(terminalID)
        terminalID = trim(terminalID, 48)
        if terminalID == "" then return false, "Стойка не опознана" end
        for _, rec in pairs(G.Garages) do
            for i, term in ipairs(rec.terminals or {}) do
                if term.id == terminalID then
                    table.remove(rec.terminals, i)
                    for _, ent in ipairs(ents.FindByClass("grm_garage_terminal")) do
                        if IsValid(ent) and ent:GetTerminalID() == terminalID then ent:Remove() end
                    end
                    G.Save("удалена стойка гаража " .. rec.id)
                    return true, ("Стойка удалена (у гаража «%s» осталось %d)"):format(rec.name, #rec.terminals)
                end
            end
        end
        return false, "Стойка не найдена в записях гаражей"
    end

    function G.RemoveNearestTerminal(pos, maxDist)
        local bestRec, bestIndex, bestD = nil, nil, (tonumber(maxDist) or 200) ^ 2
        for _, rec in pairs(G.Garages) do
            for i, term in ipairs(rec.terminals or {}) do
                local d = vec(term.pos):DistToSqr(pos)
                if d < bestD then bestRec, bestIndex, bestD = rec, i, d end
            end
        end
        if not bestIndex then return false, "Рядом нет стойки гаража" end
        local removed = table.remove(bestRec.terminals, bestIndex)
        for _, ent in ipairs(ents.FindByClass("grm_garage_terminal")) do
            if IsValid(ent) and ent:GetTerminalID() == removed.id then ent:Remove() end
        end
        G.Save("удалена стойка гаража " .. bestRec.id)
        return true, removed
    end

    -- Стойки живут в записи гаража, а не в перм-хранилище: одна точка правды.
    function G.SpawnTerminals()
        local alive = {}
        for _, ent in ipairs(ents.FindByClass("grm_garage_terminal")) do
            if IsValid(ent) then alive[ent:GetTerminalID()] = ent end
        end
        local made = 0
        for _, rec in pairs(G.Garages) do
            for _, term in ipairs(rec.terminals or {}) do
                local ent = alive[term.id]
                if not IsValid(ent) then
                    ent = ents.Create("grm_garage_terminal")
                    if IsValid(ent) then
                        ent:SetPos(vec(term.pos))
                        ent:SetAngles(ang(term.ang))
                        ent:Spawn()
                        ent:Activate()
                        made = made + 1
                    end
                end
                if IsValid(ent) then
                    ent:SetTerminalID(term.id)
                    ent:SetGarageID(rec.id)
                    ent:SetGarageName(rec.name)
                    alive[term.id] = ent
                end
            end
        end
        return made
    end

    ------------------------------------------------------------------
    -- МЕСТА СТОЯНКИ
    ------------------------------------------------------------------
    --[[ Пересекаются ли два AABB (таблицы {x,y,z}). Чистая функция —
         гоняется стендом без игры. ]]
    function G.BoxesOverlap(aMin, aMax, bMin, bMax, margin)
        if not (istable(aMin) and istable(aMax) and istable(bMin) and istable(bMax)) then return false end
        margin = tonumber(margin) or 0
        for _, axis in ipairs({ "x", "y", "z" }) do
            local a1 = (tonumber(aMin[axis]) or 0) - margin
            local a2 = (tonumber(aMax[axis]) or 0) + margin
            local b1, b2 = tonumber(bMin[axis]) or 0, tonumber(bMax[axis]) or 0
            if a1 > b2 or b1 > a2 then return false end
        end
        return true
    end

    --- Габарит места стоянки в мировых координатах.
    function G.SlotBounds(slot)
        local pos = vec(slot and slot.pos)
        local box = G.SlotBox
        local half = math.max(box.x, box.y) * 0.5     -- место может стоять под любым углом
        return { x = pos.x - half, y = pos.y - half, z = pos.z - 8 },
               { x = pos.x + half, y = pos.y + half, z = pos.z + box.z }
    end

    local function isVehicleLike(ent)
        if not IsValid(ent) then return false end
        return ent:IsVehicle() or ent.GRMGarageID ~= nil or ent.LVS ~= nil or ent.IsSimfphysCar == true
    end

    --[[ Кто занимает место. Ищем кандидатов широким радиусом, а решение
         принимаем по ПЕРЕСЕЧЕНИЮ ГАБАРИТОВ: origin машины может быть далеко
         от места, при этом кузов стоит ровно на нём. ]]
    local function slotBlocker(slot)
        local smin, smax = G.SlotBounds(slot)
        local pos = vec(slot.pos)
        for _, ent in ipairs(ents.FindInSphere(pos, G.SlotRadius + 320)) do
            if isVehicleLike(ent) then
                if isfunction(ent.WorldSpaceAABB) then
                    local mn, mx = ent:WorldSpaceAABB()
                    if G.BoxesOverlap(smin, smax,
                        { x = mn.x, y = mn.y, z = mn.z }, { x = mx.x, y = mx.y, z = mx.z }) then
                        return ent
                    end
                elseif ent:GetPos():Distance(pos) <= G.SlotRadius then
                    -- запасной путь для сущностей без габаритов
                    return ent
                end
            end
        end
        return nil
    end

    function G.SlotState(garage)
        local rows = {}
        for i, slot in ipairs((garage and garage.slots) or {}) do
            local blocker = slotBlocker(slot)
            rows[#rows + 1] = {
                id = slot.id, name = slot.name, index = i,
                free = not IsValid(blocker),
                occupiedBy = IsValid(blocker) and (blocker.GRMGarageOwner and blocker.GRMGarageOwner:Nick() or blocker:GetClass()) or "",
                pos = slot.pos,
            }
        end
        return rows
    end

    --[[ СВОБОДНОЕ МЕСТО.

         Первая версия отбраковывала место одним жёстким хуллом размером с
         машину. В тесном боксе (низкий потолок, близкие стены, колонна)
         хулл цеплялся всегда — все места считались занятыми, и система
         молча уезжала к дилеру. Владелец это и увидел: «хоть ты точки ставь
         и места — ничего».

         Теперь проверка ступенчатая: полный габарит → уменьшенный →
         «есть земля и рядом нет машины». Причина отказа по каждому месту
         сохраняется и видна в диагностике (grm_garage_slots). ]]
    local HULLS = {
        { mins = Vector(-60, -105, -40), maxs = Vector(60, 105, 56), label = "полный габарит" },
        { mins = Vector(-45, -85, -30),  maxs = Vector(45, 85, 44),  label = "уменьшенный габарит" },
    }

    local function slotPlace(slot, ply, why)
        local pos = vec(slot.pos)
        local ground = util.TraceLine({
            start = pos + Vector(0, 0, 160), endpos = pos - Vector(0, 0, 260),
            filter = ply, mask = MASK_SOLID,
        })
        local base = (ground.Hit and not ground.StartSolid) and ground.HitPos or pos

        for _, hull in ipairs(HULLS) do
            local blocked = util.TraceHull({
                start = base + Vector(0, 0, 50), endpos = base + Vector(0, 0, 50),
                mins = hull.mins, maxs = hull.maxs, filter = ply, mask = MASK_SOLID,
            })
            if not (blocked.Hit or blocked.StartSolid) then
                return { pos = base, ang = ang(slot.ang), lift = tonumber(slot.lift) or 10, slot = slot }
            end
        end

        -- последний шанс: земля есть, машин рядом нет — ставим (тесный бокс)
        if not IsValid(slotBlocker(slot)) then
            if why then why[slot.id] = "тесно, но машина влезет" end
            return { pos = base, ang = ang(slot.ang), lift = tonumber(slot.lift) or 10, slot = slot, tight = true }
        end
        if why then why[slot.id] = "занято машиной" end
        return nil
    end

    function G.FreeSlot(garage, ply)
        if not istable(garage) then return nil, "Гараж не найден" end
        if #(garage.slots or {}) == 0 then return nil, "В гараже не размечено ни одного места выдачи" end
        local why = {}
        -- сначала честно свободные, потом «тесные»
        local tight = nil
        for _, slot in ipairs(garage.slots) do
            if not IsValid(slotBlocker(slot)) then
                local place = slotPlace(slot, ply, why)
                if place and not place.tight then return place end
                if place and not tight then tight = place end
            else
                why[slot.id] = "занято машиной"
            end
        end
        if tight then return tight end
        return nil, "Все места в гараже заняты"
    end

    --[[ Диагностика мест: почему конкретное место считается занятым.
         Нужна была буквально: «места не срабатывают» проверяется за секунду. ]]
    function G.SlotDiagnose(garage, ply)
        local rows = {}
        for i, slot in ipairs((garage and garage.slots) or {}) do
            local blocker = slotBlocker(slot)
            local place = not IsValid(blocker) and slotPlace(slot, ply, {}) or nil
            rows[#rows + 1] = {
                index = i, id = slot.id, name = slot.name,
                free = place ~= nil,
                tight = place and place.tight or false,
                blocker = IsValid(blocker) and blocker:GetClass() or "",
                pos = slot.pos,
            }
        end
        return rows
    end

    ------------------------------------------------------------------
    -- ВОРОТА ГАРАЖА (двери) И СВЯЗЬ С НЕДВИЖИМОСТЬЮ
    ------------------------------------------------------------------
    G.ByDoor = G.ByDoor or {}

    function G.ReindexDoors()
        G.ByDoor = {}
        for _, rec in pairs(G.Garages) do
            for _, doorID in ipairs(rec.doors or {}) do G.ByDoor[tostring(doorID)] = rec end
        end
        return G.ByDoor
    end

    function G.GarageByDoorID(doorID) return G.ByDoor[tostring(doorID or "")] end

    local function doorEntities(rec)
        local out = {}
        if not (GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.GetDoorID) then return out end
        local wanted = {}
        for _, id in ipairs(rec.doors or {}) do wanted[tostring(id)] = true end
        if not next(wanted) then return out end
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and GRM.Doors.IsDoor(ent) then
                local id = GRM.Doors.GetDoorID(ent)
                if id and wanted[tostring(id)] then out[#out + 1] = ent end
            end
        end
        return out
    end
    G.DoorEntities = doorEntities

    -- Ворота закрыты, пока гараж не общий: у общего запирать нечего.
    function G.ApplyDoorState(rec, forceLocked)
        if not (istable(rec) and GRM.Doors and GRM.Doors.LockDoor) then return 0 end
        local locked = forceLocked
        if locked == nil then locked = rec.kind ~= "public" end
        local n = 0
        for _, ent in ipairs(doorEntities(rec)) do
            GRM.Doors.LockDoor(ent, locked == true)
            n = n + 1
        end
        return n
    end

    function G.LinkDoor(id, doorID)
        local rec = G.Get(id)
        if not rec then return false, "Гараж не найден" end
        doorID = trim(doorID, 64)
        if doorID == "" then return false, "У двери нет идентификатора (сначала занесите её в /doors_admin)" end
        local other = G.ByDoor[doorID]
        if other and other.id ~= rec.id then
            return false, ("Эта дверь уже привязана к гаражу «%s»"):format(other.name)
        end
        rec.doors = rec.doors or {}
        for i, existing in ipairs(rec.doors) do
            if existing == doorID then
                table.remove(rec.doors, i)
                G.ReindexDoors()
                G.Save("отвязана дверь от " .. rec.id)
                return true, ("Дверь отвязана от гаража «%s» (осталось %d)"):format(rec.name, #rec.doors)
            end
        end
        rec.doors[#rec.doors + 1] = doorID
        G.ReindexDoors()
        G.ApplyDoorState(rec)
        G.Save("привязана дверь к " .. rec.id)
        return true, ("Дверь привязана к гаражу «%s» (всего %d)"):format(rec.name, #rec.doors)
    end

    -- Гараж как часть дома: покупает игрок недвижимость — получает и гараж.
    function G.LinkProperty(id, propertyID)
        local rec = G.Get(id)
        if not rec then return false, "Гараж не найден" end
        propertyID = trim(propertyID, 48)
        if propertyID == "" then
            rec.propertyID = ""
            rec.kind = rec.baseKind or "public"
            rec.owner = ""
            G.Save("гараж отвязан от недвижимости")
            G.ApplyDoorState(rec)
            return true, ("Гараж «%s» отвязан от недвижимости"):format(rec.name)
        end
        if rec.propertyID == propertyID then
            rec.propertyID = ""
            rec.kind = rec.baseKind or "public"
            rec.owner = ""
            G.Save("гараж отвязан от недвижимости")
            G.ApplyDoorState(rec)
            return true, ("Гараж «%s» отвязан от объекта недвижимости"):format(rec.name)
        end
        rec.propertyID = propertyID
        G.Save("гараж привязан к недвижимости")
        G.SyncWithProperty(propertyID)
        return true, ("Гараж «%s» продаётся вместе с объектом %s"):format(rec.name, propertyID)
    end

    --[[ Синхронизация с недвижимостью: владелец дома становится владельцем
         гаража (личный или ведомственный), при освобождении дома гараж
         возвращается к типу, который задал админ. ]]
    function G.SyncWithProperty(propertyID)
        local P = GRM.Property
        if not (P and P.Records) then return 0 end
        propertyID = tostring(propertyID or "")
        local prop = P.Records[propertyID]
        local touched = 0
        for _, rec in pairs(G.Garages) do
            if rec.propertyID == propertyID then
                rec.baseKind = rec.baseKind or rec.kind
                if not prop or prop.ownerType == "none" or prop.ownerType == nil then
                    rec.kind = rec.baseKind
                    rec.owner = ""
                elseif prop.ownerType == "character" then
                    rec.kind = "private"
                    rec.owner = tostring(prop.ownerKey or "")
                    rec.name = rec.name
                elseif prop.ownerType == "faction" then
                    rec.kind = "faction"
                    rec.faction = tostring(prop.ownerKey or "")
                    rec.owner = ""
                end
                G.ApplyDoorState(rec)
                touched = touched + 1
            end
        end
        if touched > 0 then G.Save("синхронизация с недвижимостью " .. propertyID) end
        return touched
    end

    -- Владелец дома получает и ворота гаража. Двери, которые уже относятся к
    -- объекту недвижимости, оставляем её правилам — там своя логика ордеров.
    hook.Add("GRM_DoorAccessOverride", "GRM_Garage_Doors", function(ply, ent)
        if not (IsValid(ply) and IsValid(ent)) then return end
        if not (GRM.Doors and GRM.Doors.GetDoorID) then return end
        local id = GRM.Doors.GetDoorID(ent)
        if not id then return end
        local rec = G.ByDoor[tostring(id)]
        if not rec then return end
        if GRM.Property and GRM.Property.GetByDoorID and GRM.Property.GetByDoorID(id) then return end
        local can, why = G.CanUse(ply, rec)
        if can then return true, "garage_key" end
        return false, why or ("Ворота гаража «%s» закрыты."):format(rec.name)
    end)

    hook.Add("GRM_PropertyOwnerChanged", "GRM_Garage_FollowProperty", function(record)
        if not istable(record) then return end
        G.SyncWithProperty(record.id)
    end)

    ------------------------------------------------------------------
    -- СВЯЗЬ С ДИЛЕРОМ
    ------------------------------------------------------------------
    --[[ Список гаражей, куда игрок реально может отправить покупку.
         Отдаётся дилеру, чтобы игрок ВЫБИРАЛ гараж сам (заказ владельца
         19.08), а не получал «куда система решила». ]]
    function G.ChoicesFor(ply, dealer)
        local out = {}
        if not IsValid(ply) then return out end
        local home = G.HomeGarageFor(ply, dealer)
        for _, rec in pairs(G.Garages) do
            if G.CanUse(ply, rec) then
                local slots = #(rec.slots or {})
                local free = 0
                for _, s in ipairs(G.SlotState(rec)) do if s.free then free = free + 1 end end
                out[#out + 1] = {
                    id = rec.id, name = rec.name, kind = rec.kind, kindName = G.KindName(rec.kind),
                    slots = slots, free = free, fee = rec.fee or 0,
                    suggested = (home and home.id == rec.id) or false,
                    distance = math.floor(ply:GetPos():Distance(G.ZoneCenter(rec))),
                }
            end
        end
        table.sort(out, function(a, b)
            if a.suggested ~= b.suggested then return a.suggested end
            return a.distance < b.distance
        end)
        return out
    end

    --- Проверка выбранного игроком гаража: существует, доступен, есть места.
    function G.ValidateChoice(ply, garageID)
        local rec = G.Get(garageID)
        if not rec then return nil, "Гараж не найден" end
        local can, why = G.CanUse(ply, rec)
        if not can then return nil, why or "Нет доступа к гаражу" end
        if #(rec.slots or {}) == 0 then return nil, "В этом гараже нет мест стоянки" end
        return rec
    end

    -- Куда приписать покупку: гараж, привязанный к дилеру → личный гараж
    -- игрока → ближайший доступный.
    function G.HomeGarageFor(ply, dealer)
        if not IsValid(ply) then return nil end
        local key = charKey(ply)
        if IsValid(dealer) then
            local dealerID = dealer.GetDealerID and dealer:GetDealerID() or ""
            for _, rec in pairs(G.Garages) do
                for _, linked in ipairs(rec.linkedDealers or {}) do
                    if tostring(linked) == dealerID and G.CanUse(ply, rec) then return rec end
                end
            end
        end
        for _, rec in pairs(G.Garages) do
            if rec.kind == "private" and rec.owner == key then return rec end
        end
        local best, bestD = nil, math.huge
        local from = IsValid(dealer) and dealer:GetPos() or ply:GetPos()
        for _, rec in pairs(G.Garages) do
            if G.CanUse(ply, rec) and #(rec.slots or {}) > 0 then
                local d = G.ZoneCenter(rec):DistToSqr(from)
                if d < bestD then best, bestD = rec, d end
            end
        end
        return best
    end

    -- Строгий режим: у дилера личный транспорт с домашним гаражом не выдаётся.
    function G.DealerIssueBlocked(ply, record)
        if not (STRICT and STRICT:GetBool()) then return false end
        if not istable(record) or record.service then return false end
        local rec = G.Get(record.garageID)
        if not rec then return false end
        return true, ("Транспорт стоит в гараже «%s» — заберите его там."):format(rec.name)
    end

    -- Покупка в дилере приписывает машину к гаражу (дилер про гаражи не знает).
    hook.Add("GRM_VehicleDealerSpawned", "GRM_Garage_AssignHome", function(ent, ply, class, record, dealer)
        if not (IsValid(ply) and istable(record)) then return end
        if record.service then return end

        -- Игрок выбрал гараж прямо в меню дилера — уважаем выбор, если он
        -- ещё имеет смысл (гараж есть, доступен, размечен).
        local home, why
        local wanted = tostring(record.requestedGarage or "")
        record.requestedGarage = nil
        if wanted ~= "" then
            home, why = G.ValidateChoice(ply, wanted)
            if not home then notify(ply, ("Выбранный гараж не подошёл: %s"):format(tostring(why)), false) end
        end
        home = home or G.HomeGarageFor(ply, dealer)
        if not home then return end

        record.garageID = home.id
        if GRM.VehicleDealer and GRM.VehicleDealer.SaveGarages then GRM.VehicleDealer.SaveGarages() end
        notify(ply, ("Транспорт закреплён за гаражом «%s»."):format(home.name), true)
    end)

    ------------------------------------------------------------------
    -- ДЕЙСТВИЯ ИГРОКА
    ------------------------------------------------------------------
    local function records(ply)
        local VD = GRM.VehicleDealer
        if not (VD and VD.GarageRecords) then return {} end
        return VD.GarageRecords(ply) or {}
    end

    local function vehicleRows(ply, garage)
        local VD = GRM.VehicleDealer
        local out = {}
        for id, rec in pairs(records(ply)) do
            if istable(rec) and not rec.service then
                local ent = VD and VD.Active and VD.Active[id]
                local homeID = tostring(rec.garageID or "")
                local home = G.Get(homeID)
                out[#out + 1] = {
                    id = id, name = rec.name or rec.class, class = rec.class, model = rec.model,
                    price = tonumber(rec.price) or 0,
                    onMap = IsValid(ent),
                    distance = IsValid(ent) and math.floor(ply:GetPos():Distance(ent:GetPos())) or 0,
                    homeID = homeID, homeName = home and home.name or "",
                    here = homeID ~= "" and garage and homeID == garage.id or false,
                }
            end
        end
        table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
        return out
    end

    --[[ ТЕХНИКА ОРГАНИЗАЦИИ В ЭТОМ ГАРАЖЕ (модуль GRM.Fleet).
         Гараж и автопарк — один интерфейс: сотрудник видит и свои личные
         машины, и служебные, приписанные к этому гаражу, и берёт их по
         размеченным местам стоянки. ]]
    --[[ ЕДИНЫЙ СЛОЙ ТРАНСПОРТА.
         Что показывать и что с чем делать, решает GRM.Vehicles — один
         диспетчер на личные машины (записи гаража) и служебную технику
         (автопарк организации). Здесь только раскладываем его строки по
         двум таблицам, потому что окно рисует их разными блоками. ]]
    local function splitRows(ply, garage)
        local V = GRM.Vehicles
        local personal, fleet = {}, {}
        if V and V.Rows then
            for _, row in ipairs(V.Rows(ply, garage)) do
                if row.source == "fleet" then fleet[#fleet + 1] = row else personal[#personal + 1] = row end
            end
            return personal, fleet
        end
        return vehicleRows(ply, garage), {}
    end
    G.FleetRows = function(ply, garage) return select(2, splitRows(ply, garage)) end

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("garage", {
            label = "Гаражи и места выдачи", version = G.Version or "1.0.0",
            Depends = { "vehicles" },
            Status = function()
                local n = 0
                for _ in pairs(G.Garages or {}) do n = n + 1 end
                return ("гаражей на карте: %d"):format(n)
            end,
        })
    end

    function G.Push(ply, garage)
        if not IsValid(ply) then return end
        garage = garage or G.GarageAt(ply)
        if not garage then return end
        local slots = G.SlotState(garage)
        local free = 0
        for _, s in ipairs(slots) do if s.free then free = free + 1 end end
        local doors = #(garage.doors or {})
        local locked = false
        if doors > 0 and GRM.Doors and GRM.Doors.IsDoorLocked then
            for _, ent in ipairs(G.DoorEntities(garage)) do
                if GRM.Doors.IsDoorLocked(ent) then locked = true break end
            end
        end
        net.Start(NET_OPEN)
            net.WriteString(garage.id)
            net.WriteString(garage.name)
            net.WriteString(garage.kind)
            net.WriteUInt(math.min(garage.fee or 0, 16777215), 24)
            net.WriteUInt(free, 8)
            net.WriteUInt(math.min(doors, 255), 8)
            net.WriteBool(locked)
            net.WriteTable(slots)
            local personalRows, fleetOfGarage = splitRows(ply, garage)
            net.WriteTable(personalRows)
            net.WriteTable(fleetOfGarage)
        net.Send(ply)
    end

    local function result(ply, ok, msg)
        net.Start(NET_RESULT) net.WriteBool(ok == true) net.WriteString(tostring(msg or "")) net.Send(ply)
        notify(ply, msg, ok)
    end

    function G.OpenFor(ply)
        local garage, source = G.GarageAt(ply)
        if not garage then
            notify(ply, "Вы не в гараже. Подойдите к стойке гаража или встаньте в его зону.", false)
            return false
        end
        local can, why = G.CanUse(ply, garage)
        if not can then notify(ply, why or "Нет доступа к этому гаражу", false) return false end
        G.Push(ply, garage)
        return true, source
    end

    -- Выдать машину из гаража на свободное место.
    function G.Retrieve(ply, recordID)
        local garage = G.GarageAt(ply)
        if not garage then return false, "Вы не в гараже" end
        local can, why = G.CanUse(ply, garage)
        if not can then return false, why end
        local VD = GRM.VehicleDealer
        if not (VD and VD.IssueRecord) then return false, "Модуль дилера не загружен" end
        local rec = VD.FindRecord(ply, recordID)
        if not rec then return false, "Запись гаража не найдена" end
        local home = tostring(rec.garageID or "")
        if home ~= "" and home ~= garage.id then
            local h = G.Get(home)
            return false, ("Этот транспорт стоит в гараже «%s»."):format(h and h.name or home)
        end
        local place, slotErr = G.FreeSlot(garage, ply)
        if not place then return false, slotErr or "Нет свободного места" end
        local fee = math.max(0, math.floor(tonumber(garage.fee) or 0))
        if fee > 0 and GRM.HasMoney and not GRM.HasMoney(ply, fee) then
            return false, ("Не хватает средств на выезд: %s"):format(GRM.Format and GRM.Format(fee) or fee)
        end
        local ent, err = VD.IssueRecord(ply, recordID, place, nil)
        if not ent then return false, err end
        if fee > 0 and GRM.TakeMoney then GRM.TakeMoney(ply, fee, "Выезд из гаража " .. garage.name) end
        if home == "" then VD.SetRecordGarage(ply, recordID, garage.id) end
        audit("garage.retrieve", ply, { garage = garage.id, record = recordID }, { slot = place.slot and place.slot.id, fee = fee })
        return true, ("Транспорт подан на место «%s»."):format(place.slot and place.slot.name or "стоянка")
    end

    --[[ Подать машину в гараж ИЗДАЛЕКА (заказ владельца 21.08: «Купить» ≠
         «Выдать»). Игрок покупает транспорт у дилера, а затем сам решает,
         куда его выдать: здесь у дилера или в гараж. Во втором случае машина
         встаёт на свободное место гаража, а игрок забирает её там. ]]
    function G.IssueRemote(ply, recordID, garageID)
        if not IsValid(ply) then return false, "Игрок не найден" end
        local VD = GRM.VehicleDealer
        if not (VD and VD.IssueRecord) then return false, "Модуль дилера не загружен" end
        local rec = VD.FindRecord(ply, recordID)
        if not rec then return false, "Запись гаража не найдена" end
        if rec.service then return false, "Служебный транспорт выдаётся у дилера" end

        local target = G.Get(garageID)
        if not target then target = G.Get(rec.garageID) end
        if not target then target = G.HomeGarageFor(ply, nil) end
        if not target then return false, "У вас нет доступного гаража — заберите транспорт у дилера" end

        local can, why = G.CanUse(ply, target)
        if not can then return false, why or "Нет доступа к гаражу" end
        if #(target.slots or {}) == 0 then return false, ("В гараже «%s» нет мест стоянки"):format(target.name) end

        local place, slotErr = G.FreeSlot(target, ply)
        if not place then return false, slotErr or ("В гараже «%s» нет свободного места"):format(target.name) end

        local fee = math.max(0, math.floor(tonumber(target.fee) or 0))
        if fee > 0 and GRM.HasMoney and not GRM.HasMoney(ply, fee) then
            return false, ("Не хватает средств на подачу: %s"):format(GRM.Format and GRM.Format(fee) or fee)
        end

        local ent, err = VD.IssueRecord(ply, recordID, place, nil)
        if not ent then return false, err or "Не удалось выдать транспорт" end
        if fee > 0 and GRM.TakeMoney then GRM.TakeMoney(ply, fee, "Подача транспорта в гараж " .. target.name) end
        VD.SetRecordGarage(ply, recordID, target.id)
        audit("garage.issue_remote", ply, { garage = target.id, record = recordID }, { slot = place.slot and place.slot.id, fee = fee })
        return true, ("Транспорт подан в гараж «%s» на место «%s»."):format(target.name,
            place.slot and place.slot.name or "стоянка")
    end

    -- Убрать машину в гараж (её можно загонять в любой доступный гараж).
    function G.Store(ply, recordID)
        local garage = G.GarageAt(ply)
        if not garage then return false, "Вы не в гараже" end
        local can, why = G.CanUse(ply, garage)
        if not can then return false, why end
        local VD = GRM.VehicleDealer
        if not (VD and VD.StoreRecord) then return false, "Модуль дилера не загружен" end
        local ent = VD.Active and VD.Active[tostring(recordID)]
        if not IsValid(ent) then return false, "Этот транспорт не на карте" end
        local center = G.ZoneCenter(garage)
        if not G.PosInZone(garage, ent:GetPos()) and center:DistToSqr(ent:GetPos()) > 900 * 900 then
            return false, "Загоните транспорт в гараж — отсюда его не принять"
        end
        local ok, msg = VD.StoreRecord(ply, recordID, nil)
        if ok then
            VD.SetRecordGarage(ply, recordID, garage.id)
            audit("garage.store", ply, { garage = garage.id, record = recordID }, {})
        end
        return ok, msg
    end

    -- Открыть/закрыть ворота гаража (только тот, у кого есть доступ).
    function G.ToggleDoors(ply)
        local garage = G.GarageAt(ply)
        if not garage then return false, "Вы не в гараже" end
        local can, why = G.CanUse(ply, garage)
        if not can then return false, why end
        if #(garage.doors or {}) == 0 then return false, "К этому гаражу не привязаны ворота" end
        if not (GRM.Doors and GRM.Doors.IsDoorLocked and GRM.Doors.LockDoor) then return false, "Модуль дверей не загружен" end
        local anyLocked = false
        for _, ent in ipairs(G.DoorEntities(garage)) do
            if GRM.Doors.IsDoorLocked(ent) then anyLocked = true break end
        end
        local n = G.ApplyDoorState(garage, not anyLocked)
        audit("garage.doors", ply, { garage = garage.id }, { locked = not anyLocked, doors = n })
        return true, anyLocked and ("Ворота открыты (%d)"):format(n) or ("Ворота закрыты (%d)"):format(n)
    end

    function G.SetHome(ply, recordID)
        local garage = G.GarageAt(ply)
        if not garage then return false, "Вы не в гараже" end
        local can, why = G.CanUse(ply, garage)
        if not can then return false, why end
        local VD = GRM.VehicleDealer
        if not (VD and VD.SetRecordGarage) then return false, "Модуль дилера не загружен" end
        local ok, err = VD.SetRecordGarage(ply, recordID, garage.id)
        if not ok then return false, err end
        return true, ("Транспорт закреплён за гаражом «%s»."):format(garage.name)
    end

    ------------------------------------------------------------------
    -- СЕТЬ
    ------------------------------------------------------------------
    net.Receive(NET_ACT, function(bits, ply)
        if not IsValid(ply) then return end
        if GRM.Net and not GRM.Net.Guard(ply, "garage.action", { rate = 0.35, burst = 3, maxBits = 2048 }, { bits = bits }) then return end
        local op = tostring(net.ReadString() or "")
        local id = tostring(net.ReadString() or "")
        local ok, msg
        local V = GRM.Vehicles
        if op == "retrieve" then ok, msg = V and V.Issue(ply, "personal", id) or G.Retrieve(ply, id)
        elseif op == "store" then ok, msg = V and V.Store(ply, "personal", id) or G.Store(ply, id)
        elseif op == "fleet_issue" then
            -- служебная техника организации: выдача на свободное место ЭТОГО гаража
            local garage = G.GarageAt(ply)
            if not garage then ok, msg = false, "Вы не в гараже"
            elseif not V then ok, msg = false, "Модуль транспорта не загружен"
            else ok, msg = V.Issue(ply, "fleet", id, garage) end
        elseif op == "fleet_store" then
            if not V then ok, msg = false, "Модуль транспорта не загружен"
            else ok, msg = V.Store(ply, "fleet", id) end
        elseif op == "sethome" then ok, msg = G.SetHome(ply, id)
        elseif op == "doors" then ok, msg = G.ToggleDoors(ply)
        elseif op == "refresh" then G.Push(ply) return
        else return end
        result(ply, ok, msg)
        if ok then G.Push(ply) end
    end)

    net.Receive(NET_ADMIN, function(bits, ply)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        if GRM.Net and not GRM.Net.Guard(ply, "garage.admin", { rate = 0.5, burst = 3, maxBits = 8192 }, { bits = bits }) then return end
        local op = tostring(net.ReadString() or "")
        if op == "list" then
            local rows = {}
            for _, rec in ipairs(G.List()) do
                rows[#rows + 1] = {
                    id = rec.id, name = rec.name, kind = rec.kind, faction = rec.faction, owner = rec.owner,
                    fee = rec.fee, slots = #(rec.slots or {}), terminals = #(rec.terminals or {}),
                    doors = #(rec.doors or {}), propertyID = rec.propertyID or "",
                    center = vd(G.ZoneCenter(rec)),
                }
            end
            net.Start(NET_ADMIN) net.WriteString("list") net.WriteTable(rows) net.Send(ply)
            return
        end
        local id = tostring(net.ReadString() or "")
        local ok, msg
        if op == "update" then ok, msg = G.Update(id, net.ReadTable() or {}, ply)
        elseif op == "remove" then ok, msg = G.Remove(id, ply)
        elseif op == "goto" then
            local rec = G.Get(id)
            if rec then ply:SetPos(G.ZoneCenter(rec) + Vector(0, 0, 24)) ok, msg = true, "Телепорт в гараж" else ok, msg = false, "Гараж не найден" end
        else return end
        result(ply, ok, msg)
        net.Start(NET_ADMIN) net.WriteString("done") net.WriteTable({}) net.Send(ply)
    end)

    ------------------------------------------------------------------
    -- КОМАНДЫ И СТАРТ
    ------------------------------------------------------------------
    local function chatCommand(ply, text)
        local c = string.lower(string.Trim(tostring(text or "")))
        if c ~= "/garage" and c ~= "!garage" and c ~= "/гараж" and c ~= "/гараж " then return false end
        -- Если игрок в гараже — открываем гараж; иначе пусть отработает дилер.
        if not G.GarageAt(ply) then return false end
        G.OpenFor(ply)
        return true
    end
    hook.Add("PlayerSay", "GRM_Garage_Chat", function(ply, text)
        if chatCommand(ply, text) then return "" end
    end)
    hook.Add("PlayerSayTransform", "GRM_Garage_ChatEC", function(ply, pack)
        if not (istable(pack) and isstring(pack[1])) then return end
        if chatCommand(ply, pack[1]) then pack[1] = "" pack.SkipPlayerSay = true end
    end)

    concommand.Add("grm_garage_menu", function(ply) if IsValid(ply) then G.OpenFor(ply) end end)

    --- Диагностика мест выдачи: где стоите — то и разбираем.
    concommand.Add("grm_garage_slots", function(ply)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        local garage = G.GarageAt(ply) or G.Nearest(ply:GetPos(), 4096)
        if not garage then ply:ChatPrint("[Гараж] Рядом нет гаража.") return end
        ply:ChatPrint(("[Гараж] «%s» — мест: %d, связанных дилеров: %d"):format(
            garage.name, #(garage.slots or {}), #(garage.linkedDealers or {})))
        for _, row in ipairs(G.SlotDiagnose(garage, ply)) do
            ply:ChatPrint(("  #%d %s — %s%s"):format(row.index, tostring(row.name),
                row.free and (row.tight and "свободно (тесно)" or "свободно") or "занято",
                row.blocker ~= "" and ("  [" .. row.blocker .. "]") or ""))
        end
        local place, err = G.FreeSlot(garage, ply)
        ply:ChatPrint(place and ("  → выдача пойдёт на место «%s»"):format(
            (place.slot and place.slot.name) or "стоянка") or ("  → " .. tostring(err)))
    end)
    concommand.Add("grm_garage_reload", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        G.Load()
        if IsValid(ply) then notify(ply, "Гаражи перечитаны: " .. table.Count(G.Garages), true) end
    end)
    concommand.Add("grm_garages", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local function out(msg) if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end end
        out("[GRM Гаражи] всего: " .. table.Count(G.Garages))
        for _, rec in ipairs(G.List()) do
            out(("  %s | %s | %s | мест %d | стоек %d | выезд %d"):format(
                rec.id, rec.name, G.KindName(rec.kind), #(rec.slots or {}), #(rec.terminals or {}), rec.fee or 0))
        end
    end)

    -- Старт: данные грузим приоритетом normal, стойки поднимаем позже (late),
    -- чтобы не толкаться с перм-пропами и дилерами в один тик.
    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_Garage_Load", "normal", function() G.Load() end,
            { label = "Гаражи: зоны и места" })
        GRM.Boot.OnMapStart("GRM_Garage_Terminals", "late", function() G.SpawnTerminals() end,
            { label = "Гаражи: стойки вызова" })
    else
        hook.Add("InitPostEntity", "GRM_Garage_Load", function() timer.Simple(2, function() G.Load() end) end)
    end
    hook.Add("PostCleanupMap", "GRM_Garage_Cleanup", function() timer.Simple(1, function() G.SpawnTerminals() end) end)

    print("[GRM Garage] server v" .. G.Version .. " loaded")
end

-----------------------------------------------------------------------
-- КЛИЕНТ: приём данных (само окно — в cl_grm_garage_ui.lua)
-----------------------------------------------------------------------
if CLIENT then
    G.NetOpen, G.NetAct, G.NetResult, G.NetAdmin = NET_OPEN, NET_ACT, NET_RESULT, NET_ADMIN

    function G.SendAction(op, id)
        net.Start(NET_ACT)
            net.WriteString(tostring(op or ""))
            net.WriteString(tostring(id or ""))
        net.SendToServer()
    end

    net.Receive(NET_OPEN, function()
        local data = {
            id = net.ReadString(), name = net.ReadString(), kind = net.ReadString(),
            fee = net.ReadUInt(24), free = net.ReadUInt(8),
            doors = net.ReadUInt(8), doorsLocked = net.ReadBool(),
            slots = net.ReadTable() or {}, vehicles = net.ReadTable() or {},
            fleet = net.ReadTable() or {},
        }
        G.LastData = data
        if G.OpenWindow then G.OpenWindow(data) end
    end)

    net.Receive(NET_RESULT, function()
        local ok, msg = net.ReadBool(), net.ReadString()
        if msg ~= "" then notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 5) end
        surface.PlaySound(ok and "buttons/button9.wav" or "buttons/button10.wav")
    end)

    print("[GRM Garage] client v" .. G.Version .. " loaded")
end
