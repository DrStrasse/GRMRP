--[[--------------------------------------------------------------------
    GRM Vehicle Keys (VK) — client sync, owner-key menu and passive HUD
----------------------------------------------------------------------]]

if not CLIENT then return end

include("autorun/sh_vehicle_keys.lua")

VK = VK or {}
VK.ClientKeys = VK.ClientKeys or {}

local NET_SYNC_VEHICLE = "VK_SyncVehicle"
local NET_RESULT = "VK_Result"
local NET_KEYS_SYNC = "VK_Keys_Sync"
local NET_SEND_LIST = "VK_SendPlayerList"
local NET_GIVE_KEY = "VK_Keys_Give"
local NET_REVOKE_KEY = "VK_Keys_Revoke"

surface.CreateFont("VK_HUD_Title", { font = "Roboto", size = 19, weight = 700, extended = true })
surface.CreateFont("VK_HUD_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
surface.CreateFont("VK_HUD_Small", { font = "Roboto", size = 12, weight = 400, extended = true })

local function notify(message, success)
    notification.AddLegacy(tostring(message or ""), success and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
    surface.PlaySound(success and "buttons/button17.wav" or "buttons/button10.wav")
end

function VK.ClientCanManagePersonalKeys(veh)
    if not IsValid(veh) or not IsValid(LocalPlayer()) then return false end
    if LocalPlayer():IsSuperAdmin() then return true end

    local ownerType, ownerSteam = VK.GetOwnerState(veh)
    local lp = LocalPlayer()
    local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(lp)) or lp:SteamID()
    return ownerType == VK.OWNER_TYPE.PLAYER and (ownerSteam == ck or ownerSteam == lp:SteamID())
end

net.Receive(NET_SYNC_VEHICLE, function()
    local veh = net.ReadEntity()
    local ownerType = net.ReadString()
    local ownerSteam = net.ReadString()
    local ownerNick = net.ReadString()
    local factionName = net.ReadString()
    local locked = net.ReadBool()

    if not IsValid(veh) then return end

    -- Kept for compatibility with HUD/SWEP code that reads Lua fields.
    veh.VK_OwnerType = ownerType ~= "" and ownerType or nil
    veh.VK_OwnerSteam = ownerSteam ~= "" and ownerSteam or nil
    veh.VK_OwnerNick = ownerNick ~= "" and ownerNick or nil
    veh.VK_FactionName = factionName ~= "" and factionName or nil
    veh.VK_Locked = locked
end)

net.Receive(NET_RESULT, function()
    local success = net.ReadBool()
    local message = net.ReadString()
    notify(message, success)
end)

net.Receive(NET_KEYS_SYNC, function()
    VK.ClientKeys = net.ReadTable() or {}
end)

local ownerMenuFrame

local function makeButton(parent, text, color)
    local button = vgui.Create("DButton", parent)
    button:SetText(text)
    button:SetFont("VK_HUD_Small")
    button:SetTextColor(color_white)
    button.Paint = function(self, w, h)
        local drawColor = self:IsHovered() and Color(
            math.min(color.r + 20, 255),
            math.min(color.g + 20, 255),
            math.min(color.b + 20, 255)
        ) or color
        draw.RoundedBox(4, 0, 0, w, h, drawColor)
    end
    return button
end

function VK.OpenOwnerKeyMenu(veh, players)
    if not IsValid(veh) then return end

    if IsValid(ownerMenuFrame) then ownerMenuFrame:Remove() end

    local frame = vgui.Create("DFrame")
    frame:SetTitle("Ключи от машин: " .. VK.GetVehicleDisplayName(veh))
    frame:SetSize(430, 500)
    frame:Center()
    frame:MakePopup()
    ownerMenuFrame = frame

    local hint = vgui.Create("DLabel", frame)
    hint:Dock(TOP)
    hint:DockMargin(10, 5, 10, 4)
    hint:SetTall(34)
    hint:SetWrap(true)
    hint:SetText("Ключ открывает все машины этого владельца. Управлять ключами можно только рядом с личным транспортом.")
    hint:SetTextColor(VK.COL.DIM)
    hint:SetFont("VK_HUD_Small")

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(6, 0, 6, 6)

    if #players == 0 then
        local empty = vgui.Create("DLabel", scroll)
        empty:Dock(TOP)
        empty:SetTall(36)
        empty:SetContentAlignment(5)
        empty:SetText("На сервере нет других игроков")
        empty:SetFont("VK_HUD_Normal")
        empty:SetTextColor(VK.COL.DIM)
        return
    end

    for _, playerData in ipairs(players) do
        local row = vgui.Create("DPanel", scroll)
        row:Dock(TOP)
        row:SetTall(44)
        row:DockMargin(0, 0, 0, 5)
        row.Paint = function(_, w, h)
            draw.RoundedBox(5, 0, 0, w, h, Color(30, 35, 48, 245))
        end

        local name = vgui.Create("DLabel", row)
        name:Dock(LEFT)
        name:DockMargin(10, 0, 6, 0)
        name:SetWide(205)
        name:SetContentAlignment(4)
        name:SetText(playerData.nick or "Неизвестно")
        name:SetFont("VK_HUD_Normal")
        name:SetTextColor(VK.COL.TEXT)

        local action
        if playerData.hasKey then
            action = makeButton(row, "Отозвать", VK.COL.DANGER)
            action.DoClick = function()
                net.Start(NET_REVOKE_KEY)
                    net.WriteEntity(veh)
                    net.WriteString(playerData.steam)
                net.SendToServer()
                frame:Close()
            end
        else
            action = makeButton(row, "Выдать ключ", VK.COL.SUCCESS)
            action.DoClick = function()
                net.Start(NET_GIVE_KEY)
                    net.WriteEntity(veh)
                    net.WriteString(playerData.steam)
                net.SendToServer()
                frame:Close()
            end
        end

        action:Dock(RIGHT)
        action:DockMargin(4, 6, 6, 6)
        action:SetWide(145)
    end
end

net.Receive(NET_SEND_LIST, function()
    local veh = net.ReadEntity()
    local players = net.ReadTable() or {}
    if IsValid(veh) then VK.OpenOwnerKeyMenu(veh, players) end
end)

-- Passive owner label + подсказки управления для игрока, смотрящего на
-- машину ВБЛИЗИ (заказ владельца: хинты по багажнику и замку при прицеле).
-- Краски пассивной плашки: статичные константы (§6.1.8); VK.COL отвечает
-- за семантику «владелец/замок», здесь — цвета подсказок
local VH_OWNER_PLAYER = Color(120, 200, 255)
local VH_OWNER_FACTION = Color(255, 195, 120)
local VH_TRUNK = Color(255, 205, 90)
local VH_TRUNK_HINT = Color(210, 200, 170)
local VH_KEY_HINT = Color(200, 205, 215, 230)

hook.Add("HUDPaint", "VK_PassiveVehicleOwnerHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local trace = (GRM and GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(ply, 0.05) or ply:GetEyeTrace()
    if not trace then return end
    local veh = trace.Entity
    if not VK.IsVehicle(veh) then return end
    if ply:GetPos():DistToSqr(veh:GetPos()) > (VK.HUD_RANGE or 220) ^ 2 then return end

    --[[ Новый модуль взаимодействия рисует свою подсказку рядом с
         машиной. Если оставить и эту, получим ДВЕ плашки об одном и том
         же: старая по центру экрана, новая у объекта. Пока модуль
         включён — молчим, он главный. ]]
    if GRM.Interact then
        local cv = GetConVar("grm_cl_interact")
        if not cv or cv:GetInt() ~= 0 then return end
    end

    local ownerType, _, ownerNick, factionName, locked = VK.GetOwnerState(veh)
    local trunkOpen = veh:GetNW2Bool("VK_TrunkOpen", false)
    local x, y = ScrW() / 2, ScrH() / 2 + 56

    -- Название техники (GetVehicleDisplayName) убрано по заказу владельца:
    -- остаются владелец, статус замка и подсказки управления.
    if ownerType ~= "" or locked then
        local ownerText, ownerColor
        if ownerType == VK.OWNER_TYPE.PLAYER then
            ownerText = "Владелец: " .. (ownerNick ~= "" and ownerNick or "Неизвестно")
            ownerColor = VH_OWNER_PLAYER
        elseif ownerType == VK.OWNER_TYPE.FACTION then
            ownerText = "Фракция: " .. (factionName ~= "" and factionName or "Неизвестно")
            ownerColor = VH_OWNER_FACTION
        else
            ownerText = "Без владельца"
            ownerColor = VK.COL.DIM
        end
        draw.SimpleText(ownerText, "VK_HUD_Title", x, y, ownerColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(locked and "ЗАБЛОКИРОВАНА" or "РАЗБЛОКИРОВАНА", "VK_HUD_Normal", x, y + 24,
            locked and VK.COL.DANGER or VK.COL.SUCCESS, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        y = y + 24
    end

    -- Подсказки управления — у ЛЮБОЙ машины при взгляде вблизи (220 юн).
    if trunkOpen then
        draw.SimpleText("● БАГАЖНИК ОТКРЫТ", "VK_HUD_Normal", x, y + 20, VH_TRUNK, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("E или /trunk — окно   ·   крышку закройте в окне", "VK_HUD_Small", x, y + 40, VH_TRUNK_HINT, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    else
        draw.SimpleText("Ключи: ЛКМ/ПКМ — замок  •  /trunk — багажник", "VK_HUD_Small", x, y + 20, VH_KEY_HINT, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end)

print("[VK] Vehicle key client loaded")
