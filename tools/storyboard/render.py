"""Pillow renderer: shot -> PIL.Image, hand-drawn black-outline aesthetic.

Lines are drawn as polylines with small per-vertex jitter so the strokes
look like ink on paper rather than vector-perfect geometry. Each shot
exposes a small set of pose variants the stitcher cycles through; that
cycling, plus a separate per-frame ±2 px whole-figure jitter applied at
stitch time, is what produces the stop-motion judder.

What's drawn per shot kind:
  • slug         — big "SCENE N" card, no slug bar overlay
  • action       — location backdrop + present characters + props,
                   plus a narrator caption box at the bottom
  • dialogue     — location backdrop + two-shot staging (speaker high-
                   lighted, listener faded) + speech bubble
  • transition   — bold centred keyword (CUT TO:, FADE OUT.)

Public surface:
    render_pose(shot, pose_index, size=(W, H)) -> PIL.Image.Image
    draw_slug_overlay(img, heading)            -> PIL.Image.Image
"""
from __future__ import annotations
import math
import random
import re
from typing import List, Tuple, Optional, Dict

from PIL import Image, ImageDraw, ImageFont

from shotlist import Shot
from style import Style, load as _load_style

# ---- Active style (mutable, set via `set_style`) -------------------
# Defaults below mirror the "calvin" preset so the module is usable
# without an explicit set_style call.

_STYLE: Style = _load_style("calvin")


def set_style(style) -> None:
    """Replace the active style. Accepts a Style object, preset name,
    or path to a json file."""
    global _STYLE, CANVAS, BG, INK, INK_FAINT, SLUG_BG, SLUG_FG, \
        STROKE, SLUG_BAR_H
    _STYLE = _load_style(style)
    CANVAS    = (_STYLE.canvas_w, _STYLE.canvas_h)
    BG        = _STYLE.bg
    INK       = _STYLE.ink
    INK_FAINT = _STYLE.ink_faint
    SLUG_BG   = _STYLE.slug_bg
    SLUG_FG   = _STYLE.slug_fg
    STROKE    = _STYLE.stroke
    SLUG_BAR_H = _STYLE.slug_bar_h


# ---- Layout (kept as module names for compatibility) --------------
CANVAS    = (_STYLE.canvas_w, _STYLE.canvas_h)
BG        = _STYLE.bg
INK       = _STYLE.ink
INK_FAINT = _STYLE.ink_faint
SLUG_BG   = _STYLE.slug_bg
SLUG_FG   = _STYLE.slug_fg
STROKE    = _STYLE.stroke
SLUG_BAR_H = _STYLE.slug_bar_h


# ---- Font loader -----------------------------------------------------

def _font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = (
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold
        else "/System/Library/Fonts/Supplemental/Arial.ttf",
    )
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


# ---- Wobbly-line primitives -----------------------------------------

def _wobble_line(
    draw: ImageDraw.ImageDraw,
    p1: Tuple[float, float],
    p2: Tuple[float, float],
    *,
    rng: random.Random,
    jitter: Optional[float] = None,
    segments: Optional[int] = None,
    width: Optional[int] = None,
    color: Optional[Tuple[int, int, int]] = None,
):
    """Calvin-and-Hobbes-feel line: more segments + a bias along the
    direction so the wobble looks like ink flow, not noise.

    `jitter`, `segments`, `width`, `color` default to the active style
    when not specified."""
    if jitter is None:
        jitter = _STYLE.line_jitter
    if segments is None:
        segments = _STYLE.line_segments
    if width is None:
        width = _STYLE.stroke
    if color is None:
        color = _STYLE.ink
    pts: List[Tuple[float, float]] = [p1]
    # A tiny normal-direction bias gives each line one consistent
    # "lean" instead of pure random jitter — closer to Watterson's
    # confident curves.
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    L = max(1.0, (dx * dx + dy * dy) ** 0.5)
    nx, ny = -dy / L, dx / L  # unit normal
    bias = rng.uniform(-jitter * 0.6, jitter * 0.6)
    for k in range(1, segments):
        t = k / segments
        # Sin curve along length, max bias at midpoint.
        b = bias * math.sin(t * math.pi)
        x = p1[0] + dx * t + nx * b + rng.uniform(-jitter * 0.5, jitter * 0.5)
        y = p1[1] + dy * t + ny * b + rng.uniform(-jitter * 0.5, jitter * 0.5)
        pts.append((x, y))
    pts.append(p2)
    draw.line(pts, fill=color, width=width, joint="curve")


def _wobble_circle(
    draw: ImageDraw.ImageDraw,
    cx: float, cy: float, r: float,
    *, rng: random.Random,
    jitter: Optional[float] = None,
    segments: Optional[int] = None,
    width: Optional[int] = None,
    color: Optional[Tuple[int, int, int]] = None,
):
    if jitter is None:
        jitter = _STYLE.circle_jitter
    if segments is None:
        segments = _STYLE.circle_segments
    if width is None:
        width = _STYLE.stroke
    if color is None:
        color = _STYLE.ink
    pts: List[Tuple[float, float]] = []
    for k in range(segments + 1):
        a = (k / segments) * math.tau
        rr = r + rng.uniform(-jitter, jitter)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    draw.line(pts, fill=color, width=width, joint="curve")


def _wobble_ellipse(
    draw: ImageDraw.ImageDraw,
    cx: float, cy: float, rx: float, ry: float,
    *, rng: random.Random, jitter: float = 1.4, segments: int = 40,
    width: int = STROKE, color: Tuple[int, int, int] = INK,
):
    pts: List[Tuple[float, float]] = []
    for k in range(segments + 1):
        a = (k / segments) * math.tau
        pts.append((
            cx + math.cos(a) * rx + rng.uniform(-jitter, jitter),
            cy + math.sin(a) * ry + rng.uniform(-jitter, jitter),
        ))
    draw.line(pts, fill=color, width=width, joint="curve")


def _wobble_polyline(
    draw: ImageDraw.ImageDraw,
    pts: List[Tuple[float, float]],
    *, rng: random.Random, jitter: float = 1.4, width: int = STROKE,
    color: Tuple[int, int, int] = INK,
    smooth: bool = False,
):
    """Draw a jittered polyline.

    `smooth=False` (default) uses straight joins — required for any
    shape with sharp corners (rectangles, hills, bubble outlines).
    PIL's "curve" joint draws Bezier-like loops at concave corners
    which look like graffiti on rectangles.
    """
    out: List[Tuple[float, float]] = []
    for x, y in pts:
        out.append((x + rng.uniform(-jitter, jitter),
                    y + rng.uniform(-jitter, jitter)))
    kwargs = {"fill": color, "width": width}
    if smooth:
        kwargs["joint"] = "curve"
    draw.line(out, **kwargs)


def _wobble_rect(
    draw: ImageDraw.ImageDraw,
    x1: float, y1: float, x2: float, y2: float,
    *, rng: random.Random, jitter: float = 1.2, width: int = STROKE,
    color: Tuple[int, int, int] = INK,
):
    pts = [(x1, y1), (x2, y1), (x2, y2), (x1, y2), (x1, y1)]
    _wobble_polyline(draw, pts, rng=rng, jitter=jitter, width=width, color=color)


# ---- Per-character traits -------------------------------------------
# Hash a character name into a small but visually distinct trait set.
# Same name -> same look across every shot in the animatic.

_HEAD_SHAPES = ("round", "oval", "square")
_HAIR_STYLES = ("short", "bun", "tuft", "cap", "long", "bald", "buzz", "side")
_ACCESSORIES = ("none", "backpack", "headphones", "apron", "scarf", "glasses", "satchel")
_EYEBROWS    = ("flat", "raised", "thick", "none")


def _stable_hash(s: str) -> int:
    """Deterministic across processes (Python's hash() is salted)."""
    h = 0
    for ch in s:
        h = (h * 1315423911) ^ ord(ch)
        h &= 0xFFFFFFFF
    return h


_INTROS: Dict[str, str] = {}


def seed_intros(intros: Dict[str, str]) -> None:
    """Provide script-derived character descriptors so traits_for can
    pick visual cues that match the writer's intent (backpack, apron…)
    instead of relying purely on the name hash."""
    global _INTROS
    _INTROS = {k.upper(): v for k, v in intros.items()}


# Keyword -> trait override. First match wins per slot.
_DESC_HAIR = [
    ("bun", "bun"), ("braid", "long"), ("ponytail", "long"),
    ("long hair", "long"), ("short hair", "short"),
    ("buzz", "buzz"), ("shaved", "buzz"), ("bald", "bald"),
    ("cap", "cap"),
]
_DESC_ACC = [
    ("backpack", "backpack"),
    ("headphones", "headphones"), ("earphones", "headphones"),
    ("apron", "apron"),
    ("scarf", "scarf"), ("dupatta", "scarf"),
    ("glasses", "glasses"), ("specs", "glasses"),
    ("satchel", "satchel"), ("bag", "satchel"),
]


def _override_from_desc(traits: Dict, desc: str) -> Dict:
    low = desc.lower()
    out = dict(traits)
    for kw, val in _DESC_HAIR:
        if kw in low:
            out["hair"] = val
            break
    for kw, val in _DESC_ACC:
        if kw in low:
            out["accessory"] = val
            break
    # "weathered" / "older" -> bald-leaning, smaller build adjustment
    if any(w in low for w in ("weathered", "older", "old man", "elderly")):
        if out["hair"] == "short":
            out["hair"] = "buzz"
    if "young" in low or "20s" in low or "teen" in low:
        if out["hair"] == "buzz":
            out["hair"] = "short"
    return out


def traits_for(name: Optional[str]) -> Dict:
    if not name:
        return {
            "head": "round", "hair": "short", "accessory": "none",
            "build": 1.0, "height": 1.0, "brow": "flat",
        }
    h = _stable_hash(name.upper())
    base = {
        "head":      _HEAD_SHAPES[h % len(_HEAD_SHAPES)],
        "hair":      _HAIR_STYLES[(h >> 3) % len(_HAIR_STYLES)],
        "accessory": _ACCESSORIES[(h >> 6) % len(_ACCESSORIES)],
        "brow":      _EYEBROWS[(h >> 10) % len(_EYEBROWS)],
        "build":     0.92 + ((h >> 13) % 5) * 0.04,
        "height":    0.94 + ((h >> 17) % 5) * 0.03,
    }
    desc = _INTROS.get(name.upper())
    if desc:
        base = _override_from_desc(base, desc)
    return base


# ---- Hair / accessories ---------------------------------------------

def _draw_hair(
    draw: ImageDraw.ImageDraw, cx: float, head_cy: float, head_r: float,
    style: str, *, rng: random.Random,
):
    if style == "bald":
        return
    if style == "short":
        _wobble_polyline(
            draw,
            [(cx - head_r * 0.95, head_cy - head_r * 0.55),
             (cx - head_r * 0.6,  head_cy - head_r * 1.1),
             (cx,                 head_cy - head_r * 1.18),
             (cx + head_r * 0.6,  head_cy - head_r * 1.1),
             (cx + head_r * 0.95, head_cy - head_r * 0.55)],
            rng=rng, jitter=1.0,
        )
    elif style == "buzz":
        # Dotted stipple along the scalp.
        for k in range(-4, 5):
            ax = cx + k * (head_r * 0.18)
            ay = head_cy - head_r * 0.92 + (abs(k) % 2) * 2
            draw.ellipse((ax - 2, ay - 2, ax + 2, ay + 2), fill=INK)
    elif style == "bun":
        _wobble_circle(draw, cx, head_cy - head_r * 1.15, head_r * 0.42,
                       rng=rng, jitter=0.8, segments=20)
        _wobble_polyline(
            draw,
            [(cx - head_r * 0.9, head_cy - head_r * 0.5),
             (cx,                head_cy - head_r * 0.95),
             (cx + head_r * 0.9, head_cy - head_r * 0.5)],
            rng=rng, jitter=0.8,
        )
    elif style == "tuft":
        # Two upward tufts.
        _wobble_polyline(
            draw,
            [(cx - head_r * 0.55, head_cy - head_r * 0.95),
             (cx - head_r * 0.3,  head_cy - head_r * 1.35),
             (cx - head_r * 0.05, head_cy - head_r * 0.95)],
            rng=rng, jitter=0.6,
        )
        _wobble_polyline(
            draw,
            [(cx + head_r * 0.05, head_cy - head_r * 0.95),
             (cx + head_r * 0.3,  head_cy - head_r * 1.35),
             (cx + head_r * 0.55, head_cy - head_r * 0.95)],
            rng=rng, jitter=0.6,
        )
    elif style == "cap":
        # Baseball-cap silhouette.
        _wobble_polyline(
            draw,
            [(cx - head_r * 1.0,  head_cy - head_r * 0.5),
             (cx - head_r * 0.95, head_cy - head_r * 1.05),
             (cx + head_r * 0.95, head_cy - head_r * 1.05),
             (cx + head_r * 1.0,  head_cy - head_r * 0.5)],
            rng=rng, jitter=0.8,
        )
        # Bill
        _wobble_polyline(
            draw,
            [(cx + head_r * 0.2,  head_cy - head_r * 0.5),
             (cx + head_r * 1.5,  head_cy - head_r * 0.35),
             (cx + head_r * 1.5,  head_cy - head_r * 0.2),
             (cx + head_r * 0.4,  head_cy - head_r * 0.35)],
            rng=rng, jitter=0.6,
        )
    elif style == "long":
        # Hair falls past shoulders.
        _wobble_polyline(
            draw,
            [(cx - head_r * 1.05, head_cy - head_r * 0.4),
             (cx - head_r * 0.95, head_cy - head_r * 1.15),
             (cx,                 head_cy - head_r * 1.22),
             (cx + head_r * 0.95, head_cy - head_r * 1.15),
             (cx + head_r * 1.05, head_cy - head_r * 0.4)],
            rng=rng, jitter=1.0,
        )
        _wobble_line(draw,
                     (cx - head_r * 1.05, head_cy - head_r * 0.4),
                     (cx - head_r * 0.95, head_cy + head_r * 1.4),
                     rng=rng, jitter=1.2)
        _wobble_line(draw,
                     (cx + head_r * 1.05, head_cy - head_r * 0.4),
                     (cx + head_r * 0.95, head_cy + head_r * 1.4),
                     rng=rng, jitter=1.2)
    elif style == "side":
        # Side-swept fringe.
        _wobble_polyline(
            draw,
            [(cx - head_r * 0.95, head_cy - head_r * 0.55),
             (cx - head_r * 0.5,  head_cy - head_r * 1.1),
             (cx + head_r * 0.7,  head_cy - head_r * 1.05),
             (cx + head_r * 0.4,  head_cy - head_r * 0.4)],
            rng=rng, jitter=0.8,
        )


def _draw_eyebrows(
    draw, cx, head_cy, head_r, style: str, *, s: float, rng: random.Random,
):
    if style == "none":
        return
    bx = 13 * s
    by = head_cy - head_r * 0.62
    if style == "flat":
        draw.line((cx - bx - 6, by, cx - bx + 6, by), fill=INK, width=STROKE - 1)
        draw.line((cx + bx - 6, by, cx + bx + 6, by), fill=INK, width=STROKE - 1)
    elif style == "raised":
        draw.line((cx - bx - 6, by + 1, cx - bx + 6, by - 4), fill=INK, width=STROKE - 1)
        draw.line((cx + bx - 6, by - 4, cx + bx + 6, by + 1), fill=INK, width=STROKE - 1)
    elif style == "thick":
        draw.line((cx - bx - 7, by, cx - bx + 7, by), fill=INK, width=STROKE + 1)
        draw.line((cx + bx - 7, by, cx + bx + 7, by), fill=INK, width=STROKE + 1)


def _draw_accessory(
    draw, *, accessory: str, cx: float, shoulder_y: float,
    head_cy: float, head_r: float, hip_y: float, scale: float,
    facing: int, rng: random.Random,
):
    s = scale
    if accessory == "none":
        return
    if accessory == "headphones":
        # U-arc over the head; cups at the temples.
        _wobble_polyline(
            draw,
            [(cx - head_r * 1.1, head_cy - head_r * 0.05),
             (cx - head_r * 0.6, head_cy - head_r * 1.25),
             (cx,                head_cy - head_r * 1.35),
             (cx + head_r * 0.6, head_cy - head_r * 1.25),
             (cx + head_r * 1.1, head_cy - head_r * 0.05)],
            rng=rng, jitter=0.6, width=STROKE - 1,
        )
        for ex in (-1, 1):
            ax = cx + ex * head_r * 1.05
            ay = head_cy - head_r * 0.05
            draw.ellipse((ax - 7, ay - 9, ax + 7, ay + 9), outline=INK, width=STROKE - 1)
    elif accessory == "backpack":
        # Strap loops over shoulder; humped pack hangs behind hip.
        bx = cx + (-1 if facing >= 0 else 1) * 18 * s
        bw = 56 * s
        bh = 100 * s
        _wobble_rect(draw,
                     bx - bw / 2, shoulder_y + 6,
                     bx + bw / 2, shoulder_y + bh,
                     rng=rng, jitter=0.8)
        # Strap
        _wobble_polyline(
            draw,
            [(cx - 22 * s, shoulder_y + 4),
             (cx - 22 * s, shoulder_y + 50 * s),
             (bx - bw / 2 + 4, shoulder_y + 50 * s)],
            rng=rng, jitter=0.6, width=STROKE - 1,
        )
    elif accessory == "apron":
        # Trapezoid over torso.
        _wobble_polyline(
            draw,
            [(cx - 30 * s, shoulder_y + 8),
             (cx + 30 * s, shoulder_y + 8),
             (cx + 38 * s, hip_y - 4),
             (cx - 38 * s, hip_y - 4),
             (cx - 30 * s, shoulder_y + 8)],
            rng=rng, jitter=0.8,
        )
        # Neck loop
        _wobble_polyline(
            draw,
            [(cx - 22 * s, shoulder_y + 8),
             (cx,          shoulder_y - 22 * s),
             (cx + 22 * s, shoulder_y + 8)],
            rng=rng, jitter=0.6, width=STROKE - 1,
        )
    elif accessory == "scarf":
        # Wrap around neck with two tails.
        ny = shoulder_y - 4
        _wobble_polyline(
            draw,
            [(cx - 22 * s, ny), (cx, ny + 6),
             (cx + 22 * s, ny), (cx + 12 * s, ny + 30 * s),
             (cx,                ny + 24 * s)],
            rng=rng, jitter=0.8, width=STROKE - 1,
        )
    elif accessory == "glasses":
        ey = head_cy - head_r * 0.18
        for ex in (-1, 1):
            ax = cx + ex * 13 * s
            draw.ellipse((ax - 9, ey - 7, ax + 9, ey + 7),
                         outline=INK, width=STROKE - 1)
        draw.line((cx - 4, ey, cx + 4, ey), fill=INK, width=STROKE - 1)
    elif accessory == "satchel":
        bx = cx + (-1 if facing >= 0 else 1) * 26 * s
        _wobble_rect(draw, bx - 28 * s, shoulder_y + 60 * s,
                     bx + 28 * s, shoulder_y + 130 * s,
                     rng=rng, jitter=0.6)
        # Strap diagonal across torso
        _wobble_line(draw,
                     (cx + 22 * s, shoulder_y + 2),
                     (bx, shoulder_y + 60 * s),
                     rng=rng, jitter=0.6, width=STROKE - 1)


# ---- Mouth -----------------------------------------------------------

def _draw_mouth(draw, mx: float, my: float, *,
                talking: bool, mouth_cycle: int, s: float):
    if talking:
        cycle = mouth_cycle % 3
        if cycle == 0:
            draw.line((mx - 8 * s, my, mx + 8 * s, my), fill=INK, width=STROKE)
        elif cycle == 1:
            draw.ellipse((mx - 7 * s, my - 3, mx + 7 * s, my + 5),
                         outline=INK, width=STROKE)
        else:
            draw.ellipse((mx - 9 * s, my - 5, mx + 9 * s, my + 9),
                         outline=INK, width=STROKE)
    else:
        draw.line((mx - 7 * s, my, mx + 7 * s, my), fill=INK, width=STROKE)


# ---- Character figure -----------------------------------------------
#
# Returns a small dict of anchor points (head_cy, mouth, hands, …) so
# callers can attach speech-bubble tails or held props without having
# to recompute the geometry.

def _draw_figure(
    draw: ImageDraw.ImageDraw,
    cx: float, cy: float,
    *,
    rng: random.Random,
    name: Optional[str] = None,
    pose: str = "neutral",          # neutral | talking | gesture | holding | walking
    mouth_cycle: int = 0,
    facing: int = 1,                # +1 face right, -1 face left
    scale: float = 1.0,
    holding: Optional[str] = None,  # 'cup' | 'glass' | 'kettle' | None
    color: Tuple[int, int, int] = INK,
    mask: bool = True,
) -> Dict:
    """Hip is at (cx, cy). Figure ~ 300 px tall at scale=1.0.

    If `mask` is true, a paper-coloured rectangle is filled behind the
    figure first so background lines (shelves, walls, hills) don't run
    through the head and torso.
    """
    traits = traits_for(name)
    s = scale * traits["height"]
    bw = traits["build"]                   # body width multiplier
    st = _STYLE

    # Anchor lattice — proportions come from the active style.
    hip_y = cy
    shoulder_y = cy - st.shoulder_to_hip * s
    shoulder_dx = st.shoulder_dx * s * bw
    l_sh = (cx - shoulder_dx, shoulder_y)
    r_sh = (cx + shoulder_dx, shoulder_y)
    neck_top = (cx, shoulder_y - st.neck_len * s)
    head_r = st.head_r * s
    head_cy = neck_top[1] - head_r * st.head_attach
    hip_dx = st.hip_dx * s * bw
    l_hip = (cx - hip_dx, hip_y)
    r_hip = (cx + hip_dx, hip_y)

    if mask and st.body_mask:
        mask_w = head_r * 1.8
        draw.rectangle(
            (cx - mask_w, head_cy - head_r * 1.4,
             cx + mask_w, hip_y + 1),
            fill=BG,
        )

    # ---- Torso (sides only — clean stick-figure read) ----
    _wobble_line(draw, l_sh, l_hip, rng=rng, color=color)
    _wobble_line(draw, r_sh, r_hip, rng=rng, color=color)
    _wobble_line(draw, l_sh, r_sh, rng=rng, jitter=1.0, color=color)

    # ---- Neck ----
    _wobble_line(draw, (cx, shoulder_y), neck_top, rng=rng,
                 jitter=0.7, segments=4, color=color)

    # ---- Head ----
    if traits["head"] == "round":
        _wobble_circle(draw, cx, head_cy, head_r, rng=rng, color=color)
    elif traits["head"] == "oval":
        _wobble_ellipse(draw, cx, head_cy, head_r * 0.85, head_r * 1.05,
                        rng=rng, color=color)
    else:  # square
        _wobble_polyline(
            draw,
            [(cx - head_r * 0.9, head_cy - head_r * 0.95),
             (cx + head_r * 0.9, head_cy - head_r * 0.95),
             (cx + head_r * 0.95, head_cy + head_r * 0.7),
             (cx - head_r * 0.95, head_cy + head_r * 0.7),
             (cx - head_r * 0.9, head_cy - head_r * 0.95)],
            rng=rng, jitter=1.0, color=color,
        )

    # Hair on top
    if color == INK:  # don't draw hair on faded background figures
        _draw_hair(draw, cx, head_cy, head_r, traits["hair"], rng=rng)

    # ---- Face — eye style chosen by the active style ----
    eye_y = head_cy + st.eye_offset_y_factor * head_r
    eye_dx = st.eye_dx * s
    eye_shift = 2 * facing if pose != "talking" else 0
    if st.eye_style == "round_pupil":
        eye_r = st.eye_radius * s
        pupil_r = st.pupil_radius * s
        for ex in (-1, 1):
            ax = cx + ex * eye_dx + eye_shift
            draw.ellipse((ax - eye_r, eye_y - eye_r,
                          ax + eye_r, eye_y + eye_r),
                         fill=BG, outline=color, width=max(1, STROKE - 1))
            px = ax + 1.4 * facing
            py = eye_y + 0.6
            draw.ellipse((px - pupil_r, py - pupil_r,
                          px + pupil_r, py + pupil_r),
                         fill=color)
    else:  # "dot"
        d = st.eye_radius * s if st.eye_radius >= 2 else 2
        for ex in (-1, 1):
            ax = cx + ex * eye_dx + eye_shift
            draw.ellipse((ax - d, eye_y - d, ax + d, eye_y + d),
                         fill=color)
    if color == INK:
        _draw_eyebrows(draw, cx + eye_shift, head_cy, head_r, traits["brow"],
                       s=s, rng=rng)

    mouth_y = head_cy + head_r * 0.50
    _draw_mouth(draw, cx, mouth_y,
                talking=(pose == "talking"),
                mouth_cycle=mouth_cycle, s=s)

    # ---- Arms (shoulder -> elbow -> hand) ----
    arm_u = st.arm_upper * s
    arm_l = st.arm_lower * s
    if pose == "holding":
        # Both hands forward, level with chest.
        l_elbow = (l_sh[0] + 12 * s, l_sh[1] + arm_u * 0.7)
        l_hand  = (cx - 22 * s,      l_sh[1] + arm_u * 1.05)
        r_elbow = (r_sh[0] - 12 * s, r_sh[1] + arm_u * 0.7)
        r_hand  = (cx + 22 * s,      r_sh[1] + arm_u * 1.05)
    elif pose == "gesture":
        # Speaker-side hand raised in mid-gesture.
        if facing >= 0:
            l_elbow = (l_sh[0] - 16 * s, l_sh[1] + arm_u)
            l_hand  = (l_elbow[0] - 4 * s, l_elbow[1] + arm_l)
            r_elbow = (r_sh[0] + 28 * s, r_sh[1] + 2 * s)
            r_hand  = (r_elbow[0] + 18 * s, r_elbow[1] - 36 * s)
        else:
            r_elbow = (r_sh[0] + 16 * s, r_sh[1] + arm_u)
            r_hand  = (r_elbow[0] + 4 * s, r_elbow[1] + arm_l)
            l_elbow = (l_sh[0] - 28 * s, l_sh[1] + 2 * s)
            l_hand  = (l_elbow[0] - 18 * s, l_elbow[1] - 36 * s)
    elif pose == "walking":
        l_elbow = (l_sh[0] - 8 * s, l_sh[1] + arm_u)
        l_hand  = (l_elbow[0] + 6 * s, l_elbow[1] + arm_l)
        r_elbow = (r_sh[0] + 8 * s, r_sh[1] + arm_u)
        r_hand  = (r_elbow[0] - 6 * s, r_elbow[1] + arm_l)
    else:  # neutral / talking
        l_elbow = (l_sh[0] - 10 * s, l_sh[1] + arm_u)
        l_hand  = (l_elbow[0] - 4 * s, l_elbow[1] + arm_l)
        r_elbow = (r_sh[0] + 10 * s, r_sh[1] + arm_u)
        r_hand  = (r_elbow[0] + 4 * s, r_elbow[1] + arm_l)

    _wobble_line(draw, l_sh, l_elbow, rng=rng, color=color)
    _wobble_line(draw, l_elbow, l_hand, rng=rng, color=color)
    _wobble_line(draw, r_sh, r_elbow, rng=rng, color=color)
    _wobble_line(draw, r_elbow, r_hand, rng=rng, color=color)
    # Hands as small open circles
    _wobble_circle(draw, l_hand[0], l_hand[1], 5 * s, rng=rng,
                   jitter=0.5, segments=14, width=STROKE - 1, color=color)
    _wobble_circle(draw, r_hand[0], r_hand[1], 5 * s, rng=rng,
                   jitter=0.5, segments=14, width=STROKE - 1, color=color)

    # ---- Legs ----
    leg_u = st.leg_upper * s
    leg_l = st.leg_lower * s
    if pose == "walking":
        l_knee = (l_hip[0] - 6 * s, l_hip[1] + leg_u * 0.95)
        r_knee = (r_hip[0] + 12 * s, r_hip[1] + leg_u * 0.85)
        l_foot = (l_knee[0] - 14 * s, l_knee[1] + leg_l * 0.95)
        r_foot = (r_knee[0] + 4 * s, r_knee[1] + leg_l)
    else:
        l_knee = (l_hip[0] - 2 * s, l_hip[1] + leg_u)
        r_knee = (r_hip[0] + 2 * s, r_hip[1] + leg_u)
        l_foot = (l_knee[0] - 2 * s, l_knee[1] + leg_l)
        r_foot = (r_knee[0] + 2 * s, r_knee[1] + leg_l)
    _wobble_line(draw, l_hip, l_knee, rng=rng, color=color)
    _wobble_line(draw, l_knee, l_foot, rng=rng, color=color)
    _wobble_line(draw, r_hip, r_knee, rng=rng, color=color)
    _wobble_line(draw, r_knee, r_foot, rng=rng, color=color)
    # Feet (short horizontal ticks)
    foot_dir = facing if facing else 1
    _wobble_line(draw, l_foot,
                 (l_foot[0] + foot_dir * 12 * s, l_foot[1]),
                 rng=rng, jitter=0.6, segments=4, color=color)
    _wobble_line(draw, r_foot,
                 (r_foot[0] + foot_dir * 12 * s, r_foot[1]),
                 rng=rng, jitter=0.6, segments=4, color=color)
    # Ground-shadow hatching: 4-6 short diagonals under the feet.
    if color == INK and st.ground_shadow:
        sh_y = max(l_foot[1], r_foot[1]) + 6
        for k in range(5):
            x0 = cx + (-30 + k * 12) * s
            _wobble_line(draw, (x0, sh_y), (x0 + 8 * s, sh_y + 6),
                         rng=rng, jitter=0.5, segments=3,
                         width=max(1, STROKE - 2))

    # ---- Accessory (drawn on top of body) ----
    if color == INK:
        _draw_accessory(
            draw, accessory=traits["accessory"],
            cx=cx, shoulder_y=shoulder_y,
            head_cy=head_cy, head_r=head_r,
            hip_y=hip_y, scale=s, facing=facing, rng=rng,
        )

    # ---- Held object ----
    if holding and color == INK:
        # Draw between the two hands.
        ox = (l_hand[0] + r_hand[0]) / 2
        oy = (l_hand[1] + r_hand[1]) / 2
        _draw_prop(draw, ox, oy, holding, scale=s * 0.9, rng=rng)

    return {
        "head_cy": head_cy,
        "head_r":  head_r,
        "mouth":   (cx, mouth_y),
        "l_hand":  l_hand,
        "r_hand":  r_hand,
        "shoulder_y": shoulder_y,
        "hip_y":   hip_y,
        "name_y":  head_cy - head_r - 30 * s,
    }


# ---- Props ----------------------------------------------------------

def _draw_prop(draw, cx: float, cy: float, kind: str,
               *, scale: float = 1.0, rng: random.Random):
    s = scale
    if kind == "cup":
        # Tumbler with steam curls
        _wobble_polyline(
            draw,
            [(cx - 12 * s, cy - 14 * s), (cx + 12 * s, cy - 14 * s),
             (cx + 14 * s, cy + 16 * s), (cx - 14 * s, cy + 16 * s),
             (cx - 12 * s, cy - 14 * s)],
            rng=rng, jitter=0.8,
        )
        # Steam (two curls)
        for k in (-1, 1):
            _wobble_polyline(
                draw,
                [(cx + k * 5 * s, cy - 16 * s),
                 (cx + k * 9 * s, cy - 24 * s),
                 (cx + k * 4 * s, cy - 32 * s),
                 (cx + k * 9 * s, cy - 40 * s)],
                rng=rng, jitter=0.8, width=STROKE - 1,
            )
    elif kind == "glass":
        _wobble_polyline(
            draw,
            [(cx - 10 * s, cy - 16 * s), (cx + 10 * s, cy - 16 * s),
             (cx + 12 * s, cy + 16 * s), (cx - 12 * s, cy + 16 * s),
             (cx - 10 * s, cy - 16 * s)],
            rng=rng, jitter=0.6, width=STROKE - 1,
        )
    elif kind == "kettle":
        # Squat body + spout + handle
        _wobble_ellipse(draw, cx, cy, 22 * s, 16 * s, rng=rng, jitter=0.8)
        _wobble_polyline(
            draw,
            [(cx + 18 * s, cy - 8 * s),
             (cx + 32 * s, cy - 14 * s),
             (cx + 36 * s, cy - 6 * s)],
            rng=rng, jitter=0.6,
        )
        # Handle
        _wobble_polyline(
            draw,
            [(cx - 10 * s, cy - 14 * s),
             (cx,          cy - 26 * s),
             (cx + 10 * s, cy - 14 * s)],
            rng=rng, jitter=0.6,
        )
        # Steam
        for k in (-1, 0, 1):
            _wobble_polyline(
                draw,
                [(cx + k * 6 * s, cy - 18 * s),
                 (cx + k * 8 * s, cy - 30 * s),
                 (cx + k * 4 * s, cy - 42 * s)],
                rng=rng, jitter=0.7, width=STROKE - 1,
            )
    elif kind == "radio":
        _wobble_rect(draw, cx - 26 * s, cy - 14 * s,
                     cx + 26 * s, cy + 14 * s, rng=rng)
        _wobble_circle(draw, cx + 14 * s, cy, 6 * s,
                       rng=rng, jitter=0.4, segments=14, width=STROKE - 1)
        # Antenna
        _wobble_line(draw, (cx - 18 * s, cy - 14 * s),
                     (cx - 24 * s, cy - 40 * s),
                     rng=rng, jitter=0.6)
    elif kind == "phone":
        _wobble_rect(draw, cx - 8 * s, cy - 14 * s,
                     cx + 8 * s, cy + 14 * s, rng=rng, jitter=0.5)
    elif kind == "book":
        _wobble_rect(draw, cx - 18 * s, cy - 12 * s,
                     cx + 18 * s, cy + 12 * s, rng=rng)
        _wobble_line(draw, (cx, cy - 12 * s), (cx, cy + 12 * s),
                     rng=rng, jitter=0.5)
    elif kind == "bottle":
        _wobble_polyline(
            draw,
            [(cx - 6 * s, cy - 20 * s), (cx - 6 * s, cy - 10 * s),
             (cx - 10 * s, cy - 6 * s), (cx - 10 * s, cy + 16 * s),
             (cx + 10 * s, cy + 16 * s), (cx + 10 * s, cy - 6 * s),
             (cx + 6 * s, cy - 10 * s), (cx + 6 * s, cy - 20 * s),
             (cx - 6 * s, cy - 20 * s)],
            rng=rng, jitter=0.6,
        )


# ---- Backgrounds (location-aware) -----------------------------------

def _location_template(heading: str, location: str) -> str:
    """Coarse template lookup based on slug suffix words.

    EXT slugs are matched against outdoor templates FIRST so that
    "EXT. STREET OUTSIDE STALL" picks "street", not "stall".
    """
    upper = heading.upper()
    if location in ("EXT", "INT/EXT"):
        if "STREET" in upper or "ROAD" in upper or "ALLEY" in upper:
            return "street"
        if "PARK" in upper or "FIELD" in upper or "BEACH" in upper \
                or "GARDEN" in upper:
            return "outdoor"
        if location == "INT/EXT":
            return "doorway"
        return "outdoor"
    # Interior templates
    if any(k in upper for k in ("TEA STALL", "CHAI STALL", "STALL", "DHABA",
                                 "CAFE", "CAFÉ", "COFFEE")):
        return "stall"
    if "BEDROOM" in upper or "ROOM" in upper or "APARTMENT" in upper:
        return "room"
    if "OFFICE" in upper or "BOARDROOM" in upper or "MEETING" in upper:
        return "office"
    if "KITCHEN" in upper:
        return "kitchen"
    return "interior"


def _draw_floor(draw, *, rng: random.Random, y: int):
    W, _ = CANVAS
    _wobble_line(draw, (40, y), (W - 40, y),
                 rng=rng, jitter=2.0, segments=24)


def _draw_stall_bg(draw, *, rng: random.Random):
    """Tea stall back-wall: shelves with bottles, awning. Counter is
    drawn separately as foreground in `_draw_stall_fg`."""
    W, H = CANVAS
    floor_y = H - 140
    # Back wall horizon
    _wobble_line(draw, (40, floor_y - 320), (W - 40, floor_y - 320),
                 rng=rng, jitter=1.6, segments=24)
    # Shelf #1 with bottles
    sh_y = floor_y - 240
    _wobble_line(draw, (60, sh_y), (520, sh_y), rng=rng, jitter=1.0)
    for k, x in enumerate(range(80, 500, 60)):
        _draw_prop(draw, x, sh_y - 16, "bottle",
                   scale=0.7 + (k % 2) * 0.1, rng=rng)
    # Shelf #2
    sh2_y = floor_y - 180
    _wobble_line(draw, (60, sh2_y), (520, sh2_y), rng=rng, jitter=1.0)
    # Awning slats top-right
    for k in range(6):
        x = W - 480 + k * 70
        _wobble_line(draw, (x, 90), (x + 50, 130),
                     rng=rng, jitter=0.6, segments=4, width=STROKE - 1)
    _wobble_line(draw, (W - 500, 130), (W - 60, 130),
                 rng=rng, jitter=1.0, segments=18)
    _draw_floor(draw, rng=rng, y=floor_y)


def _draw_stall_fg(draw, *, rng: random.Random):
    """Counter ledge in foreground — masks the lower legs of figures
    so they read as standing behind / leaning on it."""
    W, H = CANVAS
    floor_y = H - 140
    # Solid fill so figure legs behind it are hidden.
    counter_top = floor_y - 70
    draw.rectangle((40, counter_top, W - 40, floor_y), fill=BG)
    _wobble_line(draw, (40, counter_top), (W - 40, counter_top),
                 rng=rng, jitter=1.0)
    _wobble_line(draw, (40, counter_top), (40, floor_y),
                 rng=rng, jitter=0.6, segments=4)
    _wobble_line(draw, (W - 40, counter_top), (W - 40, floor_y),
                 rng=rng, jitter=0.6, segments=4)
    _wobble_line(draw, (40, floor_y), (W - 40, floor_y),
                 rng=rng, jitter=0.8, segments=18)


def _draw_street_bg(draw, *, rng: random.Random):
    W, H = CANVAS
    floor_y = H - 140
    # Two building silhouettes left & right
    for left in (True, False):
        if left:
            x0, x1 = 40, 360
        else:
            x0, x1 = W - 360, W - 40
        roof_y = floor_y - 360
        _wobble_polyline(
            draw,
            [(x0, floor_y), (x0, roof_y),
             (x1, roof_y), (x1, floor_y)],
            rng=rng, jitter=1.4,
        )
        # Windows grid
        for r in range(3):
            for c in range(3):
                wx = x0 + 30 + c * 90
                wy = roof_y + 30 + r * 90
                _wobble_rect(draw, wx, wy, wx + 60, wy + 60,
                             rng=rng, jitter=0.8, width=STROKE - 1)
    # Road dashes
    _draw_floor(draw, rng=rng, y=floor_y)
    for x in range(120, W - 120, 140):
        _wobble_line(draw, (x, floor_y + 40), (x + 60, floor_y + 40),
                     rng=rng, jitter=0.8, segments=4)


def _draw_outdoor_bg(draw, *, rng: random.Random):
    W, H = CANVAS
    floor_y = H - 140
    # Soft hills with several control points
    pts = []
    n = 14
    base_y = floor_y - 80
    for k in range(n + 1):
        x = 40 + (W - 80) * k / n
        amp = 50 if k % 3 else 90
        y = base_y - amp * 0.35 - rng.uniform(-12, 12)
        pts.append((x, y))
    _wobble_polyline(draw, pts, rng=rng, jitter=1.6)
    # Sun
    _wobble_circle(draw, W - 200, 160, 60, rng=rng, jitter=1.4)
    # Light cloud
    _wobble_polyline(
        draw,
        [(220, 140), (270, 110), (340, 110), (390, 140), (320, 150), (220, 140)],
        rng=rng, jitter=1.2, width=STROKE - 1,
    )
    _draw_floor(draw, rng=rng, y=floor_y)


def _draw_doorway_bg(draw, *, rng: random.Random):
    W, H = CANVAS
    floor_y = H - 140
    # Rear wall
    _wobble_line(draw, (40, floor_y - 280), (W - 40, floor_y - 280),
                 rng=rng, jitter=1.2)
    # Door frame on right
    dx = W - 360
    _wobble_polyline(
        draw,
        [(dx, floor_y), (dx, 200), (dx + 200, 200), (dx + 200, floor_y)],
        rng=rng,
    )
    # Outdoor hint through door
    _wobble_polyline(
        draw,
        [(dx + 12, floor_y - 80), (dx + 100, floor_y - 110),
         (dx + 188, floor_y - 80)],
        rng=rng, jitter=1.0, width=STROKE - 1,
    )
    _draw_floor(draw, rng=rng, y=floor_y)


def _draw_room_bg(draw, *, rng: random.Random):
    W, H = CANVAS
    floor_y = H - 140
    # Window centre-back
    wx = W // 2 - 110
    _wobble_rect(draw, wx, 130, wx + 220, 320, rng=rng)
    _wobble_line(draw, (wx, 225), (wx + 220, 225), rng=rng, jitter=0.8)
    _wobble_line(draw, (wx + 110, 130), (wx + 110, 320), rng=rng, jitter=0.8)
    # Floor
    _draw_floor(draw, rng=rng, y=floor_y)


def _draw_office_bg(draw, *, rng: random.Random):
    W, H = CANVAS
    floor_y = H - 140
    # Long desk in foreground
    _wobble_rect(draw, 80, floor_y - 70, W - 80, floor_y - 30,
                 rng=rng, jitter=1.0)
    # Whiteboard back-left
    _wobble_rect(draw, 140, 130, 540, 320, rng=rng)
    # Hanging light
    _wobble_line(draw, (W // 2, 0), (W // 2, 110), rng=rng,
                 jitter=0.5, segments=4, width=STROKE - 1)
    _wobble_circle(draw, W // 2, 130, 22, rng=rng, jitter=0.6)
    _draw_floor(draw, rng=rng, y=floor_y)


def _draw_kitchen_bg(draw, *, rng: random.Random):
    W, H = CANVAS
    floor_y = H - 140
    # Cabinets
    _wobble_rect(draw, 60, 150, 480, 270, rng=rng)
    for k in range(4):
        x = 60 + k * 105
        _wobble_line(draw, (x, 150), (x, 270), rng=rng, jitter=0.8)
    # Counter strip
    _wobble_line(draw, (40, floor_y - 80), (W - 40, floor_y - 80),
                 rng=rng, jitter=1.0)
    _draw_floor(draw, rng=rng, y=floor_y)


def _draw_interior_bg(draw, *, rng: random.Random):
    """Generic interior — two windows + floor (the original look)."""
    W, H = CANVAS
    floor_y = H - 140
    for wx in (180, W - 360):
        _wobble_polyline(
            draw,
            [(wx, 140), (wx + 180, 140), (wx + 180, 320),
             (wx, 320), (wx, 140)],
            rng=rng,
        )
        _wobble_line(draw, (wx, 230), (wx + 180, 230), rng=rng, jitter=1.0)
        _wobble_line(draw, (wx + 90, 140), (wx + 90, 320), rng=rng, jitter=1.0)
    _draw_floor(draw, rng=rng, y=floor_y)


def _noop(draw, *, rng: random.Random):
    return


# Each entry: (back-pass, fore-pass). The back pass draws under figures;
# the fore pass draws on top so things like a counter occlude legs.
_BG_DISPATCH = {
    "stall":    (_draw_stall_bg, _draw_stall_fg),
    "street":   (_draw_street_bg, _noop),
    "outdoor":  (_draw_outdoor_bg, _noop),
    "doorway":  (_draw_doorway_bg, _noop),
    "room":     (_draw_room_bg, _noop),
    "office":   (_draw_office_bg, _noop),
    "kitchen":  (_draw_kitchen_bg, _noop),
    "interior": (_draw_interior_bg, _noop),
}


def _draw_background(draw, heading: str, location: str, *, rng: random.Random):
    template = _location_template(heading, location)
    _BG_DISPATCH[template][0](draw, rng=rng)


def _draw_foreground(draw, heading: str, location: str, *, rng: random.Random):
    template = _location_template(heading, location)
    _BG_DISPATCH[template][1](draw, rng=rng)


# ---- Speech bubble + caption ---------------------------------------

def _wrap(text: str, font: ImageFont.FreeTypeFont, max_w: int) -> List[str]:
    words = text.split()
    lines: List[str] = []
    cur = ""
    for w in words:
        trial = (cur + " " + w).strip()
        bbox = font.getbbox(trial)
        if bbox[2] - bbox[0] <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def _draw_bubble(
    draw: ImageDraw.ImageDraw,
    text: str,
    *,
    rng: random.Random,
    anchor: Tuple[int, int],     # speaker mouth/head
    side: str,                   # 'left' or 'right' — which side of frame
    font: ImageFont.FreeTypeFont,
    parenthetical: Optional[str] = None,
):
    W, H = CANVAS
    pad = 22
    max_text_w = 540
    lines = _wrap(text, font, max_text_w)

    line_h = font.getbbox("Hg")[3] - font.getbbox("Hg")[1] + 6
    text_h = line_h * len(lines)
    text_w = 0
    for ln in lines:
        b = font.getbbox(ln)
        text_w = max(text_w, b[2] - b[0])

    paren_h = 0
    paren_font = _font(22)
    if parenthetical:
        paren_lines = _wrap(parenthetical, paren_font, max_text_w)
        paren_h = (paren_font.getbbox("Hg")[3] - paren_font.getbbox("Hg")[1] + 4) \
                  * len(paren_lines)

    box_w = max(280, text_w + pad * 2)
    box_h = text_h + pad * 2 + (paren_h + 6 if paren_h else 0)
    if side == "left":
        box_x = 60
    else:
        box_x = W - box_w - 60
    box_y = SLUG_BAR_H + 70

    # Mask: fill paper colour slightly LARGER than the outline so any
    # background strokes (awning slats, shelf lines, hill ridges)
    # within `margin` px of the bubble get cleanly hidden.
    margin = _STYLE.bubble_margin
    draw.rounded_rectangle(
        (box_x - margin, box_y - margin,
         box_x + box_w + margin, box_y + box_h + margin),
        radius=28, fill=BG, outline=None,
    )
    r = 22
    pts = [
        (box_x + r, box_y),
        (box_x + box_w - r, box_y),
        (box_x + box_w, box_y + r),
        (box_x + box_w, box_y + box_h - r),
        (box_x + box_w - r, box_y + box_h),
        (box_x + r, box_y + box_h),
        (box_x, box_y + box_h - r),
        (box_x, box_y + r),
        (box_x + r, box_y),
    ]
    _wobble_polyline(draw, pts, rng=rng, jitter=1.2, width=STROKE)

    # Tail at the bubble's bottom edge nearest the speaker. Speaker is
    # below the bubble on the SAME side as the bubble, so the tail
    # base sits on the inside half of the bubble's bottom edge.
    if side == "left":
        tail_base_x = box_x + 50           # left bubble, speaker below-left
    else:
        tail_base_x = box_x + box_w - 80   # right bubble, speaker below-right
    tail_w = 28
    base_cx = tail_base_x + tail_w / 2
    base_cy = box_y + box_h
    dx = anchor[0] - base_cx
    dy = anchor[1] - base_cy
    norm = max(1.0, (dx * dx + dy * dy) ** 0.5)
    tail_len = 70
    tip = (base_cx + dx / norm * tail_len, base_cy + dy / norm * tail_len)
    poly = [(tail_base_x, base_cy - 1),
            (tail_base_x + tail_w, base_cy - 1), tip]
    draw.polygon(poly, fill=BG)
    _wobble_polyline(draw, [poly[0], poly[2]], rng=rng, jitter=1.0, width=STROKE)
    _wobble_polyline(draw, [poly[1], poly[2]], rng=rng, jitter=1.0, width=STROKE)

    # Text
    cy = box_y + pad
    if parenthetical:
        for pl in _wrap(parenthetical, paren_font, max_text_w):
            draw.text((box_x + pad, cy), f"({pl})", fill=INK, font=paren_font)
            cy += paren_font.getbbox("Hg")[3] - paren_font.getbbox("Hg")[1] + 4
        cy += 4
    for ln in lines:
        draw.text((box_x + pad, cy), ln, fill=INK, font=font)
        cy += line_h


def _draw_caption(
    draw: ImageDraw.ImageDraw, text: str, *, rng: random.Random,
    speaker: Optional[str] = None,
):
    W, H = CANVAS
    f = _font(28)
    name_f = _font(24, bold=True)
    pad = 28
    max_w = W - pad * 4
    lines = _wrap(text, f, max_w)
    name_h = 0
    if speaker:
        name_h = name_f.getbbox("Hg")[3] - name_f.getbbox("Hg")[1] + 6
    line_h = f.getbbox("Hg")[3] - f.getbbox("Hg")[1] + 6
    box_h = pad * 2 + line_h * len(lines) + name_h
    box_y = H - box_h - 24
    box_x = pad
    draw.rounded_rectangle(
        (box_x, box_y, W - pad, box_y + box_h),
        radius=18, fill=BG, outline=None,
    )
    pts = [
        (box_x + 18, box_y),
        (W - pad - 18, box_y),
        (W - pad, box_y + 18),
        (W - pad, box_y + box_h - 18),
        (W - pad - 18, box_y + box_h),
        (box_x + 18, box_y + box_h),
        (box_x, box_y + box_h - 18),
        (box_x, box_y + 18),
        (box_x + 18, box_y),
    ]
    _wobble_polyline(draw, pts, rng=rng, jitter=1.2, width=STROKE)
    cy = box_y + pad
    if speaker:
        draw.text((box_x + pad, cy), speaker.upper(), fill=INK, font=name_f)
        cy += name_h
    for ln in lines:
        draw.text((box_x + pad, cy), ln, fill=INK, font=f)
        cy += line_h


def _draw_slug_bar(draw: ImageDraw.ImageDraw, heading: str):
    W, _ = CANVAS
    draw.rectangle((0, 0, W, SLUG_BAR_H), fill=SLUG_BG)
    f = _font(26, bold=True)
    draw.text((28, 14), heading.upper(), fill=SLUG_FG, font=f)


def draw_slug_overlay(img: Image.Image, heading: str) -> Image.Image:
    """Stamp the slug bar back onto a (possibly jittered) frame.

    Used by the stitcher so the top bar stays rock-steady while the
    drawing layer shakes underneath.
    """
    draw = ImageDraw.Draw(img)
    _draw_slug_bar(draw, heading)
    return img


# ---- Staging --------------------------------------------------------

def _side_for(name: str, roster: List[str]) -> str:
    """Stable left/right side per character based on roster index.

    First-introduced character sits on the LEFT. Roster order comes
    from shotlist (introduction in cue or action prose). Characters
    not in the roster default to the right.
    """
    if not name or name not in roster:
        return "right"
    return "left" if roster.index(name) % 2 == 0 else "right"


def _holding_for(props: List[str], character: Optional[str],
                 roster: List[str]) -> Optional[str]:
    """Pick a held object for this character based on detected props.

    Vendor (first roster member) tends to hold the kettle/glass when
    those are present; customer (second) tends to hold the cup.
    """
    if not character or character not in roster:
        return None
    is_vendor = roster.index(character) == 0
    if is_vendor:
        for k in ("kettle", "glass"):
            if k in props:
                return k
    else:
        for k in ("cup", "glass"):
            if k in props:
                return k
    return None


def _scene_props_to_set_dressing(
    draw, props: List[str], *, rng: random.Random,
):
    """Place narrative props that aren't held by anyone into the set.

    Currently used on action shots where no character mention pulled
    them into a hand. The radio gets perched on the left counter-edge,
    the kettle on the right.
    """
    W, H = CANVAS
    floor_y = H - 140
    counter_y = floor_y - 60
    if "radio" in props:
        _draw_prop(draw, 130, counter_y - 18, "radio", scale=0.9, rng=rng)
    if "kettle" in props:
        _draw_prop(draw, W - 200, counter_y - 18, "kettle", scale=1.0, rng=rng)
    if "phone" in props:
        _draw_prop(draw, W // 2, counter_y - 16, "phone", scale=1.0, rng=rng)


# ---- Public render --------------------------------------------------

def render_pose(shot: Shot, pose_index: int, *, seed_salt: int = 0) -> Image.Image:
    """Render one pose of one shot. Returns a fresh PIL Image (1280x720).

    Determinism: the same (shot_id, pose_index, seed_salt) produces the
    same wobble pattern.
    """
    img = Image.new("RGB", CANVAS, BG)
    draw = ImageDraw.Draw(img)
    rng = random.Random(
        _stable_hash(
            f"{shot.kind}|{shot.scene_index}|{shot.text[:32]}|"
            f"{pose_index}|{seed_salt}"
        )
    )

    W, H = CANVAS

    if shot.kind == "slug":
        # Centred title card. NO top slug bar — the card itself IS the
        # slug, drawing both is a duplicate.
        f = _font(72, bold=True)
        sub = _font(34)
        label = f"SCENE {shot.scene_index + 1}"
        bbox = f.getbbox(label)
        tw = bbox[2] - bbox[0]
        draw.text(((W - tw) / 2, H / 2 - 90), label, fill=INK, font=f)
        bbox2 = sub.getbbox(shot.scene_heading.upper())
        tw2 = bbox2[2] - bbox2[0]
        draw.text(((W - tw2) / 2, H / 2), shot.scene_heading.upper(),
                  fill=INK, font=sub)
        _wobble_line(
            draw, ((W - tw2) / 2 - 20, H / 2 + 60),
            ((W - tw2) / 2 + tw2 + 20, H / 2 + 60),
            rng=rng, jitter=2.0, segments=24,
        )
        return img

    if shot.kind == "transition":
        _draw_slug_bar(draw, shot.scene_heading)
        f = _font(96, bold=True)
        bbox = f.getbbox(shot.text.upper())
        tw = bbox[2] - bbox[0]
        draw.text(((W - tw) / 2, H / 2 - 60), shot.text.upper(),
                  fill=INK, font=f)
        return img

    # Action and dialogue both get slug bar + location backdrop.
    _draw_slug_bar(draw, shot.scene_heading)
    _draw_background(draw, shot.scene_heading, shot.location, rng=rng)

    floor_y = H - 140
    # Hip sits leg_total above the floor so the feet land on it.
    figure_cy = floor_y - (_STYLE.leg_upper + _STYLE.leg_lower) - 2
    left_cx, right_cx = 360, 920

    if shot.kind == "action":
        # Stage everyone present, plus undressed props.
        present = list(shot.mentioned)
        # If nobody is mentioned but the scene already has roster members,
        # don't pull them in — let the shot be the location alone.
        for i, name in enumerate(present[:2]):
            side = _side_for(name, shot.roster)
            cx = left_cx if side == "left" else right_cx
            facing = 1 if side == "left" else -1
            holding = _holding_for(shot.props, name, shot.roster)
            pose = "holding" if holding else "neutral"
            # "walks off" / "approaches" -> walking pose
            txt_low = shot.text.lower()
            if any(w in txt_low for w in ("walks", "walked", "walking",
                                           "approaches", "rushes")):
                pose = "walking"
            _draw_figure(
                draw, cx, figure_cy,
                rng=rng, name=name, pose=pose,
                facing=facing, scale=1.0, holding=holding,
            )
            # Name plate just above the head.
            f = _font(24, bold=True)
            label = name.upper()
            bbox = f.getbbox(label)
            nw = bbox[2] - bbox[0]
            draw.text((cx - nw / 2, figure_cy - _STYLE.name_plate_offset),
                      label, fill=INK, font=f)
        # Foreground (counter etc.) before set-dressing so on-counter
        # props sit ON TOP of the counter, not behind it.
        _draw_foreground(draw, shot.scene_heading, shot.location, rng=rng)
        held = {h for n in present
                for h in [_holding_for(shot.props, n, shot.roster)] if h}
        residual_props = [p for p in shot.props if p not in held]
        _scene_props_to_set_dressing(draw, residual_props, rng=rng)
        _draw_caption(draw, shot.text, rng=rng)
        return img

    if shot.kind == "dialogue":
        speaker = shot.character
        roster = shot.roster
        # Place speaker on their side, listener (if any) opposite.
        listener = None
        for n in roster:
            if n != speaker:
                listener = n
                break

        speaker_side = _side_for(speaker, roster) if speaker else "left"
        speaker_cx = left_cx if speaker_side == "left" else right_cx
        speaker_facing = 1 if speaker_side == "left" else -1

        listener_cx = None
        if listener:
            listener_cx = right_cx if speaker_side == "left" else left_cx
            listener_facing = -1 if speaker_side == "left" else 1
            # Faded listener first so speaker overlays cleanly.
            _draw_figure(
                draw, listener_cx, figure_cy,
                rng=rng, name=listener, pose="neutral",
                facing=listener_facing, scale=0.95,
                color=INK_FAINT,
            )

        # Speaker — alternate talking / gesture poses with mouth cycle.
        speaker_pose = "gesture" if pose_index % 3 == 2 else "talking"
        speaker_holding = _holding_for(shot.props, speaker, roster)
        if speaker_holding:
            speaker_pose = "holding"
        anchors = _draw_figure(
            draw, speaker_cx, figure_cy,
            rng=rng, name=speaker, pose=speaker_pose,
            mouth_cycle=pose_index, facing=speaker_facing,
            scale=1.0, holding=speaker_holding,
        )
        # Foreground (counter etc.) draws over figures.
        _draw_foreground(draw, shot.scene_heading, shot.location, rng=rng)
        # Speech bubble on the SAME side as the speaker so the tail
        # only has to drop a short distance to the mouth — comic
        # convention. A long cross-frame tail reads ambiguously.
        bubble_side = speaker_side
        _draw_bubble(
            draw, shot.text, rng=rng,
            anchor=anchors["mouth"], side=bubble_side,
            font=_font(28),
            parenthetical=shot.parenthetical,
        )
        # Name plates LAST so the bubble's mask can't paint over them.
        if listener and listener_cx is not None:
            f = _font(20, bold=True)
            label = listener.upper()
            bbox = f.getbbox(label)
            nw = bbox[2] - bbox[0]
            draw.text((listener_cx - nw / 2, figure_cy - _STYLE.name_plate_offset),
                      label, fill=INK_FAINT, font=f)
        if speaker:
            f = _font(28, bold=True)
            label = speaker.upper()
            bbox = f.getbbox(label)
            nw = bbox[2] - bbox[0]
            draw.text((speaker_cx - nw / 2, figure_cy - _STYLE.name_plate_offset),
                      label, fill=INK, font=f)
        return img

    return img


def jitter_frame(img: Image.Image, dx: int, dy: int) -> Image.Image:
    """Translate the image by (dx, dy) on the same canvas, filling the
    revealed strip with the paper colour. Used by the stitcher for the
    per-frame stop-motion shake."""
    out = Image.new("RGB", img.size, BG)
    out.paste(img, (dx, dy))
    return out
