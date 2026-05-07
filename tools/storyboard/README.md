# storyboard

Fountain screenplay → black-outline stop-motion **animatic**, on a laptop,
free, offline.

## Why

Penova writers want to *visualise* a draft without a camera, an
illustrator, or a cloud GPU. This tool reads a `.fountain` file, builds
a shot list (one beat per slug / action / dialogue), and stitches a
hand-drawn-feel MP4 the writer can scrub through.

The aesthetic is the simplification: black ink on paper, ~10 fps,
deliberate stop-motion judder. No video diffusion, no character LoRAs,
no GPU. v2 swaps the placeholder figure for ComfyUI line-art renders.

## Usage

```sh
python3 -m pip install Pillow imageio imageio-ffmpeg numpy
python3 tools/storyboard/storyboard.py tools/storyboard/samples/chai.fountain
# -> tools/storyboard/samples/chai.mp4
```

Flags:

| flag | default | what |
|---|---|---|
| `-o PATH` | `<stem>.mp4` next to input | output path |
| `--fps N` | `10` | frame rate |
| `--hold N` | `3` | frames per pose before cycling (lower = jittier) |
| `--dump-shots` | off | print the shot list as JSON and exit |

## Pipeline

```
.fountain
   │  fountain.parse  ── title page + scenes + elements
   ▼
Document  →  shotlist.build  ── one shot per slug/action/dialogue
   │                            with a duration heuristic
   ▼
[Shot]  →  render.render_pose  ── PIL.Image per pose, hand-drawn wobble
   │                              speech bubble + slug bar + figure
   ▼
[frames]  →  stitch.write_mp4  ── 10 fps, hold N frames/pose, ±2 px shake
   ▼
out.mp4
```

## Tests

```sh
python3 tools/storyboard/tests/test_storyboard.py
```

Covers: parser invariants on `samples/chai.fountain`, shot-list timing
sanity, renderer smoke, and a full end-to-end MP4 round-trip.

## Roadmap

- v1 (this) — Pillow placeholder figure, no audio.
- v1.1 — Piper TTS per character, mux into MP4.
- v2 — swap figure for ComfyUI + SD 1.5 + ControlNet lineart, IP-Adapter for
  per-character consistency.
- v2.1 — optional Wan 2.2 / LivePortrait for marked "hero" shots only.
