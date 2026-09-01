--[[--------------------------------------------------------------------
    grm_keypad — init.lua (Серверный обработчик кейпада)
    Код 104 (находка 121): кнопки нажимаются ПРИЦЕЛОМ + E (как в модовых
    кейпадах); вспышка кнопки на экране всех клиентов (GRM_KeypadPress).
    Код 106/107: PIN — строгое сравнение с тримом ДЛЯ ВСЕХ; кейпад
    переведён на режим «только PIN» — фракционный доступ теперь у
    FFD Scanner (lua/entities/grm_scanner), толл-режим удалён.
    Код 109 (заказ владельца): авто-определение дверей по радиусу 250
    УДАЛЕНО — кейпад открывает ТОЛЬКО двери из ручных связей FFD Link
    (инструмент «FFD Link»). Без связей не трогает ни одну дверь.
----------------------------------------------------------------------]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("GRM_KeypadPress")
util.AddNetworkString("GRM_KeypadPIN")

-- ============================================================
-- Код 105 (находка 122): админский ПЕРМ-кейпад. Данные кейпада едут в
-- базу перм-энтити (sh_grm_perm_entities v1.3.0): /permadd по кейпаду
-- фиксирует PIN/режим/цену/список фракций/кнопки сигналов/задержку/
-- владельца — после рестарта сервера или админ-перезагрузки кейпад
-- встаёт на место ГОТОВЫМ К РАБОТЕ, а не пустышкой с 1234.
-- ============================================================
-- ============================================================
-- Код 107 (заказ владельца): КЕЙПАД ТЕПЕРЬ ТОЛЬКО PIN-РЕЖИМ.
-- Фракционный доступ переехал в новый FFD Scanner (grm_scanner) —
-- сканирует стоящего рядом человека и решает по его фракции.
-- Толл-режим тоже убран как неиспользуемый. NetworkVar Mode и поля
-- Cost/Faction оставлены лишь для совместимости старых перм-баз
-- (Apply ниже всегда принудительно ставит режим 0).
-- ============================================================
local function keypadPermExtract(ent)
    local rec = {
        password = ENT.SanitizePin(ent:GetPassword() or "1234"),
        mode     = 0, -- Код 107: сохраняем принудительно PIN
        cost     = 0,
        faction  = "",
        granted  = tonumber(ent.KeyGranted) or 1,
        denied   = tonumber(ent.KeyDenied) or 2,
        hold     = tonumber(ent.HoldTime) or 5,
        owner    = (IsValid(ent.KeypadOwner) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ent.KeypadOwner)) or ent.KeypadOwner:SteamID64() or "")) or tostring(ent.OwnerSID64 or ""),
    }
    -- Код 108: ручные связи с FFD-дверями едут в перм вместе с кейпадом
    if GRM.FFDLink and GRM.FFDLink.ExportData then
        rec.links = GRM.FFDLink.ExportData(ent)
    end
    return rec
end
local function keypadPermApply(ent, t)
    -- находка 123-про: пароль со стены конвара может прийти с хвостовым
    -- пробелом — до Кода 106 это маскировал байпас и «верный PIN → отказ».
    local pw = ENT.SanitizePin(t.password or "1234")
    ent:SetPassword(pw ~= "" and pw or "1234")
    ent:SetMode(0)  -- Код 107: только PIN, даже из старой базы с mode 1/2
    ent:SetCost(0)
    ent:SetFaction("")
    ent.KeyGranted = math.Clamp(tonumber(t.granted) or 1, 1, 9)
    ent.KeyDenied  = math.Clamp(tonumber(t.denied) or 2, 1, 9)
    ent.HoldTime   = math.max(0.5, tonumber(t.hold) or 5)
    ent.OwnerSID64 = tostring(t.owner or "")
    if ent.OwnerSID64 ~= "" then
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64() or "") == ent.OwnerSID64 then
                ent.KeypadOwner = p
                break
            end
        end
    end
    -- Код 108: ручные связи с FFD-дверями обратно из перма
    if GRM.FFDLink and GRM.FFDLink.ImportData then
        GRM.FFDLink.ImportData(ent, istable(t.links) and t.links or {})
    end
end
GRM = GRM or {}
GRM.PermData = GRM.PermData or { Extract = {}, Apply = {} }
GRM.PermData.Extract = GRM.PermData.Extract or {}
GRM.PermData.Apply = GRM.PermData.Apply or {}
GRM.PermData.Extract["grm_keypad"] = keypadPermExtract
GRM.PermData.Apply["grm_keypad"] = keypadPermApply

if duplicator and duplicator.RegisterEntityModifier then
    duplicator.RegisterEntityModifier("GRM_KeypadData", function(ply, ent, data)
        if IsValid(ent) and istable(data) then
            keypadPermApply(ent, data)
        end
    end)
end

function ENT:Initialize()
    self:SetModel("models/props_lab/keypad.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end

    self:SetStatus(0)
    self:SetDisplayText("")
    self.CurrentInput = ""

    self.KeyGranted = self.KeyGranted or 1
    self.KeyDenied = self.KeyDenied or 2
    self.HoldTime = self.HoldTime or 5

    -- Код 107: кейпад = только PIN-режим, навсегда
    self:SetMode(0)
    self:SetCost(0)
    self:SetFaction("")
    if ENT.SanitizePin then
        local pw = ENT.SanitizePin(self:GetPassword() or "")
        self:SetPassword(pw ~= "" and pw or "1234")
    end
end

function ENT:ProcessGrant(ply)
    if self:IsKeypadLocked() then return end

    self:SetStatus(1) -- Granted
    self.IsGrantActive = true
    self:EmitSound("buttons/button3.wav", 75, 100)

    -- Посылаем сигнал Numpad
    if self.KeypadOwner and IsValid(self.KeypadOwner) then
        numpad.Activate(self.KeypadOwner, self.KeyGranted)
    end

    -- Код 108 (заказ владельца) + Код 109 (запрет авто-связи): двери
    -- открываются ТОЛЬКО из ручного списка FFD Link. Радиусного авто-
    -- определения больше НЕТ: кейпад без связей не трогает ни одну дверь
    -- (раньше он сам хватал все FFD-двери в 250 юнитах — заказ владельца
    -- Кода 109: «этого быть не должно»).
    -- Список ЗАХВАТЫВАЕМ: по таймеру гасим ровно те же двери.
    local doorList = {}
    if GRM.FFDLink and GRM.FFDLink.Count and GRM.FFDLink.Count(self) > 0 then
        local _, doors = GRM.FFDLink.Fade(self, true)
        for _, d in ipairs(doors or {}) do doorList[#doorList + 1] = d end
    else
        -- видимая подсказка (с антиспамом), почему ничего не открылось
        local now = CurTime()
        if (self.__grmNoLinkHint or 0) <= now then
            self.__grmNoLinkHint = now + 5
            local msg = "Кейпад не привязан ни к одной двери: свяжите инструментом «FFD Link» (ЛКМ по кейпаду → ЛКМ по двери)."
            if GRM.Notify then
                GRM.Notify(ply, msg, 255, 210, 90)
            elseif IsValid(ply) and ply.PrintMessage then
                ply:PrintMessage(HUD_PRINTTALK, msg)
            end
        end
    end

    -- Удерживаем сигнал
    local hold = math.max(0.5, tonumber(self.HoldTime) or 5)
    timer.Create("GRM_Keypad_Grant_" .. self:EntIndex(), hold, 1, function()
        if not IsValid(self) then return end
        self:SetStatus(0)
        self:SetDisplayText("")
        self.CurrentInput = ""
        self.IsGrantActive = false

        if self.KeypadOwner and IsValid(self.KeypadOwner) then
            numpad.Deactivate(self.KeypadOwner, self.KeyGranted)
        end

        for _, prop in ipairs(doorList) do
            if IsValid(prop) and (prop.isFadingDoor or prop.isSlidingDoor) and prop.FadeDeactivate then
                prop:FadeDeactivate()
            end
        end
    end)
end

function ENT:ProcessDeny(ply)
    if self:IsKeypadLocked() then return end

    self:SetStatus(2) -- Denied
    self.CurrentInput = ""
    self:EmitSound("buttons/button10.wav", 75, 100)
    -- Находка 179h: событие «неверный PIN» для сигнализации
    hook.Run("GRM_KeypadDenied", ply, self)

    if self.KeypadOwner and IsValid(self.KeypadOwner) then
        numpad.Activate(self.KeypadOwner, self.KeyDenied)
        timer.Simple(1.5, function()
            if IsValid(self) and IsValid(self.KeypadOwner) then
                numpad.Deactivate(self.KeypadOwner, self.KeyDenied)
            end
        end)
    end

    timer.Create("GRM_Keypad_Deny_" .. self:EntIndex(), 1.8, 1, function()
        if not IsValid(self) then return end
        self:SetStatus(0)
        self:SetDisplayText("")
    end)
end

function ENT:PressButton(btn, ply)
    if self:IsKeypadLocked() then return end

    -- Код 107: кейпад — ТОЛЬКО PIN-режим (фракционный доступ — у
    -- FFD Scanner, grm_scanner). Поля Mode/Cost/Faction мёртвы.
    if btn == "CLR" then
        self.CurrentInput = ""
        self:SetDisplayText("")
        self:EmitSound("buttons/button14.wav", 60, 120)
        return
    end

    if btn == "OK" then
        -- Код 106 (находка 123): PIN — СТРОГОЕ сравнение ДЛЯ ВСЕХ, без
        -- байпасов владельца/суперадмина (они делали кейпад «неразличающим»
        -- для самого тестирующего админа). Код 107: обе стороны ещё и
        -- ТРИМЯТСЯ — конварный пароль с хвостовым пробелом (поле ввода
        -- DForm не обрезает) раньше давал «верный PIN → отказ».
        local targetPass = string.Trim(tostring(self:GetPassword() or ""))
        local typed = string.Trim(tostring(self.CurrentInput or ""))
        if typed ~= "" and typed == targetPass then
            self:ProcessGrant(ply)
        else
            self:ProcessDeny(ply)
        end
        return
    end

    -- Код 107: кап ввода 6 → 10 цифр (длинные PIN тоже набираются до конца)
    if #self.CurrentInput < 10 then
        self.CurrentInput = self.CurrentInput .. tostring(btn)
        self:SetDisplayText(string.rep("*", #self.CurrentInput))
        self:EmitSound("buttons/button14.wav", 60, 100 + #self.CurrentInput * 5)
    else
        -- насыщение поля — слышимый, но безмолвный отказ раньше путал
        self:EmitSound("buttons/button10.wav", 65, 140)
    end
end

function ENT:Use(ply)
    -- Код 104: общий E=OK убран — кнопки жмутся прицелом (см. хук ниже),
    -- чтобы не было двойных срабатываний «и цифра, и OK».
end

-- ============================================================
-- Код 104 (находка 121): нажатие кнопок ПРИЦЕЛОМ + E.
-- Сервер сам считает, какая кнопка под HitPos (геометрия общая, shared),
-- клиент ничего не шлёт — протокол не расширяем пользовательским вводом.
-- ============================================================
hook.Add("KeyPress", "GRM_Keypad_AimPress", function(ply, key)
    if key ~= IN_USE then return end
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    if not tr then return end
    local ent = tr.Entity
    if not (IsValid(ent) and ent:GetClass() == "grm_keypad") then return end
    if ply:GetShootPos():DistToSqr(ent:GetPos()) > (130 * 130) then return end
    local now = CurTime()
    if (ply.__grmKeypadNextPress or 0) > now then return end
    -- Код 107: анти-дабл 0.15 → 0.06 — 0.15 съедал цифры быстрого набора
    -- («правильный PIN → отказ»: человек спокойно тычет чаще 6-7 раз/с)
    ply.__grmKeypadNextPress = now + 0.06
    local idx, b = ent:KeypadButtonAt(tr.HitPos)
    if not (idx and b) then return end
    ent:PressButton(b.text, ply)
    -- вспышка нажатой кнопки на экранах всех клиентов
    net.Start("GRM_KeypadPress")
        net.WriteEntity(ent)
        net.WriteUInt(idx, 8)
    net.Broadcast()
end)

-- Окно PIN (E по экрану) и смена кода владельцем. Цифры только.
net.Receive("GRM_KeypadPIN", function(_, ply)
    if not IsValid(ply) then return end
    local now = CurTime()
    if (ply.__grmKeypadPinNext or 0) > now then return end
    ply.__grmKeypadPinNext = now + 0.35
    local ent = net.ReadEntity()
    local pin = ENT.SanitizePin(net.ReadString())
    local isSet = net.ReadBool()
    if not (IsValid(ent) and ent:GetClass() == "grm_keypad") then return end
    if ply:GetShootPos():DistToSqr(ent:GetPos()) > (160 * 160) then return end
    if isSet then
        if not ((ent.IsKeypadOwner and ent:IsKeypadOwner(ply)) or ply:IsSuperAdmin()) then return end
        if pin == "" then
            if GRM.Notify then GRM.Notify(ply, "PIN пустой — не сохранён.", 255, 180, 80) end
            return
        end
        ent:SetPassword(pin)
        if GRM.Notify then
            GRM.Notify(ply, "PIN кейпада задан (" .. #pin .. " цифр).", 100, 220, 100)
        end
        return
    end
    ent.CurrentInput = pin
    ent:PressButton("OK", ply)
end)
