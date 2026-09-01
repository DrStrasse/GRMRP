AddCSLuaFile("entities/grm_bank_terminal/shared.lua")
AddCSLuaFile("entities/grm_bank_terminal/cl_init.lua")
include("entities/grm_bank_terminal/shared.lua")

function ENT:Initialize()
    local model = "models/starless/atm.mdl"
    if GRM and GRM.Economy and GRM.Economy.Config and GRM.Economy.Config.BankTerminalModel then
        model = GRM.Economy.Config.BankTerminalModel
    end
    self:SetModel(model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetTerminalName() == "" then self:SetTerminalName("Банк GRM") end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake(); phys:EnableMotion(false) end

    -- Восстановление баланса инкассации из персистентной базы
    timer.Simple(0.1, function()
        if IsValid(self) and GRM and GRM.Incass and isfunction(GRM.Incass.RestoreTerminalCash) then
            GRM.Incass.RestoreTerminalCash(self)
        end
    end)
end

function ENT:Use(ply)
    -- Новое меню банкомата (Код 127): счёт, задолженность, услуги, дипломы.
    -- Старое окно экономики остаётся запасным вариантом, если модуль не загружен.
    if GRM and GRM.ATM and GRM.ATM.Open then
        GRM.ATM.Open(ply, self)
    elseif GRM and GRM.Economy and GRM.Economy.OpenBankTerminal then
        GRM.Economy.OpenBankTerminal(ply, self)
    end
end

-- Делегаты перм-данных для сохранения через /permadd (Код 50)
function ENT:GetPermData()
    local eid = self:EntIndex()
    local cash = 0
    if GRM and GRM.Incass and GRM.Incass.TerminalCash then
        cash = math.floor(tonumber(GRM.Incass.TerminalCash[eid]) or 0)
    end
    return {
        name = self:GetTerminalName(),
        cash = cash,
    }
end

function ENT:ApplyPermData(data)
    if not istable(data) then return end
    if data.name then self:SetTerminalName(tostring(data.name)) end
    if data.cash and GRM and GRM.Incass and GRM.Incass.TerminalCash then
        local eid = self:EntIndex()
        local amt = math.max(0, math.floor(tonumber(data.cash) or 0))
        GRM.Incass.TerminalCash[eid] = amt
        if isfunction(self.SetNWInt) then
            self:SetNWInt("GRM_TerminalCash", amt)
        end
    end
end

GRM = GRM or {}
GRM.PermData = GRM.PermData or { Extract = {}, Apply = {} }
GRM.PermData.Extract = GRM.PermData.Extract or {}
GRM.PermData.Apply = GRM.PermData.Apply or {}
GRM.PermData.Extract["grm_bank_terminal"] = function(ent)
    if IsValid(ent) and ent.GetPermData then return ent:GetPermData() end
    return nil
end
GRM.PermData.Apply["grm_bank_terminal"] = function(ent, data)
    if IsValid(ent) and ent.ApplyPermData then ent:ApplyPermData(data) end
end
