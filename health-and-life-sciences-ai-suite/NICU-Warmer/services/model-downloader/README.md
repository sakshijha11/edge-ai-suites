# NICU Warmer — Model Downloader Service

Standalone Docker service for downloading OpenVINO IR model files (XML + BIN pairs) for the NICU Warmer application.

## Overview

This service:
- Runs on container startup and downloads configured models (detection-models + action-recognition)
- Exits with status 0 on success, non-zero on failure
- Mounts models into a shared Docker volume (`/models`) for other services to access
- Skips files that already exist (idempotent)
- Skips models with empty/unconfigured URLs (useful during development)

Similar in role to `services/patient-monitoring-assets` in the multi_modal_patient_monitoring suite, but lightweight and focused solely on model download (no conversion needed).

## Configuration

Edit `model-registry.yaml` to set download URLs:

```yaml
detection-models:
  models:
    - name: person-detect-fp32
      xml_url: https://path/to/person-detect-fp32.xml
      bin_url: https://path/to/person-detect-fp32.bin
```

**Action-recognition models** are pre-configured to pull from Intel's Open Model Zoo. Detection models are **placeholders** until the team uploads them to the artifact repository.

## Build & Run

### Docker Compose (recommended)

Add to your `docker-compose.yaml`:

```yaml
services:
  nicu-model-downloader:
    build:
      context: ./services/model-downloader
      dockerfile: Dockerfile
    volumes:
      - models:/models
    environment:
      - HTTP_PROXY
      - HTTPS_PROXY
      - NO_PROXY
    # Optional: stop after download completes
    # restart: no
    # profiles: ["setup"]
```

Then:
```bash
docker compose build nicu-model-downloader
docker compose run nicu-model-downloader
# or with all services:
docker compose up --build nicu-model-downloader
```

### Standalone (without Docker)

```bash
python download_service.py --output /path/to/models
```

Check configuration without downloading:
```bash
python download_service.py --status-only
```

## Output

```
==================================================================
NICU Warmer — Model Downloader Service
==================================================================
Output directory: /models

✓ Downloading action-recognition-0001-encoder ...
✓ action-recognition-0001-encoder downloaded successfully
⊘ person-detect-fp32 skipped (no URL configured)
…

==================================================================
✓ Succeeded: 2
⊘ Skipped:  3 (already present or no URL)
✗ Failed:   0
==================================================================
```

## Integration with NICU-Warmer Backend

The backend's `asset_preparation.py` checks for models in the working directory. When using Docker Compose, mount the models volume:

```yaml
services:
  nicu-backend:
    volumes:
      - models:/app/models
      # If using relative paths, also mount:
      - ./:/app/nicu-root
    # Ensure backend can find models
    # (symlink or copy from /models to working dir as needed)
```

## Next Steps

1. **Team uploads models** to artifact repository (GitHub Releases, S3, etc.)
2. **Update `model-registry.yaml`** with correct URLs
3. **Rebuild the service** or update the volume
4. **Re-run downloader** and backend will use the downloaded models

## Troubleshooting

**Models not found in backend**
- Check that the Docker volume `models` is mounted in both containers
- Verify the downloader ran successfully (check logs)
- Confirm model filenames match the backend's expectations (see `configs/mvp-backend.yaml`)

**Download fails with 404**
- Confirm the URL is correct and reachable: `curl -I <url>`
- Check proxy settings if running in a restricted network

**Service keeps downloading the same models**
- This is expected on fresh runs; the `--output` directory may be on a temporary volume
- Use named Docker volumes (as shown above) to persist downloads across runs
