#!/usr/bin/env python3
"""storyboard.py — Fountain screenplay -> black-outline stop-motion MP4.

Pipeline:
    .fountain  ->  fountain.parse  ->  shotlist.build
                        ->  render.render_pose  ->  stitch.write_mp4

Usage:
    python3 tools/storyboard/storyboard.py [-o out.mp4] [--fps 10]
                                          [--hold 3] [--dump-shots]
                                          script.fountain

Defaults emit `<script-stem>.mp4` next to the input.
"""
from __future__ import annotations
import argparse
import json
import os
import sys
import time

# Allow running as a script: add this dir to sys.path so sibling imports
# (`fountain`, `shotlist`, `render`, `stitch`) resolve.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fountain          # noqa: E402
import shotlist as _sl   # noqa: E402
import stitch            # noqa: E402
import render as _render # noqa: E402
import style as _style   # noqa: E402


def _format_secs(s: float) -> str:
    return f"{s:.1f}s"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Fountain -> black-outline stop-motion animatic.",
    )
    ap.add_argument("script", nargs="?", help=".fountain source")
    ap.add_argument("-o", "--out", help="output MP4 path")
    ap.add_argument("--fps", type=int, default=10,
                    help="output frame rate (default 10)")
    ap.add_argument("--hold", type=int, default=3,
                    help="frames to hold each pose before cycling (default 3)")
    ap.add_argument("--dump-shots", action="store_true",
                    help="print the shot list as JSON and exit (no render)")
    ap.add_argument("--style", default="calvin",
                    help=f"visual style — built-ins: "
                         f"{', '.join(_style.list_presets())}, or pass a "
                         f"path/name of a saved style json")
    ap.add_argument("--list-styles", action="store_true",
                    help="print available styles and exit")
    ap.add_argument("--save-style", metavar="NAME",
                    help="save the selected style under NAME and exit "
                         "(useful after editing a json style file)")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    if args.list_styles:
        for name in _style.list_presets():
            print(name)
        return 0

    try:
        active_style = _style.load(args.style)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    _render.set_style(active_style)

    if args.save_style:
        path = _style.save_named(active_style, args.save_style)
        print(f"saved style to {path}")
        return 0

    if not args.script:
        ap.error("script is required (or pass --list-styles / --save-style)")
    src_path = args.script
    if not os.path.isfile(src_path):
        print(f"error: {src_path}: no such file", file=sys.stderr)
        return 2

    with open(src_path, "r", encoding="utf-8") as f:
        source = f.read()

    doc = fountain.parse(source)
    _render.seed_intros(_sl.extract_intros(doc))
    _render.seed_genders(_sl.extract_genders(doc))
    shots = _sl.build(doc)

    if args.dump_shots:
        out = []
        for s in shots:
            out.append({
                "kind": s.kind,
                "scene_index": s.scene_index,
                "scene_heading": s.scene_heading,
                "location": s.location,
                "character": s.character,
                "parenthetical": s.parenthetical,
                "duration_s": round(s.duration_s, 2),
                "poses": s.poses,
                "text": s.text,
            })
        print(json.dumps(out, indent=2, ensure_ascii=False))
        return 0

    out_path = args.out or os.path.splitext(src_path)[0] + ".mp4"
    total_dur = sum(s.duration_s for s in shots)

    if not args.quiet:
        title = doc.title_page.get("title", "(untitled)")
        author = doc.title_page.get("author") or doc.title_page.get("credit", "")
        print(f"  title:    {title}")
        if author:
            print(f"  author:   {author}")
        print(f"  scenes:   {len(doc.scenes)}")
        print(f"  shots:    {len(shots)}")
        print(f"  duration: {_format_secs(total_dur)} @ {args.fps} fps")
        print(f"  hold:     {args.hold} frames/pose")
        print(f"  style:    {active_style.name}")
        print(f"  output:   {out_path}")

    t0 = time.time()
    n = stitch.write_mp4(
        shots, out_path, fps=args.fps, hold=args.hold,
    )
    dt = time.time() - t0
    if not args.quiet:
        print(f"  rendered: {n} frames in {_format_secs(dt)}"
              f" ({n / dt:.1f} fps render speed)")
        print(f"  ✅ wrote {out_path} ({os.path.getsize(out_path) / 1024:.1f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
