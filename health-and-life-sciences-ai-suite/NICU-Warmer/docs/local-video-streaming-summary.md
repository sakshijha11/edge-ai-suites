# Local Video “Streaming” / Playback Integration Summary

This document explains how this repo integrates **local camera/video playback**, **looping**, and **real-time-ish FPS behavior**, and how frames get surfaced to the **Next.js dashboard**.

It’s written as a “how we did it + what we learned” guide for someone implementing a similar feature in another application.

## What we built (at a glance)

**Goal:** Use a camera *or* a local video file as the input source, run the CV pipeline, and show “what’s happening now” in a browser UI.

**Key design choice:** We did **not** try to stream true 30 FPS video to the browser. Instead we:

- Run a continuous backend frame loop (OpenCV capture/decoder).
- Encode the **latest processed frame** to JPEG and persist it to SQLite.
- Expose `/api/frame` to fetch that latest JPEG (binary or base64).
- Use `/api/stream` (Server-Sent Events) to push **state snapshots** (status/workflow/rPPG/model telemetry + a frame freshness marker and/or inline base64 frame).
- In the frontend, update the UI immediately when SSE indicates “new frame available”.

This keeps the UI responsive for “monitoring” without incurring the complexity of WebRTC or high-rate MJPEG.

---

## Architecture overview

### Backend (Python / Flask)
Primary file: `dashboard.py`

- **Input**: either
  - `--camera <index>` (default camera mode), or
  - `--file <path>` (video file mode).
- **Frame loop**: `process_frame()` reads frames continuously.
- **Optional file real-time pacing**: `--file-realtime` tries to keep processing aligned to wall-clock FPS by skipping frames if processing falls behind.
- **Looping**: video files are rewound and replayed when end-of-file is reached.
- **Frame surfacing**:
  - `cv2.imencode('.jpg', frame)` → bytes
  - Persist to SQLite: table `frames.latest_frame`
  - Serve via `GET /api/frame`.
- **UI streaming**: `GET /api/stream` SSE pushes consolidated snapshots about once per second.

### Frontend (Next.js)
Primary files:
- `nicu-dashboard/src/hooks/useDashboard.ts`
- `nicu-dashboard/src/hooks/useSSE.ts`
- `nicu-dashboard/src/lib/api.ts`

- Polling is kept as a fallback.
- SSE is the preferred “near real-time” path.
- When SSE signals a new frame, the UI either:
  - uses `frame_inline` (base64 data URL) if present, or
  - calls `/api/frame?base64=1` if only `frame_marker` changed.

---

## Backend implementation details

### 1) Source selection (camera vs file)

In `process_frame()`:

- If `VIDEO_FILE` is provided (`--file`), the backend resolves it robustly (absolute/relative) and opens a `cv2.VideoCapture` on the file.
- Otherwise it opens `cv2.VideoCapture` on the camera index.

Helper functions:

- `_resolve_video_file(path_str)`
  - Strips quotes and resolves relative paths against the current working directory.
- `_open_video_capture(is_video_file, source, attempt_ffmpeg=True)`
  - Tries default `cv2.VideoCapture(source)`.
  - If the file won’t open on Windows/MSMF, attempts `cv2.CAP_FFMPEG`.

**Lesson:** On Windows, backend choice matters. Adding a fallback backend is often the difference between “works on my machine” and “works for demo users”.

### 2) Looping behavior (video files)

When `cap.read()` returns `ret == False` in file mode:

- Log an info message that the video ended.
- Try rewinding with `cap.set(cv2.CAP_PROP_POS_FRAMES, 0)` and read the first frame.
- If rewind fails, release and reopen the capture for robustness.
- Maintain `VIDEO_LOOP_COUNT` for UI/debug.

**Why this matters:**
- Some codecs/backends don’t reliably handle `CAP_PROP_POS_FRAMES` seeks.
- Re-opening the capture is a pragmatic “make demos reliable” move.

### 3) “Real-time” playback (`--file-realtime`)

Problem: If you simply process frames serially from a file, processing speed becomes “as fast as inference can run”, not the video’s FPS.

Solution: When file mode + `--file-realtime` is enabled:

- Read the input file’s FPS via `cap.get(cv2.CAP_PROP_FPS)`.
  - If metadata is missing or bogus, fall back to 30 FPS.
- Track `playback_start = time.time()` and a local `frame_idx`.
- Each iteration:
  - Compute `elapsed = time.time() - playback_start`.
  - Compute `expected_idx = int(elapsed * video_fps)`.
  - If `expected_idx - frame_idx` indicates we’re behind, **read-and-discard** frames to catch up.
  - Cap skipping to avoid giant drops (`drop_target` limited to 100 per iteration).
- Handle the edge case where end-of-file occurs *during frame skip* (rewind + baseline reset).

**What we learned:**
- For demos and “monitoring dashboards”, the right behavior is often “keep up with wall clock” rather than “process every frame”.
- Frame skipping is a simple and effective approach when the UI doesn’t require every frame.

### 4) Storing and serving frames

The backend stores the last processed frame as a JPEG in SQLite:

- Encoding: `cv2.imencode('.jpg', frame)`
- Storage: `UPDATE frames SET latest_frame = ?`
- Retrieval: `get_latest_frame_bytes()` reads `frames.latest_frame`

Endpoints:

- `GET /api/frame`
  - Returns `image/jpeg` bytes by default.
  - With `?base64=1`, returns JSON: `{ image: "data:image/jpeg;base64,..." }`

**Lesson:** Persisting “latest frame” in a single-row table is a dead-simple way to make the frame available across routes and threads. For higher throughput or multi-client scaling, consider an in-memory cache or shared ring buffer.

### 5) SSE stream design (`/api/stream`)

`/api/stream` emits a JSON snapshot roughly once per second.

Snapshot includes:
- `status`, `workflow`
- rPPG metrics + waveform incremental updates
- `model_stats`
- `video_frame_idx`, `video_loop_count`
- Frame freshness:
  - `frame_marker`: short hash derived from the first bytes + size (used to detect a new frame)
  - `frame_inline`: base64 data URL for the full JPEG (optional path)

Change suppression:
- The generator caches the last payload and yields only when the snapshot changes.

**Tradeoff/lesson:**
- `frame_inline` is convenient but heavy (base64 expands size, and JSON framing adds overhead).
- The `frame_marker` + separate `/api/frame` fetch pattern is a good “bandwidth control knob” when you want to decouple state updates from frame transfer.

---

## Frontend implementation details

### 1) SSE consumption

`useSSE()` creates an `EventSource` and parses `evt.data` JSON.

`useDashboard()` layers SSE on top of periodic polling:

- On each SSE message:
  - Applies status/workflow/rPPG updates.
  - Updates the waveform incrementally during an active session.
  - Updates `video_frame_idx` and `video_loop_count`.

### 2) Frame update strategy

In `useDashboard()`:

- If `snap.frame_inline` exists, it immediately sets `frameDataUrl` and the UI updates.
- Else if `snap.frame_marker` changed, it calls `fetchFrameBase64()` (`/api/frame?base64=1`).

**What we learned:**
- “Marker + fetch” prevents redundant downloads when the server emits frequent state updates but the frame hasn’t changed.
- Keeping the base64 mode behind an API makes it easy to swap to binary fetch + Blob URLs later for performance.

---

## What worked well

- **Looping and demo reliability:** Rewinding + reopen fallback made file playback stable across Windows environments.
- **Real-time-ish file playback:** Frame skipping kept the pipeline aligned with video FPS, which is usually what people expect when watching a demo.
- **SSE over WebSockets:** SSE was enough for one-way telemetry updates and is simpler to deploy/debug.
- **Separation of concerns:** CV loop is independent from the UI; UI can reconnect and catch up via polling.

---

## Lessons / pitfalls for future implementations

### Video + inference is not “video streaming”
If you need smooth 15–30 FPS video in browser:

- Consider MJPEG (`multipart/x-mixed-replace`) as a simple step up, or
- Use WebRTC for truly smooth low-latency streaming.

Our approach is intentionally “latest frame” + state streaming, optimized for dashboards.

### Beware base64 + JSON size
- Base64 adds ~33% overhead.
- JSON + EventSource framing adds more.

For higher rates:
- Prefer `/api/frame` binary + `URL.createObjectURL(blob)`.
- Or stream JPEGs as MJPEG.

### FPS metadata can be wrong
- `CAP_PROP_FPS` is often missing/invalid for some files.
- We clamp to a reasonable default (30 FPS) to keep pacing predictable.

### Make looping robust
- Seeking (`CAP_PROP_POS_FRAMES`) is not guaranteed to work across all codecs.
- Reopening capture is often the simplest “works everywhere” fallback.

### Avoid coupling UI rate to processing rate
- A dashboard doesn’t need every frame.
- Let inference run at whatever rate is sustainable, and let the UI update at a smaller fixed cadence (or only on change).

---

## Porting checklist (to another app)

1. **Decide your UI needs**: monitoring vs real video.
2. **Backend capture**:
   - Provide camera and file inputs.
   - Add Windows backend fallbacks.
3. **Looping and pacing**:
   - Implement rewind + reopen fallback.
   - Add optional `--file-realtime` frame skipping.
4. **Frame transport**:
   - Start with “latest frame endpoint” + marker.
   - Upgrade to binary blobs/MJPEG/WebRTC if needed.
5. **Streaming state**:
   - SSE works well for one-way telemetry.
   - Make reconnection safe; include timestamps and counters.
6. **Observability**:
   - Track loop count and frame index.
   - Track model/inference FPS separately from source FPS.

---

## Where to look in this repo

- Backend:
  - `dashboard.py`
    - `process_frame()` (capture loop, looping, `--file-realtime`)
    - `GET /api/frame`
    - `GET /api/stream`
- Frontend:
  - `nicu-dashboard/src/hooks/useDashboard.ts` (SSE + frame update logic)
  - `nicu-dashboard/src/hooks/useSSE.ts` (EventSource wrapper)
  - `nicu-dashboard/src/lib/api.ts` (frame fetch helpers)
- Launch scripts:
  - `start.ps1` (recommended quick start; defaults to `--file --file-realtime --no-display`)
  - `run-dev.ps1` (more configurable developer launcher)
