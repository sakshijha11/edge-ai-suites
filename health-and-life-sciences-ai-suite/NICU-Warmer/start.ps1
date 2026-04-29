#!/usr/bin/env pwsh
# Simple startup script for NICU Warmer demo
# Launches backend (Python) + frontend (Next.js) with sensible defaults

param(
    [string]$VideoFile = "Warmer_Testbed_YTHD.mp4",
    [switch]$Realtime,
    [switch]$NoBrowser
)

Write-Host "=== NICU Warmer Quick Start ===" -ForegroundColor Cyan
Write-Host ""

# Check if video file exists
if (-not (Test-Path $VideoFile)) {
    Write-Host "ERROR: Video file '$VideoFile' not found in current directory." -ForegroundColor Red
    Write-Host "Please ensure $VideoFile is present or modify this script." -ForegroundColor Yellow
    exit 1
}

# Check Python is available
try {
    $null = python --version 2>&1
} catch {
    Write-Host "ERROR: Python not found. Please install Python 3.11+ and ensure it's in PATH." -ForegroundColor Red
    exit 1
}

# Check Node is available
try {
    $null = node --version 2>&1
} catch {
    Write-Host "ERROR: Node.js not found. Please install Node.js 18+ and ensure it's in PATH." -ForegroundColor Red
    exit 1
}

# Check if ports are already in use
$BackendPort = 5000
$FrontendPort = 3000

$BackendInUse = Get-NetTCPConnection -LocalPort $BackendPort -State Listen -ErrorAction SilentlyContinue
$FrontendInUse = Get-NetTCPConnection -LocalPort $FrontendPort -State Listen -ErrorAction SilentlyContinue

if ($BackendInUse) {
    Write-Host "WARNING: Port $BackendPort already in use. Backend may already be running." -ForegroundColor Yellow
    Write-Host "         PID: $($BackendInUse.OwningProcess) - Use .\stop.ps1 to clean up." -ForegroundColor Yellow
    $Continue = Read-Host "Continue anyway? (y/N)"
    if ($Continue -ne 'y') { exit 1 }
}

if ($FrontendInUse) {
    Write-Host "WARNING: Port $FrontendPort already in use. Frontend may already be running." -ForegroundColor Yellow
    Write-Host "         PID: $($FrontendInUse.OwningProcess) - Use .\stop.ps1 to clean up." -ForegroundColor Yellow
    $Continue = Read-Host "Continue anyway? (y/N)"
    if ($Continue -ne 'y') { exit 1 }
}

Write-Host "[1/2] Starting backend (Flask + OpenVINO)..." -ForegroundColor Green
Write-Host ("      Video: {0} | Playback: {1} | Display: OFF" -f $VideoFile, ($(if ($Realtime) { 'real-time (skip frames)' } else { 'smooth (no skipping)' }))) -ForegroundColor Gray

# Start backend in background
$BackendArgs = @(
    "dashboard.py",
    "--file", $VideoFile,
    "--no-display"
)

if ($Realtime) {
    $BackendArgs += "--file-realtime"
}

$BackendProcess = Start-Process -FilePath "python" `
    -ArgumentList $BackendArgs `
    -PassThru `
    -NoNewWindow `
    -RedirectStandardOutput "backend.log" `
    -RedirectStandardError "backend-error.log"

# Save PID for cleanup script
$BackendProcess.Id | Out-File ".backend.pid" -Encoding ASCII

Write-Host "      Backend PID: $($BackendProcess.Id) (saved to .backend.pid)" -ForegroundColor Gray
Write-Host "      Logs: backend.log / backend-error.log" -ForegroundColor Gray
Write-Host ""

# Wait a moment for backend to start
Start-Sleep -Seconds 3

# Check backend health
try {
    $Response = Invoke-WebRequest -Uri "http://localhost:5000/api/health" -TimeoutSec 5 -UseBasicParsing
    if ($Response.StatusCode -eq 200) {
        Write-Host "      Backend running at http://localhost:5000" -ForegroundColor Green
    }
} catch {
    Write-Host "      WARNING: Backend may not be ready yet (will retry)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[2/2] Starting frontend (Next.js)..." -ForegroundColor Green
Write-Host "      Dashboard will open at http://localhost:3000" -ForegroundColor Gray

# Navigate to frontend and start dev server
Push-Location nicu-dashboard

# Check if node_modules exists
if (-not (Test-Path "node_modules")) {
    Write-Host "      First run detected - installing dependencies..." -ForegroundColor Yellow
    npm install
}

# Set Node legacy provider (for TFJS compatibility)
$env:NODE_OPTIONS = "--openssl-legacy-provider"

# Start frontend (this will block; use Ctrl+C to stop both)
Write-Host ""
Write-Host "=== Services Running ===" -ForegroundColor Cyan
Write-Host "Backend:  http://localhost:5000 (PID: $($BackendProcess.Id))" -ForegroundColor White
Write-Host "Frontend: http://localhost:3000 (starting...)" -ForegroundColor White
Write-Host ""
Write-Host "Press Ctrl+C to stop all services" -ForegroundColor Yellow
Write-Host ""

# Auto-open browser unless disabled
if (-not $NoBrowser) {
    Write-Host "Opening browser in 3 seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 3
    Start-Process "http://localhost:3000"
}

try {
    # Run npm dev (this blocks)
    npm run dev
} finally {
    # Cleanup: stop backend when frontend exits
    Pop-Location
    Write-Host ""
    Write-Host "Stopping backend..." -ForegroundColor Yellow
    Stop-Process -Id $BackendProcess.Id -Force -ErrorAction SilentlyContinue
    
    # Clean up PID file
    if (Test-Path ".backend.pid") {
        Remove-Item ".backend.pid" -Force
    }
    
    Write-Host "Done." -ForegroundColor Green
}
