--[[--------------------------------------------------------------------
    grm_comp_cityhall — init.lua (Серверная часть компьютера мэрии)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_CityHall_Open")

local function looksLikeAdminFaction(fName)
    fName = string.lower(tostring(fName or ""))
    if fName == "" then return false end
    for _, w in ipairs({ "мэр", "администрац", "правитель", "правител", "городск", "city", "mayor", "govern", "labour", "труд" }) do
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
    local DOC = GRM.Documents
    if DOC and isfunction(DOC.CanIssueBusinessLicenses) and DOC.CanIssueBusinessLicenses(ply) then return true end
    if looksLikeAdminFaction(ply:GetNWString("GRM_Faction", "")) then return true end
    return false
end

local function overview()
    local DOC = GRM.Documents
    local E = GRM.Economy
    local S = GRM.Services
    local budget = 0
    if GRM.CityBudgetGet then budget = GRM.CityBudgetGet()
    elseif GRM.StateBudgetGet then budget = GRM.StateBudgetGet()
    elseif E and isfunction(E.StateBudgetGet) then budget = E.StateBudgetGet() end

    local business = {}
    if DOC and DOC.Registry and istable(DOC.Registry.businessLicenses) then
        for key, rec in pairs(DOC.Registry.businessLicenses) do
            if istable(rec) then
                business[#business + 1] = {
                    key = key,
                    name = rec.businessName or rec.fullName or "?",
                    owner = rec.fullName or "?",
                    type = rec.businessTypeName or rec.businessType or "—",
                    number = rec.number or "БЛ-?",
                    status = rec.status or "Действительна",
                }
            end
        end
    end
    table.sort(business, function(a, b) return (a.name or "") < (b.name or "") end)

    return {
        budget        = budget,
        business      = business,
        businessCount = #business,
        servicesCount = (S and istable(S.Catalog)) and table.Count(S.Catalog) or 0,
        invoicesCount = (S and istable(S.Invoices)) and #S.Invoices or 0,
        unpaidCount   = (S and istable(S.Invoices)) and (function()
            local n = 0
            for _, inv in ipairs(S.Invoices) do if inv.status == "unpaid" then n = n + 1 end end
            return n
        end)() or 0,
    }
end

function ENT:Use(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if not self:CanManage(ply) then
        if GRM.Notify then
            GRM.Notify(ply, "Доступ к компьютеру мэрии — только администрации города и суперадминам.", 255, 120, 100)
        end
        return
    end

    local onlineList = {}
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) then
            local rp = p:GetNWString("GRM_RPName", "")
            if rp == "" then rp = p:Nick() end
            local key = (GRM.Identity and isfunction(GRM.Identity.CharacterKey) and GRM.Identity.CharacterKey(p)) or (p:SteamID64() .. ":char1")
            onlineList[#onlineList + 1] = {
                key        = key,
                steamID64  = p:SteamID64() or "0",
                rpName     = rp,
                nick       = p:Nick(),
                faction    = p:GetNWString("GRM_Faction", ""),
            }
        end
    end

    local DOC = GRM.Documents
    local tpls = (DOC and DOC.Templates) or {}
    local bizTpl = tpls.businessLicense or {}
    local fee = (istable(tpls.fees) and tonumber(tpls.fees.businessLicense)) or 3000

    net.Start("GRM_CityHall_Open")
        net.WriteEntity(self)
        net.WriteTable(onlineList)
        net.WriteTable({ prefix = bizTpl.defaultPrefix or "БЛ-", issuer = bizTpl.defaultIssuer or "Экономическое управление", fee = fee })
        net.WriteTable(overview())
        net.WriteBool(ply:IsSuperAdmin())
    net.Send(ply)
end
