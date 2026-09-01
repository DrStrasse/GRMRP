AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

--[[ ВИД РОВНО КАК У ТОЧКИ ПОГРУЗКИ ЛОГИСТИКИ.

     Владелец указал её эталоном, и это правильно: маркеры сервера должны
     выглядеть одинаково, иначе игрок не понимает, что перед ним объект
     одного класса. Сочетание то же самое —

         RENDERMODE_TRANSCOLOR + models/debug/debugwhite + красный + 127

     debugwhite это чистый белый без деталей: умножение на цвет даёт
     ровную заливку без грязи от текстуры. Альфа 127 — те самые 50%
     прозрачности из заказа. ]]
local MARKER_COLOR = Color(255, 0, 0, 127)

function ENT:Initialize()
    --[[ Берём первую модель, которая реально есть на сервере. Без
         проверки отсутствующая модель дала бы невидимый маркер, и точку
         квеста нельзя было бы найти на карте. ]]
    local model = self.CheckpointModel
    for _, candidate in ipairs(self.CheckpointModelFallbacks or {}) do
        if util.IsValidModel(candidate) then model = candidate break end
    end
    self:SetModel(model)

    --[[ Физики нет намеренно: это метка, а не предмет. Иначе игроки
         сдвинут её физганом, и точка квеста уедет с места. ]]
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_WORLD)

    self:SetRenderMode(RENDERMODE_TRANSCOLOR)
    self:SetMaterial("models/debug/debugwhite")
    self:SetColor(MARKER_COLOR)

    if self:GetRadius() <= 0 then self:SetRadius(96) end
    if self:GetLabel() == "" then self:SetLabel("Чекпоинт") end

    -- Прячем сразу: до первого Think маркер иначе успеет мелькнуть у всех.
    self:UpdateTransmit()
end

--[[ ПРОВЕРКА ЗАХОДА В ЗОНУ.

     Своим Think с шагом 0.25 сек, а не каждый кадр: точек на карте
     бывает много, а зона радиусом в десятки юнитов — четырёх проверок в
     секунду хватает с запасом. Через StartTouch нельзя: у маркера нет
     физики (иначе его сдвинут физганом), а значит и касаний. ]]
function ENT:Think()
    self:NextThink(CurTime() + 0.25)

    --[[ Пересчёт видимости раз в секунду: список игроков и их квесты
         меняются редко, а точек на карте бывает много. ]]
    if (self._grmNextTransmit or 0) <= CurTime() then
        self._grmNextTransmit = CurTime() + 1
        self:UpdateTransmit()
    end

    local radius = math.max(16, tonumber(self:GetRadius()) or 96)
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive()
            and ply:GetPos():DistToSqr(self:GetPos()) <= radius * radius then
            self:TryReach(ply)
        end
    end
    return true
end

--[[ СЕТЕВАЯ ПРИВАТНОСТЬ (заказ владельца 30.08).

     Клиентская проверка в ENT:Draw уже не рисует чужой маркер, но сама
     энтити всё равно приходила бы всем: её видно чит-клиентом и
     инструментами вроде «показать все entity». Для квестовой точки это
     подсказка «здесь дают деньги», которую посторонним знать незачем.

     SetPreventTransmit прячет энтити на уровне СЕТИ: чужой клиент про
     неё просто не узнаёт. Пересчитываем раз в секунду, а не каждый тик —
     список игроков меняется редко, а точек на карте бывает много.

     Право «видеть» = квест активен у этого игрока. Ту же проверку
     делает сервер при срабатывании, так что расхождения между
     «вижу» и «сработает» не будет. ]]
function ENT:MaySee(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    local Q = GRM and GRM.Quests
    if not (Q and Q.CheckpointVisibleFor) then return true end
    return Q.CheckpointVisibleFor(ply, self:GetQuestID(), self:GetCheckpointID())
end

function ENT:UpdateTransmit()
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            -- true = НЕ передавать этому игроку
            self:SetPreventTransmit(ply, not self:MaySee(ply))
        end
    end
end

--- Игрок вошёл в зону: сообщаем ядру квестов.
function ENT:TryReach(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    local Q = GRM and GRM.Quests
    if not (Q and Q.ReachCheckpoint) then return end
    Q.ReachCheckpoint(ply, self:GetQuestID(), self:GetCheckpointID(), self)
end
