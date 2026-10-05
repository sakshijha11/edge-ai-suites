# Copyright © 2026 Intel Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Launch the ovarian tumor segmentation pop-up.
# Usage (from this folder, PowerShell):
#   .\run.ps1 -Source file   -Input C:\path\to\clip.mp4
#   .\run.ps1 -Source webcam -Input 0
#   .\run.ps1 -Source folder -Input C:\path\to\frames   -Device GPU
#
# Any extra flags are forwarded to the app, e.g.:
#   .\run.ps1 -Source file -Input clip.mp4 -- --gpu-cap 80 --record out.mp4
#
[CmdletBinding()]
param(
    [ValidateSet("file", "webcam", "folder")]
    [string]$Source = "file",
    [string]$Input = "",
    [ValidateSet("GPU", "CPU", "NPU", "AUTO")]
    [string]$Device = "GPU",
    [string]$Model = "",
    [string]$Venv = "venv",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Extra
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$py = Join-Path $Venv "Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Error "virtual environment not found ($py). Run .\setup.ps1 first."
}

$cliArgs = @("-m", "src.app", "--source", $Source, "--device", $Device)
if ($Input) { $cliArgs += @("--input", $Input) }
if ($Model) { $cliArgs += @("--model", $Model) }
if ($Extra) { $cliArgs += $Extra }

Write-Host "[run] $py $($cliArgs -join ' ')"
& $py @cliArgs
