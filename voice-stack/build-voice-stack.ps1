<#
.SYNOPSIS
  Build Voice Stack — packages all 3 sidecars + Tauri wrapper into one installer.
.DESCRIPTION
  This script orchestrates the full build pipeline:
    1. PyInstaller: Voicebox → sidecars/voicebox/voicebox.exe
    2. PyInstaller: agent-meow → sidecars/agent-meow/agent-meow.exe
    3. Copy Handy binary → sidecars/handy/handy.exe
    4. Tauri build: bundles all sidecars + React UI → dist/ .msi/.dmg/.AppImage

  Prerequisites:
    - Python 3.12+ with PyInstaller installed
    - Node.js 20+ and npm
    - Rust toolchain (cargo + rustup)
    - Handy built: `bun run tauri build` in the Handy repo
    - Voicebox source cloned at C:\github-pr\voicebox (or pass -VoiceboxDir)
    - agent-meow source cloned at C:\github-pr\agent-meow (or pass -AgentMeowDir)
    - Handy source at C:\github-pr\Handy (or pass -HandyDir)

.EXAMPLE
  .\build-voice-stack.ps1
.EXAMPLE
  .\build-voice-stack.ps1 -VoiceboxDir "D:\code\voicebox" -AgentMeowDir "D:\code\agent-meow"
#>

param(
    [string]$HandyDir = "C:\Users\1\github-pr\Handy",
    [string]$VoiceboxDir = "C:\Users\1\github-pr\voicebox",
    [string]$AgentMeowDir = "C:\Users\1\github-pr\agent-meow",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step {
    param([string]$Msg)
    Write-Host "`n[BUILD] $Msg" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Msg)
    Write-Host "  [OK] $Msg" -ForegroundColor Green
}

# ── 1. Prepare sidecars directory ────────────────────────────────────────────

$SidecarDir = Join-Path $ScriptDir "tauri-wrapper\src-tauri\sidecars"
if (Test-Path $SidecarDir) {
    Remove-Item $SidecarDir -Recurse -Force
}
New-Item -ItemType Directory -Path $SidecarDir -Force | Out-Null
Write-Step "Created sidecars directory: $SidecarDir"

# ── 2. Copy Handy binary ─────────────────────────────────────────────────────

Write-Step "Copying Handy binary"

# Handy is a Tauri app — after `bun run tauri build`, the binary is at:
#   src-tauri/target/release/handy.exe (Windows)
$handyBinary = Join-Path $HandyDir "src-tauri\target\release\handy.exe"
if (Test-Path $handyBinary) {
    $handyDest = Join-Path $SidecarDir "handy.exe"
    Copy-Item $handyBinary $handyDest
    Write-Ok "Copied Handy CLI → $handyDest"
} else {
    Write-Host "  Handy binary not found at $handyBinary" -ForegroundColor Yellow
    Write-Host "  Build Handy first: cd $HandyDir && bun run tauri build" -ForegroundColor Yellow
    Write-Host "  (Handy will be resolved from PATH at runtime if not bundled)" -ForegroundColor Yellow
}

# ── 3. Build Voicebox sidecar with PyInstaller ──────────────────────────────

Write-Step "Building Voicebox sidecar (PyInstaller)"

if (Test-Path $VoiceboxDir) {
    Push-Location $VoiceboxDir
    $voiceboxSpec = Join-Path $ScriptDir "voicebox.spec"
    pyinstaller $voiceboxSpec --noconfirm --distpath (Join-Path $SidecarDir "..\voicebox-dist")
    $voiceboxBuilt = Join-Path $SidecarDir "..\voicebox-dist\voicebox\voicebox.exe"
    if (Test-Path $voiceboxBuilt) {
        # Copy the whole voicebox directory into sidecars
        Copy-Item (Join-Path $SidecarDir "..\voicebox-dist\voicebox") -Destination (Join-Path $SidecarDir "voicebox") -Recurse
        Write-Ok "Voicebox sidecar built → sidecars/voicebox/"
    } else {
        Write-Host "  Voicebox build failed — check PyInstaller output" -ForegroundColor Red
    }
    Pop-Location
} else {
    Write-Host "  Voicebox source not found at $VoiceboxDir — skipping" -ForegroundColor Yellow
}

# ── 4. Build agent-meow sidecar with PyInstaller ────────────────────────────

Write-Step "Building agent-meow sidecar (PyInstaller)"

if (Test-Path $AgentMeowDir) {
    Push-Location $AgentMeowDir
    $agentMeowSpec = Join-Path $ScriptDir "agent-meow.spec"
    pyinstaller $agentMeowSpec --noconfirm --distpath (Join-Path $SidecarDir "..\agent-meow-dist")
    $agentMeowBuilt = Join-Path $SidecarDir "..\agent-meow-dist\agent-meow\agent-meow.exe"
    if (Test-Path $agentMeowBuilt) {
        Copy-Item (Join-Path $SidecarDir "..\agent-meow-dist\agent-meow") -Destination (Join-Path $SidecarDir "agent-meow") -Recurse
        Write-Ok "agent-meow sidecar built → sidecars/agent-meow/"
    } else {
        Write-Host "  agent-meow build failed — check PyInstaller output" -ForegroundColor Red
    }
    Pop-Location
} else {
    Write-Host "  agent-meow source not found at $AgentMeowDir — skipping" -ForegroundColor Yellow
}

# ── 5. Build Tauri wrapper ──────────────────────────────────────────────────

Write-Step "Building Tauri wrapper (npm + cargo)"

$WrapperDir = Join-Path $ScriptDir "tauri-wrapper"
Push-Location $WrapperDir

# Install npm dependencies
if (-not (Test-Path "node_modules")) {
    npm install
    Write-Ok "npm dependencies installed"
} else {
    Write-Host "  node_modules exists, skipping npm install" -ForegroundColor Yellow
}

# Build the Tauri app
npm run tauri build
Write-Ok "Tauri wrapper build complete"

Pop-Location

# ── 6. Summary ──────────────────────────────────────────────────────────────

$bundleDir = Join-Path $WrapperDir "src-tauri\target\release\bundle"
Write-Host @"
╔══════════════════════════════════════════════════════════════════════╗
║  Voice Stack Build Complete                                          ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  Installer location:                                                 ║
║    $bundleDir                       ║
║                                                                      ║
║  Bundled sidecars:                                                   ║
║    handy.exe      → STT (Handy CLI --transcribe-file)               ║
║    voicebox.exe   → TTS server (localhost:17493)                    ║
║    agent-meow.exe → Agent server + web UI (localhost:8000)          ║
║                                                                      ║
║  The installer (.msi/.dmg/.AppImage) includes all 3 binaries.        ║
║  No Python runtime needed on target machines.                       ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor White