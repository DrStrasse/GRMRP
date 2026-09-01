--[[ Чат-лента EasyChat не должна заезжать на панель состояния GRM. ]]
if not CLIENT then return end

hook.Add("ECHUDBoundsUpdate", "GRM_ChatAboveStatus", function(x, y, w, h)
    local r = GRM and GRM.HUD and GRM.HUD.StatusRect
    if not istable(r) then return end
    local gap = 14
    local bottom = math.max(120, (tonumber(r.y) or (ScrH() * 0.62)) - gap)
    local nh = math.max(140, tonumber(h) or 220)
    local ny = bottom - nh
    if ny < 96 then
        ny = 96
        nh = math.max(120, bottom - ny)
    end
    return x, ny, w, nh
end)
