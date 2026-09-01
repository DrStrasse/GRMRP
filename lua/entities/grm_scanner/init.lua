--[[--------------------------------------------------------------------
    grm_scanner — init.lua (серверная логика FFD-сканера, Код 107)
    Сканирование: игрок подходит и жмёт [E] глядя на сканер → 0.9с
    анимации сканирования → строгая проверка ЕГО фракции по белому
    списку → допущен (открываются ПРИВЯЗАННЫЕ FFD-двери на hold-секунд,
    нумпад-сигнал владельцу) или отказ (красная вспышка ~2с).
    Код 109 (заказ владельца): авто-определение дверей по радиусу 250
    УДАЛЕНО — сканер открывает ТОЛЬКО двери из ручных связей FFD Link
    (инструмент «FFD Link»). Без связей не трогает ни одну дверь.
----------------------------------------------------------------------]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local SCAN_TIME   = 0.9   -- анимация сканирования
local DENY_TIME   = 2.0   -- красная вспышка отказа
-- Код 109: DOOR_RADIUS (250, авто-определение дверей) УДАЛЁН — двери
-- открываются только из ручных связей FFD Link (заказ владельца).
local AIM_RANGE   = 130   -- дистанция прицельного нажатия

-- ============================================================
-- ПЕРМ sh_grm_perm_entities v1.4.0: данные сканера едут в rec.data —
-- после рестарта сканер возвращается готовым к работе (список
-- фракций, сигнальные клавиши, задержка, владелец по sid64).
-- ============================================================
local function scannerPermExtract(ent)
    local rec = {
        faction = tostring(ent:GetFaction() or ""),
        granted = tonumber(ent.KeyGranted) or 1,
        denied  = tonumber(ent.KeyDenied) or 2,
        hold    = tonumber(ent.HoldTime) or 4,
        owner   = (IsValid(ent.ScannerOwner) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ent.ScannerOwner)) or ent.ScannerOwner:SteamID64() or "")) or tostring(ent.OwnerSID64 or ""),
    }
    -- Код 108: ручные связи с FFD-дверями едут в перм вместе со сканером
    if GRM.FFDLink and GRM.FFDLink.ExportData then
        rec.links = GRM.FFDLink.ExportData(ent)
    end
    return rec
end
local function scannerPermApply(ent, t)
    ent:SetFaction(tostring(t.faction or ""))
    ent.KeyGranted = math.Clamp(tonumber(t.granted) or 1, 1, 9)
    ent.KeyDenied  = math.Clamp(tonumber(t.denied) or 2, 1, 9)
    ent.HoldTime   = math.max(0.5, tonumber(t.hold) or 4)
    ent.OwnerSID64 = tostring(t.owner or "")
    if ent.OwnerSID64 ~= "" then
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64() or "") == ent.OwnerSID64 then
                ent.ScannerOwner = p
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
GRM.PermData.Extract["grm_scanner"] = scannerPermExtract
GRM.PermData.Apply["grm_scanner"] = scannerPermApply

if duplicator and duplicator.RegisterEntityModifier then
    duplicator.RegisterEntityModifier("GRM_ScannerData", function(ply, ent, data)
        if IsValid(ent) and istable(data) then
            scannerPermApply(ent, data)
        end
    end)
end

function ENT:Initialize()
    -- модель — та же «стенная панель с мордой в +X», геометрия доказана
    local mdl = "models/props_lab/keypad.mdl"
    if util.IsValidModel and not util.IsValidModel(mdl) then
        mdl = "models/props_lab/keypad.mdl" -- стоковая HL2-модель, почти не бывает битой
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end

    self:SetStatus(0)
    self:SetScannedName("")
    self:SetScannedFac("")

    self.KeyGranted = self.KeyGranted or 1
    self.KeyDenied = self.KeyDenied or 2
    self.HoldTime = self.HoldTime or 4
    self:SetFaction(self.Faction or "")
end

-- вспомогательно: открыть/закрыть FFD-двери. Код 108 (заказ владельца) +
-- Код 109 (запрет авто-связи): сканер трогает ТОЛЬКО двери из ручного
-- списка FFD Link. Радиусного авто-определения больше НЕТ (раньше сканер
-- сам хватал все FFD-двери в 250 юнитах — заказ владельца Кода 109:
-- «этого быть не должно»). Возвращаем захваченный список дверей, чтобы
-- по таймеру закрыть те же самые.
local function fadeDoorsNear(self, activate)
    if GRM.FFDLink and GRM.FFDLink.Count and GRM.FFDLink.Count(self) > 0 then
        local _, doors = GRM.FFDLink.Fade(self, activate)
        return doors or {}
    end
    return {}
end

function ENT:ProcessGrant(ply, fac)
    self:SetStatus(1)
    self:SetScannedFac(tostring(fac or ""))
    self:EmitSound("buttons/button3.wav", 75, 100)

    if IsValid(self.ScannerOwner) then
        numpad.Activate(self.ScannerOwner, self.KeyGranted)
    end

    -- Код 108/109: захватываем открытые двери (только ручные связи!) —
    -- по таймеру закроем те же. Связей нет → сканер не трогает ни одну
    -- дверь: авто-определения по радиусу больше нет (заказ Кода 109).
    local doorList = fadeDoorsNear(self, true)
    if (not (GRM.FFDLink and GRM.FFDLink.Count)) or GRM.FFDLink.Count(self) <= 0 then
        local now = CurTime()
        if (self.__grmNoLinkHint or 0) <= now then
            self.__grmNoLinkHint = now + 5
            local msg = "Сканер не привязан ни к одной двери: свяжите инструментом «FFD Link» (ЛКМ по сканеру → ЛКМ по двери)."
            if GRM.Notify then
                GRM.Notify(ply, msg, 255, 210, 90)
            elseif IsValid(ply) and ply.PrintMessage then
                ply:PrintMessage(HUD_PRINTTALK, msg)
            end
        end
    end

    local hold = math.max(0.5, tonumber(self.HoldTime) or 4)
    local idx = self:EntIndex()
    timer.Create("GRM_Scanner_Grant_" .. idx, hold, 1, function()
        if not IsValid(self) then return end
        self:SetStatus(0)
        self:SetScannedName("")
        self:SetScannedFac("")
        if IsValid(self.ScannerOwner) then
            numpad.Deactivate(self.ScannerOwner, self.KeyGranted)
        end
        for _, prop in ipairs(doorList or {}) do
            if IsValid(prop) and (prop.isFadingDoor or prop.isSlidingDoor) and prop.FadeDeactivate then
                prop:FadeDeactivate()
            end
        end
    end)
end

function ENT:ProcessDeny(ply, fac)
    self:SetStatus(2)
    self:SetScannedFac(tostring(fac or ""))
    self:EmitSound("buttons/button10.wav", 75, 100)
    -- Находка 179h: событие «отказ доступа» для сигнализации
    hook.Run("GRM_ScannerDenied", ply, self)

    if IsValid(self.ScannerOwner) then
        numpad.Activate(self.ScannerOwner, self.KeyDenied)
        timer.Simple(1.5, function()
            if IsValid(self) and IsValid(self.ScannerOwner) then
                numpad.Deactivate(self.ScannerOwner, self.KeyDenied)
            end
        end)
    end

    timer.Create("GRM_Scanner_Deny_" .. self:EntIndex(), DENY_TIME, 1, function()
        if not IsValid(self) then return end
        self:SetStatus(0)
        self:SetScannedName("")
        self:SetScannedFac("")
    end)
end

-- старт сканирования НАЖАВШЕГО (человек рядом со сканером — он сам)
function ENT:StartScan(ply)
    if not IsValid(ply) then return end
    if self:GetStatus() ~= 0 then return end -- занят: идёт сканирование/вспышка

    self:SetStatus(3) -- сканирование
    self:SetScannedName(ply:Nick() or "?")
    self:SetScannedFac("")
    self:EmitSound("buttons/button9.wav", 75, 110)

    local idx = self:EntIndex()
    timer.Create("GRM_Scanner_Resolve_" .. idx, SCAN_TIME, 1, function()
        if not IsValid(self) then return end
        if not IsValid(ply) then
            self:SetStatus(0)
            self:SetScannedName("")
            return
        end
        -- СТРОГАЯ проверка фракции нажавшего — без байпасов (находка 123)
        local fac = self:ScannerFactionOf(ply)
        if self:IsFactionAllowed(fac) then
            self:ProcessGrant(ply, fac)
        else
            if GRM.Notify then
                --[[ Показываем ЧЕЛОВЕЧЕСКИЕ названия организаций, а не
                     внутренние ключи: игрок читал «Сканер: доступ ограничен
                     [police_order]» и не понимал, кого сюда пускают. ]]
                local names = {}
                for raw in string.gmatch(string.Trim(tostring(self:GetFaction() or "")), "([^,]+)") do
                    local key = string.Trim(raw)
                    if key ~= "" then
                        local display = key
                        if GRM.Factions and GRM.Factions.DisplayName then
                            display = GRM.Factions.DisplayName(key) or key
                        end
                        names[#names + 1] = display
                    end
                end
                local white = table.concat(names, ", ")
                GRM.Notify(ply, "Сканер: доступ ограничен" .. (white ~= "" and (" — " .. white) or ""), 255, 100, 100)
            end
            self:ProcessDeny(ply, fac)
        end
    end)
end

function ENT:Use(ply)
    -- общий Use пуст: нажатие — только прицелом (KeyPress ниже), чтобы
    -- не было двойных срабатываний (урок кейпада, находка 121)
end

-- нажатие [E] прицелом по сканеру (геометрия не нужна — зона большая)
hook.Add("KeyPress", "GRM_Scanner_AimPress", function(ply, key)
    if key ~= IN_USE then return end
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    if not tr then return end
    local ent = tr.Entity
    if not (IsValid(ent) and ent:GetClass() == "grm_scanner") then return end
    if ply:GetShootPos():DistToSqr(ent:GetPos()) > (AIM_RANGE * AIM_RANGE) then return end
    local now = CurTime()
    if (ply.__grmScannerNextScan or 0) > now then return end
    ply.__grmScannerNextScan = now + 0.4 -- один человек не штормит
    ent:StartScan(ply)
end)
