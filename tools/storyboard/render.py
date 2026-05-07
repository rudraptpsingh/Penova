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

def _font(size: int, bold: bool = False, italic: bool = False
          ) -> ImageFont.FreeTypeFont:
    """Best-effort system font lookup. Italic and bold-italic variants
    fall back to roman if the OS doesn't have them."""
    if bold and italic:
        candidates = (
            "/usr/share/fonts/truetype/liberation/LiberationSans-BoldItalic.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-BoldOblique.ttf",
            "/System/Library/Fonts/Supplemental/Arial Bold Italic.ttf",
        )
    elif bold:
        candidates = (
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        )
    elif italic:
        candidates = (
            "/usr/share/fonts/truetype/liberation/LiberationSans-Italic.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf",
            "/System/Library/Fonts/Supplemental/Arial Italic.ttf",
        )
    else:
        candidates = (
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
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
_GENDERS: Dict[str, str] = {}   # name.upper() -> 'm' | 'f'


def seed_intros(intros: Dict[str, str]) -> None:
    """Provide script-derived character descriptors so traits_for can
    pick visual cues that match the writer's intent (backpack, apron…)
    instead of relying purely on the name hash."""
    global _INTROS
    _INTROS = {k.upper(): v for k, v in intros.items()}


def seed_genders(genders: Dict[str, str]) -> None:
    """Provide script-derived genders. Used to pick visual conventions
    everyone recognises — men get rectangular pants, women get the
    triangular-skirt restroom-sign silhouette and longer hair."""
    global _GENDERS
    _GENDERS = {k.upper(): (v.lower() if v else "") for k, v in genders.items()}


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


_MALE_HAIR   = ("short", "buzz", "bald", "cap", "side")
_FEMALE_HAIR = ("bun", "long", "side", "short")


def traits_for(name: Optional[str]) -> Dict:
    if not name:
        return {
            "head": "round", "hair": "short", "accessory": "none",
            "build": 1.0, "height": 1.0, "brow": "flat",
            "gender": "", "body_style": "pants",
        }
    h = _stable_hash(name.upper())
    gender = _GENDERS.get(name.upper(), "")

    # Gender-aware hair pool — picks from the conventional silhouettes
    # everyone recognises (short for men, bun/long for women) so the
    # figures read at first glance.
    if gender == "m":
        hair_pool = _MALE_HAIR
    elif gender == "f":
        hair_pool = _FEMALE_HAIR
    else:
        hair_pool = _HAIR_STYLES

    base = {
        "head":       _HEAD_SHAPES[h % len(_HEAD_SHAPES)],
        "hair":       hair_pool[(h >> 3) % len(hair_pool)],
        "accessory":  _ACCESSORIES[(h >> 6) % len(_ACCESSORIES)],
        "brow":       _EYEBROWS[(h >> 10) % len(_EYEBROWS)],
        "build":      0.92 + ((h >> 13) % 5) * 0.04,
        "height":     0.94 + ((h >> 17) % 5) * 0.03,
        "gender":     gender,
        # Restroom-sign convention: women get the triangular skirt
        # silhouette, men get straight pants. Universally legible.
        "body_style": "skirt" if gender == "f" else "pants",
    }
    desc = _INTROS.get(name.upper())
    if desc:
        base = _override_from_desc(base, desc)
        # Skirt/dress wording in the descriptor wins.
        if any(w in desc.lower() for w in ("dress", "skirt", "saree", "sari")):
            base["body_style"] = "skirt"
        if any(w in desc.lower() for w in ("trousers", "jeans", "pants", "kurta")):
            base["body_style"] = "pants"
    return base


# ---- Hair / accessories ---------------------------------------------

def _hair_silhouette(cx: float, head_cy: float, head_r: float,
                     style: str) -> Optional[List[Tuple[float, float]]]:
    """Closed polygon for the hair silhouette, suitable for solid fill
    OR for stroking. Returns None for bald."""
    if style == "bald":
        return None
    r = head_r
    if style == "short":
        return [
            (cx - r * 0.95, head_cy - r * 0.55),
            (cx - r * 0.95, head_cy - r * 0.95),
            (cx - r * 0.6,  head_cy - r * 1.10),
            (cx,            head_cy - r * 1.18),
            (cx + r * 0.6,  head_cy - r * 1.10),
            (cx + r * 0.95, head_cy - r * 0.95),
            (cx + r * 0.95, head_cy - r * 0.55),
            (cx + r * 0.55, head_cy - r * 0.62),
            (cx,            head_cy - r * 0.55),
            (cx - r * 0.55, head_cy - r * 0.62),
            (cx - r * 0.95, head_cy - r * 0.55),
        ]
    if style == "long":
        return [
            (cx - r * 1.05, head_cy + r * 1.4),
            (cx - r * 1.05, head_cy - r * 0.4),
            (cx - r * 0.95, head_cy - r * 1.15),
            (cx,            head_cy - r * 1.22),
            (cx + r * 0.95, head_cy - r * 1.15),
            (cx + r * 1.05, head_cy - r * 0.4),
            (cx + r * 1.05, head_cy + r * 1.4),
            (cx + r * 0.7,  head_cy + r * 1.4),
            (cx + r * 0.6,  head_cy - r * 0.2),
            (cx,            head_cy - r * 0.55),
            (cx - r * 0.6,  head_cy - r * 0.2),
            (cx - r * 0.7,  head_cy + r * 1.4),
            (cx - r * 1.05, head_cy + r * 1.4),
        ]
    if style == "bun":
        return [
            (cx - r * 0.9, head_cy - r * 0.55),
            (cx - r * 0.9, head_cy - r * 0.95),
            (cx,           head_cy - r * 1.05),
            (cx + r * 0.9, head_cy - r * 0.95),
            (cx + r * 0.9, head_cy - r * 0.55),
            (cx + r * 0.5, head_cy - r * 0.6),
            (cx,           head_cy - r * 0.55),
            (cx - r * 0.5, head_cy - r * 0.6),
            (cx - r * 0.9, head_cy - r * 0.55),
        ]
    if style == "cap":
        return [
            (cx - r * 1.0,  head_cy - r * 0.5),
            (cx - r * 0.95, head_cy - r * 1.05),
            (cx + r * 0.95, head_cy - r * 1.05),
            (cx + r * 1.0,  head_cy - r * 0.5),
            (cx + r * 1.5,  head_cy - r * 0.35),
            (cx + r * 1.5,  head_cy - r * 0.2),
            (cx + r * 0.4,  head_cy - r * 0.35),
            (cx + r * 0.0,  head_cy - r * 0.50),
            (cx - r * 1.0,  head_cy - r * 0.5),
        ]
    if style == "side":
        return [
            (cx - r * 0.95, head_cy - r * 0.55),
            (cx - r * 0.5,  head_cy - r * 1.10),
            (cx + r * 0.7,  head_cy - r * 1.05),
            (cx + r * 0.4,  head_cy - r * 0.40),
            (cx + r * 0.2,  head_cy - r * 0.55),
            (cx - r * 0.2,  head_cy - r * 0.50),
            (cx - r * 0.95, head_cy - r * 0.55),
        ]
    return None


def _draw_hair(
    draw: ImageDraw.ImageDraw, cx: float, head_cy: float, head_r: float,
    style: str, *, rng: random.Random,
):
    if style == "bald":
        return
    # Spot-blacks: fill hair silhouette solid for the styles that have
    # one. Buzz/tuft are stipple/stroke-only and stay outline-driven.
    silhouette = _hair_silhouette(cx, head_cy, head_r, style)
    if silhouette and _STYLE.spot_blacks:
        # Solid fill, then wobble outline on top so the edge has
        # texture instead of looking laser-cut.
        draw.polygon(silhouette, fill=INK)
        _wobble_polyline(draw, silhouette, rng=rng, jitter=0.8,
                         width=_STYLE.stroke_key)
        return
    # Outline-only fallback, original lines:
    if style == "short":
        _wobble_polyline(
            draw,
            [(cx - head_r * 0.95, head_cy - head_r * 0.55),
             (cx - head_r * 0.6,  head_cy - head_r * 1.1),
             (cx,                 head_cy - head_r * 1.18),
             (cx + head_r * 0.6,  head_cy - head_r * 1.1),
             (cx + head_r * 0.95, head_cy - head_r * 0.55)],
            rng=rng, jitter=1.0, width=_STYLE.stroke_inner,
        )
    elif style == "buzz":
        # Dotted stipple along the scalp.
        for k in range(-4, 5):
            ax = cx + k * (head_r * 0.18)
            ay = head_cy - head_r * 0.92 + (abs(k) % 2) * 2
            draw.ellipse((ax - 2, ay - 2, ax + 2, ay + 2), fill=INK)
    elif style == "tuft":
        # Two upward tufts (no silhouette; stays line art).
        _wobble_polyline(
            draw,
            [(cx - head_r * 0.55, head_cy - head_r * 0.95),
             (cx - head_r * 0.3,  head_cy - head_r * 1.35),
             (cx - head_r * 0.05, head_cy - head_r * 0.95)],
            rng=rng, jitter=0.6, width=_STYLE.stroke_inner,
        )
        _wobble_polyline(
            draw,
            [(cx + head_r * 0.05, head_cy - head_r * 0.95),
             (cx + head_r * 0.3,  head_cy - head_r * 1.35),
             (cx + head_r * 0.55, head_cy - head_r * 0.95)],
            rng=rng, jitter=0.6, width=_STYLE.stroke_inner,
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
    facing: int, rng: random.Random, behind_body: bool = False,
):
    """Draws the visible part of an accessory.

    `behind_body=True` draws ONLY accessories that hang on the back
    (backpack, satchel) and skips the rest. `behind_body=False` does
    the opposite: skips back-worn items, draws everything that sits
    in front of the body (apron, scarf, glasses, headphones)."""
    s = scale
    if accessory == "none":
        return
    is_back_worn = accessory in ("backpack", "satchel")
    if behind_body and not is_back_worn:
        return
    if (not behind_body) and is_back_worn:
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
        pack = [
            (bx - bw / 2, shoulder_y + 6),
            (bx + bw / 2, shoulder_y + 6),
            (bx + bw / 2, shoulder_y + bh),
            (bx - bw / 2, shoulder_y + bh),
            (bx - bw / 2, shoulder_y + 6),
        ]
        if _STYLE.spot_blacks:
            draw.polygon(pack, fill=INK)
            _wobble_polyline(draw, pack, rng=rng, jitter=0.8,
                             width=_STYLE.stroke_key)
        else:
            _wobble_polyline(draw, pack, rng=rng, jitter=0.8,
                             width=_STYLE.stroke_key)
        # Strap (always thin)
        _wobble_polyline(
            draw,
            [(cx - 22 * s, shoulder_y + 4),
             (cx - 22 * s, shoulder_y + 50 * s),
             (bx - bw / 2 + 4, shoulder_y + 50 * s)],
            rng=rng, jitter=0.6, width=_STYLE.stroke_inner,
        )
    elif accessory == "apron":
        apron = [
            (cx - 30 * s, shoulder_y + 8),
            (cx + 30 * s, shoulder_y + 8),
            (cx + 38 * s, hip_y - 4),
            (cx - 38 * s, hip_y - 4),
            (cx - 30 * s, shoulder_y + 8),
        ]
        if _STYLE.spot_blacks:
            draw.polygon(apron, fill=INK)
            _wobble_polyline(draw, apron, rng=rng, jitter=0.8,
                             width=_STYLE.stroke_key)
        else:
            _wobble_polyline(draw, apron, rng=rng, jitter=0.8,
                             width=_STYLE.stroke_key)
        # Neck loop
        _wobble_polyline(
            draw,
            [(cx - 22 * s, shoulder_y + 8),
             (cx,          shoulder_y - 22 * s),
             (cx + 22 * s, shoulder_y + 8)],
            rng=rng, jitter=0.6, width=_STYLE.stroke_inner,
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


# ---- Expression-aware face ------------------------------------------
#
# Newspaper-comic faces vary mouth + eye + brow together to read an
# emotion at thumbnail size. These helpers map a small expression
# vocabulary (neutral, amused, sad, tired, surprised, intent,
# thoughtful, shouting, downcast) to concrete strokes.

def _draw_eyes(draw, cx, eye_y, eye_dx, *,
               expression: str, facing: int, s: float,
               color, inner_w: int, st):
    eye_r = st.eye_radius * s
    pupil_r = max(1.0, st.pupil_radius * s)

    for ex in (-1, 1):
        ax = cx + ex * eye_dx
        if st.eye_style != "round_pupil":
            d = max(2, st.eye_radius * s)
            if expression == "surprised":
                d *= 1.6
            draw.ellipse((ax - d, eye_y - d, ax + d, eye_y + d),
                         fill=color)
            continue

        # Round eye baseline
        r = eye_r
        if expression == "surprised":
            r = eye_r * 1.5
        elif expression == "tired" or expression == "thoughtful" \
                or expression == "downcast":
            r = eye_r  # full circle, but we'll mask with a half
        elif expression == "amused":
            r = eye_r * 0.95

        # Eye-white circle
        draw.ellipse((ax - r, eye_y - r, ax + r, eye_y + r),
                     fill=BG, outline=color, width=max(1, inner_w))

        # Half-mask the eye for tired/thoughtful/downcast.
        # Paint a BG rectangle over the upper half (or lower for sad).
        if expression in ("tired", "thoughtful"):
            # heavy upper lid -> half-closed
            draw.rectangle((ax - r - 1, eye_y - r - 1,
                            ax + r + 1, eye_y + 0),
                           fill=BG)
            # lid line
            draw.line((ax - r, eye_y, ax + r, eye_y),
                      fill=color, width=max(1, inner_w))
        elif expression == "downcast":
            draw.rectangle((ax - r - 1, eye_y - r - 1,
                            ax + r + 1, eye_y - r * 0.3),
                           fill=BG)
        elif expression == "amused":
            # Squint: cover the bottom half with BG so the eye becomes
            # a happy upward-curving slit.
            draw.rectangle((ax - r - 1, eye_y + 1,
                            ax + r + 1, eye_y + r + 2),
                           fill=BG)
            # curved lid line for the squint
            draw.arc((ax - r, eye_y - r, ax + r, eye_y + r),
                     start=180, end=360, fill=color,
                     width=max(1, inner_w))

        # Pupil — only when the eye is "open"
        if expression not in ("amused",):
            shift = 1.4 * facing
            ydy = 0.6
            if expression == "downcast":
                ydy = -r * 0.45
            elif expression == "thoughtful":
                shift = -1.4 * facing  # looking inward
            px = ax + shift
            py = eye_y + ydy
            # If lid covers, push pupil down to peek under
            if expression in ("tired", "thoughtful"):
                py = eye_y + r * 0.25
            draw.ellipse((px - pupil_r, py - pupil_r,
                          px + pupil_r, py + pupil_r),
                         fill=color)


def _draw_expression_brows(draw, cx, head_cy, head_r, expression: str,
                           default_brow: str, *, s: float,
                           rng: random.Random, inner_w: int):
    by = head_cy - head_r * 0.32
    bx = head_r * 0.42
    w = max(1, inner_w + 1)
    if expression == "amused":
        # Raised arches.
        for sgn in (-1, 1):
            x0 = cx + sgn * bx - 8
            x1 = cx + sgn * bx + 8
            draw.line((x0, by + 1, x1, by - 4), fill=INK, width=w)
    elif expression == "intent":
        # Furrowed: angled inward, slight V over the nose bridge.
        for sgn in (-1, 1):
            x0 = cx + sgn * bx - 8
            x1 = cx + sgn * bx + 8
            draw.line((x0, by - 3, x1, by + 4), fill=INK, width=w + 1)
    elif expression == "sad" or expression == "downcast":
        # Inner-up sad arch.
        for sgn in (-1, 1):
            x0 = cx + sgn * bx - 8
            x1 = cx + sgn * bx + 8
            draw.line((x0, by + 4, x1, by - 1), fill=INK, width=w)
    elif expression == "surprised":
        for sgn in (-1, 1):
            x0 = cx + sgn * bx - 9
            x1 = cx + sgn * bx + 9
            draw.line((x0, by - 4, x1, by - 4), fill=INK, width=w)
    elif expression == "shouting":
        for sgn in (-1, 1):
            x0 = cx + sgn * bx - 9
            x1 = cx + sgn * bx + 9
            draw.line((x0, by, x1, by + 5), fill=INK, width=w + 1)
    elif expression == "thoughtful" or expression == "tired":
        for sgn in (-1, 1):
            x0 = cx + sgn * bx - 8
            x1 = cx + sgn * bx + 8
            draw.line((x0, by + 2, x1, by + 4), fill=INK, width=w)
    else:
        _draw_eyebrows(draw, cx, head_cy, head_r, default_brow,
                       s=s, rng=rng)


def _draw_expression_mouth(draw, mx, my, expression: str, *,
                            talking: bool, mouth_cycle: int, s: float,
                            color, inner_w: int, rng: random.Random):
    w = max(1, inner_w + 1)
    if talking and expression not in ("amused", "shouting", "sad",
                                       "surprised"):
        cycle = mouth_cycle % 3
        if cycle == 0:
            draw.line((mx - 8 * s, my, mx + 8 * s, my),
                      fill=color, width=w)
        elif cycle == 1:
            draw.ellipse((mx - 7 * s, my - 3, mx + 7 * s, my + 5),
                         outline=color, width=w)
        else:
            draw.ellipse((mx - 9 * s, my - 5, mx + 9 * s, my + 9),
                         outline=color, width=w)
        return
    if expression == "amused":
        # Smile arc.
        draw.arc((mx - 12 * s, my - 4, mx + 12 * s, my + 12),
                 start=0, end=180, fill=color, width=w + 1)
    elif expression == "sad":
        draw.arc((mx - 12 * s, my, mx + 12 * s, my + 18),
                 start=180, end=360, fill=color, width=w + 1)
    elif expression == "surprised":
        # Open "o".
        draw.ellipse((mx - 6 * s, my - 5, mx + 6 * s, my + 8),
                     outline=color, width=w)
    elif expression == "shouting":
        # Big rectangular open mouth.
        pts = [(mx - 11 * s, my - 4), (mx + 11 * s, my - 4),
               (mx + 14 * s, my + 12), (mx - 14 * s, my + 12),
               (mx - 11 * s, my - 4)]
        draw.polygon(pts, fill=color)
    elif expression == "tired":
        # Slack flat line, slightly downturned at the corners.
        draw.line((mx - 10 * s, my + 1, mx + 10 * s, my + 1),
                  fill=color, width=w)
        draw.line((mx - 10 * s, my + 1, mx - 12 * s, my + 4),
                  fill=color, width=w)
        draw.line((mx + 10 * s, my + 1, mx + 12 * s, my + 4),
                  fill=color, width=w)
    elif expression == "intent":
        # Tight straight line.
        draw.line((mx - 9 * s, my, mx + 9 * s, my),
                  fill=color, width=w + 1)
    elif expression == "thoughtful":
        # Small pursed line, slightly off-center.
        draw.line((mx - 6 * s, my + 1, mx + 6 * s, my - 1),
                  fill=color, width=w)
    else:
        # Neutral straight closed mouth.
        draw.line((mx - 7 * s, my, mx + 7 * s, my),
                  fill=color, width=w)


# ---- Mitten hand ----------------------------------------------------

def _draw_mitten(
    draw: ImageDraw.ImageDraw,
    pos: Tuple[float, float],
    elbow: Tuple[float, float],
    *,
    side: int,                       # +1 thumb on outer side, -1 inner
    scale: float,
    rng: random.Random,
    color: Tuple[int, int, int] = INK,
):
    """Cartoon mitten: rounded palm + thumb tick. Hand is oriented along
    the forearm vector so it always reads as 'attached', regardless of
    arm angle."""
    s = scale
    hx, hy = pos
    ex, ey = elbow
    dx = hx - ex
    dy = hy - ey
    L = max(1.0, (dx * dx + dy * dy) ** 0.5)
    ax, ay = dx / L, dy / L           # arm forward direction
    nx, ny = -ay, ax                  # arm normal
    palm_r = 7 * s
    palm_cx = hx + ax * 2 * s
    palm_cy = hy + ay * 2 * s
    # Palm outline
    _wobble_circle(draw, palm_cx, palm_cy, palm_r, rng=rng,
                   jitter=0.6, segments=18,
                   width=_STYLE.stroke_inner,
                   color=color)
    # Thumb: a short stub on `side` of the palm
    th_base = (palm_cx + nx * side * palm_r * 0.6,
               palm_cy + ny * side * palm_r * 0.6)
    th_tip  = (palm_cx + nx * side * palm_r * 1.4 + ax * palm_r * 0.6,
               palm_cy + ny * side * palm_r * 1.4 + ay * palm_r * 0.6)
    _wobble_line(draw, th_base, th_tip, rng=rng, jitter=0.4,
                 segments=3, width=_STYLE.stroke_inner,
                 color=color)


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
    expression: str = "neutral",
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

    key_w = st.stroke_key
    inner_w = st.stroke_inner

    # ---- Torso (sides only — clean stick-figure read, keylines) ----
    _wobble_line(draw, l_sh, l_hip, rng=rng, color=color, width=key_w)
    _wobble_line(draw, r_sh, r_hip, rng=rng, color=color, width=key_w)
    _wobble_line(draw, l_sh, r_sh, rng=rng, jitter=1.0, color=color,
                 width=key_w)

    # Cross-hatch on the shadow side (opposite of facing) for body
    # form. Skip for faded listeners.
    if color == INK and st.cross_hatch:
        shade_x_l = cx + (-1 if facing >= 0 else 1) * shoulder_dx * 0.55
        shade_x_r = cx + (-1 if facing >= 0 else 1) * shoulder_dx * 0.95
        for k in range(4):
            t = (k + 1) / 6
            y = shoulder_y + (hip_y - shoulder_y) * t
            x0 = shade_x_l - 4 * s
            x1 = shade_x_r + 4 * s
            _wobble_line(draw, (min(x0, x1), y), (max(x0, x1), y),
                         rng=rng, jitter=0.5, segments=3,
                         width=max(1, inner_w - 1), color=color)

    # ---- Neck (keyline) ----
    _wobble_line(draw, (cx, shoulder_y), neck_top, rng=rng,
                 jitter=0.7, segments=4, color=color, width=key_w)

    # ---- Head (keyline) ----
    if traits["head"] == "round":
        _wobble_circle(draw, cx, head_cy, head_r, rng=rng, color=color,
                       width=key_w)
    elif traits["head"] == "oval":
        _wobble_ellipse(draw, cx, head_cy, head_r * 0.85, head_r * 1.05,
                        rng=rng, color=color, width=key_w)
    else:  # square
        _wobble_polyline(
            draw,
            [(cx - head_r * 0.9, head_cy - head_r * 0.95),
             (cx + head_r * 0.9, head_cy - head_r * 0.95),
             (cx + head_r * 0.95, head_cy + head_r * 0.7),
             (cx - head_r * 0.95, head_cy + head_r * 0.7),
             (cx - head_r * 0.9, head_cy - head_r * 0.95)],
            rng=rng, jitter=1.0, color=color, width=key_w,
        )

    # ---- Chin tick (subtle) ----
    if color == INK:
        chin_y = head_cy + head_r * 0.78
        chin_dx = head_r * 0.18
        _wobble_line(draw, (cx - chin_dx, chin_y),
                     (cx + chin_dx, chin_y + 1),
                     rng=rng, jitter=0.4, segments=3,
                     width=max(1, inner_w - 1))

    # Hair on top
    if color == INK:  # don't draw hair on faded background figures
        _draw_hair(draw, cx, head_cy, head_r, traits["hair"], rng=rng)

    # ---- Face — expression-aware eyes + brows + mouth ----
    eye_y = head_cy + st.eye_offset_y_factor * head_r
    eye_dx = st.eye_dx * s
    eye_shift = 2 * facing if pose != "talking" else 0
    _draw_eyes(draw, cx + eye_shift, eye_y, eye_dx,
               expression=expression, facing=facing, s=s, color=color,
               inner_w=inner_w, st=st)
    if color == INK:
        _draw_expression_brows(draw, cx + eye_shift, head_cy, head_r,
                               expression, traits["brow"], s=s,
                               rng=rng, inner_w=inner_w)

    # ---- Nose (small tick between eyes and mouth) ----
    if color == INK:
        nose_y_top = head_cy + head_r * 0.10
        nose_y_bot = head_cy + head_r * 0.30
        nose_x = cx + (4 if facing >= 0 else -4) * s
        _wobble_line(draw, (nose_x, nose_y_top),
                     (nose_x + (3 if facing >= 0 else -3) * s, nose_y_bot),
                     rng=rng, jitter=0.4, segments=3,
                     width=max(1, inner_w - 1))

    mouth_y = head_cy + head_r * 0.50
    _draw_expression_mouth(draw, cx, mouth_y, expression,
                            talking=(pose == "talking"),
                            mouth_cycle=mouth_cycle, s=s, color=color,
                            inner_w=inner_w, rng=rng)

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

    _wobble_line(draw, l_sh, l_elbow, rng=rng, color=color, width=key_w)
    _wobble_line(draw, l_elbow, l_hand, rng=rng, color=color, width=key_w)
    _wobble_line(draw, r_sh, r_elbow, rng=rng, color=color, width=key_w)
    _wobble_line(draw, r_elbow, r_hand, rng=rng, color=color, width=key_w)
    # Mitten hands: small palm shape with a thumb tick. Better than a
    # blank circle — reads as a hand even at thumbnail size.
    _draw_mitten(draw, l_hand, l_elbow, side=-1 * facing,
                 scale=s, rng=rng, color=color)
    _draw_mitten(draw, r_hand, r_elbow, side=+1 * facing,
                 scale=s, rng=rng, color=color)

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
    if traits.get("body_style") == "skirt":
        # Triangular skirt — the universally-readable feminine signifier.
        # Flares from hip line down to mid-thigh, then thinner legs
        # continue below to the feet. Solid-fill when spot_blacks.
        skirt_y = (hip_y + (l_knee[1] if pose != "walking" else l_knee[1]
                            )) / 2
        flare = 28 * s * bw
        skirt = [
            (l_hip[0] + 2 * s, hip_y - 2),
            (r_hip[0] - 2 * s, hip_y - 2),
            (cx + flare, skirt_y),
            (cx - flare, skirt_y),
            (l_hip[0] + 2 * s, hip_y - 2),
        ]
        if color == INK and st.spot_blacks:
            draw.polygon(skirt, fill=color)
            _wobble_polyline(draw, skirt, rng=rng, jitter=0.8,
                             width=key_w, color=color)
        else:
            _wobble_polyline(draw, skirt, rng=rng, jitter=0.8,
                             width=key_w, color=color)
        # Legs continue from skirt-bottom edges, not from hip.
        l_leg_top = (cx - flare * 0.35, skirt_y)
        r_leg_top = (cx + flare * 0.35, skirt_y)
        _wobble_line(draw, l_leg_top, l_knee, rng=rng,
                     color=color, width=key_w)
        _wobble_line(draw, r_leg_top, r_knee, rng=rng,
                     color=color, width=key_w)
    else:
        _wobble_line(draw, l_hip, l_knee, rng=rng, color=color, width=key_w)
        _wobble_line(draw, r_hip, r_knee, rng=rng, color=color, width=key_w)
    _wobble_line(draw, l_knee, l_foot, rng=rng, color=color, width=key_w)
    _wobble_line(draw, r_knee, r_foot, rng=rng, color=color, width=key_w)
    # Feet — solid filled "shoe" silhouettes when spot_blacks is on,
    # otherwise short ticks like the classic style.
    foot_dir = facing if facing else 1
    if color == INK and st.spot_blacks:
        for fx, fy in (l_foot, r_foot):
            shoe = [
                (fx - 4 * s,                 fy - 3 * s),
                (fx + foot_dir * 14 * s,     fy - 4 * s),
                (fx + foot_dir * 16 * s,     fy + 1),
                (fx - 4 * s,                 fy + 2),
                (fx - 4 * s,                 fy - 3 * s),
            ]
            draw.polygon(shoe, fill=color)
    else:
        _wobble_line(draw, l_foot,
                     (l_foot[0] + foot_dir * 12 * s, l_foot[1]),
                     rng=rng, jitter=0.6, segments=4, color=color,
                     width=key_w)
        _wobble_line(draw, r_foot,
                     (r_foot[0] + foot_dir * 12 * s, r_foot[1]),
                     rng=rng, jitter=0.6, segments=4, color=color,
                     width=key_w)
    # Motion lines for walking figures — short trails BEHIND the
    # direction of travel (opposite of facing).
    if color == INK and st.motion_lines and pose == "walking":
        trail_dir = -1 if facing >= 0 else 1
        for k in range(3):
            ty = shoulder_y + 24 * s + k * 22 * s
            x0 = cx + trail_dir * (shoulder_dx + 14) * s
            x1 = x0 + trail_dir * 32 * s
            _wobble_line(draw, (x0, ty), (x1, ty - 2 * s),
                         rng=rng, jitter=0.5, segments=4,
                         width=max(1, inner_w))

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


def _classify_bubble(text: str, parenthetical: Optional[str]) -> str:
    """Pick a bubble variant from text cues. Returns one of:
        'thought' — internal monologue (parenthetical "to herself",
                    "to no one", thinks/muses).
        'shout'   — text ending with one or more '!'.
        'speech'  — default rounded bubble.
    """
    t = text.strip()
    p = (parenthetical or "").lower()
    if any(k in p for k in (
        "to himself", "to herself", "to no one",
        "thinks", "thinking", "muses", "to themself",
        "internal", "inner",
    )):
        return "thought"
    if t.endswith("!") or "!!" in t:
        return "shout"
    return "speech"


def _bubble_cloud_pts(box_x, box_y, box_w, box_h, n_lobes=10):
    """Polygon for a cloud-style thought bubble. Lobes around the
    perimeter with small inward gaps so it reads as 'thought'."""
    pts: List[Tuple[float, float]] = []
    cx = box_x + box_w / 2
    cy = box_y + box_h / 2
    rx = box_w / 2 + 6
    ry = box_h / 2 + 6
    for k in range(n_lobes * 2 + 1):
        a = (k / (n_lobes * 2)) * math.tau
        # Alternate outward (lobe peak) and inward (lobe valley)
        out = (k % 2 == 0)
        r_mul = 1.05 if out else 0.92
        pts.append((cx + math.cos(a) * rx * r_mul,
                    cy + math.sin(a) * ry * r_mul))
    return pts


def _bubble_jagged_pts(box_x, box_y, box_w, box_h, n_spikes=18):
    """Star/zigzag polygon for a shout bubble."""
    pts: List[Tuple[float, float]] = []
    cx = box_x + box_w / 2
    cy = box_y + box_h / 2
    rx_o = box_w / 2 + 14
    ry_o = box_h / 2 + 14
    rx_i = box_w / 2 - 4
    ry_i = box_h / 2 - 4
    for k in range(n_spikes * 2 + 1):
        a = (k / (n_spikes * 2)) * math.tau - math.pi / 2
        outer = (k % 2 == 0)
        rx = rx_o if outer else max(box_w / 2 * 0.85, rx_i)
        ry = ry_o if outer else max(box_h / 2 * 0.85, ry_i)
        pts.append((cx + math.cos(a) * rx,
                    cy + math.sin(a) * ry))
    return pts


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

    bubble_type = _classify_bubble(text, parenthetical)

    # Mask: fill paper colour slightly LARGER than the outline so any
    # background strokes don't crowd the text. Cloud/jagged bubbles
    # need a wider mask because their outline pokes outside the box.
    margin = _STYLE.bubble_margin + (
        14 if bubble_type == "shout" else
        10 if bubble_type == "thought" else 0)
    draw.rounded_rectangle(
        (box_x - margin, box_y - margin,
         box_x + box_w + margin, box_y + box_h + margin),
        radius=28, fill=BG, outline=None,
    )

    if bubble_type == "thought":
        cloud = _bubble_cloud_pts(box_x, box_y, box_w, box_h)
        # Solid fill + outline so background can't bleed through lobes.
        draw.polygon(cloud, fill=BG)
        _wobble_polyline(draw, cloud, rng=rng, jitter=1.0,
                         width=_STYLE.stroke_inner)
    elif bubble_type == "shout":
        jag = _bubble_jagged_pts(box_x, box_y, box_w, box_h)
        draw.polygon(jag, fill=BG)
        _wobble_polyline(draw, jag, rng=rng, jitter=0.8,
                         width=_STYLE.stroke_key)
    else:
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

    # Tail at the bubble's bottom edge nearest the speaker.
    if side == "left":
        tail_base_x = box_x + 50
    else:
        tail_base_x = box_x + box_w - 80
    tail_w = 28
    base_cx = tail_base_x + tail_w / 2
    base_cy = box_y + box_h
    dx = anchor[0] - base_cx
    dy = anchor[1] - base_cy
    norm = max(1.0, (dx * dx + dy * dy) ** 0.5)

    if bubble_type == "thought":
        # Trail of three shrinking circles from bubble to speaker —
        # the universal "thought" tail.
        for k, frac in enumerate((0.30, 0.55, 0.85)):
            cx_dot = base_cx + dx * frac
            cy_dot = base_cy + dy * frac
            r_dot = max(3, 11 - k * 3)
            draw.ellipse((cx_dot - r_dot, cy_dot - r_dot,
                          cx_dot + r_dot, cy_dot + r_dot),
                         fill=BG, outline=INK,
                         width=max(1, _STYLE.stroke_inner))
    elif bubble_type == "shout":
        # A bold, slightly shorter triangle so it points sharply.
        tail_len = 60
        tip = (base_cx + dx / norm * tail_len,
               base_cy + dy / norm * tail_len)
        poly = [(tail_base_x - 4, base_cy - 1),
                (tail_base_x + tail_w + 4, base_cy - 1), tip]
        draw.polygon(poly, fill=BG)
        _wobble_polyline(draw, [poly[0], poly[2]], rng=rng, jitter=0.6,
                         width=_STYLE.stroke_key)
        _wobble_polyline(draw, [poly[1], poly[2]], rng=rng, jitter=0.6,
                         width=_STYLE.stroke_key)
    else:
        tail_len = 70
        tip = (base_cx + dx / norm * tail_len,
               base_cy + dy / norm * tail_len)
        poly = [(tail_base_x, base_cy - 1),
                (tail_base_x + tail_w, base_cy - 1), tip]
        draw.polygon(poly, fill=BG)
        _wobble_polyline(draw, [poly[0], poly[2]], rng=rng, jitter=1.0,
                         width=STROKE)
        _wobble_polyline(draw, [poly[1], poly[2]], rng=rng, jitter=1.0,
                         width=STROKE)

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
    # Italic action narration — distinguishes it from dialogue.
    f = _font(28, italic=True)
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
        present = list(shot.mentioned)
        is_beat = shot.framing == "beat" or shot.silent
        figure_scale = 1.15 if is_beat else 1.0
        for i, name in enumerate(present[:2]):
            side = _side_for(name, shot.roster)
            cx = left_cx if side == "left" else right_cx
            facing = 1 if side == "left" else -1
            holding = _holding_for(shot.props, name, shot.roster)
            pose = "holding" if holding else "neutral"
            txt_low = shot.text.lower()
            if any(w in txt_low for w in ("walks", "walked", "walking",
                                           "approaches", "rushes")):
                pose = "walking"
            # Center the subject for a beat panel with one character.
            if is_beat and len(present) == 1:
                cx = (left_cx + right_cx) / 2
                facing = 1
            _draw_figure(
                draw, cx, figure_cy,
                rng=rng, name=name, pose=pose,
                facing=facing, scale=figure_scale, holding=holding,
                expression=shot.expression,
            )
            f = _font(24, bold=True)
            label = name.upper()
            bbox = f.getbbox(label)
            nw = bbox[2] - bbox[0]
            draw.text((cx - nw / 2, figure_cy - _STYLE.name_plate_offset),
                      label, fill=INK, font=f)
        _draw_foreground(draw, shot.scene_heading, shot.location, rng=rng)
        held = {h for n in present
                for h in [_holding_for(shot.props, n, shot.roster)] if h}
        residual_props = [p for p in shot.props if p not in held]
        _scene_props_to_set_dressing(draw, residual_props, rng=rng)
        if is_beat:
            # Silent reaction beat — italic line tucked at lower-left,
            # no caption box. The image carries the moment.
            f = _font(20, italic=True)
            draw.text((40, H - 56), shot.text, fill=INK, font=f)
        else:
            _draw_caption(draw, shot.text, rng=rng)
        return img

    if shot.kind == "dialogue":
        speaker = shot.character
        roster = shot.roster
        listener = None
        for n in roster:
            if n != speaker:
                listener = n
                break

        speaker_side = _side_for(speaker, roster) if speaker else "left"
        speaker_cx = left_cx if speaker_side == "left" else right_cx
        speaker_facing = 1 if speaker_side == "left" else -1
        speaker_pose = "gesture" if pose_index % 3 == 2 else "talking"
        speaker_holding = _holding_for(shot.props, speaker, roster)
        if speaker_holding:
            speaker_pose = "holding"

        # ---- Close-up framing ----
        # For emotional / long dialogue: bring the speaker close to
        # camera so the face does the work. Listener becomes a faded
        # silhouette in the foreground (over-the-shoulder feel).
        if shot.framing == "close":
            close_cx = (left_cx + right_cx) / 2
            close_cy = figure_cy + 80
            close_scale = 1.55
            # Faded listener as a low foreground shoulder if present.
            if listener:
                ots_cx = (left_cx if speaker_side == "right" else right_cx)
                ots_cy = figure_cy + 220
                _draw_figure(
                    draw, ots_cx, ots_cy,
                    rng=rng, name=listener, pose="neutral",
                    facing=(-1 if speaker_side == "right" else 1),
                    scale=1.4, color=INK_FAINT,
                )
            anchors = _draw_figure(
                draw, close_cx, close_cy,
                rng=rng, name=speaker, pose=speaker_pose,
                mouth_cycle=pose_index, facing=speaker_facing,
                scale=close_scale, holding=speaker_holding,
                expression=shot.expression,
            )
            _draw_foreground(draw, shot.scene_heading, shot.location, rng=rng)
            bubble_side = speaker_side
            _draw_bubble(
                draw, shot.text, rng=rng,
                anchor=anchors["mouth"], side=bubble_side,
                font=_font(30),
                parenthetical=shot.parenthetical,
            )
            # No name plate in close-up; the figure size + bubble
            # already identify the speaker, and a label at this scale
            # would land on the face.
            return img

        # ---- Wide two-shot (default) ----
        listener_cx = None
        if listener:
            listener_cx = right_cx if speaker_side == "left" else left_cx
            listener_facing = -1 if speaker_side == "left" else 1
            _draw_figure(
                draw, listener_cx, figure_cy,
                rng=rng, name=listener, pose="neutral",
                facing=listener_facing, scale=0.95,
                color=INK_FAINT,
            )

        anchors = _draw_figure(
            draw, speaker_cx, figure_cy,
            rng=rng, name=speaker, pose=speaker_pose,
            mouth_cycle=pose_index, facing=speaker_facing,
            scale=1.0, holding=speaker_holding,
            expression=shot.expression,
        )
        _draw_foreground(draw, shot.scene_heading, shot.location, rng=rng)
        bubble_side = speaker_side
        _draw_bubble(
            draw, shot.text, rng=rng,
            anchor=anchors["mouth"], side=bubble_side,
            font=_font(28),
            parenthetical=shot.parenthetical,
        )
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
