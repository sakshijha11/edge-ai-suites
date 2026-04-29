#!/usr/bin/env pwsh
# Stop script for NICU Warmer
# Kills backend and frontend processes

Write-Host "=== NICU Warmer Cleanup ===" -ForegroundColor Cyan
Write-Host ""

$Stopped = $false

# Try to stop backend via PID file
if (Test-Path ".backend.pid") {
    $BackendPID = Get-Content ".backend.pid" -Raw
    $BackendPID = $BackendPID.Trim()
    
    if ($BackendPID -match '^\d+$') {
        try {
            $Process = Get-Process -Id $BackendPID -ErrorAction SilentlyContinue
            if ($Process) {
                Write-Host "Stopping backend (PID: $BackendPID)..." -ForegroundColor Yellow
                Stop-Process -Id $BackendPID -Force
                $Stopped = $true
                Write-Host "  Backend stopped." -ForegroundColor Green
            } else {
                Write-Host "Backend PID $BackendPID not running (stale PID file)." -ForegroundColor Gray
            }
        } catch {
            Write-Host "Could not stop backend PID $BackendPID : $_" -ForegroundColor Red
        }
    }
    
    Remove-Item ".backend.pid" -Force -ErrorAction SilentlyContinue
}

# Also check by port
$BackendPort = 5000
$FrontendPort = 3000

$BackendConn = Get-NetTCPConnection -LocalPort $BackendPort -State Listen -ErrorAction SilentlyContinue
if ($BackendConn) {
    $PID = $BackendConn.OwningProcess
    Write-Host "Found process on port $BackendPort (PID: $PID)..." -ForegroundColor Yellow
    try {
        Stop-Process -Id $PID -Force
        $Stopped = $true
        Write-Host "  Stopped." -ForegroundColor Green
    } catch {
        Write-Host "  Could not stop: $_" -ForegroundColor Red
    }
}

$FrontendConn = Get-NetTCPConnection -LocalPort $FrontendPort -State Listen -ErrorAction SilentlyContinue
if ($FrontendConn) {
    $PID = $FrontendConn.OwningProcess
    Write-Host "Found process on port $FrontendPort (PID: $PID)..." -ForegroundColor Yellow
    try {
        Stop-Process -Id $PID -Force
        $Stopped = $true
        Write-Host "  Stopped." -ForegroundColor Green
    } catch {
        Write-Host "  Could not stop: $_" -ForegroundColor Red
    }
}

# Also kill any lingering node/python processes (optional aggressive cleanup)
# Note: We can't reliably check command line args on Windows without admin rights,
# so we'll just list them and let user manually kill if needed
$PythonProcs = Get-Process -Name python -ErrorAction SilentlyContinue
if ($PythonProcs -and $PythonProcs.Count -gt 0) {
    Write-Host "Found $($PythonProcs.Count) Python process(es) still running." -ForegroundColor Yellow
    Write-Host "  If dashboard.py is still running, manually kill with: Stop-Process -Id <PID> -Force" -ForegroundColor Gray
}

$NodeProcs = Get-Process -Name node -ErrorAction SilentlyContinue
if ($NodeProcs -and $NodeProcs.Count -gt 0) {
    Write-Host "Found $($NodeProcs.Count) Node.js process(es) still running." -ForegroundColor Yellow
    Write-Host "  If Next.js dev server is still running, manually kill with: Stop-Process -Id <PID> -Force" -ForegroundColor Gray
}

if (-not $Stopped) {
    Write-Host "No running processes found." -ForegroundColor Gray
}

Write-Host ""
Write-Host "Cleanup complete." -ForegroundColor Cyan
