--[[ Атлас/мини сняты: точки плыли. Файл-заглушка, чтобы lua не падал. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Nav = GRM.Nav or {}
local N = GRM.Nav
N.Version = "1.4.1"
N.Disabled = true

function N.OpenAtlas() end
function N.CloseAtlas() end
function N.SetWaypoint() end
function N.ClearWaypoint() end
function N.DeleteMark() end
function N.SendBounds() end

print("[GRM Nav] v" .. N.Version .. " disabled stub")
