# Runtime Configuration

Every option is available as a CLI flag and as an environment variable (the CLI
flag wins). Launch via `run.ps1` for the common cases, or call the app module
directly for full control:

```powershell
venv\Scripts\python.exe -m src.app --source file --input clip.mp4 --device GPU --gpu-cap 80
```

## run.ps1 parameters

| Parameter | Values | Default | Description |
|---|---|---|---|
| `-Source` | `file` / `webcam` / `folder` | `file` | Input type |
| `-Input` | path / index / folder | — | Video path, webcam index, or stills folder |
| `-Device` | `GPU` / `CPU` / `NPU` / `AUTO` | `GPU` | OpenVINO inference device |
| `-Model` | path | app default | Override the IR `model.xml` |
| `-Venv` | path | `venv` | Virtual environment folder |
| `-Extra` | — | — | Flags after `--` are forwarded to the app |

Example forwarding extra flags:

```powershell
.\run.ps1 -Source file -Input clip.mp4 -- --record out.mp4 --gpu-cap 70 --alpha 0.5
```

## App flags

### Source

| Flag | Env | Default | Description |
|---|---|---|---|
| `--source` | `SOURCE` | `file` | `file` / `webcam` / `folder` |
| `--input` | `INPUT` | — | Video path, webcam index, or stills folder |
| `--no-loop` | `LOOP=0` | loop on | Stop at end instead of looping file/folder sources |
| `--width` | `WIDTH` | `1280` | Requested capture width |
| `--height` | `HEIGHT` | `720` | Requested capture height |
| `--target-fps` | `TARGET_FPS` | `30` | Pacing for folder/webcam sources |

### Model / inference

| Flag | Env | Default | Description |
|---|---|---|---|
| `--device` | `DEVICE` | `GPU` | `CPU` / `GPU` / `NPU` / `AUTO` |
| `--model` | `MODEL` | `models/ds2net_segformer_b5_256/model.xml` | OpenVINO IR path |
| `--res` | `RES` | `256` | Network input resolution (must match the exported IR) |
| `--frame-skip` | `FRAME_SKIP` | `1` | Run inference every Nth captured frame |

> `--res` must equal the resolution the IR was exported at. The default IR is
> exported at 256; if you export at another resolution, pass the matching `--res`.

### GPU utilization cap

| Flag | Env | Default | Description |
|---|---|---|---|
| `--gpu-cap` | `GPU_CAP` | `80` | Hard iGPU busiest-engine utilization ceiling (KPI) |
| `--no-governor` | `NO_GOVERNOR=1` | off | Disable the governor (measure uncapped utilization) |

The governor targets ~70% and hard-kicks over the cap, clamping a per-frame delay
in `[0, 1.0] s`. It reads Windows GPU-Engine counters via pywin32; on non-Windows
machines it degrades to a no-op so the app still runs for development.

### Display / output

| Flag | Env | Default | Description |
|---|---|---|---|
| `--alpha` | `ALPHA` | `0.45` | Mask overlay opacity (0–1) |
| `--mask-color` | `MASK_COLOR` | `0,0,255` | Overlay colour as `B,G,R` (default red) |
| `--display-scale` | `DISPLAY_SCALE` | `1.0` | Scale the output window |
| `--window` | `WINDOW` | `Ovarian Tumor Segmentation` | Window title |
| `--headless` | `HEADLESS=1` | off | No window (useful for recording / soak tests) |
| `--record` | `RECORD` | — | Write an annotated `.mp4` of the output |

## Examples

Measure uncapped iGPU utilization (governor off), headless, recording:

```powershell
.\run.ps1 -Source folder -Input C:\frames -Device GPU -- --no-governor --headless --record soak.mp4
```

Run on the NPU with a tighter cap and a green mask:

```powershell
.\run.ps1 -Source file -Input clip.mp4 -Device NPU -- --gpu-cap 70 --mask-color 0,255,0
```
