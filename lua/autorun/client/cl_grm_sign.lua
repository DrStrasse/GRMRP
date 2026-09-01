--[[--------------------------------------------------------------------
    GRM Sign v1.0.0 — один слой вывесок 3D2D над энтити (заказ владельца
    21.08: «у скупщиков полетел заголовок»).

    ПОЧЕМУ ЗАГОЛОВОК ПРОПАДАЛ. Торгаш и скупщик рисовали вывеску прямо в
    ENT:Draw, а у обоих RenderGroup = RENDERGROUP_BOTH. Значит Draw
    вызывался ДВАЖДЫ за кадр: сначала в непрозрачном проходе, потом в
    прозрачном. Подложка рисовалась второй раз поверх уже нарисованного
    текста, а текст второго прохода ложился в ту же плоскость глубины и
    отбрасывался тестом глубины. Итог ровно тот, что на скриншоте:
    тёмная плашка с цветной полоской есть, букв нет.

    ЧТО СДЕЛАНО. Вывеска вынесена в общий слой и рисуется ОДИН раз за
    кадр — в ENT:DrawTranslucent (прозрачный проход, где текстовым
    шрифтам и место). Дополнительно:
      • ширина плашки считается по фактической ширине заголовка и имени,
        поэтому длинные названия больше не вылезают за подложку;
      • шрифты создаются один раз и проверяются замером: если шрифт по
        какой-то причине не создался, слой честно падает на DermaLarge,
        а не рисует пустоту;
      • тело отрисовки завёрнуто в pcall, но cam.End3D2D выполняется
        всегда — ошибка внутри вывески больше не может «уронить»
        матрицу 3D2D и испортить весь остальной кадр;
      • grm_sign_debug 1 печатает причину, если отрисовка упала.

    Использование в энтити:
        function ENT:DrawTranslucent()
            GRM.Sign.Draw(self, { title = "СКУПЩИК РУДЫ", subtitle = name,
                hint = "E — открыть", accent = Color(245,195,65), height = 82 })
        end
----------------------------------------------------------------------]]

GRM = GRM or {}
GRM.Sign = GRM.Sign or {}
local S = GRM.Sign
S.Version = "1.0.0"

local cvDebug = CreateClientConVar("grm_sign_debug", "0", true, false,
    "1 — печатать ошибки отрисовки вывесок GRM")

S.Font = S.Font or {}

local FONTS = {
    title = { name = "GRM_Sign_Title", size = 26, weight = 800, fallback = "DermaLarge" },
    sub   = { name = "GRM_Sign_Sub",   size = 17, weight = 700, fallback = "DermaDefaultBold" },
    hint  = { name = "GRM_Sign_Hint",  size = 14, weight = 600, fallback = "DermaDefault" },
}

--- Создать шрифты и убедиться, что ими реально можно писать.
function S.EnsureFonts(force)
    if S._fontsReady and not force then return end
    S._fontsReady = true
    for key, def in pairs(FONTS) do
        surface.CreateFont(def.name, {
            font = "Roboto", size = def.size, weight = def.weight, extended = true, antialias = true,
        })
        local ok, w = pcall(function()
            surface.SetFont(def.name)
            return (surface.GetTextSize("Ая Wg"))
        end)
        S.Font[key] = (ok and (tonumber(w) or 0) > 0) and def.name or def.fallback
    end
end

hook.Add("OnScreenSizeChanged", "GRM_Sign_Fonts", function() S.EnsureFonts(true) end)

--- Ширина строки выбранным шрифтом (0, если что-то не так).
local function textWide(text, font)
    local ok, w = pcall(function()
        surface.SetFont(font)
        return (surface.GetTextSize(tostring(text or "")))
    end)
    return (ok and tonumber(w)) or 0
end

--- Нарисовать вывеску над энтити.
--  opts: title, subtitle, hint, accent, height, scale, dist, hintDist, minWide
function S.Draw(ent, opts)
    if not IsValid(ent) then return end
    opts = opts or {}

    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local dist = tonumber(opts.dist) or 400
    local d2 = lp:EyePos():DistToSqr(ent:GetPos())
    if d2 > dist * dist then return end

    S.EnsureFonts()

    local title  = tostring(opts.title or "")
    local sub    = tostring(opts.subtitle or "")
    local hint   = tostring(opts.hint or "")
    local accent = opts.accent or Color(245, 195, 65)
    local scale  = tonumber(opts.scale) or 0.16
    local height = tonumber(opts.height) or 82
    local hintD  = tonumber(opts.hintDist) or 220
    local showHint = hint ~= "" and d2 < hintD * hintD

    -- Подложка шире самой длинной строки: заголовок не «вылезает».
    local wide = math.max(tonumber(opts.minWide) or 300,
        textWide(title, S.Font.title) + 60,
        textWide(sub, S.Font.sub) + 50,
        showHint and (textWide(hint, S.Font.hint) + 50) or 0)
    local tall = showHint and 84 or 62

    -- Стандартный billboard 3D2D: +90 разворачивал матрицу изнанкой,
    -- поэтому оставалась подложка/иконки, а глифы текста отбрасывались.
    local ang = Angle(0, (lp:EyeAngles().y - 90) % 360, 90)
    cam.Start3D2D(ent:GetPos() + Vector(0, 0, height), ang, scale)
    local ok, err = pcall(function()
        draw.RoundedBox(8, -wide / 2, -tall / 2, wide, tall, Color(12, 17, 25, 235))
        draw.RoundedBox(8, -wide / 2, -tall / 2, wide, 6, accent)
        draw.SimpleText(title, S.Font.title, 0, -tall / 2 + 12, accent,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        if sub ~= "" then
            draw.SimpleText(sub, S.Font.sub, 0, -tall / 2 + 40, Color(235, 240, 248),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
        if showHint then
            draw.SimpleText(hint, S.Font.hint, 0, -tall / 2 + 62, Color(120, 205, 255),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end)
    cam.End3D2D()

    if not ok and cvDebug:GetBool() then
        print("[GRM Sign] " .. tostring(ent) .. ": " .. tostring(err))
    end
end

print("[GRM Sign] v" .. S.Version .. " loaded (Client)")
