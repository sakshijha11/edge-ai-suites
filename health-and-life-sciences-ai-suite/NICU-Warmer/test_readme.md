# NICU Warmer MVP — Validation Test Guide

## Overview

The NICU Warmer Monitoring System is an AI-powered dashboard for neonatal intensive care unit (NICU) warmers. It uses Intel hardware (GPU, CPU, NPU) to run real-time computer vision and vital sign monitoring on a live video feed.

**What it does:**
- Detects patient presence, caretaker presence, and warmer latch state (3 object detection models on GPU)
- Monitors heart rate and respiration via remote photoplethysmography (rPPG model on CPU)
- Recognizes patient activity/motion patterns (action recognition model on NPU)
- Displays everything in a real-time web dashboard with live video, vitals waveforms, and pipeline metrics

---

## Prerequisites

### Hardware Requirements
| Component | Requirement |
|-----------|------------|
| Processor | Intel Core Ultra (Meteor Lake) or newer |
| GPU | Intel Arc Graphics (integrated) |
| NPU | Intel NPU / AI Boost |
| RAM | 16 GB minimum |
| OS | Ubuntu 22.04 / 24.04 |

### Software Requirements
| Software | Version |
|----------|---------|
| Docker | 24.0+ |
| Docker Compose | v2.20+ |
| Git | Any recent version |

Verify Docker is installed:
```bash
docker --version
docker compose version
```

Ensure GPU/NPU device access:
```bash
ls /dev/dri/    # Should show renderD128, card0, etc.
ls /dev/accel/  # Intel NPU device
```

---

## Setup Instructions

### Step 1: Clone the Repository

```bash
git clone https://github.com/sakshijha11/edge-ai-suites.git
cd edge-ai-suites/health-and-life-sciences-ai-suite/NICU-Warmer
```

### Step 2: Extract Offline Assets

You will receive a file called `nicu-warmer-offline-assets.zip` (180 MB) separately.
This contains all AI models and the test video that cannot be included in the git repository.

**Copy the zip into the NICU-Warmer directory and extract:**

```bash
# Copy the zip file into the project directory
cp /path/to/nicu-warmer-offline-assets.zip .

# Extract — this places files exactly where the application expects them
unzip nicu-warmer-offline-assets.zip -d .
```

**Verify the files are in place:**

```bash
ls -la person-detect-fp32.xml patient-detect-fp32.xml latch-detect-fp32.xml
ls -la action-recognition-0001-encoder.xml action-recognition-0001-decoder.xml
ls -la models_rppg/mtts_can.xml
ls -la Warmer_Testbed_YTHD.mp4
```

You should see all files listed without errors. The directory structure should look like:

```
NICU-Warmer/
├── person-detect-fp32.xml + .bin        # Person detection model
├── patient-detect-fp32.xml + .bin       # Patient detection model
├── latch-detect-fp32.xml + .bin         # Latch detection model
├── action-recognition-0001-encoder.xml + .bin   # Action recognition encoder
├── action-recognition-0001-decoder.xml + .bin   # Action recognition decoder
├── Warmer_Testbed_YTHD.mp4             # Test video
├── models_rppg/
│   ├── mtts_can.xml + .bin             # rPPG model (OpenVINO IR)
│   └── mtts_can.hdf5                   # rPPG model (original Keras)
├── model_cache/
│   └── *.blob                          # Pre-compiled OpenVINO cache
├── backend_mvp/                        # Flask backend
├── ui/                                 # React frontend
├── extensions/                         # GStreamer pipeline extensions
├── configs/                            # Configuration files
├── services/                           # Model downloader service
├── docker-compose.yaml
├── Makefile
└── readme.md
```

### Step 3: Build and Start the Application

```bash
# Build and start all 5 services (backend, UI, DLSPS, MQTT, metrics)
make run
```

Or equivalently:
```bash
docker compose --profile dlsps up --build -d
```

This starts:
| Service | Port | Description |
|---------|------|-------------|
| nicu-ui | http://localhost:3001 | Web dashboard (React + nginx) |
| nicu-backend | http://localhost:5001 | Flask API + SSE streaming |
| nicu-dlsps | http://localhost:8080 | DL Streamer Pipeline Server |
| nicu-mqtt | localhost:1883 | MQTT broker for detections |
| nicu-metrics-collector | localhost:9100 | System metrics collector |

### Step 4: Wait for Services to be Healthy

```bash
# Check all containers are running and healthy
docker compose --profile dlsps ps
```

Expected output — all services should show `Up` and `(healthy)`:
```
NAME                     STATUS                 PORTS
nicu-backend             Up X minutes (healthy) 0.0.0.0:5001->5001/tcp
nicu-dlsps               Up X minutes (healthy) 0.0.0.0:8080->8080/tcp
nicu-metrics-collector   Up X minutes (healthy) 0.0.0.0:9100->9000/tcp
nicu-mqtt                Up X minutes (healthy) 0.0.0.0:1883->1883/tcp
nicu-ui                  Up X minutes           0.0.0.0:3001->3000/tcp
```

If any service is not healthy, check logs:
```bash
docker compose --profile dlsps logs nicu-backend
docker compose --profile dlsps logs nicu-dlsps
```

### Step 5: Open the Dashboard

Open a browser and navigate to:

```
http://localhost:3001
```

---

## What to Validate

### 1. Dashboard Layout
- [ ] Dashboard loads with the title "NICU Warmer Monitoring System"
- [ ] Five main panels are visible: Video Feed, Vitals (rPPG), Action Recognition, Patient Status, Pipeline Performance

### 2. Video Feed (Left Panel)
- [ ] Live video stream is displayed (from the test video)
- [ ] No flickering or rapid frame switching
- [ ] During pipeline restart: a loading overlay with spinner appears (not a blank/flickering screen)
- [ ] Status badge shows "RUNNING" (green) when pipeline is active
- [ ] FPS counter is visible in the corner
- [ ] Detection badges visible: Patient (Detected/Not Detected), Caretaker, Latch state

### 3. Pipeline Performance Table (Right Panel)
- [ ] Table shows 6 columns: **Workload | Model | Device | FPS | Latency | Status**
- [ ] 5 workloads listed:
  - Person Detection — GPU
  - Patient Detection — GPU
  - Latch Detection — GPU
  - rPPG (MTTS-CAN) — CPU — shows latency in ms
  - Action Recognition — NPU — shows latency in ms
- [ ] FPS values update in real time
- [ ] Pipeline summary row at bottom shows overall FPS and decode method

### 4. rPPG Vitals
- [ ] Heart rate (BPM) and respiration rate displayed
- [ ] Waveform charts update when patient is detected
- [ ] Values show "—" or placeholders when patient is not detected

### 5. Action Recognition
- [ ] Activity list shows recognized actions with confidence percentages
- [ ] Top activity is highlighted
- [ ] Motion level indicator visible (still / low / moderate / high)

### 6. Configuration Modal (Gear Icon ⚙️)
- [ ] Click the gear/settings icon to open the Config Modal
- [ ] **Video Source tab**: styled "Choose File" button (not default browser file input), can upload a video
- [ ] **Face ROI tab**: can set face region of interest coordinates
- [ ] **Device Assignment tab**: can change inference device (CPU/GPU/NPU)
- [ ] **Apply & Restart Pipeline** button is visible whenever pipeline is running
- [ ] Clicking Apply & Restart stops the pipeline, applies config, and restarts
- [ ] No "Done" button in the footer (removed by design)

### 7. API Endpoints (Optional — for advanced validation)

```bash
# Health check
curl http://localhost:5001/health

# System status (full JSON)
curl http://localhost:5001/status

# SSE event stream (Ctrl+C to stop)
curl -N http://localhost:5001/events

# Frame availability
curl http://localhost:5001/frame/latest?base64=1

# Pipeline performance
curl http://localhost:5001/status | python3 -m json.tool | grep -A 20 pipeline_performance
```

---

## Stopping the Application

```bash
make down
```

Or:
```bash
docker compose --profile dlsps down
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "No such file" errors on startup | Models not extracted correctly. Re-run `unzip nicu-warmer-offline-assets.zip -d .` in the NICU-Warmer directory |
| Backend shows MISSING_MODEL error | Check that `.xml` and `.bin` files are in the project root (not inside a subfolder) |
| Video feed shows placeholder | Pipeline may still be starting. Wait 30 seconds. Check `docker compose --profile dlsps logs nicu-dlsps` |
| DLSPS container exits | GPU/NPU drivers not available. Check `ls /dev/dri/` and `ls /dev/accel/` |
| UI not loading | Check `docker compose --profile dlsps logs nicu-ui` and ensure port 3001 is not in use |
| Low FPS (<5) | Normal during initial model compilation. Performance improves after first run (model_cache is populated) |
| NPU errors in logs | Action recognition falls back to CPU automatically. This is expected on systems without NPU |

---

## Files Included in Offline Assets Zip

| File | Size | Purpose |
|------|------|---------|
| person-detect-fp32.xml + .bin | 10 MB | Person/caretaker detection (YOLOv5-based) |
| patient-detect-fp32.xml + .bin | 10 MB | Patient (infant) detection |
| latch-detect-fp32.xml + .bin | 10 MB | Warmer door latch state detection |
| action-recognition-0001-encoder.xml + .bin | 43 MB | Action recognition encoder (Open Model Zoo) |
| action-recognition-0001-decoder.xml + .bin | 15 MB | Action recognition decoder (Open Model Zoo) |
| models_rppg/mtts_can.* | 13 MB | MTTS-CAN rPPG model (heart rate + respiration) |
| model_cache/*.blob | 92 MB | Pre-compiled OpenVINO inference blobs |
| Warmer_Testbed_YTHD.mp4 | 25 MB | NICU warmer test video |

**Total: ~180 MB (compressed zip)**

---

## Alternative: Auto-Download Models (if network available)

If you have internet access and prefer not to use the zip file, models can be downloaded automatically:

```bash
# This builds and runs the model-downloader container
make setup

# Then start the application
make run
```

The downloader fetches models from public URLs (Open Model Zoo, GitHub Releases) and skips any file already present on disk.

> **Note**: The auto-download writes some files to `model_artifacts/` which may need to be copied to the project root. The offline zip approach is more reliable.

---

## Contact

For questions or issues, reach out to the development team.
