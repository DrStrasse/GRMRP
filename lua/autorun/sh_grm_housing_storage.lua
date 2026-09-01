--[[--------------------------------------------------------------------
    GRM Housing Storage v1.0.0 — домашнее хранилище (шкаф). Фаза 2.

    ЗАЧЕМ. Владелец на вопрос «что даёт жильё, кроме спавна» ответил «да»
    на хранилище, отдых и приватность. Отдых сделан в фазе 1, здесь —
    хранилище.

    ЧТО ЭТО. Шкаф (grm_home_locker), который ставится ВНУТРИ квартиры.
    Он не привязывается к владельцу руками: шкаф принадлежит тому
    объекту недвижимости, в чьей зоне стоит. Сменился хозяин квартиры —
    сменился и хозяин шкафа, вещи прежнего жильца остаются в шкафу
    (как оставленная мебель), и это осознанно: иначе продажа квартиры
    была бы способом телепортировать склад.

    ПОЧЕМУ НЕ СКОПИРОВАН БАГАЖНИК ЦЕЛИКОМ. Багажник (sh_grm_trunk)
    привязан к машине и её ключам, персист по владельцу+классу. Здесь
    ключ персиста — ID объекта недвижимости, а доступ считает
    GRM.Housing.CanEnter. Но принципы взяты оттуда, потому что они
    правильные и уже проверены боем:
      • слоты и вес, а не бесконечный ящик;
      • ВСЕ перекладывания только на сервере, клиент шлёт лишь намерение
        {слот, количество, направление} — иначе дюп предметов;
      • сервер сам читает актуальные слоты и клэмпит до наличия;
      • снапшот пересобирается ВСЕМ, кто смотрит в этот же шкаф.

    ДОСТУП. Кто может войти в квартиру — тот может открыть шкаф. Это
    сознательно: отдельный список ключей от шкафа только запутает.
    Исключение — ОРДЕР: полиция входит по ордеру и видит содержимое
    (это и есть обыск), но об этом узнает владелец (фаза 3).

    ДАННЫЕ: data/grm_home_lockers.json, ключ — ID объекта недвижимости.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.HomeStorage = GRM.HomeStorage or {}
local ST = GRM.HomeStorage

ST.Version   = "1.0.0"
ST.DataFile  = "grm_home_lockers.json"

--[[ Ёмкость. Меньше багажника по слотам, но тяжелее по весу: дома
     хранят запасы, а не возят их. Числа подобраны так, чтобы шкаф не
     заменял банковскую ячейку и не превращался в бездонный склад. ]]
ST.MaxSlots  = 30
ST.MaxWeight = 200
ST.WeaponWeight = 3.0
ST.UseRange  = 140

ST.Store = ST.Store or {}   -- [propertyID] = { slots = {} }

local NET_OPEN  = "GRM_HomeLocker_Open"
local NET_SYNC  = "GRM_HomeLocker_Sync"
local NET_CLOSE = "GRM_HomeLocker_Close"
local NET_XFER  = "GRM_HomeLocker_Xfer"

ST.NET = { OPEN = NET_OPEN, SYNC = NET_SYNC, CLOSE = NET_CLOSE, XFER = NET_XFER }

local function isWeaponId(id) return string.sub(tostring(id or ""), 1, 7) == "weapon:" end
ST.IsWeaponId = isWeaponId

--- Вес одного слота. Незарегистрированное оружие считаем по фиксу.
function ST.SlotWeight(slot)
    if not istable(slot) or not slot.id then return 0 end
    local def = GRM.Inventory and GRM.Inventory.GetItemDef and GRM.Inventory.GetItemDef(slot.id)
    local w = (istable(def) and tonumber(def.weight)) or ST.WeaponWeight
    return w * (tonumber(slot.count) or 1)
end

function ST.TotalWeight(slots)
    local sum = 0
    for _, s in pairs(slots or {}) do sum = sum + ST.SlotWeight(s) end
    return sum
end

--- Сколько слотов занято (для подписи на шкафу).
function ST.UsedSlots(slots)
    local n = 0
    for _, s in pairs(slots or {}) do
        if istable(s) and s.id then n = n + 1 end
    end
    return n
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_SYNC)
    util.AddNetworkString(NET_CLOSE)
    util.AddNetworkString(NET_XFER)

    local dirty = false

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    function ST.Load()
        ST.Store = {}
        if not file.Exists(ST.DataFile, "DATA") then return end
        local t = jsonT(file.Read(ST.DataFile, "DATA") or "")
        if not istable(t) then return end
        for id, rec in pairs(t) do
            if istable(rec) and istable(rec.slots) then
                ST.Store[tostring(id)] = { slots = rec.slots }
            end
        end
    end

    function ST.Save(reason)
        local ok, txt = pcall(util.TableToJSON, ST.Store or {}, true)
        if not (ok and txt) then
            ErrorNoHalt("[GRM HomeStorage] не удалось сохранить (" .. tostring(reason) .. ")\n")
            return false
        end
        file.Write(ST.DataFile, txt)
        dirty = false
        return true
    end

    --[[ Запись на диск дебаунсим: перекладывание вещей — частое событие,
         писать файл на каждый предмет нельзя. Но на выходе игрока и
         выключении сервера пишем сразу, иначе вещи пропадут (та же
         ошибка, что была с точками выхода). ]]
    local function markDirty()
        dirty = true
        timer.Remove("GRM_HomeStorage_Debounce")
        timer.Create("GRM_HomeStorage_Debounce", 8, 1, function()
            if dirty then ST.Save("дебаунс") end
        end)
    end
    ST.MarkDirty = markDirty

    -- Автосейв — low: терпит, и при просадке его отложат первым.
    if GRM.Sched then
        GRM.Sched.Every("homestorage.autosave", 120, function()
            if dirty then ST.Save("автосейв") end
        end, { prio = "low" })
    else
        timer.Create("GRM_HomeStorage_AutoSave", 120, 0, function()
            if dirty then ST.Save("автосейв") end
        end)
    end
    hook.Add("PlayerDisconnected", "GRM_HomeStorage_Disc", function()
        if dirty then ST.Save("дисконнект") end
    end)
    hook.Add("ShutDown", "GRM_HomeStorage_Shut", function() ST.Save("shutdown") end)

    ST.Load()

    -----------------------------------------------------------------
    -- ПРИВЯЗКА ШКАФА К КВАРТИРЕ
    -----------------------------------------------------------------
    --[[ Шкаф не хранит владельца сам. Он смотрит, в чьей зоне стоит.
         Так продажа квартиры автоматически передаёт шкаф новому хозяину
         и не остаётся «висячих» шкафов с чужими правами. ]]
    function ST.PropertyOf(ent)
        if not IsValid(ent) then return nil end
        local HS = GRM.Housing
        if not (HS and HS.HousingAt) then return nil end
        return HS.HousingAt(ent:GetPos())
    end

    --- Слоты шкафа этой квартиры (создаются лениво).
    function ST.SlotsFor(rec)
        if not istable(rec) then return nil end
        local id = tostring(rec.id or "")
        if id == "" then return nil end
        if not istable(ST.Store[id]) then
            ST.Store[id] = { slots = {} }
        end
        return ST.Store[id].slots, id
    end

    --[[ ДОСТУП К ШКАФУ. Ровно тот же, что и вход в квартиру: единая
         точка правды, чтобы права не разъехались. Отдельно возвращаем
         причину — она нужна для журнала обыска (фаза 3). ]]
    function ST.CanUse(ply, ent)
        if not IsValid(ply) then return false, "invalid", "Нет игрока" end
        if not IsValid(ent) then return false, "invalid", "Нет шкафа" end
        if ply:GetPos():DistToSqr(ent:GetPos()) > ST.UseRange * ST.UseRange then
            return false, "far", "Подойдите ближе."
        end
        local rec = ST.PropertyOf(ent)
        if not rec then
            --[[ Шкаф вне зоны жилья. Это ошибка установки: такой шкаф
                 ничей и открыть его может только админ, иначе получился
                 бы общедоступный склад посреди улицы. ]]
            local P = GRM.Property
            if P and P.CanAdmin and P.CanAdmin(ply) then
                return true, "admin_loose", "Шкаф вне зоны жилья"
            end
            return false, "no_property", "Шкаф не относится ни к одному жилью."
        end
        local HS = GRM.Housing
        if not (HS and HS.CanEnter) then return false, "no_module", "Модуль жилья не загружен" end
        local allowed, reason, text = HS.CanEnter(ply, rec)
        if not allowed then return false, reason, text end
        return true, reason, text, rec
    end

    -----------------------------------------------------------------
    -- ЗРИТЕЛИ И СНАПШОТЫ
    -----------------------------------------------------------------
    ST.Viewers = ST.Viewers or {}   -- [ent] = { [ply] = true }

    local function snapshotTo(ply, ent, rec, first)
        local slots = ST.SlotsFor(rec) or {}
        local name = tostring(rec and rec.name or "Жильё")
        net.Start(first and NET_OPEN or NET_SYNC)
            net.WriteEntity(ent)
            net.WriteTable(slots)
            net.WriteFloat(ST.TotalWeight(slots))
            net.WriteUInt(ST.MaxSlots, 8)
            net.WriteFloat(ST.MaxWeight)
            if first then net.WriteString(name) end
        net.Send(ply)
    end

    --- Разослать актуальные слоты всем, кто смотрит в этот шкаф.
    function ST.PushSnapshot(ent)
        -- Подпись на корпусе обновляем всегда, даже если зрителей нет:
        -- проходящий мимо должен видеть актуальную заполненность.
        if IsValid(ent) and ent.UpdateFill then ent:UpdateFill() end
        local set = ST.Viewers[ent]
        if not istable(set) then return end
        local rec = ST.PropertyOf(ent)
        for ply in pairs(set) do
            if IsValid(ply) then
                if rec then snapshotTo(ply, ent, rec, false) end
            else
                set[ply] = nil
            end
        end
    end

    function ST.Close(ply, ent)
        local set = ST.Viewers[ent]
        if istable(set) then set[ply] = nil end
        if IsValid(ply) then
            net.Start(NET_CLOSE) net.WriteEntity(ent) net.Send(ply)
        end
    end

    function ST.Open(ply, ent)
        local allowed, reason, text, rec = ST.CanUse(ply, ent)
        if not allowed then
            if GRM.Notify then GRM.Notify(ply, tostring(text or "Нет доступа"), 255, 120, 100) end
            return false
        end
        rec = rec or ST.PropertyOf(ent)
        if not rec then
            if GRM.Notify then GRM.Notify(ply, "Шкаф не относится ни к одному жилью.", 255, 120, 100) end
            return false
        end

        ST.Viewers[ent] = ST.Viewers[ent] or {}
        ST.Viewers[ent][ply] = true
        snapshotTo(ply, ent, rec, true)

        --[[ Вход по ордеру — это обыск. Отмечаем факт сразу: полная
             обработка (уведомление владельцу, журнал) будет в фазе 3,
             но событие бросаем уже сейчас, чтобы аудит не потерял его. ]]
        if reason == "warrant_property" or reason == "warrant_owner" then
            hook.Run("GRM_HomeStorageSearched", ply, rec, ent, reason)
            if GRM.Audit and GRM.Audit.Write then
                GRM.Audit.Write("housing", "storage.search", ply,
                    { propertyID = tostring(rec.id or "") }, { reason = reason })
            end
        end
        return true
    end

    -----------------------------------------------------------------
    -- ПЕРЕКЛАДЫВАНИЕ (анти-дюп: всё считает сервер)
    -----------------------------------------------------------------
    --[[ Положить в шкаф. Возвращает, сколько штук реально поместилось:
         из инвентаря списываем РОВНО это число, иначе получится дюп
         (при отказе) или потеря (при частичном влезании). ]]
    function ST.Deposit(slots, srcSlot, count)
        if not (istable(slots) and istable(srcSlot) and srcSlot.id) then return 0 end
        local id = tostring(srcSlot.id)
        local want = math.max(0, math.min(tonumber(count) or 1, tonumber(srcSlot.count) or 1))
        if want <= 0 then return 0 end

        local weight = ST.TotalWeight(slots)
        local def = GRM.Inventory and GRM.Inventory.GetItemDef and GRM.Inventory.GetItemDef(id)
        local unit = (istable(def) and tonumber(def.weight)) or ST.WeaponWeight
        local moved = 0

        -- Оружие не стакается: одна единица — один слот.
        if isWeaponId(id) then
            if weight + unit > ST.MaxWeight then return 0 end
            for i = 1, ST.MaxSlots do
                if not istable(slots[i]) or not slots[i].id then
                    slots[i] = { id = id, count = 1, data = srcSlot.data }
                    return 1
                end
            end
            return 0
        end

        local maxStack = (GRM.Inventory and GRM.Inventory.GetMaxStack
            and GRM.Inventory.GetMaxStack(id)) or 99

        -- Сначала добиваем существующие стаки, потом занимаем пустые слоты.
        for i = 1, ST.MaxSlots do
            if moved >= want then break end
            local s = slots[i]
            if istable(s) and s.id == id and not isWeaponId(id) then
                local room = maxStack - (tonumber(s.count) or 0)
                if room > 0 then
                    local byWeight = unit > 0 and math.floor((ST.MaxWeight - weight) / unit) or (want - moved)
                    local can = math.min(want - moved, room, math.max(0, byWeight))
                    if can > 0 then
                        s.count = (tonumber(s.count) or 0) + can
                        weight = weight + can * unit
                        moved = moved + can
                    end
                end
            end
        end
        for i = 1, ST.MaxSlots do
            if moved >= want then break end
            if not istable(slots[i]) or not slots[i].id then
                local byWeight = unit > 0 and math.floor((ST.MaxWeight - weight) / unit) or (want - moved)
                local can = math.min(want - moved, maxStack, math.max(0, byWeight))
                if can <= 0 then break end
                slots[i] = { id = id, count = can }
                weight = weight + can * unit
                moved = moved + can
            end
        end
        return moved
    end

    net.Receive(NET_XFER, function(_, ply)
        if not IsValid(ply) then return end
        local ent = net.ReadEntity()
        local toLocker = net.ReadBool()
        local slotIdx = tonumber(net.ReadUInt(8)) or 0
        local count = tonumber(net.ReadUInt(16)) or 1
        if not IsValid(ent) or slotIdx <= 0 then return end

        -- Клиенту не верим: права и дистанцию проверяем заново.
        local allowed, _, text, rec = ST.CanUse(ply, ent)
        if not allowed then
            if GRM.Notify then GRM.Notify(ply, tostring(text or "Нет доступа"), 255, 120, 100) end
            return
        end
        rec = rec or ST.PropertyOf(ent)
        if not rec then return end
        -- Только тот, кто реально открыл шкаф, может в нём копаться.
        if not (ST.Viewers[ent] and ST.Viewers[ent][ply]) then return end

        local slots = ST.SlotsFor(rec)
        if not slots then return end

        if toLocker then
            local inv = GRM.Inventory and GRM.Inventory.GetPlayerInv and GRM.Inventory.GetPlayerInv(ply)
            if not istable(inv) or not istable(inv.slots) then return end
            local src = inv.slots[slotIdx]
            if not (istable(src) and src.id) then return end

            local moved = ST.Deposit(slots, src, count)
            if moved <= 0 then
                if GRM.Notify then
                    GRM.Notify(ply, ("Не влезает: шкаф полон или перегруз (%d/%d кг)."):format(
                        math.floor(ST.TotalWeight(slots)), math.floor(ST.MaxWeight)), 255, 130, 110)
                end
                return
            end
            GRM.Inventory.RemoveFromSlot(ply, slotIdx, moved)
            markDirty()
            ST.PushSnapshot(ent)
        else
            local s = slots[slotIdx]
            if not (istable(s) and s.id) then return end

            if isWeaponId(s.id) then
                local cls = (istable(s.data) and s.data.class) or string.sub(tostring(s.id), 8)
                local okAdd = GRM.Inventory.AddWeapon(ply, cls,
                    (s.data and s.data.clip1) or 0, (s.data and s.data.clip2) or 0)
                if not okAdd then
                    if GRM.Notify then GRM.Notify(ply, "В инвентаре нет места.", 255, 130, 110) end
                    return
                end
                slots[slotIdx] = nil
            else
                local want = math.min(tonumber(count) or 1, tonumber(s.count) or 1)
                local leftover = GRM.Inventory.AddItem(ply, s.id, want)
                local moved = want - (tonumber(leftover) or 0)
                if moved <= 0 then
                    if GRM.Notify then GRM.Notify(ply, "В инвентаре нет места.", 255, 130, 110) end
                    return
                end
                s.count = (tonumber(s.count) or 1) - moved
                if (tonumber(s.count) or 0) <= 0 then slots[slotIdx] = nil end
            end
            markDirty()
            ST.PushSnapshot(ent)
        end
    end)

    net.Receive(NET_CLOSE, function(_, ply)
        local ent = net.ReadEntity()
        if IsValid(ent) and ST.Viewers[ent] then ST.Viewers[ent][ply] = nil end
    end)

    --[[ Отошёл от шкафа — окно закрывается само. Иначе можно открыть
         шкаф, уйти на другой конец карты и продолжать таскать вещи. ]]
    --[[ Контроль дистанции — normal: если игрок отошёл, окно должно
         закрыться быстро (иначе таскает вещи издалека), но это не
         критично для его состояния. `when` делает задачу бесплатной,
         когда ни один шкаф не открыт — а это почти всегда. ]]
    local function rangeCheck()
        for ent, set in pairs(ST.Viewers) do
            if not IsValid(ent) then ST.Viewers[ent] = nil
            else
                for ply in pairs(set) do
                    if not IsValid(ply) then set[ply] = nil
                    elseif ply:GetPos():DistToSqr(ent:GetPos()) > (ST.UseRange * 1.5) ^ 2 then
                        ST.Close(ply, ent)
                    end
                end
            end
        end
    end


    if GRM.Sched then
        GRM.Sched.Every("homestorage.range", 1, rangeCheck, {
            prio = "normal",
            when = function() return next(ST.Viewers) ~= nil end,
        })
    else
        timer.Create("GRM_HomeStorage_Range", 1, 0, rangeCheck)
    end

    --[[ Квартиру продали или сдали заново. Вещи прежнего жильца НЕ
         удаляем: это «оставленная мебель», новый хозяин получает их
         вместе с квартирой. Иначе продажа была бы бесплатным
         телепортом склада. Но окна у всех закрываем, чтобы никто не
         остался с открытым чужим шкафом. ]]
    hook.Add("GRM_PropertyOwnerChanged", "GRM_HomeStorage_Owner", function(rec)
        if not istable(rec) then return end
        for ent, set in pairs(ST.Viewers) do
            if IsValid(ent) then
                local cur = ST.PropertyOf(ent)
                if cur and tostring(cur.id) == tostring(rec.id) then
                    for ply in pairs(set) do ST.Close(ply, ent) end
                end
            end
        end
    end)

    --- Диагностика: grm_home_storage
    concommand.Add("grm_home_storage", function(ply)
        if not IsValid(ply) then return end
        local function say(t) ply:PrintMessage(HUD_PRINTTALK, t) end
        say("[Шкаф] хранилищ в базе: " .. tostring(table.Count(ST.Store)))
        local tr = ply:GetEyeTrace()
        local ent = tr and tr.Entity
        if IsValid(ent) and ent:GetClass() == "grm_home_locker" then
            local allowed, reason, text, rec = ST.CanUse(ply, ent)
            say("  шкаф под прицелом: доступ " .. (allowed and "да" or "нет")
                .. " (" .. tostring(reason) .. ") " .. tostring(text or ""))
            rec = rec or ST.PropertyOf(ent)
            if rec then
                local slots = ST.SlotsFor(rec)
                say("  жильё: " .. tostring(rec.name or rec.id)
                    .. " · занято слотов: " .. ST.UsedSlots(slots) .. "/" .. ST.MaxSlots
                    .. " · вес: " .. string.format("%.1f", ST.TotalWeight(slots)) .. "/" .. ST.MaxWeight)
            end
        else
            say("  наведитесь на шкаф, чтобы увидеть подробности")
        end
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("home_storage", {
            label = "Домашнее хранилище",
            version = ST.Version,
            Status = function() return "шкафов с вещами: " .. tostring(table.Count(ST.Store)) end,
            Depends = { "housing" },
        })
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then
    surface.CreateFont("GRMLocker_Title", { font = "Roboto", size = 21, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMLocker_Small", { font = "Roboto", size = 13, weight = 500, extended = true, antialias = true })

    local C = {
        bg   = Color(14, 19, 28, 250),
        head = Color(22, 30, 44, 255),
        text = Color(228, 236, 248),
        dim  = Color(148, 162, 182),
        gold = Color(245, 198, 70),
    }

    ST._slots, ST._weight, ST._maxSlots, ST._maxWeight = {}, 0, 30, 200

    local function itemLabel(slot)
        if not (istable(slot) and slot.id) then return "", "" end
        if isWeaponId(slot.id) then
            local cls = (istable(slot.data) and tostring(slot.data.class)) or string.sub(tostring(slot.id), 8)
            local wdef = weapons and weapons.Get and weapons.Get(cls)
            return "Оружие: " .. tostring((wdef and wdef.PrintName) or cls), "icon16/gun.png"
        end
        local def = GRM.Inventory and GRM.Inventory.GetItemDef and GRM.Inventory.GetItemDef(slot.id)
        if istable(def) then
            return tostring(def.name or slot.id), tostring(def.icon or "icon16/package.png")
        end
        return tostring(slot.id), "icon16/package.png"
    end

    local function closeFrame()
        if IsValid(ST._frame) then ST._frame:Remove() end
        ST._frame = nil
    end

    local function paintCell(self, w, h)
        local hov = self:IsHovered()
        local filled = istable(self._slot) and self._slot.id
        draw.RoundedBox(6, 0, 0, w, h, hov and Color(44, 66, 98, 250)
            or (filled and Color(28, 36, 50, 250) or Color(17, 21, 29, 250)))
        surface.SetDrawColor(filled and 70 or 40, filled and 145 or 50, filled and 220 or 68, hov and 220 or 130)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        if not filled then
            draw.SimpleText(tostring(self._idx or ""), "GRMLocker_Small", w / 2, h / 2,
                Color(66, 78, 94), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end
        if isstring(self._icon) and self._icon ~= "" then
            local mat = Material(self._icon, "smooth")
            if mat and not mat:IsError() then
                surface.SetMaterial(mat)
                surface.SetDrawColor(255, 255, 255, 230)
                surface.DrawTexturedRect(w / 2 - 12, 8, 24, 24)
            end
        end
        draw.SimpleText(self._name or "", "GRMLocker_Small", w / 2, h - 16, C.text,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if (self._cnt or 1) > 1 then
            draw.SimpleText("×" .. tostring(self._cnt), "GRMLocker_Small", w - 6, 6,
                C.gold, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end
    end

    local function fillGrid(host, slots, count, toLocker)
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
            b._idx, b._slot, b._name, b._icon = i, slot, name, icon
            b._cnt = istable(slot) and (tonumber(slot.count) or 1) or 0
            b.Paint = paintCell
            b.DoClick = function()
                if not IsValid(ST._ent) then return end
                if not (istable(slot) and slot.id) then return end
                net.Start(NET_XFER)
                    net.WriteEntity(ST._ent)
                    net.WriteBool(toLocker)
                    net.WriteUInt(i, 8)
                    -- SHIFT — одна штука, обычный клик — весь стак.
                    net.WriteUInt(input.IsKeyDown(KEY_LSHIFT) and 1 or 999, 16)
                net.SendToServer()
            end
        end
        host:GetCanvas():SetTall(math.ceil(count / cols) * (cell + gap))
    end

    local function rebuild()
        if not IsValid(ST._frame) then return end
        local inv = (GRM.Inventory and GRM.Inventory.LocalSlots) or {}
        fillGrid(ST._scInv, inv, 24, true)
        fillGrid(ST._scBox, ST._slots or {}, math.max(1, tonumber(ST._maxSlots) or 30), false)
    end

    local function openFrame(name)
        closeFrame()
        local f = vgui.Create("DFrame")
        ST._frame = f
        f:SetTitle("")
        f:SetSize(math.min(980, ScrW() - 40), math.min(620, ScrH() - 40))
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("home_locker", f) end
        f.OnClose = function()
            if IsValid(ST._ent) then
                net.Start(NET_CLOSE) net.WriteEntity(ST._ent) net.SendToServer()
            end
        end
        f.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 50, C.head, true, true, false, false)
            draw.SimpleText("ДОМАШНИЙ ШКАФ — " .. tostring(name or ""), "GRMLocker_Title",
                16, 14, C.gold)
            draw.SimpleText(("%.1f / %.0f кг   ·   ЛКМ — весь стак  ·  SHIFT+ЛКМ — одна штука"):format(
                ST._weight or 0, ST._maxWeight or 200), "GRMLocker_Small", 16, 34, C.dim)
        end

        local x = vgui.Create("DButton", f)
        x:SetText("✕") x:SetFont("GRMLocker_Title") x:SetTextColor(color_white)
        x:SetSize(34, 30)
        x:SetPos(f:GetWide() - 42, 10)
        x.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(170, 60, 60) or Color(48, 30, 34))
        end
        x.DoClick = function() f:Close() end

        local half = math.floor((f:GetWide() - 36) / 2)

        local lblL = vgui.Create("DLabel", f)
        lblL:SetPos(16, 58) lblL:SetSize(half, 18)
        lblL:SetFont("GRMLocker_Small") lblL:SetTextColor(C.dim)
        lblL:SetText("ВАШ ИНВЕНТАРЬ")

        local lblR = vgui.Create("DLabel", f)
        lblR:SetPos(26 + half, 58) lblR:SetSize(half, 18)
        lblR:SetFont("GRMLocker_Small") lblR:SetTextColor(C.dim)
        lblR:SetText("ШКАФ")

        ST._scInv = vgui.Create("DScrollPanel", f)
        ST._scInv:SetPos(16, 80)
        ST._scInv:SetSize(half, f:GetTall() - 96)

        ST._scBox = vgui.Create("DScrollPanel", f)
        ST._scBox:SetPos(26 + half, 80)
        ST._scBox:SetSize(half, f:GetTall() - 96)

        rebuild()
    end

    net.Receive(NET_OPEN, function()
        ST._ent = net.ReadEntity()
        ST._slots = net.ReadTable() or {}
        ST._weight = net.ReadFloat()
        ST._maxSlots = net.ReadUInt(8)
        ST._maxWeight = net.ReadFloat()
        local name = net.ReadString()
        openFrame(name)
    end)

    net.Receive(NET_SYNC, function()
        local ent = net.ReadEntity()
        ST._slots = net.ReadTable() or {}
        ST._weight = net.ReadFloat()
        ST._maxSlots = net.ReadUInt(8)
        ST._maxWeight = net.ReadFloat()
        if ent == ST._ent then rebuild() end
    end)

    net.Receive(NET_CLOSE, function()
        closeFrame()
        ST._ent = nil
    end)
end
