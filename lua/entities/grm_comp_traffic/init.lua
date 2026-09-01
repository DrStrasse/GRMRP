--[[--------------------------------------------------------------------
    grm_comp_traffic — init.lua (Серверная часть)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_CompTraffic_Open")

function ENT:CanManage(ply)
    if GRM.CompAccess and GRM.CompAccess.GetRaw(self) ~= "" then
        return GRM.CompAccess.Allowed(self, ply)
    end
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    if ply:IsSuperAdmin() then return true end

    local fName = ply:GetNWString("GRM_Faction", "")
    if fName == "" then return false end

    if fName:lower():find("ordnung") or fName:lower():find("feldgendarmerie") or fName:lower():find("авто") or fName:lower():find("инспек") or fName:lower():find("police") then
        return true
    end

    if GRM.Documents and GRM.Documents.Templates and GRM.Documents.Templates.access then
        local acc = GRM.Documents.Templates.access
        if acc.licenses and acc.licenses[fName] == true then return true end
        if acc.milLicenses and acc.milLicenses[fName] == true then return true end
    end
    return false
end

function ENT:Use(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if not self:CanManage(ply) then
        if GRM.Notify then
            GRM.Notify(ply, "Доступ к терминалу разрешён инструкторам Автошколы, Дорожной Инспекции и ВАИ.", 255, 120, 100)
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
                role       = p:GetNWString("GRM_Role", ""),
                department = p:GetNWString("GRM_Department", ""),
            }
        end
    end

    local tpls = GRM.Documents and GRM.Documents.Templates or {}
    local reg  = GRM.Documents and GRM.Documents.Registry or {}

    net.Start("GRM_CompTraffic_Open")
        net.WriteEntity(self)
        net.WriteTable(onlineList)
        net.WriteTable(tpls)
        net.WriteTable(reg)
        net.WriteString(ply:GetNWString("GRM_Faction", "Дорожная Инспекция"))
        net.WriteBool(ply:IsSuperAdmin())
    net.Send(ply)
end
