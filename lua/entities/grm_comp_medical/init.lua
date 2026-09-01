--[[--------------------------------------------------------------------
    grm_comp_medical — init.lua (Серверная часть)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_CompMedical_Open")
util.AddNetworkString("GRM_CompMedical_SaveCard")
util.AddNetworkString("GRM_CompMedical_IssuePhysical")

local function legacyCanManage(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    if ply:IsSuperAdmin() then return true end
    local fName = ply:GetNWString("GRM_Faction", "")
    if fName == "" then return false end

    local docAccess=GRM.Documents and GRM.Documents.Templates and GRM.Documents.Templates.access
    if docAccess and istable(docAccess.medicalComputer) and docAccess.medicalComputer[fName]==true then return true end
    local lower = fName:lower()
    if lower:find("мед") or lower:find("госпитал") or lower:find("врач") or lower:find("hospital") or lower:find("medic") then return true end
    return GRM.Medical and GRM.Medical.CanTreat and GRM.Medical.CanTreat(ply) == true or false
end

if GRM.Access and GRM.Access.Register then
    GRM.Access.Register("medical.computer.use", {
        label = "Медицинский компьютер: вход",
        legacy = function(ply) return legacyCanManage(ply), "legacy_medical" end,
    })
    GRM.Access.Register("medical.patient.edit", {
        label = "Медицина: изменение карты пациента",
        legacy = function(ply) return legacyCanManage(ply), "legacy_medical" end,
    })
end

function ENT:CanManage(ply)
    if GRM.CompAccess and GRM.CompAccess.GetRaw(self) ~= "" then
        return GRM.CompAccess.Allowed(self, ply)
    end
    if GRM.Access and GRM.Access.Can then
        return GRM.Access.Can(ply, "medical.computer.use", { entity = self }) == true
    end
    return legacyCanManage(ply)
end

function ENT:Use(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if not self:CanManage(ply) then
        if GRM.Notify then
            GRM.Notify(ply, "Доступ к медицинской базе разрешён только медицинскому персоналу госпиталя.", 255, 120, 100)
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

    local medCards = GRM.Medical and (GRM.Medical.Cards or {}) or {}

    net.Start("GRM_CompMedical_Open")
        net.WriteEntity(self)
        net.WriteTable(onlineList)
        net.WriteTable(medCards)
        net.WriteString(ply:GetNWString("GRM_Faction", "Госпиталь"))
        net.WriteBool(ply:IsSuperAdmin())
    net.Send(ply)
end

net.Receive("GRM_CompMedical_SaveCard", function(bits, ply)
    if not IsValid(ply) then return end
    if GRM.Net and GRM.Net.Guard then
        local allowed = GRM.Net.Guard(ply, "medical.card.save", {
            rate = 0.75, burst = 3, maxBits = 262144, capability = "medical.patient.edit",
        }, { bits = bits })
        if not allowed then return end
    elseif not legacyCanManage(ply) then return end
    local targetKey = net.ReadString()
    local cardData = net.ReadTable()
    if not isstring(targetKey) or targetKey == "" or not istable(cardData) then return end
    if GRM.Identity and GRM.Identity.IsCharacterKey and not GRM.Identity.IsCharacterKey(targetKey) then return end

    if GRM.Medical then
        GRM.Medical.Cards = GRM.Medical.Cards or {}
        cardData.updated = os.time()
        -- ЕДИНАЯ МЕДКАРТА: одна запись на персонажа, канонические справочники.
        if isfunction(GRM.Medical.NormalizeBlood) and cardData.blood ~= nil then
            cardData.blood = GRM.Medical.NormalizeBlood(cardData.blood)
        end
        if isfunction(GRM.Medical.NormalizeFitness) and cardData.fitnessCategory ~= nil then
            cardData.fitnessCategory = GRM.Medical.NormalizeFitness(cardData.fitnessCategory)
        end
        GRM.Medical.Cards[targetKey] = cardData

        if GRM.Medical.SaveCards then
            GRM.Medical.SaveCards("medical computer save by " .. ply:Nick())
        elseif GRM.Medical.Save then
            GRM.Medical.Save("medical computer save by " .. ply:Nick())
        end

        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("medical", "patient.card.save", ply,
                { characterKey = targetKey }, { patientName = cardData.name or "" })
        end
        if GRM.Notify then
            GRM.Notify(ply, "Медицинская карта [" .. tostring(cardData.name or targetKey) .. "] сохранена в базу данных.", 100, 220, 120)
        end
    end
end)

net.Receive("GRM_CompMedical_IssuePhysical", function(bits, ply)
    if not IsValid(ply) then return end
    if GRM.Net and GRM.Net.Guard then
        local allowed = GRM.Net.Guard(ply, "medical.card.issue", {
            rate = 1, burst = 2, maxBits = 8192, capability = "medical.patient.edit",
        }, { bits = bits })
        if not allowed then return end
    elseif not legacyCanManage(ply) then return end
    local targetKey = net.ReadString()
    if not isstring(targetKey) or targetKey == "" then return end
    if GRM.Identity and GRM.Identity.IsCharacterKey and not GRM.Identity.IsCharacterKey(targetKey) then return end

    local targetPly = nil
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        local k = (GRM.Identity and isfunction(GRM.Identity.CharacterKey) and GRM.Identity.CharacterKey(p)) or (p:SteamID64() .. ":char1")
        if k == targetKey or p:SteamID64() == targetKey then
            targetPly = p
            break
        end
    end

    if not IsValid(targetPly) then
        if GRM.Notify then GRM.Notify(ply, "Пациент не найден на сервере (офлайн).", 255, 120, 100) end
        return
    end

    if GRM.Inventory and GRM.Inventory.AddItem then
        local ok, err = GRM.Inventory.AddItem(targetPly, "medcard", 1, { sid64 = targetPly:SteamID64(), charKey = targetKey, patientName = targetPly:Nick() })
        if ok then
            if GRM.Audit and GRM.Audit.Write then
                GRM.Audit.Write("medical", "patient.card.issue_physical", ply,
                    { characterKey = targetKey, accountKey = targetPly:SteamID64() }, {})
            end
            if GRM.Notify then
                GRM.Notify(ply, "Физическая медицинская карта выдана пациенту " .. targetPly:Nick() .. ".", 100, 220, 120)
                GRM.Notify(targetPly, "Вам выдана на руки медицинская карта (в инвентаре).", 100, 220, 120)
            end
        else
            if GRM.Notify then GRM.Notify(ply, "Не удалось выдать карту: " .. tostring(err or "инвентарь переполнен"), 255, 100, 100) end
        end
    end
end)
