--[[--------------------------------------------------------------------
    GRM Quest Dialogue v1.0 — серверный разговор у NPC.

    Паттерн Talksmith (SYSTEMS 2): клиент шлёт индекс ответа,
    сервер проверяет условия, выполняет действие, отдаёт следующую реплику.
    Флаги персонажа живут отдельно от прогресса квеста.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Quests = GRM.Quests or {}
local Q = GRM.Quests
Q.Flags = Q.Flags or {}

local NET_NODE = "GRM_Quest_DlgNode"
local NET_PICK = "GRM_Quest_DlgPick"

local function trim(s, n)
    s = string.Trim(tostring(s or ""))
    if GRM.Utf8Sub then return GRM.Utf8Sub(s, n or 160) end
    return string.sub(s, 1, n or 160)
end

local function charKey(ply)
    if Q.CharacterKey then return Q.CharacterKey(ply) end
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return tostring(ply:SteamID64()) .. ":char1"
end

function Q.GetFlag(plyOrKey, name)
    local key = IsValid(plyOrKey) and charKey(plyOrKey) or tostring(plyOrKey or "")
    name = string.lower(trim(name, 64))
    if key == "" or name == "" then return false end
    local bag = Q.Flags[key]
    return istable(bag) and bag[name] == true
end

function Q.SetFlag(plyOrKey, name, on)
    local key = IsValid(plyOrKey) and charKey(plyOrKey) or tostring(plyOrKey or "")
    name = string.lower(trim(name, 64))
    if key == "" or name == "" then return false end
    Q.Flags[key] = Q.Flags[key] or {}
    if on then Q.Flags[key][name] = true else Q.Flags[key][name] = nil end
    if SERVER and Q.SaveFlags then Q.SaveFlags() end
    return true
end

--- cond: "" | "flag:x" | "!flag:x" | "item:id" | "money:N" | "fac:Name" | "done:quest" | "active:quest"
function Q.EvalCondition(ply, cond)
    cond = string.Trim(tostring(cond or ""))
    if cond == "" then return true end
    local kind, rest = cond:match("^(!?[%w_]+):(.+)$")
    if not kind then return true end
    rest = string.Trim(rest)
    if kind == "flag" then return Q.GetFlag(ply, rest) end
    if kind == "!flag" then return not Q.GetFlag(ply, rest) end
    if kind == "item" then
        local n = GRM.Inventory and GRM.Inventory.CountItem and tonumber(GRM.Inventory.CountItem(ply, rest)) or 0
        return n > 0
    end
    if kind == "money" then
        local need = math.max(0, tonumber(rest) or 0)
        local have = (GRM.GetBalance and GRM.GetBalance(ply) or 0)
            + ((GRM.Economy and GRM.Economy.BankBalance) and GRM.Economy.BankBalance(ply) or 0)
        return have >= need
    end
    if kind == "fac" then
        return string.lower(ply:GetNWString("GRM_Faction", "") or "") == string.lower(rest)
    end
    if kind == "done" or kind == "active" then
        local p = Q.GetProgress and Q.GetProgress(ply, rest)
        if kind == "done" then return istable(p) and p.status == "completed" end
        return istable(p) and p.status == "active"
    end
    return true
end

if SERVER then
    util.AddNetworkString(NET_NODE)
    util.AddNetworkString(NET_PICK)

    Q.FlagFile = (Q.DataDir or "grm_quests") .. "/flags.json"

    function Q.SaveFlags()
        if not Q.DataDir then return false end
        if not file.IsDir(Q.DataDir, "DATA") then file.CreateDir(Q.DataDir) end
        local recs = {}
        for key, flags in pairs(Q.Flags) do
            if istable(flags) and next(flags) then recs[#recs + 1] = { key = key, flags = flags } end
        end
        local ok, raw = pcall(util.TableToJSON, { version = 1, records = recs }, true)
        if not (ok and isstring(raw)) then return false end
        file.Write(Q.FlagFile, raw)
        return true
    end

    function Q.LoadFlags()
        Q.Flags = {}
        if not file.Exists(Q.FlagFile, "DATA") then return true end
        local ok, t = pcall(util.JSONToTable, file.Read(Q.FlagFile, "DATA") or "", false, true)
        if not (ok and istable(t)) then return false end
        for _, rec in ipairs(t.records or {}) do
            if istable(rec) and isstring(rec.key) then Q.Flags[rec.key] = istable(rec.flags) and rec.flags or {} end
        end
        return true
    end

    local function nodesOf(def, phase)
        if not def then return {} end
        local dlg = def.dialogue or {}
        local pack = dlg[phase] or {}
        if isstring(pack) then
            if pack == "" then return {} end
            return { { id = phase .. "_1", speaker = "", text = pack, next = "", choices = {} } }
        end
        return istable(pack.nodes) and pack.nodes or pack
    end

    local function findNode(nodes, idOrIndex)
        if tonumber(idOrIndex) then
            return nodes[tonumber(idOrIndex)], tonumber(idOrIndex)
        end
        local want = tostring(idOrIndex or "")
        for i, n in ipairs(nodes) do
            if tostring(n.id or i) == want then return n, i end
        end
        return nodes[1], 1
    end

    local function visibleChoices(ply, node)
        local out = {}
        for i, ch in ipairs(istable(node.choices) and node.choices or {}) do
            if Q.EvalCondition(ply, ch.cond) then
                out[#out + 1] = {
                    i = i, text = trim(ch.text, 160),
                    action = trim(ch.action, 24),
                }
            end
        end
        return out
    end

    local function sendNode(ply, npcName, questID, phase, node, index, nodes)
        --[[ РЕПЛИКА КАК ТРИГГЕР ГРАФА (заказ владельца 29.08).

             Игрок дошёл до этой реплики — запускаем всё, что подключено
             к ней линией: ролик, музыку, награду. Именно это делает
             граф рабочим, а не декоративным.

             Зовём ДО отправки узла: ролик должен начаться вместе с
             репликой, а не после того, как игрок её закроет. ]]
        if Q.RunGraphFrom and node then
            local def = Q.Definitions and Q.Definitions[tostring(questID or "")]
            if def then
                local uid = tostring(node.id or "")
                if uid ~= "" then
                    --[[ Только связи с режимом «сразу». Остальные копим и
                         запустим, когда разговор закончится: иначе ролик
                         перекрывал текст, который игрок ещё не прочитал. ]]
                    Q.RunGraphFrom(ply, def, uid, nil, "now")

                    local sess = ply.GRMQuestDlg
                    if istable(sess) then
                        sess.pending = istable(sess.pending) and sess.pending or {}
                        --[[ Копим ID реплик, а не готовые эффекты: к концу
                             разговора квест могли пересохранить, и список
                             эффектов устарел бы. ]]
                        sess.pending[#sess.pending + 1] = uid
                    end
                end
            end
        end
        local choices = visibleChoices(ply, node)
        net.Start(NET_NODE)
            net.WriteString(tostring(npcName or ""))
            net.WriteString(tostring(questID or ""))
            net.WriteString(tostring(phase or "offer"))
            net.WriteUInt(index or 1, 8)
            net.WriteUInt(#nodes, 8)
            net.WriteString(trim(node.speaker, 80))
            net.WriteString(trim(node.text, 1200))
            net.WriteUInt(#choices, 4)
            for _, ch in ipairs(choices) do
                net.WriteUInt(ch.i, 8)
                net.WriteString(ch.text)
            end
        net.Send(ply)
    end

    function Q.BeginDialogue(ply, npc, questID, phase)
        if not (IsValid(ply) and IsValid(npc)) then return false end
        local def = Q.Definitions and Q.Definitions[tostring(questID or "")]
        local nodes = nodesOf(def, phase)
        if #nodes == 0 then return false end
        ply.GRMQuestDlg = {
            npc = npc, npcID = npc.GetQuestNPCID and npc:GetQuestNPCID() or "",
            npcName = npc.GetQuestNPCName and npc:GetQuestNPCName() or "NPC",
            questID = tostring(questID), phase = phase or "offer",
        }
        sendNode(ply, ply.GRMQuestDlg.npcName, questID, phase, nodes[1], 1, nodes)
        return true
    end

    --[[ Выпустить эффекты, отложенные до конца разговора.

         Зовём во ВСЕХ точках выхода: закрыл действием, дошёл до конца
         веток, оборвал по расстоянию. Пропустить хоть одну — и ролик
         не сыграет вовсе, что хуже прежнего поведения.

         Список чистим сразу: повторный вызов не должен запустить ролик
         второй раз. ]]
    --[[ Конец разговора: выпускаем и отложенные эффекты графа, и
         отложенный ролик (Q.FlushCutscene). Ролик «При принятии» ставится
         в очередь из Q.Start, потому что принятие происходит ВНУТРИ
         диалога — иначе титр лезет поверх открытой реплики. ]]
    --[[ КОНЕЦ РАЗГОВОРА: сначала эффекты, ПОТОМ выпуск очереди роликов.

         ПОРЯДОК ЗДЕСЬ КРИТИЧЕН, и на нём уже обожглись дважды.

         Гейт в cutscene() откладывает ролик, пока жив ply.GRMQuestDlg.
         На момент прогона отложенных эффектов сессия ЕЩЁ существует —
         её снимают строкой ниже, уже после выхода отсюда. Значит эффект
         «показать ролик» не рисует его сразу, а кладёт в очередь.

         Если выпустить очередь ПЕРВОЙ, она окажется пустой: ролик
         попадёт в неё шагом позже и останется там навсегда. Владелец:
         «кат-сцена не показывается при выборе верного диалога».

         Поэтому: прогоняем всё отложенное, а очередь выпускаем
         ПОСЛЕДНЕЙ — тогда в неё успевает попасть и то, что добавили
         сами эффекты.

         Выпуск стоит ВНЕ проверок на пустоту списков: ролик мог лечь в
         очередь из Q.Start (принятие квеста), где связей графа нет
         вообще. Ранний выход по пустому списку съел бы его. ]]
    local function flushPending(ply)
        if not IsValid(ply) then return end
        local sess = ply.GRMQuestDlg
        if istable(sess) and (istable(sess.pending) or istable(sess.pendingChoice)) then
            local list = istable(sess.pending) and sess.pending or {}
            local picks = sess.pendingChoice
            local def = Q.Definitions and Q.Definitions[tostring(sess.questID or "")]
            sess.pending = nil
            sess.pendingChoice = nil
            if def and Q.RunGraphFrom then
                for _, uid in ipairs(list) do
                    Q.RunGraphFrom(ply, def, uid, nil, "after")
                end
                -- Связи выбранных ответов: у каждой свой порт, иначе
                -- сработали бы варианты, которые игрок не выбирал.
                for _, rec in ipairs(istable(picks) and picks or {}) do
                    Q.RunGraphFrom(ply, def, rec.uid, nil, "after", rec.port)
                end
            end
        end
        -- ПОСЛЕДНИМ шагом: показываем всё, что накопилось в очереди.
        if Q.FlushCutscene then Q.FlushCutscene(ply) end
    end
    Q.FlushDialogueGraph = flushPending

    local function runAction(ply, def, action, arg)
        action = string.lower(trim(action, 24))
        arg = trim(arg, 96)
        if action == "" or action == "continue" then return "ok" end
        if action == "close" then return "close" end
        if action == "accept" then
            if def then
                local ok, why = Q.Start(ply, def.id)
                if not ok then
                    if GRM.Notify then GRM.Notify(ply, tostring(why), 255, 140, 100) end
                    return "stay"
                end
            end
            return "close"
        end
        if action == "set_flag" and arg ~= "" then Q.SetFlag(ply, arg, true) return "ok" end
        if action == "clear_flag" and arg ~= "" then Q.SetFlag(ply, arg, false) return "ok" end
        if action == "give_money" then
            local n = math.Clamp(math.floor(tonumber(arg) or 0), 0, 1000000)
            if n > 0 and GRM.GiveMoney then GRM.GiveMoney(ply, n, "Диалог NPC") end
            return "ok"
        end
        if action == "give_item" and arg ~= "" then
            if GRM.Inventory and GRM.Inventory.AddItem then GRM.Inventory.AddItem(ply, arg, 1) end
            return "ok"
        end
        if action == "emit" and arg ~= "" then
            if Q.Event then Q.Event(ply, arg, "", 1) end
            return "ok"
        end
        return "ok"
    end

    net.Receive(NET_PICK, function(_, ply)
        if not IsValid(ply) then return end
        ply.GRMQuestDlgNext = ply.GRMQuestDlgNext or 0
        if CurTime() < ply.GRMQuestDlgNext then return end
        ply.GRMQuestDlgNext = CurTime() + 0.2
        local sess = ply.GRMQuestDlg
        if not istable(sess) or not IsValid(sess.npc) then return end
        if ply:GetPos():DistToSqr(sess.npc:GetPos()) > 220 * 220 then
            --[[ Отошёл от NPC — разговор тоже окончен. Без этого
                 отложенный ролик завис бы навсегда. ]]
            flushPending(ply)
            ply.GRMQuestDlg = nil
            return
        end
        local nodeIndex = net.ReadUInt(8)
        local choiceIndex = net.ReadUInt(8)
        local def = Q.Definitions and Q.Definitions[sess.questID]
        local nodes = nodesOf(def, sess.phase)
        local node = nodes[nodeIndex]
        if not node then return end

        local ch
        if choiceIndex == 0 then
            ch = { next = node.next, action = "", actionArg = "" }
        else
            ch = (node.choices or {})[choiceIndex]
            if not istable(ch) or not Q.EvalCondition(ply, ch.cond) then return end
        end

        --[[ СВЯЗИ ВЫБРАННОГО ОТВЕТА (заказ владельца 29.08).

             У последней реплики два варианта, и ролик должен идти
             только на один из них. Линия в студии тянется от порта
             конкретного ответа, номер приезжает в связи как port.

             Запускаем ЗДЕСЬ, а не при показе реплики: до выбора мы не
             знаем, что игрок ответит. Связи самой реплики (port 0)
             отработали раньше в sendNode и повторно не трогаются. ]]
        if Q.RunGraphFrom and choiceIndex > 0 then
            local uid = tostring(node.id or "")
            if uid ~= "" then
                Q.RunGraphFrom(ply, def, uid, nil, "now", choiceIndex)
                local sess2 = ply.GRMQuestDlg
                if istable(sess2) then
                    --[[ Отложенные связи ответа копим отдельно от связей
                         реплики: у них свой порт, и при выпуске он нужен,
                         иначе сработают варианты, которые игрок не
                         выбирал. ]]
                    sess2.pendingChoice = istable(sess2.pendingChoice) and sess2.pendingChoice or {}
                    sess2.pendingChoice[#sess2.pendingChoice + 1] = { uid = uid, port = choiceIndex }
                end
            end
        end

        local result = runAction(ply, def, ch.action, ch.actionArg)
        if result == "close" then
            flushPending(ply)
            ply.GRMQuestDlg = nil
            net.Start(NET_NODE)
                net.WriteString("")
                net.WriteString("")
                net.WriteString("")
                net.WriteUInt(0, 8)
                net.WriteUInt(0, 8)
                net.WriteString("")
                net.WriteString("")
                net.WriteUInt(0, 4)
            net.Send(ply)
            return
        end
        if result == "stay" then
            sendNode(ply, sess.npcName, sess.questID, sess.phase, node, nodeIndex, nodes)
            return
        end

        local nextID = tostring(ch.next or "")
        local nxt, ni
        if nextID ~= "" then nxt, ni = findNode(nodes, nextID)
        else ni = nodeIndex + 1; nxt = nodes[ni] end
        if not nxt then
            flushPending(ply)
            ply.GRMQuestDlg = nil
            net.Start(NET_NODE)
                net.WriteString("") net.WriteString("") net.WriteString("")
                net.WriteUInt(0, 8) net.WriteUInt(0, 8)
                net.WriteString("") net.WriteString("") net.WriteUInt(0, 4)
            net.Send(ply)
            return
        end
        sendNode(ply, sess.npcName, sess.questID, sess.phase, nxt, ni, nodes)
    end)

    hook.Add("InitPostEntity", "GRM_Quest_LoadFlags", function()
        timer.Simple(0.5, function() if Q.LoadFlags then Q.LoadFlags() end end)
    end)
    hook.Add("ShutDown", "GRM_Quest_SaveFlags", function() if Q.SaveFlags then Q.SaveFlags() end end)
end

if CLIENT then
    --[[ Свои шрифты для окна разговора. Раньше использовались
         DermaLarge/DermaDefaultBold — они мелкие для крупного окна и
         не поддерживают кириллицу одинаково на всех клиентах. ]]
    surface.CreateFont("GRMQDlg_Name",    { font = "Roboto", size = 26, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMQDlg_Speaker", { font = "Roboto", size = 21, weight = 700, extended = true, antialias = true })
    surface.CreateFont("GRMQDlg_Text",    { font = "Roboto", size = 19, weight = 500, extended = true, antialias = true })
    surface.CreateFont("GRMQDlg_Answer",  { font = "Roboto", size = 17, weight = 600, extended = true, antialias = true })
    surface.CreateFont("GRMQDlg_Small",   { font = "Roboto", size = 14, weight = 500, extended = true, antialias = true })

    local dlg
    local function closeDlg()
        if IsValid(dlg) then dlg:Remove() end
        dlg = nil
    end

    net.Receive(NET_NODE, function()
        local npcName = net.ReadString()
        local questID = net.ReadString()
        local phase = net.ReadString()
        local index = net.ReadUInt(8)
        local total = net.ReadUInt(8)
        local speaker = net.ReadString()
        local text = net.ReadString()
        local nch = net.ReadUInt(4)
        local choices = {}
        for i = 1, nch do
            choices[#choices + 1] = { i = net.ReadUInt(8), text = net.ReadString() }
        end
        if total == 0 or text == "" and npcName == "" then closeDlg() return end

        --[[ ОКНО РАЗГОВОРА С NPC (переделано 28.08 по просьбе владельца:
             «меню квестового NPC надо переделать, сделать побольше и
             покрасивее»).

             Было: 760x560 с полями фиксированной ширины 680. На широком
             экране окно выглядело почтовой маркой, длинная реплика не
             помещалась в 160 пикселей высоты и обрезалась, а кнопки
             ответов уезжали за нижний край, если их было больше пяти.

             Стало: окно занимает долю экрана, реплика прокручивается,
             ответы пронумерованы и всегда влезают. Всё, что зависит от
             ширины, считается от неё, а не прибито числом. ]]
        if not IsValid(dlg) then
            dlg = vgui.Create("DFrame")
            dlg:SetSize(math.Clamp(ScrW() * 0.56, 820, 1180),
                        math.Clamp(ScrH() * 0.62, 560, 780))
            dlg:Center() dlg:SetTitle("") dlg:ShowCloseButton(false) dlg:MakePopup()
            dlg.Paint = function(self, w, h)
                -- Затемняем игру за окном: разговор должен держать внимание.
                surface.SetDrawColor(0, 0, 0, 170)
                surface.DrawRect(-ScrW(), -ScrH(), ScrW() * 3, ScrH() * 3)

                draw.RoundedBox(12, 0, 0, w, h, Color(11, 16, 26, 250))
                draw.RoundedBoxEx(12, 0, 0, w, 64, Color(17, 26, 40), true, true, false, false)
                -- Золотая полоса под шапкой: та же линия, что у остальных окон GRM.
                surface.SetDrawColor(242, 190, 75, 200)
                surface.DrawRect(0, 62, w, 2)
                surface.SetDrawColor(48, 68, 96)
                surface.DrawOutlinedRect(0, 0, w, h, 1)

                draw.SimpleText(tostring(self._npc or "Разговор"), "GRMQDlg_Name", 26, 26,
                    Color(245, 200, 90), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(tostring(self._sub or ""), "GRMQDlg_Small", 26, 47,
                    Color(140, 158, 182), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                -- Счётчик реплик справа: видно, длинный разговор или нет.
                draw.SimpleText(tostring(self._pos or ""), "GRMQDlg_Small", w - 26, 32,
                    Color(120, 140, 165), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
            dlg.OnClose = closeDlg
            -- ESC закрывает разговор штатно, а не оставляет висеть сессию.
            dlg.OnKeyCodePressed = function(_, key)
                if key == KEY_ESCAPE then closeDlg() end
            end
        end

        dlg._npc = npcName
        dlg._sub = ({ offer = "Предложение задания", active = "Задание в работе",
                      complete = "Задание выполнено" })[phase] or "Разговор"
        dlg._pos = (total > 1) and (index .. " / " .. total) or ""

        if IsValid(dlg._body) then dlg._body:Remove() end
        local body = vgui.Create("DPanel", dlg)
        body:Dock(FILL) body:DockMargin(20, 72, 20, 20)
        body:SetPaintBackground(false)
        dlg._body = body

        local W = dlg:GetWide() - 40

        --[[ РЕПЛИКА. Отдельная карточка с прокруткой: длинный текст
             больше не обрезается, как это было при жёстких 160px. ]]
        local textCard = vgui.Create("DPanel", body)
        textCard:Dock(TOP)
        textCard:SetTall(math.floor(dlg:GetTall() * 0.34))
        textCard:DockMargin(0, 0, 0, 14)
        textCard.Paint = function(_, w, h)
            draw.RoundedBox(10, 0, 0, w, h, Color(19, 28, 43, 250))
            draw.RoundedBox(0, 0, 0, 4, h, Color(242, 190, 75))
        end

        local who = vgui.Create("DLabel", textCard)
        who:Dock(TOP) who:SetTall(30) who:DockMargin(20, 14, 20, 0)
        who:SetFont("GRMQDlg_Speaker") who:SetTextColor(Color(242, 190, 75))
        who:SetText(speaker ~= "" and speaker or npcName)

        local scroll = vgui.Create("DScrollPanel", textCard)
        scroll:Dock(FILL) scroll:DockMargin(20, 4, 14, 14)
        local tx = vgui.Create("DLabel", scroll)
        tx:Dock(TOP) tx:SetWrap(true) tx:SetAutoStretchVertical(true)
        tx:SetFont("GRMQDlg_Text") tx:SetTextColor(Color(228, 236, 246))
        tx:SetText(text)

        local function pick(ci)
            net.Start(NET_PICK) net.WriteUInt(index, 8) net.WriteUInt(ci, 8) net.SendToServer()
        end

        --[[ ОТВЕТЫ. Кладём в прокручиваемый список и нумеруем: раньше
             шестой ответ просто уезжал за край окна. ]]
        local list = vgui.Create("DScrollPanel", body)
        list:Dock(FILL)

        local function answerButton(caption, num, accent)
            local b = vgui.Create("DButton", list)
            b:Dock(TOP) b:SetTall(46) b:DockMargin(0, 0, 6, 8)
            b:SetText("") b:SetCursor("hand")
            b.Paint = function(s, w, h)
                local base = accent and Color(32, 74, 52) or Color(24, 34, 50)
                local hov = accent and Color(46, 108, 74) or Color(40, 62, 96)
                draw.RoundedBox(8, 0, 0, w, h, s:IsHovered() and hov or base)
                surface.SetDrawColor(s:IsHovered() and Color(120, 175, 250, 200) or Color(52, 72, 100, 160))
                surface.DrawOutlinedRect(0, 0, w, h, 1)
                -- Номер в кружке: по нему же работает выбор цифрой.
                if num then
                    draw.RoundedBox(6, 10, h / 2 - 12, 24, 24, Color(14, 20, 32))
                    draw.SimpleText(tostring(num), "GRMQDlg_Small", 22, h / 2,
                        Color(200, 214, 232), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                draw.SimpleText(caption, "GRMQDlg_Answer", num and 46 or 18, h / 2,
                    Color(236, 242, 250), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            return b
        end

        if #choices > 0 then
            for idx2, ch in ipairs(choices) do
                local b = answerButton(ch.text, idx2, false)
                b.DoClick = function() pick(ch.i) end
            end
        else
            local last = index >= total
            local b = answerButton(last and "Завершить разговор" or "Продолжить", nil, not last)
            b.DoClick = function() pick(0) end
        end

        local hint = vgui.Create("DLabel", body)
        hint:Dock(BOTTOM) hint:SetTall(20) hint:DockMargin(2, 6, 2, 0)
        hint:SetFont("GRMQDlg_Small") hint:SetTextColor(Color(110, 128, 152))
        hint:SetText("ESC — выйти из разговора")
    end)
end

print("[GRM Quest Dialogue] loaded")
