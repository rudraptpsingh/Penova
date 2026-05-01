#!/usr/bin/env python3
"""
render_release_notes.py

Renders a `docs/release-notes/<version>.html` page from a free-form
release-notes string (typically the git tag's annotation message).

Used by the release workflow on every tag push so Sparkle's update
dialog has structured HTML to display when offering the user the
new version.

Bullet detection: any line starting with "- " or "* " becomes an <li>;
consecutive bullets group into a <ul>. Lines starting with "## " become
<h2> headings. Everything else becomes a <p>.

Usage:
    render_release_notes.py --version 1.2.0 --notes "$NOTES" --out ...html
"""

from __future__ import annotations

import argparse
import html
import sys
from datetime import datetime, timezone
from pathlib import Path


HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Penova {version} — release notes</title>
<style>
  body {{
    background: #0b0a08;
    color: #efe9db;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro", system-ui, sans-serif;
    font-size: 14px;
    line-height: 1.55;
    margin: 24px;
  }}
  h1 {{ font-size: 22px; margin: 0 0 16px; color: #fff; }}
  h2 {{ font-size: 16px; margin: 24px 0 8px; color: #f0a94a; }}
  ul {{ padding-left: 20px; }}
  li {{ margin-bottom: 6px; }}
  p  {{ margin: 8px 0; }}
  .date {{ font-family: ui-monospace, "SF Mono", Menlo, monospace;
          font-size: 11px; color: #948e80; letter-spacing: 0.06em;
          text-transform: uppercase; margin-bottom: 18px; }}
  code {{ font-family: ui-monospace, "SF Mono", Menlo, monospace;
         font-size: 12.5px; background: #1a1a17; padding: 1px 5px;
         border-radius: 3px; color: #d4cebe; }}
  strong {{ color: #fff; }}
</style>
</head>
<body>
<h1>Penova {version}</h1>
<div class="date">{date} · macOS 14+</div>
"""

FOOT = """
<p style="margin-top: 32px; color: #5e5a52; font-size: 12px;">
  Feedback or bug reports — <a href="mailto:rudra.ptp.singh@gmail.com" style="color: #f0a94a;">rudra.ptp.singh@gmail.com</a>
  · <a href="tel:+919956340651" style="color: #f0a94a;">+91 99563 40651</a>
  · <a href="https://wa.me/919956340651" style="color: #f0a94a;">WhatsApp</a>.
</p>
</body>
</html>
"""


def render(notes: str) -> str:
    """Convert a free-form notes string into the body HTML."""
    out: list[str] = []
    in_list = False
    for raw in notes.splitlines():
        line = raw.rstrip()
        stripped = line.lstrip()

        if not stripped:
            if in_list:
                out.append("</ul>")
                in_list = False
            continue

        if stripped.startswith("## "):
            if in_list:
                out.append("</ul>")
                in_list = False
            heading = html.escape(stripped[3:].strip())
            out.append(f"<h2>{heading}</h2>")
            continue

        if stripped.startswith("- ") or stripped.startswith("* "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            item = html.escape(stripped[2:].strip())
            out.append(f"<li>{item}</li>")
            continue

        if in_list:
            out.append("</ul>")
            in_list = False
        out.append(f"<p>{html.escape(stripped)}</p>")

    if in_list:
        out.append("</ul>")

    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--notes",   required=True, help="Free-form notes text.")
    parser.add_argument("--out",     required=True, type=Path)
    args = parser.parse_args()

    today = datetime.now(timezone.utc).strftime("%-d %b %Y")
    body = render(args.notes)
    rendered = HEAD.format(version=args.version, date=today) + body + FOOT

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(rendered, encoding="utf-8")
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
