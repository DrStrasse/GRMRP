--[[--------------------------------------------------------------------
    grm_money_press — init (находка 178)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

GRM = GRM or {}
GRM.MoneyPress = GRM.MoneyPress or {} -- реестр станков: [entIndex] = ent

local function notify(ply, msg, r, g, b)
    if IsValid(ply) and GRM and GRM.Notify then
        GRM.Notify(ply, msg, r or 200, g or 200, b or 200)
    end
end

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
        print("[GRM Money Press] ВНИМАНИЕ: модель не найдена, фолбэк '" .. tostring(mdl) .. "'")
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    self:SetActive(true)
    self:SetBroken(false)
    self:SetSpeedLevel(0)
    self:SetHeat(0)
    self:SetPrintInterval(self.BaseInterval)
    self:SetPrintAmount(self.BaseAmount)
    self:SetTotalPrinted(0)
    self:SetBuffer(0)
    self.NextPrint = CurTime() + self:GetPrintInterval()
    self.NextCool = CurTime() + 1

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end

    GRM.MoneyPress[self:EntIndex()] = self
end

function ENT:OnRemove()
    GRM.MoneyPress[self:EntIndex()] = nil
end

-- Находка 178d: точка выдачи паллет (как у дилера v3).
-- Суперадмин ставит тулом grm_bank_tool (режим «Точка выдачи»).
function ENT:SetSpawnPoint(pos, ang)
    if not pos then return false end
    self:SetSpawnPos(pos)
    self:SetSpawnAngle(ang or Angle(0, self:GetAngles().y + 90, 0))
    self:SetHasCustomSpawn(true)
    return true
end

function ENT:ClearSpawnPoint()
    self:SetHasCustomSpawn(false)
    self:SetSpawnPos(self:GetPos() + self:GetForward() * 60 + Vector(0, 0, 12))
    return true
end

-- позиция спавна паллеты (точка выдачи или дефолт впереди станка)
function ENT:SpawnPos()
    if self:GetHasCustomSpawn() then
        local p = self:GetSpawnPos() or (self:GetPos() + Vector(0, 0, 12))
        -- опустить на пол (трейс вниз), чтобы паллета не парила в воздухе
        local ground = util.TraceLine({ start = p + Vector(0, 0, 180), endpos = p - Vector(0, 0, 300), filter = { self } })
        if ground.Hit and not ground.StartSolid then
            return ground.HitPos + Vector(0, 0, 12)
        end
        return p
    end
    return self:GetPos() + self:GetForward() * 60 + Vector(0, 0, 12)
end

-- Находка 178d/178e: полное состояние станка переживает рестарт через
-- /permadd (PermData): точка выдачи, скорость, буфер, статистика, вкл/выкл.
GRM = GRM or {}
GRM.PermData = GRM.PermData or { Extract = {}, Apply = {} }
GRM.PermData.Extract = GRM.PermData.Extract or {}
GRM.PermData.Apply = GRM.PermData.Apply or {}
GRM.PermData.Extract["grm_money_press"] = function(ent)
    local rec = {
        speed = math.floor(ent:GetSpeedLevel() or 0),
        buffer = math.floor(ent:GetBuffer() or 0),
        printed = math.floor(ent:GetTotalPrinted() or 0),
        active = ent:GetActive() == true,
    }
    if ent:GetHasCustomSpawn() then
        local p = ent:GetSpawnPos()
        local a = ent:GetSpawnAngle()
        rec.spawn = {
            x = p and p.x or 0, y = p and p.y or 0, z = p and p.z or 0,
            p = a and a.p or 0, y = a and a.y or 0, r = a and a.r or 0,
        }
    end
    return rec
end
GRM.PermData.Apply["grm_money_press"] = function(ent, data)
    if not istable(data) then return end
    if data.speed then ent:SetSpeedLevel(math.floor(tonumber(data.speed) or 0)) end
    if data.buffer then ent:SetBuffer(math.floor(tonumber(data.buffer) or 0)) end
    if data.printed then ent:SetTotalPrinted(math.floor(tonumber(data.printed) or 0)) end
    if data.active ~= nil then ent:SetActive(data.active == true) end
    -- скорость влияет на сумму за цикл
    ent:SetPrintAmount(ent:AmountPerCycle())
    if istable(data.spawn) then
        ent:SetSpawnPos(Vector(tonumber(data.spawn.x) or 0, tonumber(data.spawn.y) or 0, tonumber(data.spawn.z) or 0))
        ent:SetSpawnAngle(Angle(tonumber(data.spawn.p) or 0, tonumber(data.spawn.y) or 0, tonumber(data.spawn.r) or 0))
        ent:SetHasCustomSpawn(true)
    end
end

function ENT:CanManage(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    return GRM.Economy and GRM.Economy.CanManageEconomy and GRM.Economy.CanManageEconomy(ply) == true
end

function ENT:AmountPerCycle()
    local lvl = math.floor(self:GetSpeedLevel() or 0)
    return math.floor(self.BaseAmount * (1 + lvl * 0.5)) -- 5000, 7500, 10000, ...
end

function ENT:Think()
    local now = CurTime()

    -- охлаждение
    if self:GetHeat() > 0 and (self.NextCool or 0) <= now then
        self.NextCool = now + 1
        local rate = self:GetActive() and self.CoolPerSec or (self.CoolPerSec * 2)
        self:SetHeat(math.max(0, self:GetHeat() - rate))
    end

    -- перегрев: остановка
    if self:GetActive() and self:GetHeat() >= self.OverheatAt then
        self:SetActive(false)
        self:EmitSound("ambient/energy/spark6.wav", 70, 100)
        local owner = self:OwnerPlayer()
        if IsValid(owner) then notify(owner, "Печатный станок перегрелся! Охладите его через терминал.", 255, 120, 80) end
    end

    if not self:GetActive() or self:GetBroken() or self:GetHeat() >= self.OverheatAt then
        self:NextThink(now + 1)
        return true
    end

    if (self.NextPrint or 0) <= now then
        self.NextPrint = now + math.max(5, self:GetPrintInterval())
        self:PrintMoney()
    end

    self:NextThink(now + 1)
    return true
end

function ENT:PrintMoney()
    if not (GRM.Economy and GRM.Economy.StateBudgetAdd) then return end
    local amount = self:AmountPerCycle()
    GRM.Economy.StateBudgetAdd(amount, "Печать денег (банковский станок)")
    self:SetTotalPrinted(self:GetTotalPrinted() + amount)
    self:SetHeat(math.min(120, self:GetHeat() + self.HeatPerPrint))
    self:EmitSound("buttons/button17.wav", 58, math.random(95, 110))

    -- Находка 178b/178d: копим в БУФЕР; при достижении 100.000 спавним
    -- ПАЛЛЕТУ в точке выдачи станка (дефолт — впереди; суперадмин может
    -- поставить свою точку тулом). Игрок подносит её к хранилищу.
    local buffer = math.floor(self:GetBuffer() or 0) + amount
    self:SetBuffer(buffer)
    local palletMax = math.floor(tonumber(self.BasePalletMax) or 100000)
    if buffer >= palletMax and GRM.Economy.SpawnCashAt then
        local pos = self:SpawnPos()
        local n = math.floor(buffer / palletMax)
        local spawned = 0
        for _ = 1, n do
            spawned = spawned + GRM.Economy.SpawnCashAt(pos, palletMax, nil)
        end
        buffer = buffer - n * palletMax
        self:SetBuffer(buffer)
        if spawned > 0 then
            self:EmitSound("physics/wood/wood_crate_impact_hard1.wav", 65, 100)
        end
    end
    -- Находка 179d: автообновление перм-записи (буфер/статистика)
    if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(self) end
end

function ENT:OwnerPlayer()
    local sid = tostring(self:GetOwnerSID64() or "")
    if sid == "" then return nil end
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) then
            local key = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64() or ""
            if tostring(key) == sid then return p end
        end
    end
    return nil
end

function ENT:SetPressOwner(ply)
    if not IsValid(ply) then return end
    self:SetOwnerSID64((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64() or "")
end

-- ── Действия (через терминал) ─────────────────────────────
function ENT:PressToggle(ply)
    if not self:CanManage(ply) then notify(ply, "Нет доступа к банковскому станку.", 255, 100, 100) return false end
    if self:GetBroken() then notify(ply, "Станок неисправен.", 255, 120, 80) return false end
    if self:GetActive() then
        self:SetActive(false)
        notify(ply, "Печать остановлена.", 200, 220, 255)
    else
        if self:GetHeat() >= self.OverheatAt then
            notify(ply, "Станок перегрет — сначала охладите.", 255, 140, 80)
            return false
        end
        self:SetActive(true)
        self.NextPrint = CurTime() + self:GetPrintInterval()
        notify(ply, "Печать запущена: " .. (GRM.Format and GRM.Format(self:AmountPerCycle()) or tostring(self:AmountPerCycle())) .. " GRM за " .. self:GetPrintInterval() .. " сек.", 100, 220, 130)
    end
    return true
end

function ENT:PressUpgrade(ply)
    if not self:CanManage(ply) then notify(ply, "Нет доступа к банковскому станку.", 255, 100, 100) return false end
    local lvl = math.floor(self:GetSpeedLevel() or 0)
    if lvl >= self.MaxSpeedLevel then notify(ply, "Скорость уже максимальная (ур. " .. lvl .. ").", 255, 190, 90) return false end
    local cost = self.UpgradeBaseCost * (lvl + 1)
    if GRM.HasMoney and not GRM.HasMoney(ply, cost) then notify(ply, "Нужно: " .. (GRM.Format and GRM.Format(cost) or tostring(cost)), 255, 120, 80) return false end
    if GRM.TakeMoney then GRM.TakeMoney(ply, cost, "Прокачка печатного станка") end
    self:SetSpeedLevel(lvl + 1)
    self:SetPrintAmount(self:AmountPerCycle())
    -- Находка 179d: автообновление перм-записи (скорость)
    if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(self) end
    self:EmitSound("buttons/button14.wav", 65, 115)
    notify(ply, "Скорость станка: ур. " .. (lvl + 1) .. " — " .. (GRM.Format and GRM.Format(self:AmountPerCycle()) or tostring(self:AmountPerCycle())) .. " GRM / " .. self:GetPrintInterval() .. " сек.", 100, 220, 130)
    return true
end

function ENT:PressCool(ply)
    if not self:CanManage(ply) then notify(ply, "Нет доступа к банковскому станку.", 255, 100, 100) return false end
    if self:GetHeat() <= 0 then notify(ply, "Станок не нагрет.", 180, 220, 255) return false end
    if GRM.HasMoney and not GRM.HasMoney(ply, self.CoolCost) then notify(ply, "Нужно: " .. (GRM.Format and GRM.Format(self.CoolCost) or tostring(self.CoolCost)), 255, 120, 80) return false end
    if GRM.TakeMoney then GRM.TakeMoney(ply, self.CoolCost, "Охлаждение печатного станка") end
    self:SetHeat(0)
    self:EmitSound("ambient/energy/spark6.wav", 60, 140)
    notify(ply, "Станок охлаждён.", 100, 220, 255)
    return true
end

function ENT:Use(ply)
    if not IsValid(ply) then return end
    if self:CanManage(ply) then
        if GRM.Notify then
            GRM.Notify(ply, "Управляйте станком через терминал (модель holo_wall_unit) рядом со станком.", 200, 220, 255)
        end
    elseif GRM.Notify then
        GRM.Notify(ply, "Печатный станок банка. Доступ: сотрудники с правом экономики.", 200, 200, 120)
    end
end

print("[GRM] Money Press entity loaded (находка 178)")
