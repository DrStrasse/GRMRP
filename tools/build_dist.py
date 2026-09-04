#!/usr/bin/env python3
"""Пересборка архивов dist/ из рабочего дерева.

Архивы:
  grm_single_addon.zip  — весь аддон, файлы под префиксом grm/
  grm_full_code.zip     — то же самое, но без префикса
  grm_economy.zip       — экономика, банк, документы, служебные компьютеры
                          и модули розыска/штрафов, от которых они зависят
  grm_fix_hud_tab_currency.zip — точечный фикс HUD/TAB/валюты
  grm_textscreens.zip   — 3D2D Textscreens (отдельная папка в addons/)
  grm_addon_studio.zip  — Студия аддона (отдельный аддон, addons/grm_addon_studio/)
  grmrp_gamemode.zip    — игровой режим (gamemodes/grmrp/**, распаковка в
                          garrysmod/gamemodes/; НЕ входит в аддон-архивы)

Запуск: python3 tools/build_dist.py
"""
import os
import shutil
import io
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")

# Каталоги контента аддона (те, что реально существуют, попадают в сборку).
CONTENT_DIRS = ["lua", "materials", "models", "sound", "resource", "gamemodes", "maps"]

# Экономический срез: ядро экономики + всё, что его использует.
ECONOMY_FILES = [
    # Общие контракты нужны service-компьютерам: Access/Net/Audit/Persistence.
    "lua/autorun/sh_00_grm_boot.lua",
    "lua/autorun/sh_01_grm_core.lua",
    "lua/autorun/sh_02_grm_persistence.lua",
    "lua/autorun/sh_03_grm_access.lua",
    "lua/autorun/sh_04_grm_net.lua",
    "lua/autorun/sh_05_grm_audit.lua",
    "lua/autorun/sh_06_grm_performance.lua",
    "lua/autorun/sh_07_grm_sound.lua",
    "lua/autorun/sh_grm_identity.lua",
    "lua/autorun/sh_grm_currency.lua",
    "lua/autorun/sh_grm_economy.lua",
    "lua/autorun/sh_grm_incassation.lua",
    "lua/autorun/sh_grm_perm_entities.lua",
    "lua/autorun/sh_grm_prop_protect.lua",
    "lua/autorun/sh_grm_medical.lua",
    "lua/autorun/sh_grm_documents.lua",
    # розыск и штрафы: служебные компьютеры ниже без них не работают
    "lua/autorun/sh_grm_wanted_config.lua",
    "lua/autorun/sh_grm_wanted_access.lua",
    "lua/autorun/sh_grm_wanted_fines.lua",
    # фаза 3: лист розыска, ориентировки, обмен сведениями, спецслужбы
    "lua/autorun/sh_grm_wanted_board.lua",
    "lua/autorun/sh_grm_wanted_bulletins.lua",
    "lua/autorun/sh_grm_wanted_exchange.lua",
    "lua/autorun/sh_grm_special_service.lua",
    # фаза 4: госуслуги, счета, дипломы и меню банкомата
    "lua/autorun/sh_grm_services.lua",
    "lua/autorun/sh_grm_service_orders.lua",
    "lua/autorun/sh_grm_diplomas.lua",
    "lua/autorun/sh_grm_atm.lua",
    "lua/autorun/server/sv_grm_services_commands.lua",
    "lua/autorun/sh_factions.lua",
    "lua/autorun/client/cl_grm_ui_theme.lua",
    "lua/autorun/sh_00_grm_ui.lua",
    "lua/autorun/server/sv_grm_wanted.lua",
    "lua/autorun/server/sv_grm_comp_terminal.lua",
    "lua/autorun/server/sv_grm_wanted_commands.lua",
    "lua/autorun/client/cl_grm_wanted.lua",
    "lua/autorun/client/cl_grm_comp_terminal.lua",
    "lua/weapons/weapon_grm_incass_bag/shared.lua",
    "lua/weapons/gmod_tool/stools/grm_bank_tool.lua",
    "lua/weapons/gmod_tool/stools/grm_service_tool.lua",
]
# Энтити экономического среза — целиком по три файла.
ECONOMY_ENTS = [
    "grm_bank_terminal", "grm_bank_vault", "grm_bank_computer", "grm_doc_computer",
    "grm_comp_police", "grm_comp_military_police", "grm_comp_security",
    "grm_comp_military", "grm_comp_traffic", "grm_comp_medical",
    "grm_comp_cityhall", "grm_comp_court",
    "grm_vault_cash", "grm_money_press", "grm_money_printer",
]
for ent in ECONOMY_ENTS:
    for part in ("cl_init.lua", "init.lua", "shared.lua"):
        ECONOMY_FILES.append("lua/entities/%s/%s" % (ent, part))

HUD_FIX_FILES = [
    "lua/autorun/sh_grm_currency.lua",
    "lua/autorun/sh_grm_economy.lua",
    "lua/autorun/sh_grm_tab_menu.lua",
    "lua/autorun/client/cl_grm_hud.lua",
]


def collect_all():
    """Все файлы контента в рабочем дереве, путями относительно корня репозитория."""
    out = []
    for d in CONTENT_DIRS:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            for fn in sorted(filenames):
                full = os.path.join(dirpath, fn)
                out.append(os.path.relpath(full, ROOT))
    return sorted(out)


def build(name, files, prefix=""):
    path = os.path.join(DIST, name)
    tmp = path + ".tmp"
    written = 0
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in files:
            src = os.path.join(ROOT, rel)
            if not os.path.isfile(src):
                print("  пропуск (нет файла): %s" % rel)
                continue
            z.write(src, prefix + rel)
            written += 1
    shutil.move(tmp, path)
    size = os.path.getsize(path)
    print("%-34s %4d файлов, %8.1f КБ" % (name, written, size / 1024.0))


def build_addon(name, folder, prefix=""):
    """Отдельный аддон из addons/<folder> — распаковывается в garrysmod/addons."""
    base = os.path.join(ROOT, "addons", folder)
    if not os.path.isdir(base):
        print("  пропуск (нет папки): addons/%s" % folder)
        return
    files = []
    for root, dirs, names in os.walk(base):
        dirs[:] = [d for d in dirs if d not in (".git", ".github")]
        for fn in names:
            full = os.path.join(root, fn)
            files.append(os.path.relpath(full, base))
    files.sort()
    path = os.path.join(DIST, name)
    tmp = path + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in files:
            z.write(os.path.join(base, rel), prefix + rel)
    shutil.move(tmp, path)
    print("%-34s %4d файлов, %8.1f КБ" % (name, len(files), os.path.getsize(path) / 1024.0))


PRONE_ADDON_JSON = """{
  "title": "SYSTEM PRONE",
  "type": "effects",
  "tags": ["roleplay", "realism"],
  "ignore": []
}
"""


def build_gamemode(name, folder, prefix=""):
    """Игровой режим gamemodes/<folder> — распаковать в garrysmod/gamemodes/."""
    base = os.path.join(ROOT, "gamemodes", folder)
    if not os.path.isdir(base):
        print("  пропуск (нет папки): gamemodes/%s" % folder)
        return
    files = []
    for root, dirs, names in os.walk(base):
        dirs[:] = [d for d in dirs if d not in (".git", ".github")]
        for fn in names:
            full = os.path.join(root, fn)
            files.append(os.path.relpath(full, base))
    files.sort()
    path = os.path.join(DIST, name)
    tmp = path + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in files:
            z.write(os.path.join(base, rel), prefix + rel)
    shutil.move(tmp, path)
    print("%-34s %4d файлов, %8.1f КБ" % (name, len(files), os.path.getsize(path) / 1024.0))


def pack_system_prone():
    """Prone Mod — отдельный аддон из SYSTEM PRONE.zip, не смешиваем с lua/ GRM."""
    src = os.path.join(ROOT, "SYSTEM PRONE.zip")
    if not os.path.isfile(src):
        print("  пропуск: нет SYSTEM PRONE.zip")
        return
    path = os.path.join(DIST, "system_prone.zip")
    tmp = path + ".tmp"
    written = 0
    with zipfile.ZipFile(src, "r") as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        wrote_json = False
        for info in zin.infolist():
            name = info.filename
            if name.endswith("/"):
                continue
            rel = name.split("/", 1)[-1] if name.startswith("SYSTEM PRONE/") else name
            if not rel:
                continue
            data = zin.read(info)
            if rel.replace("\\", "/") == "addon.json" and len(data.strip()) == 0:
                data = PRONE_ADDON_JSON.encode("utf-8")
                wrote_json = True
            zout.writestr("system_prone/" + rel.replace("\\", "/"), data)
            written += 1
        if not wrote_json:
            zout.writestr("system_prone/addon.json", PRONE_ADDON_JSON)
            written += 1
    shutil.move(tmp, path)
    print("%-34s %4d файлов, %8.1f КБ" % ("system_prone.zip", written, os.path.getsize(path) / 1024.0))


INDEX_DESC = [
    ("grm_single_addon.zip", "ВЕСЬ аддон grm — распаковать В ЦЕЛОМ в "
     "garrysmod/addons/ с заменой папки grm (не копировать руками!)"),
    ("grmrp_gamemode.zip", "Игровой режим — распаковать в garrysmod/gamemodes/ "
     "с заменой папки grmrp"),
    ("grm_full_code.zip", "Полные исходники проекта (дерево репозитория)"),
    ("grm_economy.zip", "Изолированный экономический срез"),
    ("grm_fire_addon.zip", "Пожарный контент-аддон"),
    ("grm_textscreens.zip", "3D2D Textscreens (отдельный аддон)"),
    ("grm_addon_studio.zip", "Студия аддона (отдельный аддон)"),
    ("grm_fix_hud_tab_currency.zip", "Точечный патч интерфейса и валюты"),
    ("system_prone.zip", "Prone Mod (отдельный аддон)"),
]


def build_index():
    """dist/index.html — честная витрина, генерится при КАЖДОМ билде:
    только реально существующие архивы, актуальные размеры, инструкция
    развертывания (веч.-20: устаревший статичный index вводил в заблуждение)."""
    head = ("<!DOCTYPE html>\n<html lang=\"ru\">\n<head>\n<meta charset=\"utf-8\">\n"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
            "<title>GRM — файлы сборки</title>\n<style>\n"
            "  body { font-family: system-ui, \"Segoe UI\", Roboto, sans-serif; "
            "background: #0e141f; color: #e8eef5; max-width: 720px; margin: 40px auto; "
            "padding: 0 16px; }\n"
            "  h1 { font-size: 20px; margin-bottom: 4px; }\n"
            "  .sub { color: #8aa0b8; font-size: 13px; margin-bottom: 20px; }\n"
            "  a.card { display: block; text-decoration: none; color: inherit; "
            "background: #16202e; border: 1px solid #26364a; border-radius: 10px; "
            "padding: 12px 16px; margin-bottom: 9px; }\n"
            "  a.card:hover { background: #1c2a3c; border-color: #3a5678; }\n"
            "  a.card.key { border-color: #2f7a4f; background: #14211b; }\n"
            "  .name { font-weight: 600; font-size: 15px; }\n"
            "  .meta { color: #8aa0b8; font-size: 12px; margin-top: 2px; }\n"
            "  .hint { color: #9fb4c9; font-size: 13px; margin-top: 20px; "
            "line-height: 1.55; background: #131c29; border: 1px solid #26364a; "
            "border-radius: 10px; padding: 12px 16px; }\n"
            "</style>\n</head>\n<body>\n")
    stamp = "сборка веч.-20 (04.09)"
    parts = [head,
             "  <h1>GRM — файлы сборки</h1>\n  <div class=\"sub\">%s · "
             "список генерируется build_dist.py, только реально собранные "
             "архивы</div>\n" % stamp]
    for name, desc in INDEX_DESC:
        path = os.path.join(DIST, name)
        if not os.path.isfile(path):
            continue
        kb = os.path.getsize(path) / 1024.0
        cls = "card key" if name in ("grm_single_addon.zip", "grmrp_gamemode.zip") else "card"
        parts.append('  <a class="%s" href="./%s" target="_blank">\n'
                     '    <div class="name">%s</div>\n'
                     '    <div class="meta">%s · %.1f МБ</div>\n  </a>\n'
                     % (cls, name, name, desc, kb / 1024.0))
    parts.append(
        "  <div class=\"hint\"><b>Порядок развертывания</b>: 1) остановить "
        "сервер; 2) снести <code>garrysmod/addons/grm</code> и распаковать "
        "<b>grm_single_addon.zip</b> в <code>garrysmod/addons/</code>; 3) снести "
        "<code>garrysmod/gamemodes/grmrp</code> и распаковать "
        "<b>grmrp_gamemode.zip</b> в <code>garrysmod/gamemodes/</code>; 4) "
        "запустить и сверить: подпись меню «вечер-20». Режим сам откажет в "
        "загрузке СТАРОЙ копии чата из аддона (страж веч.-20) и скажет об этом "
        "в консоли.</div>\n</body>\n</html>\n")
    with io.open(os.path.join(DIST, "index.html"), "w", encoding="utf-8") as f:
        f.write("".join(parts))
    print("index.html перегенерирован (список живой, не статичный)")


def main():
    os.makedirs(DIST, exist_ok=True)
    everything = collect_all()
    build("grm_single_addon.zip", everything, prefix="grm/")
    build("grm_full_code.zip", everything)
    build("grm_economy.zip", ECONOMY_FILES, prefix="grm/")
    build("grm_fix_hud_tab_currency.zip", HUD_FIX_FILES)
    # 3D2D Textscreens: отдельный аддон, ставится рядом с grm
    build_addon("grm_textscreens.zip", "grm_textscreens", prefix="grm_textscreens/")
    # Студия аддона: отдельный аддон (в lua/ её нет — см. addons/grm_addon_studio)
    build_addon("grm_addon_studio.zip", "grm_addon_studio", prefix="grm_addon_studio/")
    # Игровой режим: отдельный архив (указание владельца 03.09 — ссылка на
    # gamemode в каждом финале; аддон-dist не затрагивает)
    build_gamemode("grmrp_gamemode.zip", "grmrp", prefix="grmrp/")
    pack_system_prone()
    build_index()


if __name__ == "__main__":
    main()
