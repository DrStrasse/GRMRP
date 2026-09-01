--[[--------------------------------------------------------------------
    grm_keypad — Интерактивный Кейпад GRM (Код 70)
    Поддерживает:
      - 3D2D экран и интерактивные кнопки на корпусе
      - Режимы: PIN-код, Доступ Фракции, Платный проход (GRM Cash)
      - Прямую связку с Fading Door и Numpad
      - Взлом с помощью QTE-Взломщика ds_lockpick
----------------------------------------------------------------------]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.PrintName = "FFD Keypad"
ENT.Author = "GRM"
ENT.Contact = ""
ENT.Purpose = "Электронный кодовый замок с 3D2D дисплеем"
ENT.Instructions = "Нажимайте кнопки на экране или используйте [E]"
ENT.Category = "GRM"

ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Password")
    self:NetworkVar("String", 1, "DisplayText")
    self:NetworkVar("Int",    0, "Status")      -- 0: Normal, 1: Granted, 2: Denied
    self:NetworkVar("Int",    1, "Cost")        -- Платный проход в GRM
    self:NetworkVar("Int",    2, "Mode")        -- 0: PIN, 1: Faction, 2: Paid
    self:NetworkVar("String", 2, "Faction")     -- Код 104: список через запятую
end

-- ============================================================
-- Код 104/105 (находка 121/122): единая геометрия экрана кейпада.
-- Кейпад-модель (props_lab/keypad) смотрит лицом в +X: спавн — чистый
-- ent:SetAngles(HitNormal:Angle()) БЕЗ доп. поворотов.
-- ВАЖНО про ориентацию 3D2D (находка 122): по формуле вики GMod
-- pixel(x,y) -> world = pos + Rotate(ang)·(x·s, -y·s, 0), т.е. экран-X =
-- ang:Forward(), экран-Y(вниз) = ang:Right(). Попытки собрать угол
-- парой RotateAroundAxis давали ролл 180° — поэтому Код 105 строит угол
-- НАПРЯМУЮ из базиса модели: текст-вправо = -GetRight(), текст-вниз =
-- -GetUp(), нормаль наружу = GetForward()  →  AngleEx.
-- Размер панели — НЕ константами, а по морде модели (OBBMins/OBBMaxs):
-- панель автоподгоняется под грань, никаких «съехавших наполовину».
-- ============================================================
ENT.ScreenW      = 144            -- размер клиентской раскладки, px
ENT.ScreenH      = 220
ENT.ScreenPad    = 0.12           -- на сколько экран приподнят над гранью

ENT.Buttons = {
    { text = "1", x = 12, y = 80,  w = 36, h = 28 },
    { text = "2", x = 54, y = 80,  w = 36, h = 28 },
    { text = "3", x = 96, y = 80,  w = 36, h = 28 },
    { text = "4", x = 12, y = 114, w = 36, h = 28 },
    { text = "5", x = 54, y = 114, w = 36, h = 28 },
    { text = "6", x = 96, y = 114, w = 36, h = 28 },
    { text = "7", x = 12, y = 148, w = 36, h = 28 },
    { text = "8", x = 54, y = 148, w = 36, h = 28 },
    { text = "9", x = 96, y = 148, w = 36, h = 28 },
    { text = "CLR", x = 12, y = 182, w = 36, h = 28 },
    { text = "0",   x = 54, y = 182, w = 36, h = 28 },
    { text = "OK",  x = 96, y = 182, w = 36, h = 28 },
}

-- рамка экрана: центр морды + масштаб px→юниты по реальному размеру грани
function ENT:KeypadScreenFrame()
    local W = tonumber(self.ScreenW) or 144
    local H = tonumber(self.ScreenH) or 220
    local center, w, h = nil, nil, nil
    pcall(function()
        local mins, maxs = self:OBBMins(), self:OBBMaxs()
        if mins and maxs and (maxs.y - mins.y) > 0.3 and (maxs.z - mins.z) > 0.3 then
            w = maxs.y - mins.y       -- ширина грани (модель-«право»)
            h = maxs.z - mins.z       -- высота грани
            center = self:GetPos()
                + self:GetForward() * (maxs.x + (self.ScreenPad or 0.12))
                - self:GetRight() * ((mins.y + maxs.y) / 2)
                + self:GetUp() * ((mins.z + maxs.z) / 2)
        end
    end)
    if not center then -- фолбэк: прежние константы
        w, h = 4.8, 7.7
        center = self:GetPos() + self:GetForward() * 1.6
    end
    local s = math.min(w / W, h / H)
    if not s or s <= 0 then s = 0.035 end
    return { center = center, scale = s }
end

function ENT:KeypadScreenScale()
    return self:KeypadScreenFrame().scale
end

-- PIN: только цифры, без пробелов, максимум 10. Иначе «1234 » / «12 34»
-- из поля ввода никогда не совпадёт с тем, что набрали на кнопках.
function ENT.SanitizePin(s)
    s = string.Trim(tostring(s or ""))
    s = string.gsub(s, "%D", "")
    if #s > 10 then s = string.sub(s, 1, 10) end
    return s
end

-- Origin — правый верх грани. 3D2D в Source: Right = Up×Forward,
-- поэтому Forward=−GetRight, Up=+GetForward даёт X влево по морде
-- и Y вниз. Менять базис нельзя — панель встаёт вверх ногами.
function ENT:KeypadScreenOrigin()
    local fr = self:KeypadScreenFrame()
    return fr.center
        + self:GetRight() * ((tonumber(self.ScreenW) or 144) * fr.scale / 2)
        + self:GetUp() * ((tonumber(self.ScreenH) or 220) * fr.scale / 2)
end

function ENT:KeypadScreenAngles()
    return (-self:GetRight()):AngleEx(self:GetForward())
end

-- Попадание в той же системе, что и 3D2D: X = −GetRight, Y = −GetUp.
function ENT:KeypadButtonAt(hitPos)
    if not hitPos then return nil end
    local s = self:KeypadScreenScale()
    local rel = hitPos - self:KeypadScreenOrigin()
    local x = rel:Dot(-self:GetRight()) / s
    local y = rel:Dot(-self:GetUp()) / s
    for i, b in ipairs(self.Buttons or {}) do
        if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            return i, b
        end
    end
    return nil
end

-- Код 105: владелец кейпада — сам игрок ИЛИ онлайн-совпадение sid64
-- (permanent-восстановление: владелец мог перезайти/быть не в сети)
function ENT:IsKeypadOwner(ply)
    if not IsValid(ply) then return false end
    if ply == self.KeypadOwner then return true end
    local o = tostring(self.OwnerSID64 or "")
    local key = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or tostring(ply:SteamID64() or "")
    return o ~= "" and o == key
end

if SERVER then
    function ENT:IsKeypadLocked()
        return self:GetStatus() == 2 or self.IsGrantActive
    end

    -- Код 104: фракция с доступом может быть СПИСКОМ через запятую
    -- (чекбоксы в панели тулгана). Пустая строка — доступа никому.
    function ENT:IsFactionAllowed(facName)
        local fac = string.Trim(tostring(self:GetFaction() or ""))
        if fac == "" or facName == nil or facName == "" then return false end
        for f in string.gmatch(fac, "([^,]+)") do
            if string.Trim(f) == facName then return true end
        end
        return false
    end
end
