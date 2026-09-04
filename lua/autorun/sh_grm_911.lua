--[[--------------------------------------------------------------------
    GRM 911 v1.0.0 (Код 101)
    Тяжёлые ранения, экстренные вызовы, медицинская помощь, тела и
    первичная криминалистика. Дополняет, но не заменяет GRM.Medical.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Emergency = GRM.Emergency or {}
local EM = GRM.Emergency
EM.Version = "1.1.0"

local NET_CALL_FORM = "GRM_911_CallForm"
local NET_CALL_SEND = "GRM_911_CallSend"
local NET_CALLS = "GRM_911_Calls"
local NET_CALL_ACT = "GRM_911_CallAct"
local NET_PATIENT = "GRM_911_Patient"
local NET_TREAT = "GRM_911_Treat"
local NET_BODY = "GRM_911_Body"
local NET_ADMIN = "GRM_911_Admin"
local NET_ADMIN_SAVE = "GRM_911_AdminSave"
local NET_MARKER = "GRM_911_Marker"
local NET_BODY_ACT = "GRM_911_BodyAct"
local NET_CASES = "GRM_911_Cases"
local NET_LOOT = "GRM_911_Loot"

local function clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

if SERVER then
    for _, n in ipairs({NET_CALL_FORM,NET_CALL_SEND,NET_CALLS,NET_CALL_ACT,NET_PATIENT,NET_TREAT,NET_BODY,NET_ADMIN,NET_ADMIN_SAVE,NET_MARKER,NET_BODY_ACT,NET_CASES,NET_LOOT}) do util.AddNetworkString(n) end

    local DIR = "grm_911"
    local CFG_FILE = DIR .. "/config.json"
    local CALL_FILE = DIR .. "/incidents.json"
    local CASE_FILE = DIR .. "/cases.json"
    local function ensureDir() if not file.IsDir(DIR,"DATA") then file.CreateDir(DIR) end end
    local function jsonT(raw) local ok,t=pcall(util.JSONToTable,raw or "",false,true) return ok and istable(t) and t or nil end
    local function quarantine(path, raw) if raw and raw~="" then file.Write(path..".corrupt."..os.time()..".txt",raw) end end
    local function defaults()
        return {version=1,enabled=true,bleedoutSec=180,stabilizedSec=300,bodyTTL=1800,maxBodies=32,autoCall=true,lootInventory=true,reviveHealth=35,reviveSubsidy=300}
    end
    local function normCfg(t)
        local d=defaults(); t=istable(t) and t or {}
        d.enabled=t.enabled~=false; d.autoCall=t.autoCall~=false; d.lootInventory=t.lootInventory~=false
        d.bleedoutSec=math.floor(clamp(t.bleedoutSec,30,900)); d.stabilizedSec=math.floor(clamp(t.stabilizedSec,60,1800))
        d.bodyTTL=math.floor(clamp(t.bodyTTL,60,86400)); d.maxBodies=math.floor(clamp(t.maxBodies,1,128))
        d.reviveHealth=math.floor(clamp(t.reviveHealth,30,100)); d.reviveSubsidy=math.floor(clamp(t.reviveSubsidy,0,100000))
        return d
    end
    local function save(path,data,why)
        ensureDir(); local ok,raw=pcall(util.TableToJSON,data,true); if not ok or not raw then return false end
        file.Write(path,raw); if not jsonT(file.Read(path,"DATA") or "") then print("[GRM 911] SAVE FAIL "..path) return false end
        print("[GRM 911] SAVE ok: "..path.." ["..tostring(why or "-").."]"); return true
    end
    local function load()
        ensureDir()
        local raw=file.Read(CFG_FILE,"DATA") or ""; local t=jsonT(raw); if raw~="" and not t then quarantine(CFG_FILE,raw) end; EM.Config=normCfg(t)
        raw=file.Read(CALL_FILE,"DATA") or ""; t=jsonT(raw); if raw~="" and not t then quarantine(CALL_FILE,raw) end; EM.Calls=istable(t) and (t.calls or t) or {}
        raw=file.Read(CASE_FILE,"DATA") or ""; t=jsonT(raw); if raw~="" and not t then quarantine(CASE_FILE,raw) end; EM.Cases=istable(t) and (t.cases or t) or {}
        EM.NextCallID=1; for _,r in ipairs(EM.Calls) do EM.NextCallID=math.max(EM.NextCallID,(tonumber(r.id) or 0)+1) end
    end
    local function saveAll(why) save(CFG_FILE,EM.Config,why); save(CALL_FILE,{version=1,calls=EM.Calls},why); save(CASE_FILE,{version=1,cases=EM.Cases},why) end
    load()

    local function key(ply) return (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or (ply:SteamID64()..":char1") end
    local function rpName(ply) local n=ply:GetNWString("GRM_RPName",""); return n~="" and n or ply:Nick() end
    local function factionOf(ply)
        for name,f in pairs(Factions or {}) do if istable(f) and istable(f.Members) then local m=GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f,ply) or f.Members[ply:SteamID64()]; if m then return name end end end
        return nil
    end
    --[[ КТО МОЖЕТ РЕАНИМИРОВАТЬ (переписано 21.08 по жалобе владельца:
         «у игрока видна только кнопка стабилизировать, а как реанимировать?»).

         Реальная причина была здесь: проверка обрывалась на первом же
         источнике — `GRM.MedicalFull.IsMedic` возвращал false (там жёстко
         зашита фракция «Медики», которой на сервере нет), и дальше ни
         медицинский допуск фракции, ни аптечка в руках уже не смотрелись.
         Клиент по этому false просто НЕ РИСОВАЛ кнопку — игрок видел одну
         «Стабилизировать» и не понимал, чего ему не хватает.

         Теперь это цепочка ИЛИ, и она возвращает ещё и причину отказа —
         её видно прямо в окне помощи. ]]
    EM.ReviveItems = EM.ReviveItems or { "med_adrenaline", "med_defibrillator", "medkit", "med_bandage" }

    local function hasReviveItem(ply)
        if not (GRM.Inventory and GRM.Inventory.CountItem) then return false end
        for _, id in ipairs(EM.ReviveItems) do
            local ok, n = pcall(GRM.Inventory.CountItem, ply, id)
            if ok and (tonumber(n) or 0) > 0 then return true, id end
        end
        return false
    end
    EM.HasReviveItem = hasReviveItem

    local function isMedic(ply)
        if not IsValid(ply) then return false, "Игрок не найден" end
        if ply:IsSuperAdmin() then return true end

        if GRM.MedicalFull and GRM.MedicalFull.IsMedic then
            local ok = pcall(GRM.MedicalFull.IsMedic, ply)
            if ok and GRM.MedicalFull.IsMedic(ply) then return true end
        end
        if GRM.Medical and GRM.Medical.CanTreat and GRM.Medical.CanTreat(ply) then return true end

        -- Допуск госбазы уровня «Медицинский» или «Пожарная служба» — это и
        -- есть медслужба и спасатели, отдельного списка фракций не нужно.
        if GRM.PCBoard and GRM.PCBoard.PlayerLevel then
            local ok, level = pcall(GRM.PCBoard.PlayerLevel, ply)
            if ok and (level == "medical" or level == "fire") then return true end
        end

        -- С аптечкой/адреналином в сумке первую помощь оказывает кто угодно:
        -- иначе раненый в глуши обречён, даже если рядом есть человек с
        -- медикаментами.
        if hasReviveItem(ply) then return true end

        return false, "Нужен медик, аптечка или адреналин в инвентаре"
    end

    local function isInvestigator(ply)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        if GRM.SpecialService and GRM.SpecialService.IsAgent and GRM.SpecialService.IsAgent(ply) then return true end
        if GRM.Wanted and GRM.Wanted.CanView then local ok=GRM.Wanted.CanView(ply); if ok then return true end end
        return false
    end
    EM.IsMedic=isMedic; EM.IsInvestigator=isInvestigator

    local function publicCall(r)
        return {id=r.id,category=r.category,text=r.text,callerName=r.callerName,pos=r.pos,status=r.status,created=r.created,assignedName=r.assignedName or "",patientName=r.patientName or ""}
    end
    local function responders()
        local out={}; for _,p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do if isMedic(p) or isInvestigator(p) then out[#out+1]=p end end; return out
    end
    local function pushCalls(ply)
        if not (isMedic(ply) or isInvestigator(ply)) then return end
        local rows={}; for _,r in ipairs(EM.Calls) do if r.status~="closed" then rows[#rows+1]=publicCall(r) end end
        net.Start(NET_CALLS) net.WriteTable(rows) net.Send(ply)
    end
    local function notifyResponders(text)
        for _,p in ipairs(responders()) do if GRM.Notify then GRM.Notify(p,text,255,110,110) else p:ChatPrint("[911] "..text) end end
    end
    function EM.CreateCall(ply,category,text,pos,patient)
        pos=pos or (IsValid(ply) and ply:GetPos()) or vector_origin
        text=string.sub(string.Trim(tostring(text or "")),1,240); if text=="" then text="Требуется экстренная помощь" end
        local r={id=EM.NextCallID,category=tostring(category or "medical"),text=text,caller=IsValid(ply) and key(ply) or "system",callerName=IsValid(ply) and rpName(ply) or "Автоматическая система",patient=IsValid(patient) and key(patient) or "",patientName=IsValid(patient) and rpName(patient) or "",pos={x=pos.x,y=pos.y,z=pos.z},status="open",created=os.time()}
        EM.NextCallID=EM.NextCallID+1; EM.Calls[#EM.Calls+1]=r; while #EM.Calls>200 do table.remove(EM.Calls,1) end
        save(CALL_FILE,{version=1,calls=EM.Calls},"вызов #"..r.id); notifyResponders("Новый вызов #"..r.id..": "..r.text); hook.Run("GRM_911_Call",ply,r)
        return r
    end

    local function medCardEntry(ply,kind,text,doctor)
        local MD=GRM.Medical; if not (MD and MD.HasCard and MD.CardOf and MD.HasCard(key(ply))) then return end
        local card=MD.CardOf(key(ply)); card.entries=istable(card.entries) and card.entries or {}; card.entries[#card.entries+1]={time=os.time(),kind=kind,text=text,doctor=IsValid(doctor) and rpName(doctor) or "Система 911"}; while #card.entries>100 do table.remove(card.entries,1) end
        if MD.SaveCards then MD.SaveCards("911: "..kind) end
    end
    local function woundedRagdoll(ply)
        local rag=ply._grm911Ragdoll
        return IsValid(rag) and rag or nil
    end
    local function removeWoundedRagdoll(ply,restore)
        local rag=woundedRagdoll(ply)
        local pos=IsValid(rag) and rag:GetPos() or ply:GetPos()
        if IsValid(rag) then rag:Remove() end
        ply._grm911Ragdoll=nil
        ply:SetNWEntity("GRM_911_Ragdoll",NULL)
        if restore then
            ply:SetNoDraw(false); ply:DrawShadow(true)
            ply:SetCollisionGroup(ply._grm911OldCollision or COLLISION_GROUP_PLAYER)
        end
        return pos
    end
    local function spawnWoundedRagdoll(ply)
        local old=woundedRagdoll(ply); if IsValid(old) then old:Remove() end
        local rag=ents.Create("prop_ragdoll")
        if not IsValid(rag) then return nil end
        rag:SetModel(ply:GetModel()); rag:SetPos(ply:GetPos()); rag:SetAngles(ply:GetAngles()); rag:Spawn(); rag:Activate()
        rag:SetNWBool("GRM_911_WoundedRagdoll",true); rag:SetNWString("GRM_911_PatientName",rpName(ply)); rag:SetNWBool("GRM_911_Stable",false)
        rag._grm911Patient=ply; ply._grm911Ragdoll=rag; ply:SetNWEntity("GRM_911_Ragdoll",rag)
        local vel=ply:GetVelocity(); for i=0,rag:GetPhysicsObjectCount()-1 do local ph=rag:GetPhysicsObjectNum(i); if IsValid(ph) then ph:SetVelocity(vel) end end
        ply._grm911OldCollision=ply:GetCollisionGroup(); ply:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE); ply:SetNoDraw(true); ply:DrawShadow(false)
        return rag
    end
    local function clearDowned(ply)
        timer.Remove("GRM_911_Bleedout_"..ply:EntIndex()); ply:SetNWBool("GRM_911_Downed",false); ply:SetNWBool("GRM_911_Stable",false); ply:SetNWInt("GRM_911_DeathAt",0); ply:Freeze(false); removeWoundedRagdoll(ply,true); ply._grm911Downed=nil
    end
    function EM.Down(ply,dmg)
        if not EM.Config.enabled or not IsValid(ply) or not ply:Alive() or ply:GetNWBool("GRM_911_Downed") then return false end
        ply:SetHealth(1); ply:ExitVehicle(); ply:Freeze(true); ply:SetNWBool("GRM_911_Downed",true); ply:SetNWBool("GRM_911_Stable",false)
        local deathAt=os.time()+EM.Config.bleedoutSec; ply:SetNWInt("GRM_911_DeathAt",deathAt)
        local woundRag=spawnWoundedRagdoll(ply); if IsValid(woundRag) then woundRag:SetNWInt("GRM_911_DeathAt",deathAt) end
        local att=dmg and dmg:GetAttacker() or nil; local inf=dmg and dmg:GetInflictor() or nil
        ply._grm911Downed={at=os.time(),attacker=IsValid(att) and (att:IsPlayer() and rpName(att) or att:GetClass()) or "неизвестно",attackerKey=IsValid(att) and att:IsPlayer() and key(att) or "",weapon=IsValid(inf) and inf:GetClass() or "неизвестно",damage=dmg and math.floor(dmg:GetDamage()) or 0,damageType=dmg and dmg:GetDamageType() or 0,pos=ply:GetPos(),wounds=ply._grm911Wounds or {}}
        timer.Create("GRM_911_Bleedout_"..ply:EntIndex(),EM.Config.bleedoutSec,1,function() if IsValid(ply) and ply:GetNWBool("GRM_911_Downed") then ply._grm911ForceDeath=true; local pos=removeWoundedRagdoll(ply,true); ply:SetPos(pos+Vector(0,0,8)); ply:Freeze(false); ply:Kill() end end)
        if EM.Config.autoCall then EM.CreateCall(nil,"medical","Автоматический сигнал: тяжело ранен "..rpName(ply),ply:GetPos(),ply) end
        medCardEntry(ply,"vitals","Доставлен сигнал о критическом ранении",nil); hook.Run("GRM_911_Downed",ply,ply._grm911Downed)
        return true
    end
    function EM.Stabilize(actor,target)
        if not IsValid(target) or not target:GetNWBool("GRM_911_Downed") then return false,"Пациент не находится в тяжёлом состоянии" end
        if target:GetNWBool("GRM_911_Stable") then return false,"Пациент уже стабилизирован" end
        target:SetNWBool("GRM_911_Stable",true); local deathAt=os.time()+EM.Config.stabilizedSec; target:SetNWInt("GRM_911_DeathAt",deathAt)
        local rag=woundedRagdoll(target); if IsValid(rag) then rag:SetNWBool("GRM_911_Stable",true); rag:SetNWInt("GRM_911_DeathAt",deathAt) end
        timer.Adjust("GRM_911_Bleedout_"..target:EntIndex(),EM.Config.stabilizedSec,1,function() if IsValid(target) and target:GetNWBool("GRM_911_Downed") then target._grm911ForceDeath=true; local pos=removeWoundedRagdoll(target,true); target:SetPos(pos+Vector(0,0,8)); target:Freeze(false); target:Kill() end end)
        target:SetHealth(math.max(30,target:Health()))
        target:SetNWInt("GRM_Bleed",0); medCardEntry(target,"vitals","Стабилизация на месте. Исполнитель: "..rpName(actor),actor); hook.Run("GRM_911_Stabilized",actor,target); return true,"Пациент стабилизирован"
    end
    local function subsidy(actor)
        local amt=EM.Config.reviveSubsidy; if amt<=0 then return end
        local fac=factionOf(actor); local E=GRM.Economy
        if fac and GRM.FactionBudgetAdd and E and E.StateBudgetGet and E.StateBudgetAdd and E.StateBudgetGet()>=amt then E.StateBudgetAdd(-amt,"911: медицинская помощь"); GRM.FactionBudgetAdd(fac,amt,"911: успешная реанимация") end
    end
    function EM.Revive(actor,target)
        if not isMedic(actor) then return false,"Реанимацию может проводить только медик" end
        if not IsValid(target) or not target:GetNWBool("GRM_911_Downed") then return false,"Пациент не нуждается в реанимации" end
        local rag=woundedRagdoll(target); local returnPos=IsValid(rag) and rag:GetPos() or target:GetPos()
        clearDowned(target); target:SetPos(returnPos+Vector(0,0,8)); target:SetHealth(math.min(target:GetMaxHealth(),EM.Config.reviveHealth)); target:SetNWInt("GRM_Pain",math.max(25,target:GetNWInt("GRM_Pain",0))); subsidy(actor)
        medCardEntry(target,"operation","Экстренная реанимация. Исполнитель: "..rpName(actor),actor); hook.Run("GRM_911_Revived",actor,target); return true,"Пациент реанимирован"
    end

    hook.Add("EntityTakeDamage","GRM_911_Damage",function(target,dmg)
        if not EM.Config.enabled or not IsValid(target) or not target:IsPlayer() or not target:Alive() then return end
        if target:GetNWBool("GRM_911_Downed") then dmg:SetDamage(0) return true end
        local att=dmg:GetAttacker(); target._grm911Wounds=target._grm911Wounds or {}; target._grm911Wounds[#target._grm911Wounds+1]={at=os.time(),damage=math.floor(dmg:GetDamage()),dtype=dmg:GetDamageType(),attacker=IsValid(att) and (att:IsPlayer() and rpName(att) or att:GetClass()) or "мир"}; while #target._grm911Wounds>12 do table.remove(target._grm911Wounds,1) end
        if target._grm911ForceDeath then return end
        if dmg:GetDamage() >= target:Health() then EM.Down(target,dmg); dmg:SetDamage(0); return true end
    end)
    hook.Add("StartCommand","GRM_911_Restrict",function(ply,cmd) if ply:GetNWBool("GRM_911_Downed") then cmd:ClearMovement(); cmd:ClearButtons() end end)
    hook.Add("CanPlayerEnterVehicle","GRM_911_NoVehicle",function(ply) if ply:GetNWBool("GRM_911_Downed") then return false end end)
    hook.Add("PlayerSpawn","GRM_911_Reset",function(ply) clearDowned(ply); ply._grm911ForceDeath=nil; ply._grm911Wounds={} end)
    hook.Add("PlayerDisconnected","GRM_911_RagCleanup",function(ply) local rag=woundedRagdoll(ply); if IsValid(rag) then rag:Remove() end end)

    local function lootDisplay(slot)
        local id=tostring(slot.id or "")
        local def=GRM.Inventory and GRM.Inventory.GetItemDef and GRM.Inventory.GetItemDef(id) or nil
        local name=(def and def.name) or id
        local data=istable(slot.data) and slot.data or {}
        local docType=data.docType
        if not docType and GRM.Documents and GRM.Documents.PhysicalDefs then
            for typ,pd in pairs(GRM.Documents.PhysicalDefs) do if pd.item==id then docType=typ break end end
        end
        local number=tostring(data.number or "")
        local ownerName=""
        if docType and GRM.Documents and GRM.Documents.PhysicalRecord then
            local rec=GRM.Documents.PhysicalRecord(tostring(data.ownerKey or ""),docType)
            if istable(rec) then ownerName=tostring(rec.fullName or rec.businessName or ""); if number=="" then number=tostring(rec.number or "") end end
        end
        return {name=name,id=id,count=tonumber(slot.count) or 1,isDocument=docType~=nil,docType=docType or "",number=number,ownerName=ownerName}
    end
    local function extractInventory(victim)
        local loot,documents={},{}
        if not EM.Config.lootInventory or not (GRM.Inventory and GRM.Inventory.GetPlayerInv) then return loot,documents end
        local inv=GRM.Inventory.GetPlayerInv(victim)
        if not inv then return loot,documents end
        local indices={}; for idx,slot in pairs(inv.slots or {}) do if istable(slot) and slot.id then indices[#indices+1]=tonumber(idx) or idx end end
        table.sort(indices,function(a,b)return tonumber(a)<tonumber(b)end)
        for _,idx in ipairs(indices) do
            local slot=inv.slots[idx]
            if istable(slot) and slot.id then
                local copy={id=slot.id,count=tonumber(slot.count) or 1,data=istable(slot.data) and table.Copy(slot.data) or nil}
                loot[#loot+1]=copy
                local info=lootDisplay(copy); if info.isDocument then documents[#documents+1]=info end
                if GRM.Inventory.RemoveFromSlot then GRM.Inventory.RemoveFromSlot(victim,idx,copy.count) else inv.slots[idx]=nil end
            end
        end
        if GRM.Inventory.SyncToClient then GRM.Inventory.SyncToClient(victim) end
        return loot,documents
    end
    EM.ExtractInventory=extractInventory

    EM.Bodies=EM.Bodies or {}
    local function bodyData(victim,attacker)
        local d=victim._grm911Downed or {}; return {victim=key(victim),name=rpName(victim),time=os.time(),cause=tonumber(d.damageType) or 0,damage=tonumber(d.damage) or 0,weapon=tostring(d.weapon or "неизвестно"),attacker=tostring(d.attacker or (IsValid(attacker) and (attacker:IsPlayer() and rpName(attacker) or attacker:GetClass())) or "неизвестно"),attackerKey=tostring(d.attackerKey or ""),wounds=d.wounds or victim._grm911Wounds or {},pos={x=victim:GetPos().x,y=victim:GetPos().y,z=victim:GetPos().z}}
    end
    local function pruneBodies()
        local live={}; for _,e in ipairs(EM.Bodies) do if IsValid(e) then live[#live+1]=e end end; EM.Bodies=live
        while #EM.Bodies>=EM.Config.maxBodies do local e=table.remove(EM.Bodies,1); if IsValid(e) then e:Remove() end end
    end
    hook.Add("PlayerDeath","GRM_911_Corpse",function(victim,inflictor,attacker)
        timer.Remove("GRM_911_Bleedout_"..victim:EntIndex()); victim:Freeze(false); victim:SetNWBool("GRM_911_Downed",false)
        local wr=woundedRagdoll(victim); if IsValid(wr) then local wp=wr:GetPos(); removeWoundedRagdoll(victim,true); victim:SetPos(wp+Vector(0,0,8)) else removeWoundedRagdoll(victim,true) end
        local loot,documents=extractInventory(victim)
        local data=bodyData(victim,attacker); data.documents=documents; pruneBodies()
        local body=ents.Create("prop_ragdoll"); if IsValid(body) then body:SetModel(victim:GetModel()); body:SetPos(victim:GetPos()); body:SetAngles(victim:GetAngles()); body:Spawn(); body:SetNWBool("GRM_911_Body",true); body:SetNWString("GRM_911_Name",data.name); body:SetNWInt("GRM_911_Time",data.time); body._grm911Body=data; body._grm911Loot=loot; EM.Bodies[#EM.Bodies+1]=body; timer.Simple(EM.Config.bodyTTL,function() if IsValid(body) then body:Remove() end end) end
        EM.Cases[#EM.Cases+1]={id="case_"..data.time.."_"..math.random(100,999),body=data,actions={},status="body",created=data.time}; while #EM.Cases>300 do table.remove(EM.Cases,1) end; save(CASE_FILE,{version=1,cases=EM.Cases},"смерть "..data.name)
        medCardEntry(victim,"operation","Констатирована смерть. Причина повреждения: "..data.weapon,nil); hook.Run("GRM_911_Death",victim,data,body); victim._grm911ForceDeath=nil
    end)
    hook.Add("CreateEntityRagdoll","GRM_911_RemoveDefaultRag",function(owner,rag) if IsValid(owner) and IsValid(rag) then timer.Simple(0,function() if IsValid(rag) then rag:Remove() end end) end end)

    local function sendBody(ply,body)
        local d=body._grm911Body; if not d then return end
        local professional=isMedic(ply) or isInvestigator(ply)
        if professional then
            for _, case in ipairs(EM.Cases or {}) do
                if istable(case.body) and case.body.time == d.time and case.body.victim == d.victim then
                    case.actions = istable(case.actions) and case.actions or {}
                    case.actions[#case.actions + 1] = { time = os.time(), action = "examine", by = key(ply), byName = rpName(ply) }
                    break
                end
            end
            save(CASE_FILE,{version=1,cases=EM.Cases},"осмотр тела "..d.name)
            hook.Run("GRM_911_BodyExamined",ply,body,d)
        end
        net.Start(NET_BODY) net.WriteEntity(body) net.WriteBool(professional) net.WriteTable(professional and d or {name=d.name,time=d.time}) net.Send(ply)
    end
    hook.Add("PlayerUse","GRM_911_Use",function(ply,ent)
        local patient=nil
        if IsValid(ent) and ent:IsPlayer() and ent:GetNWBool("GRM_911_Downed") then patient=ent
        elseif IsValid(ent) and ent:GetNWBool("GRM_911_WoundedRagdoll") and IsValid(ent._grm911Patient) then patient=ent._grm911Patient end
        if IsValid(patient) then
            -- E на раненом = удержание реанимации (bleedout). Меню на E
            -- перехватывает мышь и срывает подъём. Окно — только /aid или ALT+E.
            if ply:KeyDown(IN_WALK) and (ply._grm911PatientUseAt or 0) <= CurTime() then
                ply._grm911PatientUseAt = CurTime() + 1
                local can, why = isMedic(ply)
                net.Start(NET_PATIENT)
                net.WriteEntity(patient)
                net.WriteBool(can == true)
                net.WriteBool(patient:GetNWBool("GRM_911_Stable"))
                net.WriteUInt(math.max(0, patient:GetNWInt("GRM_911_DeathAt", os.time()) - os.time()), 12)
                net.WriteString(can and "" or tostring(why or ""))
                net.WriteUInt(math.Clamp(patient:GetNWInt("GRM_Bleed", 0), 0, 100), 7)
                net.WriteUInt(math.Clamp(patient:GetNWInt("GRM_Pain", 0), 0, 100), 7)
                net.Send(ply)
            end
            return false
        end
        if IsValid(ent) and ent:GetNWBool("GRM_911_Body") then
            if (ply._grm911BodyUseAt or 0) <= CurTime() then ply._grm911BodyUseAt = CurTime() + 2; sendBody(ply,ent) end
            return false
        end
    end)
    local function caseForBody(body)
        local d = IsValid(body) and body._grm911Body or nil
        if not d then return nil end
        for _, case in ipairs(EM.Cases or {}) do
            if istable(case.body) and case.body.time == d.time and case.body.victim == d.victim then return case end
        end
    end
    local function sendLoot(ply,body)
        local rows={}
        for i,slot in ipairs(body._grm911Loot or {}) do local info=lootDisplay(slot); info.index=i; rows[#rows+1]=info end
        net.Start(NET_LOOT) net.WriteEntity(body) net.WriteTable(rows) net.Send(ply)
    end
    local function takeLoot(ply,body,index)
        local loot=body._grm911Loot or {}; local slot=loot[index]
        if not istable(slot) or not slot.id then return false,"Предмет уже изъят" end
        local ok=false; local left=slot.count or 1
        if string.StartWith(tostring(slot.id),"weapon:") and GRM.Inventory and GRM.Inventory.AddWeapon then
            local cls=(slot.data and slot.data.class) or string.sub(slot.id,8); ok=GRM.Inventory.AddWeapon(ply,cls,slot.data and slot.data.clip1,slot.data and slot.data.clip2); if ok then left=0 end
        elseif GRM.Inventory and GRM.Inventory.AddItem then
            left=GRM.Inventory.AddItem(ply,slot.id,slot.count or 1,slot.data); ok=left<(slot.count or 1)
        end
        if not ok then return false,"В инвентаре нет места" end
        if left>0 then slot.count=left else table.remove(loot,index) end
        local info=lootDisplay(slot)
        local case=caseForBody(body); if case then case.actions=case.actions or {}; case.actions[#case.actions+1]={time=os.time(),action="loot_take",item=info.id,itemName=info.name,by=key(ply),byName=rpName(ply)}; save(CASE_FILE,{version=1,cases=EM.Cases},"изъятие из тела") end
        hook.Run("GRM_911_BodyLootTaken",ply,body,slot,info)
        return true,"Изъято: "..info.name
    end
    EM.TakeBodyLoot=takeLoot
    net.Receive(NET_BODY_ACT,function(_,ply)
        local body=net.ReadEntity(); local act=net.ReadString()
        if not IsValid(body) or not body:GetNWBool("GRM_911_Body") or ply:GetPos():DistToSqr(body:GetPos())>180*180 then return end
        if act=="search" then sendLoot(ply,body) return end
        if act=="take" then local idx=net.ReadUInt(8); local ok,msg=takeLoot(ply,body,idx); if GRM.Notify then GRM.Notify(ply,msg,ok and 100 or 255,ok and 220 or 130,ok and 140 or 110) end; sendLoot(ply,body); return end
        local case=caseForBody(body); if not case then return end
        if act=="seal" and isInvestigator(ply) then
            case.status="sealed"; case.actions[#case.actions+1]={time=os.time(),action="seal",by=key(ply),byName=rpName(ply)}
        elseif act=="morgue" and isMedic(ply) then
            case.status="morgue"; case.actions[#case.actions+1]={time=os.time(),action="morgue",by=key(ply),byName=rpName(ply)}; body:Remove()
        else return end
        save(CASE_FILE,{version=1,cases=EM.Cases},"действие с телом")
    end)
    local function sendCases(ply)
        if not isInvestigator(ply) then return end
        local rows={}
        for i=#EM.Cases,math.max(1,#EM.Cases-99),-1 do local c=EM.Cases[i]; rows[#rows+1]={id=c.id,status=c.status,created=c.created,body=c.body,actions=c.actions} end
        net.Start(NET_CASES) net.WriteTable(rows) net.Send(ply)
    end

    local function delayedTreatment(actor,target,kind,seconds)
        if (actor._grm911TreatAt or 0)>CurTime() then return end; actor._grm911TreatAt=CurTime()+seconds
        local start=actor:GetPos(); if GRM.Notify then GRM.Notify(actor,"Процедура начата. Не отходите от пациента "..seconds.." с.",120,220,255) end
        timer.Simple(seconds,function()
            local rag=IsValid(target) and woundedRagdoll(target) or nil; local patientPos=IsValid(rag) and rag:GetPos() or (IsValid(target) and target:GetPos() or vector_origin)
            if not IsValid(actor) or not IsValid(target) or actor:GetPos():DistToSqr(patientPos)>150*150 or actor:GetPos():DistToSqr(start)>180*180 then return end
            local ok,msg=kind=="revive" and EM.Revive(actor,target) or EM.Stabilize(actor,target); if IsValid(actor) then if GRM.Notify then GRM.Notify(actor,msg,ok and 80 or 255,ok and 230 or 120,ok and 150 or 110) else actor:ChatPrint("[911] "..msg) end end
        end)
    end
    net.Receive(NET_TREAT,function(_,ply) local target=net.ReadEntity(); local act=net.ReadString(); local rag=IsValid(target) and woundedRagdoll(target) or nil; local tpos=IsValid(rag) and rag:GetPos() or (IsValid(target) and target:GetPos() or vector_origin); if not IsValid(target) or not target:IsPlayer() or ply:GetPos():DistToSqr(tpos)>160*160 then return end; if act=="stabilize" then delayedTreatment(ply,target,act,6)
        elseif act=="revive" then
            local can,why=isMedic(ply)
            if can then delayedTreatment(ply,target,act,10)
            else ply:ChatPrint("[911] Реанимация недоступна: "..tostring(why or "нет допуска")) end
        elseif act=="checkup" then
            -- Осмотр доступен всем: это РП-действие, а не лечение.
            ply:ChatPrint(("[911] Осмотр: %s · %s · кровопотеря %d%% · боль %d%% · до остановки %d с")
                :format(rpName(target), target:GetNWBool("GRM_911_Stable") and "стабилизирован" or "критическое",
                    target:GetNWInt("GRM_Bleed",0), target:GetNWInt("GRM_Pain",0),
                    math.max(0,target:GetNWInt("GRM_911_DeathAt",os.time())-os.time())))
            -- Вечер-15: отыгровка осмотра — через шину (тот же радиус 355),
            -- не ручным ChatPrint-циклом (правило: «* …» живёт только в
            -- GRM.RPBroadcast → свой чат; OWNER_REPORTS §4).
            GRM.RPBroadcast(ply, "осматривает пострадавшего.", 355)
        elseif act=="call" then
            if (ply._grm911CallAt or 0)>CurTime() then ply:ChatPrint("[911] Вызов уже отправлен, подождите.") return end
            ply._grm911CallAt=CurTime()+10
            EM.CreateCall(ply,"medical","Нужна помощь: тяжело ранен "..rpName(target),tpos,target)
            ply:ChatPrint("[911] Вызов медицинской службы отправлен.")
        end end)
    net.Receive(NET_CALL_SEND,function(_,ply) if not IsValid(ply) or (ply._grm911CallAt or 0)>CurTime() then return end; ply._grm911CallAt=CurTime()+10; EM.CreateCall(ply,net.ReadString(),net.ReadString(),ply:GetPos(),nil) end)
    net.Receive(NET_CALL_ACT,function(_,ply) if not (isMedic(ply) or isInvestigator(ply)) then return end; local id=net.ReadUInt(32); local act=net.ReadString(); for _,r in ipairs(EM.Calls) do if r.id==id and r.status~="closed" then if act=="take" then r.status="assigned"; r.assigned=key(ply); r.assignedName=rpName(ply); net.Start(NET_MARKER) net.WriteBool(true) net.WriteVector(Vector(r.pos.x,r.pos.y,r.pos.z)) net.WriteUInt(r.id,32) net.Send(ply) elseif act=="close" then r.status="closed"; r.closed=os.time(); r.closedBy=rpName(ply); net.Start(NET_MARKER) net.WriteBool(false) net.Send(ply) end; save(CALL_FILE,{version=1,calls=EM.Calls},"вызов действие"); pushCalls(ply); break end end end)
    net.Receive(NET_ADMIN_SAVE,function(_,ply) if not IsValid(ply) or not ply:IsSuperAdmin() then return end; EM.Config=normCfg(net.ReadTable()); save(CFG_FILE,EM.Config,"админ"); end)

    local function openCallForm(ply) net.Start(NET_CALL_FORM) net.Send(ply) end
    local function openAdmin(ply) if ply:IsSuperAdmin() then net.Start(NET_ADMIN) net.WriteTable(EM.Config) net.Send(ply) end end
    local function examine(ply)
        local e=ply:GetEyeTrace().Entity; if not IsValid(e) or not e:GetNWBool("GRM_911_Body") or ply:GetPos():DistToSqr(e:GetPos())>180*180 then ply:ChatPrint("[911] Наведитесь на тело рядом.") return end; sendBody(ply,e)
    end
    local function chat(ply,text)
        local t=string.Trim(text or ""); local low=string.lower(t)
        if low=="/911" then openCallForm(ply) return true end
        if string.sub(low,1,5)=="/911 " then
            if (ply._grm911CallAt or 0) <= CurTime() then ply._grm911CallAt=CurTime()+10; EM.CreateCall(ply,"emergency",string.sub(t,6),ply:GetPos(),nil) else ply:ChatPrint("[911] Повторный вызов можно отправить через несколько секунд.") end
            return true
        end
        if low=="/911_calls" or low=="/вызовы" then pushCalls(ply) return true end
        if low=="/911_admin" then openAdmin(ply) return true end
        if low=="/911_cases" or low=="/дела911" then sendCases(ply) return true end
        if low=="/aid" or low=="/помощь" then local aimed=ply:GetEyeTrace().Entity; local target=(IsValid(aimed) and aimed:IsPlayer()) and aimed or (IsValid(aimed) and aimed:GetNWBool("GRM_911_WoundedRagdoll") and aimed._grm911Patient or nil); if IsValid(target) then local can,why=isMedic(ply); net.Start(NET_PATIENT) net.WriteEntity(target) net.WriteBool(can==true) net.WriteBool(target:GetNWBool("GRM_911_Stable")) net.WriteUInt(math.max(0,target:GetNWInt("GRM_911_DeathAt",os.time())-os.time()),12) net.WriteString(can and "" or tostring(why or "")) net.WriteUInt(math.Clamp(target:GetNWInt("GRM_Bleed",0),0,100),7) net.WriteUInt(math.Clamp(target:GetNWInt("GRM_Pain",0),0,100),7) net.Send(ply) end return true end
        if low=="/forensics" or low=="/осмотр" then examine(ply) return true end
        return false
    end
    hook.Add("PlayerSay", "GRM_911_Transform", function(ply, text, teamSays)
        local data = { tostring(text or ""), SkipPlayerSay = false }
            if istable(data) and isstring(data[1]) and chat(ply,data[1]) then data[1]="" data.SkipPlayerSay=true end
        if data.SkipPlayerSay == true then return "" end
    end)
    hook.Add("PlayerSay","GRM_911_Chat",function(ply,text) if chat(ply,text) then return "" end end)
    timer.Create("GRM_911_Autosave",60,0,function() saveAll("авто") end); hook.Add("ShutDown","GRM_911_Save",function() saveAll("shutdown") end)
else
    surface.CreateFont("GRM911_Title",{font="Roboto",size=22,weight=800,extended=true}); surface.CreateFont("GRM911_Text",{font="Roboto",size=14,weight=500,extended=true}); surface.CreateFont("GRM911_HUD",{font="Roboto",size=20,weight=800,extended=true})
    local C={bg=Color(8,14,23,248),panel=Color(16,27,42),text=Color(225,238,247),muted=Color(132,160,178),red=Color(244,78,96),green=Color(64,222,147),cyan=Color(48,204,255)}
    local marker=nil
    local function frame(title,w,h) local f=vgui.Create("DFrame") f:SetSize(w,h) f:Center() f:MakePopup() f:SetTitle("") f:ShowCloseButton(false) f.Paint=function(_,pw,ph) draw.RoundedBox(9,0,0,pw,ph,C.bg); draw.RoundedBoxEx(9,0,0,pw,52,Color(10,22,37),true,true,false,false); draw.SimpleText(title,"GRM911_Title",16,26,C.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER) end local x=vgui.Create("DButton",f) x:SetPos(w-42,10) x:SetSize(30,30) x:SetText("✕") x:SetTextColor(color_white) x.DoClick=function() f:Close() end return f end
    local function button(parent,text,y,col,fn) local b=vgui.Create("DButton",parent) b:SetPos(16,y) b:SetSize(parent:GetWide()-32,36) b:SetText(text) b:SetTextColor(color_white) b.Paint=function(s,w,h) draw.RoundedBox(5,0,0,w,h,s:IsHovered() and Color(math.min(255,col.r+20),math.min(255,col.g+20),math.min(255,col.b+20)) or col) end b.DoClick=fn return b end
    net.Receive(NET_CALL_FORM,function() local f=frame("911 • ЭКСТРЕННЫЙ ВЫЗОВ",560,330); local cat=vgui.Create("DComboBox",f) cat:SetPos(16,72) cat:SetSize(528,30) cat:AddChoice("Медицинская помощь","medical",true); cat:AddChoice("Полиция / происшествие","police"); cat:AddChoice("Пожар","fire"); local txt=vgui.Create("DTextEntry",f) txt:SetPos(16,116) txt:SetSize(528,100) txt:SetMultiline(true) txt:SetPlaceholderText("Кратко опишите происшествие и ориентиры..."); button(f,"ОТПРАВИТЬ ВЫЗОВ",238,C.red,function() local _,id=cat:GetSelected(); net.Start(NET_CALL_SEND) net.WriteString(id or "emergency") net.WriteString(txt:GetValue()) net.SendToServer(); f:Close() end) end)
    --[[ ОКНО ПОМОЩИ ПОСТРАДАВШЕМУ (переписано 21.08).
         Было: кнопка «Реанимировать» просто НЕ создавалась, если сервер
         посчитал игрока не медиком — человек видел одну «Стабилизировать» и
         не понимал, что делать дальше. Стало: все действия видны всегда,
         недоступное подписано причиной, плюс осмотр и вызов медслужбы. ]]
    local function buttonState(parent, text, y, col, enabled, fn, hint)
        local b = button(parent, text, y, enabled and col or Color(60, 64, 74), function()
            if not enabled then
                if hint and hint ~= "" then chat.AddText(Color(225, 90, 80), "[911] " .. hint) end
                surface.PlaySound("buttons/button10.wav")
                return
            end
            fn()
        end)
        if not enabled then b:SetTextColor(Color(150, 155, 165)) end
        if hint and hint ~= "" then b:SetTooltip(hint) end
        return b
    end

    net.Receive(NET_PATIENT, function()
        local target = net.ReadEntity()
        local canRevive = net.ReadBool()
        local stable = net.ReadBool()
        local left = net.ReadUInt(12)
        local why = net.ReadString()
        local bleed = net.ReadUInt(7)
        local pain = net.ReadUInt(7)
        if not IsValid(target) then return end
        if IsValid(EM._patientFrame) and EM._patientTarget == target then return end
        if IsValid(EM._patientFrame) then EM._patientFrame:Remove() end

        local f = frame("911 • ПОСТРАДАВШИЙ", 520, 420)
        EM._patientFrame = f
        EM._patientTarget = target
        f.OnRemove = function()
            if EM._patientFrame == f then EM._patientFrame = nil EM._patientTarget = nil end
        end

        local rp = target:GetNWString("GRM_RPName", "")
        local l = vgui.Create("DLabel", f)
        l:SetPos(16, 66) l:SetSize(488, 84)
        l:SetFont("GRM911_Text") l:SetTextColor(C.text) l:SetWrap(true)
        l:SetText((rp ~= "" and rp or target:Nick()) ..
            "\nСостояние: " .. (stable and "стабилизирован" or "критическое") ..
            "\nКровопотеря: " .. bleed .. "% · боль: " .. pain .. "%" ..
            "\nДо остановки жизненных функций: " .. left .. " с")

        local function send(action)
            net.Start(NET_TREAT)
            net.WriteEntity(target)
            net.WriteString(action)
            net.SendToServer()
        end

        buttonState(f, stable and "УЖЕ СТАБИЛИЗИРОВАН" or "СТАБИЛИЗИРОВАТЬ (6 С)", 156, C.cyan,
            not stable, function() send("stabilize") f:Close() end,
            stable and "Пациент уже стабилизирован" or nil)

        buttonState(f, canRevive and "РЕАНИМИРОВАТЬ (10 С)" or "РЕАНИМИРОВАТЬ — НЕТ ДОПУСКА", 202, C.green,
            canRevive, function() send("revive") f:Close() end,
            canRevive and "" or (why ~= "" and why or "Нужен медик, аптечка или адреналин"))

        button(f, "ОСМОТРЕТЬ ПОСТРАДАВШЕГО", 248, C.panel, function() send("checkup") end)
        button(f, "ВЫЗВАТЬ МЕДИЦИНСКУЮ СЛУЖБУ (911)", 294, C.red, function() send("call") f:Close() end)

        local note = vgui.Create("DLabel", f)
        note:SetPos(16, 340) note:SetSize(488, 60)
        note:SetFont("GRM911_Text") note:SetTextColor(C.muted) note:SetWrap(true)
        note:SetText(canRevive and "Стабилизация продлевает жизнь, реанимация поднимает человека на ноги."
            or ("Поднять на ноги может медик. " .. (why ~= "" and why or "") ..
                ". Пока — стабилизируйте и вызовите службу."))
    end)

    net.Receive(NET_CALLS,function() local rows=net.ReadTable() or {}; local f=frame("911 • АКТИВНЫЕ ВЫЗОВЫ",820,600); local sc=vgui.Create("DScrollPanel",f) sc:SetPos(12,62) sc:SetSize(796,526); for _,r in ipairs(rows) do local p=vgui.Create("DPanel",sc) p:Dock(TOP) p:DockMargin(0,0,0,7) p:SetTall(92) p.Paint=function(_,w,h) draw.RoundedBox(6,0,0,w,h,C.panel); draw.SimpleText("#"..r.id.." • "..r.category.." • "..r.status,"GRM911_Text",12,12,C.red); draw.SimpleText(r.text,"GRM911_Text",12,36,C.text); draw.SimpleText(r.callerName..(r.assignedName~="" and " • принял: "..r.assignedName or ""),"GRM911_Text",12,62,C.muted) end local take=vgui.Create("DButton",p) take:SetPos(620,10) take:SetSize(160,30) take:SetText("Принять") take.DoClick=function() net.Start(NET_CALL_ACT) net.WriteUInt(r.id,32) net.WriteString("take") net.SendToServer() end local close=vgui.Create("DButton",p) close:SetPos(620,50) close:SetSize(160,30) close:SetText("Закрыть") close.DoClick=function() net.Start(NET_CALL_ACT) net.WriteUInt(r.id,32) net.WriteString("close") net.SendToServer() end sc:AddItem(p) end end)
    net.Receive(NET_BODY,function() local ent=net.ReadEntity(); local pro=net.ReadBool(); local d=net.ReadTable() or {}; local f=frame("911 • ОСМОТР ТЕЛА",620,440); local text="Личность: "..tostring(d.name or "неизвестно").."\nВремя смерти: "..os.date("%d.%m.%Y %H:%M",tonumber(d.time) or os.time()); if pro then text=text.."\nОрудие/источник: "..tostring(d.weapon).."\nПредполагаемый нападавший: "..tostring(d.attacker).."\nПоследний урон: "..tostring(d.damage).."\nСледов повреждений: "..tostring(#(d.wounds or {})).."\nДокументов при теле: "..tostring(#(d.documents or {})) else text=text.."\nДля подробного заключения нужен медик или следователь." end local l=vgui.Create("DLabel",f) l:SetPos(18,74) l:SetSize(584,240) l:SetFont("GRM911_Text") l:SetTextColor(C.text) l:SetWrap(true) l:SetText(text); if IsValid(ent) then local search=vgui.Create("DButton",f) search:SetPos(18,320) search:SetSize(584,32) search:SetText("ОБЫСКАТЬ ТЕЛО") search.DoClick=function() net.Start(NET_BODY_ACT) net.WriteEntity(ent) net.WriteString("search") net.SendToServer() end end; if pro and IsValid(ent) then local seal=vgui.Create("DButton",f) seal:SetPos(18,360) seal:SetSize(280,36) seal:SetText("ОПЕЧАТАТЬ МЕСТО") seal.DoClick=function() net.Start(NET_BODY_ACT) net.WriteEntity(ent) net.WriteString("seal") net.SendToServer(); f:Close() end local morgue=vgui.Create("DButton",f) morgue:SetPos(316,360) morgue:SetSize(286,36) morgue:SetText("ДОСТАВИТЬ В МОРГ") morgue.DoClick=function() net.Start(NET_BODY_ACT) net.WriteEntity(ent) net.WriteString("morgue") net.SendToServer(); f:Close() end end end)
    net.Receive(NET_LOOT,function()
        local body,rows=net.ReadEntity(),net.ReadTable() or {}
        if IsValid(EM._lootFrame) then EM._lootFrame:Remove() end
        local f=frame("911 • ОБЫСК ТЕЛА",760,560); EM._lootFrame=f; local sc=vgui.Create("DScrollPanel",f); sc:SetPos(12,62); sc:SetSize(736,486)
        if #rows==0 then local l=vgui.Create("DLabel",sc); l:Dock(TOP); l:SetTall(50); l:SetText("При теле ничего не найдено."); l:SetTextColor(C.muted); l:SetFont("GRM911_Text"); sc:AddItem(l) end
        for _,r in ipairs(rows) do
            local row=vgui.Create("DPanel",sc); row:Dock(TOP); row:DockMargin(0,0,0,7); row:SetTall(r.isDocument and 78 or 58)
            row.Paint=function(_,w,h) draw.RoundedBox(6,0,0,w,h,C.panel); draw.SimpleText(tostring(r.name).." ×"..tostring(r.count),"GRM911_Text",12,12,r.isDocument and Color(250,185,63) or C.text); if r.isDocument then draw.SimpleText("Документ: "..tostring(r.docType).." • №"..tostring(r.number).." • "..tostring(r.ownerName),"GRM911_Text",12,38,C.muted) end end
            local take=vgui.Create("DButton",row); take:Dock(RIGHT); take:SetWide(140); take:SetText("ИЗЪЯТЬ"); take.DoClick=function() if not IsValid(body) then return end net.Start(NET_BODY_ACT); net.WriteEntity(body); net.WriteString("take"); net.WriteUInt(tonumber(r.index) or 0,8); net.SendToServer() end
            sc:AddItem(row)
        end
    end)

    net.Receive(NET_CASES,function() local rows=net.ReadTable() or {}; local f=frame("911 • ЖУРНАЛ РАССЛЕДОВАНИЙ",900,620); local sc=vgui.Create("DScrollPanel",f) sc:SetPos(12,62) sc:SetSize(876,546); for _,c in ipairs(rows) do local p=vgui.Create("DPanel",sc) p:Dock(TOP) p:DockMargin(0,0,0,7) p:SetTall(86) p.Paint=function(_,w,h) draw.RoundedBox(6,0,0,w,h,C.panel); draw.SimpleText(tostring(c.id).." • "..tostring(c.status),"GRM911_Text",12,12,C.red); draw.SimpleText(tostring(c.body and c.body.name or "неизвестно").." • "..os.date("%d.%m.%Y %H:%M",tonumber(c.created) or 0),"GRM911_Text",12,36,C.text); draw.SimpleText("Орудие: "..tostring(c.body and c.body.weapon or "—").." • действий: "..tostring(#(c.actions or {})),"GRM911_Text",12,60,C.muted) end sc:AddItem(p) end end)
    net.Receive(NET_ADMIN,function() local cfg=net.ReadTable() or {}; local f=frame("911 • НАСТРОЙКА",620,520); local vals={}; local fields={{"bleedoutSec","До смерти, сек"},{"stabilizedSec","После стабилизации, сек"},{"bodyTTL","Время тела, сек"},{"maxBodies","Максимум тел"},{"reviveHealth","HP после реанимации"},{"reviveSubsidy","Субсидия медслужбе"}}; for i,v in ipairs(fields) do local l=vgui.Create("DLabel",f) l:SetPos(16,66+(i-1)*48) l:SetSize(260,22) l:SetText(v[2]) l:SetTextColor(C.muted); local e=vgui.Create("DTextEntry",f) e:SetPos(290,64+(i-1)*48) e:SetSize(300,26) e:SetValue(tostring(cfg[v[1]] or 0)); vals[v[1]]=e end local enabled=vgui.Create("DCheckBoxLabel",f) enabled:SetPos(16,360) enabled:SetSize(260,24) enabled:SetText("Система включена") enabled:SetTextColor(C.text) enabled:SetValue(cfg.enabled and 1 or 0); local auto=vgui.Create("DCheckBoxLabel",f) auto:SetPos(290,360) auto:SetSize(300,24) auto:SetText("Автовызов при ранении") auto:SetTextColor(C.text) auto:SetValue(cfg.autoCall and 1 or 0); local loot=vgui.Create("DCheckBoxLabel",f) loot:SetPos(16,390) loot:SetSize(400,24) loot:SetText("Переносить инвентарь в тело") loot:SetTextColor(C.text) loot:SetValue(cfg.lootInventory and 1 or 0); button(f,"СОХРАНИТЬ",438,C.green,function() local t={enabled=enabled:GetChecked(),autoCall=auto:GetChecked(),lootInventory=loot:GetChecked()}; for k,e in pairs(vals) do t[k]=tonumber(e:GetValue()) end net.Start(NET_ADMIN_SAVE) net.WriteTable(t) net.SendToServer(); f:Close() end) end)
    net.Receive(NET_MARKER,function() if net.ReadBool() then marker={pos=net.ReadVector(),id=net.ReadUInt(32),at=CurTime()} else marker=nil end end)
    local WOUND_POS = Vector(0, 0, 34)
    local WOUND_ANG = Angle(0, 0, 90)
    local WOUND_BG = Color(18, 5, 8, 225)
    local WOUND_HEAD = Color(255, 70, 85)
    hook.Add("PostDrawTranslucentRenderables","GRM_911_WoundedLabels",function()
        local ragdolls=GRM.Perf and GRM.Perf.Entities and GRM.Perf.Entities("prop_ragdoll")or ents.FindByClass("prop_ragdoll")
        for _,rag in ipairs(ragdolls) do
            if IsValid(rag) and rag:GetNWBool("GRM_911_WoundedRagdoll") then
                local rp=rag:GetPos()
                WOUND_POS.x = rp.x; WOUND_POS.y = rp.y; WOUND_POS.z = rp.z + 34
                local pos=WOUND_POS
                WOUND_ANG.y = EyeAngles().y - 90
                local ang=WOUND_ANG
                cam.Start3D2D(pos,ang,0.09)
                    draw.RoundedBox(7,-105,-28,210,56,WOUND_BG)
                    surface.SetDrawColor(244,78,96,220); surface.DrawOutlinedRect(-105,-28,210,56,2)
                    draw.SimpleText("РАНЕН","GRM911_HUD",0,-20,WOUND_HEAD,TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP)
                    draw.SimpleText(rag:GetNWBool("GRM_911_Stable") and "СТАБИЛИЗИРОВАН" or "НУЖНА ПОМОЩЬ","GRM911_Text",0,5,rag:GetNWBool("GRM_911_Stable") and C.green or C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP)
                cam.End3D2D()
            end
        end
    end)
    local RAG_UP = Vector(0, 0, 48)
    local MARKER_RED = Color(244, 78, 96, 180)
    hook.Add("CalcView","GRM_911_RagdollView",function(ply,pos,ang,fov)
        if not IsValid(ply) or not ply:GetNWBool("GRM_911_Downed") then return end
        local rag=ply:GetNWEntity("GRM_911_Ragdoll")
        if not IsValid(rag) then return end
        return {origin=rag:GetPos()+RAG_UP-ang:Forward()*90,angles=ang,fov=fov,drawviewer=false}
    end)

    local DWN_BG = Color(20, 8, 12, 230)
    hook.Add("HUDPaint","GRM_911_HUD",function() local lp=LocalPlayer(); if IsValid(lp) and lp:GetNWBool("GRM_911_Downed") then local nowEpoch=(GRM.Time and GRM.Time.Epoch) and math.floor(GRM.Time.Epoch()) or os.time(); local left=math.max(0,lp:GetNWInt("GRM_911_DeathAt",nowEpoch)-nowEpoch); draw.RoundedBox(8,ScrW()/2-240,ScrH()-155,480,90,DWN_BG); draw.SimpleText("ТЯЖЁЛОЕ РАНЕНИЕ","GRM911_HUD",ScrW()/2,ScrH()-137,C.red,TEXT_ALIGN_CENTER); draw.SimpleText((lp:GetNWBool("GRM_911_Stable") and "Стабилизирован • " or "Кровопотеря • ").."до смерти "..left.." с","GRM911_Text",ScrW()/2,ScrH()-105,C.text,TEXT_ALIGN_CENTER); draw.SimpleText("Ожидайте помощь. Вызов: /911","GRM911_Text",ScrW()/2,ScrH()-82,C.muted,TEXT_ALIGN_CENTER) end; if marker then local d=math.floor(LocalPlayer():GetPos():Distance(marker.pos)); draw.SimpleText("911 #"..marker.id.." • "..d.." юн","GRM911_HUD",ScrW()/2,90,C.red,TEXT_ALIGN_CENTER) end end)
    hook.Add("PostDrawTranslucentRenderables","GRM_911_Marker",function() if marker then render.SetColorMaterial(); render.DrawWireframeSphere(marker.pos,80,20,10,MARKER_RED,true) end end)
    hook.Add("CalcMainActivity","GRM_911_Lie",function(ply) if ply:GetNWBool("GRM_911_Downed") then return ACT_DIESIMPLE,-1 end end)
end

print("[GRM 911] v"..EM.Version.." loaded")

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/911", "/911_admin", "/911_calls", "/911_cases", "/aid", "/forensics", "/вызовы", "/дела911", "/осмотр", "/помощь" })
end
