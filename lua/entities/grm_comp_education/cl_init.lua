--[[--------------------------------------------------------------------
    grm_comp_education — cl_init.lua

    Рисует табличку на корпусе. Само окно рабочего места собирает
    GRM.Education.OpenFrame() по сети (GRM_Edu_Open).
----------------------------------------------------------------------]]
include("shared.lua")

local CC = {
    bg    = Color(12, 18, 30, 240),
    gold  = Color(245, 205, 80),
    text  = Color(226, 234, 248),
    dim   = Color(150, 170, 200),
}

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + self:GetUp() * 24 + self:GetForward() * 2
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), 90)
    ang:RotateAroundAxis(ang:Forward(), 90)

    cam.Start3D2D(pos, ang, 0.08)
        draw.RoundedBox(6, -150, -50, 300, 100, CC.bg)
        -- Заголовок задаётся инструментом «GRM Служебное оборудование»
        local title = self:GetComputerName()
        if title == "" then title = "УЧРЕЖДЕНИЕ ОБРАЗОВАНИЯ" end
        draw.SimpleText(title, "DermaDefaultBold", 0, -25, CC.gold,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Выписка государственных дипломов", "DermaDefault", 0, -5, CC.text,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Нажмите [E] для входа в систему", "DermaDefault", 0, 20, CC.dim,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
