--[[--------------------------------------------------------------------
    GRM Physical Documents v1.0.0 (Код 103)
    Физические копии документов в инвентаре: до 6 экземпляров каждого
    типа, просмотр владельца, дроп/подбор моделью бланка.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Documents = GRM.Documents or {}
local DOC = GRM.Documents
DOC.PhysicalVersion = "1.2.0"
DOC.MaxPhysicalCopies = 6

local NET_VIEW = "GRM_Doc_ReceiveView"

DOC.PhysicalDefs = {
    passport = { item="passport", registry="passports", template="passport", name="Паспорт гражданина", icon="icon16/book.png" },
    badge = { item="badge", registry="badges", template="badge", name="Служебное удостоверение", icon="icon16/shield.png" },
    military = { item="military_ticket", registry="military", template="military", name="Военный билет", icon="icon16/book_open.png" },
    license = { item="driver_license", registry="licenses", template="license", name="Водительское удостоверение", icon="icon16/car.png" },
    milLicense = { item="military_license", registry="milLicenses", template="militaryLicense", name="Удостоверение военного водителя ВАИ", icon="icon16/car.png" },
    weaponLicense = { item="weapon_license", registry="weaponLicenses", template="weaponLicense", name="Лицензия на оружие", icon="icon16/gun.png" },
    businessLicense = { item="business_license", registry="businessLicenses", template="businessLicense", name="Лицензия на ведение бизнеса", icon="icon16/briefcase.png" },
}

local ALIASES = {
    civilian_license="license", weapon_license="weaponLicense", business_license="businessLicense",
    license_mil="milLicense", military_license="milLicense",
}

function DOC.CanonicalPhysicalType(docType)
    docType=tostring(docType or "")
    return ALIASES[docType] or docType
end

local function keyOf(ply)
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return IsValid(ply) and (ply:SteamID64()..":char1") or ""
end

function DOC.PhysicalRecord(ownerKey,docType)
    docType=DOC.CanonicalPhysicalType(docType)
    local def=DOC.PhysicalDefs[docType]
    if not def or not istable(DOC.Registry) then return nil,nil,nil end
    local bucket=DOC.Registry[def.registry]
    local rec=istable(bucket) and bucket[tostring(ownerKey or "")] or nil
    return istable(rec) and rec or nil,def,docType
end

local function templateFor(def,rec)
    if def.template=="badge" then return (DOC.Templates and DOC.Templates.factions and DOC.Templates.factions[tostring(rec.faction or "")]) or {} end
    return (DOC.Templates and DOC.Templates[def.template]) or {}
end

local function registerItems()
    local INV=GRM.Inventory
    if not (INV and INV.RegisterItem and INV.RegisterUseHandler) then return false end
    for docType,def in pairs(DOC.PhysicalDefs) do
        INV.RegisterItem(def.item,{
            type="item",name=def.name,desc="Физический государственный бланк. Можно использовать, передать или выбросить на землю.",
            icon=def.icon,maxStack=1,weight=0.1,model="models/props_lab/clipboard.mdl",useFunc="doc_physical_view",
        })
    end
    local function usePhysical(ply,slotIdx,slot)
        local data=istable(slot and slot.data) and slot.data or {}
        local item=tostring(slot and slot.id or "")
        local typ=data.docType
        if not typ then for id,def in pairs(DOC.PhysicalDefs) do if def.item==item then typ=id break end end end
        typ=DOC.CanonicalPhysicalType(typ)
        local owner=tostring(data.ownerKey or keyOf(ply))
        local rec,def=DOC.PhysicalRecord(owner,typ)
        if not rec then if GRM.Notify then GRM.Notify(ply,"Запись документа отсутствует в государственном реестре.",255,130,110) end return false end
        local copyGeneration=tonumber(data.generation)or 1;local currentGeneration=tonumber(rec.physicalGeneration)or 1
        if copyGeneration~=currentGeneration then if GRM.Notify then GRM.Notify(ply,"Эта физическая копия аннулирована после восстановления документа.",255,120,100)end return false end
        net.Start(NET_VIEW)
            net.WriteString(typ)
            net.WriteTable(rec)
            net.WriteTable(templateFor(def,rec))
            net.WriteBool(false)
            net.WriteString("")
        net.Send(ply)
        return true
    end
    INV.RegisterUseHandler("doc_physical_view",usePhysical)
    -- Старые предметы до миграции имели отдельные useFunc и не содержали data.
    for _,handler in ipairs({"doc_passport_view","doc_badge_view","doc_military_view","doc_license_view","doc_mil_license_view"}) do INV.RegisterUseHandler(handler,usePhysical) end
    return true
end
DOC.RegisterPhysicalItems=registerItems

if SERVER then
    local function copyCount(ply,docType,ownerKey)
        local INV=GRM.Inventory
        local inv=INV and INV.GetPlayerInv and INV.GetPlayerInv(ply)
        if not inv then return 0 end
        local def=DOC.PhysicalDefs[DOC.CanonicalPhysicalType(docType)]
        if not def then return 0 end
        local n=0
        for _,slot in pairs(inv.slots or {}) do
            if istable(slot) and slot.id==def.item then
                local data=istable(slot.data) and slot.data or {}
                local slotOwner=tostring(data.ownerKey or keyOf(ply))
                if slotOwner==ownerKey then n=n+(tonumber(slot.count) or 1) end
            end
        end
        return n
    end
    DOC.CountPhysicalCopies=copyCount
    local function removeCopyByID(ply,copyID)
        local inv=GRM.Inventory and GRM.Inventory.GetPlayerInv and GRM.Inventory.GetPlayerInv(ply);if not inv then return false end
        for idx,slot in pairs(inv.slots or{})do if istable(slot)and istable(slot.data)and tostring(slot.data.copyID or"")==tostring(copyID)then inv.slots[idx]=nil;if GRM.Inventory.SyncSlot then GRM.Inventory.SyncSlot(ply,idx)end return true end end
        return false
    end

    function DOC.GivePhysicalCopy(target,docType,ownerKey,issuer)
        if not IsValid(target) or not target:IsPlayer() then return false,"Получатель должен находиться в игре" end
        docType=DOC.CanonicalPhysicalType(docType); ownerKey=tostring(ownerKey or keyOf(target))
        local rec,def=DOC.PhysicalRecord(ownerKey,docType)
        if not rec and ownerKey==keyOf(target) and docType=="passport" and DOC.EnsurePassport then DOC.EnsurePassport(target); rec,def=DOC.PhysicalRecord(ownerKey,docType) end
        if not rec and ownerKey==keyOf(target) and docType=="badge" and DOC.EnsureBadge then DOC.EnsureBadge(target); rec,def=DOC.PhysicalRecord(ownerKey,docType) end
        if not rec or not def then return false,"Документ не найден в государственном реестре" end
        local count=copyCount(target,docType,ownerKey)
        if count>=DOC.MaxPhysicalCopies then return false,"Лимит физических копий этого документа: "..DOC.MaxPhysicalCopies end
        if not (GRM.Inventory and GRM.Inventory.AddItem) then return false,"Инвентарь не загружен" end
        local copyID="doc_"..os.time().."_"..math.random(100000,999999)
        local left=GRM.Inventory.AddItem(target,def.item,1,{docType=docType,ownerKey=ownerKey,ownerName=tostring(rec.fullName or rec.businessName or target:Nick()),number=tostring(rec.number or rec.series or ""),copyID=copyID,generation=tonumber(rec.physicalGeneration)or 1,issuedAt=os.time(),issuedBy=IsValid(issuer) and issuer:Nick() or "Система"})
        if left~=0 then return false,"В инвентаре нет свободного места" end
        if GRM.Inventory.SaveNow and not GRM.Inventory.SaveNow("physical document "..copyID)then removeCopyByID(target,copyID);return false,"Не удалось надёжно сохранить физический документ; выдача отменена"end
        if GRM.Notify then GRM.Notify(target,"Получен физический бланк: "..def.name.." (копия "..tostring(count+1).."/"..DOC.MaxPhysicalCopies..")",100,220,140) end
        hook.Run("GRM_DocumentPhysicalIssued",target,docType,ownerKey,copyID,issuer)
        return true,copyID
    end

    --[[ ПОЧЕМУ ВОССТАНОВЛЕНИЕ МОЛЧА ДАВАЛО НОЛЬ (фикс 21.08).
         Меню считало недостающие бланки правильно (4), а восстановление
         возвращало 0 и НЕ показывало причин: команда `all` собирала ошибки
         в таблицу и выбрасывала её. При этом типичная причина — общая:
         хранилище помечено нездоровым (инвентарь или реестр документов
         загрузились из повреждённого файла), и любая запись блокируется.
         Тогда выдача бланка откатывалась, а игрок видел «Восстановлено: 0».

         Теперь причина проверяется ДО выдачи и показывается человеку, а на
         `/docrestore диаг` печатается полная картина по каждому типу. ]]
    function DOC.StorageBlockedReason()
        if GRM.Inventory and GRM.Inventory.PersistenceHealthy then
            local healthy, source = GRM.Inventory.PersistenceHealthy()
            if healthy == false then
                return "Инвентарь загружен из повреждённого файла (" .. tostring(source or "?") ..
                    ") — запись заблокирована. Диагностика: /docrestore диаг"
            end
        end
        if DOC.RegistryHealthy == false then
            return "Реестр документов загружен из повреждённого файла — запись заблокирована. " ..
                "Диагностика: /docrestore диаг"
        end
        return nil
    end

    function DOC.RestorePhysicalDocument(ply,docType,opts)
        if not IsValid(ply)or not ply:IsPlayer()then return false,"Игрок не найден"end
        opts=istable(opts)and opts or{}
        local admin=opts.admin==true
        local blocked=DOC.StorageBlockedReason()
        if blocked then return false,blocked end
        docType=DOC.CanonicalPhysicalType(docType);local ownerKey=keyOf(ply);local rec,def=DOC.PhysicalRecord(ownerKey,docType)
        if not rec or not def then return false,"Документ этого типа не выдавался персонажу"end
        local status=string.lower(tostring(rec.status or"действителен"))
        if not admin and (status:find("аннулир",1,true)or status:find("отозван",1,true))then return false,"Документ аннулирован в реестре"end
        if not admin and copyCount(ply,docType,ownerKey)>0 then return false,"Физический документ уже находится в инвентаре"end
        local now=os.time();local cooldown=6*3600
        if not admin and rec.unlosable~=true and now-(tonumber(rec.lastPhysicalRestore)or 0)<cooldown then return false,"Повторное восстановление будет доступно позже"end
        local oldGeneration=tonumber(rec.physicalGeneration)or 1;rec.physicalGeneration=oldGeneration+1
        if DOC.SaveRegistry and DOC.SaveRegistry("invalidate lost physical copies "..ownerKey.." "..docType)==false then rec.physicalGeneration=oldGeneration;return false,"Реестр документов временно недоступен"end
        local ok,result=DOC.GivePhysicalCopy(ply,docType,ownerKey,ply)
        if not ok then rec.physicalGeneration=oldGeneration;if DOC.SaveRegistry then DOC.SaveRegistry("rollback physical restore")end return false,result end
        rec.lastPhysicalRestore=now;if DOC.SaveRegistry then DOC.SaveRegistry("physical restore "..ownerKey.." "..docType)end
        if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("documents","physical.restore",ply,{characterKey=ownerKey,docType=docType},{copyID=result,generation=rec.physicalGeneration})end
        return true,result
    end

    function DOC.MissingPhysicalTypes(ply)
        local ownerKey=keyOf(ply);local out={}
        for typ in pairs(DOC.PhysicalDefs)do local rec=DOC.PhysicalRecord(ownerKey,typ);if rec and copyCount(ply,typ,ownerKey)==0 then local status=string.lower(tostring(rec.status or"действителен"));if not status:find("аннулир",1,true)and not status:find("отозван",1,true)then out[#out+1]=typ end end end
        table.sort(out);return out
    end
    local function notifyMissing(ply)
        if not IsValid(ply)then return end;local key=keyOf(ply);local missing=DOC.MissingPhysicalTypes(ply);if #missing<1 then return end
        DOC._missingTold=DOC._missingTold or{};if DOC._missingTold[key]then return end;DOC._missingTold[key]=true
        if GRM.Notify then GRM.Notify(ply,"В реестре есть документы без физического бланка. Восстановление: /docrestore all",255,190,90)else ply:ChatPrint("[Документы] Восстановление физических бланков: /docrestore all")end
    end
    hook.Add("GRM_CharacterChanged","GRM_PhysicalDocs_Missing",function(ply)timer.Simple(3,function()notifyMissing(ply)end)end)
    hook.Add("PlayerInitialSpawn","GRM_PhysicalDocs_MissingJoin",function(ply)timer.Simple(8,function()notifyMissing(ply)end)end)

    --- Полная картина по восстановлению: что мешает и по какому типу.
    function DOC.PrintRestoreDiag(ply)
        if not IsValid(ply) then return end
        local ownerKey=keyOf(ply)
        local function out(line) ply:ChatPrint("[Документы] "..tostring(line)) end

        out("Диагностика восстановления бланков, персонаж "..ownerKey)
        local blocked=DOC.StorageBlockedReason()
        out("Хранилище: "..(blocked and ("ЗАБЛОКИРОВАНО — "..blocked) or "в порядке"))

        if GRM.Inventory and GRM.Inventory.GetPlayerInv then
            local inv=GRM.Inventory.GetPlayerInv(ply)
            local used=0
            for _,slot in pairs(istable(inv) and inv.slots or {}) do
                if istable(slot) and slot.id then used=used+1 end
            end
            local maxSlots=(GRM.Inventory.Config and GRM.Inventory.Config.MaxSlots) or 0
            out(("Инвентарь: занято слотов %d из %d"):format(used,maxSlots))
        else
            out("Инвентарь: модуль не загружен")
        end

        local now=os.time()
        for typ,def in pairs(DOC.PhysicalDefs) do
            local rec=DOC.PhysicalRecord(ownerKey,typ)
            if not rec then
                out(("  %-16s записи в реестре нет"):format(typ))
            else
                local copies=copyCount(ply,typ,ownerKey)
                local status=tostring(rec.status or "действителен")
                local left=math.max(0,(6*3600)-(now-(tonumber(rec.lastPhysicalRestore) or 0)))
                out(("  %-16s копий %d · статус «%s»%s"):format(typ,copies,status,
                    left>0 and (" · повтор через "..math.ceil(left/60).." мин.") or ""))
            end
        end
        out("Выдать один бланк: /docrestore <тип>. Все: /docrestore all")
    end

    local function findOnlineByKey(ownerKey)
        for _,p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do if keyOf(p)==ownerKey then return p end end
    end

    local function handleCopyCommand(ply,text)
        local raw=string.Trim(tostring(text or "")); local low=string.lower(raw)
        if low~="/doccopy" and string.sub(low,1,9)~="/doccopy " then return false end
        local arg=string.Trim(string.sub(raw,9)); if arg=="" then ply:ChatPrint("[Документы] /doccopy passport|badge|military|license|milLicense|weaponLicense|businessLicense") return true end
        local ok,msg=DOC.GivePhysicalCopy(ply,arg,keyOf(ply),ply)
        if not ok and GRM.Notify then GRM.Notify(ply,msg,255,140,110) end
        return true
    end
    local function handleRestoreCommand(ply,text)
        local raw=string.Trim(tostring(text or""));local low=string.lower(raw);local arg
        if low=="/docrestore"then arg=""elseif low:sub(1,12)=="/docrestore "then arg=string.Trim(raw:sub(13))else return false end;if arg==""then ply:ChatPrint("[Документы] /docrestore passport|badge|military|license|milLicense|weaponLicense|businessLicense|all|диаг")return true end
        if string.lower(arg)=="диаг" or string.lower(arg)=="diag" then DOC.PrintRestoreDiag(ply) return true end
        if string.lower(arg)=="all"then
            local restored,errors,tried=0,{},0
            for typ in pairs(DOC.PhysicalDefs)do
                local rec=DOC.PhysicalRecord(keyOf(ply),typ)
                if rec and copyCount(ply,typ,keyOf(ply))==0 then
                    tried=tried+1
                    local ok,msg=DOC.RestorePhysicalDocument(ply,typ)
                    if ok then restored=restored+1
                    else
                        local text=tostring(msg or "неизвестная причина")
                        errors[text]=(errors[text] or 0)+1
                    end
                end
            end
            if GRM.Notify then
                GRM.Notify(ply,"Восстановлено бланков: "..restored.." из "..tried,
                    restored>0 and 100 or 255,restored>0 and 220 or 150,120)
            end
            -- Молчаливого нуля больше нет: причины уходят в чат.
            for text,count in pairs(errors) do
                ply:ChatPrint("[Документы] Не восстановлено ("..count.."): "..text)
            end
            if restored==0 and tried>0 then
                ply:ChatPrint("[Документы] Подробности: /docrestore диаг")
            end
            return true
        end
        local ok,msg=DOC.RestorePhysicalDocument(ply,arg);if GRM.Notify then GRM.Notify(ply,ok and"Физический документ восстановлен."or tostring(msg),ok and 100 or 255,ok and 220 or 140,ok and 130 or 110)end return true
    end
    hook.Add("PlayerSay", "GRM_PhysicalDocs_Transform", function(ply, text, teamSays)
        local data = { tostring(text or ""), SkipPlayerSay = false }
            if istable(data)and isstring(data[1])and(handleCopyCommand(ply,data[1])or handleRestoreCommand(ply,data[1]))then data[1]="";data.SkipPlayerSay=true end
        if data.SkipPlayerSay == true then return "" end
    end)
    hook.Add("PlayerSay","GRM_PhysicalDocs_Chat",function(ply,text)if handleCopyCommand(ply,text)or handleRestoreCommand(ply,text)then return""end end)

    registerItems(); timer.Simple(2,registerItems); timer.Simple(6,registerItems)
end

if CLIENT then
    registerItems()
    timer.Simple(2,registerItems)
end

print("[GRM Physical Documents] v"..DOC.PhysicalVersion.." loaded")

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/doccopy", "/docrestore" })
end
