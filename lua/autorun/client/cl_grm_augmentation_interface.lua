-- GRM Augmentation Interface: отдельный экран управления имплантами.
if not CLIENT then return end
GRM = GRM or {}
GRM.AugmentationUI = GRM.AugmentationUI or {}
local UI = GRM.AugmentationUI

surface.CreateFont("GRMAugUI_Title", {font="Roboto", size=25, weight=800, extended=true})
surface.CreateFont("GRMAugUI_Sub", {font="Roboto", size=15, weight=700, extended=true})
surface.CreateFont("GRMAugUI_Text", {font="Roboto", size=14, weight=500, extended=true})
surface.CreateFont("GRMAugUI_Small", {font="Roboto", size=12, weight=500, extended=true})
local C={bg=Color(13,19,28,252), head=Color(21,30,43), panel=Color(25,36,51), slot=Color(31,46,64), accent=Color(55,164,247), green=Color(58,205,119), warn=Color(247,181,61), red=Color(220,79,78), text=Color(235,241,248), dim=Color(151,168,187)}
local frame
local function chips()
    return (GRM.AugHUD and GRM.AugHUD.CachedChips) or {}
end
local function installedChips()
    local out={}
    for _,c in ipairs(chips()) do if c.implanted then out[#out+1]=c end end
    return out
end
local function activeChips()
    local out={}
    for _,c in ipairs(installedChips()) do if c.active ~= false then out[#out+1]=c end end
    return out
end
local function button(parent, text, x, y, w, fn, color)
    local b=vgui.Create("DButton",parent); b:SetPos(x,y); b:SetSize(w,36); b:SetText("")
    b.Paint=function(self,pw,ph) draw.RoundedBox(5,0,0,pw,ph,self:IsHovered() and Color(75,180,255) or (color or C.accent)); draw.SimpleText(text,"GRMAugUI_Text",pw/2,ph/2,C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER) end
    b.DoClick=fn; return b
end
function UI.OpenReprogram(chip)
    local f=vgui.Create("DFrame"); f:SetTitle(""); f:SetSize(math.min(700,ScrW()-80),math.min(560,ScrH()-80)); f:Center(); f:MakePopup(); f:ShowCloseButton(false)
    f.Paint=function(self,w,h) draw.RoundedBox(8,0,0,w,h,C.bg); draw.RoundedBoxEx(8,0,0,w,52,C.head,true,true,false,false); draw.SimpleText("ПЕРЕПРОГРАММИРОВАНИЕ ЧИПА","GRMAugUI_Title",18,22,C.text); draw.SimpleText(chip.name or "Чип","GRMAugUI_Small",18,42,C.accent) end
    local close=vgui.Create("DButton",f); close:SetPos(f:GetWide()-38,12); close:SetSize(25,25); close:SetText("X"); close:SetTextColor(C.text); close.DoClick=function() f:Close() end
    local y=72; local controls={}
    local cfg=(GRM.AugChips and GRM.AugChips.Config and GRM.AugChips.Config.Modifiers) or {}
    local modifierKeys={}
    for key in pairs(chip.modifiers or {}) do modifierKeys[key]=true end
    modifierKeys.doorHack=true
    for key,val in pairs(modifierKeys) do
        val=(chip.modifiers or {})[key]
        local c=cfg[key]; if c then
            local l=vgui.Create("DLabel",f); l:SetPos(20,y); l:SetSize(180,24); l:SetText(c.name or key);
            local sl=vgui.Create("DNumSlider",f); sl:SetPos(200,y); sl:SetSize(390,30); sl:SetText(""); sl:SetMin(c.minValue or 0); sl:SetMax(c.maxValue or 100); sl:SetDecimals(c.options and 0 or 2); if not c.options then sl:SetValue(tonumber(val) or c.defaultValue or 0) else sl:Remove(); sl=vgui.Create("DComboBox",f); sl:SetPos(200,y); sl:SetSize(390,30); for _,opt in ipairs(c.options) do sl:AddChoice(opt,opt) end; local id=1; for n=1,#(c.options or {}) do if sl:GetOptionData(n)==val then id=n break end end; sl:ChooseOptionID(id) end
            controls[key]={cfg=c,slider=sl,value=val}; y=y+42
        end
    end
    local save=vgui.Create("DButton",f); save:SetPos(20,450); save:SetSize(570,40); save:SetText("СОХРАНИТЬ И ПРИМЕНИТЬ")
    save.DoClick=function() local mods={}; for k,e in pairs(controls) do
        -- Для комбобокса (options) берём ВЫБРАННОЕ значение, а не старое из chip.modifiers
        mods[k] = e.cfg.options and (isfunction(e.slider.GetSelected) and e.slider:GetSelected() or e.value) or e.slider:GetValue()
    end; net.Start("GRM_AugChip_Reprogram"); net.WriteString(chip.id or ""); net.WriteTable(mods); net.SendToServer(); f:Close() end
end

--[[ СИНХРОНИЗАЦИЮ ЧИПОВ ПРИНИМАЕТ ОДИН МОДУЛЬ — cl_grm_augmentations_hud.
     Здесь стоял ВТОРОЙ net.Receive на то же сообщение. В GMod второй
     ресивер молча заменяет первый, и кто победит — решает алфавитный
     порядок загрузки файлов. Наш вариант ещё и не выставлял LastUpdate,
     поэтому при перестановке имён файлов HUD переставал видеть свежесть
     данных. Держим один обработчик, а обновление ловим хуком, который он
     же и запускает. ]]
-- Перерисовку окна по свежим данным делает хук GRM_AugUI_RefreshState в
-- конце этого файла; отдельный обработчик здесь не нужен.

function UI.Open()
    net.Start("GRM_AugChip_RequestSync"); net.SendToServer()
    if IsValid(frame) then frame:MakePopup(); return end
    frame=vgui.Create("DFrame"); frame:SetTitle(""); frame:SetSize(math.min(1080,ScrW()-70),math.min(700,ScrH()-70)); frame:Center(); frame:MakePopup(); frame:ShowCloseButton(false)
    frame.Paint=function(self,w,h)
        draw.RoundedBox(9,0,0,w,h,C.bg); draw.RoundedBoxEx(9,0,0,w,58,C.head,true,true,false,false)
        draw.SimpleText("АУГМЕНТАЦИИ", "GRMAugUI_Title",22,22,C.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
        draw.SimpleText("GRM // CYBERNETIC CONTROL", "GRMAugUI_Small",22,43,C.accent,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
        draw.SimpleText("BIO-LINK ONLINE", "GRMAugUI_Small",w-55,22,C.green,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER)
    end
    local close=vgui.Create("DButton",frame); close:SetPos(frame:GetWide()-42,14); close:SetSize(28,28); close:SetText("X"); close:SetTextColor(C.text); close.DoClick=function() frame:Close() end
    local sheet=vgui.Create("DPropertySheet",frame); sheet:Dock(FILL); sheet:DockMargin(15,68,15,15)
    local function page(title, paint)
        local p=vgui.Create("DPanel"); p:Dock(FILL); p.Paint=paint or function(self,w,h) draw.RoundedBox(6,0,0,w,h,C.panel) end; sheet:AddSheet(title,p,"icon16/cog.png"); return p
    end
    local overview=page("Обзор")
    overview.Paint=function(self,w,h) draw.RoundedBox(6,0,0,w,h,C.panel); draw.SimpleText("СОСТОЯНИЕ СИСТЕМЫ", "GRMAugUI_Sub",25,28,C.text); draw.SimpleText("Имплантированные чипы: "..#chips(),"GRMAugUI_Text",25,62,C.dim); draw.SimpleText("Канал биосвязи: АКТИВЕН","GRMAugUI_Text",25,91,C.green); draw.SimpleText("Стабильность: 100%","GRMAugUI_Text",25,120,C.green); draw.SimpleText("Выберите вкладку для управления слотами и эффектами.","GRMAugUI_Text",25,174,C.dim) end
    local active=page("Активные чипы")
    active.Paint=function(self,w,h) draw.RoundedBox(6,0,0,w,h,C.panel); local y=22; local list=chips(); if #list==0 then draw.SimpleText("Активных чипов нет","GRMAugUI_Text",25,30,C.dim); return end; for _,chip in ipairs(list) do if chip.implanted and chip.active ~= false then draw.RoundedBox(5,18,y,w-36,66,C.slot); draw.SimpleText(chip.name or "Чип","GRMAugUI_Sub",34,y+20,C.text); draw.SimpleText((chip.category == "experimental" and "ЭКСПЕРИМЕНТАЛЬНЫЙ" or chip.category == "military" and "ВОЕННЫЙ" or chip.category == "service" and "СЛУЖЕБНЫЙ" or "ГРАЖДАНСКИЙ").."  //  уровень "..(chip.level or 1),"GRMAugUI_Small",34,y+44,C.dim); draw.SimpleText(chip.hasComplications and "ОСЛОЖНЕНИЯ" or "ONLINE","GRMAugUI_Small",w-35,y+30,chip.hasComplications and C.warn or C.green,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER); y=y+78 end end end
    local slots=page("Слоты")
    slots.Paint=function(self,w,h) draw.RoundedBox(6,0,0,w,h,C.panel); draw.SimpleText("СЛОТЫ АУГМЕНТАЦИЙ", "GRMAugUI_Sub",24,25,C.text); draw.SimpleText("Подготовка отдельной системы слотов для головы, нервной системы, корпуса и конечностей.","GRMAugUI_Text",24,60,C.dim); for i=1,5 do local x=24+(i-1)*145; local chip=installedChips()[i]; draw.RoundedBox(5,x,115,125,120,C.slot); surface.SetDrawColor(chip and chip.implanted and C.green or Color(70,86,110,190)); surface.DrawOutlinedRect(x,115,125,120,chip and chip.implanted and 2 or 1); draw.SimpleText("СЛОТ "..i,"GRMAugUI_Small",x+12,135,C.dim); if chip and chip.implanted then draw.SimpleText(string.sub(chip.name or "ЧИП",1,16),"GRMAugUI_Small",x+12,160,C.text); draw.SimpleText(chip.active == false and "DEACTIVATED" or "ONLINE","GRMAugUI_Text",x+12,184,chip.active == false and C.warn or C.green) else draw.SimpleText("СВОБОДЕН","GRMAugUI_Text",x+12,172,C.green) end end end
    local slotButtons = {}
    for i=1,5 do
        local b=vgui.Create("DButton",slots); b:SetPos(24+(i-1)*145,115); b:SetSize(125,120); b:SetText(""); b:SetZPos(5)
        b.Paint=function(self,w,h) if self:IsHovered() then draw.RoundedBox(4,4,h-28,w-8,22,Color(50,170,220,190)); draw.SimpleText("ДЕЙСТВИЯ","GRMAugUI_Small",w/2,h-17,C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER) end end
        b.DoClick=function()
            local chip=installedChips()[i]
            if not chip or not chip.implanted then return end
            local menu=DermaMenu()
            menu:AddOption("Снять чип и вернуть в инвентарь",function() net.Start("GRM_AugChip_ExtractByUI"); net.WriteString(chip.id or ""); net.SendToServer(); timer.Simple(0.2,function() if IsValid(frame) then frame:Close(); UI.Open() end end) end):SetIcon("icon16/arrow_down.png")
            menu:AddOption(chip.active == false and "Активировать чип" or "Деактивировать чип",function() net.Start("GRM_AugChip_Toggle"); net.WriteString(chip.id or ""); net.SendToServer(); timer.Simple(0.2,function() if IsValid(frame) then frame:Close(); UI.Open() end end) end):SetIcon("icon16/lightbulb.png")
            menu:AddOption("Перепрограммировать",function()
                UI.OpenReprogram(chip)
            end):SetIcon("icon16/cog_edit.png")
            menu:AddOption("Отмена",function() end)
            menu:Open()
        end
        b.DoRightClick = b.DoClick
    end

    local effects=page("Эффекты")
    effects.Paint=function(self,w,h) draw.RoundedBox(6,0,0,w,h,C.panel); draw.SimpleText("АКТИВНЫЕ ЭФФЕКТЫ", "GRMAugUI_Sub",24,25,C.text); local y=65; for _,chip in ipairs(activeChips()) do for key,val in pairs(chip.modifiers or {}) do draw.SimpleText((key or "effect")..": "..tostring(val),"GRMAugUI_Text",30,y,C.green); y=y+27 end end end
end
concommand.Add("grm_augmentations",UI.Open)
concommand.Add("grm_augments",UI.Open)
hook.Add("GRMRPChat_ClientCommand", "GRM_AugmentationUI_Command", function(ply, text)
    local pack = { tostring(text or ""), SkipPlayerSay = false }
        local text=istable(pack) and (pack.text or pack[1]) or pack; if ply==LocalPlayer() and string.lower(string.Trim(tostring(text or "")))=="/augmentations" then UI.Open(); return true end
    if pack.SkipPlayerSay == true then return true end
end)
print("[GRM AugmentationUI] loaded")

hook.Add("OnPlayerChat", "GRM_AugmentationUI_OnChat", function(ply, text)
    if ply ~= LocalPlayer() then return end
    local command = string.lower(string.Trim(tostring(text or "")))
    if command == "/augmentations" or command == "/augment" then UI.Open() end
end)

-- Быстрое контекстное меню аугментаций (C/контекст): действия без открытия инвентаря.
hook.Add("OnContextMenu", "GRM_Augmentation_ContextActions", function()
    if not GRM.AugHUD or #GRM.AugHUD.GetActiveChips() == 0 then return end
    local m=DermaMenu()
    m:AddOption("Открыть Биоконтроль", function() UI.Open() end):SetIcon("icon16/application_view_tile.png")
    m:AddOption("Открыть инвентарь", function() if GRM.Inventory and GRM.Inventory.OpenGUI then GRM.Inventory.OpenGUI() end end):SetIcon("icon16/box.png")
    m:AddOption("Настройки аугментаций", function() UI.Open(); timer.Simple(0,function() end) end):SetIcon("icon16/cog_edit.png")
    m:AddOption("Деактивировать все чипы", function()
        for _,chip in ipairs(GRM.AugHUD.CachedChips or {}) do if chip.implanted and chip.active ~= false then net.Start("GRM_AugChip_Toggle"); net.WriteString(chip.id or ""); net.SendToServer() end end
    end):SetIcon("icon16/lightbulb_off.png")
    m:AddOption("Активировать все чипы", function()
        for _,chip in ipairs(GRM.AugHUD.CachedChips or {}) do if chip.implanted and chip.active == false then net.Start("GRM_AugChip_Toggle"); net.WriteString(chip.id or ""); net.SendToServer() end end
    end):SetIcon("icon16/lightbulb.png")
    m:AddOption("Обновить синхронизацию", function() RunConsoleCommand("grm_aughud_refresh") end):SetIcon("icon16/arrow_refresh.png")
    m:Open()
    return true
end)


-- Обновление состояния НЕ пересоздаёт окно (иначе цикл: Open → RequestSync →
-- Sync → hook.Run → Close+Open → ... — окно вечно пересоздаётся и всегда
-- показывает первую вкладку). Paint-функции вкладок читают кэш чипов
-- (chips()) динамически каждый кадр — достаточно просто перерисовать.
hook.Add("GRM_AugmentationStateUpdated", "GRM_AugUI_RefreshState", function()
    if IsValid(frame) then
        pcall(function() frame:InvalidateLayout() end)
    end
end)
