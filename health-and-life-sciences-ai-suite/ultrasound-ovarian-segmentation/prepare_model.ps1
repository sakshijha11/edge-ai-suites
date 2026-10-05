# Copyright © 2026 Intel Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Model preparation: export (and optionally train) the DS2Net SegFormer-B5 model
# and place its fp16 OpenVINO IR where the app expects it.
#
# The app does NOT ship a trained IR. Run this once to produce
#   models\ds2net_segformer_b5_<Res>\model.xml
# before launching .\run.ps1.
#
# Usage (from this folder, PowerShell, after .\setup.ps1):
#   # Export an existing trained checkpoint -> IR, then verify Dice:
#   .\prepare_model.ps1 -Verify
#
#   # Train from scratch on the Intel iGPU first, then export + verify:
#   .\prepare_model.ps1 -Train -Verify
#
[CmdletBinding()]
param(
    [string]$Checkpoint = "models\segformer_b5_mmotu",
    [int]$Res = 256,
    [string]$Data = "data\OTU_2d",
    [ValidateSet("GPU", "CPU", "NPU")]
    [string]$Device = "GPU",
    [switch]$Train,
    [switch]$Verify,
    [string]$Venv = "venv"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$py = Join-Path $Venv "Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Error "virtual environment not found ($py). Run .\setup.ps1 first."
}

Write-Host "[prepare] installing model-prep dependencies (backend\requirements.txt)"
& $py -m pip install -r backend\requirements.txt

if ($Train) {
    Write-Host "[prepare] training SegFormer-B5 on MMOTU-2D (this is the long step)"
    & $py -m backend.bootstrap.train --data $Data --res $Res --device xpu --out $Checkpoint
    if ($LASTEXITCODE -ne 0) { Write-Error "training failed" }
}

if (-not (Test-Path $Checkpoint)) {
    Write-Error ("trained checkpoint not found: $Checkpoint`n" +
        "Train it first with:  .\prepare_model.ps1 -Train`n" +
        "or point -Checkpoint at an existing HF SegFormer checkpoint.")
}

$irDir = "models\ds2net_segformer_b5_$Res"
Write-Host "[prepare] exporting $Checkpoint -> $irDir (fp16 OpenVINO IR)"
& $py -m backend.bootstrap.export --from-pretrained $Checkpoint --res $Res --out $irDir
if ($LASTEXITCODE -ne 0) { Write-Error "export failed" }

$irXml = Join-Path $irDir "model.xml"
if (-not (Test-Path $irXml)) { Write-Error "export did not produce $irXml" }

if ($Verify) {
    Write-Host "[prepare] verifying Dice/IoU on the MMOTU-2D val split (device=$Device)"
    & $py -m backend.bootstrap.eval --ir $irXml --res $Res --data $Data --device $Device
    if ($LASTEXITCODE -ne 0) { Write-Error "eval failed" }
    Write-Host "[prepare] expected reference at res 256: Dice ~0.8657 / IoU ~0.7913"
}

Write-Host "[prepare] done. Model ready at $irXml"
Write-Host "[prepare] launch the demo:"
Write-Host "  .\run.ps1 -Source file -Input <clip.mp4> -Device $Device"
