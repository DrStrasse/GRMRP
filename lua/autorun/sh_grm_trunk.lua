--[[--------------------------------------------------------------------
    GRM Vehicle Trunk v1.0.0 (Код 80) — Багажник любого транспорта

    Работает с ЛЮБЫМ транспортом сборки (VK.IsVehicle: стандарт, simfphys,
    LVS/LFS, дилер VD_ID). Открытие: /trunk или консоль grm_trunk,
    глядя на машину в радиусе 200 юн. Крышка открывается/закрывается
    (звук ящика, 3D2D-метка «БАГАЖНИК ОТКРЫТ»), автозакрытие на ходу
    (>~20 км/ч), при уходе всех смотревших или по таймауту.

    Доступ (зеркало прав дверей/ключей):
      - владелец (player) и члены фракции-владельца — всегда;
      - чужой — ТОЛЬКО пока машина разблокирована (осознанный риск кражи,
        RP-законен), на заблокированной — отказ (звук deny);
      - суперадмин — всегда.

    Хранение: виртуальные слоты (та же семантика, что у GRM.Inventory):
    предметы стакаются по maxStack, оружие — поштучно с обоймами.
    Лимиты: 24 слота и 120 кг (weight из ItemDefs; для незарегистрированного
    оружия — 3.0 кг постоянный вес). Пер-оверрайд по классу: GRM.Trunk.ClassCaps.
    Персист data/grm_trunks.json: ключ «ply|STEAMID|class» / «fac|Имя|class»
    (jsonT 3-им аргументом — находка 65), техника без владельца хранит
    только на сессию (мусор в БД не пишется). Сейв: дебаунс 10с + тик 60с
    + Disconnect/ShutDown, печать причин.

    Анти-дюп: все перекладывания только на сервере; клиент шлёт намерение
    {veh, dir, slot, count}, сервер сам читает актуальные слоты, клэмпит
    до наличия, пересобирает снапшот ВСЕМ зрителям одного багажника.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Trunk = GRM.Trunk or {}
local TK = GRM.Trunk

TK.Version       = "1.2.0"
TK.DataFile      = "grm_trunks.json"
TK.MaxSlots      = 24
TK.MaxWeight     = 120
TK.WeaponWeight  = 3.0
TK.OpenRange     = 200
TK.UseRange      = 260
TK.SpeedLimit    = 600   -- ~33 км/ч: быстрее — крышка захлопывается
TK.CloseDelay    = 20    -- сек до автозакрытия без зрителей
TK.ClassCaps     = TK.ClassCaps or {} -- [class] = { slots = N, weight = W } — расширяемо

local NET_OPEN  = "GRM_Trunk_Open"   -- C→S: просьба открыть/закрыть        S→C: снапшот открытого багажника
local NET_SYNC  = "GRM_Trunk_Sync"   -- S→C: обновление слотов смотревшим
local NET_CLOSE = "GRM_Trunk_Close"  -- двусторонний
local NET_XFER  = "GRM_Trunk_Xfer"   -- C→S: перенос слота

local function capsFor(veh)
    local c = istable(veh) and TK.ClassCaps[veh:GetClass()] or nil
    if istable(c) then
        return tonumber(c.slots) or TK.MaxSlots, tonumber(c.weight) or TK.MaxWeight
    end
    return TK.MaxSlots, TK.MaxWeight
end

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_SYNC)
    util.AddNetworkString(NET_CLOSE)
    util.AddNetworkString(NET_XFER)

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    -- хранилище -----------------------------------------------------
    TK.Store = TK.Store or {}
    local function loadStore()
        TK.Store = {}
        local t = jsonT(file.Read(TK.DataFile, "DATA") or "")
        if istable(t) then
            for k, rec in pairs(t) do
                if isstring(k) and istable(rec) and istable(rec.slots) then
                    TK.Store[k] = { slots = rec.slots }
                end
            end
        end
        print("[GRM Trunk] LOAD: " .. tostring(table.Count(TK.Store)) .. " багажников")
    end
    local dirty = false
    local function saveStore(why)
        local ok, txt = pcall(util.TableToJSON, TK.Store, true)
        if ok and txt then
            file.Write(TK.DataFile, txt)
            print("[GRM Trunk] SAVE ok (" .. tostring(why or "-") .. "): " .. tostring(table.Count(TK.Store)) .. " багажников")
        end
        dirty = false
    end
    loadStore()
    local function markDirty()
        dirty = true
        timer.Remove("GRM_Trunk_Debounce")
        timer.Create("GRM_Trunk_Debounce", 10, 1, function() if dirty then saveStore("дебаунс 10с") end end)
    end
    timer.Create("GRM_Trunk_AutoSave", 60, 0, function() if dirty then saveStore("автосейв 60с") end end)
    hook.Add("PlayerDisconnected", "GRM_Trunk_Disc", function() if dirty then saveStore("дисконнект") end end)
    hook.Add("ShutDown", "GRM_Trunk_Shut", function() saveStore("shutdown") end)

    -- владение/доступ (по данным VK, поля сервера/NW2 — обе формы) -----
    local function ownerState(veh)
        local otype = veh.VK_OwnerType or veh:GetNW2String("VK_OwnerType", "")
        local osteam = veh.VK_OwnerSteam or veh:GetNW2String("VK_OwnerSteam", "")
        local fac = veh.VK_FactionName or veh:GetNW2String("VK_FactionName", "")
        local locked = (veh.VK_Locked == true) or veh:GetNW2Bool("VK_Locked", false)
        return tostring(otype or ""), tostring(osteam or ""), tostring(fac or ""), locked
    end

    local function myFaction(ply)
        if _G.FactionsAPI and _G.FactionsAPI.GetFactionOf then
            local found = _G.FactionsAPI.GetFactionOf(ply)
            if found then return found end
        end
        if istable(Factions) then
            local sid, s64 = ply:SteamID(), ply:SteamID64()
            for name, f in pairs(Factions) do
                if istable(f) and istable(f.Members) and (f.Members[sid] or f.Members[s64]) then return name end
            end
        end
        return nil
    end

    function TK.CanAccess(ply, veh)
        if not IsValid(ply) or not IsValid(veh) then return false, "Нет машины" end
        if ply:IsSuperAdmin() then return true end
        local otype, osteam, fac, locked = ownerState(veh)
        local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()
        if otype == "player" and (osteam == ck or osteam == ply:SteamID() or osteam == ply:SteamID64()) then return true end
        if otype == "faction" and fac ~= "" and myFaction(ply) == fac then return true end
        if not locked then return true end -- чужая, но ОТКРЫТАЯ машина: риск владельца (RP-кража)
        return false, "Багажник недоступен: машина заблокирована, ключи не ваши"
    end

    -- ключ персиста ---------------------------------------------------
    local function storeKey(veh)
        local otype, osteam, fac = ownerState(veh)
        if otype == "player" and osteam ~= "" then return "ply|" .. osteam .. "|" .. veh:GetClass() end
        if otype == "faction" and fac ~= "" then return "fac|" .. fac .. "|" .. veh:GetClass() end
        return nil -- без владельца: только сессия
    end

    local function getSlots(veh)
        local k = storeKey(veh)
        if k then
            if not TK.Store[k] then TK.Store[k] = { slots = {} } markDirty() end
            return TK.Store[k].slots, k
        end
        veh.TK_Slots = veh.TK_Slots or {}
        return veh.TK_Slots, nil
    end

    -- вес ---------------------------------------------------------------
    local function slotWeight(slot)
        if not istable(slot) or not slot.id then return 0 end
        local def = GRM.Inventory and GRM.Inventory.GetItemDef and GRM.Inventory.GetItemDef(slot.id)
        local w = (istable(def) and tonumber(def.weight)) or TK.WeaponWeight
        return w * (tonumber(slot.count) or 1)
    end
    local function totalWeight(slots)
        local sum = 0
        for _, s in pairs(slots) do sum = sum + slotWeight(s) end
        return sum
    end
    local function isWeaponId(id) return string.sub(tostring(id or ""), 1, 7) == "weapon:" end

    -- зрители / крышка ----------------------------------------------------
    TK.Viewers = TK.Viewers or {} -- [veh] = { [ply] = true }

    local function pushSnapshot(veh)
        local set = TK.Viewers[veh]
        if not istable(set) then return end
        local slots = getSlots(veh)
        local maxSlots, maxWeight = capsFor(veh)
        for ply in pairs(set) do
            if IsValid(ply) then
                net.Start(NET_SYNC)
                    net.WriteEntity(veh)
                    net.WriteTable(slots)
                    net.WriteFloat(totalWeight(slots))
                    net.WriteUInt(maxSlots, 8)
                    net.WriteFloat(maxWeight)
                net.Send(ply)
            else
                set[ply] = nil
            end
        end
    end

    local function setLid(veh, open, why)
        veh:SetNW2Bool("VK_TrunkOpen", open)
        veh:EmitSound(open and "items/ammocrate_open.wav" or "items/ammocrate_close.wav", 70, open and 100 or 90)
        if open then veh._tkOpenedAt = CurTime() end
    end

    local function closeForAll(veh)
        -- сначала рассылаем окно-закрытие, потом чистим зрителей
        local set = TK.Viewers[veh]
        if istable(set) then
            for p in pairs(set) do
                if IsValid(p) then net.Start(NET_CLOSE) net.WriteEntity(veh) net.Send(p) end
            end
        end
        TK.Viewers[veh] = nil
        setLid(veh, false, "закрытие")
    end

    local function sendSnapshot(ply, veh)
        local slots = getSlots(veh)
        local maxSlots, maxWeight = capsFor(veh)
        net.Start(NET_OPEN)
            net.WriteEntity(veh)
            net.WriteTable(slots)
            net.WriteFloat(totalWeight(slots))
            net.WriteUInt(maxSlots, 8)
            net.WriteFloat(maxWeight)
            net.WriteString(VK and VK.GetVehicleDisplayName and VK.GetVehicleDisplayName(veh) or "Транспорт")
        net.Send(ply)
    end

    function TK.Open(ply, veh)
        if not IsValid(ply) or not IsValid(veh) then return end
        if ply:GetPos():DistToSqr(veh:GetPos()) > TK.OpenRange * TK.OpenRange then
            if GRM.Notify then GRM.Notify(ply, "Подойдите ближе к машине.", 255, 190, 90) end
            return
        end
        do
            local sp = 0
            local ok, v = pcall(function() return veh:GetVelocity():Length() end)
            if ok and tonumber(v) then sp = v end
            if sp > TK.SpeedLimit then
                if GRM.Notify then GRM.Notify(ply, "На ходу багажник не открыть.", 255, 130, 110) end
                return
            end
        end
        -- крышка уже открыта
        if veh:GetNW2Bool("VK_TrunkOpen", false) then
            if TK.Viewers[veh] and TK.Viewers[veh][ply] then
                -- повторный вызов зрителем = закрыть крышку для всех
                closeForAll(veh)
            else
                -- второй зритель: доступ + подключение к общему багажнику
                local okA, err = TK.CanAccess(ply, veh)
                if not okA then
                    if GRM.Notify then GRM.Notify(ply, tostring(err or "Нет доступа."), 255, 130, 110) end
                    veh:EmitSound("buttons/button11.wav", 65, 100)
                    return
                end
                TK.Viewers[veh] = TK.Viewers[veh] or {}
                TK.Viewers[veh][ply] = true
                sendSnapshot(ply, veh)
            end
            return
        end
        local ok, err = TK.CanAccess(ply, veh)
        if not ok then
            if GRM.Notify then GRM.Notify(ply, tostring(err or "Нет доступа."), 255, 130, 110) end
            veh:EmitSound("buttons/button11.wav", 65, 100)
            return
        end
        setLid(veh, true, "открытие")
        TK.Viewers[veh] = TK.Viewers[veh] or {}
        TK.Viewers[veh][ply] = true
        sendSnapshot(ply, veh)
    end

    function TK.CloseViewer(ply, veh)
        if IsValid(veh) and istable(TK.Viewers[veh]) then TK.Viewers[veh][ply] = nil end
    end

    function TK.Slam(ply, veh)
        if not (IsValid(ply) and IsValid(veh)) then return end
        if not veh:GetNW2Bool("VK_TrunkOpen", false) then return end
        local ok = TK.CanAccess(ply, veh)
        if not ok and not ply:IsSuperAdmin() then return end
        closeForAll(veh)
    end

    net.Receive(NET_CLOSE, function(_, ply)
        if not IsValid(ply) then return end
        local veh = net.ReadEntity()
        local slam = false
        if net.BytesLeft and net.BytesLeft() >= 1 then slam = net.ReadBool() == true end
        if slam then TK.Slam(ply, veh) else TK.CloseViewer(ply, veh) end
    end)

    hook.Add("PlayerUse", "GRM_Trunk_UseReopen", function(ply, ent)
        if not (IsValid(ply) and IsValid(ent)) then return end
        if not (VK and VK.IsVehicle and VK.IsVehicle(ent)) then return end
        if not ent:GetNW2Bool("VK_TrunkOpen", false) then return end
        if ply:GetPos():DistToSqr(ent:GetPos()) > TK.UseRange * TK.UseRange then return end
        if (tonumber(ply._tkUseAt) or 0) > CurTime() then return false end
        ply._tkUseAt = CurTime() + 0.45
        TK.Open(ply, ent)
        return false
    end)

    -- сторож автозакрытия: бежим только по открытым крышкам (TK.Viewers) ---
    timer.Create("GRM_Trunk_Watch", 0.5, 0, function()
        -- Аудит нагрузки 18.08: сторож крутился всегда. Если багажник никто
        -- не смотрит, выходим до цикла (99% времени сервера).
        if not istable(TK.Viewers) or next(TK.Viewers) == nil then return end
        for veh, set in pairs(TK.Viewers or {}) do
            if not IsValid(veh) then
                TK.Viewers[veh] = nil
            else
                local sp = 0
                local ok, v = pcall(function() return veh:GetVelocity():Length() end)
                if ok and tonumber(v) then sp = v end
                if sp > TK.SpeedLimit then
                    closeForAll(veh)
                else
                    local viewers = 0
                    for p in pairs(set or {}) do
                        if IsValid(p) and p:GetPos():DistToSqr(veh:GetPos()) < TK.UseRange * TK.UseRange then
                            viewers = viewers + 1
                        else
                            set[p] = nil
                            if IsValid(p) then net.Start(NET_CLOSE) net.WriteEntity(veh) net.Send(p) end
                        end
                    end
                    if viewers == 0 and (tonumber(veh._tkOpenedAt) or 0) + TK.CloseDelay < CurTime() then
                        closeForAll(veh)
                    end
                end
            end
        end
    end)

    hook.Add("EntityRemoved", "GRM_Trunk_EntGone", function(ent)
        if TK.Viewers and TK.Viewers[ent] then TK.Viewers[ent] = nil end
    end)
    hook.Add("PlayerDisconnected", "GRM_Trunk_Leave", function(ply)
        for veh, set in pairs(TK.Viewers or {}) do
            if istable(set) then set[ply] = nil end
        end
    end)

    -- переносы ------------------------------------------------------------,
    local function firstFree(slots, maxSlots)
        for i = 1, maxSlots do
            if not istable(slots[i]) or not slots[i].id then return i end
        end
        return nil
    end

    -- кладём в багажник (часть может не влезть — вернёт уложенное)
    local function depositToTrunk(slots, maxSlots, maxWeight, slot, count)
        local moved = 0
        local id = slot.id
        if isWeaponId(id) then
            local free = firstFree(slots, maxSlots)
            if not free then return 0 end
            if totalWeight(slots) + TK.WeaponWeight > maxWeight then return 0 end
            slots[free] = { id = id, count = 1, data = istable(slot.data) and table.Copy(slot.data) or nil }
            return 1
        end
        local def = GRM.Inventory.GetItemDef(id)
        if not istable(def) then return 0 end
        local maxStack = GRM.Inventory.GetMaxStack(id)
        local want = math.min(tonumber(count) or 1, tonumber(slot.count) or 1)
        local w = tonumber(def.weight) or TK.WeaponWeight
        -- добивка стаков
        for i = 1, maxSlots do
            if moved >= want then break end
            local s = slots[i]
            if istable(s) and s.id == id and (tonumber(s.count) or 0) < maxStack then
                local can = math.min(want - moved, maxStack - (tonumber(s.count) or 0))
                while can > 0 and totalWeight(slots) + w > maxWeight do can = can - 1 end
                if can > 0 then s.count = (tonumber(s.count) or 0) + can moved = moved + can end
            end
        end
        -- новые слоты
        while moved < want do
            local free = firstFree(slots, maxSlots)
            if not free then break end
            local can = math.min(want - moved, maxStack)
            while can > 0 and totalWeight(slots) + w > maxWeight do can = can - 1 end
            if can <= 0 then break end
            slots[free] = { id = id, count = can }
            moved = moved + can
        end
        return moved
    end

    net.Receive(NET_XFER, function(_, ply)
        if not IsValid(ply) then return end
        local veh = net.ReadEntity()
        local toTrunk = net.ReadBool()
        local slotIdx = tonumber(net.ReadUInt(8)) or 0
        local count = tonumber(net.ReadUInt(16)) or 1
        if not IsValid(veh) or slotIdx <= 0 then return end
        if not veh:GetNW2Bool("VK_TrunkOpen", false) then return end
        if ply:GetPos():DistToSqr(veh:GetPos()) > TK.UseRange * TK.UseRange then return end
        if not (TK.Viewers[veh] and TK.Viewers[veh][ply]) then return end

        local slots, pKey = getSlots(veh)
        local maxSlots, maxWeight = capsFor(veh)

        if toTrunk then
            local inv = GRM.Inventory and GRM.Inventory.GetPlayerInv and GRM.Inventory.GetPlayerInv(ply)
            if not istable(inv) then return end
            local slot = inv.slots[slotIdx]
            if not istable(slot) or not slot.id then return end
            local moved = depositToTrunk(slots, maxSlots, maxWeight, slot, count)
            if moved <= 0 then
                if GRM.Notify then GRM.Notify(ply, "Не влезает: багажник полон или перегруз (" .. tostring(math.floor(totalWeight(slots))) .. "/" .. tostring(math.floor(maxWeight)) .. " кг).", 255, 130, 110) end
                veh:EmitSound("buttons/button11.wav", 65, 100)
                return
            end
            GRM.Inventory.RemoveFromSlot(ply, slotIdx, moved)
            markDirty()
            pushSnapshot(veh)
            if GRM.Notify then GRM.Notify(ply, "Положено в багажник: " .. tostring(moved) .. " шт.", 160, 220, 255) end
        else
            local slot = slots[slotIdx]
            if not istable(slot) or not slot.id then return end
            if isWeaponId(slot.id) then
                local cls = istable(slot.data) and slot.data.class or string.sub(slot.id, 8)
                local ok = GRM.Inventory.AddWeapon(ply, cls, (slot.data and slot.data.clip1) or 0, (slot.data and slot.data.clip2) or 0)
                if not ok then
                    if GRM.Notify then GRM.Notify(ply, "В инвентаре нет места.", 255, 130, 110) end
                    return
                end
                slots[slotIdx] = nil
            else
                local want = math.min(tonumber(count) or 1, tonumber(slot.count) or 1)
                local leftover = GRM.Inventory.AddItem(ply, slot.id, want)
                local moved = want - (tonumber(leftover) or 0)
                if moved <= 0 then
                    if GRM.Notify then GRM.Notify(ply, "В инвентаре нет места.", 255, 130, 110) end
                    return
                end
                slot.count = (tonumber(slot.count) or 1) - moved
                if (tonumber(slot.count) or 0) <= 0 then slots[slotIdx] = nil end
            end
            markDirty()
            pushSnapshot(veh)
        end
    end)

    -- команды -------------------------------------------------------------
    local function aimedVehicle(ply)
        local tr = ply:GetEyeTrace()
        local veh = tr and tr.Entity or nil
        if IsValid(veh) and VK and VK.IsVehicle and VK.IsVehicle(veh) then return veh end
        return nil
    end

    function TK.RequestToggle(ply)
        if not IsValid(ply) then return end
        local veh = aimedVehicle(ply)
        if not IsValid(veh) then
            -- редакторский фолбэк: ближайшая машина в радиусе
            local best, bd = nil, TK.OpenRange * TK.OpenRange
            for _, e in ipairs(ents.FindInSphere(ply:GetPos(), TK.OpenRange)) do
                if IsValid(e) and VK and VK.IsVehicle and VK.IsVehicle(e) then
                    local d = ply:GetPos():DistToSqr(e:GetPos())
                    if d < bd then bd = d best = e end
                end
            end
            veh = best
        end
        if not IsValid(veh) then
            if GRM.Notify then GRM.Notify(ply, "Наведите прицел на машину (или встаньте рядом) — багажник любого транспорта.", 200, 200, 210) end
            return
        end
        TK.Open(ply, veh)
    end

    function TK.HandleChat(ply, text)
        if not IsValid(ply) then return false end
        local low = string.lower(string.Trim(tostring(text or "")))
        if low == "/trunk" or low == "/багажник" then
            TK.RequestToggle(ply)
            return true
        end
        return false
    end

    hook.Add("PlayerSayTransform", "GRM_Trunk_TransformCmds", function(ply, datapack)
        if not istable(datapack) then return end
        local msg = datapack[1]
        if not isstring(msg) then return end
        if TK.HandleChat and TK.HandleChat(ply, msg) then
            datapack[1] = ""
            datapack.SkipPlayerSay = true
        end
    end)
    hook.Add("PlayerSay", "GRM_Trunk_ChatCmds", function(ply, text)
        if TK.HandleChat and TK.HandleChat(ply, text) then return "" end
    end)
    concommand.Add("grm_trunk", function(ply) TK.RequestToggle(ply) end)

    print("[GRM Trunk] Багажник транспорта v" .. TK.Version .. " загружен (Код 80)")
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    surface.CreateFont("GRMTrunk_Title",  { font = "Roboto", size = 20, weight = 800, extended = true })
    surface.CreateFont("GRMTrunk_Sub",    { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMTrunk_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMTrunk_Small",  { font = "Roboto", size = 12, weight = 500, extended = true })
    surface.CreateFont("GRMTrunk_3D",     { font = "Roboto", size = 20, weight = 800, extended = true })

    local C = {
        bg    = Color(24, 28, 38, 240),
        head  = Color(18, 22, 30, 255),
        panel = Color(32, 38, 50, 245),
        panel2= Color(26, 32, 42, 235),
        acc   = Color(70, 150, 240),
        green = Color(60, 190, 110),
        red   = Color(220, 75, 70),
        yellow= Color(230, 180, 60),
        text  = Color(240, 245, 250),
        dim   = Color(170, 180, 195),
    }

    TK._frame = nil
    TK._veh = nil
    TK._slots = {}
    TK._weight = 0
    TK._maxSlots = 24
    TK._maxWeight = 120
    TK._vehName = "Транспорт"

    local function itemLabel(slot)
        if not istable(slot) then return "", "" end
        local def = GRM.Inventory and GRM.Inventory.GetItemDef and GRM.Inventory.GetItemDef(slot.id)
        if istable(def) then
            return tostring(def.name or slot.id), tostring(def.icon or "icon16/package.png")
        end
        if string.sub(tostring(slot.id), 1, 7) == "weapon:" then
            local cls = istable(slot.data) and tostring(slot.data.class) or string.sub(tostring(slot.id), 8)
            local wdef = weapons and weapons.Get and weapons.Get(cls)
            return "Оружие: " .. tostring((wdef and wdef.PrintName) or cls), "icon16/gun.png"
        end
        return tostring(slot.id), "icon16/package.png"
    end

    local function closeFrame()
        if IsValid(TK._frame) then TK._frame:Remove() end
        TK._frame = nil
    end

    local function sendClose(slam)
        if IsValid(TK._veh) then
            net.Start(NET_CLOSE)
                net.WriteEntity(TK._veh)
                net.WriteBool(slam == true)
            net.SendToServer()
        end
    end

    local function paintCell(self, pw, ph)
        local hov = self:IsHovered()
        local filled = istable(self._slot) and self._slot.id
        draw.RoundedBox(6, 0, 0, pw, ph, hov and Color(48, 72, 108, 250) or (filled and Color(30, 38, 52, 250) or Color(18, 22, 30, 250)))
        surface.SetDrawColor(filled and 70 or 42, filled and 150 or 52, filled and 230 or 70, hov and 220 or 140)
        surface.DrawOutlinedRect(0, 0, pw, ph, 1)
        if not filled then
            draw.SimpleText(tostring(self._idx or ""), "GRMTrunk_Small", pw / 2, ph / 2, Color(70, 82, 98), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end
        local icon = self._icon
        if isstring(icon) and icon ~= "" then
            local mat = Material(icon, "smooth")
            if mat and not mat:IsError() then
                surface.SetMaterial(mat)
                surface.SetDrawColor(255, 255, 255, 230)
                surface.DrawTexturedRect(pw / 2 - 12, 8, 24, 24)
            end
        end
        draw.SimpleText(self._name or "", "GRMTrunk_Small", pw / 2, ph - 18, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if (self._cnt or 1) > 1 then
            draw.SimpleText("×" .. tostring(self._cnt), "GRMTrunk_Small", pw - 6, 6, C.yellow, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end
    end

    local function fillGrid(host, slots, count, toTrunk)
        if not IsValid(host) then return end
        if GRM.UI and GRM.UI.SafeClear then GRM.UI.SafeClear(host) else host:Clear() end
        local cols, gap = 6, 6
        local canvas = host:GetCanvas()
        local wide = math.max(300, (IsValid(canvas) and canvas:GetWide() or host:GetWide()) - 12)
        local cell = math.floor((wide - (cols - 1) * gap) / cols)
        for i = 1, count do
            local slot = slots[i]
            local name, icon = itemLabel(slot)
            local b = vgui.Create("DButton", host)
            local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
            b:SetPos(c * (cell + gap), r * (cell + gap))
            b:SetSize(cell, cell)
            b:SetText("")
            b._idx, b._slot, b._name, b._icon, b._cnt = i, slot, name, icon, istable(slot) and (tonumber(slot.count) or 1) or 0
            b.Paint = paintCell
            b.DoClick = function()
                if not IsValid(TK._veh) then return end
                if not (istable(slot) and slot.id) then return end
                net.Start(NET_XFER)
                    net.WriteEntity(TK._veh)
                    net.WriteBool(toTrunk)
                    net.WriteUInt(i, 8)
                    net.WriteUInt(input.IsKeyDown(KEY_LSHIFT) and 1 or 999, 16)
                net.SendToServer()
            end
        end
        host:GetCanvas():SetTall(math.ceil(count / cols) * (cell + gap))
    end

    local function rebuild(scInv, scTrunk)
        if not IsValid(scInv) or not IsValid(scTrunk) then return end
        local inv = (GRM.Inventory and GRM.Inventory.LocalSlots) or {}
        fillGrid(scInv, inv, 24, true)
        fillGrid(scTrunk, TK._slots or {}, math.max(1, tonumber(TK._maxSlots) or 24), false)
    end

    local function stateLine()
        return string.format("%.1f / %.0f кг   ·   ЛКМ стак  ·  SHIFT+ЛКМ 1 шт.", TK._weight or 0, TK._maxWeight or 120)
    end

    local function openFrame()
        closeFrame()
        local f = vgui.Create("DFrame")
        TK._frame = f
        f:SetTitle("")
        f:SetSize(math.min(980, ScrW() - 40), math.min(620, ScrH() - 40))
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("trunk", f) end
        f.OnClose = function() sendClose() end
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, C.bg)
            draw.RoundedBoxEx(8, 0, 0, pw, 50, C.head, true, true, false, false)
            draw.SimpleText("БАГАЖНИК — " .. tostring(TK._vehName), "GRMTrunk_Title", 16, 16, Color(245, 195, 65))
            draw.SimpleText(stateLine(), "GRMTrunk_Small", 16, 36, C.dim)
        end
        local x = vgui.Create("DButton", f)
        x:SetText("✕") x:SetFont("GRMTrunk_Title") x:SetTextColor(color_white)
        x:SetSize(34, 30)
        x.DoClick = function() f:Close() end
        x.Paint = function(self, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and C.red or Color(45, 52, 68)) end
        x.Think = function(s) s:SetPos(f:GetWide() - 42, 10) end
        local slam = vgui.Create("DButton", f)
        slam:SetText("ЗАКРЫТЬ КРЫШКУ")
        slam:SetFont("GRMTrunk_Small")
        slam:SetTextColor(color_white)
        slam:SetSize(148, 26)
        slam.Paint = function(self, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and C.red or Color(90, 48, 52)) end
        slam.DoClick = function() sendClose(true); f:Close() end
        slam.Think = function(s) s:SetPos(f:GetWide() - 198, 12) end

        local lp = vgui.Create("DPanel", f)
        lp:Dock(LEFT) lp:SetWide(470) lp:DockMargin(12, 58, 6, 14) lp:SetPaintBackground(false)
        local lt = vgui.Create("DLabel", lp)
        lt:Dock(TOP) lt:SetTall(22) lt:SetFont("GRMTrunk_Sub") lt:SetTextColor(C.yellow) lt:SetText("ИНВЕНТАРЬ")
        local scInv = vgui.Create("DScrollPanel", lp)
        scInv:Dock(FILL)

        local rp = vgui.Create("DPanel", f)
        rp:Dock(FILL) rp:DockMargin(6, 58, 12, 14) rp:SetPaintBackground(false)
        local rt = vgui.Create("DLabel", rp)
        rt:Dock(TOP) rt:SetTall(22) rt:SetFont("GRMTrunk_Sub") rt:SetTextColor(C.green)
        rt:SetText("БАГАЖНИК  ·  " .. tostring(TK._maxSlots or 24) .. " ячеек")
        local scTrunk = vgui.Create("DScrollPanel", rp)
        scTrunk:Dock(FILL)

        hook.Add("GRM_InventoryUpdated", f, function() rebuild(scInv, scTrunk) end)
        f._rebuild = function() rebuild(scInv, scTrunk) end
        timer.Simple(0, function() if IsValid(f) then rebuild(scInv, scTrunk) end end)
    end

    net.Receive(NET_OPEN, function()
        TK._veh = net.ReadEntity()
        TK._slots = net.ReadTable() or {}
        TK._weight = net.ReadFloat() or 0
        TK._maxSlots = net.ReadUInt(8) or 24
        TK._maxWeight = net.ReadFloat() or 120
        TK._vehName = net.ReadString() or "Транспорт"
        openFrame()
    end)

    net.Receive(NET_SYNC, function()
        local veh = net.ReadEntity()
        if not IsValid(TK._frame) then return end
        if veh ~= TK._veh then return end
        TK._slots = net.ReadTable() or {}
        TK._weight = net.ReadFloat() or 0
        TK._maxSlots = net.ReadUInt(8) or 24
        TK._maxWeight = net.ReadFloat() or 120
        if TK._frame and TK._frame._rebuild then TK._frame._rebuild() end
    end)

    net.Receive(NET_CLOSE, function()
        local veh = net.ReadEntity()
        if veh == TK._veh then closeFrame() end
    end)

    -- 3D2D-метка: реестр меняется по NW-событию, без FindByClass("*") в кадре.
    local openTrunks=setmetatable({},{__mode="k"})
    hook.Add("EntityNetworkedVarChanged","GRM_Trunk_LidRegistry",function(ent,name,_,value)if name=="VK_TrunkOpen"then if value==true then openTrunks[ent]=true else openTrunks[ent]=nil end end end)
    hook.Add("EntityRemoved","GRM_Trunk_LidRegistryRemove",function(ent)openTrunks[ent]=nil end)
    timer.Simple(1,function()for _,veh in ipairs(ents.GetAll())do if IsValid(veh)and veh.GetNW2Bool and veh:GetNW2Bool("VK_TrunkOpen",false)then openTrunks[veh]=true end end end)
    local TK_LOCAL = Vector(0, 0, 0)
    local TK_ANG = Angle(0, 0, 90)
    local TK_BG = Color(14, 18, 26, 215)
    hook.Add("PostDrawTranslucentRenderables", "GRM_Trunk_Lid", function()
        local lp=LocalPlayer();if not IsValid(lp)then return end
        for veh in pairs(openTrunks)do if not IsValid(veh)or not veh:GetNW2Bool("VK_TrunkOpen",false)then openTrunks[veh]=nil elseif lp:GetPos():DistToSqr(veh:GetPos())<=300*300 then
            local mins,maxs=veh:OBBMins(),veh:OBBMaxs();local back=(mins and mins.y)and mins.y or-60
            TK_LOCAL.y=back-8;TK_LOCAL.z=(maxs and maxs.z or 60)*.5+30+math.sin(CurTime()*3)*3;local pos=veh:LocalToWorld(TK_LOCAL)
            TK_ANG.y=EyeAngles().y-90;local ang=TK_ANG
            cam.Start3D2D(pos,ang,.1);draw.RoundedBox(6,-110,-20,220,40,TK_BG);surface.SetDrawColor(C.yellow.r,C.yellow.g,C.yellow.b,220);surface.DrawOutlinedRect(-110,-20,220,40,2);draw.SimpleText("БАГАЖНИК ОТКРЫТ","GRMTrunk_3D",0,0,C.yellow,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER);cam.End3D2D();return
        end end
    end)

    print("[GRM Trunk] Клиент багажника v" .. TK.Version .. " загружен")
end
