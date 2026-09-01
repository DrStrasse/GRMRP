-- /dep, /d и /fr выводятся как /gnews: шапка канала + перенос строки,
-- дальше имя, должность и текст отдельными сегментами.
-- Раньше вся волна клеилась в одну строку одним цветом (см. sim до 18.08.2026);
-- заказ владельца — «обработка и перенос строки как у /gnews».
local f = assert(io.open("lua/autorun/sh_factions.lua", "rb"))
local s = f:read("*a")
f:close()

local fail = 0
local function ok(c, n) if c then print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

local printer = s:match("local function printChannel(.-)\nend") or ""
ok(printer ~= "", "есть единый вывод служебных каналов printChannel")
ok(printer:find('tagColor, "[" .. tostring(tag or "") .. "]\\n"', 1, true) ~= nil,
    "после тэга идёт перенос строки — как в /gnews")
ok(printer:find('bodyColor, tostring(name or "")', 1, true) ~= nil,
    "имя отдельным сегментом, цветом канала")
ok(printer:find('" (" .. tostring(role or "Участник") .. "): "', 1, true) ~= nil,
    "должность отдельным сегментом")

local depBlock = s:match("net%.Receive%(NET_DEP_MSG, function%(%)(.-)end%)") or ""
ok(depBlock:find('printChannel("[Волна] ", CH_DEP_WINE, CH_DEP_WINE', 1, true) ~= nil,
    "госволна целиком бордовая: шапка, тэг и текст")
ok(depBlock:find("net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)", 1, true) ~= nil,
    "цвет фракции читается и используется для тэга")

local radioBlock = s:match("net%.Receive%(NET_RADIO_MSG, function%(%)(.-)end%)") or ""
ok(radioBlock:find('printChannel("[Рация] "', 1, true) ~= nil, "/fr использует тот же вывод")

ok(s:find('lower:find("^/dep%s+")', 1, true) ~= nil
    and s:find('lower:find("^/d%s+")', 1, true) ~= nil
    and s:find("net.Start(NET_DEP)", 1, true) ~= nil,
    "/dep и /d используют NET_DEP")

ok(s:find('local rpName = ply:GetNWString("GRM_RPName", "")', 1, true) ~= nil,
    "в канал уходит RP-имя, а не ник Steam")

print(("DEP WAVE FORMAT: 9 checks, failures=%d"):format(fail))
os.exit(fail == 0 and 0 or 1)
