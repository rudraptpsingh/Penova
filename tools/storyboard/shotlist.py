"""AST -> shot list with timings.

A "shot" is one sustained image on screen, held for a duration. The
storyboard pipeline holds each shot for N stop-motion frames per pose,
cycling between 2-3 pose variants for the staccato judder.

Heuristics:
  • Slug shot: 1.6 s, 2 poses (establishes scene).
  • Action shot: max(1.8 s, words / 2.6 wps), 2 poses.
  • Dialogue shot: max(1.6 s, words / 2.5 wps), 3 poses (mouth cycles).
  • Transition: 1.0 s, 1 pose.

Words-per-second for dialogue is intentionally slow (~150 wpm) so the
animatic feels readable. Action narration speed is similar.
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import List, Optional

from fountain import Document, Scene, Element


@dataclass
class Shot:
    kind: str            # 'slug' | 'action' | 'dialogue' | 'transition'
    scene_heading: str
    text: str            # caption / dialogue body
    character: Optional[str] = None
    parenthetical: Optional[str] = None
    duration_s: float = 1.6
    poses: int = 2       # number of distinct pose variants to alternate
    scene_index: int = 0
    location: str = ""   # 'INT' | 'EXT' | ''


def _location_tag(heading: str) -> str:
    upper = heading.upper().lstrip()
    if upper.startswith(("INT/EXT", "INT./EXT", "I/E", "I./E")):
        return "INT/EXT"
    if upper.startswith(("EXT", "EST")):
        return "EXT"
    if upper.startswith("INT"):
        return "INT"
    return ""


def _word_count(s: str) -> int:
    return len([w for w in s.split() if w.strip()])


def build(doc: Document) -> List[Shot]:
    shots: List[Shot] = []
    for idx, scene in enumerate(doc.scenes):
        loc = _location_tag(scene.heading)
        # Slug shot first.
        shots.append(
            Shot(
                kind="slug",
                scene_heading=scene.heading,
                text=scene.heading,
                duration_s=1.8,
                poses=2,
                scene_index=idx,
                location=loc,
            )
        )

        pending_paren: Optional[str] = None
        for el in scene.elements:
            if el.kind == "parenthetical":
                pending_paren = el.text.strip("()").strip()
                continue
            if el.kind == "action":
                wc = _word_count(el.text)
                dur = max(1.8, wc / 2.6)
                shots.append(
                    Shot(
                        kind="action",
                        scene_heading=scene.heading,
                        text=el.text,
                        duration_s=dur,
                        poses=2,
                        scene_index=idx,
                        location=loc,
                    )
                )
                pending_paren = None
            elif el.kind == "dialogue":
                wc = _word_count(el.text)
                dur = max(1.6, wc / 2.5)
                shots.append(
                    Shot(
                        kind="dialogue",
                        scene_heading=scene.heading,
                        text=el.text,
                        character=el.character,
                        parenthetical=pending_paren,
                        duration_s=dur,
                        poses=3,
                        scene_index=idx,
                        location=loc,
                    )
                )
                pending_paren = None
            elif el.kind == "transition":
                shots.append(
                    Shot(
                        kind="transition",
                        scene_heading=scene.heading,
                        text=el.text,
                        duration_s=1.0,
                        poses=1,
                        scene_index=idx,
                        location=loc,
                    )
                )
            elif el.kind == "character":
                # Character cue is metadata for the next dialogue/paren.
                continue
    return shots
