@echo off
chcp 65001 >nul
title Сборка Терминала Комитета (.exe)

echo ============================================================
echo   СБОРКА «ТЕРМИНАЛ КОМИТЕТА» В ОДИН .EXE
echo ============================================================
echo.

set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY where python >nul 2>nul && set "PY=python"
if not defined PY (
    echo [ОШИБКА] Python не найден.
    pause
    exit /b 1
)

%PY% -m pip install pyinstaller pywebview >nul
if errorlevel 1 (
    echo [ОШИБКА] Не удалось установить PyInstaller.
    pause
    exit /b 1
)

echo Сборка исполняемого файла...
%PY% -m PyInstaller --clean --noconfirm komitet.spec
if errorlevel 1 (
    echo [ОШИБКА] Сборка не удалась.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   ГОТОВО! Файл: dist\Komitet.exe
echo   Это переносимый .exe — можно запускать без Python.
echo ============================================================
pause
