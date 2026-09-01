--[[--------------------------------------------------------------------
    grm_vault_cash — init (находка 178)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

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
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    if self:GetAmount() <= 0 then self:SetAmount(1) end
    self._picked = false
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        -- Находка 178f: паллета НЕПОДВИЖНА — иначе физика «выбрасывает»
        -- её из точки (стена/пересечение) и она улетает в сторону.
        phys:EnableMotion(false)
    end
end

function ENT:OnRemove()
    -- вернуть место в хранилище (если паллета ещё не подобрана и не
    -- удалена как «исчезнувшая» вручную)
    if not self._picked and IsValid(self.Vault) and self.Vault.GetHeldCash and self.Vault.SetHeldCash then
        local held = math.max(0, math.floor(self.Vault:GetHeldCash() or 0) - math.floor(self:GetAmount() or 0))
        self.Vault:SetHeldCash(held)
        if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(self.Vault) end
    end
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if (self._grmUseT or 0) > CurTime() then return end
    self._grmUseT = CurTime() + 0.4
    local amt = math.max(0, math.floor(self:GetAmount() or 0))
    if amt <= 0 then self:Remove() return end

    -- Находка 178f: сумка ограбления — деньги собираются ПОЭТАПНО
    -- (порциями perUse за подход, максимум maxMoney в сумке).
    if GRM.Customization and GRM.Customization.HasFunction and GRM.Customization.HasFunction(ply, "loot_bag") then
        local taken = GRM.Customization.LootBagAdd and GRM.Customization.LootBagAdd(ply, amt) or 0
        if taken > 0 then
            local left = amt - taken
            if left > 0 then
                self:SetAmount(left)
            else
                self._picked = true
                if IsValid(self.Vault) and self.Vault.GetHeldCash and self.Vault.SetHeldCash then
                    local held = math.max(0, math.floor(self.Vault:GetHeldCash() or 0) - amt)
                    self.Vault:SetHeldCash(held)
                    if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(self.Vault) end
                end
                self:Remove()
            end
            if GRM.Notify then
                local cur = GRM.Customization.LootBagGet and GRM.Customization.LootBagGet(ply) or 0
                local maxM = GRM.Customization.LootBagMax and GRM.Customization.LootBagMax(ply) or 100000
                GRM.Notify(ply, "В сумку ограбления: " .. (GRM.Format and GRM.Format(taken) or tostring(taken)) .. "  (в сумке: " .. (GRM.Format and GRM.Format(cur) or tostring(cur)) .. " / " .. (GRM.Format and GRM.Format(maxM) or tostring(maxM)) .. ")", 255, 210, 100)
            end
            return
        end
        -- сумка полна — не подбираем в кошелёк напрямую? Нет: подбираем
        -- как обычно (полная сумка не блокирует обычный подбор).
    end

    if not (GRM and GRM.GiveMoney) then return end
    GRM.GiveMoney(ply, amt, "Подобраны деньги из банковского хранилища")
    self._picked = true
    if IsValid(self.Vault) and self.Vault.GetHeldCash and self.Vault.SetHeldCash then
        local held = math.max(0, math.floor(self.Vault:GetHeldCash() or 0) - amt)
        self.Vault:SetHeldCash(held)
        if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(self.Vault) end
    end
    if GRM.Notify then
        GRM.Notify(ply, "Подобрано из хранилища: " .. (GRM.Format and GRM.Format(amt) or tostring(amt)), 100, 220, 100)
    end
    hook.Run("GRM_Money_Picked", ply, amt)
    self:Remove()
end

print("[GRM] Vault Cash entity loaded (находка 178)")
