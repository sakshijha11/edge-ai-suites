# Release Notes

## 1.0.0

Initial release of the Ultrasound Ovarian Segmentation sample app.

- Real-time promptless ovarian tumor segmentation on 2D ultrasound using a
  SegFormer-B5 (DS2Net) fp16 OpenVINO IR.
- Decoupled capture / inference / display pipeline with an OpenCV overlay pop-up
  and FPS / latency / GPU HUD.
- Inputs: video file, USB webcam, or a folder of stills. Devices: CPU / Intel
  iGPU / Intel NPU.
- Built-in GPU utilization governor enforcing the Intel iGPU < 80% busiest-engine
  KPI, with a per-run PASS/OVER verdict.
- Model-preparation backend (`backend/bootstrap`): MMOTU-2D fine-tune, fp16
  OpenVINO export, and Dice/IoU verification. The app ships the recipe, not the
  weights; reference accuracy is Dice 0.8657 / IoU 0.7913 at res 256 on the
  MMOTU-2D val split.
