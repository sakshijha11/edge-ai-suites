# Model Preparation (backend)

The app ships the model-preparation recipe, not the weights. These modules
produce the OpenVINO IR the runtime app loads:

| Module | Purpose |
|---|---|
| `backend.bootstrap.train` | MMOTU-2D fine-tune of a promptless SegFormer-B5 |
| `backend.bootstrap.export` | trained checkpoint → fp16 OpenVINO IR |
| `backend.bootstrap.eval` | Dice / IoU verification on the val split |

Drive them with `..\prepare_model.ps1`, or run each with `-m`
(e.g. `python -m backend.bootstrap.export --help`). Full walkthrough:
[../docs/user-guide/get-started/model-preparation.md](../docs/user-guide/get-started/model-preparation.md).
