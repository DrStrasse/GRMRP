include("shared.lua")

function SWEP:DrawHUD()
    -- Подсказка при наведении на игрока
    local trace = self.Owner:GetEyeTrace()
    if trace.Entity:IsPlayer() and trace.Entity:Alive() then
        local ply = trace.Entity

        draw.SimpleTextOutlined(
            "Игрок: " .. ply:Nick(),
            "DermaDefault",
            ScrW() / 2, ScrH() / 2 + 50,
            Color(255, 255, 255),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            Color(0, 0, 0)
        )

        draw.SimpleTextOutlined(
            "ЛКМ: Обыск",
            "DermaDefault",
            ScrW() / 2, ScrH() / 2 + 70,
            Color(100, 220, 100),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            Color(0, 0, 0)
        )

        draw.SimpleTextOutlined(
            "ПКМ: Документы",
            "DermaDefault",
            ScrW() / 2, ScrH() / 2 + 90,
            Color(100, 200, 255),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            Color(0, 0, 0)
        )
    end
end
