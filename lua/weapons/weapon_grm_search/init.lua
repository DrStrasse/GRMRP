AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_Search_Result")
util.AddNetworkString("GRM_Search_Confiscate")

function SWEP:Initialize()
    self:SetHoldType("normal")
end

function SWEP:PrimaryAttack()
    if not self.Owner:IsPlayer() then return end

    local trace = self.Owner:GetEyeTrace()
    local target = trace.Entity

    if not target:IsPlayer() or not target:Alive() then
        self.Owner:ChatPrint("[Обыск] Наведитесь на живого игрока")
        return
    end

    -- Проверка дистанции
    if self.Owner:GetPos():Distance(target:GetPos()) > 100 then
        self.Owner:ChatPrint("[Обыск] Слишком далеко (макс. 100 единиц)")
        return
    end

    -- Проверка прав (только полиция или админ)
    if not self:CanSearch(self.Owner) then
        self.Owner:ChatPrint("[Обыск] Только полиция может проводить обыск!")
        return
    end

    -- Начинаем обыск
    self:PerformSearch(self.Owner, target)
end

function SWEP:SecondaryAttack()
    if not self.Owner:IsPlayer() then return end

    local trace = self.Owner:GetEyeTrace()
    local target = trace.Entity

    if not target:IsPlayer() or not target:Alive() then
        self.Owner:ChatPrint("[Обыск] Наведитесь на живого игрока")
        return
    end

    if self.Owner:GetPos():Distance(target:GetPos()) > 100 then
        self.Owner:ChatPrint("[Обыск] Слишком далеко")
        return
    end

    -- Проверка документов
    self:CheckDocuments(self.Owner, target)
end

-- CanSearch теперь в shared.lua

function SWEP:PerformSearch(searcher, target)
    local found = {}

    -- Проверяем инвентарь
    if GRM.Inventory and GRM.Inventory.GetPlayerInv then
        local inv = GRM.Inventory.GetPlayerInv(target)
        if istable(inv) and istable(inv.slots) then
            for _, slot in pairs(inv.slots) do
                if istable(slot) and slot.id then
                    -- Запрещённые предметы
                    for _, contraband in ipairs(self.Contraband) do
                        if slot.id == contraband then
                            found[#found + 1] = {type = "item", id = slot.id, count = slot.count or 1}
                        end
                    end
                end
            end
        end
    end

    -- Проверяем оружие
    local weapons = target:GetWeapons()
    for _, wep in ipairs(weapons) do
        local class = wep:GetClass()
        for _, contraband in ipairs(self.ContrabandWeapons) do
            if class == contraband then
                found[#found + 1] = {type = "weapon", id = class}
            end
        end
    end

    -- Отправляем результат обыскивающему (UI с чекбоксами)
    net.Start("GRM_Search_Result")
        net.WriteEntity(searcher)
        net.WriteEntity(target)
        net.WriteUInt(#found, 8)
        for _, item in ipairs(found) do
            net.WriteString(item.type)
            net.WriteString(item.id)
            net.WriteUInt(item.count or 1, 8)
        end
    net.Send(searcher)

    -- Уведомление цели
    if GRM.Notify then
        GRM.Notify(target, "У вас провели обыск.", 255, 200, 100)
    end

    -- Логирование
    self:LogSearch(searcher, target, found)
end

function SWEP:CheckDocuments(searcher, target)
    if not IsValid(target) or not target:IsPlayer() then return end

    local targetName = target:GetNWString("GRM_RPName", "")
    if targetName == "" then targetName = target:Nick() end

    local charKey = (GRM.Identity and isfunction(GRM.Identity.CharacterKey) and GRM.Identity.CharacterKey(target)) or (target:SteamID64() .. ":char1")

    -- 1. Паспорт
    local pass = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.passports and GRM.Documents.Registry.passports[charKey]
    local passStr = pass and string.format("Серия %s №%s (ФИО: %s, %s)", pass.series or "GRM", pass.number or "—", pass.fullName or targetName, pass.status or "Действителен") or "Не оформлен в реестре"

    -- 2. Служебное удостоверение
    local badge = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.badges and GRM.Documents.Registry.badges[charKey]
    local badgeStr = badge and string.format("%s (Звание: %s, Отдел: %s, Жетон: %s)", badge.faction or "Ведомство", badge.role or "—", badge.department or "—", badge.number or "—") or "Отсутствует"

    -- 3. Военный билет
    local mil = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.military and GRM.Documents.Registry.military[charKey]
    local milStr = mil and string.format("№ %s (Звание: %s, Часть: %s, %s)", mil.number or "—", mil.rank or "—", mil.formation or "—", mil.status or "Действителен") or "Не выдан"

    -- 4. Водительские права (Дорожная Инспекция)
    local lic = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.licenses and GRM.Documents.Registry.licenses[charKey]
    local licStr = lic and string.format("№ %s (Категории: %s, %s)", lic.number or "—", lic.categoriesStr or "B", lic.status or "Действительно") or "Не получены"

    -- 5. Военные водительские права (ВАИ)
    local milLic = GRM.Documents and GRM.Documents.Registry and GRM.Documents.Registry.milLicenses and GRM.Documents.Registry.milLicenses[charKey]
    local milLicStr = milLic and string.format("№ %s (ВУС: %s, Кат: %s, %s)", milLic.number or "—", milLic.vus or "ВУС-837", milLic.categoriesStr or "B-В", milLic.status or "Действительно") or "Не выданы"

    -- 6. Медкарта (единая: одна запись на персонажа, без авто-создания)
    local card = (GRM.Medical and isfunction(GRM.Medical.HasCard) and GRM.Medical.HasCard(charKey)) and GRM.Medical.Cards[charKey] or nil
    local medStr = card and string.format("Группа: %s | Категория: %s", (card.blood ~= "" and card.blood or "—"), (card.fitnessCategory or "А")) or "Не заведена"

    -- 7. Оружие
    local wepCount = #target:GetWeapons()

    local msg = string.format("══════════ [ДОСЬЕ ДОКУМЕНТОВ: %s] ══════════\n• Паспорт: %s\n• Удостоверение: %s\n• Военный билет: %s\n• Права (Дорожная Инспекция): %s\n• Права (ВАИ): %s\n• Медкарта: %s\n• Оружие при себе: %d ед.", targetName, passStr, badgeStr, milStr, licStr, milLicStr, medStr, wepCount)
    searcher:ChatPrint(msg)
    if GRM.Notify then GRM.Notify(searcher, "Досье документов проверено: " .. targetName, 120, 200, 255) end
end

function SWEP:LogSearch(searcher, target, found)
    -- Записываем в лог
    local log = string.format("[ОБЫСК] %s обыскал %s | Найдено: %d предметов",
        searcher:Nick(),
        target:Nick(),
        #found
    )

    print(log)

    -- Отправляем в чат всем игрокам с доступом
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(ply) and self:CanSearch(ply) then
            ply:ChatPrint(log)
        end
    end
end

-- Изъятие предмета (по запросу от клиента)
net.Receive("GRM_Search_Confiscate", function(_, searcher)
    if not IsValid(searcher) then return end
    if not searcher:IsPlayer() then return end

    -- Проверяем доступ
    local canSearch = false
    if searcher:IsSuperAdmin() then
        canSearch = true
    elseif Factions then
        for _, factionName in ipairs(GRM.Search.AllowedFactions) do
            local f = Factions[factionName]
            if istable(f) and istable(f.Members) then
                local sid = searcher:SteamID()
                local sid64 = searcher:SteamID64()
                local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(searcher)) or sid64
                if (GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f, searcher))
                    or (not GRM.Identity and (f.Members[sid] or f.Members[sid64])) then
                    canSearch = true
                    break
                end
            end
        end
    end

    if not canSearch then return end

    local target = net.ReadEntity()
    if not IsValid(target) or not target:IsPlayer() then return end

    local itemType = net.ReadString()
    local itemID = net.ReadString()
    local count = net.ReadUInt(8)

    if itemType == "item" then
        GRM.Inventory.RemoveItem(target, itemID, count)
        if GRM.Notify then
            GRM.Notify(searcher, "Изъято: " .. itemID .. " x" .. count, 100, 220, 100)
            GRM.Notify(target, "У вас изъяли: " .. itemID, 255, 100, 100)
        end
    elseif itemType == "weapon" then
        target:StripWeapon(itemID)
        if GRM.Notify then
            GRM.Notify(searcher, "Изъято оружие: " .. itemID, 100, 220, 100)
            GRM.Notify(target, "У вас изъяли оружие: " .. itemID, 255, 100, 100)
        end
    end

    print("[ИЗЪЯТИЕ] " .. searcher:Nick() .. " изъял " .. itemID .. " у " .. target:Nick())
end)

-- Статическая проверка доступа (для net.Receive)
function SWEP:CanSearchStatic(ply)
    return SWEP:CanSearch(ply)
end
