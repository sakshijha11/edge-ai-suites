# Get Started

This guide takes you from a fresh clone to a running segmentation pop-up on a
Windows machine with an Intel Core Ultra (Intel Arc iGPU).

## Prerequisites

- Windows 11 with an Intel Core Ultra processor (Intel Arc iGPU).
- Up-to-date Intel graphics drivers (the iGPU must appear in Task Manager and be
  visible to OpenVINO).
- Python 3.11 (64-bit) on `PATH`.
- PowerShell. If scripts are blocked, allow them for the current session only:

  ```powershell
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  ```

## 1. Install runtime dependencies

From the `ultrasound-ovarian-segmentation` folder:

```powershell
.\setup.ps1
```

This creates a local `venv` and installs the runtime dependencies
(`requirements.txt`): OpenVINO, OpenCV, NumPy, and pywin32 (for the GPU-Engine
counters the governor reads).

## 2. Prepare the model

The app does not ship a trained model. Produce the OpenVINO IR the app loads
(`models/ds2net_segformer_b5_256/model.xml`):

```powershell
.\prepare_model.ps1 -Verify          # if you already have models\segformer_b5_mmotu
# or
.\prepare_model.ps1 -Train -Verify   # train on the Intel iGPU first, then export
```

To use the optional prompted SAM-256 arch instead, add `-Arch sam` (it needs the
stock SAM ViT-B weights downloaded first):

```powershell
.\prepare_model.ps1 -Arch sam -Verify
```

Full walkthrough — dataset, backbone, training, export, expected Dice — in
[Model Preparation](./get-started/model-preparation.md).

## 3. Run the segmentation pop-up

```powershell
.\run.ps1 -Source file -Input C:\path\to\clip.mp4 -Device GPU
```

A window opens showing each frame with the tumor-mask overlay, plus a HUD
showing inference FPS/latency and live iGPU utilization. Press `q` or `Esc` to
quit, or close the window.

Other sources:

```powershell
.\run.ps1 -Source folder -Input C:\path\to\frames -Device GPU
.\run.ps1 -Source webcam -Input 0 -Device GPU
```

Run the prompted SAM-256 arch (after preparing its IRs):

```powershell
.\run.ps1 -Arch sam -Source file -Input C:\path\to\clip.mp4 -Device GPU
```

## 4. Confirm the GPU KPI

On exit the app prints the governor verdict, for example:

```text
GPU KPI (< 80%): PASS — peak busiest-engine 17.8% mean 11.5% (samples=900, throttle_engaged=False)
```

`PASS` means sustained Intel iGPU busiest-engine utilization stayed under the 80%
cap for the whole run. On typical ultrasound workloads the pipeline is host-bound
(~12–24% iGPU), so `throttle_engaged=False` is expected — the governor is a proven
safety net rather than a bottleneck. See
[Runtime Configuration](./runtime-configuration.md) to change the cap or disable
the governor to measure uncapped utilization.

## Next steps

- [Runtime Configuration](./runtime-configuration.md) — all flags / env vars.
- [Troubleshooting](./troubleshooting.md) — device not found, no pop-up, low Dice.
