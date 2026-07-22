<#
.SYNOPSIS
  Voice Stack Installer — Handy (STT) + Voicebox (TTS) + agent-meow (Agent)
.DESCRIPTION
  Single bootstrap script that installs all three voice integration components
  on Windows, configures environment variables, and sets up Windows services
  for background auto-start.

  Architecture:
    Handy       → Desktop app + CLI (--transcribe-file --json), tray-resident
    Voicebox    → Python FastAPI server on localhost:17493 (TTS, 7 engines)
    agent-meow  → Python server + web UI on localhost:8000 (agent execution)

  agent-meow discovers Handy via HANDY_CLI_PATH and Voicebox via VOICEBOX_URL.
.PARAMETER InstallDir
  Base directory for Voicebox and agent-meow venvs. Default: C:\voice-stack
.PARAMETER HandyMsi
  Path to the Handy .msi installer. If omitted, downloads from handy.computer.
.PARAMETER SkipHandy
  Skip Handy installation (use if Handy is already installed).
.PARAMETER SkipVoicebox
  Skip Voicebox installation.
.PARAMETER SkipAgentMeow
  Skip agent-meow installation.
.EXAMPLE
  .\install-voice-stack.ps1
.EXAMPLE
  .\install-voice-stack.ps1 -HandyMsi "C:\Downloads\Handy_0.9.4_x64.msi" -InstallDir "D:\apps\voice-stack"
#>

param(
    [string]$InstallDir = "C:\voice-stack",
    [string]$HandyMsi = "",
    [switch]$SkipHandy,
    [switch]$SkipVoicebox,
    [switch]$SkipAgentMeow
)

$ErrorActionPreference = "Stop"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host "`n[INSTALL] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [ERROR] $Message" -ForegroundColor Red
}

function Test-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    return $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Set-SystemEnvVar {
    param([string]$Name, [string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, "Machine")
    # Also set for current session
    Set-Item -Path "Env:$Name" -Value $Value
    Write-Ok "Set $Name = $Value"
}

function New-PythonVenv {
    param([string]$VenvPath, [string]$PackageName)
    if (Test-Path $VenvPath) {
        Write-Host "  Venv already exists at $VenvPath, reusing..." -ForegroundColor Yellow
    } else {
        python -m venv $VenvPath
        Write-Ok "Created venv at $VenvPath"
    }
    $pip = Join-Path $VenvPath "Scripts\pip.exe"
    & $pip install --upgrade pip 2>$null
    & $pip install $PackageName
    Write-Ok "Installed $PackageName in $VenvPath"
}

function New-WindowsService {
    param(
        [string]$Name,
        [string]$BinPath,
        [string]$DisplayName
    )
    # Check if service already exists
    $existing = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Service '$Name' already exists, skipping..." -ForegroundColor Yellow
        return
    }
    # Use nssm (Non-Sucking Service Manager) if available, else use sc.exe
    $nssm = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssm) {
        & nssm install $Name $BinPath
        & nssm set $Name DisplayName $DisplayName
        & nssm set $Name Start SERVICE_AUTO_START
        & nssm start $Name
        Write-Ok "Service '$Name' created and started (via nssm)"
    } else {
        # Fallback: create a scheduled task that runs at logon
        $action = New-ScheduledTaskAction -Execute $BinPath
        $trigger = New-ScheduledTaskTrigger -AtLogon
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force
        Write-Ok "Scheduled task '$Name' created (nssm not found, using Task Scheduler)"
    }
}

# ── Pre-flight checks ────────────────────────────────────────────────────────

Write-Host @"
╔══════════════════════════════════════════════════════════════════════╗
║         Voice Stack Installer                                        ║
║  Handy (STT) + Voicebox (TTS) + agent-meow (Agent)                   ║
╚══════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor White

if (-not (Test-Admin)) {
    Write-Err "This script requires Administrator privileges."
    Write-Host "  Please re-run as Administrator." -ForegroundColor Yellow
    exit 1
}

# Check Python
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Err "Python is not installed or not in PATH."
    Write-Host "  Install Python 3.12+ from https://python.org" -ForegroundColor Yellow
    exit 1
}
$pyVersion = (python --version 2>&1)
Write-Ok "Found $pyVersion"

# Create install directory
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Ok "Created install directory: $InstallDir"
}

# ── 1. Install Handy ─────────────────────────────────────────────────────────

if (-not $SkipHandy) {
    Write-Step "Installing Handy (STT desktop app + CLI)"

    # Check if Handy is already installed
    $handyExe = "C:\Program Files\Handy\handy.exe"
    if (Test-Path $handyExe) {
        Write-Host "  Handy is already installed at $handyExe" -ForegroundColor Yellow
    } else {
        if ($HandyMsi -and (Test-Path $HandyMsi)) {
            Write-Host "  Installing from: $HandyMsi"
            Start-Process msiexec.exe -ArgumentList "/i `"$HandyMsi`" /quiet /norestart" -Wait
        } else {
            Write-Host "  Downloading Handy installer from handy.computer..." -ForegroundColor Yellow
            $downloadUrl = "https://github.com/cjpais/Handy/releases/latest"
            Write-Host "  Please download the latest .msi from:" -ForegroundColor Yellow
            Write-Host "    $downloadUrl" -ForegroundColor Yellow
            Write-Host "  Then re-run with -HandyMsi <path>" -ForegroundColor Yellow
            $HandyMsi = Read-Host "  Enter path to Handy .msi (or press Enter to skip)"
            if ($HandyMsi -and (Test-Path $HandyMsi)) {
                Start-Process msiexec.exe -ArgumentList "/i `"$HandyMsi`" /quiet /norestart" -Wait
            } else {
                Write-Host "  Skipping Handy MSI install. Make sure Handy is installed manually." -ForegroundColor Yellow
            }
        }
        # Re-check
        if (Test-Path $handyExe) {
            Write-Ok "Handy installed successfully"
        }
    }

    # Set HANDY_CLI_PATH
    if (Test-Path $handyExe) {
        Set-SystemEnvVar -Name "HANDY_CLI_PATH" -Value $handyExe
    } else {
        # Fallback: try portable location
        $portableHandy = Join-Path $InstallDir "handy\handy.exe"
        if (Test-Path $portableHandy) {
            Set-SystemEnvVar -Name "HANDY_CLI_PATH" -Value $portableHandy
        } else {
            Write-Err "handy.exe not found. Set HANDY_CLI_PATH manually after installing Handy."
        }
    }
}

# ── 2. Install Voicebox ──────────────────────────────────────────────────────

$voiceboxVenv = Join-Path $InstallDir "voicebox-venv"
$voiceboxExe = Join-Path $voiceboxVenv "Scripts\voicebox.exe"
$voiceboxUrl = "http://127.0.0.1:17493"

if (-not $SkipVoicebox) {
    Write-Step "Installing Voicebox (TTS server on $voiceboxUrl)"

    New-PythonVenv -VenvPath $voiceboxVenv -PackageName "voicebox"

    if (Test-Path $voiceboxExe) {
        Write-Ok "Voicebox installed: $voiceboxExe"
        Set-SystemEnvVar -Name "VOICEBOX_URL" -Value $voiceboxUrl

        # Create Windows service
        New-WindowsService -Name "Voicebox" `
            -BinPath $voiceboxExe `
            -DisplayName "Voicebox TTS Server"
    } else {
        Write-Err "Voicebox executable not found after install."
        Write-Host "  Check that the 'voicebox' package is available." -ForegroundColor Yellow
    }
}

# ── 3. Install agent-meow ────────────────────────────────────────────────────

$agentMeowVenv = Join-Path $InstallDir "agent-meow-venv"
$agentMeowExe = Join-Path $agentMeowVenv "Scripts\agent-meow.exe"
$agentMeowUrl = "http://127.0.0.1:8000"

if (-not $SkipAgentMeow) {
    Write-Step "Installing agent-meow (agent server on $agentMeowUrl)"

    New-PythonVenv -VenvPath $agentMeowVenv -PackageName "agent-meow"

    if (Test-Path $agentMeowExe) {
        Write-Ok "agent-meow installed: $agentMeowExe"

        # Create Windows service
        New-WindowsService -Name "AgentMeow" `
            -BinPath $agentMeowExe `
            -DisplayName "agent-meow Agent Server"
    } else {
        Write-Err "agent-meow executable not found after install."
        Write-Host "  Check that the 'agent-meow' package is available." -ForegroundColor Yellow
    }
}

# ── 4. Summary ───────────────────────────────────────────────────────────────

Write-Host @"
╔══════════════════════════════════════════════════════════════════════╗
║  Installation Complete                                               ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  Handy (STT)         $(if (Test-Path "C:\Program Files\Handy\handy.exe") { '✅ C:\Program Files\Handy' } else { '⚠️  Install manually' })
║  Voicebox (TTS)      $(if (Test-Path $voiceboxExe) { "✅ $voiceboxUrl" } else { '⚠️  Skipped' })
║  agent-meow (Agent)  $(if (Test-Path $agentMeowExe) { "✅ $agentMeowUrl" } else { '⚠️  Skipped' })
║                                                                      ║
║  Environment variables set:                                          ║
║    HANDY_CLI_PATH  = $(if ($env:HANDY_CLI_PATH) { $env:HANDY_CLI_PATH } else { '(not set)' })
║    VOICEBOX_URL    = $(if ($env:VOICEBOX_URL) { $env:VOICEBOX_URL } else { '(not set)' })
║                                                                      ║
║  Next steps:                                                         ║
║    1. Reboot or re-open terminal for env vars to take effect         ║
║    2. Launch Handy from Start Menu (tray icon appears)               ║
║    3. Voicebox + agent-meow auto-start as services                   ║
║    4. Open agent-meow UI at $agentMeowUrl                         ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor White