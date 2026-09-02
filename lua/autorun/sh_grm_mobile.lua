--[[--------------------------------------------------------------------
    GRM Mobile UI v3.0 / protocol v1.2.2
    Полноценная телефония с разными корпусами интерфейса:
      • кнопочные Badger — LCD, навигационная клавиша и физическая клавиатура;
      • The Lost Flip — отдельный раскладной корпус;
      • Touch/Whiz/Tinkle — смартфон с сеткой приложений и touch hitboxes.
    Серверный контракт звонков/SMS/контактов/заметок/биржи/фракции/форума
    сохранён совместимым с v1.2.2.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Mobile = GRM.Mobile or {}
local MB = GRM.Mobile

MB.DataFile = "grm_mobile.json"
MB.ForumFile = "grm_mobile_forum.json"
MB.SmsCap = 40
MB.ContactsCap = 50
MB.NotesCap = 30
MB.Version = "1.2.2" -- network/data compatibility
MB.UIVersion = "3.6.0"

MB.Tiers = {
    crappy = {
        item = "mobile_crappy",
        name = "Badger Crappy",
        model = "models/ivancorn/gtaiv/electrical/phones/cellphone_badger_crappy.mdl",
        price = 700,
        desc = "Дешёвая трубка. Только звонки.",
        sms = false, contacts = false, notes = false, apps = false, minQ = 0.35, ui = "feature",
    },
    badger = {
        item = "mobile_badger",
        name = "Badger Classic",
        model = "models/ivancorn/gtaiv/electrical/phones/cellphone_badger.mdl",
        price = 1800,
        desc = "Рабочая лошадка: звонки, SMS, контакты.",
        sms = true, contacts = true, notes = false, apps = false, minQ = 0.30, ui = "feature",
    },
    badger_touch = {
        item = "mobile_badger_touch",
        name = "Badger Touch",
        model = "models/ivancorn/gtaiv/electrical/phones/phone_mobile_badger_touchscreen.mdl",
        price = 3500,
        desc = "Сенсорный Badger: SMS, контакты, заметки.",
        sms = true, contacts = true, notes = true, apps = false, minQ = 0.25, ui = "touch",
    },
    lost = {
        item = "mobile_lost",
        name = "The Lost Flip",
        model = "models/ivancorn/gtaiv/electrical/phones/cellphone_thelostdamned.mdl",
        price = 4200,
        desc = "Байкерская раскладушка: SMS, контакты, заметки.",
        sms = true, contacts = true, notes = true, apps = false, minQ = 0.22, ui = "flip",
    },
    tinkle = {
        item = "mobile_tinkle",
        name = "Panoramic Tinkle",
        model = "models/ivancorn/gtaiv/electrical/phones/cellphone_panoramic_tinkle.mdl",
        price = 6500,
        desc = "Смартфон: базовые приложения, биржа, фракция, форум.",
        sms = true, contacts = true, notes = true, apps = true, minQ = 0.18, ui = "smartphone",
    },
    whiz_high = {
        item = "mobile_whiz_high",
        name = "Whiz Highspeed",
        model = "models/ivancorn/gtaiv/electrical/phones/cellphone_whiz_highspeed.mdl",
        price = 9000,
        desc = "Флагман Whiz: уверенный приём и все приложения.",
        sms = true, contacts = true, notes = true, apps = true, minQ = 0.14, ui = "smartphone",
    },
    whiz_gold = {
        item = "mobile_whiz_gold",
        name = "Whiz Gold",
        model = "models/ivancorn/gtaiv/electrical/phones/cellphone_whiz_gold.mdl",
        price = 14000,
        desc = "Золотой Whiz: статус и лучший приёмник в городе.",
        sms = true, contacts = true, notes = true, apps = true, minQ = 0.10, ui = "smartphone",
    },
}

MB.Order = { "crappy", "badger", "badger_touch", "lost", "tinkle", "whiz_high", "whiz_gold" }
local TierOrder = MB.Order
MB.TierOrder = TierOrder
MB.ItemTier = MB.ItemTier or {}
for _, key in ipairs(TierOrder) do
    if MB.Tiers[key] and MB.Tiers[key].item then MB.ItemTier[MB.Tiers[key].item] = key end
end
-- Legacy aliases from earlier broken/short mobile snapshots: if such item is already
-- in a player's inventory, still treat it as a real phone instead of saying "buy one".
MB.ItemTier.mobile_touch = MB.ItemTier.mobile_touch or "badger_touch"
MB.ItemTier.mobile_smartphone = MB.ItemTier.mobile_smartphone or "tinkle"
MB.Lines = MB.Lines or {}
MB.Data = MB.Data or {}

function MB.Key(value)
    if IsValid(value) and value:IsPlayer() then
        if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(value) end
        return tostring(value:SteamID64() or "")
    end
    local raw = tostring(value or "")
    if raw:match(":char[1-3]$") then return raw end
    if raw:match("^%d+$") then return raw .. ":char1" end
    if util.SteamIDTo64 then
        local s64 = util.SteamIDTo64(raw)
        if s64 and s64 ~= "0" then return tostring(s64) .. ":char1" end
    end
    return raw
end

MB.Forum = MB.Forum or { posts = {}, nextID = 1 }
MB.Forum.posts = MB.Forum.posts or {}
MB.Forum.nextID = math.max(1, math.floor(tonumber(MB.Forum.nextID) or 1))
MB.ForumCap = MB.ForumCap or 120

local function forumPostByID(id)
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return nil end
    for _, post in ipairs(MB.Forum.posts) do
        if math.floor(tonumber(post.id) or 0) == id then return post end
    end
    return nil
end

local function normalizeForumPosts()
    local used, highest = {}, 0
    for _, post in ipairs(MB.Forum.posts) do
        if istable(post) then
            local id = math.floor(tonumber(post.id) or 0)
            if id <= 0 or used[id] then
                id = math.max(MB.Forum.nextID, highest + 1)
                while used[id] do id = id + 1 end
            end
            post.id = id
            post.likes = istable(post.likes) and post.likes or {}
            used[id], highest = true, math.max(highest, id)
        end
    end
    MB.Forum.nextID = math.max(MB.Forum.nextID, highest + 1)
end
normalizeForumPosts()

--[[ РЕЕСТР ПРИЛОЖЕНИЙ ТЕЛЕФОНА — единственный источник (ГРМ §5.4).
     Одна строка описывает: подпись, экран открытия, запрос данных при
     входе, фильтр по флагу тарифа. Раньше гейтинг был переписан трижды —
     в AvailableApps (описание тарифа), в appList (домашний экран) и
     лестницей из 11 веток в обработчике нажатия; новое приложение
     требовало синхронно править все три. Порядок списка = порядок иконок
     на домашнем экране. `homeOnly` — пункт интерфейса, не «приложение»:
     в описании тарифа не показывается. ]]
MB.AppDefs = {
    { id = "dial",     name = "Телефон",      screen = "dial" },
    { id = "sms",      name = "SMS",          tier = "sms",      screen = "sms",     query = "sms_read" },
    { id = "contacts", name = "Контакты",     tier = "contacts", screen = "contacts" },
    { id = "notes",    name = "Заметки",      tier = "notes",    screen = "notes",   query = "note_query" },
    { id = "jobs",     name = "Биржа",        tier = "apps",     screen = "jobs",    query = "jobs_query" },
    { id = "fac",      name = "Моя фракция",  tier = "apps",     screen = "fac",     query = "fac_query" },
    { id = "gps",      name = "GPS",          tier = "apps",     screen = "gps" },
    { id = "forum",    name = "Форум",        tier = "apps",     screen = "forum",   query = "forum_query" },
    { id = "taxi",     name = "Такси",        screen = "taxi",   query = "taxi_query" },
    { id = "calc",     name = "Калькулятор",  screen = "calc" },
    { id = "power",    name = "Управление",   screen = "power",  homeOnly = true },
}

-- Приложения тарифа: def допускается, если флага нет вовсе или он включён.
local function appAllowed(def, tier)
    if not def.tier then return true end
    return tier ~= nil and tier[def.tier] == true
end

function MB.AvailableApps(tierKey)
    local tier = MB.Tiers[tostring(tierKey or "")]
    local apps = {}
    for _, d in ipairs(MB.AppDefs) do
        if not d.homeOnly and appAllowed(d, tier) then apps[#apps + 1] = d.name end
    end
    return apps
end

function MB.GenerateNumber()
    return tostring(math.random(10000, 99999))
end

function MB.GetTierByItem(itemID)
    itemID = tostring(itemID or "")
    for _, key in ipairs(TierOrder) do
        local tier = MB.Tiers[key]
        if tier and tier.item == itemID then return tier, key end
    end
    return nil
end

function MB.IsMobileItem(itemID)
    return (MB.ItemTier or {})[tostring(itemID or "")] ~= nil
end

-- Форвард-декларация: tierRank объявлена ниже, но используется в этой
-- функции. Без неё замыкание читало глобал (nil) и подсчёт чипов падал.
local tierRank
function MB.InventoryMobileStats(ply)
    local total, active, bestActive = 0, 0, nil
    if not (IsValid(ply) and GRM.Inventory and GRM.Inventory.GetPlayerInv) then return total, active, bestActive end
    local inv = GRM.Inventory.GetPlayerInv(ply)
    if not (istable(inv) and istable(inv.slots)) then return total, active, bestActive end
    local bestRank = 0
    for _, slot in pairs(inv.slots) do
        if istable(slot) then
            local key = (MB.ItemTier or {})[tostring(slot.id or "")]
            if key then
                total = total + (tonumber(slot.count) or 1)
                local data = istable(slot.data) and slot.data or nil
                if data and data.active == true then
                    active = active + 1
                    local r = tierRank(key)
                    if r > bestRank then bestActive, bestRank = key, r end
                end
            end
        end
    end
    return total, active, bestActive
end

tierRank = function(key)
    for i, k in ipairs(TierOrder) do if k == key then return i end end
    return 0
end

function MB.CarriedTier(ply)
    if not (IsValid(ply) and GRM.Inventory) then return nil end

    local best, bestRank = nil, 0
    local sawExplicitInactive = false
    local sawAnyMobile = false

    if GRM.Inventory.GetPlayerInv then
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if istable(inv) and istable(inv.slots) then
            for _, slot in pairs(inv.slots) do
                if istable(slot) then
                    local itemID = tostring(slot.id or "")
                    local key = (MB.ItemTier or {})[itemID]
                    if key then
                        sawAnyMobile = true
                        local data = istable(slot.data) and slot.data or nil
                        if data and data.active == true then
                            local r = tierRank(key)
                            if r > bestRank then best, bestRank = key, r end
                        elseif data and data.active == false then
                            sawExplicitInactive = true
                        end
                    end
                end
            end
        end
    end

    if best then return best end

    -- Legacy compatibility: старые телефоны, купленные ДО флага active, не имеют
    -- slot.data.active вообще. Их считаем активными, но новые покупки из phoneshop
    -- кладутся с active=false и требуют «Использовать».
    if sawAnyMobile and not sawExplicitInactive and GRM.Inventory.GetPlayerInv then
        local inv = GRM.Inventory.GetPlayerInv(ply)
        for _, slot in pairs(inv.slots or {}) do
            local key = istable(slot) and (MB.ItemTier or {})[tostring(slot.id or "")] or nil
            if key then
                local r = tierRank(key)
                if r > bestRank then best, bestRank = key, r end
            end
        end
        if best then return best end
    end

    return nil
end
function MB.SignalOf(ply)
    if not IsValid(ply) then return 0 end
    if not (GRM.RadioNet and GRM.RadioNet.QualityAt) then return 1 end
    local ok, q = pcall(GRM.RadioNet.QualityAt, ply:GetPos())
    if ok then return math.max(0, math.min(1, tonumber(q) or 0)) end
    return 0
end

function MB.SignalOK(ply, tierKey)
    local tier = MB.Tiers[tostring(tierKey or "")]
    if not tier then return false end
    return MB.SignalOf(ply) >= (tonumber(tier.minQ) or 0)
end

function MB.LineOnline(line)
    if not IsValid(line) then return false end
    local owner = line._grmOwner
    local tierKey = owner and MB.CarriedTier(owner) or line._grmTier
    if not tierKey then return false end
    return MB.SignalOK(owner, tierKey)
end

function MB.CanUseLine(ply, line)
    return IsValid(ply) and IsValid(line) and line._grmOwner == ply and MB.CarriedTier(ply) ~= nil
end

function MB.EnsureData(ply)
    if not IsValid(ply) then return nil end
    local sid = MB.Key(ply)
    MB.Data[sid] = MB.Data[sid] or { contacts = {}, sms = {}, notes = {}, number = MB.GenerateNumber() }
    local d = MB.Data[sid]
    d.contacts = istable(d.contacts) and d.contacts or {}
    d.sms = istable(d.sms) and d.sms or {}
    d.notes = istable(d.notes) and d.notes or {}
    d.number = tostring(d.number or "")
    if #d.number ~= 5 then d.number = MB.GenerateNumber() end
    return d
end

function MB.RemoveLine(plyOrSid)
    local sid = MB.Key(plyOrSid)
    if not sid then return end
    local line = MB.Lines[sid]
    if IsValid(line) then line:Remove() end
    MB.Lines[sid] = nil
end

function MB.EnsureLine(ply)
    if not IsValid(ply) then return nil end
    local tierKey = MB.CarriedTier(ply)
    if not tierKey then
        MB.RemoveLine(ply)
        return nil
    end

    local sid = MB.Key(ply)
    local data = MB.EnsureData(ply)
    local line = MB.Lines[sid]

    if not IsValid(line) then
        line = ents.Create("grm_mobile_line")
        if not IsValid(line) then return nil end
        MB.Lines[sid] = line
        line._grmOwner = ply
        line._grmTier = tierKey
        line.IsMobile = true
        if line.SetOwnerSID64 then line:SetOwnerSID64(sid) end
        if line.SetPhoneNumber then line:SetPhoneNumber(data.number) end
        if line.SetDisplayName then line:SetDisplayName(ply:Nick()) end
        if line.SetExchangeID then line:SetExchangeID("cell") end
        if line.SetLineState then line:SetLineState("idle") end
        if line.SetCallID then line:SetCallID(0) end
        if line.SetPos then line:SetPos(ply:GetPos()) end
        if line.Spawn then line:Spawn() end
        if line.Activate then line:Activate() end
    end

    line._grmOwner = ply
    line._grmTier = tierKey
    if line.SetPos then line:SetPos(ply:GetPos()) end
    if line.GetExchangeID and line.SetExchangeID and line:GetExchangeID() == "" then line:SetExchangeID("cell") end
    if line.GetLineState and line.SetLineState and line:GetLineState() == "" then line:SetLineState("idle") end
    if line.GetPhoneNumber and line.SetPhoneNumber and line:GetPhoneNumber() == "" then line:SetPhoneNumber(data.number) end
    return line
end

function MB.Think()
    local list = player.GetAll and player.GetAll() or {}
    local seen = {}
    for _, ply in ipairs(list) do
        if IsValid(ply) then
            local sid = MB.Key(ply)
            seen[sid] = true
            local line = MB.EnsureLine(ply)
            if ply._grmMobUI and CurTime() - ply._grmMobUI > 3 then
                ply._grmMobUI = nil
                ply:SetNWString("GRM_MobHold", "")
            end
            if ply._grmMobUI then
                local lastPush = tonumber(ply._grmMobDataTs) or -999
                if CurTime() - lastPush >= 3 then
                    MB.PushAllData(ply)
                    ply._grmMobDataTs = CurTime()
                end
            end
            if IsValid(line) and line.GetLineState and line:GetLineState() ~= "idle" and not MB.LineOnline(line) then
                local call = nil
                if GRM.Phone and GRM.Phone.Calls and line.GetCallID then
                    call = GRM.Phone.Calls[line:GetCallID()]
                end
                if GRM.Phone and GRM.Phone.ForceEndCall and call then
                    GRM.Phone.ForceEndCall(call, "mobile signal lost")
                elseif line.SetLineState then
                    line:SetLineState("idle")
                    if line.SetCallID then line:SetCallID(0) end
                end
                if MB.ServerNotify then MB.ServerNotify(ply, "Разговор завершён: потерян сигнал сотовой связи.") end
            end
        end
    end
    for sid, line in pairs(MB.Lines or {}) do
        if not seen[sid] then
            if IsValid(line) then line:Remove() end
            MB.Lines[sid] = nil
        end
    end
end

function MB.Dial(ply, number)
    if not (GRM.Phone and GRM.Phone.Dial) then
        if MB.ServerNotify then MB.ServerNotify(ply, "Телефонное ядро ещё не загружено.") end
        return false
    end
    local line = MB.EnsureLine(ply)
    if not IsValid(line) then
        if MB.ServerNotify then MB.ServerNotify(ply, "У вас нет активной мобильной линии.") end
        return false
    end
    GRM.Phone.Dial(ply, line, tostring(number or ""))
    return true
end

function MB.Answer(ply)
    if not (GRM.Phone and GRM.Phone.Answer) then return false end
    local line = MB.EnsureLine(ply)
    if not IsValid(line) then return false end
    GRM.Phone.Answer(ply, line)
    return true
end

function MB.Hangup(ply)
    if not (GRM.Phone and GRM.Phone.Hangup) then return false end
    local sid = IsValid(ply) and MB.Key(ply) or nil
    local line = sid and MB.Lines[sid] or nil
    if not IsValid(line) then return false end
    GRM.Phone.Hangup(ply, line)
    return true
end

function MB.FindLineByNumber(num)
    num = tostring(num or "")
    for _, line in pairs(MB.Lines or {}) do
        if IsValid(line) and line.GetPhoneNumber and line:GetPhoneNumber() == num then return line end
    end
    return nil
end

local function ownerOfLine(line)
    return IsValid(line) and line._grmOwner or nil
end

function MB.UnreadCount(ply)
    local d = MB.EnsureData(ply)
    local n = 0
    for _, msg in ipairs(d and d.sms or {}) do
        if msg.dir == "in" and msg.read ~= true then n = n + 1 end
    end
    return n
end

function MB.PushState(ply)
    if not IsValid(ply) then return end
    local tierKey = MB.CarriedTier(ply)
    local data = MB.EnsureData(ply)
    local line = tierKey and MB.EnsureLine(ply) or nil
    local other = IsValid(line) and line.GetOtherPhone and line:GetOtherPhone() or nil
    net.Start("GRM_Mob_State")
        net.WriteTable({
            tier = tierKey or "",
            number = data and data.number or "",
            signal = MB.SignalOf(ply),
            bars = math.max(0, math.min(4, math.ceil(MB.SignalOf(ply) * 4))),
            operator = "GRM CELL",
            modelName = tierKey and MB.Tiers[tierKey] and MB.Tiers[tierKey].name or "",
            formFactor = tierKey and MB.Tiers[tierKey] and MB.Tiers[tierKey].ui or "feature",
            unread = MB.UnreadCount(ply),
            apps = MB.AvailableApps(tierKey or ""),
            has = tierKey ~= nil,
            active = tierKey ~= nil,
            lineState = IsValid(line) and line.GetLineState and line:GetLineState() or "idle",
            otherNumber = IsValid(other) and other.GetPhoneNumber and other:GetPhoneNumber() or "",
            otherName = IsValid(other) and other.GetDisplayName and other:GetDisplayName() or "",
        })
    net.Send(ply)
end

function MB.PushData(ply, kind)
    if not IsValid(ply) then return end
    kind = tostring(kind or "")
    local d = MB.EnsureData(ply)
    local payload = { rows = {} }

    if kind == "contacts" then
        for i, r in ipairs(d.contacts or {}) do
            payload.rows[#payload.rows + 1] = { i = i, name = r.name, num = r.num }
        end
    elseif kind == "sms" then
        for i, r in ipairs(d.sms or {}) do
            local row = table.Copy(r)
            row.i = i
            payload.rows[#payload.rows + 1] = row
        end
    elseif kind == "notes" then
        for i, r in ipairs(d.notes or {}) do
            payload.rows[#payload.rows + 1] = { i = i, text = r.text, ts = r.ts or r.time }
        end
    elseif kind=="taxi"then
        payload.data=GRM.Jobs and GRM.Jobs.TaxiStatus and GRM.Jobs.TaxiStatus(ply)or nil
    elseif kind == "forum" then
        normalizeForumPosts()
        local key = MB.Key(ply)
        local replyCounts = {}
        for _, post in ipairs(MB.Forum.posts) do
            local parent = math.floor(tonumber(post.replyTo) or 0)
            if parent > 0 then replyCounts[parent] = (replyCounts[parent] or 0) + 1 end
        end
        for i = 1, math.min(40, #MB.Forum.posts) do
            local post = MB.Forum.posts[i]
            local liked = false
            for _, liker in ipairs(post.likes or {}) do if tostring(liker) == key then liked = true break end end
            payload.rows[i] = {
                id = post.id,
                author = tostring(post.author or "Горожанин"),
                text = tostring(post.text or ""),
                time = tonumber(post.time or post.ts) or 0,
                likes = #(post.likes or {}),
                liked = liked,
                replies = replyCounts[post.id] or 0,
                replyTo = math.floor(tonumber(post.replyTo) or 0),
                replyAuthor = tostring(post.replyAuthor or ""),
                mine = tostring(post.authorKey or "") == key,
            }
        end
    else
        return
    end

    net.Start("GRM_Mob_Data")
        net.WriteString(kind)
        net.WriteTable(payload)
    net.Send(ply)
end

function MB.PushAllData(ply)
    MB.PushData(ply, "contacts")
    MB.PushData(ply, "sms")
    MB.PushData(ply,"notes");MB.PushData(ply,"taxi");MB.PushData(ply,"forum")
end

function MB.SendSms(ply, num, text)
    if not IsValid(ply) then return false end
    local tierKey = MB.CarriedTier(ply)
    local tier = tierKey and MB.Tiers[tierKey] or nil
    if not (tier and tier.sms) then
        if MB.ServerNotify then MB.ServerNotify(ply, "Ваш телефон не умеет SMS.") end
        return false
    end
    local targetLine = MB.FindLineByNumber(num)
    local target = ownerOfLine(targetLine)
    if not IsValid(target) then
        if MB.ServerNotify then MB.ServerNotify(ply, "Номер не обслуживается.") end
        return false
    end
    local fromData = MB.EnsureData(ply)
    local toData = MB.EnsureData(target)
    text = tostring(text or ""):sub(1, 500)
    if text == "" then return false end
    local now = os.time()
    toData.sms[#toData.sms + 1] = { dir = "in", from = fromData.number, num = fromData.number, text = text, time = now, read = false }
    fromData.sms[#fromData.sms + 1] = { dir = "out", to = tostring(num or ""), num = tostring(num or ""), text = text, time = now, read = true }
    return true
end

local function sortContacts(d)
    table.sort(d.contacts, function(a, b) return tostring(a.name or "") < tostring(b.name or "") end)
end

function MB.HandleAction(ply, act)
    if not IsValid(ply) then return end
    act = istable(act) and act or {}
    local op = tostring(act.op or "")
    local tierKey = MB.CarriedTier(ply)
    local tier = tierKey and MB.Tiers[tierKey] or nil
    local d = MB.EnsureData(ply)

    if op == "open" or op == "ping" then
        ply._grmMobUI = CurTime()
        local mdl = (tier and tier.model) or ""
        ply:SetNWString("GRM_MobHold", mdl)
        MB.PushState(ply)
        if op == "open" then MB.PushAllData(ply) end
        return
    elseif op == "close" then
        ply._grmMobUI = nil
        ply:SetNWString("GRM_MobHold", "")
        return
    elseif op == "sms_read" then
        for _, msg in ipairs(d.sms) do msg.read = true end
        return
    elseif op == "sms" then
        MB.SendSms(ply, act.num, act.text)
        return
    elseif op == "deactivate" then
        ply._grmMobUI = nil
        if GRM.Inventory and GRM.Inventory.GetPlayerInv then
            local inv = GRM.Inventory.GetPlayerInv(ply)
            if istable(inv) and istable(inv.slots) then
                for i, sl in pairs(inv.slots) do
                    if istable(sl) and sl.id and MB.IsMobileItem(sl.id) then
                        sl.data = istable(sl.data) and sl.data or {}
                        sl.data.active = false
                        if GRM.Inventory.SyncSlot then GRM.Inventory.SyncSlot(ply, i) end
                    end
                end
                if GRM.Inventory._devSaveSoon then GRM.Inventory._devSaveSoon("mobile deactivate") end
            end
        end
        MB.RemoveLine(ply)
        MB.PushState(ply)
        if MB.ServerNotify then MB.ServerNotify(ply, "Телефон деактивирован. Активировать — через /inv → Использовать.") end
        return
    elseif op == "contact_add" then
        if not (tier and tier.contacts) then return end
        if #d.contacts >= MB.ContactsCap then return end
        local name = string.Trim(tostring(act.name or "")):sub(1, 48)
        local num = string.Trim(tostring(act.num or "")):sub(1, 16)
        if name ~= "" and num ~= "" then
            d.contacts[#d.contacts + 1] = { name = name, num = num }
            sortContacts(d)
        end
        return
    elseif op == "contact_del" then
        table.remove(d.contacts, math.max(1, math.floor(tonumber(act.i) or 0)))
        return
    elseif op == "note_add" then
        if not (tier and tier.notes) then return end
        if #d.notes >= MB.NotesCap then return end
        local text = string.Trim(tostring(act.text or "")):sub(1, 500)
        if text ~= "" then d.notes[#d.notes + 1] = { text = text, time = os.time() } end
        MB.PushData(ply, "notes")
        return
    elseif op == "note_del" then
        table.remove(d.notes, math.max(1, math.floor(tonumber(act.i) or 0)))
        MB.PushData(ply, "notes")
        return
    elseif op == "note_query" then
        MB.PushData(ply, "notes")
        return
    elseif op == "forum_post" then
        if not (tier and tier.apps) then return end
        local now = os.time()
        if ply._grmMobForumTs and now - ply._grmMobForumTs < 5 then return end
        local text = string.Trim(tostring(act.text or "")):sub(1, 500)
        if text == "" then return end
        normalizeForumPosts()
        local replyTo = math.floor(tonumber(act.replyTo) or 0)
        local parent = replyTo > 0 and forumPostByID(replyTo) or nil
        ply._grmMobForumTs = now
        local id = MB.Forum.nextID
        MB.Forum.nextID = id + 1
        table.insert(MB.Forum.posts, 1, {
            id = id,
            author = ply:Nick(),
            authorKey = MB.Key(ply),
            text = text,
            time = now,
            likes = {},
            replyTo = parent and parent.id or 0,
            replyAuthor = parent and tostring(parent.author or "") or "",
        })
        while #MB.Forum.posts > MB.ForumCap do table.remove(MB.Forum.posts) end
        if MB.SaveForum then MB.SaveForum() end
        MB.PushData(ply, "forum")
        return
    elseif op == "forum_like" then
        if not (tier and tier.apps) then return end
        if ply._grmMobForumLikeTs and CurTime() - ply._grmMobForumLikeTs < 0.35 then return end
        local post = forumPostByID(act.id)
        if not post then return end
        ply._grmMobForumLikeTs = CurTime()
        local key, found = MB.Key(ply), nil
        post.likes = istable(post.likes) and post.likes or {}
        for i, liker in ipairs(post.likes) do if tostring(liker) == key then found = i break end end
        if found then table.remove(post.likes, found) else post.likes[#post.likes + 1] = key end
        if MB.SaveForum then MB.SaveForum() end
        MB.PushData(ply, "forum")
        return
    elseif op == "forum_query" then
        MB.PushData(ply, "forum")
        return
    elseif op=="taxi_call"then
        if not tier then return end;local ok,msg=false,"Модуль такси не загружен";if GRM.Jobs and GRM.Jobs.CallTaxi then ok,msg=GRM.Jobs.CallTaxi(ply,"mobile")end;if not ok and MB.ServerNotify then MB.ServerNotify(ply,tostring(msg or"Не удалось вызвать такси"))end;MB.PushData(ply,"taxi");return
    elseif op=="taxi_cancel"then
        local ok,msg=false,"Модуль такси не загружен";if GRM.Jobs and GRM.Jobs.CancelTaxi then ok,msg=GRM.Jobs.CancelTaxi(ply,"mobile")end;if not ok and MB.ServerNotify then MB.ServerNotify(ply,tostring(msg or"Нет заказа"))end;MB.PushData(ply,"taxi");return
    elseif op=="taxi_query"then MB.PushData(ply,"taxi");return
    elseif op == "jobs_query" then
        local rows = {}
        local posts = GRM.Jobs and GRM.Jobs.Cfg and GRM.Jobs.Cfg.posts or {}
        for fac, list in pairs(posts) do
            if istable(list) then
                for _, job in ipairs(list) do
                    if istable(job) and not job.takenBy then
                        rows[#rows + 1] = {
                            fac = tostring(fac),
                            title = tostring(job.title or ""),
                            kind = tostring(job.kind or ""),
                            reward = tonumber(job.reward or job.salary or 0) or 0,
                            desc = tostring(job.desc or ""),
                        }
                    end
                end
            end
        end
        table.sort(rows, function(a, b)
            if a.fac == b.fac then return a.title < b.title end
            return a.fac < b.fac
        end)
        net.Start("GRM_Mob_Data")
            net.WriteString("jobs")
            net.WriteTable({ rows = rows })
        net.Send(ply)
        return
    elseif op == "fac_query" then
        local sid, sid64 = ply:SteamID(), MB.Key(ply)
        local foundName, found = nil, nil
        for name, fac in pairs(Factions or {}) do
            local member
            if GRM.Identity and GRM.Identity.FactionMember then
                member = GRM.Identity.FactionMember(fac, ply)
            else
                member = istable(fac) and fac.Members and (fac.Members[sid] or fac.Members[sid64])
            end
            if istable(fac) and member then
                foundName, found = tostring(name), fac
                break
            end
        end
        local payload = { data = nil }
        if found then
            local rows, online = {}, 0
            for msid, rec in pairs(found.Members or {}) do
                local oply = player.GetBySteamID64 and player.GetBySteamID64(tostring(msid)) or nil
                if not IsValid(oply) then
                    for _, pp in ipairs(player.GetAll and player.GetAll() or {}) do
                        if IsValid(pp) and (MB.Key(pp) == tostring(msid) or pp:SteamID() == tostring(msid)) then oply = pp break end
                    end
                end
                local isOn = IsValid(oply)
                if isOn then online = online + 1 end
                rows[#rows + 1] = {
                    sid = tostring(msid),
                    name = isOn and oply:Nick() or tostring(msid),
                    role = istable(rec) and tostring(rec.Role or "") or "",
                    dept = istable(rec) and tostring(rec.Department or "") or "",
                    online = isOn,
                    leader = tostring(found.Leader or "") == tostring(msid),
                }
            end
            table.sort(rows, function(a, b)
                if a.online ~= b.online then return a.online end
                if a.leader ~= b.leader then return a.leader end
                return a.name < b.name
            end)
            payload.data = { name = foundName, total = #rows, online = online, rows = rows }
        end
        net.Start("GRM_Mob_Data")
            net.WriteString("fac")
            net.WriteTable(payload)
        net.Send(ply)
        return
    end
end


function MB.ActivateInventoryPhone(ply, slotIdx, slot)
    if not IsValid(ply) then return false end
    if not (GRM.Inventory and GRM.Inventory.GetPlayerInv) then
        if MB.ServerNotify then MB.ServerNotify(ply, "Инвентарь ещё не загружен.") end
        return false
    end

    local inv = GRM.Inventory.GetPlayerInv(ply)
    if not (istable(inv) and istable(inv.slots)) then return false end
    slotIdx = tonumber(slotIdx) or 0
    local changed = false
    local activated = false

    for i, s in pairs(inv.slots) do
        if istable(s) and s.id and MB.IsMobileItem and MB.IsMobileItem(s.id) then
            s.data = istable(s.data) and s.data or {}
            local should = (i == slotIdx)
            if s.data.active ~= should then changed = true end
            s.data.active = should
            if should then activated = true end
            if GRM.Inventory.SyncSlot then GRM.Inventory.SyncSlot(ply, i) end
        end
    end

    -- Fallback if caller passed slot but index comparison failed for any reason.
    if not activated and istable(slot) and slot.id and MB.IsMobileItem and MB.IsMobileItem(slot.id) then
        slot.data = istable(slot.data) and slot.data or {}
        slot.data.active = true
        changed = true
        activated = true
        if slotIdx > 0 and GRM.Inventory.SyncSlot then GRM.Inventory.SyncSlot(ply, slotIdx) end
    end

    if changed then
        if GRM.Inventory._devSaveSoon then
            GRM.Inventory._devSaveSoon("mobile activate")
        elseif GRM.Inventory.SaveSoon then
            GRM.Inventory.SaveSoon("mobile activate")
        end
    end
    if MB.PushState then MB.PushState(ply) end
    if MB.ServerNotify then
        MB.ServerNotify(ply, activated and "Телефон активирован. Открыть — СТРЕЛКА ВВЕРХ, закрыть — СТРЕЛКА ВНИЗ." or "Телефон не найден в инвентаре.")
    end
    return activated
end

if SERVER then
    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    function MB.LoadForum()
        if not file.Exists(MB.ForumFile, "DATA") then return end
        local t = jsonT(file.Read(MB.ForumFile, "DATA") or "")
        if not istable(t) then return end
        local posts = istable(t.posts) and t.posts or t
        local out = {}
        for _, p in ipairs(posts) do
            if istable(p) and tostring(p.text or "") ~= "" then
                out[#out + 1] = {
                    id = math.floor(tonumber(p.id) or 0),
                    author = tostring(p.author or "Горожанин"):sub(1, 64),
                    authorKey = tostring(p.authorKey or ""),
                    text = tostring(p.text or ""):sub(1, 500),
                    time = tonumber(p.time or p.ts) or 0,
                    likes = istable(p.likes) and p.likes or {},
                    replyTo = math.floor(tonumber(p.replyTo) or 0),
                    replyAuthor = tostring(p.replyAuthor or ""),
                }
            end
        end
        MB.Forum.posts = out
        MB.Forum.nextID = math.max(1, math.floor(tonumber(t.nextID) or 1))
        normalizeForumPosts()
    end

    function MB.SaveForum()
        local fn = function()
            local pack = { nextID = MB.Forum.nextID or 1, posts = MB.Forum.posts or {} }
            local ok, txt = pcall(util.TableToJSON, pack, false)
            if ok and txt then file.Write(MB.ForumFile, txt) end
        end
        if GRM.Perf and GRM.Perf.Coalesce then GRM.Perf.Coalesce("grm_mob_forum", 0.6, fn) else fn() end
    end

    util.AddNetworkString("GRM_Mobile_Open")
    util.AddNetworkString("GRM_Mob_State")
    util.AddNetworkString("GRM_Mob_Data")
    util.AddNetworkString("GRM_Mob_Act")

    function MB.ServerNotify(ply, msg)
        if not IsValid(ply) then return end
        if GRM.Notify then
            GRM.Notify(ply, msg, 100, 220, 100)
        elseif ply.ChatPrint then
            ply:ChatPrint("[Телефон] " .. tostring(msg or ""))
        end
    end

    function MB.HasAnyPhone(ply)
        if not (IsValid(ply) and GRM.Inventory) then return false end
        local total = MB.InventoryMobileStats and select(1, MB.InventoryMobileStats(ply)) or 0
        if total > 0 then return true, total end
        if GRM.Inventory.CountItem then
            for itemID in pairs(MB.ItemTier or {}) do
                if (GRM.Inventory.CountItem(ply, itemID) or 0) > 0 then return true, 1 end
            end
        end
        return false, 0
    end

    function MB.HasPhone(ply)
        if not IsValid(ply) then return false end
        if not GRM.Inventory then return false end
        local tierKey = MB.CarriedTier(ply)
        if tierKey then return true, MB.Tiers[tierKey], tierKey end
        return false
    end

    local function registerPhones()
        if not (GRM.Inventory and GRM.Inventory.RegisterItem) then return false end

        for _, key in ipairs(TierOrder) do
            local tier = MB.Tiers[key]
            GRM.Inventory.RegisterItem(tier.item, {
                type = "item",
                name = "Телефон: " .. tier.name,
                desc = tier.desc,
                icon = "icon16/phone.png",
                maxStack = 1,
                weight = 0.35,
                model = tier.model,
                useFunc = "mobile_open",
            })
        end

        if GRM.Inventory.RegisterUseHandler then
            local function activateHandler(ply, slotIdx, slot)
                MB.ActivateInventoryPhone(ply, slotIdx, slot)
            end
            -- mobile_open/mobile_use: ИСПОЛЬЗОВАТЬ = активировать трубку, НЕ открывать UI.
            GRM.Inventory.RegisterUseHandler("mobile_open", activateHandler)
            GRM.Inventory.RegisterUseHandler("mobile_use", activateHandler)
        end

        return true
    end

    function MB.RegisterPhones()
        return registerPhones()
    end

    function MB.AutoActivateBest(ply)
        if not (IsValid(ply) and GRM.Inventory and GRM.Inventory.GetPlayerInv) then return false end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not (istable(inv) and istable(inv.slots)) then return false end
        local bestIdx, bestRank, bestSlot = nil, -1, nil
        for i, slot in pairs(inv.slots) do
            local key = istable(slot) and (MB.ItemTier or {})[tostring(slot.id or "")] or nil
            if key then
                local r = tierRank(key)
                if r > bestRank then bestIdx, bestRank, bestSlot = i, r, slot end
            end
        end
        if not bestIdx then return false end
        return MB.ActivateInventoryPhone(ply, bestIdx, bestSlot) == true
    end

    function MB.Open(ply)
        if not IsValid(ply) then return end
        if not MB.HasPhone(ply) and MB.HasAnyPhone and MB.HasAnyPhone(ply) then
            MB.AutoActivateBest(ply)
        end
        local hasPhone = MB.HasPhone(ply)
        if not hasPhone then
            MB.PushState(ply) -- sends has=false explicitly; client may show throttled hint
            --[[ ВТОРОЙ РУБЕЖ ПРОТИВ СПАМА (жалоба владельца 28.08).

                 Клиент теперь не шлёт запрос без телефона, но полагаться
                 только на него нельзя: открыть телефон можно и командой,
                 и из инвентаря, и чужим кодом через MB.Open. Поэтому
                 сообщение показываем не чаще раза в 8 секунд — иначе
                 чат снова забьётся одинаковыми строками. ]]
            if CurTime() - (ply._grmMobNoPhoneAt or -999) >= 8 then
                ply._grmMobNoPhoneAt = CurTime()
                if MB.HasAnyPhone and MB.HasAnyPhone(ply) then
                    MB.ServerNotify(ply, "Телефон есть в инвентаре. Нажмите «Использовать», чтобы активировать его.")
                else
                    MB.ServerNotify(ply, "У вас нет мобильного телефона. Купите его в /phoneshop.")
                end
            end
            return
        end
        -- Critical: send fresh state BEFORE opening. Without this, the client can still
        -- have startup has=false and will locally say "buy a phone" even though the item
        -- is already in inventory.
        MB.PushState(ply)
        ply._grmMobUI = CurTime()
        local tdef = MB.Tiers[tostring(MB.CarriedTier(ply) or "")]
        ply:SetNWString("GRM_MobHold", (tdef and tdef.model) or "")
        net.Start("GRM_Mobile_Open")
        net.Send(ply)
    end

    MB.LoadForum()
    hook.Add("ShutDown", "GRM_Mob_ForumSave", function()
        if MB.SaveForum then MB.SaveForum() end
    end)

    registerPhones()
    timer.Simple(1, registerPhones)
    timer.Simple(3, registerPhones)
    timer.Simple(6, registerPhones)
    hook.Add("InitPostEntity", "GRM_Mob_RegisterPhones", registerPhones)
    hook.Add("Initialize", "GRM_Mob_RegisterPhones", registerPhones)
    timer.Create("GRM_Mob_Think", 1, 0, function()
        MB.Think()
    end)

    hook.Add("PlayerDisconnected", "GRM_Mobile_RemoveLine", function(ply)
        MB.RemoveLine(ply)
    end)
    hook.Add("PlayerDeath", "GRM_Mobile_DropHold", function(ply)
        if IsValid(ply) then ply:SetNWString("GRM_MobHold", "") ply._grmMobUI = nil end
    end)

    hook.Add("StartCommand", "GRM_Mobile_FreezeOpenUI", function(ply, cmd)
        if not (IsValid(ply) and ply._grmMobUI and CurTime() - ply._grmMobUI <= 3) then return end
        if cmd.ClearMovement then cmd:ClearMovement() end
        if cmd.ClearButtons then cmd:ClearButtons() end
    end)

    net.Receive("GRM_Mobile_Open", function(_, ply)
        MB.Open(ply)
    end)

    net.Receive("GRM_Mob_Act", function(_, ply)
        local act = net.ReadTable() or {}
        local op = tostring(act.op or "")
        if op == "dial" then MB.Dial(ply, act.number or act.num or "") return end
        if op == "answer" then MB.Answer(ply) return end
        if op == "hangup" then MB.Hangup(ply) return end
        MB.HandleAction(ply, act)
    end)

    hook.Add("PlayerSay", "GRM_Mobile_ChatCommand", function(ply, text)
        local cmd = string.lower(string.Trim(text or ""))
        if cmd == "/mobile" or cmd == "!mobile" or cmd == "/phone" or cmd == "/телефон" then
            MB.Open(ply)
            return ""
        end
    end)

    print("[GRM Mobile] v" .. MB.Version .. " loaded (stabilized)")
end


if CLIENT then
    surface.CreateFont("GRMMob_T", { font = "Roboto", size = 24, weight = 800, extended = true })
    surface.CreateFont("GRMMob_B", { font = "Roboto", size = 17, weight = 700, extended = true })
    surface.CreateFont("GRMMob_S", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMMob_XS", { font = "Roboto", size = 11, weight = 400, extended = true })

    local C = {
        shell = Color(12, 15, 22, 252), bg = Color(16, 20, 28, 248), top = Color(12, 15, 22, 248),
        row = Color(22, 28, 38, 242), row2 = Color(28, 36, 48, 245), accent = Color(65, 145, 235),
        text = Color(240, 244, 250), dim = Color(155, 170, 190), green = Color(55, 185, 110), red = Color(225, 70, 70), yellow = Color(245, 195, 65),
        card = Color(22, 28, 38, 246), card2 = Color(28, 36, 48, 246), violet = Color(65, 145, 235)
    }

    local APP_META = {
        dial={icon="icon16/telephone.png",color=Color(60,190,110)}, sms={icon="icon16/email.png",color=Color(65,145,240)},
        contacts={icon="icon16/group.png",color=Color(236,158,67)}, notes={icon="icon16/note.png",color=Color(235,198,76)},
        jobs={icon="icon16/briefcase.png",color=Color(70,174,205)},taxi={icon="icon16/car.png",color=Color(235,175,60)},fac={icon="icon16/shield.png",color=Color(202,83,91)},
        gps={icon="icon16/map.png",color=Color(235,175,60)},
        forum={icon="icon16/comments.png",color=Color(135,105,235)}, calc={icon="icon16/calculator.png",color=Color(90,110,140)},
        power={icon="icon16/disconnect.png",color=Color(190,72,82)},
    }
    local FORM = {
        smartphone={shell=Color(8,11,17),screen=Color(17,24,35),accent=Color(65,145,240)},
        touch={shell=Color(15,18,24),screen=Color(27,34,43),accent=Color(75,175,205)},
        feature={shell=Color(25,29,34),screen=Color(32,48,38),accent=Color(55,95,68)},
        flip={shell=Color(32,30,29),screen=Color(53,48,35),accent=Color(112,82,48)},
    }

    local M = {
        open = false, frame = nil, stateKnown = false, pendingOpen = false, state = { has = false, tier = "", number = "", lineState = "idle", unread = 0, signal = 0 },
        data = {}, screen = "home", sel = 1, listSel = 1, smsThread = nil, smsSel = 1,
        dial = "", calc = "", down = {}, lastTap = {}, hold = {}, nextRepeat = {}, noPhoneAt = -999,
        promptOpen = false, lastSelectAt = -999, lastPointerAt = -999,
        pointerX = -999, pointerY = -999, pointerPulse = nil, pointerPending = false, pointerSerial = 0, hoverAnim = {},
        poll = { up = false, down = false, mouse3 = false }
    }
    MB._devUI = M

    local function safe(obj, name, ...)
        if obj and obj[name] then return obj[name](obj, ...) end
    end
    local function lp() return LocalPlayer and LocalPlayer() or nil end
    local function hasPhone() return M.state and M.state.has ~= false and M.state.tier ~= nil and M.state.tier ~= "" end
    local function tierDef() return MB.Tiers[tostring(M.state.tier or "")] or MB.Tiers.crappy or {} end
    local function formFactor() return tostring(tierDef().ui or "feature") end
    local function smartForm() local f=formFactor();return f=="smartphone" or f=="touch" end
    local function now() return CurTime and CurTime() or 0 end
    --[[ ЗАНЯТ ЛИ ВВОД (жалоба владельца 28.08: «спамится при нажатии
         стрелки... не должно срабатывать когда игрок пишет в чате или
         в консоли»).

         Раньше проверялся только чат. Консоль и игровое меню не
         учитывались вовсе: стрелки в консоли листают историю команд, и
         каждое нажатие уходило в телефон. ]]
    local function chatBusy()
        if M.chatOpen == true then return true end
        if chat and chat.IsChatOpen and chat.IsChatOpen() then return true end
        if gui then
            if gui.IsConsoleVisible and gui.IsConsoleVisible() then return true end
            if gui.IsGameUIVisible and gui.IsGameUIVisible() then return true end
        end
        -- Курсор на экране = игрок в каком-то окне, стрелки принадлежат ему.
        if vgui and vgui.CursorVisible and vgui.CursorVisible() and not M.open then return true end
        return false
    end
    local function textInputActive()
        if chatBusy() then return true end
        local focus = vgui and vgui.GetKeyboardFocus and vgui.GetKeyboardFocus() or nil
        if not IsValid(focus) or focus == M.frame then return false end
        local cls = focus.GetClassName and tostring(focus:GetClassName() or "") or ""
        return cls == "DTextEntry" or cls == "RichText" or focus.IsEditing == true
    end
    local function clamp(v, lo, hi)
        v = tonumber(v) or lo or 0
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    local function snd(kind)
        local map = {
            open = "buttons/button14.wav",
            close = "buttons/button19.wav",
            nav = "buttons/lightswitch2.wav",
            select = "ui/buttonclick.wav",
            back = "ui/buttonclickrelease.wav",
            err = "common/wpn_denyselect.wav",
            ring = "buttons/button17.wav",
            hover = "garrysmod/ui_hover.wav",
        }
        local path = map[kind] or map.select
        if GRM.Sound and GRM.Sound.UI then GRM.Sound.UI(path, kind == "nav" and 0.03 or 0.04)
        elseif surface and surface.PlaySound then surface.PlaySound(path) end
    end

    local function notify(txt)
        if notification and notification.AddLegacy then notification.AddLegacy(tostring(txt or ""), NOTIFY_HINT or 3, 3) end
    end

    local function askString(title, text, default, cb)
        if M.promptOpen then return end
        M.promptOpen = true
        Derma_StringRequest(title, text, default or "", function(value)
            M.promptOpen = false
            if cb then cb(value) end
        end, function()
            M.promptOpen = false
        end)
    end

    local function sendAct(t)
        net.Start("GRM_Mob_Act")
        net.WriteTable(t or {})
        net.SendToServer()
    end
    local function requestServerOpen()
        net.Start("GRM_Mobile_Open")
        net.SendToServer()
    end

    local function appList()
        local tier = MB.Tiers[tostring(M.state.tier or "")] or MB.Tiers.tinkle
        local out = {}
        for _, d in ipairs(MB.AppDefs) do
            if appAllowed(d, tier) then out[#out + 1] = d end
        end
        return out
    end

    local function rows(kind)
        local d = M.data[kind] or {}
        return d.rows or {}
    end
    local function smsThreads()
        local map = {}
        for _, m in ipairs(rows("sms")) do
            local n = tostring(m.num or m.from or m.to or "")
            if n ~= "" then
                local r = map[n] or { num = n, last = "", ts = 0, unread = 0, rows = {} }
                r.rows[#r.rows+1] = m
                r.last = tostring(m.text or r.last or "")
                r.ts = tonumber(m.ts or m.time or r.ts or 0) or 0
                if m.dir == "in" and m.read == false then r.unread = r.unread + 1 end
                map[n] = r
            end
        end
        local out = {}
        for _, r in pairs(map) do table.sort(r.rows, function(a,b) return (tonumber(a.ts or a.time or 0) or 0) < (tonumber(b.ts or b.time or 0) or 0) end); out[#out+1]=r end
        table.sort(out, function(a,b) return (a.ts or 0) > (b.ts or 0) end)
        return out
    end

    local function calcEval(expr)
        expr = tostring(expr or "")
        local a, op, b = expr:match("^%s*(%-?%d+%.?%d*)%s*([%+%-%*/])%s*(%-?%d+%.?%d*)%s*$")
        a, b = tonumber(a), tonumber(b)
        if not a or not b or not op then return expr end
        if op == "+" then return tostring(a + b) end
        if op == "-" then return tostring(a - b) end
        if op == "*" then return tostring(a * b) end
        if op == "/" then return b ~= 0 and tostring(a / b) or "ERR" end
        return expr
    end

    local function goHome()
        M.screen = "home"
        M.sel = 1
        M.listSel = 1
        M.smsThread = nil
        M.contact = nil
    end

    local function setScreen(scr)
        M.screen = scr or "home"
        M.listSel = 1
    end

    local closePhone -- forward declarations: dynamic UI callbacks call these
    local enter
    local back
    local selectCurrent

    -- РЕЕСТР ЭКРАНОВ ТЕЛЕФОНА (ГРМ §5.4): экран описывает только свой
    -- список пунктов. Диспетчеру неизвестный экран = пустой список,
    -- а не расхождение лестницы с правкой; новый экран — одна функция
    -- SCREENS.<имя> здесь, тело screenItems не трогаем.
    local SCREENS = {}

    function SCREENS.home(add)
        for _, a in ipairs(appList()) do
            add(a.name, function()
                -- экран и запрос данных описаны в MB.AppDefs — здесь нет
                -- ветки на приложение и разойтись они не могут
                if a.screen then setScreen(a.screen) end
                if a.query then sendAct({ op = a.query }) end
            end, a.id == "sms" and tonumber(M.state.unread or 0) > 0 and ("Новых: " .. tostring(M.state.unread)) or nil, "app", a.id)
        end
    end

    function SCREENS.power(add)
        add("Убрать телефон", function() closePhone(true) end, "Закрыть интерфейс, оставив телефон активным", "small")
        add("Деактивировать", function() setScreen("deactivate_confirm") end, "Выключить связь до повторной активации через инвентарь", "call_bad")
        add("Главное меню", function() goHome(); snd("back") end, nil, "back")
    end

    function SCREENS.deactivate_confirm(add)
        add("Да, деактивировать", function() sendAct({op="deactivate"}); closePhone(false) end, "Телефон перестанет принимать звонки", "call_bad")
        add("Отмена", function() setScreen("power"); snd("back") end, "Оставить телефон активным", "back")
    end

    function SCREENS.dial(add)
        for _, d in ipairs({"1","2","3","4","5","6","7","8","9"}) do add(d, function() M.dial = (M.dial or "") .. d; snd("select") end, "цифра", "digit") end
        add("←", function() M.dial = string.sub(M.dial or "", 1, math.max(0, #(M.dial or "") - 1)); snd("back") end, "стереть", "digit")
        add("0", function() M.dial = (M.dial or "") .. "0"; snd("select") end, "цифра", "digit")
        add("☎", function() if (M.dial or "") ~= "" then snd("ring"); sendAct({op="dial", number=M.dial}) else snd("err") end end, "позвонить", "call_good")
        add("Очистить", function() M.dial = ""; snd("back") end, nil, "small")
        add("Назад", function() goHome(); snd("back") end, nil, "back")
    end

    function SCREENS.sms(add)
        for threadIndex, th in ipairs(smsThreads()) do add(th.num, function() M.smsThread = th.num;M.smsThreadListSel=threadIndex;setScreen("sms_dialog") end, (th.unread > 0 and ("новых: " .. th.unread .. " • ") or "") .. tostring(th.last or "")) end
        add("Новое SMS", function()
            askString("SMS", "Номер", "", function(num)
                askString("SMS", "Текст", "", function(txt) sendAct({op="sms", num=num, text=txt}) end)
            end)
        end)
        add("Назад", function() goHome(); snd("back") end, nil, "back")
    end

    function SCREENS.sms_dialog(add)
        add("Ответить", function()
            local num = M.smsThread or ""
            askString("SMS", "Текст для " .. num, "", function(txt) sendAct({op="sms", num=num, text=txt}) end)
        end, M.smsThread)
        add("Позвонить", function() if M.smsThread then sendAct({op="dial", number=M.smsThread}) end end)
        add("Назад к SMS", function() setScreen("sms"); snd("back") end, nil, "back")
        add("Главное меню", function() goHome(); snd("back") end, nil, "back")
    end

    function SCREENS.contacts(add)
        for contactIndex, r in ipairs(rows("contacts")) do add(tostring(r.name or r.num or "Контакт"), function() M.contact = r;M.contactListSel=contactIndex;setScreen("contact_actions") end, tostring(r.num or "")) end
        add("Добавить контакт", function()
            askString("Контакт", "Имя", "", function(name)
                askString("Контакт", "Номер", "", function(num) sendAct({op="contact_add", name=name, num=num}) end)
            end)
        end)
        add("Назад", function() goHome(); snd("back") end, nil, "back")
    end

    function SCREENS.contact_actions(add)
        local r = M.contact or {}
        add("Позвонить", function() if r.num then sendAct({op="dial", number=r.num}) end end, tostring(r.num or ""))
        add("SMS", function() askString("SMS", "Текст для " .. tostring(r.num or ""), "", function(txt) sendAct({op="sms", num=r.num or "", text=txt}) end) end)
        add("Удалить", function() if r.i then sendAct({op="contact_del", i=r.i}) end; setScreen("contacts") end, nil, "call_bad")
        add("Назад", function() setScreen("contacts"); snd("back") end, nil, "back")
    end

    function SCREENS.notes(add)
        for _, r in ipairs(rows("notes")) do add(tostring(r.text or "Заметка"), function() end, "заметка") end
        add("Добавить заметку", function() askString("Заметка", "Текст", "", function(txt) sendAct({op="note_add", text=txt}) end) end)
        add("Удалить выбранную", function() sendAct({op="note_del", i=math.max(1, M.listSel)}) end, nil, "call_bad")
        add("Обновить", function() sendAct({op="note_query"}); snd("select") end, nil, "small")
        add("Назад", function() goHome(); snd("back") end, nil, "back")
    end

    function SCREENS.jobs(add)
        for _,r in ipairs(rows("jobs"))do add(tostring(r.fac or"")..": "..tostring(r.title or""),function()end,tostring(r.kind or"").." "..tostring(r.pay or r.reward or""))end;add("Обновить",function()sendAct({op="jobs_query"});snd("select")end,nil,"small");add("Назад",function()goHome();snd("back")end,nil,"back")
    end

    function SCREENS.taxi(add)
        local td=(M.data.taxi or{}).data
        if istable(td)then add("Статус: "..tostring(td.status or"ожидание"),function()end,(td.driverName~=""and("Водитель: "..td.driverName)or"Идёт поиск водителя")..((tonumber(td.fare)or 0)>0 and(" • "..tostring(td.fare))or""));add("Отменить заказ",function()sendAct({op="taxi_cancel"})end,nil,"call_bad")
        else add("ВЫЗВАТЬ ТАКСИ",function()sendAct({op="taxi_call"})end,"Место подачи определяется по вашей текущей позиции","call_good")end
        add("Обновить",function()sendAct({op="taxi_query"});snd("select")end,nil,"small");add("Назад",function()goHome();snd("back")end,nil,"back")
    end

    function SCREENS.fac(add)
        local d = (M.data.fac or {}).data or {}
        for _, r in ipairs(d.rows or {}) do add((r.online and "● " or "○ ") .. tostring(r.name or "?"), function() end, tostring(r.role or "") .. " / " .. tostring(r.dept or "")) end
        add("Обновить", function() sendAct({op="fac_query"}); snd("select") end, nil, "small")
        add("Назад", function() goHome(); snd("back") end, nil, "back")
    end

    function SCREENS.forum(add)
        add("Написать", function() askString("Новая публикация", "Что происходит в городе?", "", function(txt) sendAct({op="forum_post", text=txt}) end) end, nil, "forum_new")
        add("Обновить", function() sendAct({op="forum_query"}); snd("select") end, nil, "forum_refresh")
        add("Назад", function() goHome(); snd("back") end, nil, "forum_back")
        for _, r in ipairs(rows("forum")) do
            add(tostring(r.author or "Горожанин"), function()
                M.forumPost = r
                M.forumPostID = tonumber(r.id) or 0
                M.forumFeedSel = M.listSel
                setScreen("forum_detail")
            end, tostring(r.text or ""), "forum_post", tonumber(r.id) or 0)
        end
    end

    function SCREENS.forum_detail(add)
        local post = M.forumPost or {}
        add(post.liked and "Убрать реакцию" or "Нравится", function()
            if tonumber(post.id) then sendAct({op="forum_like", id=tonumber(post.id)}) end
            post.liked = not post.liked
            post.likes = math.max(0, (tonumber(post.likes) or 0) + (post.liked and 1 or -1))
        end, nil, "forum_like")
        add("Ответить", function()
            askString("Ответ для " .. tostring(post.author or "пользователя"), "Текст ответа", "", function(txt)
                sendAct({op="forum_post", text=txt, replyTo=tonumber(post.id) or 0})
                setScreen("forum")
            end)
        end, nil, "forum_reply")
        add("К ленте", function() setScreen("forum"); snd("back") end, nil, "forum_back")
    end

    function SCREENS.calc(add)
        for _, b in ipairs({"7","8","9","+","4","5","6","-","1","2","3","*","0","/","C","="}) do
            add(b, function()
                if b == "C" then M.calc = ""; snd("back")
                elseif b == "=" then M.calc = calcEval(M.calc); snd("select")
                else M.calc = (M.calc or "") .. b; snd("select") end
            end, nil, (b == "=" and "call_good") or (b == "C" and "call_bad") or "digit")
        end
        add("Назад", function() goHome(); snd("back") end, nil, "back")
    end

    local function screenItems()
        local items = {}
        local function add(label, fn, hint, kind, id) items[#items + 1] = { label = label, fn = fn, hint = hint, kind = kind, id = id } end

        local st = tostring(M.state.lineState or "idle")
        if st == "ringing" then
            add("Ответить", function() sendAct({op="answer"}) end, tostring(M.state.otherName or M.state.otherNumber or ""), "call_good")
            add("Сбросить", function() sendAct({op="hangup"}) end, "входящий вызов", "call_bad")
            add("Назад", function() goHome() end, nil, "back")
            return items
        elseif st == "dialing" or st == "call" then
            add("Сбросить вызов", function() sendAct({op="hangup"}) end, tostring(M.state.otherName or M.state.otherNumber or ""), "call_bad")
            add("Главное меню", function() goHome() end, nil, "back")
            return items
        end

        local build = SCREENS[M.screen]
        if build then build(add) end
        return items
    end

    closePhone = function(send)
        if not M.open then return end
        M.open = false
        M.pointerPending = false
        M.pointerPulse = nil
        M.pointerSerial = (tonumber(M.pointerSerial) or 0) + 1
        if send ~= false then sendAct({ op = "close" }) end
        snd("close")
        if IsValid(M.frame) then safe(M.frame, "SetVisible", false); safe(M.frame, "Remove") end
        M.frame = nil
    end

    local function fitText(text, font, maxWidth)
        text = tostring(text or "")
        if not surface or not surface.SetFont or not surface.GetTextSize then return text end
        surface.SetFont(font)
        if surface.GetTextSize(text) <= maxWidth then return text end
        local suffix = "…"
        while #text > 0 do
            local cut = #text
            while cut > 1 do
                local byte = string.byte(text, cut)
                if not byte or byte < 128 or byte > 191 then break end
                cut = cut - 1
            end
            text = string.sub(text, 1, cut - 1)
            if surface.GetTextSize(text .. suffix) <= maxWidth then return text .. suffix end
        end
        return suffix
    end

    local function pointerFeedback(x, y, w, h, id)
        local over = M.pointerX >= x and M.pointerX <= x + w and M.pointerY >= y and M.pointerY <= y + h
        if over then
            local hid = tostring(M.screen) .. ":" .. tostring(id or "")
            if M._hoverId ~= hid then M._hoverId = hid snd("hover") end
        end
        local key = tostring(M.screen) .. ":" .. tostring(id or "")
        local current = tonumber(M.hoverAnim[key]) or 0
        local speed = math.min(1, (FrameTime and FrameTime() or 0.016) * 14)
        current = current + ((over and 1 or 0) - current) * speed
        if current < 0.01 and not over then current = 0 end
        M.hoverAnim[key] = current
        local pulse = M.pointerPulse
        local pressed = pulse and pulse.screen == M.screen and pulse.id == tostring(id or "") and now() < (pulse.untilAt or 0)
        return current, pressed == true
    end

    local function drawPointerFeedback(radius, x, y, w, h, id)
        local hover, pressed = pointerFeedback(x, y, w, h, id)
        if hover > 0 then
            draw.RoundedBox(radius, x, y, w, h, Color(255, 255, 255, math.floor(24 * hover)))
        end
        if pressed then
            draw.RoundedBox(radius, x + 2, y + 2, math.max(1, w - 4), math.max(1, h - 4), Color(8, 12, 20, 80))
        end
        return hover, pressed
    end

    local function drawEmpty(w, y, title, text)
        draw.RoundedBox(10, 18, y, w - 36, 86, C.card)
        draw.SimpleText(fitText(title, "GRMMob_B", w - 64), "GRMMob_B", w / 2, y + 30, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(fitText(text, "GRMMob_XS", w - 64), "GRMMob_XS", w / 2, y + 56, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local function forumAge(ts)
        local delta = math.max(0, os.time() - (tonumber(ts) or os.time()))
        if delta < 60 then return "сейчас" end
        if delta < 3600 then return math.floor(delta / 60) .. " мин" end
        if delta < 86400 then return math.floor(delta / 3600) .. " ч" end
        return math.floor(delta / 86400) .. " д"
    end

    local function forumInitial(author)
        author = string.Trim(tostring(author or "?"))
        local first = string.byte(author, 1) or 63
        local length = first < 128 and 1 or (first < 224 and 2 or (first < 240 and 3 or 4))
        return string.upper(string.sub(author, 1, length))
    end

    local function wrapForumText(text, font, maxWidth, maxLines)
        text = tostring(text or "")
        surface.SetFont(font)
        local lines, current = {}, ""
        for word in text:gmatch("%S+") do
            local candidate = current == "" and word or (current .. " " .. word)
            if surface.GetTextSize(candidate) <= maxWidth then
                current = candidate
            else
                if current ~= "" then lines[#lines + 1] = current end
                current = fitText(word, font, maxWidth)
                if #lines >= maxLines then break end
            end
        end
        if current ~= "" and #lines < maxLines then lines[#lines + 1] = current end
        if #lines == 0 then lines[1] = "Без текста" end
        if #lines == maxLines and surface.GetTextSize(lines[#lines]) > maxWidth - 12 then lines[#lines] = fitText(lines[#lines], font, maxWidth - 12) end
        return lines
    end

    local function drawForumFeed(w, startY, maxY, items)
        M.listSel = clamp(M.listSel, 1, math.max(1, #items))
        M.hitboxes = {}
        local gap, x = 8, 18
        local widths = { math.floor((w - 52) * .46), math.floor((w - 52) * .30) }
        widths[3] = w - 36 - widths[1] - widths[2] - gap * 2
        local colors = { C.violet, C.row2, Color(65, 72, 88) }
        local icons = { "+  Написать", "↻  Обновить", "‹" }
        for i = 1, 3 do
            local active = M.listSel == i
            draw.RoundedBox(12, x, startY, widths[i], 42, active and colors[i] or C.card2)
            local _, pressed = drawPointerFeedback(12, x, startY, widths[i], 42, i)
            draw.SimpleText(icons[i], i == 3 and "GRMMob_T" or "GRMMob_B", x + widths[i] / 2, startY + 21 + (pressed and 1 or 0), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            M.hitboxes[#M.hitboxes + 1] = { x=x, y=startY, w=widths[i], h=42, index=i }
            x = x + widths[i] + gap
        end

        local posts = math.max(0, #items - 3)
        local y, cardH = startY + 54, 92
        if posts == 0 then
            drawEmpty(w, y, "Пока тихо", "Начните городское обсуждение")
            return
        end
        local visible = math.max(1, math.floor((maxY - y + 8) / (cardH + 8)))
        local selectedPost = M.listSel > 3 and (M.listSel - 3) or 1
        local first = clamp(selectedPost - visible + 1, 1, math.max(1, posts - visible + 1))
        for postIndex = first, math.min(posts, first + visible - 1) do
            local itemIndex, item = postIndex + 3, items[postIndex + 3]
            local post = rows("forum")[postIndex] or {}
            local active = M.listSel == itemIndex
            draw.RoundedBox(14, 18, y, w - 36, cardH, active and Color(54, 48, 92, 250) or C.card)
            drawPointerFeedback(14, 18, y, w - 36, cardH, itemIndex)
            draw.RoundedBox(18, 30, y + 12, 36, 36, active and C.violet or C.row2)
            draw.SimpleText(forumInitial(post.author), "GRMMob_B", 48, y + 30, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(fitText(post.author, "GRMMob_B", w - 180), "GRMMob_B", 78, y + 20, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(forumAge(post.time), "GRMMob_XS", w - 30, y + 20, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            if tostring(post.replyAuthor or "") ~= "" then
                draw.SimpleText("↳ ответ для " .. fitText(post.replyAuthor, "GRMMob_XS", 110), "GRMMob_XS", 78, y + 38, C.violet, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            draw.SimpleText(fitText(post.text, "GRMMob_S", w - 72), "GRMMob_S", 34, y + 60, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText((post.liked and "♥ " or "♡ ") .. tostring(tonumber(post.likes) or 0) .. "    ◌ " .. tostring(tonumber(post.replies) or 0), "GRMMob_XS", w - 30, y + 78, post.liked and Color(245,105,135) or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            M.hitboxes[#M.hitboxes + 1] = { x=18, y=y, w=w-36, h=cardH, index=itemIndex }
            y = y + cardH + 8
        end
    end

    local function drawForumDetail(w, startY, maxY, items)
        M.listSel = clamp(M.listSel, 1, #items)
        M.hitboxes = {}
        local post = M.forumPost or {}
        draw.RoundedBox(16, 18, startY, w - 36, 174, C.card)
        draw.RoundedBox(20, 32, startY + 14, 40, 40, C.violet)
        draw.SimpleText(forumInitial(post.author), "GRMMob_B", 52, startY + 34, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(fitText(post.author, "GRMMob_B", w - 180), "GRMMob_B", 84, startY + 24, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(forumAge(post.time), "GRMMob_XS", w - 32, startY + 24, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        if tostring(post.replyAuthor or "") ~= "" then draw.SimpleText("Ответ для " .. fitText(post.replyAuthor, "GRMMob_XS", 150), "GRMMob_XS", 84, startY + 45, C.violet, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        local lines = wrapForumText(post.text, "GRMMob_S", w - 68, 4)
        for i, line in ipairs(lines) do draw.SimpleText(line, "GRMMob_S", 34, startY + 70 + (i - 1) * 19, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        draw.SimpleText((post.liked and "♥" or "♡") .. "  " .. tostring(tonumber(post.likes) or 0) .. " нравится", "GRMMob_XS", 34, startY + 154, post.liked and Color(245,105,135) or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("◌  " .. tostring(tonumber(post.replies) or 0) .. " ответов", "GRMMob_XS", w - 34, startY + 154, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        local labels = { post.liked and "♥  Убрать" or "♡  Нравится", "↳  Ответить", "‹  К ленте" }
        local colors = { Color(185,70,105), C.violet, C.row2 }
        local y = startY + 186
        for i = 1, 3 do
            if y + 44 > maxY then break end
            local active = M.listSel == i
            draw.RoundedBox(12, 18, y, w - 36, 44, active and colors[i] or C.card2)
            local _, pressed = drawPointerFeedback(12, 18, y, w - 36, 44, i)
            draw.SimpleText(labels[i], "GRMMob_B", w / 2, y + 22 + (pressed and 1 or 0), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            M.hitboxes[#M.hitboxes + 1] = { x=18, y=y, w=w-36, h=44, index=i }
            y = y + 52
        end
    end

    local function facInitial(name)
        name = string.Trim(tostring(name or "?"))
        local first = string.byte(name, 1) or 63
        local length = first < 128 and 1 or (first < 224 and 2 or (first < 240 and 3 or 4))
        return string.upper(string.sub(name, 1, length))
    end

    local function drawFacRoster(w, startY, maxY, items)
        M.listSel = clamp(M.listSel, 1, math.max(1, #items))
        M.hitboxes = {}
        local pack = (M.data.fac or {}).data
        local hasFac = istable(pack)
        local name = hasFac and tostring(pack.name or "Фракция") or "Нет фракции"
        local online = hasFac and (tonumber(pack.online) or 0) or 0
        local total = hasFac and (tonumber(pack.total) or #(pack.rows or {})) or 0
        local members = hasFac and (pack.rows or {}) or {}

        local bannerH = 92
        draw.RoundedBox(16, 18, startY, w - 36, bannerH, Color(42, 28, 36, 250))
        draw.RoundedBox(18, 30, startY + 18, 56, 56, Color(202, 83, 91, 245))
        draw.SimpleText(facInitial(name), "GRMMob_T", 58, startY + 46, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(fitText(name, "GRMMob_B", w - 180), "GRMMob_B", 98, startY + 32, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if hasFac then
            draw.SimpleText("онлайн  " .. tostring(online) .. "  ·  состав  " .. tostring(total), "GRMMob_XS", 98, startY + 56, Color(245, 180, 185), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("вы не состоите в организации", "GRMMob_XS", 98, startY + 56, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local y = startY + bannerH + 10
        local btnW = math.floor((w - 44) / 2)
        local labels = { "↻  Обновить", "‹  Назад" }
        local colors = { Color(72, 48, 56, 250), Color(48, 42, 52, 250) }
        for i = 1, 2 do
            local x = 18 + (i - 1) * (btnW + 8)
            local active = M.listSel == i
            draw.RoundedBox(12, x, y, btnW, 40, active and Color(202, 83, 91, 250) or colors[i])
            local _, pressed = drawPointerFeedback(12, x, y, btnW, 40, i)
            draw.SimpleText(labels[i], "GRMMob_S", x + btnW / 2, y + 20 + (pressed and 1 or 0), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            M.hitboxes[#M.hitboxes + 1] = { x = x, y = y, w = btnW, h = 40, index = i }
        end
        y = y + 52

        if not hasFac then
            drawEmpty(w, y, "Нет фракции", "Вступите в организацию, чтобы видеть состав")
            return
        end
        if #members == 0 then
            drawEmpty(w, y, "Состав пуст", "Обновите список или дождитесь назначения")
            return
        end

        local cardH = 58
        local visible = math.max(1, math.floor((maxY - y + 8) / (cardH + 8)))
        local selectedMember = M.listSel > 2 and (M.listSel - 2) or 1
        local first = clamp(selectedMember - visible + 1, 1, math.max(1, #members - visible + 1))
        for mi = first, math.min(#members, first + visible - 1) do
            local itemIndex = mi + 2
            local rec = members[mi] or {}
            local active = M.listSel == itemIndex
            local on = rec.online == true
            local cardCol = active and Color(78, 38, 46, 250) or (on and Color(28, 36, 42, 246) or Color(22, 24, 30, 246))
            draw.RoundedBox(12, 18, y, w - 36, cardH, cardCol)
            drawPointerFeedback(12, 18, y, w - 36, cardH, itemIndex)
            draw.RoundedBox(14, 30, y + 12, 34, 34, on and Color(55, 185, 110, 230) or Color(70, 76, 86, 230))
            draw.SimpleText(facInitial(rec.name), "GRMMob_B", 47, y + 29, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            local badge = rec.leader and "лидер" or (on and "в сети" or "оффлайн")
            draw.SimpleText(fitText(rec.name, "GRMMob_B", w - 170), "GRMMob_B", 76, y + 20, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(badge, "GRMMob_XS", w - 30, y + 20, rec.leader and C.yellow or (on and C.green or C.dim), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            local role = tostring(rec.role or "")
            local dept = tostring(rec.dept or "")
            local sub = role
            if dept ~= "" then sub = (sub ~= "" and (role .. "  ·  " .. dept) or dept) end
            if sub == "" then sub = "без должности" end
            draw.SimpleText(fitText(sub, "GRMMob_XS", w - 90), "GRMMob_XS", 76, y + 40, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            M.hitboxes[#M.hitboxes + 1] = { x = 18, y = y, w = w - 36, h = cardH, index = itemIndex }
            y = y + cardH + 8
        end
    end

    local function drawGpsRoster(w, startY, maxY, items)
        M.listSel = clamp(M.listSel, 1, math.max(1, #items))
        M.hitboxes = {}
        local y = startY
        for i, it in ipairs(items or {}) do
            local h = 46
            if y + h > maxY then break end
            local active = M.listSel == i
            draw.RoundedBox(10, 18, y, w - 36, h, active and C.yellow or C.card)
            drawPointerFeedback(10, 18, y, w - 36, h, i)
            draw.SimpleText(fitText(it.label, "GRMMob_B", w - 76), "GRMMob_B", 34, y + (it.hint and 18 or h/2), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if it.hint then draw.SimpleText(fitText(it.hint, "GRMMob_XS", w - 76), "GRMMob_XS", 34, y + h - 14, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
            M.hitboxes[#M.hitboxes + 1] = { x=18, y=y, w=w-36, h=h, index=i }
            y = y + h + 8
        end
    end

    local function drawButtonList(w, startY, maxY)
        local items = screenItems()
        if #items == 0 then return end
        local lineState = tostring(M.state.lineState or "idle")
        local callControls = lineState == "ringing" or lineState == "dialing" or lineState == "call"
        if M.screen == "home" and not callControls then M.sel = clamp(M.sel, 1, #items) else M.listSel = clamp(M.listSel, 1, #items) end
        local selected = (M.screen == "home" and not callControls) and M.sel or M.listSel
        M.hitboxes = {}

        if not callControls and M.screen == "forum" then drawForumFeed(w, startY, maxY, items) return end
        if not callControls and M.screen == "forum_detail" then drawForumDetail(w, startY, maxY, items) return end
        if not callControls and M.screen == "fac" then drawFacRoster(w, startY, maxY, items) return end
        if not callControls and M.screen == "gps" then drawGpsRoster(w, startY, maxY, items) return end

        if not callControls and M.screen == "home" and smartForm() then
            local cols,gap=3,10
            local tile=math.floor((w-36-(cols-1)*gap)/cols)
            for i,it in ipairs(items) do
                local col=(i-1)%cols;local row=math.floor((i-1)/cols)
                local x=18+col*(tile+gap);local y=startY+row*(tile+24+gap)
                if y+tile+24>maxY then break end
                local active=i==selected;local meta=APP_META[it.id] or {icon="icon16/power.png",color=C.red}
                draw.RoundedBox(14,x,y,tile,tile,active and meta.color or C.card2)
                local hover,pressed=drawPointerFeedback(14,x,y,tile,tile+24,i)
                local iconSize=36+math.floor(hover*4);local iconShift=pressed and 2 or 0
                surface.SetMaterial(Material(meta.icon,"smooth"));surface.SetDrawColor(255,255,255,math.min(255,(active and 255 or 220)+math.floor(hover*35)));surface.DrawTexturedRect(x+tile/2-iconSize/2,y+tile/2-iconSize/2+iconShift,iconSize,iconSize)
                draw.SimpleText(fitText(it.label,"GRMMob_XS",tile),"GRMMob_XS",x+tile/2,y+tile+12+iconShift,hover>.05 and color_white or C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                if it.id=="sms" and tonumber(M.state.unread or 0)>0 then draw.RoundedBox(9,x+tile-22,y+5,18,18,C.red);draw.SimpleText(tostring(M.state.unread),"GRMMob_XS",x+tile-13,y+14,color_white,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)end
                M.hitboxes[#M.hitboxes+1]={x=x,y=y,w=tile,h=tile+24,index=i}
            end
            return
        end

        if (M.screen == "jobs" and #rows("jobs") == 0) then drawEmpty(w, startY, "Нет объявлений", "Нажмите «Обновить», чтобы проверить биржу"); startY = startY + 98 end
        if (M.screen == "forum" and #rows("forum") == 0) then drawEmpty(w, startY, "Форум пуст", "Создайте первый пост или обновите ленту"); startY = startY + 98 end
        if (M.screen == "contacts" and #rows("contacts") == 0) then drawEmpty(w, startY, "Контактов нет", "Добавьте первый контакт"); startY = startY + 98 end
        if (M.screen == "notes" and #rows("notes") == 0) then drawEmpty(w, startY, "Заметок нет", "Добавьте заметку"); startY = startY + 98 end

        if not callControls and (M.screen == "dial" or M.screen == "calc") then
            local cols = (M.screen == "calc") and 4 or 3
            local gap = 8
            local bw = math.floor((w - 36 - (cols - 1) * gap) / cols)
            local bh = 54
            for i, it in ipairs(items) do
                local col = (i - 1) % cols
                local row = math.floor((i - 1) / cols)
                local x = 18 + col * (bw + gap)
                local y = startY + row * (bh + gap)
                if y + bh > maxY then break end
                local active = i == selected
                local color = active and C.accent or C.card2
                if it.kind == "call_good" then color = active and C.green or Color(38, 78, 55, 245) end
                if it.kind == "call_bad" then color = active and C.red or Color(82, 42, 48, 245) end
                if it.kind == "back" then color = active and C.yellow or Color(74, 62, 34, 245) end
                draw.RoundedBox(10, x, y, bw, bh, color)
                local _,pressed=drawPointerFeedback(10,x,y,bw,bh,i)
                draw.SimpleText(tostring(it.label or ""), (it.kind == "digit" or M.screen == "calc") and "GRMMob_T" or "GRMMob_B", x + bw / 2, y + 24 + (pressed and 1 or 0), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                if it.hint and tostring(it.hint) ~= "" then draw.SimpleText(tostring(it.hint), "GRMMob_XS", x + bw / 2, y + 43, active and Color(245,250,255) or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
                M.hitboxes[#M.hitboxes+1]={x=x,y=y,w=bw,h=bh,index=i}
            end
            return
        end

        local y = startY
        for i, it in ipairs(items) do
            local isAction = it.kind == "small" or it.kind == "back" or it.kind == "call_good" or it.kind == "call_bad"
            local h = isAction and 42 or ((M.screen == "forum" or M.screen == "jobs" or M.screen == "contacts" or M.screen == "notes") and 64 or 46)
            if y + h > maxY then break end
            local active = i == selected
            local color = active and C.accent or (isAction and C.row or C.card)
            if it.kind == "call_good" then color = active and C.green or Color(38, 78, 55, 245) end
            if it.kind == "call_bad" then color = active and C.red or Color(82, 42, 48, 245) end
            if it.kind == "back" then color = active and C.yellow or Color(74, 62, 34, 245) end
            draw.RoundedBox(10, 18, y, w - 36, h, color)
            local hover,pressed=drawPointerFeedback(10,18,y,w-36,h,i)
            draw.SimpleText(fitText(it.label, "GRMMob_B", w - 76), "GRMMob_B", 34 + math.floor(hover*3), y + (it.hint and 20 or h/2) + (pressed and 1 or 0), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if it.hint and tostring(it.hint) ~= "" then draw.SimpleText(fitText(it.hint, "GRMMob_XS", w - 76), "GRMMob_XS", 34, y + h - 18, active and Color(230,240,255) or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
            M.hitboxes[#M.hitboxes+1]={x=18,y=y,w=w-36,h=h,index=i}
            y = y + h + 8
        end
    end

    local function activatePointerBox(box)
        if not box or M.pointerPending then return end
        if now() - (tonumber(M.lastPointerAt) or -999) < 0.18 then return end
        M.lastPointerAt = now()

        local screenAtClick = M.screen
        local pulseID = box.navAction and ("nav:" .. tostring(box.navAction)) or (box.keyValue and ("key:" .. tostring(box.keyValue)) or tostring(box.index or ""))
        M.pointerPulse = { screen=screenAtClick, id=pulseID, untilAt=now()+0.14 }
        M.pointerPending = true
        M.pointerSerial = (tonumber(M.pointerSerial) or 0) + 1
        local clickSerial = M.pointerSerial

        local action
        if box.navAction then
            local navAction = tostring(box.navAction)
            action = function()
                if navAction == "back" then back()
                elseif navAction == "home" then goHome(); snd("back")
                elseif navAction == "close" then closePhone(true) end
            end
        elseif box.keyValue then
            local value = tostring(box.keyValue)
            action = function()
                if value == "OK" then
                    enter()
                elseif tonumber(value) then
                    if M.screen == "dial" then M.dial = (M.dial or "") .. value
                    elseif M.screen == "calc" then M.calc = (M.calc or "") .. value end
                    snd("select")
                end
            end
        else
            -- Capture the item before its callback changes screenItems(). The short
            -- delay leaves one painted frame for a visible press animation.
            local items = screenItems()
            local item = items[box.index]
            if not item or not item.fn then M.pointerPending=false return end
            local st = tostring(M.state.lineState or "idle")
            if M.screen == "home" and st == "idle" then M.sel = box.index else M.listSel = box.index end
            snd("select")
            action = item.fn
        end

        local function finishClick()
            if M.pointerSerial ~= clickSerial then return end
            M.pointerPending = false
            if not M.open or M.screen ~= screenAtClick then return end
            action()
        end
        if timer and timer.Simple then timer.Simple(0.07, finishClick) else finishClick() end
    end

    local function openPhone(force)
        if not hasPhone() then
            requestServerOpen()
            if now() - (M.noPhoneAt or -999) >= 2 then
                M.noPhoneAt = now()
                notify("Нет активного телефона. Купите в /phoneshop или нажмите «Использовать» в инвентаре.")
            end
            return
        end
        if not IsValid(M.frame) then
            local f = vgui.Create("DFrame")
            if not IsValid(f) then return end
            M.frame = f
            safe(f, "SetTitle", "")
            safe(f, "ShowCloseButton", false)
            safe(f, "SetDraggable", false)
            local form=formFactor()
            local baseSize=({smartphone={430,760},touch={410,720},feature={360,700},flip={370,750}})[form] or {360,700}
            local fw,fh=math.min(baseSize[1],ScrW()-50),math.min(baseSize[2],ScrH()-50)
            safe(f, "SetSize", fw, fh)
            if f.SetPos then f:SetPos(ScrW() - fw - 34, ScrH() - fh - 34) end
            safe(f,"SetVisible",true)
            safe(f,"MakePopup")
            f.OnKeyCodePressed=function(_,key)if MB._uiKeyDown then MB._uiKeyDown(key)end end
            f.OnKeyCodeReleased=function(_,key)if MB._uiKeyUp then MB._uiKeyUp(key)end end
            f.OnMousePressed=function(self,key)
                if key~=MOUSE_LEFT then return end
                local sx,sy=gui.MousePos();local fx,fy=self:GetPos();local x,y=sx-fx,sy-fy
                for _,box in ipairs(M.hitboxes or{})do
                    if x>=box.x and x<=box.x+box.w and y>=box.y and y<=box.y+box.h then
                        activatePointerBox(box)
                        return
                    end
                end
            end
            f.Paint = function(self, w, h)
                if self.CursorPos then M.pointerX,M.pointerY=self:CursorPos() else M.pointerX,M.pointerY=-999,-999 end
                local form=formFactor();local palette=FORM[form] or FORM.feature;local smart=smartForm()
                draw.RoundedBox(smart and 28 or 18,0,0,w,h,palette.shell)
                if form=="flip" then draw.RoundedBox(5,10,math.floor(h*.58),w-20,12,Color(12,12,14));surface.SetDrawColor(80,75,70);surface.DrawOutlinedRect(10,math.floor(h*.58),w-20,12,2)end
                local screenBottom=smart and(h-45)or math.floor(h*(form=="flip"and .55 or .58))
                draw.RoundedBox(smart and 22 or 9,10,10,w-20,screenBottom-10,palette.screen)
                draw.RoundedBoxEx(smart and 20 or 8,10,10,w-20,42,palette.accent,true,true,false,false)
                draw.SimpleText(os.date("%H:%M"),"GRMMob_S",22,27,C.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
                draw.SimpleText(tostring(M.state.operator or"GRM"),"GRMMob_XS",w/2,27,C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                local bars=clamp(math.floor(tonumber(M.state.bars)or((tonumber(M.state.signal)or 0)*4)),0,4)
                for i=1,4 do draw.RoundedBox(1,w-70+(i-1)*8,32-i*4,5,4+i*4,i<=bars and C.green or Color(90,100,110))end
                draw.SimpleText(tostring(M.state.modelName or tierDef().name or"GRM Mobile"),"GRMMob_B",20,64,smart and C.text or Color(25,40,28),TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
                draw.SimpleText("№"..tostring(M.state.number or""),"GRMMob_XS",w-20,64,smart and C.dim or Color(45,65,48),TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER)

                local st = tostring(M.state.lineState or "idle")
                if st == "ringing" then
                    draw.RoundedBox(8, 18, 76, w - 36, 44, C.green)
                    draw.SimpleText("Входящий: " .. tostring(M.state.otherName or M.state.otherNumber or ""), "GRMMob_B", w/2, 98, Color(10,20,15), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end

                local callControls = st == "ringing" or st == "dialing" or st == "call"
                local title = ({ home="Главное меню", dial="Набор номера", sms="SMS", sms_dialog="Диалог " .. tostring(M.smsThread or ""), contacts="Контакты", contact_actions="Контакт", notes="Заметки",jobs="Биржа труда",taxi="Вызов такси",fac="Моя фракция", gps="GPS-метки", forum="Городской форум", forum_detail="Публикация", calc="Калькулятор", power="Телефон", deactivate_confirm="Подтверждение" })[M.screen] or M.screen
                if st == "ringing" then title = "Управление вызовом"
                elseif st == "dialing" then title = "Исходящий вызов"
                elseif st == "call" then title = "Разговор" end
                local titleY = st == "ringing" and 142 or 92
                draw.SimpleText(fitText(title, "GRMMob_B", w - 48), "GRMMob_B", 24, titleY, C.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local topY = titleY + 26
                if not callControls and M.screen == "dial" then
                    draw.RoundedBox(8, 18, topY, w - 36, 54, C.row2)
                    draw.SimpleText(fitText(M.dial == "" and "Введите номер" or M.dial, "GRMMob_T", w - 60), "GRMMob_T", w/2, topY + 27, C.green, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    topY = topY + 66
                elseif not callControls and M.screen == "calc" then
                    draw.RoundedBox(8, 18, topY, w - 36, 54, C.row2)
                    draw.SimpleText(fitText(M.calc == "" and "0" or M.calc, "GRMMob_T", w - 60), "GRMMob_T", w/2, topY + 27, C.green, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    topY = topY + 66
                elseif not callControls and M.screen == "sms_dialog" then
                    local y = topY
                    local rr = {}
                    for _, th in ipairs(smsThreads()) do if th.num == M.smsThread then rr = th.rows end end
                    local endIndex=clamp(#rr-(math.max(1,tonumber(M.smsSel)or 1)-1),1,math.max(1,#rr))
                    for i = math.max(1, endIndex - 4), endIndex do
                        local m = rr[i]
                        if m then
                            local out = m.dir == "out"
                            draw.RoundedBox(8, out and w - 250 or 22, y, 228, 28, out and C.accent or C.row2)
                            draw.SimpleText(fitText(m.text, "GRMMob_XS", 204), "GRMMob_XS", out and w - 238 or 34, y + 14, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                            y = y + 32
                        end
                    end
                    topY = y + 8
                end
                local contentBottom=smart and(h-58)or(screenBottom-12)
                drawButtonList(w,topY,contentBottom)
                if not smart then
                    local keyTop=screenBottom+22
                    draw.RoundedBox(12,14,keyTop+8,82,46,Color(55,62,72))
                    local _,backPressed=drawPointerFeedback(12,14,keyTop+8,82,46,"nav:back")
                    draw.SimpleText("Назад","GRMMob_XS",55,keyTop+31+(backPressed and 1 or 0),C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                    draw.RoundedBox(12,w-96,keyTop+8,82,46,Color(108,45,50))
                    local _,closePressed=drawPointerFeedback(12,w-96,keyTop+8,82,46,"nav:close")
                    draw.SimpleText("Убрать","GRMMob_XS",w-55,keyTop+31+(closePressed and 1 or 0),C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                    M.hitboxes[#M.hitboxes+1]={x=14,y=keyTop+8,w=82,h=46,navAction="back"}
                    M.hitboxes[#M.hitboxes+1]={x=w-96,y=keyTop+8,w=82,h=46,navAction="close"}
                    draw.RoundedBox(18,w/2-52,keyTop,104,62,Color(44,49,56))
                    draw.RoundedBox(12,w/2-30,keyTop+8,60,46,Color(70,80,90))
                    local _,okPressed=drawPointerFeedback(18,w/2-52,keyTop,104,62,"key:OK")
                    draw.SimpleText("OK","GRMMob_S",w/2,keyTop+31+(okPressed and 1 or 0),C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                    local labels={{"1",""},{"2","ABC"},{"3","DEF"},{"4","GHI"},{"5","JKL"},{"6","MNO"},{"7","PQRS"},{"8","TUV"},{"9","WXYZ"},{"*",""},{"0","+"},{"#",""}}
                    local kw,kh=math.floor((w-64)/3),42
                    for i,k in ipairs(labels)do
                        local col=(i-1)%3;local row=math.floor((i-1)/3);local x=24+col*(kw+8);local y=keyTop+78+row*(kh+7)
                        draw.RoundedBox(8,x,y,kw,kh,Color(48,54,62))
                        local _,pressed=drawPointerFeedback(8,x,y,kw,kh,"key:"..k[1])
                        draw.SimpleText(k[1],"GRMMob_B",x+kw/2,y+15+(pressed and 1 or 0),C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                        draw.SimpleText(k[2],"GRMMob_XS",x+kw/2,y+31+(pressed and 1 or 0),C.dim,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                        M.hitboxes[#M.hitboxes+1]={x=x,y=y,w=kw,h=kh,keyValue=k[1]}
                    end
                    M.hitboxes[#M.hitboxes+1]={x=w/2-52,y=keyTop,w=104,h=62,keyValue="OK"}
                else
                    local navY,navGap= h-48,6
                    local navW=math.floor((w-36-navGap*2)/3)
                    local nav={{id="back",label="‹  Назад"},{id="home",label="○  Домой"},{id="close",label="—  Убрать"}}
                    for i,entry in ipairs(nav)do
                        local x=18+(i-1)*(navW+navGap)
                        local base=entry.id=="close" and Color(70,42,48,245) or Color(31,40,56,245)
                        draw.RoundedBox(10,x,navY,navW,34,base)
                        local _,pressed=drawPointerFeedback(10,x,navY,navW,34,"nav:"..entry.id)
                        draw.SimpleText(entry.label,"GRMMob_XS",x+navW/2,navY+17+(pressed and 1 or 0),C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                        M.hitboxes[#M.hitboxes+1]={x=x,y=navY,w=navW,h=34,navAction=entry.id}
                    end
                    draw.RoundedBox(3,w/2-25,h-8,50,3,Color(150,160,175,150))
                end
            end
        end
        M.open = true
        safe(M.frame, "SetVisible", true)
        M.screen = "home"
        M.sel = 1
        M.listSel = 1
        sendAct({ op = "open" })
        snd("open")
    end

    local function move(delta)
        local st = tostring(M.state.lineState or "idle")
        if st == "idle" and M.screen=="sms_dialog"then M.smsSel=math.max(1,(tonumber(M.smsSel)or 1)+delta);snd("nav");return end
        local items = screenItems()
        if #items == 0 then return end
        if M.screen == "home" and st == "idle" then M.sel = ((M.sel - 1 + delta) % #items) + 1 else M.listSel = ((M.listSel - 1 + delta) % #items) + 1 end
        snd("nav")
    end
    enter = function()
        local st = tostring(M.state.lineState or "idle")
        if st == "ringing" then sendAct({op="answer"}); return end
        if st=="idle" and M.screen=="dial" and (M.dial or"")~="" then snd("ring");sendAct({op="dial",number=M.dial});return end
        local items = screenItems()
        local idx = (M.screen == "home" and st == "idle") and M.sel or M.listSel
        local it = items[idx]
        if it and it.fn then snd("select"); it.fn() end
    end
    back = function()
        local st=tostring(M.state.lineState or "idle")
        if st=="ringing" or st=="call" or st=="dialing" then sendAct({op="hangup"}); return end
        if M.screen=="sms_dialog"then M.screen="sms";M.listSel=math.max(1,tonumber(M.smsThreadListSel)or 1);M.smsSel=1;snd("back");return end
        if M.screen=="contact_actions"then M.screen="contacts";M.listSel=math.max(1,tonumber(M.contactListSel)or 1);snd("back");return end
        if M.screen=="forum_detail"then M.screen="forum";M.listSel=math.max(4,tonumber(M.forumFeedSel)or 4);snd("back");return end
        if M.screen=="deactivate_confirm"then setScreen("power");snd("back");return end
        if M.screen == "home" then closePhone(true) else goHome() end
    end
    local DIGIT_KEYS = {
        [KEY_0]="0",[KEY_1]="1",[KEY_2]="2",[KEY_3]="3",[KEY_4]="4",[KEY_5]="5",[KEY_6]="6",[KEY_7]="7",[KEY_8]="8",[KEY_9]="9",
    }
    local function digit(key)
        local value=DIGIT_KEYS[key]
        if not value then return false end
        if M.screen=="dial" then M.dial=(M.dial or"")..value;snd("select");return true end
        if M.screen=="calc" then M.calc=(M.calc or"")..value;snd("select");return true end
        return false
    end
    local function isMouse3(key)
        -- Garry's Mod uses 107 for MOUSE_LEFT. Treating 107 as Mouse3 made every
        -- left click also confirm the selected item through PlayerButtonDown.
        return (_G.KEY_MOUSE3 and key == KEY_MOUSE3)
            or (_G.MOUSE_MIDDLE and key == MOUSE_MIDDLE)
            or key == 109 -- MOUSE_MIDDLE in GMod's BUTTON_CODE enum
    end

    local function keyDown(key)
        --[[ Пока телефон закрыт, любая стрелка при активном вводе — не
             наша: раньше отсекался только KEY_UP, поэтому стрелки вниз
             и вбок всё равно доходили до телефона. ]]
        if not M.open and textInputActive() then return end
        if M.down[key] then return end
        if now()-(M.lastTap[key] or -999)<0.07 then return end
        M.down[key]=true;M.lastTap[key]=now();M.hold[key]=now();M.nextRepeat[key]=now()+0.45
        if not M.open then
            --[[ Сервер дёргаем ТОЛЬКО если телефон есть. Раньше запрос
                 уходил всегда, сервер отвечал «купите в /phoneshop», и
                 каждое нажатие стрелки давало новую строку в чат. ]]
            if key==KEY_UP then
                if hasPhone() then requestServerOpen() openPhone(false) else openPhone(false) end
            end
            return
        end
        if key==KEY_UP then move(-1);return end
        if key==KEY_DOWN then move(1);return end
        if key==KEY_ENTER then enter();return end
        if isMouse3(key)then selectCurrent();return end
        if key==KEY_BACKSPACE then back();return end
        if _G.KEY_ESCAPE and key==KEY_ESCAPE then closePhone(true);return end
        if key==KEY_LEFT then back();return end
        if key==KEY_RIGHT then goHome();snd("back");return end
        if key==KEY_DELETE and M.screen=="notes"then sendAct({op="note_del",i=math.max(1,M.listSel)});return end
        if key==KEY_N and M.screen=="forum"then askString("Форум","Текст поста","",function(txt)sendAct({op="forum_post",text=txt})end);return end
        if key==KEY_E then RunConsoleCommand("say","/me показывает номер телефона "..tostring(M.state.number or""));return end
        if digit(key)then return end
        if M.screen=="calc"then
            local operators={[_G.KEY_PAD_PLUS or -1]="+",[_G.KEY_PAD_MINUS or -2]="-",[_G.KEY_PAD_MULTIPLY or -3]="*",[_G.KEY_PAD_DIVIDE or -4]="/"}
            local op=operators[key];if op then M.calc=(M.calc or"")..op;snd("select")end
        end
    end

    local function keyUp(key)
        -- SDL/OS может слать синтетические Down+Up пары, пока клавиша всё
        -- ещё физически зажата. Не снимаем lock до настоящего отпускания.
        if input and input.IsKeyDown and input.IsKeyDown(key) then return end
        M.down[key]=nil; M.hold[key]=nil; M.nextRepeat[key]=nil
    end
    MB._uiKeyDown=keyDown
    MB._uiKeyUp=keyUp

    function MB.ClientIsOpen()
        return M.open == true
    end
    function MB.ClientBlocksInput()
        return M.open == true
    end
    function MB.ClientWheel(delta)
        if M.open then move(tonumber(delta) or 1) return true end
        return false
    end
    selectCurrent = function()
        if now() - (tonumber(M.lastSelectAt) or -999) < 0.25 then return end
        M.lastSelectAt = now()
        enter()
    end

    function MB.ClientSelect()
        if M.open then selectCurrent() return true end
        return false
    end
    function MB.ClientClose()
        if M.open then closePhone(true) return true end
        return false
    end

    net.Receive("GRM_Mob_State", function()
        M.state = net.ReadTable() or {}; M.stateKnown = true; MB.ClientState=M.state
        if M.state.has == false then
            M.pendingOpen = false
            closePhone(false)
        elseif M.pendingOpen and not M.open then
            M.pendingOpen = false
            openPhone(false)
        end
    end)
    net.Receive("GRM_Mob_Data", function()
        local k=net.ReadString()
        local p=net.ReadTable() or {}
        k=tostring(k or "")
        M.data[k]=p
        if k=="forum" and tonumber(M.forumPostID) then
            for _,post in ipairs(p.rows or {})do
                if tonumber(post.id)==tonumber(M.forumPostID)then M.forumPost=post break end
            end
        end
        MB.ClientData=M.data
    end)
    net.Receive("GRM_Mobile_Open", function()
        M.pendingOpen = true
        if hasPhone() then M.pendingOpen = false; openPhone(false) end
    end)

    hook.Add("StartChat", "GRM_Mobile_BlockOpenWhileTyping", function() M.chatOpen = true end)
    hook.Add("FinishChat", "GRM_Mobile_UnblockOpenAfterTyping", function() M.chatOpen = false end)
    hook.Add("PlayerButtonDown", "GRM_Mobile_KeyDown", function(ply, key) if ply ~= lp() then return end keyDown(key) end)
    hook.Add("PlayerButtonUp", "GRM_Mobile_KeyUp", function(ply, key) if ply ~= lp() then return end keyUp(key) end)
    local keyRepeatDelta={[KEY_UP]=-1,[KEY_DOWN]=1}
    hook.Add("Think", "GRM_Mobile_KeyRepeat", function()
        -- Keyboard repeat intentionally disabled: menu navigation is mouse wheel only.
        -- Live GMod note: DFrame/MakePopup may eat PlayerButtonDown for arrows.
        -- Poll physical keys here so UP opens and DOWN closes even with VGUI focus.
        if not input or not input.IsKeyDown then return end

        if M.open then
            for key,delta in pairs(keyRepeatDelta)do
                if M.down[key] and input.IsKeyDown(key) and now()>=(M.nextRepeat[key] or math.huge)then
                    M.nextRepeat[key]=now()+0.11;move(delta)
                end
            end
        end

        local upNow = input.IsKeyDown(KEY_UP) == true
        if upNow and not M.poll.up then
            if not M.open and not textInputActive() then
                -- Тот же принцип, что в keyDown: без телефона сервер не тревожим.
                if hasPhone() then requestServerOpen() openPhone(false) else openPhone(false) end
            elseif M.open then move(-1) end
        end
        M.poll.up = upNow

        local downNow = input.IsKeyDown(KEY_DOWN) == true
        if downNow and not M.poll.down and not M.down[KEY_DOWN] and M.open then move(1) end
        M.poll.down = downNow

        local leftNow = input.IsKeyDown(KEY_LEFT) == true
        if leftNow and not M.poll.left and not M.down[KEY_LEFT] and M.open then back() end
        M.poll.left = leftNow
        local rightNow = input.IsKeyDown(KEY_RIGHT) == true
        if rightNow and not M.poll.right and not M.down[KEY_RIGHT] and M.open then goHome(); snd("back") end
        M.poll.right = rightNow

        local mouse3Now = false
        if _G.KEY_MOUSE3 then mouse3Now = mouse3Now or input.IsKeyDown(KEY_MOUSE3) == true end
        if _G.MOUSE_MIDDLE then
            mouse3Now = mouse3Now or input.IsKeyDown(MOUSE_MIDDLE) == true
            if input.IsMouseDown then mouse3Now = mouse3Now or input.IsMouseDown(MOUSE_MIDDLE) == true end
        else
            mouse3Now = mouse3Now or input.IsKeyDown(109) == true
            if input.IsMouseDown then mouse3Now = mouse3Now or input.IsMouseDown(109) == true end
        end
        if mouse3Now and not M.poll.mouse3 and M.open then selectCurrent() end
        M.poll.mouse3 = mouse3Now
    end)
    hook.Add("CreateMove", "GRM_Mobile_NoWorldFire", function(cmd)
        if not M.open then return end
        cmd:RemoveKey(IN_ATTACK)
        cmd:RemoveKey(IN_ATTACK2)
        cmd:RemoveKey(IN_RELOAD)
        cmd:RemoveKey(IN_USE)
        cmd:RemoveKey(IN_GRENADE1)
        cmd:RemoveKey(IN_GRENADE2)
    end)
    hook.Add("HUDShouldDraw", "GRM_Mobile_HideSelector", function(name)
        if M.open and (name == "CHudWeaponSelection" or name == "CHudAmmo") then return false end
    end)
    hook.Add("HUDPaint", "GRM_Mobile_CallHUD", function() if M.open and tostring(M.state.lineState or "") == "ringing" then draw.SimpleText("Входящий вызов", "GRMMob_B", ScrW()/2, 120, C.green, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end end)
    hook.Add("PlayerBindPress", "GRM_Mobile_BlockSlots", function(_, bind, pressed)
        if not M.open then return false end
        bind = string.lower(tostring(bind or ""))

        if not pressed then
            return false
        end

        -- Mouse wheel is the only navigation channel while the phone is open.
        if bind == "invnext" then move(1); return true end
        if bind == "invprev" then move(-1); return true end

        -- Middle mouse confirms/selects. Different configs expose it as +attack3/mouse3.
        if bind == "+attack3" or bind == "attack3" or bind == "mouse3" or bind == "+mouse3" then
            selectCurrent()
            return true
        end

        -- Block weapon selector, weapon slots and all gameplay actions while phone UI is open.
        if bind:match("^slot%d") or bind == "lastinv" or bind == "phys_swap" then return true end
        if bind == "+attack" or bind == "+attack2" or bind == "+reload" or bind == "+use" then return true end
        if bind == "+jump" or bind == "+duck" or bind == "+speed" or bind == "+walk" then return true end
        if bind == "gmod_undo" or bind == "undo" or bind == "gm_showhelp" or bind == "gm_showteam" or bind == "gm_showspare1" or bind == "gm_showspare2" then return true end

        -- Conservative default: if the phone is open, do not let unknown press-binds leak
        -- into gameplay/addons. DOWN arrow or close button handles closing.
        return true
    end)
    timer.Create("GRM_Mob_Tick", 1, 0, function()
        if not M.open then return end
        local p=lp(); if p and p.Alive and not p:Alive() then closePhone(true); return end
        sendAct({op="ping"})
    end)
end


--[[ Модуль представляется общему реестру GRM.Modules: соседи знают, что он
     есть, а шина обновлений сама позовёт его при смене прав, состава,
     должности или персонажа. ]]
if GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("mobile", {
        label = "Мобильная связь",
        version = (GRM.Mobile and GRM.Mobile.Version) or "1.0.0",
        Depends = { "access" },
        Status = function() local n = 0 for _ in pairs(GRM.Mobile.Numbers or {}) do n = n + 1 end return ("номеров выдано: %d"):format(n) end,
    })
end
