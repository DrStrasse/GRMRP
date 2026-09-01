AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function A() return GRM and GRM.FireAddon end

local function ghostBox(self)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:DrawShadow(false)
    self:SetNotSolid(true)
end

function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

function ENT:Initialize()
    local FA = A()
    local typ = self:GetNodeType() or 0
    local lay = FA and FA.NODE_LAY or 1
    local src = FA and FA.NODE_SOURCE or 0
    local jun = FA and FA.NODE_JUNCTION or 2
    local noz = FA and FA.NODE_NOZZLE or 3

    if typ == lay or typ == src then
        -- якоря: модель в Draw не рисуем. Альфу 0 и NoDraw нельзя —
        -- движок тогда не зовёт DrawTranslucent и кабель пропадает.
        self:SetModel("models/props_junk/PopCan01a.mdl")
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
        self:DrawShadow(false)
        self:SetRenderMode(RENDERMODE_NORMAL)
        self:SetColor(Color(220, 40, 30, 255))
        self:SetRenderBounds(Vector(-96, -96, -16), Vector(96, 96, 32))
        return
    end

    local mdl
    if typ == jun then
        mdl = (FA and FA.SafeModel(FA.Models.junction)) or "models/props_lab/tpplugholder_single.mdl"
    elseif typ == noz then
        mdl = util.IsValidModel("models/weapons/w_firehose_grm.mdl") and "models/weapons/w_firehose_grm.mdl"
            or ((FA and FA.SafeModel(FA.Models.nozzle)) or "models/props_canal/mattpipe.mdl")
    else
        mdl = "models/props_junk/PopCan01a.mdl"
    end
    self:SetModel(mdl)
    ghostBox(self)
    self:SetUseType(SIMPLE_USE)
    if typ == jun then
        self:SetRenderMode(RENDERMODE_TRANSALPHA)
        self:SetColor(Color(220, 80, 50, 200))
    end
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local FA = A()
    if not FA then return end
    local hose = self:GetHose()
    local typ = self:GetNodeType()

    if typ == FA.NODE_NOZZLE and IsValid(hose) then
        if hook.Run("GRM_FireAddon_HoseNodeUse", ply, self) == false then return end
        hose:PickNozzle(ply)
        return
    end

    if typ == FA.NODE_JUNCTION then
        if hook.Run("GRM_FireAddon_HoseNodeUse", ply, self) == false then return end
        if IsValid(ply.GRM_FireHose) then
            ply.GRM_FireHose:DockTo(self, ply)
            return
        end
        local h, err = FA.TakeHose(ply, self)
        if not h and err and ply.ChatPrint then ply:ChatPrint("[Рукав] " .. err) end
        return
    end
end
