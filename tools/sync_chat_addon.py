#!/usr/bin/env python3
"""Синхронизатор чат-модуля: gamemode GRMRP (источник) → аддон (GRMChat).

Режим автономен (указание 8), но песочнице с аддоном нужен тот же чат, а не
движковый. Дублирование кола запрещено правилами, поэтому аддонская копия —
МАШИНОГЕННАЯ: источник всегда gamemodes/grmrp/gamemode/modules/chat/*, а
lua/autorun/*08_grm_chat* перегенерируются этой утилитой с механической
заменой имён и realm-клеем. --check — режим гейта (расхождение = красные
ворота). См. WIKI 7.2 «чат режима», CHANGELOG 03.09.
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join("gamemodes", "grmrp", "gamemode", "modules", "chat")

GEN_NOTE = (
    "-- СГЕНЕРИРОВАНО tools/sync_chat_addon.py — источник: %s\n"
    "-- Не править руками: изменения вносите в файл режима и перегенерируйте\n"
    "-- (`python3 tools/sync_chat_addon.py`); расхождение ловит --check.\n"
)

PRELUDE = """--[[ GRMChat — аддонский мутированный порт чат-модуля режима (тот же код,
    другие имена). На серверах с gamemode GRMRP порт подавляется САМИМ
    РЕЖИМОМ (GRMRPChat.SuppressAddonPort снимает все хуки/таймеры/команды с
    id «GRMChat*»; вечер-13): прежний guard «if GRMRP.Version» ловил
    только поздний reload — GMod исполняет lua/autorun аддонов ДО файлов
    режима, и на свежей карте два чата жили бок о бок (двойная Y-полоса,
    перехваты, общая DATA-история). Теперь плюс ранний guard (порядок
    reload через lua_refresh) и гейты SUPPRESSED на входах.
]]
"""

EARLY_GUARD = ("if (GRMRP and GRMRP.Version) or (GRMRPChat and GRMRPChat.Channels)\n"
               "    then return end -- режим уже здесь/на reload: порт не рождается\n")

CORE_HEAD = PRELUDE + EARLY_GUARD + """
GRMChat = GRMChat or {}
GRMChat._standalone = true -- песочница: режимного чата нет (для диагностики)
GRMChat.Net = { SAY = "grm/chat_say", MSG = "grm/chat_msg" }

-- Вечер-13 (дефект песочницы): GRMRPChat.Enabled живёт в shared.lua РЕЖИМА,
-- в конверт он не попадает — а ProcessLine порта звал GRMChat.Enabled()
-- напрямую: крах на первом же сообщении. Фолбэк читает реплицируемый cvar
-- порта (CreateConVar — в сконвертированном sv-файле).
if not GRMChat.Enabled then
    function GRMChat.Enabled()
        local cv = GetConVar and GetConVar("grm_chat_enable")
        if not cv then return true end
        return cv:GetBool()
    end
end

-- Вечер-13: и в песочнице владелец один. Старый модуль sh_grm_rp_chat.lua
-- вешает PlayerSay с return "" и глотает чужие строки целиком; его лента
-- вторым слоем дублирует вывод через chat.AddText. Снимаем его хуки после
-- загрузки всех аддонов (Initialize — порядок файлов внутри autorun
-- не гарантирован).
if hook and hook.Add then
    hook.Add("Initialize", "GRMChat_SuppressLegacy", function()
        if not (hook and hook.GetTable) then return end
        for name, byId in pairs(hook.GetTable()) do
            local doomed = {}
            for id in pairs(byId) do
                if type(id) == "string" and string.find(id, "^GRM_RPChat", 1, true) then
                    doomed[#doomed + 1] = id
                end
            end
            for i = 1, #doomed do pcall(hook.Remove, name, doomed[i]) end
        end
        if concommand and concommand.Remove then
            pcall(concommand.Remove, "grm_rpchat_help")
        end
    end)
end

function GRMChat.ErrorNoHalt(...)
    if MsgC then
        MsgC(Color(244, 78, 96), "[GRMChat] ", Color(250, 185, 63), ...)
    end
end

"""

SV_TAIL = """
-- Realm-клей песочницы: движковый PlayerSay превращается в наш канал.
hook.Add("PlayerSay", "GRMChat_Capture", function(ply, text, teamChat, isDead)
    if GRMChat.SUPPRESSED then return end -- вечер-13: режим владелец
    if GRMChat.Enabled and GRMChat.Enabled() then
        if GRMChat.OnPlayerSay(ply, text, teamChat, isDead) == "keep" then
            return text -- обрабатывают модули; лента получит их вывод
        end
        return ""
    end
end)
"""

HUD_TAIL = """
-- Единственный владелец отображения чата: движковая панель скрыта, весь
-- chat.AddText (его зовут документы/обучение/биндер) течёт в нашу ленту.
hook.Add("HUDShouldDraw", "GRMChat_HideVanilla", function(name)
    if GRMChat.SUPPRESSED then return end -- вечер-13: решает режим
    if name == "CHudChat" and GRMChat.Enabled and GRMChat.Enabled() then
        return false
    end
end)

do
    local baseAddText = chat.AddText
    function chat.AddText(...)
        -- вечер-13: при живом чате режима порт прозрачен (цепочка наружу,
        -- строки идут в ленту режима, не в порт)
        if GRMChat.SUPPRESSED or (GRMRPChat and GRMRPChat.Channels)
            or not (GRMChat.Enabled and GRMChat.Enabled()) then
            return baseAddText(...)
        end
        local parts = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if isstring(v) then
                parts[#parts + 1] = v
            end
        end
        local text = table.concat(parts, " ")
        if #text == 0 then return end
        if GRMChat.AddLine then
            GRMChat.AddLine("ooc", "", text, CurTime())
        end
    end
end
"""

INPUT_TAIL = """
-- Y в песочнице: хук движковой клавиатуры + консольная команда для бинда.
hook.Add("HUDKeyPress", "GRMChat_Y", function(code, down, up, onlydown)
    if GRMChat.SUPPRESSED then return end -- вечер-13: Y принадлежит режиму
    if code == KEY_Y and GRMChat.Enabled and GRMChat.Enabled() then
        GRMChat.OpenInput()
        return true
    end
end)
concommand.Add("grm_chat_open", function()
    if GRMChat.OpenInput then GRMChat.OpenInput() end
end)
"""

FILES = [
    # (источник, назначение, prelude?, tail?, только-client)
    ("sh_grmrp_chat_core.lua", "lua/autorun/sh_08_grm_chat_core.lua", CORE_HEAD, "", False),
    ("sv_grmrp_chat.lua", "lua/autorun/sv_08_grm_chat.lua",
     PRELUDE + EARLY_GUARD + "\n" +
     "GRMChat.DeferToModules = true -- любые /команды остаются модулям\n\n",
     SV_TAIL, False),
    ("cl_grmrp_chat_hud.lua", "lua/autorun/client/cl_08_grm_chat_hud.lua",
     PRELUDE + "if SERVER then return end\n" + EARLY_GUARD + "\n",
     HUD_TAIL, True),
    ("cl_grmrp_chat.lua", "lua/autorun/client/cl_08_grm_chat_input.lua",
     PRELUDE + "if SERVER then return end\n" + EARLY_GUARD + "\n",
     INPUT_TAIL, True),
]

# вечер-13: порт больше не пишет в ту же историю, что режим (на общем
# сервере файлы совпадали — архив режима перезаписывался песочным)
POST_REPL = [
    ('"grm_chat/archive.txt"', '"grm_chat/port_archive.txt"'),
    ('"grm_chat/input.txt"', '"grm_chat/port_input.txt"'),
    ('rawget(_G, "GRMChat")', 'rawget(_G, "GRMRPChat")'),
    # в песочнице Diagnosis-строка про порт читается про себя:
    ('"песочный порт: не установлен"', '"порт: активен (песочница, режим не найден)"'),
]

REPL = [
    ("GRMRPChat", "GRMChat"),
    ("GRMRP.Net", "GRMChat.Net"),
    ("GRMRP.ErrorNoHalt", "GRMChat.ErrorNoHalt"),
    ("grmrp_chat_", "grm_chat_"),
    ("grmrp/chat_", "grm/chat_"),
]


def convert(src_name):
    with io.open(os.path.join(ROOT, SRC, src_name), encoding="utf-8") as fh:
        body = fh.read()
    for a, b in REPL:
        body = body.replace(a, b)
    for a, b in POST_REPL:
        body = body.replace(a, b)
    # исходный заголовок-комментарий режима заменяем ген-пометкой
    if body.startswith("--[["):
        end = body.index("]]") + 2
        body = body[end:].lstrip("\n")
    return body


def expected(src_name, dst_rel, prelude, tail):
    return (GEN_NOTE % src_name) + prelude + convert(src_name).rstrip() + "\n" + tail


def main():
    check = "--check" in sys.argv
    bad = []
    for src_name, dst_rel, prelude, tail, _client in FILES:
        want = expected(src_name, dst_rel, prelude, tail)
        dst = os.path.join(ROOT, dst_rel)
        if check:
            have = ""
            if os.path.isfile(dst):
                with io.open(dst, encoding="utf-8") as fh:
                    have = fh.read()
            if have != want:
                bad.append(dst_rel)
        else:
            with io.open(dst, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(want)
            print("записан %s" % dst_rel)
    if check:
        if bad:
            print("РАСХОЖДЕНИЕ аддонской копии чата (перегенерируйте): " + ", ".join(bad))
            sys.exit(1)
        print("чат-порт синхронен источнику")


if __name__ == "__main__":
    main()
