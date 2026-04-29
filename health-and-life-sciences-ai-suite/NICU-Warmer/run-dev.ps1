<#!
.SYNOPSIS
  Development convenience script to launch NICU Warmer backend (Flask + SSE) and Next.js frontend.

.DESCRIPTION
  Provides parameterized startup for:
    - Backend: Python Flask server (dashboard.py)
  - Frontend: Next.js dev server (nicu-dashboard)
  Supports optional dependency installation (pip + npm) and choosing video source (camera index or file).

.EXAMPLES
  # Run with defaults (camera index 0, local inference, start both services)
  ./run-dev.ps1

  # Use a video file as source and enable debug + performance telemetry
  ./run-dev.ps1 -UseVideoFile -VideoFile Warmer_Testbed_YTHD.mp4 -Debug -Performance

  # OVMS mode with explicit server URL and skip frontend
  ./run-dev.ps1 -Inference ovms -OvmsUrl http://localhost:9000 -NoFrontend

  # Only frontend (assuming backend already running elsewhere)
  ./run-dev.ps1 -NoBackend

  # Reinstall / ensure dependencies first
  ./run-dev.ps1 -InstallDeps

.PARAMETER Inference
  Inference mode: local | ovms

.PARAMETER OvmsUrl
  Base OVMS REST endpoint when using ovms mode.

.PARAMETER VideoFile
  Path to a video file (used when -UseVideoFile supplied).

.PARAMETER Camera
  Camera index (ignored if -UseVideoFile specified).

.PARAMETER UseVideoFile
  Switch to use VideoFile instead of camera index.

.PARAMETER Debug
  Enable debug logging in backend.

.PARAMETER Performance
  Enable performance telemetry logging in backend.

.PARAMETER NoFrontend
  Skip launching the Next.js frontend.

.PARAMETER NoBackend
  Skip launching the Python backend.

.PARAMETER InstallDeps
  Ensure Python and Node dependencies before launching.

.PARAMETER Python
  Python executable (default 'python'). Override if using pyenv/venv explicitly (e.g. '.venv/Scripts/python.exe').

.PARAMETER BackendPath
  Path to backend root containing dashboard.py (default current directory).

.PARAMETER FrontendPath
  Path to frontend (default 'nicu-dashboard').

.NOTES
  Press Ctrl+C to terminate. This script starts each service in a background Job so they continue until stopped.
!>
param(
    [ValidateSet('local','ovms')] [string]$Inference = 'local',
    [string]$OvmsUrl = 'http://localhost:9000',
    [string]$VideoFile = 'Warmer_Testbed_YTHD.mp4',
    [int]$Camera = 0,
    [switch]$UseVideoFile,
    [switch]$Debug,
    [switch]$Performance,
    [switch]$NoFrontend,
    [switch]$NoBackend,
    [switch]$InstallDeps,
    [switch]$SkipNodeLegacy,
    [string]$Python = 'python',
    [string]$BackendPath = '.',
  [string]$FrontendPath = 'nicu-dashboard'
)

function Write-Section($Title) {
    Write-Host "`n==== $Title ====\n" -ForegroundColor Cyan
}

function Invoke-Checked($Cmd, $Description) {
    Write-Host "[RUN] $Description" -ForegroundColor DarkGray
    & $Cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Command failed (exit $LASTEXITCODE): $Cmd"
        throw "Aborting due to failure running: $Description"
    }
}

function Ensure-PythonDeps {
    if (-not (Test-Path "$BackendPath/requirements.txt")) { return }
    Write-Section "Python Dependencies"
    Invoke-Checked "$Python -m pip install --upgrade pip" "Upgrade pip"
    Invoke-Checked "$Python -m pip install -r $BackendPath/requirements.txt" "Install backend requirements"
}

function Ensure-NodeDeps {
    if (-not (Test-Path (Join-Path $FrontendPath 'package.json'))) { return }
    Write-Section "Node Dependencies"
    Push-Location $FrontendPath
    try {
        Invoke-Checked "npm install" "npm install"
    } finally { Pop-Location }
}

if ($InstallDeps) {
    if (-not $NoBackend) { Ensure-PythonDeps }
    if (-not $NoFrontend) { Ensure-NodeDeps }
}

$backendArgs = @('--inference', $Inference, '--ovms_url', $OvmsUrl)
if ($UseVideoFile) {
    $backendArgs += @('--file', $VideoFile)
} else {
    $backendArgs += @('--camera', $Camera)
}
if ($Debug) { $backendArgs += '--debug' }
if ($Performance) { $backendArgs += '--performance' }

$jobs = @()

if (-not $NoBackend) {
    Write-Section "Launching Backend"
    if (-not (Test-Path (Join-Path $BackendPath 'dashboard.py'))) {
        throw "dashboard.py not found at path: $BackendPath"
    }
    $argLine = $backendArgs -join ' '
    Write-Host "Backend Command: $Python dashboard.py $argLine" -ForegroundColor Green
    $jobs += Start-Job -Name NICUBackend -ScriptBlock {
        param($Path,$Py,$Args)
        Set-Location $Path
        & $Py dashboard.py @Args
    } -ArgumentList (Resolve-Path $BackendPath), $Python, $backendArgs
}

if (-not $NoFrontend) {
    Write-Section "Launching Frontend"
    if (-not (Test-Path $FrontendPath)) { throw "Frontend path not found: $FrontendPath" }
    Push-Location $FrontendPath
    if (-not $SkipNodeLegacy) {
        $env:NODE_OPTIONS = "--openssl-legacy-provider"
    }
    $jobs += Start-Job -Name NICUFrontend -ScriptBlock {
        param($Path,$UseLegacy)
        Set-Location $Path
        if ($UseLegacy) { $env:NODE_OPTIONS = "--openssl-legacy-provider" }
        & npm run dev
    } -ArgumentList (Resolve-Path $FrontendPath), (-not $SkipNodeLegacy)
    Pop-Location
}

Write-Section "Status"
if ($jobs.Count -eq 0) {
    Write-Host "No jobs started (check -NoBackend / -NoFrontend flags)." -ForegroundColor Yellow
} else {
    $jobs | ForEach-Object { Write-Host ("Started Job: {0} (Id={1})" -f $_.Name, $_.Id) -ForegroundColor Green }
    Write-Host "Use: Get-Job; Receive-Job -Name NICUBackend -Keep; Receive-Job -Name NICUFrontend -Keep" -ForegroundColor DarkGray
}

Write-Host "`nPress Ctrl+C to stop all running jobs..." -ForegroundColor Cyan

# Graceful shutdown on Ctrl+C
$script:stopping = $false
Register-EngineEvent PowerShell.Exiting -Action {
    if ($script:stopping) { return }
    $script:stopping = $true
    Write-Host "\nStopping jobs..." -ForegroundColor Yellow
    Get-Job -Name NICUBackend,NICUFrontend -ErrorAction SilentlyContinue | Stop-Job -Force
    Get-Job -Name NICUBackend,NICUFrontend -ErrorAction SilentlyContinue | Remove-Job -Force
}

# Block until all jobs finish (user interruption)
while ($true) {
    Start-Sleep -Seconds 2
    $alive = Get-Job -Name NICUBackend,NICUFrontend -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Running' }
    if (-not $alive) { break }
}

Write-Host "All jobs exited." -ForegroundColor Cyan
