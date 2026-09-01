-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[ GRM Faction Core v5.0: stable structure metadata, departments & subdepartments, role display names, personnel records and domain events. ]]
if SERVER then AddCSLuaFile()end
GRM=GRM or{};GRM.FactionCore=GRM.FactionCore or{};local C=GRM.FactionCore
C.Version="5.0.0";C.Revision=C.Revision or 0;C.MaxHistory=200;C.MaxNotes=50
local function charKey(value)if IsValid(value)and value.IsPlayer and value:IsPlayer()then return GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(value)or(value:SteamID64()..":char1")end;return tostring(value or"")end
local function actorName(actor)if IsValid(actor)then local n=actor:GetNWString("GRM_RPName","");return n~=""and n or actor:Nick()end;return tostring(actor or"Система")end
local function normalizePersonnel(rec,key,source)
 rec.Personnel=istable(rec.Personnel)and rec.Personnel or{};local p=rec.Personnel;local changed=false
 local function set(k,v)if p[k]==nil then p[k]=v;changed=true end end
 set("joinedAt",os.time());set("hiredBy","");set("source",source or"migration");set("status","active");set("probationUntil",0);set("lastUpdated",os.time());p.notes=istable(p.notes)and p.notes or{};p.history=istable(p.history)and p.history or{};p.characterKey=tostring(key or p.characterKey or"");return p,changed
end
local function pushHistory(rec,eventType,actor,text,details)
 local p=normalizePersonnel(rec,rec.Personnel and rec.Personnel.characterKey);local row={id="ph_"..os.time().."_"..math.random(1000,9999),type=tostring(eventType or"event"),time=os.time(),actorKey=charKey(actor),actorName=actorName(actor),text=string.sub(tostring(text or""),1,400),details=istable(details)and details or{}}
 p.history[#p.history+1]=row;while#p.history>C.MaxHistory do table.remove(p.history,1)end;p.lastUpdated=os.time();return row
end
local function faction(name)return istable(Factions)and Factions[tostring(name or"")]or nil end
function C.Touch(factionName,eventType,payload)
 local f=faction(factionName);if not f then return end;C.Revision=C.Revision+1;f.CoreRevision=(tonumber(f.CoreRevision)or 0)+1;hook.Run("GRM_FactionCoreChanged",factionName,eventType,payload or{},f.CoreRevision,C.Revision)
end
function C.EnsureFaction(factionName,f)
 f=istable(f)and f or faction(factionName);if not f then return false end;local changed=false
 f.DepartmentDisplayNames=istable(f.DepartmentDisplayNames)and f.DepartmentDisplayNames or{}
 for _,key in ipairs(f.Departments or{})do if tostring(f.DepartmentDisplayNames[key]or"")==""then f.DepartmentDisplayNames[key]=key;changed=true end end
 f.RoleDisplayNames=istable(f.RoleDisplayNames)and f.RoleDisplayNames or{}
 for _,key in ipairs(f.Roles or{})do if tostring(f.RoleDisplayNames[key]or"")==""then f.RoleDisplayNames[key]=key;changed=true end end
 f.Subdepartments=istable(f.Subdepartments)and f.Subdepartments or{}
 f.SubdepartmentDisplayNames=istable(f.SubdepartmentDisplayNames)and f.SubdepartmentDisplayNames or{}
 for subKey,sub in pairs(f.Subdepartments)do if istable(sub)then local pub=tostring(sub.name or f.SubdepartmentDisplayNames[subKey] or subKey);if pub==""then pub=subKey end;sub.id=subKey;sub.name=pub;f.SubdepartmentDisplayNames[subKey]=pub end end
 f.PersonnelArchive=istable(f.PersonnelArchive)and f.PersonnelArchive or{}
 for key,rec in pairs(f.Members or{})do if istable(rec)then local _,c=normalizePersonnel(rec,key,"migration");changed=changed or c end end;return changed
end
function C.RoleDisplayName(factionName,roleKey)
 local f=faction(factionName);if not f then return tostring(roleKey or"Участник")end
 if GRM.Factions and GRM.Factions.RoleDisplayName then return GRM.Factions.RoleDisplayName(f,roleKey)end
 local names=f.RoleDisplayNames;local key=tostring(roleKey or"")
 return (names and names[key] and names[key]~="") and names[key] or (key~="" and key or "Участник")
end
function C.ResolveRoleKey(factionName,roleInput)
 local f=faction(factionName);if not f then return tostring(roleInput or"")end
 if GRM.Factions and GRM.Factions.ResolveRoleKey then return GRM.Factions.ResolveRoleKey(f,roleInput)end
 local input=tostring(roleInput or"");if f.RoleDisplayNames and f.RoleDisplayNames[input] then return input end
 if istable(f.RoleDisplayNames) then for k,v in pairs(f.RoleDisplayNames) do if tostring(v)==input then return k end end end
 return input
end
function C.SubdepartmentDisplayName(factionName,subKey)
 local f=faction(factionName);if not f then return tostring(subKey or"")end
 if GRM.Factions and GRM.Factions.SubdepartmentDisplayName then return GRM.Factions.SubdepartmentDisplayName(f,subKey)end
 local names=f.SubdepartmentDisplayNames;local key=tostring(subKey or"")
 return (names and names[key] and names[key]~="") and names[key] or key
end
function C.GetPersonnel(factionName,key,includeArchive)local f=faction(factionName);if not f then return nil end;local rec=f.Members and f.Members[key];if rec then normalizePersonnel(rec,key);return rec.Personnel,rec,false end;if includeArchive then local archived=f.PersonnelArchive and f.PersonnelArchive[key];if archived then return archived.Personnel,archived,true end end end
function C.ListPersonnel(factionName,includeArchive)local f=faction(factionName);local out={};if not f then return out end;for key,rec in pairs(f.Members or{})do if istable(rec)then normalizePersonnel(rec,key);out[#out+1]={key=key,role=rec.Role,department=rec.Department,subdepartment=rec.Subdepartment or rec.Subdept or"",personnel=rec.Personnel,archived=false}end end;if includeArchive then for key,rec in pairs(f.PersonnelArchive or{})do out[#out+1]={key=key,role=rec.Role,department=rec.Department,subdepartment=rec.Subdepartment or rec.Subdept or"",personnel=rec.Personnel,archived=true}end end;return out end
function C.AddRecord(factionName,key,eventType,actor,text,details)local f=faction(factionName);if not f then return false,"Фракция не найдена"end;local rec=f.Members and f.Members[key];if not rec then return false,"Сотрудник не найден"end;local row=pushHistory(rec,eventType,actor,text,details);C.Touch(factionName,"personnel.record",{characterKey=key,row=row});if FactionsAPI and FactionsAPI.Save then FactionsAPI.Save()end;return true,row end
function C.SetProbation(factionName,key,untilAt,actor)local f=faction(factionName);local rec=f and f.Members and f.Members[key];if not rec then return false,"Сотрудник не найден"end;local p=normalizePersonnel(rec,key);p.probationUntil=math.max(0,tonumber(untilAt)or 0);p.status=p.probationUntil>os.time()and"probation"or"active";pushHistory(rec,"probation",actor,p.status=="probation"and"Назначен испытательный срок"or"Испытательный срок завершён",{untilAt=p.probationUntil});C.Touch(factionName,"personnel.probation",{characterKey=key,untilAt=p.probationUntil});if FactionsAPI and FactionsAPI.Save then FactionsAPI.Save()end;return true end
if SERVER then
 hook.Add("GRM_FactionMemberJoined","GRM_FactionCore_PersonnelJoin",function(factionName,key,rec,actor,source)local p=normalizePersonnel(rec,key,source);p.joinedAt=os.time();p.hiredBy=charKey(actor);p.status="active";pushHistory(rec,"joined",actor,"Принят во фракцию",{source=source});C.Touch(factionName,"member.joined",{characterKey=key})end)
 hook.Add("GRM_FactionMemberRemoved","GRM_FactionCore_PersonnelRemoved",function(factionName,key,rec,actor,reason)local f=faction(factionName);if not(f and istable(rec))then return end;local p=normalizePersonnel(rec,key);p.status="dismissed";p.leftAt=os.time();pushHistory(rec,"dismissed",actor,"Уволен из фракции",{reason=reason});f.PersonnelArchive=f.PersonnelArchive or{};f.PersonnelArchive[key]=table.Copy(rec);C.Touch(factionName,"member.removed",{characterKey=key,reason=reason})end)
 hook.Add("GRM_FactionMemberRoleChanged","GRM_FactionCore_PersonnelRole",function(factionName,key,rec,oldRole,newRole,actor)pushHistory(rec,"role_changed",actor,"Изменена должность",{from=oldRole,to=newRole});C.Touch(factionName,"member.role",{characterKey=key,from=oldRole,to=newRole})end)
 --[[ Назначение на должность и снятие — событие кадрового дела наравне с
      переводом в отдел. Раньше в истории было видно только смену звания, и
      «за что человека сняли с начальника» нигде не хранилось. ]]
 hook.Add("GRM_FactionMemberPositionChanged","GRM_FactionCore_PersonnelPosition",function(factionName,key,rec,oldPos,newPos,actor)
  local f=faction(factionName);local function nameOf(id)
   if not id or id=="" then return "" end
   local pos=GRM.Positions and GRM.Positions.Get and GRM.Positions.Get(f or factionName,id)
   return pos and pos.name or tostring(id)
  end
  local text
  if (newPos or "")=="" then text="Снят с должности «"..nameOf(oldPos).."»"
  elseif (oldPos or "")=="" then text="Назначен на должность «"..nameOf(newPos).."»"
  else text="Переведён с должности «"..nameOf(oldPos).."» на «"..nameOf(newPos).."»" end
  pushHistory(rec,"position_changed",actor,text,{from=oldPos or "",to=newPos or ""})
  C.Touch(factionName,"member.position",{characterKey=key,from=oldPos or "",to=newPos or ""})
 end)
 hook.Add("GRM_FactionMemberDepartmentChanged","GRM_FactionCore_PersonnelDepartment",function(factionName,key,rec,oldDept,newDept,actor)pushHistory(rec,"department_changed",actor,"Переведён в другой отдел",{from=oldDept,to=newDept});C.Touch(factionName,"member.department",{characterKey=key,from=oldDept,to=newDept})end)
 hook.Add("GRM_FactionMemberSubdepartmentChanged","GRM_FactionCore_PersonnelSubdepartment",function(factionName,key,rec,oldSub,newSub,actor)local subDisp=C.SubdepartmentDisplayName(factionName,newSub);local txt=newSub~=""and("Назначен в подотдел «"..subDisp.."»")or"Выведен из подотдела";pushHistory(rec,"subdepartment_changed",actor,txt,{from=oldSub,to=newSub});C.Touch(factionName,"member.subdepartment",{characterKey=key,from=oldSub,to=newSub})end)
 hook.Add("GRM_FactionDutyChanged","GRM_FactionCore_PersonnelDuty",function(ply,onDuty,factionName)local key=charKey(ply);local f=faction(factionName);local rec=f and f.Members and f.Members[key];if not rec then return end;pushHistory(rec,onDuty and"duty_started"or"duty_ended",ply,onDuty and"Вышел на службу"or"Завершил службу",{});C.Touch(factionName,"member.duty",{characterKey=key,onDuty=onDuty});if FactionsAPI and FactionsAPI.Save then FactionsAPI.Save()end end)
 local function migrate()local changed=false;for name,f in pairs(Factions or{})do changed=C.EnsureFaction(name,f)or changed end;if changed and FactionsAPI and FactionsAPI.Save then FactionsAPI.Save()end end;timer.Simple(1,migrate);grmBootStart("GRM_FactionCore_Migrate","early",function()timer.Simple(1,migrate)end)
 timer.Simple(1,function()if not FactionsAPI then return end;FactionsAPI.GetPersonnel=C.GetPersonnel;FactionsAPI.ListPersonnel=C.ListPersonnel;FactionsAPI.AddPersonnelRecord=C.AddRecord;FactionsAPI.SetProbation=C.SetProbation;FactionsAPI.GetRoleDisplayName=C.RoleDisplayName;FactionsAPI.ResolveRoleKey=C.ResolveRoleKey;FactionsAPI.GetSubdepartmentDisplayName=C.SubdepartmentDisplayName end)
end
print("[GRM Faction Core] v"..C.Version.." loaded")
