# Ultrasound Ovarian Segmentation Sample App

> [!NOTE]
> This application is for **reference and evaluation purposes only**. It is
> **not intended for direct use in clinical or diagnostic environments** and is
> not validated for such a purpose.

Real-time ovarian tumor segmentation in 2D ultrasound using Intel hardware
acceleration (CPU / Intel iGPU / Intel NPU) with OpenVINO. The app runs a
**promptless SegFormer-B5 (DS2Net)** model — it takes the whole frame and
outputs a tumor mask, with no bounding-box prompt and no separate detector — and
overlays the mask on a live side-by-side pop-up window. A built-in **GPU
utilization cap** keeps the Intel iGPU under an 80% busiest-engine ceiling and
records the peak/mean so the KPI can be proven after a run.

|   |   |
|---|---|
| **Model** | DS2Net — promptless SegFormer MiT-B5, fp16 OpenVINO IR (Apache-2.0) |
| **Accuracy** | Dice 0.8657 / IoU 0.7913 on the MMOTU-2D val split (res 256) |
| **Inference** | Pure OpenVINO runtime (no PyTorch at run time) |
| **Runtime** | Native Windows Python app (PowerShell + venv) |
| **Inputs** | Video file, USB webcam, or a folder of ultrasound stills |
| **Display** | OpenCV pop-up with mask overlay + FPS / GPU HUD |
| **GPU cap** | Adaptive governor enforces the iGPU < 80% utilization KPI |

## Topology

Decoupled capture / inference / display threads, so the displayed video stays
smooth regardless of inference speed.

```text
source (file / webcam / folder)
        |
        v
  capture thread ──► display queue ──► display (main thread): overlay + HUD pop-up
        │
        └────────► inference queue ──► inference thread: OpenVINO SegFormer ──► mask
                                              │
                                              └── GPU governor paces this loop
                                                  if iGPU utilization nears the cap
```

## Model Preparation

This app does **not** ship a trained model. Produce the OpenVINO IR locally — it
lands at `models/ds2net_segformer_b5_256/model.xml`, the app's default. Two paths:

- **Export an existing checkpoint** — if you already have a trained SegFormer
  checkpoint at `models/segformer_b5_mmotu`:

  ```powershell
  .\setup.ps1                     # one-time: create venv + install runtime deps
  .\prepare_model.ps1 -Verify     # export checkpoint -> fp16 IR, then verify Dice
  ```

- **Train from scratch** — download the MMOTU-2D dataset and the MiT-B5 backbone,
  then train on the Intel iGPU before exporting:

  ```powershell
  .\setup.ps1
  .\prepare_model.ps1 -Train -Verify   # train -> export -> verify
  ```

See [Model Preparation](docs/user-guide/get-started/model-preparation.md) for the
full end-to-end walkthrough (dataset layout, backbone download, training, export,
and the expected Dice).

## Quickstart

From this directory, after model preparation:

```powershell
.\run.ps1 -Source file -Input C:\path\to\clip.mp4 -Device GPU
```

A pop-up window opens with the original frame on the left and the tumor-mask
overlay on the right. Press `q` or `Esc` to quit. On exit the app prints the GPU
KPI verdict, for example:

```text
GPU KPI (< 80%): PASS — peak busiest-engine 17.8% mean 11.5% (samples=900, throttle_engaged=False)
```

## Common Commands

Run against a folder of ultrasound stills (paced like a slideshow):

```powershell
.\run.ps1 -Source folder -Input C:\path\to\frames -Device GPU
```

Run against a USB webcam (device index 0):

```powershell
.\run.ps1 -Source webcam -Input 0 -Device GPU
```

Run on the CPU or NPU instead of the iGPU:

```powershell
.\run.ps1 -Source file -Input clip.mp4 -Device CPU
.\run.ps1 -Source file -Input clip.mp4 -Device NPU
```

Record an annotated video, or tighten the GPU cap (extra flags after `--` are
forwarded to the app):

```powershell
.\run.ps1 -Source file -Input clip.mp4 -- --record out.mp4 --gpu-cap 70
```

See [Runtime Configuration](docs/user-guide/runtime-configuration.md) for every
flag and environment variable.

## GPU Utilization Cap

The app builds a `GpuGovernor` per run (`src/gpu_governor.py`). A background
thread samples the Intel iGPU busiest-engine utilization from Windows GPU-Engine
performance counters; a proportional controller grows a small per-frame delay
when utilization approaches the target (70%) and hard-kicks it over the cap
(80%), so sustained iGPU utilization stays under the KPI ceiling. On real
ultrasound workloads the pipeline is host-bound (~12–24% iGPU), so the throttle
never engages — the cap is a proven safety net, not a bottleneck. The governor
degrades to a no-op on non-Windows machines (the counter source is unavailable),
so the code still imports and runs for development.

## Project Layout

```text
ultrasound-ovarian-segmentation/
  src/                      # runtime app (pure OpenVINO)
    app.py                  #   capture / inference / display pipeline + CLI
    config.py               #   CLI + env configuration
    segmenter.py            #   SegFormer IR -> tumor mask
    sources.py              #   file / webcam / folder capture
    display.py              #   overlay + HUD pop-up
    gpu_governor.py         #   adaptive iGPU < 80% utilization cap
  backend/                  # model preparation (train / export / eval)
    bootstrap/train.py      #   MMOTU-2D fine-tune of SegFormer-B5
    bootstrap/export.py     #   checkpoint -> fp16 OpenVINO IR
    bootstrap/eval.py       #   Dice / IoU verification on the val split
    requirements.txt        #   training/export deps (torch, transformers, ...)
  monitoring/windows/       # Windows GPU-Engine counter source for the governor
  models/                   # produced locally (git-ignored); see models/README.md
  docs/user-guide/          # setup, runtime configuration, troubleshooting
  setup.ps1                 # create venv + install runtime deps
  prepare_model.ps1         # train/export the model into models/
  run.ps1                   # launch the segmentation pop-up
  requirements.txt          # runtime deps (openvino, opencv, numpy, pywin32)
```

## License

Apache-2.0. See [third_party_programs_ultrasound-ovarian-segmentation.txt](third_party_programs_ultrasound-ovarian-segmentation.txt)
for third-party notices, and note the backbone/dataset licenses called out in
the Model Preparation guide.
