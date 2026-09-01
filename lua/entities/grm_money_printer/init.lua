AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_Printer_Open")
util.AddNetworkString("GRM_Printer_Action")
util.AddNetworkString("GRM_Printer_Broken")


local function clamp(v, lo, hi)
    v = tonumber(v) or lo or 0
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local DEFAULT = {
    model = "models/props_lab/reciever01b.mdl",
    maxMoney = 10000,
    printAmount = 250,
    printInterval = 20,
    maxHealth = 250,
    heatPerPrint = 9,
    coolPerSecond = 1,
    overheatAt = 100,
    warningHeat = 75,
    repairCost = 750,
    upgradeCapacityCost = 2500,
    upgradeRateCost = 3500,
    maxCapacity = 50000,
    minInterval = 5,
    maxPrintAmount = 2500,
}

local SND = {
    print = "buttons/button17.wav",
    collect = "garrysmod/save_load1.wav",
    repair = "buttons/button15.wav",
    upgrade = "buttons/button14.wav",
    toggle = "buttons/lightswitch2.wav",
    warn = "ambient/energy/spark" ,
    broken = "ambient/energy/spark6.wav",
}

local function emit(ent, snd, level, pitch)
    if IsValid(ent) and snd and snd ~= "" then ent:EmitSound(snd, level or 65, pitch or 100) end
end

local function money(n)
    n = math.floor(tonumber(n) or 0)
    return GRM and GRM.Format and GRM.Format(n) or (tostring(n) .. " GRM")
end

local function notify(ply, msg, r, g, b)
    if not IsValid(ply) then return end
    if GRM and GRM.Notify then GRM.Notify(ply, msg, r or 220, g or 220, b or 220)
    elseif ply.ChatPrint then ply:ChatPrint("[Принтер] " .. tostring(msg or "")) end
end

local function canPay(ply, amount)
    if amount <= 0 then return true end
    if GRM and GRM.HasMoney then return GRM.HasMoney(ply, amount) end
    if GRM and GRM.GetBalance then return (GRM.GetBalance(ply) or 0) >= amount end
    return true
end

local function takeMoney(ply, amount, reason)
    if amount <= 0 then return true end
    if GRM and GRM.TakeMoney then return GRM.TakeMoney(ply, amount, reason or "Денежный принтер") ~= false end
    return true
end

local function giveMoney(target, amount, reason)
    if amount <= 0 then return false end
    if GRM and GRM.GiveMoney then GRM.GiveMoney(target, amount, reason or "Денежный принтер") return true end
    return false
end

function ENT:SpawnFunction(ply, tr, class)
    if not tr.Hit then return end
    local ent = ents.Create(class or "grm_money_printer")
    if not IsValid(ent) then return end
    ent:SetPos(tr.HitPos + tr.HitNormal * 18)
    ent:SetAngles(Angle(0, IsValid(ply) and ply:EyeAngles().y or 0, 0))
    ent:Spawn()
    ent:Activate()
    if IsValid(ply) then ent:SetPrinterOwner(ply) end
    return ent
end

function ENT:Initialize()
    self:SetModel(DEFAULT.model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    self:SetPrinted(0)
    self:SetMaxMoney(DEFAULT.maxMoney)
    self:SetPrintAmount(DEFAULT.printAmount)
    self:SetPrintInterval(DEFAULT.printInterval)
    self:SetHeat(0)
    self:SetPrinterHealth(DEFAULT.maxHealth)
    self:SetActive(true)
    self:SetBroken(false)
    self.NextPrint = CurTime() + self:GetPrintInterval()
    self.NextCool = CurTime() + 1

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

function ENT:SetPrinterOwner(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    self:SetOwner(ply)
    self:SetCreator(ply)
    self:SetOwnerSID64((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64())
    self:SetOwnerName(ply:Nick())
end

function ENT:OwnerPlayer()
    local sid = self:GetOwnerSID64()
    if sid == "" then return nil end
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and (((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64()) == sid) then return p end
    end
    return nil
end

function ENT:IsOwner(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    local sid = self:GetOwnerSID64()
    return sid ~= "" and ((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()) == sid
end

function ENT:ClaimIfEmpty(ply)
    if self:GetOwnerSID64() == "" and IsValid(ply) then
        self:SetPrinterOwner(ply)
    end
end

function ENT:Think()
    local now = CurTime()

    if self:GetHeat() > 0 and (self.NextCool or 0) <= now then
        self.NextCool = now + 1
        local cool = self:GetActive() and DEFAULT.coolPerSecond or (DEFAULT.coolPerSecond * 2)
        self:SetHeat(math.max(0, self:GetHeat() - cool))
    end

    if self:GetBroken() or not self:GetActive() then
        self:NextThink(now + 1)
        return true
    end

    if (self.NextPrint or 0) <= now then
        self.NextPrint = now + math.max(DEFAULT.minInterval, self:GetPrintInterval())
        self:PrintMoney()
    end

    self:NextThink(now + 1)
    return true
end

function ENT:PrintMoney()
    if self:GetPrinted() >= self:GetMaxMoney() then return end

    local add = math.min(self:GetPrintAmount(), self:GetMaxMoney() - self:GetPrinted())
    self:SetPrinted(self:GetPrinted() + add)
    self:SetHeat(math.min(120, self:GetHeat() + DEFAULT.heatPerPrint))
    emit(self, SND.print, 58, math.random(95, 110))

    if self:GetHeat() >= DEFAULT.overheatAt then
        self:Break("перегрев")
    elseif self:GetHeat() >= DEFAULT.warningHeat and math.random() < 0.05 then
        emit(self, "ambient/energy/spark" .. math.random(1, 6) .. ".wav", 65, 100)
    end
end

function ENT:Break(reason)
    if self:GetBroken() then return end
    self:SetBroken(true)
    self:SetActive(false)
    self:SetPrinterHealth(0)
    emit(self, SND.broken, 75, 100)
    net.Start("GRM_Printer_Broken")
        net.WriteEntity(self)
        net.WriteString(tostring(reason or "поломка"))
    net.Broadcast()
end

function ENT:DestroyPrinter(attacker)
    if self.GRM_Destroying then return end
    self.GRM_Destroying = true
    self:SetBroken(true)
    self:SetActive(false)
    self:SetPrinterHealth(0)
    local pos = self:WorldSpaceCenter()
    local effect = EffectData(); effect:SetOrigin(pos); effect:SetScale(1.2); util.Effect("Explosion", effect, true, true)
    local blast = ents.Create("env_explosion")
    if IsValid(blast) then blast:SetPos(pos);blast:SetOwner(IsValid(attacker) and attacker or self);blast:SetKeyValue("iMagnitude","70");blast:SetKeyValue("iRadiusOverride","180");blast:Spawn();blast:Fire("Explode","",0) end
    emit(self, "ambient/explosions/explode_4.wav", 90, 100)
    hook.Run("GRM_MoneyPrinterDestroyed", self, attacker, self:GetPrinted())
    timer.Simple(0, function() if IsValid(self) then self:Remove() end end)
end

function ENT:OnTakeDamage(dmg)
    if self.GRM_Destroying then return end
    self:TakePhysicsDamage(dmg)
    local amount = math.max(0, dmg:GetDamage())
    if amount <= 0 then return end
    local health = math.max(0, self:GetPrinterHealth() - math.ceil(amount))
    self:SetPrinterHealth(health)
    if health <= 0 then self:DestroyPrinter(dmg:GetAttacker())
    elseif amount >= 15 and math.random() < 0.35 then emit(self, "ambient/energy/spark" .. math.random(1, 6) .. ".wav", 68, 100) end
end

function ENT:CollectMoney(ply)
    ply = IsValid(ply) and ply or self:OwnerPlayer()
    local amount = math.floor(self:GetPrinted())
    if amount <= 0 then
        if IsValid(ply) then notify(ply, "В принтере пока нет денег", 255, 190, 90) end
        return false
    end

    local recipient = self:OwnerPlayer() or self:GetOwnerSID64()
    if recipient == "" then recipient = ply end
    if not giveMoney(recipient, amount, "Денежный принтер") then
        if IsValid(ply) then notify(ply, "Модуль валюты не загружен", 255, 120, 120) end
        return false
    end
    self:SetPrinted(0)
    emit(self, SND.collect, 65, 105)
    if IsValid(ply) then notify(ply, "Снято с принтера: " .. money(amount), 100, 220, 100) end
    local owner = self:OwnerPlayer()
    if IsValid(owner) and owner ~= ply then notify(owner, "Принтер выплатил: " .. money(amount), 100, 220, 100) end
    return true
end

function ENT:Repair(ply)
    if not self:GetBroken() and self:GetPrinterHealth() >= DEFAULT.maxHealth then
        notify(ply, "Принтер не требует ремонта", 180, 220, 255)
        return
    end
    if not canPay(ply, DEFAULT.repairCost) then notify(ply, "Нужно на ремонт: " .. money(DEFAULT.repairCost), 255, 120, 120) return end
    takeMoney(ply, DEFAULT.repairCost, "Ремонт денежного принтера")
    self:SetBroken(false)
    self:SetActive(true)
    self:SetPrinterHealth(DEFAULT.maxHealth)
    self:SetHeat(0)
    emit(self, SND.repair, 65, 100)
    self.NextPrint = CurTime() + self:GetPrintInterval()
    notify(ply, "Принтер отремонтирован за " .. money(DEFAULT.repairCost), 100, 220, 100)
end

function ENT:UpgradeCapacity(ply)
    if self:GetMaxMoney() >= DEFAULT.maxCapacity then notify(ply, "Ёмкость уже максимальная", 255, 190, 90) return end
    if not canPay(ply, DEFAULT.upgradeCapacityCost) then notify(ply, "Нужно: " .. money(DEFAULT.upgradeCapacityCost), 255, 120, 120) return end
    takeMoney(ply, DEFAULT.upgradeCapacityCost, "Улучшение ёмкости принтера")
    self:SetMaxMoney(math.min(DEFAULT.maxCapacity, math.floor(self:GetMaxMoney() * 1.5)))
    emit(self, SND.upgrade, 65, 105)
    notify(ply, "Ёмкость принтера улучшена до " .. money(self:GetMaxMoney()), 100, 220, 100)
end

function ENT:UpgradeRate(ply)
    if self:GetPrintInterval() <= DEFAULT.minInterval and self:GetPrintAmount() >= DEFAULT.maxPrintAmount then notify(ply, "Скорость уже максимальная", 255, 190, 90) return end
    if not canPay(ply, DEFAULT.upgradeRateCost) then notify(ply, "Нужно: " .. money(DEFAULT.upgradeRateCost), 255, 120, 120) return end
    takeMoney(ply, DEFAULT.upgradeRateCost, "Улучшение скорости принтера")
    self:SetPrintInterval(math.max(DEFAULT.minInterval, math.floor(self:GetPrintInterval() * 0.85)))
    self:SetPrintAmount(math.min(DEFAULT.maxPrintAmount, math.floor(self:GetPrintAmount() * 1.25)))
    emit(self, SND.upgrade, 65, 115)
    notify(ply, "Скорость принтера улучшена", 100, 220, 100)
end

function ENT:SendMenu(ply)
    net.Start("GRM_Printer_Open")
        net.WriteEntity(self)
        net.WriteTable({
            printed = self:GetPrinted(), maxMoney = self:GetMaxMoney(), heat = self:GetHeat(),
            health = self:GetPrinterHealth(), maxHealth = DEFAULT.maxHealth, active = self:GetActive(), broken = self:GetBroken(),
            printAmount = self:GetPrintAmount(), printInterval = self:GetPrintInterval(),
            owner = self:GetOwnerName(), repairCost = DEFAULT.repairCost,
            upgradeCapacityCost = DEFAULT.upgradeCapacityCost, upgradeRateCost = DEFAULT.upgradeRateCost,
        })
    net.Send(ply)
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    self:ClaimIfEmpty(ply)
    if not self:IsOwner(ply) then notify(ply, "Это не ваш принтер", 255, 100, 100) return end
    self:SendMenu(ply)
end

--[[ ДЕЙСТВИЯ С ПРИНТЕРОМ — таблица вместо лестницы `elseif action ==`.
     Владелец и класс энтити проверены ВЫШЕ, до диспетчеризации: право
     проверяется один раз для всех действий, а не переписывается в каждой
     ветке (админский сброс — отдельная проверка внутри своего действия).
     Контракт: (ent, ply). ]]
local PRINTER_ACTIONS = {
    collect = function(ent, ply) ent:CollectMoney(ply) end,
    repair = function(ent, ply) ent:Repair(ply) end,
    cap = function(ent, ply) ent:UpgradeCapacity(ply) end,
    rate = function(ent, ply) ent:UpgradeRate(ply) end,

    toggle = function(ent, ply)
        ent:SetActive(not ent:GetActive())
        emit(ent, SND.toggle, 60, ent:GetActive() and 110 or 90)
        notify(ply, ent:GetActive() and "Принтер включён" or "Принтер выключен", 150, 220, 255)
    end,

    admin_reset = function(ent, ply)
        -- Сброс перегрева и поломки — только суперадмину: иначе владелец
        -- чинит принтер бесплатно и обходит всю экономику ремонта.
        if not ply:IsSuperAdmin() then return end
        ent:SetPrinted(0)
        ent:SetHeat(0)
        ent:SetBroken(false)
        ent:SetActive(true)
        ent:SetPrinterHealth(DEFAULT.maxHealth)
    end,
}

net.Receive("GRM_Printer_Action", function(_, ply)
    local ent = net.ReadEntity()
    local action = net.ReadString()
    if not IsValid(ent) or ent:GetClass() ~= "grm_money_printer" then return end
    ent:ClaimIfEmpty(ply)
    if not ent:IsOwner(ply) then notify(ply, "Это не ваш принтер", 255, 100, 100) return end

    local handler = PRINTER_ACTIONS[action]
    if handler then handler(ent, ply) end

    ent:SendMenu(ply)
end)

concommand.Add("grm_printer_config", function(ply, _, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    local ent = ply:GetEyeTrace().Entity
    if not IsValid(ent) or ent:GetClass() ~= "grm_money_printer" then ply:ChatPrint("[Принтер] Наведитесь на принтер") return end
    local key, value = tostring(args[1] or ""), tonumber(args[2])
    if key == "interval" and value then ent:SetPrintInterval(math.max(DEFAULT.minInterval, math.floor(value)))
    elseif key == "max" and value then ent:SetMaxMoney(clamp(math.floor(value), 1000, DEFAULT.maxCapacity))
    elseif key == "amount" and value then ent:SetPrintAmount(clamp(math.floor(value), 1, DEFAULT.maxPrintAmount))
    else ply:ChatPrint("[Принтер] grm_printer_config <interval|max|amount> <value>") return end
    ent:SendMenu(ply)
end)

hook.Add("PhysgunPickup", "GRM_MoneyPrinter_PhysgunPickup", function(ply, ent)
    if not IsValid(ent) or ent:GetClass() ~= "grm_money_printer" then return end
    if ent:IsOwner(ply) or (IsValid(ply) and ply:IsSuperAdmin()) then return true end
    return false
end)

hook.Add("PhysgunDrop", "GRM_MoneyPrinter_PhysgunDrop", function(ply, ent)
    if not IsValid(ent) or ent:GetClass() ~= "grm_money_printer" then return end
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end)

print("[GRM] Money Printer v2.1.0 entity loaded")
