# Troubleshooting

## `virtual environment not found`

Run `.\setup.ps1` from the `ultrasound-ovarian-segmentation` folder first. It
creates `venv` and installs `requirements.txt`.

## PowerShell blocks the scripts

Allow scripts for the current session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## `model IR not found: models\ds2net_segformer_b5_256\model.xml`

The app does not ship a model. Produce it:

```powershell
.\prepare_model.ps1 -Verify          # export an existing checkpoint
.\prepare_model.ps1 -Train -Verify   # or train first
```

See [Model Preparation](./get-started/model-preparation.md).

## Device not available / falls back to CPU

If `--device GPU` is not in OpenVINO's available devices, the app logs a warning
and falls back to CPU. Check that:

- Intel graphics drivers are installed and current.
- The device appears in Task Manager and `venv\Scripts\python.exe -c "import openvino as ov; print(ov.Core().available_devices)"` lists `GPU`.

> **NPU:** neither model (DS2Net or SAM) is supported on the NPU. Passing
> `--device NPU` logs a notice and uses the GPU (or CPU) instead.

## No pop-up window appears

- Make sure OpenCV has GUI support: `requirements.txt` installs `opencv-python`
  (not `opencv-python-headless`). A headless build renders no window. Verify with
  `venv\Scripts\python.exe -c "import cv2; print(cv2.getBuildInformation())"` and
  look for a GUI backend (e.g. WIN32UI).
- Run from an interactive desktop session (not a service / SSH-only session).
- Check the console for a source or device error that prevented the run from
  starting.

## Mean Dice is ~0 after export

Almost always one of:

- The IR was exported **without** `--from-pretrained` (random weights). Re-run
  `export.py --from-pretrained models\segformer_b5_mmotu --res 256`.
- `--res` does not match the resolution the IR was exported at.
- Dataset paths are wrong — `eval.py` could not find `images/` or
  `annotations/` under `--data`, or `val.txt` lists the wrong stems.

## SAM arch: IR not found or low Dice

With `-Arch sam` the app loads three IRs (YOLO bbox, SAM encoder, SAM decoder).
If any is missing, prepare them — and confirm the stock SAM ViT-B weights were
downloaded to `models\sam_vit_b_01ec64.pth` first:

```powershell
.\prepare_model.ps1 -Arch sam -Verify
```

A low end-to-end Dice (well under 0.82) usually means the encoder IR was exported
from random weights (missing `--weights models\sam256_stockft.pth`) or the
encoder was fine-tuned with the wrong preprocessing — the fine-tune and the
runtime must both scale images by `/255` (no mean/std). See
[Model Preparation](./get-started/model-preparation.md#sam-256-arch).

## GPU KPI prints `OVER`

Unexpected on typical ultrasound workloads (the pipeline is host-bound, ~12–24%
iGPU). If you see `OVER`, the device was saturated by other work, or the governor
was disabled (`--no-governor`). Re-run without `--no-governor`, or lower
`--gpu-cap` to pace inference down further.

## GPU HUD shows "unavailable" / governor inactive

The governor reads Windows GPU-Engine performance counters via **pywin32**. If
`pywin32` is missing, or you run on a non-Windows machine, the governor degrades
to a no-op and the HUD marks GPU utilization unavailable — the app still runs. On
Windows, reinstall deps: `.\setup.ps1`.

## Webcam opens the wrong camera

`--input` is the device index. Try `0`, `1`, `2`. Close other apps that may hold
the camera.
