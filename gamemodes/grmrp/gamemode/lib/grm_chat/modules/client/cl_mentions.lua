--[[ Модуль (client): УПОМИНАНИЯ (EasyChat.mentions по мотивам, но на нашей
    ленте): чужая строка с нашим ником → перекрас line.color + короткий сигнал
    (cvar grmrp_chat_mention_sound, по умолчанию вкл). Только чат-окно/лента,
    никаких модалок — игровой ввод не ломается (правило веч.-10). ]]
if not (GRMRPChat and hook and hook.Add) then return end

local cv = GetConVar and GetConVar("grmrp_chat_mention_sound")
    or (CreateConVar and CreateConVar("grmrp_chat_mention_sound", "1",
        FCVAR_ARCHIVE and { FCVAR_ARCHIVE } or nil,
        "Звук при упоминании вашего ника"))

local function sndCv()
    return cv ~= nil and cv:GetBool()
end

hook.Add("GRMRPChat_Message", "grm_chat.mentions", function(line)
    if not (line and GRMRPChat.MentionHit) then return end
    local me = LocalPlayer and LocalPlayer()
    if not (me and me.IsValid and me:IsValid()) then return end
    if line.mine then return end
    local nick = GRMRPChat.Sanitize and GRMRPChat.Sanitize(me:Nick(), 64)
        or tostring(me:Nick())
    if not GRMRPChat.MentionHit(line.name or "", nick, line.text or "") then
        return
    end
    line.mention = true
    line.color = Color(255, 214, 102)
    if sndCv() and surface and surface.PlaySound then
        surface.PlaySound("buttons/button15.wav")
    end
end)
