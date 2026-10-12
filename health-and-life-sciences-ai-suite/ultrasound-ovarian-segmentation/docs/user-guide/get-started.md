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

A window opens showing the **original frame next to the segmented frame**
(tumor-mask overlay), plus a HUD showing inference FPS/latency and live iGPU
utilization; pass `--view overlay` for a single overlaid pane. Press `q` or `Esc`
to quit, or close the window.

Other sources:

```powershell
.\run.ps1 -Source folder -Input C:\path\to\frames -Device GPU
.\run.ps1 -Source webcam -Input 0 -Device GPU
```

Run the prompted SAM-256 arch (after preparing its IRs):

```powershell
.\run.ps1 -Arch sam -Source file -Input C:\path\to\clip.mp4 -Device GPU
```

## 4. Run the web dashboard (UI)

The web dashboard is the primary way to drive the app: on top of the same
`src/` pipeline the CLI uses, it adds device/use-case selection in the browser
plus live hardware utilization (CPU / iGPU / NPU / power / memory) and pipeline
KPIs.

The UI needs a few extra Python packages beyond the CLI (Flask + psutil, and
pandas for the power graph). On a connected box, add them to the `venv`:

```powershell
.\venv\Scripts\pip install -r webapp\requirements.txt
```

On an air-gapped box, point `-Venv` at a virtual environment that already has
them. Then launch (reuses the same `venv` by default):

```powershell
.\run_webapp.ps1
```

This serves the UI at <http://127.0.0.1:8080> and opens your browser. Then:

1. Pick a **Use case** (default *DS2Net Tumor Segmentation*), a **Device**
   (Intel iGPU or CPU), and **Precision** (FP16).
2. In **Video / image source**, enter the path to a clip (`.mp4`) or a folder of
   frames — or leave it blank to use `data\stills`.
3. Click **Start** in the top bar.

The segmentation video opens in a separate OpenCV pop-up (*Original |
Segmentation*); press **ESC** in that window, or **Stop** in the UI, to end the
run. The browser shows live inference latency / FPS, the iGPU KPI, and the
hardware-utilization graphs. Use `-Port 8090` to change the port or `-NoBrowser`
to skip launching the browser.

> **Hardware-utilization graphs.** CPU and memory come from `psutil` with no
> extra setup. The iGPU / NPU / power graphs use Intel vendor tools (SoCWatch,
> Level Zero) that are **not** committed. Stage them once by copying a
> `monitoring\tools` folder from your existing benchmark install into this
> clone, and make sure the `venv` has `pandas` + `pywin32`; without them the app
> still runs and shows CPU + memory.

## 5. Confirm the GPU KPI

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
