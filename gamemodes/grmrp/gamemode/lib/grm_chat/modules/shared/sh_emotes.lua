--[[ Модуль (shared): КАТАЛОГ отыгрышей/команд — единый справочник для
    пикера, автодополнения и /chatdiag. Источник правды: GRMRPChat.RP
    (форматы отыгрышей) + GRMRPChat.Channels (каналы) + реестр внешних
    команд модулей (RegisterExternalChatCommand) + переданный список
    локальных клиентских команд. Чистые функции — без движка. ]]
GRMRPChat = GRMRPChat or {}
if GRMRPChat.__m_emotes then return end
GRMRPChat.__m_emotes = true

local HINTS = {
    me = "отыгрыш: действие от третьего лица («* Вася оглядывается»)",
    ["do"] = "отыгрыш: описание со стороны (услышат рядом)",
    it = "отыгрыш: реакция на последний /do рядом",
    try = "отыгрыш: попытка с серверной проверкой исхода",
    roll = "бросок кубика 1..N (серверный результат)",
}

function GRMRPChat.EmoteHint(cmd)
    return HINTS[tostring(cmd or ""):lower()]
end

-- Единый словарь «/имя → смысл». extra = таблица имен локальных команд
-- клиента (mute/help/...), помечаются kind=локально.
function GRMRPChat.CatalogCommands(extra)
    local out, seen = {}, {}
    local function add(nm, hint, kind)
        nm = tostring(nm or ""):lower():gsub("^/+", "")
        if nm == "" or seen[nm] then return end
        seen[nm] = true
        out[#out + 1] = { name = "/" .. nm, hint = hint or "", kind = kind or "" }
    end
    for cmd in pairs(GRMRPChat.RP or {}) do
        add(cmd, GRMRPChat.EmoteHint(cmd), "отыгрыш")
    end
    for id, ch in pairs(GRMRPChat.Channels or {}) do
        add(ch.cmd or id, "канал: " .. tostring(ch.title or id), "канал")
    end
    for nm in pairs(GRMRPChat.ExternalCommands or {}) do
        add(nm, "команда модуля", "модуль")
    end
    for nm in pairs(extra or {}) do
        add(nm, "локальная команда клиента", "локально")
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Кандидаты автодополнения: ввод начинается с «/». maxN — потолок списка.
function GRMRPChat.CompleteCandidates(typed, catalog, maxN)
    typed = GRMRPChat.LowerFold and GRMRPChat.LowerFold(tostring(typed or ""))
        or string.lower(tostring(typed or ""))
    if typed:sub(1, 1) ~= "/" then return {} end
    local out = {}
    local cap = tonumber(maxN) or 7
    for _, it in ipairs(catalog or {}) do
        if #it.name > #typed and it.name:sub(1, #typed) == typed then
            out[#out + 1] = it
            if #out >= cap then break end
        end
    end
    return out
end

-- Упоминание: чужая строка, в тексте которой есть ник слушателя (>=3
-- символа, регистронезависимо, без ложных срабатываний на себе).
-- Регистронезависимость без зависимости от string.lower движка: ASCII
-- + русские заглавные (UTF-8 D0 90..AF и Ё). Тот же результат в бою и
-- в стенде.
local function lowerFold(s)
    local out, i = {}, 1
    while i <= #s do
        local c = s:byte(i)
        local b2 = s:byte(i + 1)
        if c >= 65 and c <= 90 then
            out[#out + 1] = string.char(c + 32)
            i = i + 1
        elseif c == 0xD0 and b2 then
            if b2 >= 0x90 and b2 <= 0x9F then
                out[#out + 1] = string.char(0xD0, b2 + 32)
            elseif b2 >= 0xA0 and b2 <= 0xAF then
                -- Р..Я: строчные за границей D0→D1 (р..я = D1 80..8F)
                out[#out + 1] = string.char(0xD1, b2 - 0x20)
            elseif b2 == 0x81 then
                -- Ё → ё (U+0451 = D1 91, не D0 B1!)
                out[#out + 1] = string.char(0xD1, 0x91)
            else
                out[#out + 1] = s:sub(i, i + 1)
            end
            i = i + 2
        else
            out[#out + 1] = s:sub(i, i)
            i = i + 1
        end
    end
    return table.concat(out)
end

GRMRPChat.LowerFold = lowerFold

function GRMRPChat.MentionHit(authorNick, myNick, text)
    local a = lowerFold(tostring(authorNick or ""))
    local m = lowerFold(tostring(myNick or ""))
    if #m < 3 or a == m then return false end
    return lowerFold(tostring(text or "")):find(m, 1, true) ~= nil
end
