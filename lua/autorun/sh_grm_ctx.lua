-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Context Menu — единое контекстное меню (server + client)
--------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
    util.AddNetworkString("GRM_Ctx_Check")
    util.AddNetworkString("GRM_Ctx_Result")
    util.AddNetworkString("GRM_Ctx_VehAct")
    util.AddNetworkString("GRM_Ctx_MoneyAct")
    util.AddNetworkString("GRM_Ctx_Action")
    util.AddNetworkString("GRM_Ctx_Radio")
    util.AddNetworkString("GRM_Laws_Open")
    util.AddNetworkString("Factions_OpenAdminMenu")
    util.AddNetworkString("Factions_OpenLeaderMenu")

    -- Игрок в прицеле (для кнопки «Передать деньги»)
    local function aimPlyInfo(ply)
        -- pcall: в нетиповых средах (тестовые стенды) плейер может не иметь GetEyeTrace
        local ok, tr = pcall(function() return ply:GetEyeTrace() end)
        if not ok or not istable(tr) then return nil end
        local t = tr.Entity
        if IsValid(t) and t:IsPlayer() and t ~= ply
            and t:GetPos():DistToSqr(ply:GetPos()) <= 300 * 300 then
            return { name = t:Nick(), idx = t:EntIndex() }
        end
        return nil
    end

    local function getPlayerFaction(ply)
        if not Factions then return nil, nil end
        local sid = ply:SteamID()
        local s64 = ply:SteamID64()
        local hasIdentity = GRM.Identity and GRM.Identity.FactionMember
        local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or s64
        for name, f in pairs(Factions) do
            if istable(f) and hasIdentity and hasIdentity(f, ply) then
                return name, f
            end
        end
        return nil, nil
    end

    local function isPlyLeader(ply, f)
        if not IsValid(ply) or not istable(f) then return false end
        if _G.FactionsAPI and _G.FactionsAPI.IsLeader then
            for fname, fac in pairs(Factions or {}) do
                if fac == f then
                    return _G.FactionsAPI.IsLeader(ply, fname)
                end
            end
        end
        local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()
        if f.Leader and f.Leader == ck then return true end
        local member = f.Members and GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f, ply)
        local leaderRole = f.LeaderRoleName or "Лидер"
        return istable(member) and (member.Role == leaderRole or member.Role == "Лидер")
    end

    local function openFactionsMenu(ply)
        if not IsValid(ply) then return end
        if ply:IsSuperAdmin() then
            net.Start("Factions_OpenAdminMenu")
            net.Send(ply)
            return
        end

        local isLeader = false
        if _G.FactionsAPI and _G.FactionsAPI.GetFactionOfLeader then
            isLeader = _G.FactionsAPI.GetFactionOfLeader(ply) ~= nil
        end
        if not isLeader and Factions then
            for _, f in pairs(Factions) do
                if istable(f) and isPlyLeader(ply, f) then
                    isLeader = true
                    break
                end
            end
        end

        if isLeader then
            net.Start("Factions_OpenLeaderMenu")
            net.Send(ply)
        else
            ply:PrintMessage(HUD_PRINTTALK, "[Фракции] У вас нет прав для использования этого меню.")
        end
    end

    -- Транспорт в прицеле (Код 82): имя/замок/права для кнопок меню
    local function vehInfo(ply)
        if not (_G.VK and VK.IsVehicle) then return nil end
        local veh = nil
        if VK.GetAimedVehicle then veh = VK.GetAimedVehicle(ply, 240) end
        if not (IsValid(veh) and VK.IsVehicle(veh)) then return nil end
        local canManage = (VK.CanInteract and VK.CanInteract(veh, ply, true)) or ply:IsSuperAdmin()
        local canUse = (VK.CanInteract and VK.CanInteract(veh, ply, false)) or ply:IsSuperAdmin()
        local mineStrict = (veh.VD_Owner == ply)
            or (veh.VK_OwnerType == "player" and veh.VK_OwnerSteam == ((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID()))
        local mine = mineStrict or ply:IsSuperAdmin()
        local tracked = (VD_AllVehicles and VD_AllVehicles[veh:EntIndex()] ~= nil)
            or veh.VD_Owner ~= nil or veh.VD_ID ~= nil
        local price = tonumber(veh.VD_Price) or 0
        return {
            name = (VK.GetVehicleDisplayName and VK.GetVehicleDisplayName(veh)) or veh:GetClass(),
            locked = veh.VK_Locked == true or veh:GetNW2Bool("VK_Locked", false),
            canManage = canManage == true,   -- владелец/ключи/суперадмин → замок
            canUse = canUse == true,         -- член фракции/ключи → багажник (дальше решит TK.CanAccess)
            canRemove = mine and tracked,    -- только Т/С дилера у своего владельца; суперадмин — любое дилерское
            refund = (mineStrict and price > 0) and math.floor(price * 0.5) or 0, -- подпись кнопки (2.1)
        }
    end

    net.Receive("GRM_Ctx_Check", function(_, ply)
        if not IsValid(ply) then return end
        local result = {}
        local factionName, faction = getPlayerFaction(ply)
        result.isFactionMember = (factionName ~= nil)
        result.isLeaderOrAdmin = (faction and isPlyLeader(ply, faction)) or ply:IsSuperAdmin()
        result.factionName = factionName or ""
        result.veh = vehInfo(ply)
        result.aimPly = aimPlyInfo(ply)
        result.isSuperAdmin = ply:IsSuperAdmin() == true
        result.hasMaskAccess = false

        -- Кнопка документа появляется только при наличии ФИЗИЧЕСКОГО
        -- собственного бланка в инвентаре. Чужой ownerKey права не даёт.
        local key = (GRM.Identity and isfunction(GRM.Identity.CharacterKey) and GRM.Identity.CharacterKey(ply)) or (ply:SteamID64() .. ":char1")
        local function hasOwnItem(itemID,docType)
            local inv=GRM.Inventory and GRM.Inventory.GetPlayerInv and GRM.Inventory.GetPlayerInv(ply)
            if not inv then return false end
            for _,slot in pairs(inv.slots or {}) do
                if istable(slot) and slot.id==itemID then
                    local d=istable(slot.data) and slot.data or {}
                    local owner=tostring(d.ownerKey or d.sid64 or "")
                    if owner=="" then owner=key end -- старые личные бланки до instance-data
                    local typ=GRM.Documents and GRM.Documents.CanonicalPhysicalType and GRM.Documents.CanonicalPhysicalType(d.docType or docType) or (d.docType or docType)
                    if owner==key and (not docType or tostring(typ)==tostring(docType)) then return true end
                end
            end
            return false
        end
        local pass = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.passports and GRM.Documents.Registry.passports[key]
        result.hasPassport = hasOwnItem("passport","passport") and pass ~= nil

        local hasCover = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.coverBadges and GRM.Documents.Registry.coverBadges[key] and GRM.Documents.Registry.coverBadges[key].status == "Действителен"
        local coverRec = hasCover and GRM.Documents.Registry.coverBadges[key] or nil
        local badge = GRM.Documents and GRM.Documents.GetOfficialBadge and GRM.Documents.GetOfficialBadge(key)
            or (GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.badges and GRM.Documents.Registry.badges[key])
        local officialList = GRM.Documents and GRM.Documents.AllOfficialBadges and GRM.Documents.AllOfficialBadges(key) or (istable(badge) and { badge } or {})
        local hasOfficial = false
        for _, rec in ipairs(officialList) do
            if rec.status ~= "Аннулирован / Изъят" then hasOfficial = true break end
        end
        local hasBadgeItem=hasOwnItem("badge","badge")
        result.badgeChoices={}
        if hasBadgeItem then
            for _, rec in ipairs(officialList) do
                if rec.status ~= "Аннулирован / Изъят" then
                    local tag = (rec.kind == "special" or rec.lockFaction) and "Спецслужбы" or "Служебное"
                    result.badgeChoices[#result.badgeChoices+1]={
                        subType="official:"..tostring(rec.faction or ""),
                        label=tag..": "..tostring(rec.faction or factionName),
                        number=tostring(rec.number or""),
                    }
                end
            end
        end
        local covers=GRM.SpecialService and GRM.SpecialService.ListCovers and GRM.SpecialService.ListCovers(key) or{}
        if hasBadgeItem then for _,c in ipairs(covers)do if c.status=="Действителен"then result.badgeChoices[#result.badgeChoices+1]={subType="cover:"..tostring(c.index),label="Прикрытие: "..tostring(c.label).." — "..tostring(c.fullName),number=tostring(c.number or""),active=c.active==true}end end end
        result.hasBadge = #result.badgeChoices>0
        result.hasOfficialBadge = hasBadgeItem and hasOfficial
        result.hasCoverBadge = #result.badgeChoices>(result.hasOfficialBadge and 1 or 0)
        result.officialBadgeFac = hasOfficial and (badge and badge.faction or factionName) or ""
        result.coverBadgeFac = hasCover and (coverRec and coverRec.faction or "") or ""

        result.hasMedCard = hasOwnItem("medcard",nil) and (GRM.Medical and isfunction(GRM.Medical.HasCard) and GRM.Medical.HasCard(key)) == true

        -- Дипломы: свои бланки игрок смотрит как любой другой документ.
        -- Аннулированные учитываем тоже — владелец должен видеть их статус.
        local dipl = GRM.Diplomas and isfunction(GRM.Diplomas.For) and GRM.Diplomas.For(ply, true)
        result.diplomaCount = istable(dipl) and #dipl or 0

        local mil = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.military and GRM.Documents.Registry.military[key]
        result.hasMilitary = hasOwnItem("military_ticket","military") and (mil ~= nil and mil.status ~= "Аннулирован")

        local lic = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.licenses and GRM.Documents.Registry.licenses[key]
        result.hasLicense = hasOwnItem("driver_license","license") and (lic ~= nil and lic.status ~= "Аннулировано" and lic.status ~= "Лишён права управления")

        local milLic = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.milLicenses and GRM.Documents.Registry.milLicenses[key]
        result.hasMilLicense = hasOwnItem("military_license","milLicense") and (milLic ~= nil and milLic.status ~= "Аннулировано" and milLic.status ~= "Лишён ВАИ")

        local weaponLic = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.weaponLicenses and GRM.Documents.Registry.weaponLicenses[key]
        result.hasWeaponLicense = hasOwnItem("weapon_license","weaponLicense") and weaponLic ~= nil
        local businessLic = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.businessLicenses and GRM.Documents.Registry.businessLicenses[key]
        result.hasBusinessLicense = hasOwnItem("business_license","businessLicense") and businessLic ~= nil
        local missing=GRM.Documents and GRM.Documents.MissingPhysicalTypes and GRM.Documents.MissingPhysicalTypes(ply)or{}
        result.missingPhysicalCount=istable(missing)and #missing or 0

        if factionName and FactionsExt and FactionsExt[factionName] then
            local cfg = FactionsExt[factionName]
            local member = faction and GRM.Identity.FactionMember(faction, ply)
            if member and cfg.MaskDepartments then
                for _, dept in pairs(cfg.MaskDepartments) do
                    if istable(dept.Roles) then
                        for _, role in ipairs(dept.Roles) do
                            if role == member.Role then
                                result.hasMaskAccess = true
                                break
                            end
                        end
                    end
                    if result.hasMaskAccess then break end
                end
            end
        end
        net.Start("GRM_Ctx_Result")
            net.WriteTable(result)
        net.Send(ply)
    end)

    net.Receive("GRM_Ctx_Action", function(_, ply)
        if not IsValid(ply) then return end
        local action = tostring(net.ReadString() or "")
        if action == "factions" then
            openFactionsMenu(ply)
            return
        end
    end)

    -- ── Действия с транспортом из контекст-меню (Код 82) ──────
    net.Receive("GRM_Ctx_Radio", function(_, ply)
        if not IsValid(ply) then return end
        local op = tostring(net.ReadString() or "")
        local value = net.ReadString() or ""
        local rn = GRM.RadioNet
        if not rn then return end
        if op == "leave" and rn.FreqLeave then
            rn.FreqLeave(ply)
        elseif op == "set" and rn.FreqSet then
            rn.FreqSet(ply, value)
        end
    end)

    net.Receive("GRM_Ctx_VehAct", function(_, ply)
        if not IsValid(ply) then return end
        local doAct = tostring(net.ReadString() or "")
        if not (_G.VK and VK.IsVehicle and VK.GetAimedVehicle) then return end
        local veh = VK.GetAimedVehicle(ply, 260)
        if not (IsValid(veh) and VK.IsVehicle(veh)) then return end

        -- «Замок»: владелец/ключи/суперадмин
        if doAct == "lock" then
            local canManage = (VK.CanInteract and VK.CanInteract(veh, ply, true)) or ply:IsSuperAdmin()
            if not canManage then
                if GRM.Notify then GRM.Notify(ply, "Нет доступа к замку (нужен ключ)", 255, 120, 110) end
                return
            end
            veh.VK_Locked = not (veh.VK_Locked == true)
            if VK.SyncVehicle then VK.SyncVehicle(veh) end
            veh:EmitSound(veh.VK_Locked and "doors/door_latch3.wav" or "doors/door_latch1.wav")
            if GRM.Notify then
                GRM.Notify(ply, veh.VK_Locked and "Транспорт ЗАКРЫТ" or "Транспорт ОТКРЫТ", 120, 200, 255)
            end
            return
        end

        -- «Багажник»: делегируем модулю багажника (сам решит доступ)
        if doAct == "trunk" then
            if GRM.Trunk and GRM.Trunk.RequestToggle then
                GRM.Trunk.RequestToggle(ply)
            elseif GRM.Notify then
                GRM.Notify(ply, "Модуль багажника не загружен", 255, 140, 120)
            end
            return
        end

        -- «Убрать Т/С» (Диллер 2.1): ЕДИНАЯ точка удаления с меню дилера —
        -- одинаковые права, возврат 50%, чистка реестра, синк «Мои Т/С».
        if doAct == "remove" then
            local removeFn = _G.VD_RemoveDealerVehicle
            if not removeFn then
                if GRM.Notify then GRM.Notify(ply, "Модуль авто-дилера не загружен", 255, 140, 120) end
                return
            end
            local ok, msg = removeFn(ply, veh, { maxDist = 400 })
            if GRM.Notify then
                if ok then GRM.Notify(ply, tostring(msg or "Готово"), 140, 230, 150)
                else GRM.Notify(ply, tostring(msg or "Отказ"), 255, 140, 120) end
            end
            return
        end
    end)

    -- ── Передача денег из контекст-меню (Код 85.2) ─────────────
    -- Выброс пачки идёт клиентской командой /dropmoney (вся логика на месте).
    local lastGive = {}
    net.Receive("GRM_Ctx_MoneyAct", function(_, ply)
        if not IsValid(ply) then return end
        local op = tostring(net.ReadString() or "")
        if op ~= "give" then return end
        local target = net.ReadEntity()
        local amount = math.floor(net.ReadUInt(32))
        local now = CurTime()
        if lastGive[ply] and now - lastGive[ply] < 0.8 then return end -- антифлуд
        lastGive[ply] = now
        if not (IsValid(target) and target:IsPlayer() and target ~= ply) then
            if GRM.Notify then GRM.Notify(ply, "Игрок не найден.", 255, 140, 120) end
            return
        end
        if target:GetPos():DistToSqr(ply:GetPos()) > 300 * 300 then
            if GRM.Notify then GRM.Notify(ply, "Слишком далеко — подойдите ближе (до 300 юнитов).", 255, 140, 120) end
            return
        end
        if amount <= 0 then return end
        if not (GRM.TakeMoney and GRM.GiveMoney and GRM.GetBalance) then return end
        if GRM.GetBalance(ply) < amount then
            if GRM.Notify then GRM.Notify(ply, "Не хватает наличных (есть " .. tostring(GRM.GetBalance(ply)) .. ").", 255, 140, 120) end
            return
        end
        GRM.TakeMoney(ply, amount, "Передача наличных: " .. target:Nick())
        GRM.GiveMoney(target, amount, "Передача наличных от " .. ply:Nick())
        if GRM.Notify then
            GRM.Notify(ply, "Передано " .. tostring(amount) .. " → " .. target:Nick(), 120, 220, 140)
            GRM.Notify(target, "Вам передали " .. tostring(amount) .. " (от " .. ply:Nick() .. ")", 120, 220, 140)
        end
    end)

    print("[GRM CTX] Server loaded (v3: +передача денег в C-меню)")
end

if CLIENT then

local MENU_Y = 300

surface.CreateFont("GRMCtx_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })

local CC = {
    ticket  = Color(180, 100, 60),  ticketH  = Color(200, 120, 80),
    inv     = Color(50, 120, 200),  invH     = Color(70, 140, 220),
    third   = Color(100, 100, 180), thirdH   = Color(120, 120, 200),
    radio   = Color(180, 160, 60),  radioH   = Color(200, 180, 80),
    faction = Color(80, 80, 180),   factionH = Color(100, 100, 200),
    mask    = Color(140, 80, 160),  maskH    = Color(160, 100, 180),
}
local BG   = Color(14, 16, 22, 230)
local BORD = Color(40, 45, 65, 180)

local visible = false
local wasDown = false
local cooldowns = {}
local armed = { id = nil, untilT = 0 } -- двойное нажатие для опасных кнопок (confirm)
local data = {}
local tp = false

local function actTicket()    RunConsoleCommand("grm_ticket") end
local function actInv()       RunConsoleCommand("grm_inventory") end
-- Суперадмин: открыть инвентарь игрока в прицеле (просмотр/изъятие)
local function actAdminInv()
    local ap = istable(data.aimPly) and data.aimPly or nil
    if not ap then return end
    -- idx = EntIndex цели — шлём запрос просмотра чужого инвентаря
    net.Start("GRM_Inv_AdminOpen")
        net.WriteUInt(tonumber(ap.idx) or 0, 16)
    net.SendToServer()
end
--[[ Вид от третьего лица — СВОЙ модуль (GRM.ThirdPerson).

     Раньше здесь звалась simple_thirdperson_enable_toggle — команда
     ЧУЖОГО аддона. Нет его на сервере или переименовали в новой
     версии — кнопка молча ничего не делает, и локальный флаг tp при
     этом честно переключался: подпись менялась на «Выкл», а вид не
     менялся.

     Теперь состояние спрашиваем у своего модуля, а не храним копию:
     вид можно включить ещё и командой grm_tp, и подпись в меню обязана
     это показывать. ]]
local function actTp()
    if GRM.ThirdPerson and GRM.ThirdPerson.Toggle then
        tp = GRM.ThirdPerson.Toggle()
        return
    end
    -- Модуль не загрузился — не притворяемся, что сработало.
    if GRM.Notify then GRM.Notify("Вид от третьего лица недоступен", 255, 160, 90) end
end

--[[ Подпись кнопки читает РЕАЛЬНОЕ состояние модуля. Локальный tp
     оставлен только как запасной вариант, если модуля нет. ]]
local function tpOn()
    if GRM.ThirdPerson and GRM.ThirdPerson.IsEnabled then
        return GRM.ThirdPerson.IsEnabled()
    end
    return tp
end
local function actRadio()
    Derma_StringRequest("Рация", "Частота (1-999.9) или пусто = отключиться:", "",
        function(v)
            net.Start("GRM_Ctx_Radio")
                net.WriteString(v and v ~= "" and "set" or "leave")
                net.WriteString(v or "")
            net.SendToServer()
        end)
end

local function actLaws()
    net.Start("GRM_Laws_Open")
    net.SendToServer()
end
local function actFactions()
    net.Start("GRM_Ctx_Action")
        net.WriteString("factions")
    net.SendToServer()
end
local function actMask()      RunConsoleCommand("say", "/mask") end

local function actShowPassport()
    local ap = istable(data.aimPly) and data.aimPly or nil
    net.Start("GRM_Doc_ShowDoc")
        net.WriteString("passport")
        net.WriteEntity(Entity(ap and ap.idx or 0))
    net.SendToServer()
end

local function badgeChoiceMenu(targetEnt,ownView)
    local choices=istable(data.badgeChoices) and data.badgeChoices or{}
    if #choices==0 then return end
    local function send(choice)
        net.Start(ownView and "GRM_Doc_OpenDoc" or "GRM_Doc_ShowDoc")
            net.WriteString("badge")
            if not ownView then net.WriteEntity(targetEnt) end
            net.WriteString(tostring(choice.subType or"official"))
        net.SendToServer()
    end
    if #choices==1 then send(choices[1]) return end
    local menu=DermaMenu()
    for _,choice in ipairs(choices)do
        local text=(choice.active and "★ "or"")..tostring(choice.label or"Удостоверение")..(choice.number~=""and("  №"..choice.number)or"")
        menu:AddOption(text,function()send(choice)end):SetIcon(choice.subType=="official"and"icon16/shield.png"or"icon16/user_suit.png")
    end
    menu:Open()
end

local function actShowBadge()
    local ap=istable(data.aimPly) and data.aimPly or nil
    badgeChoiceMenu(Entity(ap and ap.idx or 0),false)
end

local function actShowMedCard()
    local ap = istable(data.aimPly) and data.aimPly or nil
    net.Start("GRM_Doc_ShowDoc")
        net.WriteString("medcard")
        net.WriteEntity(Entity(ap and ap.idx or 0))
    net.SendToServer()
end

local function actShowMilitary()
    local ap = istable(data.aimPly) and data.aimPly or nil
    net.Start("GRM_Doc_ShowDoc")
        net.WriteString("military")
        net.WriteEntity(Entity(ap and ap.idx or 0))
    net.SendToServer()
end

local function actShowLicense()
    local ap = istable(data.aimPly) and data.aimPly or nil
    net.Start("GRM_Doc_ShowDoc")
        net.WriteString("license")
        net.WriteEntity(Entity(ap and ap.idx or 0))
        net.WriteString("civilian")
    net.SendToServer()
end

local function actShowMilLicense()
    local ap = istable(data.aimPly) and data.aimPly or nil
    net.Start("GRM_Doc_ShowDoc")
        net.WriteString("milLicense")
        net.WriteEntity(Entity(ap and ap.idx or 0))
        net.WriteString("military")
    net.SendToServer()
end

local function actShowWeaponLicense()
    local ap=istable(data.aimPly) and data.aimPly or nil
    net.Start("GRM_Doc_ShowDoc") net.WriteString("weaponLicense") net.WriteEntity(Entity(ap and ap.idx or 0)) net.SendToServer()
end
local function actShowBusinessLicense()
    local ap=istable(data.aimPly) and data.aimPly or nil
    net.Start("GRM_Doc_ShowDoc") net.WriteString("businessLicense") net.WriteEntity(Entity(ap and ap.idx or 0)) net.SendToServer()
end

local function actOwnPassport()
    net.Start("GRM_Doc_OpenDoc")
        net.WriteString("passport")
    net.SendToServer()
end

local function actOwnBadge()
    badgeChoiceMenu(nil,true)
end

local function actOwnMilitary()
    net.Start("GRM_Doc_OpenDoc")
        net.WriteString("military")
    net.SendToServer()
end

local function actOwnLicense()
    net.Start("GRM_Doc_OpenDoc")
        net.WriteString("license")
        net.WriteString("civilian")
    net.SendToServer()
end

local function actOwnMilLicense()
    net.Start("GRM_Doc_OpenDoc")
        net.WriteString("milLicense")
        net.WriteString("military")
    net.SendToServer()
end

local function actOwnWeaponLicense()
    net.Start("GRM_Doc_OpenDoc") net.WriteString("weaponLicense") net.SendToServer()
end
local function actOwnBusinessLicense()
    net.Start("GRM_Doc_OpenDoc") net.WriteString("businessLicense") net.SendToServer()
end

local function actOwnMedCard()
    net.Start("GRM_Doc_OpenDoc")
        net.WriteString("medcard")
    net.SendToServer()
end

local function actOwnDiplomas()
    if GRM.Education and isfunction(GRM.Education.AskMine) then
        GRM.Education.AskMine()
    else
        RunConsoleCommand("say", "/mydiplomas")
    end
end

-- Деньги в C-меню (по заказу: «выбросить деньги / передать деньги игроку»)
local function actDropMoney()
    Derma_StringRequest("Выбросить наличные", "Сумма (пачка упадёт перед вами):", "",
        function(v)
            local n = math.floor(tonumber(v) or 0)
            if n > 0 then RunConsoleCommand("say", "/dropmoney " .. tostring(n)) end
        end)
end
local function actGiveMoney()
    local ap = istable(data.aimPly) and data.aimPly or nil
    Derma_StringRequest("Передать наличные", "Сумма для передачи " .. (ap and ("(" .. tostring(ap.name) .. ")") or "игроку") .. ":", "",
        function(v)
            local n = math.floor(tonumber(v) or 0)
            if n <= 0 or not ap then return end
            net.Start("GRM_Ctx_MoneyAct")
                net.WriteString("give")
                net.WriteEntity(Entity(ap.idx or 0))
                net.WriteUInt(n, 32)
            net.SendToServer()
        end)
end

-- Транспорт рядом (Код 82): сервер сам перепроверит прицел и права
-- fg: req объявлена форвардом — vehAct вызывает её из замыкания (иначе была бы
-- ссылка на ГЛОБАЛЬНЫЙ req=nil → timer.Simple(function expected, got nil), 18.07.2026)
local req
local function vehAct(what)
    return function()
        net.Start("GRM_Ctx_VehAct")
            net.WriteString(what)
        net.SendToServer()
        timer.Simple(0.25, req) -- обновить статус (замок/список)
    end
end
local function vehOk(field)
    return function() return istable(data.veh) and data.veh[field] == true end
end

local BTNS = {
    { id = "ticket",     l = "Тикет",        fn = actTicket,     c = CC.ticket,  ch = CC.ticketH,  ok = function() return true end },
    { id = "inventory",  l = "Инвентарь",    fn = actInv,        c = CC.inv,     ch = CC.invH,     ok = function() return true end },
    { id = "gps",        l = "GPS-метки",     fn = function() RunConsoleCommand("grm_gps") end, c = Color(55, 155, 185), ch = Color(75, 180, 210), ok = function() return true end },
    { id = "money_drop", l = "Выбросить деньги…", fn = actDropMoney,
      c = Color(190, 150, 60), ch = Color(210, 170, 80), ok = function() return true end },
    { id = "money_give", l = function()
          if istable(data.aimPly) then
              local n = tostring(data.aimPly.name or "игроку")
              n = GRM.Utf8Ellipsis(n, 16)
              return "Передать деньги: " .. n
          end
          return "Передать деньги игроку"
      end,
      fn = actGiveMoney,
      c = Color(90, 170, 90), ch = Color(110, 190, 110),
      ok = function() return istable(data.aimPly) end },
    -- ── документы: показ игроку перед собой (Код 87) ──────────
    { id = "doc_pass", l = function()
          local n = istable(data.aimPly) and tostring(data.aimPly.name or "игроку") or "игроку"
          n = GRM.Utf8Ellipsis(n, 14)
          return "Показать паспорт: " .. n
      end,
      fn = actShowPassport,
      c = Color(140, 45, 55), ch = Color(170, 60, 70),
      ok = function() return istable(data.aimPly) and data.hasPassport == true end },
    { id = "doc_badge", l = function()
          local n = istable(data.aimPly) and tostring(data.aimPly.name or "игроку") or "игроку"
          n = GRM.Utf8Ellipsis(n, 14)
          return "Предъявить удостоверение: " .. n
      end,
      fn = actShowBadge,
      c = Color(35, 75, 135), ch = Color(50, 100, 170),
      ok = function() return istable(data.aimPly) and data.hasBadge == true end },
    { id = "doc_mil", l = function()
          local n = istable(data.aimPly) and tostring(data.aimPly.name or "игроку") or "игроку"
          n = GRM.Utf8Ellipsis(n, 14)
          return "Показать военный билет: " .. n
      end,
      fn = actShowMilitary,
      c = Color(38, 90, 45), ch = Color(55, 120, 60),
      ok = function() return istable(data.aimPly) and data.hasMilitary == true end },
    { id = "doc_lic", l = function()
          local n = istable(data.aimPly) and tostring(data.aimPly.name or "игроку") or "игроку"
          n = GRM.Utf8Ellipsis(n, 14)
          return "Показать права (Дорожная Инспекция): " .. n
      end,
      fn = actShowLicense,
      c = Color(35, 95, 165), ch = Color(50, 120, 195),
      ok = function() return istable(data.aimPly) and data.hasLicense == true end },
    { id = "doc_mil_lic", l = function()
          local n = istable(data.aimPly) and tostring(data.aimPly.name or "игроку") or "игроку"
          n = GRM.Utf8Ellipsis(n, 14)
          return "Показать права (ВАИ): " .. n
      end,
      fn = actShowMilLicense,
      c = Color(42, 105, 52), ch = Color(60, 135, 70),
      ok = function() return istable(data.aimPly) and data.hasMilLicense == true end },
    { id = "doc_weapon_lic", l = function()
          local n=istable(data.aimPly) and tostring(data.aimPly.name or "игроку") or "игроку"
          return "Показать лицензию на оружие: " .. GRM.Utf8Ellipsis(n,12)
      end,
      fn=actShowWeaponLicense, c=Color(55,105,75), ch=Color(70,135,95),
      ok=function() return istable(data.aimPly) and data.hasWeaponLicense==true end },
    { id = "doc_business_lic", l = function()
          local n=istable(data.aimPly) and tostring(data.aimPly.name or "игроку") or "игроку"
          return "Показать бизнес-лицензию: " .. GRM.Utf8Ellipsis(n,12)
      end,
      fn=actShowBusinessLicense, c=Color(35,115,115), ch=Color(50,145,145),
      ok=function() return istable(data.aimPly) and data.hasBusinessLicense==true end },
    { id = "doc_diploma", l = function()
          local n = istable(data.aimPly) and tostring(data.aimPly.name or "игроку") or "игроку"
          n = GRM.Utf8Ellipsis(n, 14)
          return "Предъявить диплом: " .. n
      end,
      fn = function()
          if GRM.Education and isfunction(GRM.Education.AskShow) then
              GRM.Education.AskShow()
          end
      end,
      c = Color(150, 120, 45), ch = Color(185, 150, 60),
      ok = function() return istable(data.aimPly) and (tonumber(data.diplomaCount) or 0) > 0 end },
    { id = "doc_med", l = function()
          local n = istable(data.aimPly) and tostring(data.aimPly.name or "игроку") or "игроку"
          n = GRM.Utf8Ellipsis(n, 14)
          return "Показать медкарту: " .. n
      end,
      fn = actShowMedCard,
      c = Color(35, 120, 95), ch = Color(45, 150, 120),
      ok = function() return istable(data.aimPly) and data.hasMedCard == true end },
    -- ── документы: личный просмотр (Код 87) ───────────────────
    { id="doc_restore",l=function()return"Восстановить бланки ("..tostring(tonumber(data.missingPhysicalCount)or 0)..")"end,
      fn=function()RunConsoleCommand("say","/docrestore all")end,c=Color(185,115,45),ch=Color(215,145,65),
      ok=function()return not istable(data.aimPly)and(tonumber(data.missingPhysicalCount)or 0)>0 end },
    { id = "doc_self_pass", l = "Мой паспорт",
      fn = actOwnPassport,
      c = Color(140, 45, 55), ch = Color(170, 60, 70),
      ok = function() return not istable(data.aimPly) and data.hasPassport == true end },
    { id = "doc_self_badge", l = "Моё удостоверение",
      fn = actOwnBadge,
      c = Color(35, 75, 135), ch = Color(50, 100, 170),
      ok = function() return not istable(data.aimPly) and data.hasBadge == true end },
    { id = "doc_self_mil", l = "Мой военный билет",
      fn = actOwnMilitary,
      c = Color(38, 90, 45), ch = Color(55, 120, 60),
      ok = function() return not istable(data.aimPly) and data.hasMilitary == true end },
    { id = "doc_self_lic", l = "Мои права (Дорожная Инспекция)",
      fn = actOwnLicense,
      c = Color(35, 95, 165), ch = Color(50, 120, 195),
      ok = function() return not istable(data.aimPly) and data.hasLicense == true end },
    { id = "doc_self_mil_lic", l = "Мои права (ВАИ)",
      fn = actOwnMilLicense,
      c = Color(42, 105, 52), ch = Color(60, 135, 70),
      ok = function() return not istable(data.aimPly) and data.hasMilLicense == true end },
    { id = "doc_self_weapon_lic", l = "Моя лицензия на оружие",
      fn=actOwnWeaponLicense, c=Color(55,105,75), ch=Color(70,135,95),
      ok=function() return not istable(data.aimPly) and data.hasWeaponLicense==true end },
    { id = "doc_self_business_lic", l = "Моя бизнес-лицензия",
      fn=actOwnBusinessLicense, c=Color(35,115,115), ch=Color(50,145,145),
      ok=function() return not istable(data.aimPly) and data.hasBusinessLicense==true end },
    { id = "doc_self_med", l = "Моя медкарта",
      fn = actOwnMedCard,
      c = Color(35, 120, 95), ch = Color(45, 150, 120),
      ok = function() return not istable(data.aimPly) and data.hasMedCard == true end },
    { id = "doc_self_diploma", l = function()
          local n = tonumber(data.diplomaCount) or 0
          return (n > 1) and ("Мои дипломы (" .. n .. ")") or "Мой диплом"
      end,
      fn = actOwnDiplomas,
      c = Color(150, 120, 45), ch = Color(185, 150, 60),
      ok = function() return not istable(data.aimPly) and (tonumber(data.diplomaCount) or 0) > 0 end },
    -- ── транспорт (Код 82): только когда смотрим на машину ──
    { id = "veh_lock",   l = function() return (istable(data.veh) and data.veh.locked) and "Открыть замок Т/С" or "Закрыть Т/С на замок" end,
      fn = vehAct("lock"),   c = Color(90, 140, 200), ch = Color(110, 160, 220), ok = vehOk("canManage") },
    { id = "veh_trunk",  l = "Багажник (окно)", fn = vehAct("trunk"),
      c = Color(200, 160, 80), ch = Color(220, 180, 100), ok = vehOk("canUse") },
    { id = "veh_remove", l = function()
          if istable(data.veh) and (data.veh.refund or 0) > 0 then
              local rt = GRM and GRM.Format and GRM.Format(data.veh.refund) or tostring(data.veh.refund)
              return "Убрать Т/С (вернуть " .. rt .. ")"
          end
          return "Убрать Т/С"
      end,
      fn = vehAct("remove"),
      c = Color(190, 90, 80), ch = Color(210, 110, 100), ok = vehOk("canRemove"),
      confirm = true }, -- двойное нажатие-подтверждение (Диллер 2.1)
    { id = "tp",         l = function() return (tpOn() and "Выкл" or "Вкл") .. " 3-е лицо" end, fn = actTp, c = CC.third, ch = CC.thirdH, ok = function() return true end },
    { id = "radio",      l = "Рация",        fn = actRadio,      c = CC.radio,   ch = CC.radioH,   ok = function() return true end },
    { id = "laws",       l = "Законы государства", fn = actLaws, c = Color(200, 180, 100), ch = Color(220, 200, 120), ok = function() return true end },
    { id = "faction",    l = "Меню фракций", fn = actFactions,   c = CC.faction, ch = CC.factionH, ok = function() return data.isLeaderOrAdmin == true or data.isFactionMember == true end },
    { id = "mask",       l = "Маскировка",   fn = actMask,       c = CC.mask,    ch = CC.maskH,    ok = function() return data.hasMaskAccess == true end },
    -- Суперадмин (находка 170): единая админ-панель + инвентарь игрока в прицеле
    { id = "admin",      l = "Админ-панель (GRM)", fn = function() RunConsoleCommand("grm_admin") end,
      c = Color(150, 90, 200), ch = Color(170, 110, 220), ok = function() return data.isSuperAdmin == true end },
    { id = "admin_inv",  l = function()
          if istable(data.aimPly) then
              local n = tostring(data.aimPly.name or "игроку")
              n = GRM.Utf8Ellipsis(n, 14)
              return "Инвентарь игрока: " .. n
          end
          return "Инвентарь игрока (прицел)"
      end,
      fn = actAdminInv,
      c = Color(200, 130, 60), ch = Color(220, 150, 80), ok = function() return data.isSuperAdmin == true and istable(data.aimPly) end },
}

req = function()
    net.Start("GRM_Ctx_Check")
    net.SendToServer()
end
net.Receive("GRM_Ctx_Result", function() data = net.ReadTable() or {} end)
timer.Create("GRM_Ctx_Refresh", 15, 0, req)
grmBootStart("GRM_Ctx_Init", "early", function() timer.Simple(3, req) end)

local function drawMenu()
    if not visible then return end

    local sw, sh = ScrW(), ScrH()
    local bw, bh, gap, pad = 200, 36, 4, 8
    local list = {}
    for _, b in ipairs(BTNS) do if b.ok() then table.insert(list, b) end end
    if #list == 0 then return end

    local vehBar = istable(data.veh) and 22 or 0
    -- Документов стало больше: при нехватке высоты меню автоматически
    -- раскладывается в несколько колонок и не уезжает за нижний край.
    local maxH=math.max(180,sh-MENU_Y-20)
    local rowsPerCol=math.max(1,math.floor((maxH-pad*2-vehBar+gap)/(bh+gap)))
    local cols=math.max(1,math.ceil(#list/rowsPerCol))
    local visibleRows=math.min(#list,rowsPerCol)
    local colW=bw+pad*2
    local totalW=cols*colW+(cols-1)*gap
    local th=visibleRows*(bh+gap)-gap+pad*2+vehBar
    local x,y=sw-totalW-20,MENU_Y

    draw.RoundedBox(6,x,y,totalW,th,BG)
    surface.SetDrawColor(BORD)
    surface.DrawOutlinedRect(x,y,totalW,th,1)

    -- шапка с текущим Т/С (Код 82): имя + статус замка
    if vehBar > 0 then
        local vt = tostring(data.veh.name or "Т/С")
        vt = GRM.Utf8Ellipsis(vt, 26)
        local lockCol = data.veh.locked and Color(230, 120, 110) or Color(120, 220, 140)
        draw.SimpleText(vt .. "  •  " .. (data.veh.locked and "ЗАКРЫТА" or "ОТКРЫТА"),
            "GRMCtx_Normal", x + totalW / 2, y + pad + 9, lockCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local mx, my = gui.MouseX(), gui.MouseY()
    local down = input.IsMouseDown(MOUSE_LEFT)
    local click = down and not wasDown
    if armed.id and CurTime() > (armed.untilT or 0) then armed.id = nil end -- протухло подтверждение

    for bi,b in ipairs(list) do
        local col=math.floor((bi-1)/rowsPerCol)
        local row=(bi-1)%rowsPerCol
        local bx=x+col*(colW+gap)+pad
        local by=y+pad+vehBar+row*(bh+gap)
        local col, colH = b.c, b.ch
        if b.id == "tp" then
            col = tp and Color(60, 160, 80) or b.c
            colH = tp and Color(80, 180, 100) or b.ch
        end
        local isArmed = (armed.id == b.id)
        if isArmed then
            col, colH = Color(210, 70, 60), Color(230, 90, 80)
        end
        local hov = mx >= bx and mx <= bx + bw and my >= by and my <= by + bh
        draw.RoundedBox(4, bx, by, bw, bh, hov and colH or col)
        local lbl = type(b.l) == "function" and b.l() or b.l
        if isArmed then lbl = "⚠ Ещё раз — подтвердить" end
        draw.SimpleText(lbl, "GRMCtx_Normal", bx + bw / 2, by + bh / 2, Color(255, 255, 255, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if hov and click then
            local cd = cooldowns[b.id]
            if not cd or CurTime() > cd then
                if b.confirm and not isArmed then
                    -- опасное действие: первое нажатие только «взводит» кнопку на 3 с
                    armed.id = b.id
                    armed.untilT = CurTime() + 3
                else
                    cooldowns[b.id] = CurTime() + 0.3
                    armed.id = nil
                    b.fn()
                end
            end
        end
    end
    wasDown = down
end

-- Убираем старые хуки
hook.Remove("OnContextMenuOpen", "GRM_Ctx_Open")
hook.Remove("Think", "GRM_Ctx_CheckQ")
hook.Remove("PlayerBindPress", "GRM_Ctx_Toggle")

hook.Add("OnContextMenuOpen", "GRM_Ctx_Open", function()
    -- Сразу блокируем стандартное меню (return true)
    -- Через кадр проверяем, что это не Q
    timer.Simple(0, function()
        if g_SpawnMenu and g_SpawnMenu:IsVisible() then
            visible = false
            gui.EnableScreenClicker(false)
            return
        end
        visible = true
        wasDown = input.IsMouseDown(MOUSE_LEFT)
        req()
        gui.EnableScreenClicker(true)
    end)
    return true
end)

hook.Add("OnContextMenuClose", "GRM_Ctx_Close", function()
    visible = false
    gui.EnableScreenClicker(false)
end)

hook.Add("PostRenderVGUI", "GRM_Ctx_Draw", drawMenu)

print("[GRM CTX] Client loaded")

end
