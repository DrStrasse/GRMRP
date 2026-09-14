#!/usr/bin/env bash
# Установщик «Терминала Комитета» (Linux / macOS)
set -e

echo "============================================================"
echo "  УСТАНОВЩИК «ТЕРМИНАЛ КОМИТЕТА» (автоустановка)"
echo "============================================================"
echo

# 1. Python
if command -v python3 >/dev/null 2>&1; then
    PY=python3
elif command -v python >/dev/null 2>&1; then
    PY=python
else
    echo "[ОШИБКА] Python 3 не найден. Установите его из пакетного менеджера."
    exit 1
fi
echo "[1/4] Python найден: $PY"

# 2. Каталог установки
case "$(uname -s)" in
    Darwin) APPDIR="$HOME/Library/Application Support/Komitet";;
    *)      APPDIR="${XDG_DATA_HOME:-$HOME/.local/share}/komitet";;
esac
mkdir -p "$APPDIR"
echo "[2/4] Каталог установки: $APPDIR"

# 3. Копирование файлов
SRC="$(cd "$(dirname "$0")" && pwd)"
for f in main.py db.py server.py index.html; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$APPDIR/$f"
done
echo "[3/4] Файлы приложения скопированы"

# 4. Виртуальное окружение + зависимости
if [ ! -x "$APPDIR/venv/bin/python" ]; then
    "$PY" -m venv "$APPDIR/venv"
fi
VENVPY="$APPDIR/venv/bin/python"
"$VENVPY" -m pip install --upgrade pip >/dev/null 2>&1 || true
"$VENVPY" -m pip install pywebview >/dev/null
echo "[4/4] Зависимости установлены"

# 5. Лаунчер
cat > "$APPDIR/run.sh" <<EOF
#!/usr/bin/env bash
exec "$VENVPY" "$APPDIR/main.py"
EOF
chmod +x "$APPDIR/run.sh"

DESKTOP_FILE="$HOME/.local/share/applications/komitet.desktop"
mkdir -p "$HOME/.local/share/applications"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Терминал Комитета
Comment=Реестр досье и рапортов
Exec=$APPDIR/run.sh
Type=Application
Categories=Utility;
Terminal=false
EOF
echo

echo "============================================================"
echo "  ГОТОВО! Запуск: $APPDIR/run.sh"
echo "  База данных: $HOME/.local/share/komitet/komitet.db"
echo "============================================================"
