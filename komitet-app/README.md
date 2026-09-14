# Терминал Комитета — десктопное приложение

Редактор и база данных (реестр досье, рапорты, агенты, журнал действий) в стиле Minecraft.
Данные хранятся в **настоящей базе SQLite** (файл `komitet.db`), а не в браузере.

## Состав

| Файл | Назначение |
|---|---|
| `main.py` | Точка входа: запускает сервер и нативное окно |
| `db.py` | Слой SQLite (создание таблиц, CRUD, журнал, импорт/экспорт) |
| `server.py` | Встроенный HTTP-сервер + REST API |
| `index.html` | Интерфейс (пиксельный, в стиле Minecraft) |
| `install.bat` | Автоустановщик для Windows |
| `install.sh` | Автоустановщик для Linux / macOS |
| `build_exe.bat` | Сборка переносимого `.exe` (PyInstaller) |
| `komitet.spec` | Спека PyInstaller |
| `installer.iss` | Сценарий инсталлятора Inno Setup (Windows) |

## Быстрый запуск (без установки)

```bash
pip install pywebview
python main.py
```

Если `pywebview` не установлен — приложение автоматически откроется в браузере.

## Установка

### Windows

Дважды запустить `install.bat`. Установщик сам:

1. найдёт Python (или сообщит, где скачать);
2. создаст изолированное окружение в `%LOCALAPPDATA%\Komitet`;
3. установит зависимости и скопирует файлы;
4. создаст лаунчер и ярлык на рабочем столе.

### Linux / macOS

```bash
chmod +x install.sh
./install.sh
```

## Где лежит база данных

- **Windows:** `%APPDATA%\Komitet\komitet.db`
- **Linux/macOS:** `~/.local/share/komitet/komitet.db`

## Резервное копирование

Кнопка **«Экспорт»** скачивает базу в JSON-файл, кнопка **«Импорт»** восстанавливает из него.
Можно также просто копировать файл `komitet.db`.

## Сборка переносимого .exe

1. Установите Python (галочка «Add Python to PATH»).
2. Запустите `build_exe.bat`.
3. Результат: `dist\Komitet.exe` — один файл, запускается без Python.

## Сборка инсталлятора (Setup.exe)

1. Соберите `dist\Komitet.exe` (шаг выше).
2. Установите [Inno Setup](https://jrsoftware.org/isinfo.php).
3. Откройте `installer.iss` и нажмите **Compile**.
4. Получите `Komitet_Setup_1.0.exe` — полноценный установщик с ярлыками и удалением.
