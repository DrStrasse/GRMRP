--[[--------------------------------------------------------------------
    GRM Faction Roster v1.1.0 — /members и /leaders
    /leaders — всем; /members — свой состав, суперадмину все составы.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM=GRM or{}
GRM.FactionRoster=GRM.FactionRoster or{}
local R=GRM.FactionRoster
R.Version="1.1.0"

local function resolve(characterKey)
    return GRM.Identity and GRM.Identity.ResolveCharacter and GRM.Identity.ResolveCharacter(characterKey) or nil
end

local function nameOf(characterKey,rec)
    local ply=resolve(characterKey)
    if IsValid(ply) then
        local name=ply:GetNWString("GRM_RPName","")
        return name~="" and name or ply:Nick()
    end
    local account,slot=tostring(characterKey):match("^(.-):(char[1-3])$")
    local chars=account and GRM.Char and GRM.Char.Data and GRM.Char.Data[account]
    local ch=chars and chars.slots and chars.slots[slot]
    return ch and ch.name or (rec and (rec.Name or rec.name)) or tostring(characterKey)
end

local function factionOf(ply)
    for name,faction in pairs(Factions or{}) do
        if GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(faction,ply) then return name,faction end
    end
end

local function dutyStatus(characterKey,ply)
    local saved=GRM.FactionDuty and GRM.FactionDuty.State and GRM.FactionDuty.State[characterKey]
    if IsValid(ply) then
        local onDuty=GRM.FactionDuty and GRM.FactionDuty.IsOnDuty and GRM.FactionDuty.IsOnDuty(ply)
        return onDuty and "НА СЛУЖБЕ" or "ВНЕ СЛУЖБЫ"
    end
    return saved==false and "ВЫХОДНОЙ" or "НЕ В СЕТИ"
end

local function locationOf(ply)
    if not IsValid(ply) then return "—" end
    local pos=ply:GetPos()
    return string.format("%.0f %.0f %.0f",pos.x,pos.y,pos.z)
end

local function rowsOf(faction)
    local rows={}
    for characterKey,rec in pairs(faction.Members or{}) do
        local ply=resolve(characterKey)
        rows[#rows+1]={key=characterKey,rec=rec,ply=ply,name=nameOf(characterKey,rec),status=dutyStatus(characterKey,ply)}
    end
    table.sort(rows,function(a,b)
        if a.key==faction.Leader then return true end
        if b.key==faction.Leader then return false end
        if a.status~=b.status then return a.status<b.status end
        return string.lower(a.name)<string.lower(b.name)
    end)
    return rows
end

local function displayFaction(name,faction)return GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(faction,name)or name end
local function printFaction(ply,factionName,faction,index,total)
    local rows=rowsOf(faction);local publicName=displayFaction(factionName,faction)
    local online,onDuty=0,0
    for _,row in ipairs(rows) do if IsValid(row.ply) then online=online+1 end;if row.status=="НА СЛУЖБЕ" then onDuty=onDuty+1 end end
    local prefix=(total and total>1) and string.format("[%d/%d] ",index,total) or ""
    ply:ChatPrint("════════════════════════════════")
    ply:ChatPrint(prefix..publicName..string.format(" • всего %d • онлайн %d • на службе %d",#rows,online,onDuty))
    if #rows==0 then ply:ChatPrint("  — состав пуст —") return end
    for i,row in ipairs(rows) do
        local leader=row.key==faction.Leader and "★ " or "  "
        ply:ChatPrint(string.format("%s%02d. %s | %s | %s | %s | %s",leader,i,row.name,tostring(row.rec.Role or"Участник"),tostring(GRM.Factions and GRM.Factions.DepartmentDisplayName and GRM.Factions.DepartmentDisplayName(faction,row.rec.Department)or row.rec.Department or"—"),row.status,locationOf(row.ply)))
    end
end

function R.PrintMembers(ply,requested)
    if not IsValid(ply) then return end
    requested=string.Trim(tostring(requested or""))
    local ownName,ownFaction=factionOf(ply)

    if ply:IsSuperAdmin() then
        if requested~="" and string.lower(requested)~="all" and requested~="все" then
            local registration=Factions and Factions[requested]and requested or(FactionsAPI and FactionsAPI.GetRegistrationName and FactionsAPI.GetRegistrationName(requested));local faction=registration and Factions[registration]
            if not faction then ply:ChatPrint("[Состав] Фракция «"..requested.."» не найдена.") return end
            printFaction(ply,registration,faction,1,1)
            return
        end
        local names={}
        for name in pairs(Factions or{}) do names[#names+1]=name end
        table.sort(names,function(a,b)return string.lower(a)<string.lower(b)end)
        ply:ChatPrint("=== ВСЕ ФРАКЦИИ И СОСТАВЫ ===")
        for i,name in ipairs(names) do printFaction(ply,name,Factions[name],i,#names) end
        ply:ChatPrint("════════════════════════════════")
        ply:ChatPrint("Фракций: "..#names)
        return
    end

    if not ownFaction then ply:ChatPrint("[Состав] Вы не состоите во фракции.") return end
    -- Участник и лидер видят исключительно свою организацию; аргумент игнорируем.
    printFaction(ply,ownName,ownFaction,1,1)
end

function R.PrintLeaders(ply)
    if not IsValid(ply) then return end
    local names={}
    for name in pairs(Factions or{}) do names[#names+1]=name end
    table.sort(names,function(a,b)return string.lower(a)<string.lower(b)end)
    ply:ChatPrint("=== ЛИДЕРЫ ФРАКЦИЙ ===")
    for i,name in ipairs(names) do
        local faction=Factions[name]
        local leaderKey=tostring(faction.Leader or"")
        local leader=leaderKey~="" and resolve(leaderKey) or nil
        local leaderName=leaderKey~="" and nameOf(leaderKey,faction.Members and faction.Members[leaderKey]) or "НЕ НАЗНАЧЕН"
        ply:ChatPrint(string.format("%02d. %s — %s [%s]",i,displayFaction(name,faction),leaderName,IsValid(leader) and "В СЕТИ" or "НЕ В СЕТИ"))
    end
    ply:ChatPrint("Всего фракций: "..#names)
end

if SERVER then
    local function handle(ply,text)
        local raw=string.Trim(tostring(text or""))
        local low=string.lower(raw)
        if low=="/members" or low=="/состав" or string.sub(low,1,9)=="/members " then
            R.PrintMembers(ply,string.Trim(string.sub(raw,9)))
            return true
        end
        if low=="/leaders" or low=="/лидеры" then R.PrintLeaders(ply) return true end
        return false
    end
    hook.Add("PlayerSay", "GRM_Roster_Transform", function(ply, text, teamSays)
        local data = { tostring(text or ""), SkipPlayerSay = false }
            if istable(data) and isstring(data[1]) and handle(ply,data[1]) then data[1]="" data.SkipPlayerSay=true end

        if data.SkipPlayerSay == true then return "" end
    end)
    hook.Add("PlayerSay","GRM_Roster_Chat",function(ply,text) if handle(ply,text) then return""end end)
    timer.Create("GRM_Roster_LiveSync",10,0,function() if isfunction(broadcastFactionData) then broadcastFactionData() end end)
end

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/leaders", "/members", "/лидеры", "/состав" })
end
