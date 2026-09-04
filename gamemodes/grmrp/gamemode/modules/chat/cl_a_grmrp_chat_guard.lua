--[[ Вечер-20. Карантин устаревшей копии аддона. Третья серия одинаковых
    боевых трейсов показала системную причину: режим владелец обновляет, а
    addons/grm остаётся веч.-18-ным — и форвардеры режима (file.Exists
    "grm_chat/...","LUA") из принципа «единая библиотека» берут именно
    аддонскую копию, отравляя и свежий gamemode мёртвыми методами движка.
    Режим не может переписать чужие файлы — но обязан их НЕ грузить: если
    cl-копии аддона содержат фантомы (Panel:SetBounds / SetKeyInputEnabled —
    обоих НЕТ в Lua-API; боевые крешы веч.-17/18), форвардеры игнорируют
    аддонскую копию и берут встроенную lib/grm_chat (байтово идентична
    библиотеке — гейт tools/sync_chat_addon.py --check). Имя файла с
    префиксом cl_a — чтобы GRMAPI загрузил стража раньше прочих cl-модулей
    чата. ]]
GRMRP = GRMRP or {}

local stale = nil
local POISON = { ":SetBounds(", ":SetKeyInputEnabled(" }

local function poisoned(path)
    if not (file and file.Read) then return false end
    local ok, src = pcall(file.Read, path, "LUA")
    if not ok or not isstring(src) then return false end
    for _, p in ipairs(POISON) do
        if src:find(p, 1, true) then return true end
    end
    return false
end

function GRMRP.IsAddonChatStale()
    if stale == nil then
        local present = file and file.Exists
            and file.Exists("grm_chat/cl_hud.lua", "LUA")
        stale = (present == true) and (poisoned("grm_chat/cl_hud.lua")
            or poisoned("grm_chat/cl_input.lua"))
        if stale then
            MsgC(Color(255, 168, 0), "[GRMRP] ЧАТ: копия аддона grm СТАРАЯ ")
            MsgC(Color(255, 168, 0), "(фантомы SetBounds/SetKeyInputEnabled).\n")
            MsgC(Color(255, 168, 0), "[GRMRP] Подключена встроенная копия ")
            MsgC(Color(255, 168, 0), "режима — чат работает. Замени аддон на ")
            MsgC(Color(255, 168, 0), "сборку веч.-20+: grm_single_addon.zip ")
            MsgC(Color(255, 168, 0), "→ garrysmod/addons/ (папка grm).\n")
        end
    end
    return stale == true
end
