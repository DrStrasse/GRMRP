-- Контракты новых служебных компьютеров: grm_comp_fire и grm_comp_cityhall.
local function read(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end
local fireInit = read("lua/entities/grm_comp_fire/init.lua")
local fireCl   = read("lua/entities/grm_comp_fire/cl_init.lua")
local fireSh   = read("lua/entities/grm_comp_fire/shared.lua")
local policeCl = read("lua/entities/grm_comp_police/cl_init.lua")
local medicalInit = read("lua/entities/grm_comp_medical/init.lua")
local documents = read("lua/autorun/sh_grm_documents.lua")
local chInit   = read("lua/entities/grm_comp_cityhall/init.lua")
local chCl     = read("lua/entities/grm_comp_cityhall/cl_init.lua")
local chSh     = read("lua/entities/grm_comp_cityhall/shared.lua")
local courtInit = read("lua/entities/grm_comp_court/init.lua")
local courtCl   = read("lua/entities/grm_comp_court/cl_init.lua")
local courtSh   = read("lua/entities/grm_comp_court/shared.lua")
local tool     = read("lua/weapons/gmod_tool/stools/grm_service_tool.lua")
local perm     = read("lua/autorun/sh_grm_perm_entities.lua")

local pass, fail = 0, 0
local function has(s, n) return s:find(n, 1, true) ~= nil end
local function ok(v, n) if v then pass = pass + 1; print("  ok  " .. n) else fail = fail + 1; print("  FAIL " .. n) end end

-- Пожарная станция.
ok(has(fireSh, "grm_comp_fire") and has(fireSh, "Пожарная станция"), "fire computer shared defines class/name")
ok(has(fireInit, "GRM_CompFire_Open") and has(fireInit, "GRM_CompFire_Calls"), "fire computer net strings (журнал вызовов вместо действий дежурства)")
ok(has(fireInit, "function ENT:CanManage") and has(fireInit, "GRM.Fire"), "fire computer access via GRM.Fire")
ok(has(fireInit, "F.CanFightPro") and has(fireInit, "F.CanDispatch"), "fire access: fighters + dispatchers")
ok(not has(fireInit, "F.CommissionTruck") and not has(fireInit, "F.TakeHoseFromTruck") and has(fireInit, 'r.category or ""'), "станция — только журналы: ствол/рукав и закрепление машины убраны")
ok(has(fireInit, "F.Snapshot"), "fire snapshot of active vfire")
ok(has(fireCl, "grm_fire_access") and has(fireCl, "grm_fire_log") and has(fireCl, "grm_fire_trucks") and has(fireCl, "grm_fire_spots"), "fire UI opens existing fire menus")
ok(has(fireCl, "grm_fire_notify"), "fire UI opens notify menu")
ok(has(fireInit, "local function snapshot(ent, ply)") and has(fireInit, "snapshot(self, ply)"), "fire E snapshot uses valid entity, not nil self")
ok(has(fireCl, "GRM.FireComputerFrame") and has(fireCl, "body.PerformLayout"), "fire UI singleton and delayed-width layout")
ok(has(policeCl,"Лицензии на оружие") and has(policeCl,'net.WriteString("weaponLicense")') and has(policeCl,'StartExam("weaponLicense"'),"police computer issues weapon licenses and runs exam")
ok(has(documents,"medicalComputerBoxes") and has(documents,"tpl.access.medicalComputer"),"doc_admin exposes medical computer access")
ok(has(medicalInit,"docAccess.medicalComputer") and has(medicalInit,"GRM.Medical.CanTreat"),"medical computer checks doc_admin plus detailed medical access")

-- Мэрия.
ok(has(chSh, "grm_comp_cityhall") and has(chSh, "мэрии"), "cityhall shared defines class/name")
ok(has(chInit, "GRM_CityHall_Open"), "cityhall net string")
ok(has(chInit, "function ENT:CanManage") and has(chInit, "CanIssueBusinessLicenses"), "cityhall access via business license right")
ok(has(chInit, "GRM.Economy") and has(chInit, "StateBudgetGet"), "cityhall overview: state budget")
ok(has(chInit, "GRM.Services"), "cityhall overview: services")
ok(has(chCl, "GRM_Doc_ComputerIssue") and has(chCl, "businessLicense"), "cityhall issues business licenses via documents core")
ok(has(chCl, "GRM_Doc_ComputerRevoke"), "cityhall revokes business licenses via documents core")
ok(has(chCl, "GRM.Documents.StartExam") and has(chCl, "businessLicense"), "cityhall runs theory exam (no practice)")

-- Юстиция.
ok(has(courtSh, "grm_comp_court") and has(courtSh, "юстиции"), "court shared defines class/name")
ok(has(courtInit, "GRM_CompCourt_Open") and has(courtInit, "GRM_CompCourt_Action"), "court net strings")
ok(has(courtInit, "function ENT:CanManage") and has(courtInit, "GRM.Wanted"), "court access via wanted core")
ok(has(courtInit, "F.Issue") and has(courtInit, "F.Cancel"), "court issues/cancels fines via fines core")
ok(has(courtInit, "jurisdiction = \"civil\""), "court operates civil jurisdiction")
ok(has(courtInit, "F.Page"), "court lists fines via F.Page")
ok(has(courtCl, "Законы и статьи") and has(courtCl, "Штрафы"), "court UI: laws + fines tabs")

-- Регистрация.
ok(has(tool, 'class     = "grm_comp_fire"') and has(tool, 'class     = "grm_comp_cityhall"') and has(tool, 'class     = "grm_comp_court"'), "all new computers registered in service tool")
ok(has(perm, "grm_comp_fire            = true") and has(perm, "grm_comp_cityhall        = true") and has(perm, "grm_comp_court           = true"), "all new computers in PERM_CLASSES")
ok(has(perm, '"grm_comp_fire", "grm_comp_cityhall"') and has(perm, '"grm_comp_court"'), "computer titles persist via PermData")

print(("SERVICE_COMPUTERS: %d/%d failures=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
