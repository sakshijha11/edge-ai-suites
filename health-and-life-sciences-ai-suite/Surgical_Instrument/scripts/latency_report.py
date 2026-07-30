#!/usr/bin/env python3
"""Generate shareable latency summaries for recorded-video and Basler runs.

This script runs the pipeline twice (recorded video and Basler), parses
pipeline latency tracer lines from the `surgical-pipeline` container logs,
computes latency metrics, and writes artifacts under `logs/latency`.

Reported metrics for each run:
- mean
- p50
- p90
- p95
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import subprocess
import time
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import re
from typing import Any


RE_PIPELINE_LATENCY = re.compile(r"(?<!element-)latency,.*time=\(guint64\)(?P<ns>\d+)")


@dataclass(frozen=True)
class SourceRun:
    label: str
    kind: str
    arg: str


def _post_json(base_url: str, path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
    payload = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        f"{base_url}{path}",
        data=payload,
        method="POST",
        headers={"Content-Type": "application/json"} if payload is not None else {},
    )
    with urllib.request.urlopen(req, timeout=20) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw) if raw else {}


def _safe_stop(base_url: str) -> None:
    try:
        _post_json(base_url, "/stop")
    except Exception:
        pass


def _read_status(base_url: str) -> dict[str, Any]:
    with urllib.request.urlopen(f"{base_url}/status", timeout=10) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw) if raw else {}


def _fetch_container_logs_since(container: str, since_ts: str) -> str:
    proc = subprocess.run(
        ["docker", "logs", "--since", since_ts, container],
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    # Docker logs may emit to stderr depending on runtime/driver.
    return (proc.stdout or "") + (proc.stderr or "")


def _nearest_rank(sorted_vals: list[float], quantile: float) -> float:
    if not sorted_vals:
        return 0.0
    idx = max(1, min(len(sorted_vals), int(math.ceil(quantile * len(sorted_vals)))))
    return sorted_vals[idx - 1]


def _summarize(values: list[float]) -> dict[str, float | int]:
    if not values:
        return {
            "samples": 0,
            "mean_ms": 0.0,
            "p50_ms": 0.0,
            "p90_ms": 0.0,
            "p95_ms": 0.0,
        }
    sorted_vals = sorted(values)
    return {
        "samples": len(sorted_vals),
        "mean_ms": round(statistics.fmean(sorted_vals), 3),
        "p50_ms": round(_nearest_rank(sorted_vals, 0.50), 3),
        "p90_ms": round(_nearest_rank(sorted_vals, 0.90), 3),
        "p95_ms": round(_nearest_rank(sorted_vals, 0.95), 3),
    }


def _parse_pipeline_latency_ms(raw_log: str) -> list[float]:
    values_ms: list[float] = []
    for line in raw_log.splitlines():
        match = RE_PIPELINE_LATENCY.search(line)
        if not match:
            continue
        values_ms.append(int(match.group("ns")) / 1_000_000.0)
    return values_ms


def _run_one_source(
    base_url: str,
    source: SourceRun,
    device: str,
    seconds: int,
    warm_seconds: int,
    sample_interval: float,
    container: str,
) -> dict[str, Any]:
    _safe_stop(base_url)
    time.sleep(1.5)

    # Only parse logs created during this run.
    run_start_utc = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    start_payload = {
        "device": device,
        "source": {"kind": source.kind, "arg": source.arg},
    }
    start_response = _post_json(base_url, "/start", start_payload)

    time.sleep(warm_seconds)

    status_samples: list[dict[str, Any]] = []
    end_at = time.time() + seconds
    while time.time() < end_at:
        try:
            status = _read_status(base_url)
            status_samples.append(status)
        except Exception:
            pass
        time.sleep(sample_interval)

    _safe_stop(base_url)
    time.sleep(1.0)

    raw_log = _fetch_container_logs_since(container, run_start_utc)
    pipeline_latency_ms = _parse_pipeline_latency_ms(raw_log)
    metrics = {
        "pipeline": _summarize(pipeline_latency_ms),
    }

    fps_series: list[float] = []
    for sample in status_samples:
        inference = sample.get("inference") or {}
        fps = inference.get("delivered_fps")
        if isinstance(fps, (int, float)) and fps > 0:
            fps_series.append(float(fps))

    return {
        "source_label": source.label,
        "source_kind": source.kind,
        "source_arg": source.arg,
        "device": device,
        "duration_seconds": seconds,
        "warmup_seconds": warm_seconds,
        "status_samples": len(status_samples),
        "fps_mean": round(statistics.fmean(fps_series), 3) if fps_series else 0.0,
        "start_response": start_response,
        "metrics": metrics,
        "pipeline_latency_samples": len(pipeline_latency_ms),
        "log_since_utc": run_start_utc,
        "raw_log": raw_log,
    }


def _write_markdown_report(report_path: Path, run_results: list[dict[str, Any]]) -> None:
    lines = [
        "# Latency Summary",
        "",
        "| Source | Device | Metric | Samples | Mean (ms) | P50 (ms) | P90 (ms) | P95 (ms) |",
        "|---|---|---|---:|---:|---:|---:|---:|",
    ]

    for result in run_results:
        source_label = result["source_label"]
        device = result["device"]
        for metric_name, metric in (("Pipeline", result["metrics"]["pipeline"]),):
            lines.append(
                "| "
                f"{source_label} | {device} | {metric_name} | {metric['samples']} | "
                f"{metric['mean_ms']:.3f} | {metric['p50_ms']:.3f} | {metric['p90_ms']:.3f} | {metric['p95_ms']:.3f} |"
            )

    lines.append("")
    lines.append("Notes:")
    lines.append("- Pipeline is parsed from GStreamer tracer lines in pipeline container logs.")
    lines.append("- This build exposes rolling latency via /api/status and does not write /frames/latency.log.")

    report_path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run latency measurements for recorded video and Basler, then save summaries."
    )
    parser.add_argument("--api-base", default="http://localhost:8080/api", help="Backend API base URL")
    parser.add_argument("--device", choices=["CPU", "GPU", "NPU"], default="GPU", help="Target device")
    parser.add_argument("--seconds", type=int, default=60, help="Sampling duration per source")
    parser.add_argument("--warm", type=int, default=5, help="Warm-up seconds before sampling")
    parser.add_argument("--sample-interval", type=float, default=1.0, help="Status polling interval (seconds)")
    parser.add_argument(
        "--video-path",
        default="/videos/polyp_test.mp4",
        help="Recorded video path inside pipeline container",
    )
    parser.add_argument("--basler-serial", default="40067928", help="Basler camera serial")
    parser.add_argument("--container", default="surgical-pipeline", help="Pipeline container name")
    parser.add_argument(
        "--output-dir",
        default="logs/latency",
        help="Directory to save report artifacts",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    runs = [
        SourceRun(label="recorded_video", kind="file", arg=args.video_path),
        SourceRun(label="basler", kind="basler", arg=args.basler_serial),
    ]

    results: list[dict[str, Any]] = []
    for source in runs:
        print(
            f"[latency_report] Running {source.label} on {args.device} "
            f"for {args.seconds}s (warm-up {args.warm}s)"
        )
        result = _run_one_source(
            base_url=args.api_base,
            source=source,
            device=args.device,
            seconds=args.seconds,
            warm_seconds=args.warm,
            sample_interval=args.sample_interval,
            container=args.container,
        )
        results.append(result)

        raw_log_path = out_dir / f"latency_raw_{source.label}_{timestamp}.log"
        raw_log_path.write_text(result["raw_log"], encoding="utf-8")
        print(f"[latency_report] Saved raw log: {raw_log_path}")

    output_json = {
        "timestamp_utc": timestamp,
        "api_base": args.api_base,
        "device": args.device,
        "seconds_per_source": args.seconds,
        "warm_seconds": args.warm,
        "sample_interval_seconds": args.sample_interval,
        "metric_source": "pipeline_container_logs",
        "runs": [
            {
                k: v
                for k, v in result.items()
                if k != "raw_log"
            }
            for result in results
        ],
    }

    json_path = out_dir / f"latency_summary_{timestamp}.json"
    json_path.write_text(json.dumps(output_json, indent=2), encoding="utf-8")

    md_path = out_dir / f"latency_summary_{timestamp}.md"
    _write_markdown_report(md_path, results)

    print(f"[latency_report] Saved summary JSON: {json_path}")
    print(f"[latency_report] Saved summary Markdown: {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())