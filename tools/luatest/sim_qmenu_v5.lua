-- Q-menu v5: урезанный spawn-контур, крупное окно, палитра и HOLD-Q.
local f=assert(io.open("lua/autorun/sh_grm_qmenu.lua","rb")); local s=f:read("*a"); f:close()
local fails=0
local function ok(c,n) if c then print("  ok  "..n) else fails=fails+1 print("  FAIL "..n) end end
ok(s:find('QM.Version = "5.2.0"',1,true)~=nil,"версия 5.2.0")
ok(s:find('what ~= "prop"',1,true)~=nil,"обычному игроку разрешены только prop")
ok(s:find('PlayerSpawnNPC',1,true)~=nil and s:find('PlayerSpawnSENT',1,true)~=nil,"NPC и SENT закрыты серверными хуками")
ok(s:find('PlayerSpawnSWEP',1,true)~=nil and s:find('PlayerGiveSWEP',1,true)~=nil,"спавн и выдача SWEP закрыты")
ok(s:find('PlayerSpawnVehicle',1,true)~=nil and s:find('PlayerSpawnRagdoll',1,true)~=nil,"транспорт и ragdoll закрыты")
ok(s:find('QM.PlayerTools',1,true)~=nil and s:find('grm_perm_tool=true',1,true)==nil,"отдельный безопасный набор инструментов")
ok(s:find('DColorMixer',1,true)~=nil and s:find('SetPalette(true)',1,true)~=nil,"цветовая палитра")
ok(s:find('DNumSlider',1,true)~=nil and s:find('DBinder',1,true)~=nil,"ползунки и выбор клавиш")
ok(s:find('winch_fwd_speed',1,true)~=nil and s:find('pulley_forcelimit',1,true)~=nil and s:find('hydraulic_addlength',1,true)~=nil,"параметры лебёдки, шкива и гидравлики")
ok(s:find('sw * 0.94',1,true)~=nil and s:find('sh * 0.92',1,true)~=nil,"большое окно 94%×92%")
ok(s:find('{ "settings", "Настройки ⚙"',1,true)~=nil,"вкладка настроек")
ok(s:find('dynamic = "factions"',1,true)~=nil and s:find('payload._factions',1,true)~=nil,"динамический выбор фракции")
ok(s:find('bind ~= "+menu"',1,true)~=nil and s:find('QM.OpenMenu(true)',1,true)~=nil and s:find('QM.CloseMenu()',1,true)~=nil,"HOLD-Q сохранён")
ok(s:find('grm_qmenu_admin_vanilla',1,true)~=nil and s:find('QM.SetAdminQMode',1,true)~=nil,"персональный выбор Q для суперадмина")
ok(s:find('grm_qmenu_admin_toggle',1,true)~=nil and s:find('Q: СТАНДАРТНОЕ',1,true)~=nil,"кнопка и консольное переключение режима")
-- 22.08: настройки инструментов снова строит сам инструмент — иначе у
-- 3D2D Textscreen, «Материала» и «Цвета» видны не те параметры.
ok(s:find('function QM.NativePanel(parent, toolId)',1,true)~=nil
   and s:find('vgui.Create("ControlPanel", parent)',1,true)~=nil
   and s:find('pcall(build, cp, tool)',1,true)~=nil,
   "панель инструмента строит его собственный BuildCPanel")
ok(s:find('function QM.ToolTable(toolId)',1,true)~=nil
   and s:find('weapons.GetStored("gmod_tool")',1,true)~=nil,
   "инструмент берётся из тулгана, как в ванильном меню")
ok(s:find('QM._lastPanelSource = "schema"',1,true)~=nil,
   "наша схема осталась страховкой, если родной панели нет")
print(("QMENU V5: %d/16, failures=%d"):format(16-fails,fails))
os.exit(fails==0 and 0 or 1)
