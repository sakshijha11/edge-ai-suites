"""Download MTTS-CAN HDF5 and convert to OpenVINO IR.

Ported from multi_modal_patient_monitoring rppg_download_assets.py.
Registers TSM and Attention_mask custom Keras layers, loads the HDF5,
and converts to OpenVINO IR (XML + BIN) suitable for CPU/GPU inference.

Usage (standalone):
    python scripts/rppg_convert.py --url <hdf5_url> --output /models/rppg
"""
from __future__ import annotations

import argparse
import logging
import sys
import urllib.request
from pathlib import Path

import tensorflow as tf
from tensorflow import keras
import openvino as ov

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


# ── Custom Keras layers needed to deserialize MTTS-CAN HDF5 ──────


@keras.utils.register_keras_serializable(package="Custom")
class TSM(keras.layers.Layer):
    """Temporal Shift Module stub for MTTS-CAN deserialization."""

    def __init__(self, n_frame=10, fold_div=3, **kwargs):
        super().__init__(**kwargs)
        self.n_frame = n_frame
        self.fold_div = fold_div

    def call(self, inputs, *args, **kwargs):
        return inputs

    def get_config(self):
        config = super().get_config()
        config.update({"n_frame": self.n_frame, "fold_div": self.fold_div})
        return config


@keras.utils.register_keras_serializable(package="Custom")
class Attention_mask(keras.layers.Layer):
    """Attention mask stub for MTTS-CAN deserialization."""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def call(self, inputs, *args, **kwargs):
        if isinstance(inputs, list) and len(inputs) == 2:
            attention, features = inputs
            attention = tf.repeat(attention, features.shape[-1], axis=-1)
            return attention * features
        return inputs

    def get_config(self):
        return super().get_config()


# ── Download + convert ────────────────────────────────────────────


def download_hdf5(url: str, dest: Path) -> None:
    """Download HDF5 model weights."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        logger.info("HDF5 already present: %s (skipping download)", dest)
        return
    logger.info("Downloading MTTS-CAN HDF5 from %s", url)
    urllib.request.urlretrieve(url, dest)
    size_mb = dest.stat().st_size / (1024 * 1024)
    logger.info("✓ Downloaded %.1f MB → %s", size_mb, dest)


def convert_to_openvino(h5_path: Path, output_dir: Path) -> None:
    """Convert HDF5 → OpenVINO IR (mtts_can.xml + .bin)."""
    xml_path = output_dir / "mtts_can.xml"
    if xml_path.exists():
        logger.info("OpenVINO IR already exists: %s (skipping conversion)", xml_path)
        return
    logger.info("Converting %s → OpenVINO IR ...", h5_path)
    model = keras.models.load_model(
        str(h5_path),
        custom_objects={"TSM": TSM, "Attention_mask": Attention_mask},
        compile=False,
    )
    ov_model = ov.convert_model(model)
    ov.save_model(ov_model, str(xml_path))
    logger.info("✓ Saved %s", xml_path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="MTTS-CAN HDF5 → OpenVINO IR converter")
    parser.add_argument("--url", required=True, help="URL of MTTS-CAN HDF5 weights")
    parser.add_argument("--output", type=Path, default=Path("/models/rppg"), help="Output directory")
    args = parser.parse_args(argv)

    h5_path = args.output / "mtts_can.hdf5"
    try:
        download_hdf5(args.url, h5_path)
        convert_to_openvino(h5_path, args.output)
    except Exception as exc:
        logger.error("rPPG conversion failed: %s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
