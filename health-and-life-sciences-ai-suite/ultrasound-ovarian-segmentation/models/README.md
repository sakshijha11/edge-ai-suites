# Models

This app does **not** ship a trained model. The OpenVINO IR is produced locally
by the model-preparation step and dropped here.

After running model preparation you will have:

```
models/
  segformer_b5_mmotu/            # trained Hugging Face checkpoint (from backend/bootstrap/train.py)
  ds2net_segformer_b5_256/
    model.xml                    # <-- the IR the app loads by default
    model.bin
    .converted_ok
```

The app's default model path is `models/ds2net_segformer_b5_256/model.xml`
(see `src/config.py`). To produce it:

```powershell
.\prepare_model.ps1 -Verify          # export an existing checkpoint -> IR, verify Dice
.\prepare_model.ps1 -Train -Verify   # train on the Intel iGPU first, then export + verify
```

See [docs/user-guide/get-started/model-preparation.md](../docs/user-guide/get-started/model-preparation.md)
for the full walkthrough (dataset, backbone, training, export, verification).

Everything under `models/` except this file is git-ignored.
