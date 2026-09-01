--[[--------------------------------------------------------------------
    GRM Chat System — Shared Config
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Chat = GRM.Chat or {}

-- Ролевые команды: sh_grm_rp_chat.lua (/me /do /it /try /roll /w /y /looc /ooc)
GRM.Chat.Config = {
    -- ── Радиусы ──────────────────────────────────────────────
    LocalRadius = 355,
    WhisperRadius = 120,
    YellRadius = 700,
    LOOCRadius = 355,
    RadioRadius = 0,          -- 0 = вся карта (глобально для фракции)

    -- ── Поведение ────────────────────────────────────────────
    ForceNormalChatLocal = true,
    AllowAdminGlobalChat = true,
    OOCOnlyAdmin = true,

    -- ── История сообщений ────────────────────────────────────
    MaxHistoryLines = 200,
    SaveHistoryToFile = true,

    -- ── Цвета ────────────────────────────────────────────────
    Colors = {
        localChat  = Color(235, 235, 235),
        globalChat = Color(200, 200, 255),
        me         = Color(200, 160, 255),
        doChat     = Color(160, 210, 255),
        it         = Color(190, 190, 210),
        tryGood    = Color(100, 220, 100),
        tryBad     = Color(230, 90, 90),
        roll       = Color(255, 220, 120),
        whisper    = Color(180, 180, 180),
        yell       = Color(255, 210, 120),
        looc       = Color(255, 165, 0),
        ooc        = Color(255, 255, 255),
        radio      = Color(0, 255, 100),
        frRadio    = Color(255, 200, 0),
        dep        = Color(120, 200, 255),
        depb       = Color(180, 180, 180),
        gnews      = Color(255, 0, 0),
        gnewsName  = Color(100, 200, 255),
        system     = Color(255, 200, 80),
        name       = Color(100, 200, 255),
        prefix     = Color(200, 200, 200),
    },

    -- ── Контекстное меню ─────────────────────────────────────
    ContextMenu = {
        Width = 200,
        ButtonHeight = 36,
        Gap = 4,
        Padding = 8,
        XOffset = 20,          -- отступ от правого края
        YOffset = 200,         -- отступ сверху
        Colors = {
            bg      = Color(14, 16, 22, 230),
            border  = Color(40, 45, 65, 180),
            ticket  = Color(180, 100, 60),
            ticketH = Color(200, 120, 80),
            inv     = Color(50, 120, 200),
            invH    = Color(70, 140, 220),
            market  = Color(60, 180, 100),
            marketH = Color(80, 200, 120),
            third   = Color(100, 100, 180),
            thirdH  = Color(120, 120, 200),
            radio   = Color(180, 160, 60),
            radioH  = Color(200, 180, 80),
            faction = Color(80, 80, 180),
            factionH= Color(100, 100, 200),
            mask    = Color(140, 80, 160),
            maskH   = Color(160, 100, 180),
        },
    },
}
