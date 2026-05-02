#!/usr/bin/env python3
"""
last_two_versions.py

Reads `docs/appcast.xml` and prints the latest two
`<sparkle:shortVersionString>` values, newest first, one per line.

Used by the release workflow to figure out the previous version so
it can rewrite version refs across the website (homepage, blog,
support, privacy) as part of a tag-push deploy.

Output format:
    1.2.0
    1.1.0
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: last_two_versions.py docs/appcast.xml", file=sys.stderr)
        return 1
    feed = Path(sys.argv[1]).read_text(encoding="utf-8")
    versions = re.findall(
        r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>",
        feed,
    )
    for v in versions[:2]:
        print(v.strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
