--[[ GRM:RP — общий загрузочный слой режима (Часть VII проекта, WIKI.md)

    Режим автономный: свои права (GRM.Admin), свои сохранения, свой чат.
    Зависимости от ULib/ULX запрещены постоянным указанием владельца.
    База sandbox — единственное заимствование движка (паттерн DarkRP 4.16.1),
    все переопределения идут через self.BaseClass с честным fallback.
]]

-- Единственный правильный дом для DeriveGamemode — shared.lua: оба входа
-- (init/cl_init) включают shared сами (движок shared.lua НЕ подгружает —
-- см. GMod wiki «Gamemode Creation»), поэтому на рантайме вызов происходит
-- ровно один раз. Инцидент 03.09.2026: без include("shared.lua") в cl_init
-- клиент падал на nil GRMRP и откатывался на base (player_sandbox бэктрейс).
DeriveGamemode("sandbox")

include("grm_api.lua")

GRMRP = GRMRP or {
    VERSION = "0.1.0",
    -- Фаза «идёт загрузка»: модули декларируют реестры, но не исполняют
    -- межмодульные вызовы (флаг проверяют точки, которым важно наличие
    -- соседей). Снимается в init.lua/cl_init.lua после GRMAPI.finish().
    Loading = true,
    Modules = GRMRP and GRMRP.Modules or {},
}

GRMRP.Net = GRMRP.Net or {
    SAY = "grmrp/chat_say",
    MSG = "grmrp/chat_msg",
    PING = "grmrp/ping"
}

function GRMRP.Log(...)
    MsgC(Color(64, 222, 147), "[GRMRP] ", Color(225, 238, 247), ...)
    PrintMessage(HUD_PRINTCONSOLE, "\n")
end

function GRMRP.ErrorNoHalt(...)
    MsgC(Color(244, 78, 96), "[GRMRP] ", Color(250, 185, 63), ...)
    PrintMessage(HUD_PRINTCONSOLE, "\n")
end
