-- GRM Vehicle Dealer v3 compatibility bridge
if SERVER then AddCSLuaFile() end
if SERVER then
 hook.Add("PlayerSpawnVehicle","GRM_BlockUnauthorizedSpawn",function(ply,model,name)
  if not IsValid(ply)or ply:IsSuperAdmin()then return end
  if GRM_HasVehicleAccess and not GRM_HasVehicleAccess(ply,name)then return false end
 end)
 hook.Add("GRM_VendorPurchased","GRM_VD_IgnoreVendorHook",function()end)
 hook.Add("GRM_VehicleDealerSpawned","GRM_VD_Log",function(ent,ply,class)
  if IsValid(ent)and IsValid(ply)then file.Append("vd_spawn_log.txt",("[%s] %s (%s) получил %s\n"):format(os.date("%Y-%m-%d %H:%M:%S"),ply:Nick(),ply:SteamID(),class))end
 end)
 print("[GRM VehicleDealer] v3 compatibility bridge loaded")
end
