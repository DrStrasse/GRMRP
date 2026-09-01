--[[--------------------------------------------------------------------
    grm_comp_security — init.lua (Серверная часть)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_CompSecurity_Open")

function ENT:CanManage(ply)
    if GRM.CompAccess and GRM.CompAccess.GetRaw(self) ~= "" then
        return GRM.CompAccess.Allowed(self, ply)
    end
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    if ply:IsSuperAdmin() then return true end

    -- Единый источник истины — реестр агентов спецслужбы. Он же покрывает
    -- отделы, должности и персональные допуски, которых здесь не было.
    local SS = GRM.SpecialService
    if SS and isfunction(SS.IsAgent) and SS.IsAgent(ply) then return true end

    local fName = ply:GetNWString("GRM_Faction", "")
    if fName == "" then return false end

    if fName:lower():find("gestapo") or fName:lower():find("komitet") or fName:lower():find("комитет") or fName:lower():find("сгб") or fName:lower():find("security") then
        return true
    end

    if GRM.Documents and GRM.Documents.Templates and GRM.Documents.Templates.access then
        local acc = GRM.Documents.Templates.access
        if acc.coverDocs and acc.coverDocs[fName] == true then return true end
    end
    return false
end

function ENT:Use(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if not self:CanManage(ply) then
        if GRM.Notify then
            GRM.Notify(ply, "Доступ строго ограничен. Терминал Службы Государственной Безопасности.", 255, 60, 60)
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

    -- Спецслужба видит всё, но отдавать в net-сообщении базу целиком
    -- нельзя: лимит 64 КБ. Берём срез обеих юрисдикций через общий
    -- сборщик терминалов (он же прячет то, что прятать не нужно).
    local wantedRecords = {}
    local T = GRM.CompTerminal
    if T and isfunction(T.WantedSlice) then
        wantedRecords = T.WantedSlice("all", T.MaxRecordsSent or 150, true)
    else
        local n = 0
        for k, r in pairs((GRM.Wanted and GRM.Wanted.Records) or {}) do
            if n >= 150 then break end
            wantedRecords[k] = r
            n = n + 1
        end
    end

    local tpls = GRM.Documents and GRM.Documents.Templates or {}
    local reg  = GRM.Documents and GRM.Documents.Registry or {}
    local medCards = GRM.Medical and GRM.Medical.Cards or {}

    -- Образование субъектов учёта: диплом — такой же установочный
    -- признак, как военный билет. Шлём только по онлайн-списку, чтобы
    -- не упереться в лимит net-сообщения.
    local diplomas = {}
    local D = GRM.Diplomas
    if D and isfunction(D.For) then
        for _, pd in ipairs(onlineList) do
            local recs = D.For(pd.key, true) or {}
            if #recs > 0 then
                local out = {}
                for _, r in ipairs(recs) do
                    out[#out + 1] = {
                        number      = r.number,
                        institution = r.institution,
                        specialty   = r.specialty,
                        levelName   = isfunction(D.LevelName) and D.LevelName(r.level) or tostring(r.level or ""),
                        formName    = isfunction(D.FormName) and D.FormName(r.form) or tostring(r.form or ""),
                        issued      = r.issued,
                        revoked     = r.revoked == true,
                    }
                end
                diplomas[pd.key] = out
            end
        end
    end

    net.Start("GRM_CompSecurity_Open")
        net.WriteEntity(self)
        net.WriteTable(onlineList)
        net.WriteTable(tpls)
        net.WriteTable(reg)
        net.WriteTable(wantedRecords)
        net.WriteTable(medCards)
        net.WriteTable(diplomas)
        net.WriteTable((GRM.SpecialService and isfunction(GRM.SpecialService.CaseRows))
            and GRM.SpecialService.CaseRows() or {})
        net.WriteString(ply:GetNWString("GRM_Faction", "Gestapo"))
        net.WriteBool(ply:IsSuperAdmin())
    net.Send(ply)
end
