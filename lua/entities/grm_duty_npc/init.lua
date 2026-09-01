AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local IDLE_NAMES={"idle_all_01","idle_all","pose_standing_02","idle_subtle","idle_angry"}
local function usableSequence(ent,name)
    local seq=ent:LookupSequence(name)
    if not seq or seq<0 then return nil end
    local duration=ent:SequenceDuration(seq)
    if not duration or duration<=0 then return nil end
    return seq
end
function ENT:RefreshIdle(force)
    local model=string.lower(tostring(self:GetModel()or""));local current=string.lower(tostring(self:GetSequenceName(self:GetSequence())or""))
    if not force and self._grmIdleModel==model and current~=""and current~="reference"and current~="ragdoll"then return true end
    local seq
    for _,name in ipairs(IDLE_NAMES)do seq=usableSequence(self,name);if seq then break end end
    if not seq then local candidate=self:SelectWeightedSequence(ACT_IDLE);if candidate and candidate>=0 and self:SequenceDuration(candidate)>0 and string.lower(tostring(self:GetSequenceName(candidate)or""))~="reference"then seq=candidate end end
    if not seq then return false end
    self:ResetSequence(seq);self:ResetSequenceInfo();self:SetCycle(0);self:SetPlaybackRate(1);self._grmIdleModel=model;self._grmIdleSequence=seq
    return true
end
ENT.DefaultModel = "models/Humans/Group01/Male_07.mdl"

--[[ Применение конфигурации станции (фракция, надпись, модель).
     Заказ владельца 18.08: раньше модель и фракция жили ТОЛЬКО в NW-строках,
     которые при спавне ещё пусты — Initialize ставил дефолтного гражданина, а
     если перм-записи не было, настройки терялись совсем. Теперь конфиг
     хранится и в полях энтити, и в отдельном файле станций. ]]
function ENT:ApplyStationConfig(cfg)
    if not istable(cfg) then return false end

    local faction = tostring(cfg.faction or "")
    if faction ~= "" then
        self.GRMDutyFaction = faction
        self:SetNWString("GRM_DutyFaction", faction)
    end

    local id = tostring(cfg.id or "")
    if id ~= "" then
        self.GRMDutyID = id
        self:SetNWString("GRM_DutyID", id)
    end

    local title = tostring(cfg.title or "")
    if title ~= "" then
        self.GRMDutyTitle = title
        self:SetNWString("GRM_DutyTitle", title)
    end

    local mdl = tostring(cfg.model or "")
    if mdl ~= "" and util.IsValidModel(mdl) then
        self.GRMDutyModel = mdl
        self:SetNWString("GRM_DutyModel", mdl)
        if string.lower(tostring(self:GetModel() or "")) ~= string.lower(mdl) then
            self:SetModel(mdl)
            self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 72))
            self:RefreshIdle(true)
        end
    end
    return true
end

function ENT:StationConfig()
    return {
        id = tostring(self.GRMDutyID or self:GetNWString("GRM_DutyID", "")),
        faction = tostring(self.GRMDutyFaction or self:GetNWString("GRM_DutyFaction", "")),
        title = tostring(self.GRMDutyTitle or self:GetNWString("GRM_DutyTitle", "ПУНКТ ВЫХОДА НА СЛУЖБУ")),
        model = tostring(self.GRMDutyModel or self:GetNWString("GRM_DutyModel", self:GetModel() or "")),
    }
end

function ENT:Initialize()
    -- Модель: сначала уже назначенная полем (перм/файл станций применили её
    -- до спавна), затем NW, и только потом дефолт.
    local mdl = tostring(self.GRMDutyModel or "")
    if mdl == "" or not util.IsValidModel(mdl) then mdl = self:GetNWString("GRM_DutyModel", "") end
    if mdl == "" or not util.IsValidModel(mdl) then mdl = self.DefaultModel end

    self:SetModel(mdl)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 72))
    self:SetUseType(SIMPLE_USE)
    self:DrawShadow(false)
    self:DropToFloor()
    self:RefreshIdle(true)

    -- Конфиг мог быть загружен раньше энтити: применяем его следующим тиком.
    timer.Simple(0, function()
        if not IsValid(self) then return end
        if GRM and GRM.FactionDuty and GRM.FactionDuty.RestoreStation then
            GRM.FactionDuty.RestoreStation(self)
        end
    end)
end
function ENT:OnRestore()timer.Simple(0,function()if IsValid(self)then self:RefreshIdle(true)end end)end
function ENT:Use(activator)
    if not IsValid(activator)or not activator:IsPlayer()then return end;if(self._grmUseAt or 0)>CurTime()then return end;self._grmUseAt=CurTime()+.7
    if GRM and GRM.FactionDuty and GRM.FactionDuty.Open then GRM.FactionDuty.Open(activator,self)end
end
function ENT:OnTakeDamage(dmg)if dmg and dmg.SetDamage then dmg:SetDamage(0)end;return 0 end
