--[[--------------------------------------------------------------------
    Сеть автоматов: касса, владелец, инкассация.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.VendingBiz = GRM.VendingBiz or {}
local VB = GRM.VendingBiz
VB.BuyPrice = 8000

if CLIENT then
    hook.Add("PlayerButtonDown", "GRM_VendingBiz_G", function(ply, button)
        if button ~= KEY_G or ply ~= LocalPlayer() then return end
        local tr = ply:GetEyeTrace()
        local ent = IsValid(tr.Entity) and tr.Entity
        if not (IsValid(ent) and ent:GetClass() == "grm_vending_machine") then return end
        if ply:GetPos():DistToSqr(ent:GetPos()) > 220 * 220 then return end
        local onIncass = ply:GetNWEntity("GRM_IncassMyCar", NULL)
        if IsValid(onIncass) or (ply:GetNWInt("GRMIncass_BagAmount", 0) or 0) > 0 then
            RunConsoleCommand("grm_vending_incass")
            return true
        end
    end)
    return
end

util.AddNetworkString("GRM_Vending_Biz")

local function keyOf(ply)
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return IsValid(ply) and (ply:SteamID64() .. ":char1") or ""
end

function VB.GetCash(ent)
    if not IsValid(ent) then return 0 end
    return math.max(0, math.floor(ent:GetNWInt("GRM_VendCash", 0)))
end

function VB.SetCash(ent, n)
    if not IsValid(ent) then return end
    ent:SetNWInt("GRM_VendCash", math.max(0, math.floor(tonumber(n) or 0)))
    ent.GRMVendDirty = true
    if VB.MarkDirty then VB.MarkDirty() end
end

--[[ Продажа: деньги в кассу плюс СЧЁТЧИКИ за всё время. Раньше считалась
     только текущая касса, поэтому после снятия денег история продаж
     исчезала и «общая сумма» нигде не хранилась. ]]
function VB.AddSale(ent, price)
    if not IsValid(ent) then return end
    local p = math.max(0, math.floor(tonumber(price) or 0))
    if p <= 0 then return end
    VB.SetCash(ent, VB.GetCash(ent) + p)
    ent.GRMVendSold = math.max(0, math.floor(tonumber(ent.GRMVendSold) or 0)) + 1
    ent.GRMVendEarned = math.max(0, math.floor(tonumber(ent.GRMVendEarned) or 0)) + p
    ent:SetNWInt("GRM_VendSold", ent.GRMVendSold)
    ent:SetNWInt("GRM_VendEarned", ent.GRMVendEarned)
    if VB.MarkDirty then VB.MarkDirty() end
end

--- Итоги автомата за всё время: штук продано и сколько заработано.
function VB.GetStats(ent)
    if not IsValid(ent) then return 0, 0 end
    return math.max(0, math.floor(tonumber(ent.GRMVendSold) or 0)),
        math.max(0, math.floor(tonumber(ent.GRMVendEarned) or 0))
end

function VB.GetOwner(ent)
    if not IsValid(ent) then return "" end
    return tostring(ent:GetNWString("GRM_VendOwner", "") or "")
end

function VB.IsOwner(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return false end
    if ply:IsSuperAdmin() then return true end
    return VB.GetOwner(ent) == keyOf(ply)
end

function VB.Claim(ply, ent)
    if not IsValid(ply) or not IsValid(ent) or ent:GetClass() ~= "grm_vending_machine" then
        return false, "Нет автомата"
    end
    if ply:GetPos():DistToSqr(ent:GetPos()) > 200 * 200 then return false, "Подойдите ближе" end
    local cur = VB.GetOwner(ent)
    if cur ~= "" and cur ~= keyOf(ply) and not ply:IsSuperAdmin() then
        return false, "Автомат уже принадлежит другому"
    end
    --[[ Правило владельца: одиночная точка выкупается лично, а точка
         внутри бизнес-зоны или в скоплении — только через бизнес. ]]
    if GRM.Estate and GRM.Estate.CanOwnStandalone and cur == "" and not ply:IsSuperAdmin() then
        local can, why = GRM.Estate.CanOwnStandalone(ent)
        if not can then return false, tostring(why or "Нужна бизнес-зона") end
    end
    local price = VB.BuyPrice
    if cur == "" then
        if GRM.HasMoney and not GRM.HasMoney(ply, price) then
            return false, "Нужно " .. tostring(price) .. " GRM, чтобы выкупить автомат"
        end
        if GRM.TakeMoney then GRM.TakeMoney(ply, price, "покупка автомата") end
    end
    local k = keyOf(ply)
    ent:SetNWString("GRM_VendOwner", k)
    ent.GRMVendOwner = k
    if VB.MarkDirty then VB.MarkDirty() end
    if VB.Persist then VB.Persist(true) end
    return true, cur == "" and ("Автомат куплен за " .. price .. " GRM") or "Вы владелец этого автомата"
end

function VB.Withdraw(ply, ent)
    --[[ Автомат внутри оформленной бизнес-зоны принадлежит бизнесу: его
         касса снимается через окно бизнеса. Иначе прежний владелец
         автомата обходил бы владельца зоны и забирал выручку себе. ]]
    if GRM.Estate and GRM.Estate.ZoneAt and IsValid(ent) then
        local zone = GRM.Estate.ZoneAt(ent:GetPos())
        if zone and GRM.Estate.IsBusiness(zone) then
            if not (GRM.Estate.IsOwner(ply, zone) or (IsValid(ply) and ply:IsSuperAdmin())) then
                return false, "Автомат принадлежит бизнесу «" .. tostring(zone.name or "") .. "»"
            end
            return GRM.Estate.Collect(ply, zone)
        end
    end
    if not VB.IsOwner(ply, ent) then return false, "Это не ваш автомат" end
    local cash = VB.GetCash(ent)
    if cash <= 0 then return false, "Касса пуста" end
    VB.SetCash(ent, 0)
    if GRM.GiveMoney then GRM.GiveMoney(ply, cash, "касса автомата") end
    return true, "Снято " .. cash .. " GRM"
end

-- Патч покупки: после списания кладём выручку в кассу.
hook.Add("Think", "GRM_VendingBiz_HookBuy", function()
    hook.Remove("Think", "GRM_VendingBiz_HookBuy")
    -- хук вызывается из патча ниже через GRM.VendingBiz.AddSale
end)

-- Расширяем сохранение автоматов: owner + cash.
timer.Simple(2, function()
    local oldSave = GRM.Food and GRM.Food.SaveVendingMachines
    if not isfunction(oldSave) then return end
    -- данные пишем поверх JSON после штатного сейва
end)

--[[ СОХРАНЕНИЕ БИЗНЕС-ДАННЫХ.

     Было: строки файла сопоставлялись с автоматами по ПОРЯДКОВОМУ НОМЕРУ
     в ents.FindByClass. Порядок сущностей в GMod не гарантирован, поэтому
     после рестарта касса и владелец могли уехать к чужому автомату, а при
     любом изменении числа автоматов — потеряться совсем.

     Стало: привязка по позиции на карте. Автомат стоит там же, где стоял,
     значит его данные найдутся однозначно. ]]
local function posKey(vec)
    if not vec then return "" end
    return string.format("%.0f:%.0f:%.0f", vec.x or 0, vec.y or 0, vec.z or 0)
end

local function rowPos(row)
    if not istable(row) or not istable(row.pos) then return "" end
    return posKey({ x = tonumber(row.pos.x) or 0, y = tonumber(row.pos.y) or 0,
        z = tonumber(row.pos.z) or 0 })
end

local dirty = false
function VB.MarkDirty() dirty = true end

local function persistOverlay(force)
    if not (GRM.Food and file) then return end
    if not force and not dirty then return end
    dirty = false
    local map = string.lower(game.GetMap() or "unknown")
    local path = "grm_food/vending_" .. map .. ".json"
    if not file.Exists(path, "DATA") then return end
    local ok, data = pcall(util.JSONToTable, file.Read(path, "DATA") or "", false, true)
    if not (ok and istable(data)) then return end

    local byPos = {}
    for _, ent in ipairs(ents.FindByClass("grm_vending_machine")) do
        if IsValid(ent) then byPos[posKey(ent:GetPos())] = ent end
    end

    local changed = false
    for _, row in ipairs(data) do
        local ent = byPos[rowPos(row)]
        if IsValid(ent) and istable(row) then
            local sold, earned = VB.GetStats(ent)
            row.owner = VB.GetOwner(ent)
            row.cash = VB.GetCash(ent)
            row.sold = sold
            row.earned = earned
            changed = true
        end
    end
    if not changed then return end
    local encOk, enc = pcall(util.TableToJSON, data, true)
    if encOk and enc then file.Write(path, enc) end
end
VB.Persist = persistOverlay

-- Раз в 20 с, но только если что-то менялось; на выключении — обязательно.
timer.Create("GRM_VendingBiz_Persist", 20, 0, function() persistOverlay(false) end)
hook.Add("ShutDown", "GRM_VendingBiz_Persist", function() persistOverlay(true) end)

hook.Add("InitPostEntity", "GRM_VendingBiz_Restore", function()
    timer.Simple(3, function()
        local map = string.lower(game.GetMap() or "unknown")
        local path = "grm_food/vending_" .. map .. ".json"
        if not file.Exists(path, "DATA") then return end
        local ok, data = pcall(util.JSONToTable, file.Read(path, "DATA") or "", false, true)
        if not (ok and istable(data)) then return end

        local byPos = {}
        for _, ent in ipairs(ents.FindByClass("grm_vending_machine")) do
            if IsValid(ent) then byPos[posKey(ent:GetPos())] = ent end
        end
        for _, row in ipairs(data) do
            local ent = byPos[rowPos(row)]
            if IsValid(ent) and istable(row) then
                if isstring(row.owner) and row.owner ~= "" then
                    ent:SetNWString("GRM_VendOwner", row.owner)
                    ent.GRMVendOwner = row.owner
                end
                if tonumber(row.cash) then ent:SetNWInt("GRM_VendCash", math.floor(row.cash)) end
                ent.GRMVendSold = math.max(0, math.floor(tonumber(row.sold) or 0))
                ent.GRMVendEarned = math.max(0, math.floor(tonumber(row.earned) or 0))
                ent:SetNWInt("GRM_VendSold", ent.GRMVendSold)
                ent:SetNWInt("GRM_VendEarned", ent.GRMVendEarned)
            end
        end
    end)
end)

net.Receive("GRM_Vending_Biz", function(_, ply)
    if not IsValid(ply) then return end
    local op = net.ReadString()
    local ent = net.ReadEntity()
    local ok, msg
    if op == "claim" then ok, msg = VB.Claim(ply, ent)
    elseif op == "withdraw" then ok, msg = VB.Withdraw(ply, ent)
    else return end
    if GRM.Notify then GRM.Notify(ply, tostring(msg), ok and 100 or 255, ok and 220 or 140, 110) end
end)

-- Инкассация: изъять кассу как у банкомата.
function VB.CollectForIncass(ply, ent)
    local I = GRM.Incass
    if not (I and I.CollectFromTerminal) then return false, "Инкассация не загружена" end
    if not IsValid(ent) or ent:GetClass() ~= "grm_vending_machine" then return false, "Нет автомата" end
    local cash = VB.GetCash(ent)
    if cash <= 0 then return false, "В автомате нет наличных" end
    -- временно маскируем под терминал: кладём сумму и зовём ту же выдачу чемодана
    if not I.GiveBagWeapon then return false, "Нет чемодана" end
    local runOK
    for _, r in pairs(I.ActiveRuns or {}) do
        if IsValid(r.driver) and r.driver == ply then runOK = r break end
    end
    if not runOK then return false, "Нет активного рейса /incass" end
    if I.PlayerBagAmount(ply) > 0 then return false, "Сначала сдайте чемодан" end
    local take = math.min(cash, I.Config.BagChunk or 50000)
    VB.SetCash(ent, cash - take)
    local w = I.GiveBagWeapon(ply, take)
    if not IsValid(w) then VB.SetCash(ent, cash) return false, "Не выдан чемодан" end
    if I.Notify then I.Notify(ply, "Из автомата изъято " .. take .. " GRM", 100, 220, 130) end
    return true, take
end

concommand.Add("grm_vending_incass", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local ent = IsValid(tr.Entity) and tr.Entity or nil
    if not (IsValid(ent) and ent:GetClass() == "grm_vending_machine") then
        for _, e in ipairs(ents.FindByClass("grm_vending_machine")) do
            if ply:GetPos():DistToSqr(e:GetPos()) < 220 * 220 then ent = e break end
        end
    end
    if not IsValid(ent) then return end
    local ok, err = VB.CollectForIncass(ply, ent)
    if not ok and GRM.Notify then GRM.Notify(ply, tostring(err), 255, 140, 110) end
end)

hook.Add("PlayerSay", "GRM_VendingBiz_Chat", function(ply, text)
    local low = string.lower(string.Trim(tostring(text or "")))
    if low ~= "/vending_buy" and low ~= "/автомат" then return end
    local tr = ply:GetEyeTrace()
    local ent = IsValid(tr.Entity) and tr.Entity
    if not (IsValid(ent) and ent:GetClass() == "grm_vending_machine") then
        ply:ChatPrint("[Автомат] Смотрите на автомат: /vending_buy")
        return ""
    end
    local ok, msg = VB.Claim(ply, ent)
    ply:ChatPrint("[Автомат] " .. tostring(msg))
    return ""
end)

print("[GRM VendingBiz] loaded")
