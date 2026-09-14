# -*- mode: python ; coding: utf-8 -*-
# Спека PyInstaller для сборки «Терминала Комитета» в один .exe/.bin
import os

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[('index.html', '.')],
    hiddenimports=[],
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='Komitet',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,          # без консольного окна (GUI)
    icon=None,
)
