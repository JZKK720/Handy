# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec for Voicebox — bundles the Voicebox FastAPI server
into a standalone executable for use as a Tauri sidecar.

Build:
  cd voicebox
  pyinstaller voice-stack/voicebox.spec --noconfirm

Output:
  dist/voicebox/voicebox.exe (directory mode, includes all deps)
  Then zip dist/voicebox/ → sidecars/voicebox.zip
"""

import os
from PyInstaller.utils.hooks import collect_all

block_cipher = None

# Collect all submodules and data files for key dependencies
datas = []
binaries = []
hiddenimports = []

for pkg in ["fastapi", "uvicorn", "pydantic", "starlette", "httpx"]:
    d, b, h = collect_all(pkg)
    datas += d
    binaries += b
    hiddenimports += h

a = Analysis(
    ["voicebox/__main__.py"],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "PIL", "IPython"],
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="voicebox",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    icon="voice-stack/voicebox-icon.ico",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="voicebox",
)