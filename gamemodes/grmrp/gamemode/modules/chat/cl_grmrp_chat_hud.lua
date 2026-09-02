--[[ GRMRPChat HUD-лента: closed-form fade (EasyChat chathud, WIKI 4.21.4),
    кольцевой буфер, разметка не парсится — рисуем чипами (цвет канала +
    имя + текст), т.к. пользовательский ввод уже обезврежен на сервере.
]]

if SERVER then return end

surface.CreateFont("GRMRP_Chat14", {
    font = "Roboto", size = 14, weight = 500, extended = true
})
surface.CreateFont("GRMRP_ChatChip", {
    font = "Roboto", size = 13, weight = 700, extended = true
})

GRMRPChat = GRMRPChat or {}
GRMRPChat.lines = GRMRPChat.lines or {}
GRMRPChat.INPUT_OPEN = false

local MAX_LINES = 60
local TTL, FADE = 45, 4          -- сек; fade — последние FADE секунд жизни

local function push(chan, name, text, t, mine)
    table.insert(GRMRPChat.lines, {
        chan = chan, name = name, text = text, t = t, mine = mine and true or false
    })
    if #GRMRPChat.lines > MAX_LINES then
        table.remove(GRMRPChat.lines, 1)
    end
end

function GRMRPChat.AddLine(chanId, name, text, t)
    local chan = GRMRPChat.GetChannel and GRMRPChat.GetChannel(chanId)
    push(chan or { title = "·", color = { r = 255, g = 255, b = 255 } },
        name, text, t, false)
end

function GRMRPChat.AddSelfLine(chanId, text)
    local chan = GRMRPChat.GetChannel and GRMRPChat.GetChannel(chanId)
    push(chan or { title = "·", color = { r = 255, g = 255, b = 255 } },
        LocalPlayer():Name(), text, CurTime(), true)
end

function GRMRPChat.ClearLines()
    GRMRPChat.lines = {}
end

net.Receive(GRMRP.Net.MSG, function()
    if not IsValid(GRMRPChat) then return end
    local chanId = net.ReadString()
    local name = net.ReadString()
    local text = net.ReadString()
    local t = net.ReadDouble()
    if chanId == "system" then
        push({ title = "!", color = { r = 250, g = 185, b = 63 } }, "", name, CurTime(), false)
        return
    end
    if string.sub(chanId, -5) == "_self" then
        -- эхо сервера для наших старых клиентов: локальный эхо-каст уже
        -- напечатан — молча гасим дубль (§5.2 «один владелец строки»)
        return
    end
    GRMRPChat.AddLine(chanId, name, text, t)
end)

hook.Add("HUDPaint", "GRMRPChat_HUD", function()
    local lines = GRMRPChat.lines
    if #lines == 0 then return end

    local h = ScrH()
    local x, yBase = 16, h - 130
    local nowRT = RealTime()
    local hold = GRMRPChat.INPUT_OPEN

    local shown = 0
    for i = #lines, 1, -1 do
        local ln = lines[i]
        if shown < 18 then
            local age = nowRT - ln.t
            local lifeLeft = (hold and 0) or math.Clamp((TTL + FADE - age) / FADE, 0, 1)
            if lifeLeft > 0 then
                shown = shown + 1
                local y = yBase - shown * 22
                local chan = ln.chan
                local col = chan.color or { r = 255, g = 255, b = 255 }
                local a = math.floor(255 * lifeLeft + 0.5)

                surface.SetFont("GRMRP_Chat14")
                local tw = surface.GetTextSize(ln.text) or 40
                surface.SetDrawColor(8, 14, 23, math.floor(a * 0.55))
                surface.DrawRect(x - 6, y - 3, math.min(760, 130 + tw), 20)
                draw.DrawText("[" .. chan.title .. "]", "GRMRP_ChatChip", x, y - 1,
                    Color(col.r, col.g, col.b, a), TEXT_ALIGN_LEFT)
                local tx = x + 14 + #chan.title * 9
                if #ln.name > 0 then
                    draw.DrawText(ln.name .. ":", "GRMRP_ChatChip", tx, y - 1,
                        Color(170, 190, 210, a), TEXT_ALIGN_LEFT)
                    tx = tx + #ln.name * 8 + 10
                end
                draw.DrawText(ln.text, "GRMRP_Chat14", tx, y,
                    ln.mine and Color(255, 255, 255, a) or Color(225, 238, 247, a),
                    TEXT_ALIGN_LEFT)
            end
        end
    end

    -- подметание просроченных (не держим мусор буфера между боями)
    if not hold then
        for i = #lines, 1, -1 do
            if nowRT - lines[i].t > TTL + FADE then
                table.remove(lines, i)
            end
        end
    end
end)
