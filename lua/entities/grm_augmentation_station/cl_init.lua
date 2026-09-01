include("shared.lua")

function ENT:Draw()
    self:DrawModel()

    -- Отображение информации о станции
    local pos = self:GetPos() + Vector(0, 0, 60)
    -- Метка следует за камерой рендера, а не за поворотом игрока
    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.15)
        draw.SimpleTextOutlined(
            self:GetStationName() or "Augmentation Station",
            "DermaLarge",
            0, 0,
            Color(0, 200, 255),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            2,
            Color(0, 0, 0)
        )

        local status = self:GetActive() and "[АКТИВНА]" or "[НЕАКТИВНА]"
        local statusColor = self:GetActive() and Color(100, 255, 100) or Color(255, 100, 100)
        draw.SimpleTextOutlined(
            status,
            "DermaDefault",
            0, 30,
            statusColor,
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            Color(0, 0, 0)
        )

        draw.SimpleTextOutlined(
            "Нажмите E для использования",
            "DermaDefault",
            0, 50,
            Color(200, 200, 200),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            Color(0, 0, 0)
        )
    cam.End3D2D()
end
