--[[--------------------------------------------------------------------
    GRM Addon Studio — серверная часть.

    Обязанности:
      * доступ — только суперадмин (владелец);
      * витрина сущностей: scripted_ents.GetList() (аддоны читаются так);
      * проекты: data/grm_studio/<slug>.json через GRM.Persistence;
      * снимки: data/grm_studio/shots/<slug>_<n>.jpg (байты с клиента);
      * команды /studio, /адонстудия, /addonstudio + grm_addon_studio.

    Сетевые каналы (в sh_grm_addon_studio.lua зарегистрированы):
      GRM_AS_Open  S→C   открыть окно;
      GRM_AS_Sync  S→C   каталог сущностей/проекты/снимки/проект;
      GRM_AS_Act   C→S   save / load / list / photo / close.
----------------------------------------------------------------------]]
if not SERVER then return end

GRM = GRM or {}
GRM.AddonStudio = GRM.AddonStudio or {}
local A = GRM.AddonStudio

A.Catalog = A.Catalog or { ents = {}, projects = {}, shots = {} }

local function admin(ply)
    return IsValid(ply) and ply:IsSuperAdmin() == true
end

--[[ Каталог сущностей. Сканируется один раз при первом открытии и
     кэшируется: scripted_ents.GetList() дёшев, но на сервере с десятком
     аддонов даёт пару сотен записей — гонять его при каждом открытии
     незачем. ]]
function A.RefreshEnts()
    local out = {}
    local list = scripted_ents and scripted_ents.GetList and scripted_ents.GetList() or {}
    for class, _ in pairs(list) do
        if type(class) == "string" and class ~= "" then out[#out + 1] = class end
    end
    table.sort(out, function(a, b) return a < b end)
    A.Catalog.ents = out
    return #out
end

function A.RefreshProjects()
    local out = {}
    if file.Exists(A.ProjDir, "DATA") then
        for _, f in ipairs(file.Find(A.ProjDir .. "/*.json", "DATA")) do
            out[#out + 1] = string.sub(f, 1, -6)
        end
    end
    table.sort(out)
    A.Catalog.projects = out
    return #out
end

function A.RefreshShots()
    local out = {}
    if file.Exists(A.ShotsDir, "DATA") then
        for _, f in ipairs(file.Find(A.ShotsDir .. "/*.jpg", "DATA")) do out[#out + 1] = f end
    end
    table.sort(out)
    A.Catalog.shots = out
    return #out
end

function A.RefreshAll()
    A.RefreshEnts()
    A.RefreshProjects()
    A.RefreshShots()
end

--- Полный путь проекта.
function A.ProjectPath(slug)
    return A.ProjDir .. "/" .. string.sub(A.Slug(slug or ""), 1, 48) .. ".json"
end

--- Сохранение с read-back (грм-правило: file.Write сам по себе не успех).
--- GRM.Persistence — часть основного аддона GRM: без него честно отказ.
function A.SaveProject(slug, proj)
    if not GRM.Persistence or not GRM.Persistence.SaveJSON then
        return nil, "no_grm_persistence"
    end
    local path = A.ProjectPath(slug)
    local ok, res = GRM.Persistence.SaveJSON(path, A.Normalize(proj), { version = A.FormatVersion })
    return ok, res
end

function A.LoadProject(slug)
    if not GRM.Persistence or not GRM.Persistence.LoadJSON then
        return nil, "no_grm_persistence"
    end
    local path = A.ProjectPath(slug)
    local data, res = GRM.Persistence.LoadJSON(path, nil, {
        version = A.FormatVersion,
        normalize = function(t) return A.Normalize(t) end,
    })
    if res == "missing" then return nil, "missing" end
    if res ~= "ok" then return nil, res end
    return data, "ok"
end

--[[ Снимок с клиента: net.WriteData уже прочитан вызывающим, пишем его
     в файл. Имя только из нашего slug + счётчика — путь от клиента не
     берём вовсе (path traversal недопустим). ]]
function A.SaveShot(slug, bytes)
    if not isstring(bytes) or #bytes == 0 then return nil, "empty" end
    if #bytes > 512 * 1024 then return nil, "too_big" end
    if not file.Exists(A.ShotsDir, "DATA") then file.CreateDir(A.ShotsDir) end
    local base = A.Slug(slug or "shot")
    local n, name = 0, ""
    repeat
        n = n + 1
        name = string.format("%s_%03d.jpg", base, n)
    until not file.Exists(A.ShotsDir .. "/" .. name, "DATA") or n > 999
    file.Write(A.ShotsDir .. "/" .. name, bytes)
    if file.Read(A.ShotsDir .. "/" .. name, "DATA") ~= bytes then return nil, "readback" end
    return A.ShotsDir .. "/" .. name
end

function A.SendSync(ply, extra)
    if not IsValid(ply) then return end
    net.Start("GRM_AS_Sync")
    net.WriteTable({
        ents = A.Catalog.ents or {},
        projects = A.Catalog.projects or {},
        shots = A.Catalog.shots or {},
        extra = extra or {},
    })
    net.Send(ply)
end

function A.OpenStudio(ply)
    if not admin(ply) then
        if GRM.Notify then GRM.Notify(ply, "Только суперадмин.", 255, 120, 100) end
        return
    end
    A.RefreshAll()
    net.Start("GRM_AS_Open")
    net.Send(ply)
    A.SendSync(ply)
end

--[[ Приём кусков (begin/part). Манифест и снимки приходят сжатыми и
     порезанными по 8 КБ; собираем по индексам в буфере игрока, чтобы
     порядок сообщений не имел значения. ]]
A._inbox = A._inbox or {}

local function inboxComplete(ply, tag, total)
    local bx = A._inbox[tostring(ply:SteamID64() or ply:EntIndex())]
    if not bx or bx.tag ~= tag or bx.total ~= total then return nil end
    local n = 0
    for i = 1, total do if bx.parts[i] then n = n + 1 end end
    if n < total then return nil end
    local buf = {}
    for i = 1, total do buf[#buf + 1] = bx.parts[i] end
    A._inbox[tostring(ply:SteamID64() or ply:EntIndex())] = nil
    return table.concat(buf)
end

local function saveFromParts(ply, tag, total)
    local packed = inboxComplete(ply, tag, total)
    if not packed then return end
    local raw = util.Decompress(packed)
    if not isstring(raw) or #raw > 768 * 1024 then return end
    local ok, proj = pcall(A.ParseText, raw)
    if not ok or not istable(proj) or #(proj.nodes or {}) == 0 then return end
    local slug = string.sub(tag, 6, 48)
    proj.id = slug
    local saved, res = A.SaveProject(slug, proj)
    A.RefreshProjects()
    net.Start("GRM_AS_Sync")
    net.WriteTable({ projects = A.Catalog.projects or {}, saved = saved and slug or nil, result = res })
    net.Send(ply)
end

local function photoFromParts(ply, tag, total)
    local packed = inboxComplete(ply, tag, total)
    if not packed then return end
    -- Клиент сжимал и JPEG тоже (util.Compress в sendChunked).
    local bytes = util.Decompress(packed)
    if not isstring(bytes) then return end
    local path, res = A.SaveShot(string.sub(tag, 7), bytes)
    if path then A.RefreshShots() end
    net.Start("GRM_AS_Sync")
    net.WriteTable({ shotPath = path, shotResult = res or "ok" })
    net.Send(ply)
end

net.Receive("GRM_AS_Act", function(_, ply)
    if not admin(ply) then return end
    if GRM.Perf and GRM.Perf.Throttle and not GRM.Perf.Throttle("as." .. ply:EntIndex(), 0.05) then return end
    local op = string.sub(tostring(net.ReadString() or ""), 1, 12)
    local key = tostring(ply:SteamID64() or ply:EntIndex())

    if op == "close" then
        A._inbox[key] = nil
        return
    end
    if op == "begin" then
        local tag = string.sub(tostring(net.ReadString() or ""), 1, 64)
        local total = math.min(net.ReadByte(), 200)
        A._inbox[key] = { tag = tag, total = total, parts = {} }
        return
    end
    if op == "part" then
        local idx = math.floor(net.ReadByte())
        local data = net.ReadData() or ""
        local bx = A._inbox[key]
        if not bx or idx < 1 or idx > bx.total or #data > 16384 then return end
        bx.parts[idx] = data
        if string.sub(bx.tag, 1, 5) == "save:" then saveFromParts(ply, bx.tag, bx.total) end
        if string.sub(bx.tag, 1, 6) == "photo:" then photoFromParts(ply, bx.tag, bx.total) end
        return
    end
    if op == "load" then
        local slug = string.sub(A.Slug(net.ReadString() or ""), 1, 48)
        local proj, res = A.LoadProject(slug)
        if not proj then
            net.Start("GRM_AS_Sync")
            net.WriteTable({ loadError = res or "missing" })
            net.Send(ply)
            return
        end
        net.Start("GRM_AS_Sync")
        net.WriteTable({ project = proj })
        net.Send(ply)
        return
    end
    if op == "list" then
        A.RefreshAll()
        A.SendSync(ply)
        return
    end
end)

local function openStudio(ply)
    A.OpenStudio(ply)
end

hook.Add("PlayerSay", "GRM_AS_Chat", function(ply, text)
    local t = string.lower(string.Trim(tostring(text or "")))
    if t == "/studio" or t == "/адонстудия" or t == "/addonstudio" then
        openStudio(ply)
        return ""
    end
end)

hook.Add("PlayerSayTransform", "GRM_AS_ChatTransform", function(ply, pack)
    if not istable(pack) then return end
    local t = string.lower(string.Trim(tostring(pack[1] or "")))
    if t == "/studio" or t == "/адонстудия" or t == "/addonstudio" then
        openStudio(ply)
        pack[1] = ""
        pack.SkipPlayerSay = true
    end
end)

concommand.Add("grm_addon_studio", function(ply)
    if IsValid(ply) then openStudio(ply) end
end)

concommand.Add("grm_addon_studio_catalog", function(ply)
    if not IsValid(ply) or not admin(ply) then return end
    A.RefreshAll()
    print("[GRM Addon Studio] сущностей: " .. #(A.Catalog.ents or {})
        .. ", проектов: " .. #(A.Catalog.projects or {})
        .. ", снимков: " .. #(A.Catalog.shots or {}))
    A.SendSync(ply)
end)

print("[GRM Addon Studio] server loaded")
