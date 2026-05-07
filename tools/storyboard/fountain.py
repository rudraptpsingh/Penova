"""Minimal Fountain parser for the storyboard tool.

Mirrors the pragmatic subset implemented in
PenovaKit/Sources/PenovaKit/FountainParser.swift, kept dependency-free
so the storyboard pipeline runs from a clean Python install.

Element kinds: heading | action | character | parenthetical | dialogue |
transition. Title page is a key->value dict consumed from the top of the
file until the first blank line.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, field
from typing import List, Dict, Optional


SCENE_PREFIXES = (
    "INT.", "EXT.", "EST.",
    "INT/EXT.", "INT./EXT.", "EXT/INT.", "EXT./INT.",
    "I/E.", "I./E.",
)

TITLE_KEY_RE = re.compile(r"^([A-Za-z][A-Za-z _-]{0,31}):\s*(.*)$")


@dataclass
class Element:
    kind: str
    text: str
    character: Optional[str] = None  # only set on dialogue/parenthetical


@dataclass
class Scene:
    heading: str
    elements: List[Element] = field(default_factory=list)


@dataclass
class Document:
    title_page: Dict[str, str] = field(default_factory=dict)
    scenes: List[Scene] = field(default_factory=list)


def _is_caps(s: str) -> bool:
    """A line counts as 'all caps' if it has at least one letter and no
    lowercase letters. Digits, parens, periods, slashes are tolerated.
    """
    saw_letter = False
    for ch in s:
        if ch.isalpha():
            saw_letter = True
            if ch.islower():
                return False
    return saw_letter


def _is_scene_heading(line: str) -> bool:
    t = line.strip()
    if not t:
        return False
    if t.startswith("."):  # forced heading: ".INT WAREHOUSE"
        rest = t[1:].lstrip().upper()
        return rest.startswith(("INT", "EXT", "EST", "I/E", "I./E"))
    upper = t.upper()
    for p in SCENE_PREFIXES:
        if upper.startswith(p) or upper.startswith(p + " "):
            return True
    return False


def _is_transition(line: str) -> bool:
    t = line.strip()
    if not t or not _is_caps(t):
        return False
    upper = t.upper()
    if upper.endswith("TO:"):
        return True
    if upper in {
        "FADE OUT.", "FADE OUT", "FADE TO BLACK.", "FADE TO BLACK",
        "THE END.", "THE END",
    }:
        return True
    # Forced transition: ">SMASH CUT"
    if t.startswith(">") and t.endswith(":"):
        return True
    return False


def _is_parenthetical(line: str) -> bool:
    t = line.strip()
    return t.startswith("(") and t.endswith(")") and len(t) >= 2


def _is_character_cue(line: str, next_line: Optional[str]) -> bool:
    """A character cue is an ALL CAPS line followed by a non-blank line.
    The follower may be a parenthetical or dialogue. Single-word ALL CAPS
    that happen to be transitions are already filtered earlier.
    """
    t = line.strip()
    if not t or not _is_caps(t):
        return False
    if len(t) > 50 or len(t) < 2:
        return False
    if any(c in t for c in ".,!?"):
        # Cues with "(V.O.)" / "(O.S.)" / "(CONT'D)" still contain a "."
        # — only reject if the period sits OUTSIDE a parenthetical suffix.
        bare = re.sub(r"\s*\([^)]*\)\s*$", "", t)
        if any(c in bare for c in ".,!?"):
            return False
    if next_line is None:
        return False
    return next_line.strip() != ""


def _strip_cue_suffix(text: str) -> str:
    """Strip "(V.O.)", "(O.S.)", "(CONT'D)" etc. from a character cue,
    leaving just the speaking name."""
    return re.sub(r"\s*\([^)]*\)\s*$", "", text).strip()


def _strip_scene_number(text: str) -> str:
    """Drop a trailing/leading "#42" Fountain scene number marker."""
    # Trailing "#42#"
    text = re.sub(r"\s*#[A-Za-z0-9.-]+#\s*$", "", text)
    return text.strip()


def parse(source: str) -> Document:
    src = source.replace("\r\n", "\n").replace("\r", "\n")
    raw_lines = src.split("\n")

    doc = Document()

    # ---- Title page (key: value pairs until first blank line) ----
    body_start = 0
    if raw_lines:
        # Find first non-empty
        i = 0
        while i < len(raw_lines) and raw_lines[i].strip() == "":
            i += 1
        if i < len(raw_lines) and TITLE_KEY_RE.match(raw_lines[i].strip()):
            last_key: Optional[str] = None
            while i < len(raw_lines):
                line = raw_lines[i]
                if line.strip() == "":
                    body_start = i + 1
                    break
                # Continuation lines (3+ leading spaces or a tab).
                if (line.startswith("\t") or line.startswith("   ")) and last_key:
                    cont = line.strip()
                    prev = doc.title_page.get(last_key, "")
                    doc.title_page[last_key] = (
                        prev + "\n" + cont if prev else cont
                    )
                else:
                    m = TITLE_KEY_RE.match(line.strip())
                    if m:
                        key = m.group(1).strip().lower()
                        val = m.group(2).strip()
                        doc.title_page[key] = val
                        last_key = key
                    else:
                        # Not a title-page line after all — abandon what we
                        # collected and treat the whole file as body.
                        doc.title_page.clear()
                        body_start = 0
                        break
                i += 1
                if i == len(raw_lines):
                    body_start = i

    lines = raw_lines[body_start:]

    # ---- Body parse ----
    current: Optional[Scene] = None
    pending_action: List[str] = []
    last_character: Optional[str] = None
    expecting_dialogue_block = False  # true after a character cue

    def flush_action():
        nonlocal pending_action
        if not pending_action:
            return
        joined = " ".join(s.strip() for s in pending_action).strip()
        pending_action = []
        if joined and current is not None:
            current.elements.append(Element("action", joined))

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped == "":
            flush_action()
            expecting_dialogue_block = False
            i += 1
            continue

        if _is_scene_heading(stripped):
            flush_action()
            expecting_dialogue_block = False
            heading = stripped[1:].strip() if stripped.startswith(".") else stripped
            heading = _strip_scene_number(heading)
            if current is not None:
                doc.scenes.append(current)
            current = Scene(heading=heading)
            i += 1
            continue

        if _is_transition(stripped):
            flush_action()
            expecting_dialogue_block = False
            text = stripped[1:].strip() if stripped.startswith(">") else stripped
            if current is not None:
                current.elements.append(Element("transition", text))
            i += 1
            continue

        # Look-ahead so we can disambiguate cue vs action.
        next_line = lines[i + 1] if i + 1 < len(lines) else None

        if expecting_dialogue_block:
            if _is_parenthetical(stripped):
                if current is not None:
                    current.elements.append(
                        Element("parenthetical", stripped, character=last_character)
                    )
                i += 1
                continue
            # Otherwise it's dialogue. Collapse continuation lines until
            # blank.
            buf = [stripped]
            j = i + 1
            while j < len(lines) and lines[j].strip() != "":
                if _is_parenthetical(lines[j].strip()):
                    break
                buf.append(lines[j].strip())
                j += 1
            if current is not None:
                current.elements.append(
                    Element("dialogue", " ".join(buf), character=last_character)
                )
            i = j
            continue

        if _is_character_cue(stripped, next_line):
            flush_action()
            cue = _strip_cue_suffix(stripped)
            last_character = cue
            expecting_dialogue_block = True
            if current is not None:
                current.elements.append(Element("character", cue))
            i += 1
            continue

        # Default → action. Collect contiguous non-blank lines.
        pending_action.append(stripped)
        i += 1

    flush_action()
    if current is not None:
        doc.scenes.append(current)

    return doc
