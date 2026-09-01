--[[ Контракт фотографии в документах (заказ владельца 21.08: «в чужом
     удостоверении игрок видит свою аватарку»).
     Проверяем: владелец штампуется на сервере, клиент никогда не берёт
     LocalPlayer для ЧУЖОГО бланка, есть нейтральная заглушка.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_doc_avatar.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end
local f = assert(io.open("lua/autorun/sh_grm_documents.lua", "rb"))
local src = f:read("*a") f:close()
local function has(n) return src:find(n, 1, true) ~= nil end

print("\n=== 1. СЕРВЕР ШТАМПУЕТ ВЛАДЕЛЬЦА ===")
ok(has("local function forView(rec, ply)"), "перед отправкой запись копируется и подписывается владельцем")
ok(has('out.steamID64 = tostring(ply:SteamID64() or "")'), "SteamID64 владельца проставляется, если его не было")
ok(has("out.ownerKey = out.ownerKey"), "ключ персонажа тоже уходит в бланк")
for _, doc in ipairs({ "pass", "badge", "mil", "lic", "milLic", "wl", "bl" }) do
    ok(has("net.WriteTable(forView(" .. doc .. ", ply))"), "подписывается документ: " .. doc)
end

print("\n=== 2. КЛИЕНТ НЕ ПОДСТАВЛЯЕТ СЕБЯ ===")
ok(has("function docOwnerSteamID(data, isShown)") and has("local docPhoto, docOwnerSteamID"),
    "владелец определяется отдельной функцией (с форвард-декларацией)")
ok(has("if not isShown then"), "LocalPlayer берётся только для СВОЕГО бланка")
ok(has('for _, field in ipairs({ data.ownerKey, data.charKey, data.key, data.owner })'),
    "если поля нет — SteamID64 достаётся из ключа персонажа")
ok(not has('local sid64 = data.steamID64 or (LocalPlayer():SteamID64())'),
    "старая подстановка своего SteamID убрана полностью")

print("\n=== 3. ЗАГЛУШКА ВМЕСТО ЧУЖОГО ЛИЦА ===")
ok(has("function docPhoto(parent, data, x, y, w, h, isShown)"), "фото рисует один общий помощник")
ok(has('draw.SimpleText("ФОТО"'), "если владелец неизвестен — нейтральная карточка, а не аватар")
local n = select(2, src:gsub("docPhoto%(", ""))
ok(n >= 7, "все бланки переведены на общий помощник", n)

print(("\nDOC AVATAR: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
