--[[--------------------------------------------------------------------
    grm_bank_computer — init (Компьютер Управления Банком)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_BankComp_Open")
util.AddNetworkString("GRM_BankComp_Action")

local function isPly(p) return IsValid(p) and p:IsPlayer() end

local function notify(ply, msg, r, g, b)
    if IsValid(ply) and GRM and GRM.Notify then
        GRM.Notify(ply, msg, r or 200, g or 200, b or 200)
    end
end

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetComputerName() == "" then
        self:SetComputerName("Компьютер Управления (Банк)")
    end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
end

function ENT:CanManage(ply)
    if not isPly(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    if GRM and GRM.Economy and isfunction(GRM.Economy.CanManageEconomy) then
        return GRM.Economy.CanManageEconomy(ply) == true
    end
    -- Проверка прав через FactionPerms (Код 122)
    if GRM and GRM.FactionPerms and isfunction(GRM.FactionPerms.HasPermission) then
        if GRM.FactionPerms.HasPermission(ply, "state_budget_view") or GRM.FactionPerms.HasPermission(ply, "state_budget_add") then
            return true
        end
    end
    return false
end

-- «ближайший объект класса в радиусе» — общий поиск (было по копии на
-- хранилище и на печатный станок, §5.4 п.12)
local function nearestOf(self, cls, radius)
    radius = radius or 1200
    local best, bestD = nil, math.huge
    local pos = self:GetPos()
    for _, ent in ipairs(ents.FindByClass(cls)) do
        if IsValid(ent) then
            local d = ent:GetPos():DistToSqr(pos)
            if d < bestD and d <= (radius * radius) then
                best, bestD = ent, d
            end
        end
    end
    return best
end

function ENT:FindNearestVault(radius)
    return nearestOf(self, "grm_bank_vault", radius)
end

function ENT:FindNearestPress(radius)
    return nearestOf(self, "grm_money_press", radius)
end

function ENT:GetVaultsSummary()
    local totalHeld = 0
    local totalCap = 0
    local count = 0
    for _, ent in ipairs(ents.FindByClass("grm_bank_vault")) do
        if IsValid(ent) and isfunction(ent.GetHeldCash) then
            totalHeld = totalHeld + math.floor(ent:GetHeldCash() or 0)
            totalCap = totalCap + (isfunction(ent.GetCapacity) and math.floor(ent:GetCapacity() or 500000) or 500000)
            count = count + 1
        end
    end
    return totalHeld, totalCap, count
end

function ENT:SendMenu(ply)
    if not isPly(ply) then return end
    if not self:CanManage(ply) then
        notify(ply, "Доступ закрыт: требуется право управления экономикой (суперадмин или банк).", 255, 120, 100)
        return
    end

    local nearestVault = self:FindNearestVault(1200)
    local nearestPress = self:FindNearestPress(1200)
    local totalHeld, totalCap, vaultCount = self:GetVaultsSummary()
    local stateBud = (GRM.Economy and GRM.Economy.StateBudgetGet and GRM.Economy.StateBudgetGet()) or 0

    local factionsList = {}
    if Factions then
        for fName, f in pairs(Factions) do
            if istable(f) then
                local b = math.max(
                    math.floor(tonumber(GRM.FactionBudgetGet and GRM.FactionBudgetGet(fName)) or 0),
                    math.floor(tonumber(f.Budget) or 0)
                )
                local tax = (GRM.FactionTaxGet and GRM.FactionTaxGet(fName))
                    or (GRM.Economy and GRM.Economy.TaxRateGet and GRM.Economy.TaxRateGet(fName))
                    or 0.05
                factionsList[fName] = {
                    budget = b,
                    taxRate = tax,
                }
            end
        end
    end

    local pressData = { found = false }
    if IsValid(nearestPress) then
        pressData = {
            found = true,
            active = nearestPress:GetActive(),
            broken = nearestPress:GetBroken(),
            heat = nearestPress:GetHeat(),
            buffer = nearestPress:GetBuffer(),
            speedLevel = nearestPress:GetSpeedLevel(),
            printAmount = nearestPress:GetPrintAmount(),
            totalPrinted = nearestPress:GetTotalPrinted(),
        }
    end

    local payload = {
        stateBudget = stateBud,
        totalHeld = totalHeld,
        totalCap = totalCap,
        vaultCount = vaultCount,
        nearestVaultFound = IsValid(nearestVault),
        nearestVaultHeld = IsValid(nearestVault) and math.floor(nearestVault:GetHeldCash() or 0) or 0,
        nearestVaultCap = IsValid(nearestVault) and (isfunction(nearestVault.GetCapacity) and math.floor(nearestVault:GetCapacity() or 500000) or 500000) or 0,
        press = pressData,
        factions = factionsList,
        canManage = true,
    }

    net.Start("GRM_BankComp_Open")
        net.WriteEntity(self)
        net.WriteTable(payload)
    net.Send(ply)
end

function ENT:Use(ply)
    if not isPly(ply) then return end
    if (self._grmUseT or 0) > CurTime() then return end
    self._grmUseT = CurTime() + 0.4
    self:SendMenu(ply)
end

-- Обработчик действий управляющего банком
net.Receive("GRM_BankComp_Action", function(_, ply)
    if not isPly(ply) then return end
    local comp = net.ReadEntity()
    local action = net.ReadString()
    local target = net.ReadString()
    local amount = math.max(0, math.floor(net.ReadUInt(32) or 0))

    if not IsValid(comp) or comp:GetClass() ~= "grm_bank_computer" then return end
    if ply:GetPos():DistToSqr(comp:GetPos()) > (250 * 250) then return end
    if not comp:CanManage(ply) then return end

    local nearestVault = comp:FindNearestVault(1200)
    local nearestPress = comp:FindNearestPress(1200)
    local stateBudget = (GRM.Economy and GRM.Economy.StateBudgetGet and GRM.Economy.StateBudgetGet()) or 0

    -- 1. Зачислить из хранилища в госбюджет
    if action == "vault_to_state" then
        if not IsValid(nearestVault) then
            notify(ply, "Рядом нет хранилища (grm_bank_vault).", 255, 120, 100)
            return
        end
        local held = math.floor(nearestVault:GetHeldCash() or 0)
        if amount <= 0 or held < amount then
            notify(ply, "В хранилище недостаточно наличных (доступно: " .. (GRM.Format and GRM.Format(held) or held) .. ").", 255, 120, 100)
            return
        end
        nearestVault:SetHeldCash(held - amount)
        if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(nearestVault) end
        if GRM.Economy and GRM.Economy.StateBudgetAdd then
            GRM.Economy.StateBudgetAdd(amount, "Зачислено из хранилища: " .. ply:Nick())
        end
        comp:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 100)
        notify(ply, "Зачислено из хранилища в госбюджет: " .. (GRM.Format and GRM.Format(amount) or amount), 100, 220, 130)

    -- 2. Выделить из госбюджета в хранилище
    elseif action == "state_to_vault" then
        if not IsValid(nearestVault) then
            notify(ply, "Рядом нет хранилища (grm_bank_vault).", 255, 120, 100)
            return
        end
        if amount <= 0 or stateBudget < amount then
            notify(ply, "В госбюджете недостаточно средств (доступно: " .. (GRM.Format and GRM.Format(stateBudget) or stateBudget) .. ").", 255, 120, 100)
            return
        end
        local held = math.floor(nearestVault:GetHeldCash() or 0)
        local cap = isfunction(nearestVault.GetCapacity) and math.floor(nearestVault:GetCapacity() or 500000) or 500000
        if held + amount > cap then
            notify(ply, "Хранилище не может вместить такую сумму (свободно: " .. (GRM.Format and GRM.Format(cap - held) or (cap - held)) .. ").", 255, 120, 100)
            return
        end
        nearestVault:SetHeldCash(held + amount)
        if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(nearestVault) end
        if GRM.Economy and GRM.Economy.StateBudgetAdd then
            GRM.Economy.StateBudgetAdd(-amount, "Выделено в хранилище: " .. ply:Nick())
        end
        comp:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 100)
        notify(ply, "Выделено из госбюджета в хранилище: " .. (GRM.Format and GRM.Format(amount) or amount), 100, 220, 130)

    -- 3. Перевести из хранилища в бюджет фракции
    elseif action == "vault_to_faction" then
        if not IsValid(nearestVault) then
            notify(ply, "Рядом нет хранилища (grm_bank_vault).", 255, 120, 100)
            return
        end
        local held = math.floor(nearestVault:GetHeldCash() or 0)
        if amount <= 0 or held < amount then
            notify(ply, "В хранилище недостаточно наличных.", 255, 120, 100)
            return
        end
        if not target or target == "" or not Factions or not Factions[target] then
            notify(ply, "Не выбрана фракция.", 255, 120, 100)
            return
        end
        nearestVault:SetHeldCash(held - amount)
        if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(nearestVault) end
        if GRM.FactionBudgetAdd then
            GRM.FactionBudgetAdd(target, amount, "Выделено из хранилища банка: " .. ply:Nick())
        end
        comp:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 100)
        notify(ply, "Переведено из хранилища в бюджет фракции «" .. target .. "»: " .. (GRM.Format and GRM.Format(amount) or amount), 100, 220, 130)

    -- 4. Перевести из госбюджета в бюджет фракции (субсидия)
    elseif action == "state_to_faction" then
        if amount <= 0 or stateBudget < amount then
            notify(ply, "В госбюджете недостаточно средств.", 255, 120, 100)
            return
        end
        if not target or target == "" or not Factions or not Factions[target] then
            notify(ply, "Не выбрана фракция.", 255, 120, 100)
            return
        end
        if GRM.Economy and GRM.Economy.StateBudgetAdd then
            GRM.Economy.StateBudgetAdd(-amount, "Гос. субсидия фракции [" .. target .. "]: " .. ply:Nick())
        end
        if GRM.FactionBudgetAdd then
            GRM.FactionBudgetAdd(target, amount, "Гос. субсидия: " .. ply:Nick())
        end
        comp:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 100)
        notify(ply, "Гос. субсидия перечислена в бюджет фракции «" .. target .. "»: " .. (GRM.Format and GRM.Format(amount) or amount), 100, 220, 130)

    -- 5. Управление печатным станком: вкл/выкл
    elseif action == "press_toggle" then
        if not IsValid(nearestPress) then
            notify(ply, "Печатный станок (grm_money_press) не найден рядом.", 255, 120, 100)
            return
        end
        local cur = nearestPress:GetActive()
        nearestPress:SetActive(not cur)
        if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(nearestPress) end
        notify(ply, "Печатный станок: " .. (not cur and "ВКЛЮЧЕН" or "ВЫКЛЮЧЕН"), 100, 220, 130)

    -- 6. Управление печатным станком: охлаждение
    elseif action == "press_cool" then
        if not IsValid(nearestPress) then
            notify(ply, "Печатный станок не найден.", 255, 120, 100)
            return
        end
        nearestPress:SetHeat(0)
        nearestPress:SetBroken(false)
        if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(nearestPress) end
        nearestPress:EmitSound("ambient/machines/steam_release_2.wav", 65, 100)
        notify(ply, "Печатный станок охлаждён (нагрев сброшен).", 100, 220, 130)

    -- 7. Выдача паллеты из буфера станка
    elseif action == "press_flush_buffer" then
        if not IsValid(nearestPress) then
            notify(ply, "Печатный станок не найден.", 255, 120, 100)
            return
        end
        local buf = nearestPress:GetBuffer()
        if buf <= 0 then
            notify(ply, "В буфере станка нет напечатанных средств.", 255, 180, 80)
            return
        end
        if nearestPress.SpawnPallet then
            nearestPress:SpawnPallet()
            notify(ply, "Паллета выдана из станка.", 100, 220, 130)
        end
    end

    comp:SendMenu(ply)
end)

-- Делегаты для сохранения через /permadd (Код 50)
GRM = GRM or {}
GRM.PermData = GRM.PermData or { Extract = {}, Apply = {} }
GRM.PermData.Extract = GRM.PermData.Extract or {}
GRM.PermData.Apply = GRM.PermData.Apply or {}
GRM.PermData.Extract["grm_bank_computer"] = function(ent)
    if not IsValid(ent) then return nil end
    return {
        name = isfunction(ent.GetComputerName) and ent:GetComputerName() or "Компьютер Управления (Банк)",
    }
end
GRM.PermData.Apply["grm_bank_computer"] = function(ent, data)
    if not IsValid(ent) or not istable(data) then return end
    if data.name and isfunction(ent.SetComputerName) then
        ent:SetComputerName(tostring(data.name))
    end
end

print("[GRM Bank Computer] Entity loaded (models/props/cs_office/computer.mdl)")
