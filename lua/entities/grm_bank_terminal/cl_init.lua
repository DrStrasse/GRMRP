include("entities/grm_bank_terminal/shared.lua")

function ENT:Draw()
    self:DrawModel()
    local pos = self:GetPos() + Vector(0, 0, 55)
    local ang = EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    local isIncass = self:GetNWBool("GRM_IncassLocked", false)

    cam.Start3D2D(pos, Angle(0, ang.y, 90), 0.09)
        if isIncass then
            draw.SimpleTextOutlined("[!] ИНКАССАЦИЯ", "DermaLarge", 0, 0, Color(245, 180, 50),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
            draw.SimpleTextOutlined("Терминал на обслуживании", "DermaDefaultBold", 0, 30,
                Color(255, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        else
            local number=self:GetNWInt("GRM_ATMNumber",0);draw.SimpleTextOutlined(number>0 and("БАНКОМАТ №"..number)or"БАНК GRM","DermaLarge",0,0,Color(100,220,120),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
            draw.SimpleTextOutlined("[E] Операции со счетами", "DermaDefaultBold", 0, 30,
                Color(220, 220, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        end
    cam.End3D2D()
end
