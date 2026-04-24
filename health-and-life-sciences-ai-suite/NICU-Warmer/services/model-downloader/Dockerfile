########################################
# NICU Warmer Model Downloader Service
########################################

FROM python:3.11-slim

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy model registry and download script
COPY model-registry.yaml requirements.txt /app/
COPY download_service.py /app/
COPY scripts/ /app/scripts/

# Install Python dependencies (includes TF + OV for rPPG conversion)
RUN pip install --no-cache-dir -r requirements.txt

# Create output directories for models and data
RUN mkdir -p /models /models/rppg /models/action /data

# Default: run the downloader on startup
ENTRYPOINT ["python", "/app/download_service.py"]
CMD ["--output", "/models"]
