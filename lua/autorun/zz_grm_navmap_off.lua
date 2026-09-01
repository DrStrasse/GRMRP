-- Если на сервере завалялся старый sh_grm_navmap.lua, этот файл
-- гасит его хуки после загрузки. Сам атлас в репо — заглушка.
if SERVER then AddCSLuaFile() end
if not CLIENT then return end
hook.Add("InitPostEntity", "GRM_Nav_ForceOff", function()
    hook.Remove("HUDPaint", "GRM_Nav_Mini")
    hook.Remove("HUDPaint", "GRM_Nav_AtlasHUD")
    hook.Remove("PlayerButtonDown", "GRM_Nav_Key")
    hook.Remove("Think", "GRM_Nav_SchemeScan")
    hook.Remove("Think", "GRM_Nav_AtlasDrag")
    hook.Remove("Think", "GRM_Nav_Arrive")
    hook.Remove("PostRender", "GRM_Nav_Peek")
    hook.Remove("SetupWorldFog", "GRM_Nav_NoFog")
    hook.Remove("SetupSkyboxFog", "GRM_Nav_NoFogSky")
    hook.Remove("PlayerBindPress", "GRM_Nav_AtlasWheel")
    hook.Remove("PlayerSayTransform", "GRM_Nav_Chat")
end)
