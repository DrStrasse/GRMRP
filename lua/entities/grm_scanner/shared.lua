--[[--------------------------------------------------------------------
    grm_scanner — FFD Scanner (Код 107, заказ владельца)
    Сканер фракционного доступа. НЕ кейпад: никакого ввода кода — человек
    подходит и жмёт [E], сканер читает его и решает по его фракции:
    фракция из белого списка → допущен (открывает FFD-двери рядом и даёт
    сигнал нумпада как кейпад), иначе → отказ. ПРОВЕРКА СТРОГАЯ ДЛЯ ВСЕХ
    (без байпасов владельца/суперадмина — находка 123: байпасы слепят
    самого тестирующего админа; владелец нужен сканеру лишь как приёмник
    нумпад-сигнала).

    Геометрия 3D2D — тот же доказанный базис, что кейпад-Код 105: угол из
    базиса модели одной строкой AngleEx, масштаб — по морде модели (OBB).
----------------------------------------------------------------------]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.PrintName = "FFD Scanner"
ENT.Author = "GRM"
ENT.Contact = ""
ENT.Purpose = "Сканер фракционного доступа: подойдите и нажмите [E]"
ENT.Instructions = "Сканирует стоящего рядом человека и определяет его фракционный доступ"
ENT.Category = "GRM"

ENT.Spawnable = true
ENT.AdminSpawnable = true

-- Статусы: 0 — ожидание, 1 — допущен, 2 — отказ, 3 — сканирование
function ENT:SetupDataTables()
    self:NetworkVar("Int",    0, "Status")
    self:NetworkVar("String", 0, "ScannedName")   -- имя просканированного
    self:NetworkVar("String", 1, "ScannedFac")    -- его фракция (или "")
    self:NetworkVar("String", 2, "Faction")       -- белый список, через запятую
end

-- раскладка клиентской панели (панели без кнопок; квадрат вместо полосы)
ENT.ScreenW      = 150
ENT.ScreenH      = 118
ENT.ScreenPad    = 0.12

-- рамка экрана: центр морды + масштаб px→юниты по реальному размеру грани
function ENT:ScannerScreenFrame()
    local W = tonumber(self.ScreenW) or 150
    local H = tonumber(self.ScreenH) or 118
    local center, w, h = nil, nil, nil
    pcall(function()
        local mins, maxs = self:OBBMins(), self:OBBMaxs()
        if mins and maxs and (maxs.y - mins.y) > 0.3 and (maxs.z - mins.z) > 0.3 then
            w = maxs.y - mins.y
            h = maxs.z - mins.z
            center = self:GetPos()
                + self:GetForward() * (maxs.x + (self.ScreenPad or 0.12))
                - self:GetRight() * ((mins.y + maxs.y) / 2)
                + self:GetUp() * ((mins.z + maxs.z) / 2)
        end
    end)
    if not center then
        w, h = 4.8, 3.8
        center = self:GetPos() + self:GetForward() * 1.6
    end
    local s = math.min(w / W, h / H)
    if not s or s <= 0 then s = 0.032 end
    return { center = center, scale = s }
end

function ENT:ScannerScreenScale()
    return self:ScannerScreenFrame().scale
end

function ENT:ScannerScreenOrigin()
    local fr = self:ScannerScreenFrame()
    return fr.center
        + self:GetRight() * ((tonumber(self.ScreenW) or 150) * fr.scale / 2)
        + self:GetUp() * ((tonumber(self.ScreenH) or 118) * fr.scale / 2)
end

-- базис плоскости 3D2D напрямую из базиса модели (находка 122):
-- экран-X = -GetRight, экран-Y(вниз) = -GetUp, нормаль = +GetForward
function ENT:ScannerScreenAngles()
    return (-self:GetRight()):AngleEx(self:GetForward())
end

-- приёмник нумпад-сигнала (не пропуск!): владелец-человек или sid64 из перма
function ENT:IsScannerOwner(ply)
    if not IsValid(ply) then return false end
    if ply == self.ScannerOwner then return true end
    local o = tostring(self.OwnerSID64 or "")
    local key = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or tostring(ply:SteamID64() or "")
    return o ~= "" and o == key
end

if SERVER then
    -- фракция с доступом может быть СПИСКОМ через запятую (чекбоксы тулгана)
    function ENT:IsFactionAllowed(facName)
        local fac = string.Trim(tostring(self:GetFaction() or ""))
        if fac == "" or facName == nil or facName == "" then return false end
        for f in string.gmatch(fac, "([^,]+)") do
            if string.Trim(f) == facName then return true end
        end
        return false
    end

    -- фракция игрока по серверному глобалу Factions (как было у кейпада)
    function ENT:ScannerFactionOf(ply)
        if not (Factions and IsValid(ply) and ply.SteamID) then return nil end
        for fName, fData in pairs(Factions) do
            local member = GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(fData, ply)
            if not member and not GRM.Identity then
                member = fData.Members[ply:SteamID()] or fData.Members[ply:SteamID64()]
            end
            if istable(fData) and istable(fData.Members) and member then
                return fName
            end
        end
        return nil
    end
end
