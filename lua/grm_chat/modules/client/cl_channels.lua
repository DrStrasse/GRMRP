--[[ Модуль (client): ПОДАВЛЕНИЕ КАНАЛОВ (по образцу tag-фильтров EasyChat:
    у нас роль тегов играют каналы). /mute <канал>, /unmute <канал>,
    /mutes — список. Подавленная строка не попадает в ленту-витрину, НО
    идёт в архив/историю (данные не теряем). Настройки живут в
    data/grm_chat_mutes.txt — переживают перезаход. ]]
if not (GRMRPChat and hook and hook.Add) then return end

local FILE = "grm_chat_mutes.txt"
local MUTED = {}
GRMRPChat.MutedChannels = MUTED

local function loadMutes()
    if not (file and file.Exists and file.Read) then return end
    if not file.Exists(FILE, "DATA") then return end
    for line in tostring(file.Read(FILE, "DATA") or ""):gmatch("[^\r\n]+") do
        local nm = line:match("^%s*(.-)%s*$")
        if nm and #nm > 0 then MUTED[nm:lower()] = true end
    end
end

local function saveMutes()
    if not (file and file.Write) then return end
    local t = {}
    for c in pairs(MUTED) do t[#t + 1] = c end
    table.sort(t)
    file.Write(FILE, table.concat(t, "\n"))
end

loadMutes()

local function chanId(token)
    token = tostring(token or ""):lower():gsub("^/+", "")
    if token == "" then return nil end
    if GRMRPChat.GetChannel and GRMRPChat.GetChannel(token) then return token end
    if GRMRPChat.Channels then
        for id, ch in pairs(GRMRPChat.Channels) do
            if ch.cmd == token then return id end
        end
    end
    return nil
end

hook.Add("GRMRPChat_Message", "grm_chat.channels", function(line)
    local id = line and line.chan and (line.chan.id or line.chan.cmd)
    if id and MUTED[tostring(id):lower()] then line.muted = true end
end)

hook.Add("GRMRPChat_ClientCommand", "grm_chat.channels", function(ply, text)
    if ply ~= LocalPlayer() then return end
    text = tostring(text or "")
    local add, tok = text:match("^/(mute)%s+(%S+)$")
    if not add then
        add, tok = text:match("^/(unmute)%s+(%S+)$")
    end
    if add then
        local id = chanId(tok)
        if not id then
            GRMRPChat.AddSystem("нет такого канала: " .. tok
                .. " (список — /mutes)")
            return true
        end
        if add == "mute" then MUTED[id] = true else MUTED[id] = nil end
        saveMutes()
        GRMRPChat.AddSystem("канал «" .. id .. "» — "
            .. (MUTED[id] and "подавлен в ленте (архив пишется)"
                or "снова виден"))
        return true
    end
    if text:match("^/mutes/?$") then
        local t = {}
        for c in pairs(MUTED) do t[#t + 1] = c end
        table.sort(t)
        GRMRPChat.AddSystem(#t > 0
            and "подавлено: " .. table.concat(t, ", ")
            or "подавленных каналов нет")
        return true
    end
end)
