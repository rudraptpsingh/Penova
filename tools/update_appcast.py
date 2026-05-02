#!/usr/bin/env python3
"""
update_appcast.py

Inserts a new <item> block at the top of `docs/appcast.xml`, right
after `<language>en</language>` and before any existing items, so the
feed stays in newest-first order. Used by .github/workflows/release.yml
on every tag push.

Usage:
    update_appcast.py --feed docs/appcast.xml --new-item "<item>...</item>"
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


INSERTION_ANCHOR = "<language>en</language>"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--feed", required=True, type=Path)
    parser.add_argument("--new-item", required=True, type=str)
    args = parser.parse_args()

    text = args.feed.read_text(encoding="utf-8")
    if INSERTION_ANCHOR not in text:
        print(
            f"error: appcast.xml missing the '{INSERTION_ANCHOR}' anchor "
            "the script needs for newest-first insertion.",
            file=sys.stderr,
        )
        return 1

    # Indent the supplied <item> block one level deeper than the anchor
    # (8 spaces — matches the existing convention in the repo's appcast).
    new_item = args.new_item.strip()
    indented_lines: list[str] = []
    for line in new_item.splitlines():
        if line.strip():
            indented_lines.append("        " + line.lstrip())
        else:
            indented_lines.append("")
    indented = "\n".join(indented_lines)

    # If the version we're emitting already exists in the feed, replace
    # it instead of duplicating. This keeps re-runs of the workflow
    # idempotent.
    short_version_match = re.search(
        r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>",
        new_item,
    )
    if short_version_match is not None:
        version = short_version_match.group(1)
        existing_pattern = re.compile(
            r"\s*<item>[\s\S]*?<sparkle:shortVersionString>"
            + re.escape(version)
            + r"</sparkle:shortVersionString>[\s\S]*?</item>\s*",
            re.MULTILINE,
        )
        if existing_pattern.search(text):
            text = existing_pattern.sub("\n", text, count=1)

    replacement = f"{INSERTION_ANCHOR}\n{indented}"
    new_text = text.replace(INSERTION_ANCHOR, replacement, 1)
    args.feed.write_text(new_text, encoding="utf-8")
    print(f"appcast updated: {args.feed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
