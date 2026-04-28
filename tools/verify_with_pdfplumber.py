#!/usr/bin/env python3
"""
Drop-in alternative to verify_parser.py for environments where the
system pdftotext (-bbox-layout mode) crashes (macOS poppler 26.04 has a
known std::out_of_range abort on certain PDFs). Uses pdfplumber to
extract per-word positions, feeds them into the same parser logic, and
also covers FDX / Fountain fixtures.

Usage:
    python3 tools/verify_with_pdfplumber.py             # all fixtures
    python3 tools/verify_with_pdfplumber.py path.pdf    # one file
"""

from __future__ import annotations

import os
import sys
import xml.etree.ElementTree as ET
from typing import List

import pdfplumber

# Reuse the parser + Line type from the existing verifier.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from verify_parser import (  # type: ignore
    Line,
    parse,
    report,
    FIXTURES,
    _emit_line,
)


def extract_lines_via_pdfplumber(pdf_path: str) -> List[List[Line]]:
    """Same output shape as verify_parser.extract_lines, sourced from
    pdfplumber instead of pdftotext."""
    pages_out: List[List[Line]] = []
    with pdfplumber.open(pdf_path) as pdf:
        for page_idx, page in enumerate(pdf.pages):
            page_h = float(page.height)
            words = page.extract_words(use_text_flow=True, keep_blank_chars=False)
            fragments = []  # (yMin, xMin, text)
            for w in words:
                txt = (w.get("text") or "").strip()
                if not txt:
                    continue
                # pdfplumber y-origin is top-left, but verify_parser's
                # Line uses y_top measured from page bottom (PDF user
                # space). Convert: yMin in PDF user space = page_h - top.
                y_top_in_plumber = float(w["top"])  # from top
                bottom_in_plumber = float(w["bottom"])
                y_min_user_space = page_h - bottom_in_plumber
                x_min = float(w["x0"])
                fragments.append((y_min_user_space, x_min, txt))
            if not fragments:
                pages_out.append([])
                continue
            fragments.sort(key=lambda f: (f[0], f[1]))

            TOL_Y = 3.0
            GAP = 80.0
            groups = []
            cur_y = None
            cur_group = []
            for y_min, x_min, txt in fragments:
                if cur_y is None or abs(y_min - cur_y) > TOL_Y:
                    if cur_group:
                        groups.append(cur_group)
                    cur_group = [(y_min, x_min, txt)]
                    cur_y = y_min
                else:
                    cur_group.append((y_min, x_min, txt))
            if cur_group:
                groups.append(cur_group)

            page_lines: List[Line] = []
            for group in groups:
                group.sort(key=lambda f: f[1])
                run = []
                for frag in group:
                    if not run:
                        run.append(frag)
                        continue
                    prev = run[-1]
                    approx_right = prev[1] + len(prev[2]) * 7.2
                    if frag[1] - approx_right > GAP:
                        page_lines.append(_emit_line(run, page_h, page_idx))
                        run = [frag]
                    else:
                        run.append(frag)
                if run:
                    page_lines.append(_emit_line(run, page_h, page_idx))

            page_lines.sort(key=lambda l: -l.y_top)
            pages_out.append(page_lines)
    return pages_out


def parse_fdx(path: str):
    """Quick FDX sanity check: count <Paragraph Type="Scene Heading"> and
    cue paragraphs, no full re-implementation needed."""
    with open(path, "rb") as f:
        data = f.read()
    text = data.decode("utf-8", errors="replace")
    # Strip BOM / xml decl quirks safely.
    if text.startswith("﻿"):
        text = text[1:]
    root = ET.fromstring(text)
    scene_count = 0
    cue_count = 0
    dialogue_count = 0
    action_count = 0
    title = None
    for para in root.iter("Paragraph"):
        ty = para.get("Type", "Action")
        text_content = "".join(t.text or "" for t in para.iter("Text")).strip()
        if not text_content:
            continue
        if ty == "Scene Heading":
            scene_count += 1
        elif ty == "Character":
            cue_count += 1
        elif ty == "Dialogue":
            dialogue_count += 1
        elif ty == "Action":
            action_count += 1
    # First Title-Page paragraph as a heuristic title.
    for tp in root.iter("TitlePage"):
        for para in tp.iter("Paragraph"):
            text_content = "".join(t.text or "" for t in para.iter("Text")).strip()
            if text_content:
                title = text_content
                break
        if title:
            break
    return {
        "scenes": scene_count,
        "cues": cue_count,
        "dialogue": dialogue_count,
        "action": action_count,
        "title": title,
    }


def main(argv):
    failures = []

    # PDF targets
    pdf_targets = []
    if len(argv) > 1:
        pdf_targets = [a for a in argv[1:] if a.lower().endswith(".pdf")]
        fdx_targets = [a for a in argv[1:] if a.lower().endswith(".fdx")]
    else:
        fdx_targets = []
        if os.path.isdir(FIXTURES):
            for name in sorted(os.listdir(FIXTURES)):
                p = os.path.join(FIXTURES, name)
                if name.lower().endswith(".pdf") and os.path.isfile(p):
                    pdf_targets.append(p)
                elif name.lower().endswith(".fdx") and os.path.isfile(p):
                    fdx_targets.append(p)

    # ------------------------------------------------------------------
    # PDF parsing
    # ------------------------------------------------------------------
    print("=" * 72)
    print(f"PDF parsing — {len(pdf_targets)} target(s)")
    print("=" * 72)
    for path in pdf_targets:
        label = os.path.relpath(path, ROOT) if path.startswith(ROOT) else path
        try:
            pages = extract_lines_via_pdfplumber(path)
            doc, diag = parse(pages)
            report(label, doc, diag)
            # Acceptance baseline: real screenplay must yield ≥ 1 scene
            # AND ≥ 1 character cue.
            cue_count = sum(1 for s in doc.scenes for e in s.elements
                            if e.kind == "character")
            if diag.scene_count < 1:
                raise AssertionError(f"{label}: zero scenes parsed")
            if cue_count < 1:
                raise AssertionError(f"{label}: zero character cues parsed")
            print(f"  ✅ {os.path.basename(path)}: {diag.scene_count} scene(s), {cue_count} cue(s)")
        except Exception as exc:
            failures.append(f"{label}: {exc}")
            print(f"  ❌ {label}: {exc}")

    # ------------------------------------------------------------------
    # FDX parsing
    # ------------------------------------------------------------------
    print()
    print("=" * 72)
    print(f"FDX parsing — {len(fdx_targets)} target(s)")
    print("=" * 72)
    for path in fdx_targets:
        label = os.path.relpath(path, ROOT) if path.startswith(ROOT) else path
        try:
            r = parse_fdx(path)
            print(f"  ✅ {label}: {r['scenes']} scenes, {r['cues']} cues, "
                  f"{r['dialogue']} dialogue, {r['action']} action; "
                  f"title={r['title']!r}")
            if r["scenes"] < 1:
                raise AssertionError("zero scene headings found")
        except Exception as exc:
            failures.append(f"{label}: {exc}")
            print(f"  ❌ {label}: {exc}")

    print()
    if failures:
        print(f"FAIL: {len(failures)} failure(s)")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"PASS: {len(pdf_targets) + len(fdx_targets)} fixture(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
