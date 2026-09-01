--[[--------------------------------------------------------------------
    GRM Board — доска объявлений/набора во фракции (Код 76)
    Модель: пробковая доска corkboardverticle01 (уточнил владелец).
    Лидеры фракций с доступом (суперадмин настраивает E→⚙ или через
    /factions → «Доступы») открывают набор; вступившие через доску попадают во фракцию автоматически,
    лидеру приходят сведения (ник, RP-имя, SteamID, время).
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Доска объявлений GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model         = "models/props_interiors/corkboardverticle01.mdl"
ENT.ModelFallback = "models/props_interiors/Furniture_shelf01a.mdl"

function ENT:SetupDataTables() end
