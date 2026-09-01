--[[--------------------------------------------------------------------
    grm_doc_computer — init.lua (Серверная часть)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_DocComp_Open")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetComputerName() == "" then
        self:SetComputerName("Компьютер оформления документов")
    end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:EnableMotion(false)
    end
end

function ENT:CanManage(ply)
    if GRM.CompAccess and GRM.CompAccess.GetRaw(self) ~= "" then
        return GRM.CompAccess.Allowed(self, ply)
    end
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    if ply:IsSuperAdmin() then return true end

    local fName = ply:GetNWString("GRM_Faction", "")
    if fName == "" then return false end

    -- Лидер фракции
    if _G.FactionsAPI and _G.FactionsAPI.IsLeader and _G.FactionsAPI.IsLeader(ply, fName) then
        return true
    end

    -- Доступы из шаблонов
    if GRM.Documents and GRM.Documents.Templates and GRM.Documents.Templates.access then
        local acc = GRM.Documents.Templates.access
        if acc.passports and acc.passports[fName] == true then return true end
        if acc.badges and acc.badges[fName] == true then return true end
        if acc.military and acc.military[fName] == true then return true end
        if acc.licenses and acc.licenses[fName] == true then return true end
        if acc.milLicenses and acc.milLicenses[fName] == true then return true end
        if acc.weaponLicenses and acc.weaponLicenses[fName] == true then return true end
        if acc.businessLicenses and acc.businessLicenses[fName] == true then return true end
        if acc.coverDocs and acc.coverDocs[fName] == true then return true end
    end

    return true
end

function ENT:Use(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if not self:CanManage(ply) then
        if GRM.Notify then
            GRM.Notify(ply, "Доступ к служебному компьютеру разрешён только сотрудникам ведомств и руководству.", 255, 120, 100)
        end
        return
    end

    local onlineList = {}
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) then
            local rp = (p.GetNWString and p:GetNWString("GRM_RPName", ""))
            if not isstring(rp) or rp == "" then rp = p:Nick() end
            local key = (GRM.Identity and isfunction(GRM.Identity.CharacterKey) and GRM.Identity.CharacterKey(p)) or (p:SteamID64() .. ":char1")
            local fac = p:GetNWString("GRM_Faction", "")
            local role = p:GetNWString("GRM_Role", "")
            local dept = p:GetNWString("GRM_Department", "")

            onlineList[#onlineList + 1] = {
                key        = key,
                steamID64  = p:SteamID64() or "0",
                rpName     = rp,
                nick       = p:Nick(),
                faction    = fac,
                role       = role,
                department = dept,
            }
        end
    end

    local tpls = GRM.Documents and GRM.Documents.Templates or {}
    local reg  = GRM.Documents and GRM.Documents.Registry or { passports = {}, badges = {}, coverBadges = {}, military = {}, licenses = {}, milLicenses = {}, weaponLicenses = {}, businessLicenses = {} }
    local myFac = ply:GetNWString("GRM_Faction", "")
    local isLeader = (_G.FactionsAPI and _G.FactionsAPI.IsLeader and myFac ~= "" and _G.FactionsAPI.IsLeader(ply, myFac)) == true
    local hasCover = (ply:IsSuperAdmin() or (tpls.access and tpls.access.coverDocs and tpls.access.coverDocs[myFac] == true)) == true
    local hasPassport = (ply:IsSuperAdmin() or (tpls.access and tpls.access.passports and tpls.access.passports[myFac] == true)) == true
    local hasMilitary = (ply:IsSuperAdmin() or (tpls.access and tpls.access.military and tpls.access.military[myFac] == true)) == true
    local hasLicense  = (ply:IsSuperAdmin() or (tpls.access and tpls.access.licenses and tpls.access.licenses[myFac] == true)) == true
    local hasMilLicense = (ply:IsSuperAdmin() or (tpls.access and tpls.access.milLicenses and tpls.access.milLicenses[myFac] == true) or (tpls.access and tpls.access.military and tpls.access.military[myFac] == true)) == true
    local hasWeaponLicense = (ply:IsSuperAdmin() or (tpls.access and tpls.access.weaponLicenses and tpls.access.weaponLicenses[myFac] == true)) == true
    local hasBusinessLicense = (ply:IsSuperAdmin() or (tpls.access and tpls.access.businessLicenses and tpls.access.businessLicenses[myFac] == true)) == true

    net.Start("GRM_DocComp_Open")
        net.WriteEntity(self)
        net.WriteTable(onlineList)
        net.WriteTable(tpls)
        net.WriteTable(reg)
        net.WriteString(myFac)
        net.WriteBool(ply:IsSuperAdmin())
        net.WriteBool(isLeader)
        net.WriteBool(hasCover)
        net.WriteBool(hasPassport)
        net.WriteBool(hasMilitary)
        net.WriteBool(hasLicense)
        net.WriteBool(hasMilLicense)
        net.WriteBool(hasWeaponLicense)
        net.WriteBool(hasBusinessLicense)
    net.Send(ply)
end
