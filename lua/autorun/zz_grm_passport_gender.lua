--[[ Паспорт берёт пол с персонажа (GRM_Gender / слот). ]]
if SERVER then AddCSLuaFile() end
if not SERVER then return end

local function genderOf(ply)
    if not IsValid(ply) then return "Мужской" end
    local nw = ply:GetNWString("GRM_Gender", "")
    if nw == "Женский" or nw == "female" then return "Женский" end
    if nw == "Мужской" or nw == "male" then return "Мужской" end
    if GRM.Char and GRM.Char.Get then
        local c = GRM.Char.Get(ply)
        if istable(c) then
            local g = GRM.Char.NormalizeGender and GRM.Char.NormalizeGender(c.gender or c.model) or c.gender
            if g == "female" then return "Женский" end
        end
    end
    return "Мужской"
end

local function apply()
    local DOC = GRM and GRM.Documents
    if not (DOC and DOC.EnsurePassport) then return false end
    if DOC._grmGenderWrap then return true end
    local old = DOC.EnsurePassport
    DOC.EnsurePassport = function(ply)
        local p = old(ply)
        if istable(p) and IsValid(ply) then
            local g = genderOf(ply)
            if p.gender ~= g then
                p.gender = g
                p.updated = os.time()
                if DOC.SaveRegistry then DOC.SaveRegistry("passport gender sync") end
            end
        end
        return p
    end
    DOC._grmGenderWrap = true
    return true
end

timer.Create("GRM_PassportGender_Wrap", 1, 20, function()
    if apply() then timer.Remove("GRM_PassportGender_Wrap") end
end)
