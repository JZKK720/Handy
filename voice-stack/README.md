# Voice Stack — All-in-One Packaging

Packaging for the voice integration stack: **Handy (STT) + Voicebox (TTS) + agent-meow (Agent)**.

## Status: SCAFFOLD — Not yet buildable

These scaffolds are reference implementations. Before building the installer,
all 3 components must be in a buildable state:

| Component | Buildable? | Entry Point | Notes |
|---|---|---|---|
| Handy | ✅ Yes | `handy.exe` | Build with `bun run tauri build` in the Handy repo |
| agent-meow | ✅ Imports OK | `omni` / `meow` / `agent-meow` CLI | 277 rebrand files uncommitted — resolve before packaging |
| Voicebox | ❓ Unverified | `voicebox` server | Source repo not cloned locally — verify build before packaging |

## Two packaging options

### Option 1: Bootstrap Script (ship today)

Installs 3 pre-built components via a single PowerShell script.

```powershell
# Run as Administrator
.\voice-stack\install-voice-stack.ps1

# Or with specific paths
.\voice-stack\install-voice-stack.ps1 -HandyMsi "C:\Downloads\Handy_0.9.4_x64.msi" -InstallDir "D:\apps\voice-stack"
```

**What it does:**
1. Installs Handy from `.msi` (silent)
2. Creates a Python venv for Voicebox, `pip install voicebox`, sets up as Windows service
3. Creates a Python venv for agent-meow, `pip install agent-meow`, sets up as Windows service
4. Sets system env vars: `HANDY_CLI_PATH`, `VOICEBOX_URL`

**Prerequisites on target machine:**
- Python 3.12+ installed
- Handy `.msi` downloaded
- Admin privileges

### Option 2: Tauri Wrapper (single installer)

Bundles all 3 as frozen sidecar binaries into one `.msi`/`.dmg`/`.AppImage`.
No Python runtime needed on the target machine.

```powershell
# Build all sidecars + Tauri wrapper in one command
.\voice-stack\build-voice-stack.ps1

# With custom source directories
.\voice-stack\build-voice-stack.ps1 -VoiceboxDir "D:\code\voicebox" -AgentMeowDir "D:\code\agent-meow"
```

**What it does:**
1. Copies Handy binary → `sidecars/handy.exe`
2. PyInstaller: Voicebox → `sidecars/voicebox/voicebox.exe` (frozen Python)
3. PyInstaller: agent-meow → `sidecars/agent-meow/agent-meow.exe` (frozen Python + web UI)
4. Tauri build: bundles all sidecars + React UI → single installer

**Prerequisites on build machine:**
- Python 3.12+ with PyInstaller (`pip install pyinstaller`)
- Node.js 20+ and npm
- Rust toolchain (`rustup`)
- Handy built (`bun run tauri build` in Handy repo)
- Voicebox source cloned
- agent-meow source cloned and in a clean buildable state

**Result on target machine:**
- One installer (`.msi` on Windows)
- One desktop app with tray icon
- Auto-starts all 3 sidecar processes
- Service manager UI (start/stop/status)
- "Open agent-meow Web UI" button
- Closing the app stops all services cleanly

## Directory structure

```
voice-stack/
├── install-voice-stack.ps1     # Bootstrap installer script
├── build-voice-stack.ps1       # Full build pipeline (sidecars + Tauri)
├── voicebox.spec               # PyInstaller spec for Voicebox
├── agent-meow.spec             # PyInstaller spec for agent-meow
├── README.md                   # This file
└── tauri-wrapper/              # Tauri desktop app (the single installer)
    ├── package.json            # npm deps (React, Tauri SDK)
    ├── vite.config.ts          # Vite build config
    ├── tsconfig.json           # TypeScript config
    ├── tailwind.config.js      # Tailwind CSS config
    ├── postcss.config.js       # PostCSS config
    ├── index.html              # HTML entry point
    ├── src/
    │   ├── main.tsx            # React entry
    │   ├── App.tsx             # Service manager UI (start/stop/status)
    │   └── index.css           # Global styles
    └── src-tauri/
        ├── tauri.conf.json     # Tauri config (sidecar resources, bundle settings)
        ├── Cargo.toml          # Rust deps
        ├── build.rs            # Tauri build script
        ├── capabilities/
        │   └── default.json    # Tauri permissions
        └── src/
            ├── main.rs         # Rust entry point
            └── lib.rs          # Sidecar manager (process lifecycle, health checks)
```

## Architecture

```
┌─────────────────────────────────────────────┐
│           Voice Stack (Tauri Wrapper)        │
│  ┌───────────────────────────────────────┐  │
│  │         React Service Manager UI      │  │
│  │  Handy ✅  Voicebox ✅  agent-meow ✅ │  │
│  │  [Start All] [Stop All] [Open Web UI]│  │
│  └───────────────────────────────────────┘  │
│                    │                         │
│         Rust sidecar process manager         │
│                    │                         │
│  ┌────────┬──────────────┬──────────────┐   │
│  │ handy  │  voicebox    │  agent-meow  │   │
│  │ (STT)  │  (TTS)       │  (Agent)     │   │
│  │ CLI    │  :17493      │  :8000       │   │
│  └────────┴──────────────┴──────────────┘   │
└─────────────────────────────────────────────┘
```

## Before building — checklist

- [ ] Handy built: `cd Handy && bun run tauri build` → `src-tauri/target/release/handy.exe`
- [ ] agent-meow in clean state: commit or stash the 277 rebrand files, verify `npm run build` in `web/` works
- [ ] Voicebox source cloned and buildable: verify `python -m voicebox` starts the server on :17493
- [ ] PyInstaller installed: `pip install pyinstaller`
- [ ] Rust toolchain: `rustup show`
- [ ] Node.js 20+: `node --version`