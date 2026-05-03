"""Frame timeline -> MP4 via imageio-ffmpeg.

Each shot is rendered into a small set of pose images, then held on
screen at the target FPS while cycling through poses for the stop-motion
judder. A per-frame ±2 px integer translation is applied to the cached
pose image so adjacent frames never look identical even when the same
pose is held twice.

The slug bar (top-of-frame chapter marker) is re-stamped onto the frame
*after* the jitter so it stays rock-steady while the drawing layer
shakes underneath. Without this, the bar's bottom edge flickers as a
1-2 px paper strip on every frame.

Public surface:
    write_mp4(shots, out_path, fps=10, hold=3) -> int  # frames written
"""
from __future__ import annotations
import random
from typing import List

import numpy as np
import imageio.v2 as imageio

from shotlist import Shot
from render import render_pose, jitter_frame, draw_slug_overlay


def write_mp4(
    shots: List[Shot],
    out_path: str,
    *,
    fps: int = 10,
    hold: int = 3,
    jitter_px: int = 2,
) -> int:
    """Render `shots` to an MP4 at `out_path`. Returns total frame count.

    `hold` = how many frames each pose stays on screen before cycling
    to the next. At fps=10, hold=3 ≈ 3.3 poses/second — the classic
    stop-motion cadence.
    """
    writer = imageio.get_writer(
        out_path,
        fps=fps,
        codec="libx264",
        pixelformat="yuv420p",
        macro_block_size=1,
        ffmpeg_params=["-crf", "20", "-preset", "veryfast"],
    )
    rng = random.Random(0xC0FFEE)
    total = 0
    try:
        for shot in shots:
            n_frames = max(1, int(round(shot.duration_s * fps)))
            pose_imgs = [
                render_pose(shot, p) for p in range(max(1, shot.poses))
            ]
            # Slug + transition cards don't need the overlay (the slug
            # card IS the slug; the transition is full-screen text).
            stamp_slug = shot.kind in ("action", "dialogue")
            for f in range(n_frames):
                pose_idx = (f // hold) % len(pose_imgs)
                base = pose_imgs[pose_idx]
                dx = rng.randint(-jitter_px, jitter_px)
                dy = rng.randint(-jitter_px, jitter_px)
                frame = jitter_frame(base, dx, dy)
                if stamp_slug:
                    frame = draw_slug_overlay(frame, shot.scene_heading)
                writer.append_data(np.asarray(frame))
                total += 1
    finally:
        writer.close()
    return total
