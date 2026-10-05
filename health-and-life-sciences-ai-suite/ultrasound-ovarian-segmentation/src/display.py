# Copyright © 2026 Intel Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
"""cv2 pop-up presenter — overlay the tumor mask and a GPU/FPS HUD on each frame.

Draws the latest segmentation mask (semi-transparent fill + contour) on every
displayed frame and a heads-up panel showing display/inference FPS and the live
iGPU utilization vs. the governor's cap, so the KPI status is visible while the
app runs. Optionally writes an annotated .mp4. Windows pop-up window via OpenCV.
"""
from __future__ import annotations

import logging
import time

import cv2
import numpy as np

log = logging.getLogger("display")


class _Rate:
    def __init__(self) -> None:
        self._t = time.monotonic()
        self._n = 0
        self.fps = 0.0

    def tick(self) -> None:
        self._n += 1
        now = time.monotonic()
        if now - self._t >= 1.0:
            self.fps = self._n / (now - self._t)
            self._t, self._n = now, 0


class Presenter:
    def __init__(self, window: str, scale: float, alpha: float,
                 color: tuple[int, int, int], headless: bool = False,
                 record: str | None = None, src=None) -> None:
        self.window = window
        self.scale = float(scale)
        self.alpha = float(alpha)
        self.color = tuple(int(c) for c in color)
        self.headless = headless
        self._rate = _Rate()
        self._writer = None
        if record and src is not None:
            fourcc = cv2.VideoWriter_fourcc(*"mp4v")
            fps = src.fps if src.fps > 0 else 30.0
            self._writer = cv2.VideoWriter(record, fourcc, fps, (src.width, src.height))
            log.info("recording annotated output -> %s", record)
        if not headless:
            cv2.namedWindow(window, cv2.WINDOW_NORMAL)

    def _overlay(self, frame: np.ndarray, mask: np.ndarray | None) -> np.ndarray:
        if mask is None:
            return frame.copy()
        m = mask.astype(bool)
        if m.shape[:2] != frame.shape[:2]:
            m = cv2.resize(m.astype(np.uint8), (frame.shape[1], frame.shape[0]),
                           interpolation=cv2.INTER_NEAREST).astype(bool)
        out = frame.copy()
        fill = np.zeros_like(frame)
        fill[m] = self.color
        out = cv2.addWeighted(out, 1.0, fill, self.alpha, 0.0)
        cnts, _ = cv2.findContours(m.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cv2.drawContours(out, cnts, -1, self.color, 2)
        return out

    def _hud(self, frame: np.ndarray, hud: dict) -> np.ndarray:
        self._rate.tick()
        lines = [f"display {self._rate.fps:4.1f} fps   inference {hud['inf_fps']:4.1f} fps "
                 f"({hud['inf_ms']:4.0f} ms)"]
        if hud.get("gpu_available"):
            verdict = "PASS" if hud["within_cap"] else "OVER"
            status = "THROTTLING" if hud["throttle_ms"] > 0 else "ok"
            lines.append(f"iGPU busiest  peak {hud['gpu_peak']:4.1f}%  mean {hud['gpu_mean']:4.1f}%  "
                         f"/ cap {hud['gpu_cap']:.0f}%  [{verdict}]")
            lines.append(f"governor {status}  (+{hud['throttle_ms']:.0f} ms/frame)")
        else:
            lines.append("iGPU governor: counters unavailable (non-Windows host)")
        y = 26
        for ln in lines:
            cv2.putText(frame, ln, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(frame, ln, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1, cv2.LINE_AA)
            y += 26
        return frame

    def show(self, frame: np.ndarray, mask: np.ndarray | None, hud: dict) -> int:
        """Draw overlay + HUD, present, and return the pressed key (-1 if none)."""
        out = self._hud(self._overlay(frame, mask), hud)
        if self._writer is not None:
            self._writer.write(out)
        if self.headless:
            return -1
        if self.scale != 1.0:
            out = cv2.resize(out, None, fx=self.scale, fy=self.scale, interpolation=cv2.INTER_LINEAR)
        cv2.imshow(self.window, out)
        return cv2.waitKey(1) & 0xFF

    def close(self) -> None:
        if self._writer is not None:
            self._writer.release()
        if not self.headless:
            try:
                cv2.destroyWindow(self.window)
            except Exception:  # noqa: BLE001
                pass
