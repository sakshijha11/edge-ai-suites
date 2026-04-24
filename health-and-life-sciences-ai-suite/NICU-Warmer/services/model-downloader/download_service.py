"""Standalone model downloader service for NICU Warmer detection models.

This service:
1. Runs as a Docker container or standalone script
2. Downloads OpenVINO IR model pairs (XML + BIN) on startup
3. Exposes a health endpoint to verify download status
4. Mounts models into a shared volume for other services to use

Usage:
    docker build -t nicu-model-downloader .
    docker run -v models:/models nicu-model-downloader

    # Or standalone (from NICU-Warmer/services/model-downloader/):
    python download_service.py --output /output/path
"""

from __future__ import annotations

import argparse
import logging
import json
import sys
from pathlib import Path
from typing import Any

import yaml

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

# Default location of model registry
_DEFAULT_REGISTRY = Path(__file__).parent / "model-registry.yaml"


class ModelRegistry:
    """Load and manage model download configuration."""

    def __init__(self, registry_path: Path) -> None:
        self._path = registry_path
        self._registry: dict[str, Any] = {}
        if registry_path.exists():
            with registry_path.open("r", encoding="utf-8") as fh:
                self._registry = yaml.safe_load(fh) or {}

    def get_all_models(self) -> list[dict[str, Any]]:
        """Return a flat list of all models across all groups."""
        models: list[dict[str, Any]] = []
        for group_cfg in self._registry.values():
            if isinstance(group_cfg, dict):
                models.extend(group_cfg.get("models", []))
        return models

    def get_groups(self) -> dict[str, dict[str, Any]]:
        """Return the full registry keyed by group name."""
        return {k: v for k, v in self._registry.items() if isinstance(v, dict)}

    def get_status(self) -> dict[str, Any]:
        """Return summary of all models and their configuration status."""
        models = self.get_all_models()
        status = {
            "total": len(models),
            "models": [],
        }
        for model in models:
            name = model.get("name", "unknown")
            xml_url = model.get("xml_url", "")
            bin_url = model.get("bin_url", "")
            has_urls = bool(xml_url and bin_url) or bool(model.get("hdf5_url")) or bool(model.get("url"))
            status["models"].append(
                {
                    "name": name,
                    "urls_configured": has_urls,
                }
            )
        return status


class ModelDownloader:
    """Download and manage OpenVINO IR model files."""

    def __init__(self, output_dir: Path, registry: ModelRegistry) -> None:
        self._output_dir = output_dir
        self._registry = registry
        self._output_dir.mkdir(parents=True, exist_ok=True)

    def download_all(self) -> dict[str, Any]:
        """Attempt to download all models.  Return summary of successes/failures."""
        results: dict[str, list] = {
            "succeeded": [],
            "skipped": [],
            "failed": [],
        }

        for group_name, group_cfg in self._registry.get_groups().items():
            target_dir = Path(group_cfg.get("target_dir", str(self._output_dir)))
            target_dir.mkdir(parents=True, exist_ok=True)
            convert = group_cfg.get("convert", False)
            models = group_cfg.get("models", [])

            for model in models:
                name = model.get("name", "")
                if not name:
                    continue

                # rPPG: HDF5 download + OpenVINO conversion
                hdf5_url = model.get("hdf5_url", "")
                if hdf5_url and convert:
                    xml_path = target_dir / f"{name}.xml"
                    if xml_path.exists():
                        logger.info("✓ Already present: %s (skipping)", xml_path)
                        results["skipped"].append(name)
                        continue
                    logger.info("↓ Downloading + converting rPPG model %s ...", name)
                    try:
                        self._download_and_convert_rppg(hdf5_url, target_dir)
                        logger.info("✓ %s converted successfully", name)
                        results["succeeded"].append(name)
                    except Exception as exc:
                        logger.error("✗ Failed to convert %s: %s", name, exc)
                        results["failed"].append({"name": name, "error": str(exc)})
                    continue

                # Video: single URL download
                single_url = model.get("url", "")
                if single_url:
                    ext = Path(single_url).suffix or ".mp4"
                    dest = target_dir / f"{name}{ext}"
                    if dest.exists():
                        logger.info("✓ Already present: %s (skipping)", dest)
                        results["skipped"].append(name)
                        continue
                    logger.info("↓ Downloading %s ...", name)
                    try:
                        self._download_file(single_url, dest, name)
                        logger.info("✓ %s downloaded", name)
                        results["succeeded"].append(name)
                    except Exception as exc:
                        logger.error("✗ Failed to download %s: %s", name, exc)
                        results["failed"].append({"name": name, "error": str(exc)})
                    continue

                # Standard XML+BIN pair
                xml_url = model.get("xml_url", "")
                bin_url = model.get("bin_url", "")
                xml_path = target_dir / f"{name}.xml"
                bin_path = target_dir / f"{name}.bin"

                if xml_path.exists() and bin_path.exists():
                    logger.info("✓ Already present: %s (skipping)", name)
                    results["skipped"].append(name)
                    continue

                if not xml_url or not bin_url:
                    logger.warning(
                        "⚠ No URLs configured for '%s' — skipping (fill in model-registry.yaml)",
                        name,
                    )
                    results["skipped"].append(name)
                    continue

                logger.info("↓ Downloading %s ...", name)
                try:
                    self._download_file(xml_url, xml_path, f"{name}.xml")
                    self._download_file(bin_url, bin_path, f"{name}.bin")
                    logger.info("✓ %s downloaded successfully", name)
                    results["succeeded"].append(name)
                except Exception as exc:
                    logger.error("✗ Failed to download %s: %s", name, exc)
                    results["failed"].append({"name": name, "error": str(exc)})

        return results

    @staticmethod
    def _download_file(url: str, dest: Path, label: str) -> None:
        """Download a single file from URL to destination."""
        import urllib.request

        logger.debug("  Downloading %s from %s", label, url)
        urllib.request.urlretrieve(url, dest)

    @staticmethod
    def _download_and_convert_rppg(hdf5_url: str, output_dir: Path) -> None:
        """Download HDF5 and convert to OpenVINO IR using the rppg_convert script."""
        import subprocess
        script = Path(__file__).parent / "scripts" / "rppg_convert.py"
        result = subprocess.run(
            [sys.executable, str(script), "--url", hdf5_url, "--output", str(output_dir)],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr or result.stdout or "rppg_convert failed")
        if result.stdout:
            logger.info(result.stdout.strip())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="NICU Warmer Model Downloader Service")
    parser.add_argument(
        "--registry",
        type=Path,
        default=_DEFAULT_REGISTRY,
        help="Path to model-registry.yaml",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("/models"),
        help="Output directory for downloaded models (default: /models)",
    )
    parser.add_argument(
        "--status-only",
        action="store_true",
        help="Print configuration status and exit (no download)",
    )
    args = parser.parse_args(argv)

    logger.info("=" * 70)
    logger.info("NICU Warmer — Model Downloader Service")
    logger.info("=" * 70)

    registry = ModelRegistry(args.registry)

    if args.status_only:
        status = registry.get_status()
        print(json.dumps(status, indent=2))
        return 0

    downloader = ModelDownloader(args.output, registry)
    logger.info("Output directory: %s", args.output)
    logger.info("")

    results = downloader.download_all()

    logger.info("")
    logger.info("=" * 70)
    logger.info("✓ Succeeded: %d", len(results["succeeded"]))
    logger.info("⊘ Skipped:  %d (already present or no URL)", len(results["skipped"]))
    logger.info("✗ Failed:   %d", len(results["failed"]))
    if results["failed"]:
        for fail in results["failed"]:
            logger.error("  %s: %s", fail["name"], fail.get("error", "unknown"))
    logger.info("=" * 70)

    return 0 if len(results["failed"]) == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
