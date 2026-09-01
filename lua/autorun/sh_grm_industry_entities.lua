--[[--------------------------------------------------------------------
    GRM Industry — сущности цеха и логистики.

    ОДИН КЛАСС НА РОЛЬ, ОДНА РЕАЛИЗАЦИЯ НА ВСЕХ. В старом цехе было
    десять сущностей с десятью копиями SetupDataTables, и правка
    «добавить поле» превращалась в десять правок. Здесь общий
    конструктор, роль задаётся параметром.

    Роль станка (components / gpu / weapon / furnace) НЕ класс, а
    свойство: админ ставит один станок и переключает его тип в меню,
    не переставляя сущность на карте.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Industry = GRM.Industry or {}
local I = GRM.Industry

if I.EntitiesRegistered then return end
I.EntitiesRegistered = true

--[[ Роли и ёмкости описаны в sh_grm_industry_core.lua: это данные,
     а не регистрация. Здесь только scripted_ents.Register. ]]

local function registerNode(class, printName, role, spawnable)
    local ENT = {}
    ENT.Type = "anim"
    ENT.Base = "base_gmodentity"
    ENT.PrintName = printName
    ENT.Category = "GRM Industry"
    ENT.Spawnable = spawnable == true
    ENT.AdminSpawnable = spawnable == true
    ENT.NodeRole = role

    function ENT:SetupDataTables()
        self:NetworkVar("String", 0, "NodeID")
        self:NetworkVar("String", 1, "NodeKind")
        self:NetworkVar("String", 2, "FactionName")
        self:NetworkVar("String", 3, "NodeLabel")
        self:NetworkVar("String", 4, "WorkerName")
        self:NetworkVar("String", 5, "JobStage")
        self:NetworkVar("Int", 0, "Stock")
        self:NetworkVar("Int", 1, "Wear")
        self:NetworkVar("Bool", 0, "Busy")
        self:NetworkVar("Float", 0, "Progress")
    end

    if SERVER then
        function ENT:Initialize()
            if GRM.Industry and GRM.Industry.InitNode then GRM.Industry.InitNode(self) end
        end

        function ENT:Use(ply)
            if GRM.Industry and GRM.Industry.UseNode then GRM.Industry.UseNode(ply, self) end
        end

        function ENT:OnRemove()
            if GRM.Industry and GRM.Industry.NodeRemoved then GRM.Industry.NodeRemoved(self) end
        end

        --[[ PERM-DATA (Код 50): настройки едут вместе с закреплением,
             как это уже сделано у терминалов и старой логистики. ]]
        function ENT:GetPermData()
            local d = {
                nodeID = self:GetNodeID(),
                kind = self:GetNodeKind(),
                faction = self:GetFactionName(),
                label = self:GetNodeLabel(),
                role = self.NodeRole,
            }
            if GRM.Industry and GRM.Industry.NodePermData then
                local extra = GRM.Industry.NodePermData(self)
                if istable(extra) then for k, v in pairs(extra) do d[k] = v end end
            end
            return d
        end

        function ENT:ApplyPermData(data)
            if not istable(data) then return end
            if data.nodeID then self:SetNodeID(data.nodeID) end
            if data.kind then self:SetNodeKind(data.kind) end
            if data.faction then self:SetFactionName(data.faction) end
            if data.label then self:SetNodeLabel(data.label) end
            if GRM.Industry and GRM.Industry.ApplyNodePermData then
                GRM.Industry.ApplyNodePermData(self, data)
            end
        end
    else
        function ENT:Draw()
            self:DrawModel()
        end
    end

    scripted_ents.Register(ENT, class)
    if GRM.Perm and GRM.Perm.RegisterClass then GRM.Perm.RegisterClass(class, true) end
end

registerNode("grm_ind_supply", "Источник сырья", "supply", true)
registerNode("grm_ind_station", "Производственный станок", "station", true)
registerNode("grm_ind_storage", "Склад цеха", "storage", true)
registerNode("grm_ind_market", "Точка сбыта", "market", true)
registerNode("grm_ind_depot", "Точка отправления", "depot", true)
registerNode("grm_ind_warehouse", "Склад фракции", "warehouse", true)
registerNode("grm_ind_armory", "Оружейный шкаф фракции", "armory", true)

print("[GRM Industry] сущности зарегистрированы")
