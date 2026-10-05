# Ultrasound Ovarian Segmentation Sample App

> [!NOTE]
> This application is for **reference and evaluation purposes only**. It is
> **not intended for direct use in clinical or diagnostic environments** and is
> not validated for such a purpose.

The app demonstrates how Intel hardware acceleration (CPU / Intel iGPU / Intel
NPU) can be applied through OpenVINO to AI-based real-time ovarian tumor
segmentation in 2D ultrasound. It runs a promptless SegFormer-B5 (DS2Net) model
with a decoupled capture / inference / display architecture, so the displayed
video stays smooth regardless of inference speed, and enforces an Intel iGPU
< 80% utilization KPI with a built-in GPU governor.

Supported inputs:

- Video file (for demos and benchmarking)
- USB / webcam
- Folder of ultrasound stills (paced like a slideshow)

How to start:

- See [Model Preparation](./get-started/model-preparation.md) to produce the
  OpenVINO IR the app loads — the app does not ship a trained model.
- See [Get Started](./get-started.md) for a step-by-step setup and run guide.
- See [Runtime Configuration](./runtime-configuration.md) for every flag and
  environment variable the app exposes.
- See [Troubleshooting](./troubleshooting.md) for common issues.
- See [Release Notes](./release-notes.md) for version history.
