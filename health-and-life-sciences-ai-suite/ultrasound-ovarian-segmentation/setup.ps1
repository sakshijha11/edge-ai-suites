# Copyright © 2026 Intel Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# One-time setup: create a local virtual environment and install runtime deps.
# Usage (from this folder, PowerShell):
#   .\setup.ps1
#
[CmdletBinding()]
param(
    [string]$Python = "python",
    [string]$Venv = "venv"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path $Venv)) {
    Write-Host "[setup] creating virtual environment: $Venv"
    & $Python -m venv $Venv
}

$py = Join-Path $Venv "Scripts\python.exe"
Write-Host "[setup] upgrading pip"
& $py -m pip install --upgrade pip wheel
Write-Host "[setup] installing requirements.txt"
& $py -m pip install -r requirements.txt

Write-Host "[setup] done. Next:"
Write-Host "  .\prepare_model.ps1 -Verify                 # produce models\ds2net_segformer_b5_256\model.xml"
Write-Host "  .\run.ps1 -Source file -Input <clip.mp4>    # segment a video"
Write-Host "  (model prep walkthrough: docs/user-guide/get-started/model-preparation.md)"
