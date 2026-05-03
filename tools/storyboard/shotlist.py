"""AST -> shot list with timings.

A "shot" is one sustained image on screen, held for a duration. The
storyboard pipeline holds each shot for N stop-motion frames per pose,
cycling between 2-3 pose variants for the staccato judder.

Heuristics:
  • Slug shot: 1.8 s, 2 poses (establishes scene).
  • Action shot: max(1.6 s, min(4.5 s, words / 2.6 wps)), 2 poses.
    Long action paragraphs are split on sentence boundaries so each
    beat gets its own image.
  • Dialogue shot: max(1.6 s, words / 2.5 wps), 3 poses (mouth cycles).
  • Transition: 1.0 s, 1 pose.

Each shot also carries:
  • `roster`        — characters in the scene up through this shot,
                      in first-appearance order (for left/right staging).
  • `mentioned`     — names that appear in this shot's text.
  • `props`         — prop keywords detected in the text (kettle, cup, …).
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set
import re

from fountain import Document, Scene, Element


# ---- Prop dictionary -------------------------------------------------
#
# Maps a canonical prop key to the words that should trigger it in
# action / dialogue text. Order matters when two keys would both match
# a substring; the first match wins.

_PROP_PATTERNS: List[tuple[str, tuple[str, ...]]] = [
    ("kettle",   ("kettle",)),
    ("cup",      ("steel cup", "tumbler", "chai", "cup")),
    ("glass",    ("glass",)),
    ("radio",    ("radio",)),
    ("backpack", ("backpack",)),
    ("headphones", ("headphones", "earphones")),
    ("counter",  ("counter", "stall")),
    ("milk",     ("milk",)),
    ("steam",    ("steam",)),
    ("traffic",  ("traffic", "rickshaw", "auto", "car", "bus")),
    ("door",     ("door", "doorway", "threshold")),
    ("phone",    ("phone", "mobile",)),
    ("book",     ("book", "notebook")),
    ("pen",      ("pen", "pencil")),
    ("bed",      ("bed",)),
    ("desk",     ("desk", "table")),
    ("window",   ("window",)),
    ("bottle",   ("bottle",)),
    ("bag",      ("bag", "shopping bag")),
]


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
    location: str = ""   # 'INT' | 'EXT' | 'INT/EXT' | ''
    roster: List[str] = field(default_factory=list)
    mentioned: List[str] = field(default_factory=list)
    props: List[str] = field(default_factory=list)


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


_PROP_RE_CACHE: Dict[str, re.Pattern] = {}


def _prop_regex(word: str) -> re.Pattern:
    cached = _PROP_RE_CACHE.get(word)
    if cached is None:
        # Multi-word phrases ("steel cup") need flexible whitespace,
        # single words need full word boundaries so "phone" doesn't
        # match "headphones".
        pat = r"\b" + re.escape(word).replace(r"\ ", r"\s+") + r"\b"
        cached = re.compile(pat, re.IGNORECASE)
        _PROP_RE_CACHE[word] = cached
    return cached


def _detect_props(text: str) -> List[str]:
    found: List[str] = []
    for key, words in _PROP_PATTERNS:
        if any(_prop_regex(w).search(text) for w in words):
            if key not in found:
                found.append(key)
    return found


def _detect_mentions(text: str, roster: List[str]) -> List[str]:
    """Return roster names that appear in `text` as a whole word.

    Matches on the upper-cased name. We allow lowercase first letter
    matching too because action prose often refers to characters in
    title case ("Raja smiles") even though the cue was "RAJA".
    """
    found: List[str] = []
    for name in roster:
        pattern = re.compile(rf"\b{re.escape(name)}\b", re.IGNORECASE)
        if pattern.search(text):
            if name not in found:
                found.append(name)
    return found


_SENT_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-Z(])")


def _split_sentences(paragraph: str) -> List[str]:
    """Split an action paragraph into sentences.

    Conservative: only splits on `.`, `!`, `?` followed by whitespace
    and a capital letter or open-paren. Single-sentence paragraphs
    return unchanged.
    """
    paragraph = paragraph.strip()
    if not paragraph:
        return []
    parts = _SENT_SPLIT.split(paragraph)
    out = [p.strip() for p in parts if p.strip()]
    # Don't split a paragraph into 1-2 word fragments.
    return out if all(_word_count(p) >= 2 for p in out) else [paragraph]


def _action_duration(text: str) -> float:
    wc = _word_count(text)
    return max(1.6, min(4.5, wc / 2.6))


def _scene_roster(scene: Scene) -> List[str]:
    """First-appearance order of named characters in a scene.

    Picks up names from explicit cues AND from ALL-CAPS character
    introductions in action lines like
    "RAJA (50s, weathered) wipes a glass…".
    """
    seen: Set[str] = set()
    order: List[str] = []
    intro_re = re.compile(r"\b([A-Z][A-Z'-]{1,30})\b")
    for el in scene.elements:
        if el.kind == "character":
            name = el.text.strip().upper()
            if name and name not in seen:
                seen.add(name)
                order.append(name)
        elif el.kind == "action":
            # An ALL-CAPS token of 2+ letters in action text usually
            # introduces or refers to a character. Skip common false
            # positives like "INT" / "EXT" / "DAY" / "NIGHT" / "I".
            stop = {
                "INT", "EXT", "DAY", "NIGHT", "MORNING", "EVENING",
                "AFTERNOON", "CONTINUOUS", "LATER", "SAME", "OK",
                "OKAY", "USA", "UK", "AM", "PM", "TV", "DJ",
            }
            for m in intro_re.findall(el.text):
                if m in stop or len(m) < 2:
                    continue
                if m not in seen:
                    seen.add(m)
                    order.append(m)
    return order


_INTRO_RE = re.compile(r"\b([A-Z][A-Z'-]{1,30})\s*\(([^)]{1,200})\)")


def extract_intros(doc: Document) -> Dict[str, str]:
    """Scan action lines for "<NAME> (<descriptors>)" introductions.

    Returns name -> descriptor blob, e.g.
    "PRIYA" -> "20s, backpack, headphones around her neck".
    """
    out: Dict[str, str] = {}
    for scene in doc.scenes:
        for el in scene.elements:
            if el.kind != "action":
                continue
            for m in _INTRO_RE.finditer(el.text):
                name, desc = m.group(1), m.group(2).strip()
                if name in {"INT", "EXT", "DAY", "NIGHT", "CONTINUOUS",
                            "LATER", "SAME", "MORNING", "AFTERNOON",
                            "EVENING", "V", "O", "S"}:
                    continue
                if name not in out:
                    out[name] = desc
    return out


_MALE_TOKENS = {
    "he", "him", "his", "man", "boy", "guy", "gentleman", "father",
    "son", "uncle", "brother", "husband", "sir", "mister", "mr",
}
_FEMALE_TOKENS = {
    "she", "her", "hers", "woman", "girl", "lady", "mother", "daughter",
    "aunt", "sister", "wife", "ma'am", "madam", "mrs", "miss", "ms",
}
_NAME_WINDOW = 60   # words after a name to scan for pronouns
_NAME_TOKEN_RE = re.compile(r"[A-Za-z']+")


def extract_genders(doc: Document, roster: Optional[List[str]] = None
                    ) -> Dict[str, str]:
    """Heuristic name -> 'm' | 'f' map, derived from pronouns near
    each character mention plus descriptor keywords.

    Strategy: for each ALL-CAPS character name found in any action
    line, scan up to `_NAME_WINDOW` whitespace tokens AFTER the name
    and tally male/female pronoun hits. The first decisive scene wins.
    Descriptor blob (from extract_intros) is consulted last.
    """
    intros = extract_intros(doc)
    candidates: set = set()
    for scene in doc.scenes:
        for el in scene.elements:
            if el.kind == "character":
                candidates.add(el.text.strip().upper())
    # Also accept names that appear in intro descriptors (action prose).
    candidates.update(intros.keys())
    if roster:
        candidates.update(r.upper() for r in roster)

    # Aggregate text per character: scan action prose, and for every
    # token that matches a known character (case-insensitive), grab a
    # window of words after it. Names with all-caps cues match either
    # spelling ("Raja smiles" or "RAJA wipes").
    bag: Dict[str, str] = {}
    for scene in doc.scenes:
        for el in scene.elements:
            if el.kind != "action":
                continue
            tokens = _NAME_TOKEN_RE.findall(el.text)
            for i, original in enumerate(tokens):
                if original.upper() not in candidates:
                    continue
                window_end = min(len(tokens), i + 1 + _NAME_WINDOW)
                snippet = " ".join(tokens[i + 1:window_end])
                bag.setdefault(original.upper(), "")
                bag[original.upper()] += " " + snippet
    out: Dict[str, str] = {}
    for name, blob in bag.items():
        low = blob.lower()
        words = set(re.findall(r"[a-z']+", low))
        m = sum(1 for w in words if w in _MALE_TOKENS)
        f = sum(1 for w in words if w in _FEMALE_TOKENS)
        if m > f:
            out[name] = "m"
        elif f > m:
            out[name] = "f"
        # ambiguous -> consult descriptor
        if name not in out and name in intros:
            d = intros[name].lower()
            if any(w in d for w in _MALE_TOKENS):
                out[name] = "m"
            elif any(w in d for w in _FEMALE_TOKENS):
                out[name] = "f"
    return out


def build(doc: Document) -> List[Shot]:
    shots: List[Shot] = []
    for idx, scene in enumerate(doc.scenes):
        loc = _location_tag(scene.heading)
        roster = _scene_roster(scene)

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
                roster=list(roster),
            )
        )

        # Track which roster members have been seen IN-SHOT so far,
        # so each shot's `roster` reflects the cumulative cast at that
        # point in the scene (useful for staging carry-over).
        seen_so_far: List[str] = []

        def cumulative(extra: List[str]) -> List[str]:
            cur = list(seen_so_far)
            for n in extra:
                if n not in cur:
                    cur.append(n)
            return cur

        pending_paren: Optional[str] = None
        for el in scene.elements:
            if el.kind == "parenthetical":
                pending_paren = el.text.strip("()").strip()
                continue
            if el.kind == "action":
                # Split on sentences so each beat gets a frame.
                for sentence in _split_sentences(el.text):
                    mentions = _detect_mentions(sentence, roster)
                    seen_so_far = cumulative(mentions)
                    shots.append(
                        Shot(
                            kind="action",
                            scene_heading=scene.heading,
                            text=sentence,
                            duration_s=_action_duration(sentence),
                            poses=2,
                            scene_index=idx,
                            location=loc,
                            roster=list(seen_so_far),
                            mentioned=mentions,
                            props=_detect_props(sentence),
                        )
                    )
                pending_paren = None
            elif el.kind == "dialogue":
                wc = _word_count(el.text)
                dur = max(1.6, wc / 2.5)
                speaker = el.character
                if speaker and speaker not in seen_so_far:
                    seen_so_far = cumulative([speaker])
                shots.append(
                    Shot(
                        kind="dialogue",
                        scene_heading=scene.heading,
                        text=el.text,
                        character=speaker,
                        parenthetical=pending_paren,
                        duration_s=dur,
                        poses=3,
                        scene_index=idx,
                        location=loc,
                        roster=list(seen_so_far),
                        mentioned=[speaker] if speaker else [],
                        props=_detect_props(el.text),
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
                        roster=list(seen_so_far),
                    )
                )
            elif el.kind == "character":
                # Character cue is metadata for the next dialogue/paren.
                continue
    return shots
