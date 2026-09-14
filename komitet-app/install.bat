@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Установка Терминала Комитета

echo ============================================================
echo   УСТАНОВЩИК  «ТЕРМИНАЛ КОМИТЕТА»  (автоустановка)
echo ============================================================
echo.

REM --- 1. Поиск Python ---
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY where python >nul 2>nul && set "PY=python"
if not defined PY (
    echo [ОШИБКА] Python не найден.
    echo Скачайте и установите Python 3.8+ : https://www.python.org/downloads/
    echo При установке ОБЯЗАТЕЛЬНО отметьте галочку "Add Python to PATH".
    pause
    exit /b 1
)
%PY% --version >nul 2>nul
if errorlevel 1 (
    echo [ОШИБКА] Python найден, но не запускается.
    pause
    exit /b 1
)
echo [1/4] Python найден.

REM --- 2. Создание виртуального окружения ---
set "APPDIR=%LOCALAPPDATA%\Komitet"
if not exist "%APPDIR%" mkdir "%APPDIR%"
cd /d "%APPDIR%"
if not exist "%APPDIR%\venv\Scripts\python.exe" (
    echo [2/4] Создание виртуального окружения...
    %PY% -m venv "%APPDIR%\venv"
)
set "VENVPY=%APPDIR%\venv\Scripts\python.exe"

REM --- 3. Копирование файлов приложения ---
echo [3/4] Копирование файлов приложения...
for %%F in (main.py db.py server.py index.html) do (
    if exist "%~dp0%%F" copy /y "%~dp0%%F" "%APPDIR%\%%F" >nul
)

REM --- 4. Установка зависимостей ---
echo [4/4] Установка зависимости pywebview (для нативного окна)...
"%VENVPY%" -m pip install --upgrade pip >nul 2>nul
"%VENVPY%" -m pip install pywebview >nul

REM --- 5. Лаунчер и ярлык ---
(
echo @echo off
echo "%VENVPY%" "%APPDIR%\main.py"
) > "%APPDIR%\Запустить_Комитет.bat"

echo Создание ярлыка на рабочем столе...
powershell -NoProfile -Command ^
  "$ws=New-Object -ComObject WScript.Shell; $desk=[Environment]::GetFolderPath('Desktop'); $sc=$ws.CreateShortcut(\"$desk\Терминал Комитета.lnk\"); $sc.TargetPath='%APPDIR%\Запустить_Комитет.bat'; $sc.WorkingDirectory='%APPDIR%'; $sc.Save()" >nul 2>nul

echo.
echo ============================================================
echo   ГОТОВО! Приложение установлено.
echo   Запуск: ярлык «Терминал Комитета» на рабочем столе
echo     или файл: %APPDIR%\Запустить_Комитет.bat
echo   База данных: %APPDATA%\Komitet\komitet.db
echo ============================================================
pause
