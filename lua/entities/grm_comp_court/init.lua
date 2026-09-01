--[[--------------------------------------------------------------------
    grm_comp_court — init.lua (Серверная часть компьютера юстиции)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_CompCourt_Open")
util.AddNetworkString("GRM_CompCourt_Action")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then mdl = self.ModelFallback end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetComputerName() == "" then
        self:SetComputerName("ЮСТИЦИЯ • СУД И ПРОКУРАТУРА")
    end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
end

-- Юстиция: суперадмин, фракция-суд/прокуратура, либо обладатель прав розыска.
local function looksLikeJustice(fName)
    fName = string.lower(tostring(fName or ""))
    if fName == "" then return false end
    for _, w in ipairs({ "юстиц", "суд", "прокур", "правосуд", "justice", "court", "prokur", "адвокат" }) do
        if fName:find(w, 1, true) then return true end
    end
    return false
end

function ENT:CanManage(ply)
    if GRM.CompAccess and GRM.CompAccess.GetRaw(self) ~= "" then
        return GRM.CompAccess.Allowed(self, ply)
    end
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    if ply:IsSuperAdmin() then return true end
    if looksLikeJustice(ply:GetNWString("GRM_Faction", "")) then return true end
    local W = GRM.Wanted
    if W and isfunction(W.CanEdit) and W.CanEdit(ply) == true then return true end
    return false
end

local function keyOf(p)
    if GRM.Identity and isfunction(GRM.Identity.CharacterKey) then return GRM.Identity.CharacterKey(p) end
    return tostring(p:SteamID64() or "0") .. ":char1"
end

local function wantedList()
    local W = GRM.Wanted
    local out = {}
    if W and istable(W.Records) then
        for sid, r in pairs(W.Records) do
            if istable(r) and (r.jurisdiction ~= "military") and (r.level > 0 or #(r.reasons or {}) > 0) then
                local totalFine = 0
                for _, c in ipairs(r.reasons or {}) do totalFine = totalFine + (tonumber(c.fine) or 0) end
                out[#out + 1] = {
                    sid = sid, name = r.name or sid, level = tonumber(r.level) or 0,
                    reasons = #(r.reasons or {}), totalFine = totalFine, updated = r.updated,
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.level == b.level and a.name < b.name or a.level > b.level end)
    return out
end

local function catalogList()
    local W = GRM.Wanted
    local out = {}
    if W and istable(W.Catalog) then
        for _, a in ipairs(W.Catalog) do
            if istable(a) and a.jurisdiction ~= "military" then
                out[#out + 1] = a
            end
        end
    end
    return out
end

local function onlineList()
    local out = {}
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) then
            local rp = p:GetNWString("GRM_RPName", "")
            if rp == "" then rp = p:Nick() end
            out[#out + 1] = { key = keyOf(p), steamID64 = p:SteamID64() or "0", rpName = rp, nick = p:Nick() }
        end
    end
    return out
end

function ENT:Use(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if not self:CanManage(ply) then
        if GRM.Notify then
            GRM.Notify(ply, "Доступ к компьютеру юстиции — только судьям, прокуратуре и суперадминам.", 255, 120, 100)
        end
        return
    end

    local F = GRM.Wanted and GRM.Wanted.Fines
    local fines = {}
    if F and isfunction(F.Page) then
        fines = (F.Page("civil", { status = "unpaid" }, 0, 200))
    end

    local warrants = {}
    if GRM.Doors and GRM.Doors.ListWarrants then
        warrants = GRM.Doors.ListWarrants(nil, true)
    end

    net.Start("GRM_CompCourt_Open")
        net.WriteEntity(self)
        net.WriteTable({ name = self:GetComputerName(), isSuper = ply:IsSuperAdmin() })
        net.WriteTable(wantedList())
        net.WriteTable(catalogList())
        net.WriteTable(GRM.Wanted and GRM.Wanted.Levels or {})
        net.WriteTable(fines)
        net.WriteTable(onlineList())
        net.WriteTable(warrants)
    net.Send(ply)
end

-- Обработка действий юстиции (штрафы и судебные ордера)
net.Receive("GRM_CompCourt_Action", function(_, ply)
    if not IsValid(ply) then return end
    local ent = net.ReadEntity()
    if not IsValid(ent) or ent:GetClass() ~= "grm_comp_court" then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > 250 * 250 then return end
    if not ent:CanManage(ply) then return end

    local op = net.ReadString()
    local F = GRM.Wanted and GRM.Wanted.Fines

    if op == "fine_issue" then
        if not F then return end
        local targetKey = net.ReadString()
        local amount = math.floor(tonumber(net.ReadString()) or 0)
        local reason = net.ReadString()
        local article = net.ReadString()
        if targetKey == "" or amount <= 0 then return end
        local rec, err = F.Issue(ply, targetKey, amount, reason ~= "" and reason or "Судебное решение", { article = article, jurisdiction = "civil" })
        if GRM.Notify then
            if rec then GRM.Notify(ply, ("Штраф №%d выписан: %s — %s"):format(rec.id, rec.targetName or targetKey, tostring(rec.amount)), 120, 220, 140)
            else GRM.Notify(ply, tostring(err or "Не выписать штраф"), 255, 140, 100) end
        end
    elseif op == "fine_cancel" then
        if not F then return end
        local id = math.floor(tonumber(net.ReadString()) or 0)
        local reason = net.ReadString()
        if id <= 0 then return end
        local ok, err = F.Cancel(ply, id, reason ~= "" and reason or "решение суда")
        if GRM.Notify then
            if ok then GRM.Notify(ply, ("Штраф №%d аннулирован."):format(id), 120, 220, 140)
            else GRM.Notify(ply, tostring(err or "Не аннулировать"), 255, 140, 100) end
        end
    elseif op == "warrant_request" then
        local targetKey = net.ReadString()
        local wType = net.ReadString()
        local mins = net.ReadUInt(16)
        local reason = net.ReadString()
        local propId = net.ReadString()
        if GRM.Doors and GRM.Doors.RequestWarrant then
            local ok, w = GRM.Doors.RequestWarrant(ply, targetKey, wType, mins, reason, propId)
            if GRM.Notify then
                if ok then GRM.Notify(ply, "Ходатайство на судебный ордер подано.", 100, 220, 130)
                else GRM.Notify(ply, "Ошибка подачи ходатайства: " .. tostring(w), 255, 120, 100) end
            end
        end
    elseif op == "warrant_approve" then
        local warId = net.ReadString()
        local mins = net.ReadUInt(16)
        if GRM.Doors and GRM.Doors.ApproveWarrant then
            local ok, w = GRM.Doors.ApproveWarrant(ply, warId, mins)
            if GRM.Notify then
                if ok then GRM.Notify(ply, "Судебный ордер утверждён и вступил в силу!", 100, 220, 130)
                else GRM.Notify(ply, "Не удалось утвердить ордер: " .. tostring(w), 255, 120, 100) end
            end
        end
    elseif op == "warrant_reject" then
        local warId = net.ReadString()
        local reason = net.ReadString()
        if GRM.Doors and GRM.Doors.RejectWarrant then
            local ok = GRM.Doors.RejectWarrant(ply, warId, reason)
            if GRM.Notify then
                if ok then GRM.Notify(ply, "Ходатайство на ордер отклонено.", 235, 180, 80) end
            end
        end
    elseif op == "warrant_revoke" then
        local targetSid = net.ReadString()
        if GRM.Doors and GRM.Doors.RevokeWarrant then
            local ok = GRM.Doors.RevokeWarrant(ply, targetSid)
            if GRM.Notify then
                if ok then GRM.Notify(ply, "Судебный ордер отозван.", 235, 180, 80) end
            end
        end
    end
end)
