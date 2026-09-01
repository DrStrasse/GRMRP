--[[--------------------------------------------------------------------
    grm_comp_fire — init.lua (Серверная часть пожарной станции)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_CompFire_Open")
util.AddNetworkString("GRM_CompFire_Calls")
util.AddNetworkString("GRM_CompFire_CallsData")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then mdl = self.ModelFallback end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    if self:GetComputerName() == "" then
        self:SetComputerName("ПОЖАРНАЯ СЛУЖБА • ДИСПЕТЧЕРСКАЯ")
    end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
end

-- Кто вправе пользоваться станцией: суперадмин, бойцы (FightPro), диспетчеры.
function ENT:CanManage(ply)
    if GRM.CompAccess and GRM.CompAccess.GetRaw(self) ~= "" then
        return GRM.CompAccess.Allowed(self, ply)
    end
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    if ply:IsSuperAdmin() then return true end
    local F = GRM.Fire
    if not F then return false end
    if isfunction(F.CanFightPro) and F.CanFightPro(ply) == true then return true end
    if isfunction(F.CanDispatch) and F.CanDispatch(ply) == true then return true end
    return false
end

local function snapshot(ent, ply)
    local F = GRM.Fire
    local fires = (F and isfunction(F.Snapshot) and F.Snapshot()) or {}
    local cfg = (F and F.Config) or {}
    return {
        isAdmin       = ply:IsSuperAdmin() == true,
        canControl    = (F and isfunction(F.CanFightPro) and F.CanFightPro(ply) == true),
        canDispatch   = (F and isfunction(F.CanDispatch) and F.CanDispatch(ply) == true),
        addonReady    = (F and isfunction(F.AddonReady) and F.AddonReady() == true),
        vfireReady    = (F and isfunction(F.VFireReady) and F.VFireReady() == true),
        activeFires   = #fires,
        randomEnabled = cfg.RandomEnabled == true,
        stoveEnabled  = cfg.StoveEnabled == true,
        maxIncidents  = tonumber(cfg.MaxIncidents) or 8,
        minSec        = tonumber(cfg.RandomMinSec) or 480,
        maxSec        = tonumber(cfg.RandomMaxSec) or 900,
        name          = IsValid(ent) and ent:GetComputerName() or "ПОЖАРНАЯ СЛУЖБА • ДИСПЕТЧЕРСКАЯ",
    }
end

function ENT:Use(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if ply:GetPos():DistToSqr(self:GetPos()) > 250 * 250 then return end
    if (self._grmFireUseAt or 0) > CurTime() then return end
    self._grmFireUseAt = CurTime() + 0.7
    if not self:CanManage(ply) then
        if GRM.Notify then
            GRM.Notify(ply, "Доступ к пожарной станции — только бойцам, диспетчерам пожарной службы и суперадминам.", 255, 120, 100)
        end
        return
    end

    net.Start("GRM_CompFire_Open")
        net.WriteEntity(self)
        net.WriteTable(snapshot(self, ply))
    net.Send(ply)
end

-- Заказ владельца 18.08: со станции убраны кнопки «закрепить/снять машину»
-- и «взять ствол / рукав» — это делается у самой машины (/firetruck,
-- /firetruck_off) и через рукавный ящик, а компьютер остаётся чисто
-- диспетчерским: журнал пожаров и журнал вызовов.

-- Журнал вызовов: экстренные вызовы 911 категории «Пожар».
net.Receive("GRM_CompFire_Calls", function(_, ply)
    if not IsValid(ply) then return end
    local ent = net.ReadEntity()
    if not IsValid(ent) or ent:GetClass() ~= "grm_comp_fire" then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > 250 * 250 then return end
    if not ent:CanManage(ply) then return end

    -- Основной источник — диспетчерские вызовы пожарной службы
    -- (sh_grm_fire_dispatch), плюс экстренные вызовы 911 категории «Пожар».
    local rows = {}
    local D = GRM.Fire and GRM.Fire.Dispatch
    if D and isfunction(D.LogRows) then
        for _, r in ipairs(D.LogRows(100)) do rows[#rows + 1] = r end
    end

    local EM = GRM.Emergency
    if EM and istable(EM.Calls) then
        for i = #EM.Calls, 1, -1 do
            local r = EM.Calls[i]
            if istable(r) and tostring(r.category or "") == "fire" then
                rows[#rows + 1] = {
                    id = tonumber(r.id) or 0,
                    text = tostring(r.text or ""),
                    caller = tostring(r.callerName or ""),
                    status = tostring(r.status or "open"),
                    assigned = tostring(r.assignedName or ""),
                    created = tonumber(r.created) or 0,
                    x = math.floor((r.pos and r.pos.x) or 0),
                    y = math.floor((r.pos and r.pos.y) or 0),
                    z = math.floor((r.pos and r.pos.z) or 0),
                }
                if #rows >= 150 then break end
            end
        end
    end

    table.sort(rows, function(a, b) return (tonumber(a.created) or 0) > (tonumber(b.created) or 0) end)
    while #rows > 100 do table.remove(rows) end

    net.Start("GRM_CompFire_CallsData")
        net.WriteTable(rows)
    net.Send(ply)
end)
