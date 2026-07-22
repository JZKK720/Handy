# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec for agent-meow — bundles the agent-meow server + web UI
into a standalone executable for use as a Tauri sidecar.

Build:
  cd agent-meow
  pyinstaller voice-stack/agent-meow.spec --noconfirm

Output:
  dist/agent-meow/agent-meow.exe (directory mode, includes all deps + web UI)
  Then zip dist/agent-meow/ → sidecars/agent-meow.zip
"""

import os
from PyInstaller.utils.hooks import collect_all

block_cipher = None

# Collect all submodules and data files for key dependencies
datas = []
binaries = []
hiddenimports = []

for pkg in [
    "fastapi",
    "uvicorn",
    "pydantic",
    "starlette",
    "httpx",
    "jinja2",
    "yaml",
    "tomli",
    "click",
    "rich",
]:
    d, b, h = collect_all(pkg)
    datas += d
    binaries += b
    hiddenimports += h

# Include the built web UI static files
web_ui_path = os.path.join("agent_meow", "server", "static", "web-ui")
if os.path.isdir(web_ui_path):
    datas += [(web_ui_path, "agent_meow/server/static/web-ui")]

a = Analysis(
    ["agent_meow/__main__.py"],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports + [
        "agent_meow.runner.tool_dispatch",
        "agent_meow.server.app",
        "agent_meow.server.routes",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "IPython"],
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="agent-meow",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    icon="voice-stack/agent-meow-icon.ico",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="agent-meow",
)