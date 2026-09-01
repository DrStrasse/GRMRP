TOOL.Category="GRM";TOOL.Name="#tool.grm_jobs.name";TOOL.Command=nil;TOOL.ConfigName="";TOOL.ClientConVar={point_type="courier",point_name=""}
if CLIENT then language.Add("tool.grm_jobs.name","GRM Точки работ");language.Add("tool.grm_jobs.desc","Отдельная установка точек маршрутов и физических мусорок");language.Add("tool.grm_jobs.0","ЛКМ: поставить выбранный объект • ПКМ: настройки • R: удалить объект под прицелом/ближайшую точку")end
local function spawnGarbageBin(ply,tr,name)
 local e=ents.Create("grm_garbage_bin");if not IsValid(e)then return false end
 e:SetPos(tr.HitPos+tr.HitNormal*4);e:SetAngles(Angle(0,ply:EyeAngles().y,0));e:SetBinName(string.Trim(tostring(name or""))~=""and string.sub(string.Trim(tostring(name)),1,64)or"Мусорный контейнер");e:Spawn();e:Activate()
 if GRM.Notify then GRM.Notify(ply,"Мусорка установлена. Сохраните её через /grm_persistence.",90,225,145)end;return true
end
function TOOL:LeftClick(tr)
 if CLIENT then return true end;local ply=self:GetOwner();if not(IsValid(ply)and ply:IsSuperAdmin()and tr and tr.Hit and GRM.Jobs)then return false end
 local typ=self:GetClientInfo("point_type");local name=self:GetClientInfo("point_name")
 if typ=="garbage_bin"then return spawnGarbageBin(ply,tr,name)end
 if not GRM.Jobs.AddWorkPoint then return false end;local ok,rec=GRM.Jobs.AddWorkPoint(typ,name,tr.HitPos);if not ok then return false end
 if GRM.Notify then GRM.Notify(ply,"Точка работы добавлена: "..tostring(rec.name),90,225,145)end;return true
end
function TOOL:RightClick()if CLIENT then return true end;local ply=self:GetOwner();if IsValid(ply)and ply:IsSuperAdmin()and GRM.Jobs and GRM.Jobs.OpenAdmin then GRM.Jobs.OpenAdmin(ply)return true end return false end
function TOOL:Reload(tr)
 if CLIENT then return true end;local ply=self:GetOwner();if not(IsValid(ply)and ply:IsSuperAdmin()and GRM.Jobs)then return false end
 local ent=tr and tr.Entity or nil;if IsValid(ent)and ent:GetClass()=="grm_garbage_bin"then local removed=false;if GRM.Perm and GRM.Perm.Remove then removed=GRM.Perm.Remove(ply,ent,true)==true end;if not removed and IsValid(ent)then ent:Remove()end;if GRM.Notify then GRM.Notify(ply,"Мусорка удалена.",230,175,80)end;return true end
 local pos=tr and tr.HitPos or ply:GetPos();local ok=GRM.Jobs.RemoveNearestWorkPoint(pos,180);if ok and GRM.Notify then GRM.Notify(ply,"Точка маршрута удалена. Мусорки не затронуты.",230,175,80)end;return ok==true
end
function TOOL.BuildCPanel(p)
 local combo=p:ComboBox("Что установить","grm_jobs_point_type");combo:AddChoice("Курьер — точка доставки","courier");combo:AddChoice("Мусоровоз — точка маршрута","garbage");combo:AddChoice("Мусоровоз — свалка","dump");combo:AddChoice("Физическая мусорка (отдельно)","garbage_bin");combo:AddChoice("Такси — стоянка/ориентир","taxi_pickup");combo:AddChoice("Такси — ориентир назначения","taxi_dropoff")
 p:TextEntry("Название","grm_jobs_point_name");p:Button("Открыть полную настройку","grm_jobs_admin");p:Help("ЛКМ ставит только выбранный объект. Физическая мусорка и точка маршрута мусоровоза устанавливаются отдельно. Мусорки сохраняются и загружаются в /grm_persistence.")
end
