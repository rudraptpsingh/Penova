"""Pillow renderer: shot -> PIL.Image, hand-drawn black-outline aesthetic.

Lines are drawn as polylines with small per-vertex jitter so the strokes
look like ink on paper rather than vector-perfect geometry. Each shot
exposes a small set of pose variants the stitcher cycles through; that
cycling, plus a separate per-frame ±2 px whole-figure jitter applied at
stitch time, is what produces the stop-motion judder.

Public surface:
    render_pose(shot, pose_index, size=(W, H)) -> PIL.Image.Image
"""
from __future__ import annotations
import math
import random
from typing import List, Tuple, Optional

from PIL import Image, ImageDraw, ImageFont

from shotlist import Shot

# ---- Layout ----
CANVAS = (1280, 720)
BG = (252, 248, 240)         # off-white "paper"
INK = (20, 20, 24)           # near-black ink
SLUG_BG = (20, 20, 24)
SLUG_FG = (252, 248, 240)
STROKE = 4

# Try to load a friendly font; fall back to PIL default if unavailable.
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


# ---- Wobbly-line primitive ----

def _wobble_line(
    draw: ImageDraw.ImageDraw,
    p1: Tuple[float, float],
    p2: Tuple[float, float],
    *,
    rng: random.Random,
    jitter: float = 1.6,
    segments: int = 8,
    width: int = STROKE,
):
    """Draw an ink-like wobbly line between p1 and p2."""
    pts: List[Tuple[float, float]] = [p1]
    for k in range(1, segments):
        t = k / segments
        x = p1[0] + (p2[0] - p1[0]) * t
        y = p1[1] + (p2[1] - p1[1]) * t
        x += rng.uniform(-jitter, jitter)
        y += rng.uniform(-jitter, jitter)
        pts.append((x, y))
    pts.append(p2)
    draw.line(pts, fill=INK, width=width, joint="curve")


def _wobble_circle(
    draw: ImageDraw.ImageDraw,
    cx: float, cy: float, r: float,
    *, rng: random.Random, jitter: float = 1.4, segments: int = 36,
    width: int = STROKE,
):
    pts: List[Tuple[float, float]] = []
    for k in range(segments + 1):
        a = (k / segments) * math.tau
        rr = r + rng.uniform(-jitter, jitter)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    draw.line(pts, fill=INK, width=width, joint="curve")


def _wobble_polyline(
    draw: ImageDraw.ImageDraw,
    pts: List[Tuple[float, float]],
    *, rng: random.Random, jitter: float = 1.4, width: int = STROKE,
):
    out: List[Tuple[float, float]] = []
    for x, y in pts:
        out.append((x + rng.uniform(-jitter, jitter),
                    y + rng.uniform(-jitter, jitter)))
    draw.line(out, fill=INK, width=width, joint="curve")


# ---- Character figure ----
# Stylized "outline person" anchored at hip (cx, cy). Each pose tweaks
# arm/leg/head angles. Mouth shape cycles for talking poses.

def _draw_figure(
    draw: ImageDraw.ImageDraw,
    cx: float, cy: float,
    *,
    rng: random.Random,
    pose: int = 0,
    talking: bool = False,
    mouth_cycle: int = 0,
    facing: int = 1,  # +1 right, -1 left
    scale: float = 1.0,
):
    """Hip is at (cx, cy). Figure ~ 280 px tall at scale=1.0."""
    s = scale
    head_r = 36 * s
    head_cx = cx
    head_cy = cy - 150 * s

    # Body
    shoulder = (cx, cy - 110 * s)
    hip = (cx, cy)
    _wobble_line(draw, shoulder, hip, rng=rng)

    # Head
    _wobble_circle(draw, head_cx, head_cy - head_r * 0.4, head_r, rng=rng)

    # Eyes (two short ticks)
    eye_y = head_cy - head_r * 0.55
    draw.ellipse(
        (head_cx - 14 * s - 2, eye_y - 2, head_cx - 14 * s + 2, eye_y + 2),
        fill=INK,
    )
    draw.ellipse(
        (head_cx + 14 * s - 2, eye_y - 2, head_cx + 14 * s + 2, eye_y + 2),
        fill=INK,
    )

    # Mouth
    mouth_y = head_cy - head_r * 0.18
    if talking:
        cycle = mouth_cycle % 3
        if cycle == 0:
            # closed
            draw.line(
                (head_cx - 8 * s, mouth_y, head_cx + 8 * s, mouth_y),
                fill=INK, width=STROKE,
            )
        elif cycle == 1:
            # half
            draw.ellipse(
                (head_cx - 7 * s, mouth_y - 3,
                 head_cx + 7 * s, mouth_y + 5),
                outline=INK, width=STROKE,
            )
        else:
            # wide
            draw.ellipse(
                (head_cx - 9 * s, mouth_y - 5,
                 head_cx + 9 * s, mouth_y + 9),
                outline=INK, width=STROKE,
            )
    else:
        # closed line
        draw.line(
            (head_cx - 7 * s, mouth_y, head_cx + 7 * s, mouth_y),
            fill=INK, width=STROKE,
        )

    # Arms — pose-dependent. Angles fan OUT from the body so the strokes
    # don't overlap the torso line. 0° = right, 90° = up.
    arm_len = 90 * s
    if pose == 0:
        # Relaxed, fanning slightly forward
        l_angle = math.radians(245)
        r_angle = math.radians(295)
    elif pose == 1:
        # One hand raised, gesturing
        l_angle = math.radians(240)
        r_angle = math.radians(335)
    else:
        # Both arms out, more open
        l_angle = math.radians(210)
        r_angle = math.radians(330)
    # left arm
    lend = (
        shoulder[0] + math.cos(l_angle) * arm_len,
        shoulder[1] - math.sin(l_angle) * arm_len,  # screen y inverted
    )
    rend = (
        shoulder[0] + math.cos(r_angle) * arm_len,
        shoulder[1] - math.sin(r_angle) * arm_len,
    )
    _wobble_line(draw, shoulder, lend, rng=rng)
    _wobble_line(draw, shoulder, rend, rng=rng)

    # Legs
    leg_len = 130 * s
    lleg_a = math.radians(265 if pose != 2 else 260)
    rleg_a = math.radians(275 if pose != 2 else 280)
    lle = (
        hip[0] + math.cos(lleg_a) * leg_len,
        hip[1] - math.sin(lleg_a) * leg_len,
    )
    rle = (
        hip[0] + math.cos(rleg_a) * leg_len,
        hip[1] - math.sin(rleg_a) * leg_len,
    )
    _wobble_line(draw, hip, lle, rng=rng)
    _wobble_line(draw, hip, rle, rng=rng)


# ---- Background hints ----

def _draw_background(
    draw: ImageDraw.ImageDraw, location: str, *, rng: random.Random
):
    W, H = CANVAS
    floor_y = H - 140

    # Floor / ground line
    _wobble_line(
        draw, (40, floor_y), (W - 40, floor_y),
        rng=rng, jitter=2.0, segments=24,
    )

    if location == "INT":
        # Two windows on the back wall
        for wx in (180, W - 360):
            _wobble_polyline(
                draw,
                [(wx, 140), (wx + 180, 140), (wx + 180, 320), (wx, 320), (wx, 140)],
                rng=rng,
            )
            _wobble_line(draw, (wx, 230), (wx + 180, 230), rng=rng, jitter=1.0)
            _wobble_line(draw, (wx + 90, 140), (wx + 90, 320), rng=rng, jitter=1.0)
    elif location == "EXT":
        # Horizon hill + sun
        _wobble_polyline(
            draw,
            [(60, floor_y - 80), (260, floor_y - 130), (520, floor_y - 90),
             (820, floor_y - 150), (1100, floor_y - 95), (W - 40, floor_y - 110)],
            rng=rng, jitter=2.4,
        )
        _wobble_circle(draw, W - 200, 160, 60, rng=rng, jitter=1.6)
    elif location == "INT/EXT":
        _wobble_polyline(
            draw,
            [(60, floor_y - 60), (W // 2, floor_y - 110), (W - 60, floor_y - 70)],
            rng=rng, jitter=2.0,
        )
        # A door / threshold rectangle
        dx = W - 360
        _wobble_polyline(
            draw,
            [(dx, 200), (dx + 200, 200), (dx + 200, floor_y),
             (dx, floor_y), (dx, 200)],
            rng=rng,
        )


# ---- Speech bubble ----

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
    anchor: Tuple[int, int],
    font: ImageFont.FreeTypeFont,
    parenthetical: Optional[str] = None,
):
    """Draw a hand-drawn speech bubble with `text`. The tail points to
    `anchor` (head/shoulder of speaker). Bubble lives in the upper-right
    quadrant of the frame.
    """
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
        paren_h = (paren_font.getbbox("Hg")[3] - paren_font.getbbox("Hg")[1] + 4) * len(paren_lines)

    box_w = max(280, text_w + pad * 2)
    box_h = text_h + pad * 2 + (paren_h + 6 if paren_h else 0)
    box_x = W - box_w - 60
    box_y = 100

    # Bubble outline (rounded rect, drawn as wobbly polyline)
    r = 22
    pts = []
    # Top edge
    pts.append((box_x + r, box_y))
    pts.append((box_x + box_w - r, box_y))
    # Right
    pts.append((box_x + box_w, box_y + r))
    pts.append((box_x + box_w, box_y + box_h - r))
    # Bottom
    pts.append((box_x + box_w - r, box_y + box_h))
    pts.append((box_x + r, box_y + box_h))
    # Left
    pts.append((box_x, box_y + box_h - r))
    pts.append((box_x, box_y + r))
    pts.append((box_x + r, box_y))

    # Fill bubble in solid bg first so wobble lines don't get clipped by background.
    draw.rounded_rectangle(
        (box_x, box_y, box_x + box_w, box_y + box_h),
        radius=r, fill=BG, outline=None,
    )
    _wobble_polyline(draw, pts, rng=rng, jitter=1.2, width=STROKE)

    # Tail — short triangle at the bubble's lower-left edge, pointing
    # toward the speaker. Length is capped so the tail never crosses
    # the canvas as a long arrow.
    tail_base_x = box_x + 50
    tail_w = 28
    # Tail tip sits ~70 px below the bubble in the direction of `anchor`.
    base_cx = tail_base_x + tail_w / 2
    base_cy = box_y + box_h
    dx = anchor[0] - base_cx
    dy = anchor[1] - base_cy
    norm = max(1.0, (dx * dx + dy * dy) ** 0.5)
    tail_len = 70
    tip = (base_cx + dx / norm * tail_len, base_cy + dy / norm * tail_len)
    poly = [
        (tail_base_x, base_cy - 1),
        (tail_base_x + tail_w, base_cy - 1),
        tip,
    ]
    draw.polygon(poly, fill=BG)
    _wobble_polyline(draw, [poly[0], poly[2]], rng=rng, jitter=1.0, width=STROKE)
    _wobble_polyline(draw, [poly[1], poly[2]], rng=rng, jitter=1.0, width=STROKE)

    # Text
    cy = box_y + pad
    if parenthetical:
        for pl in _wrap(parenthetical, paren_font, max_text_w):
            draw.text(
                (box_x + pad, cy), f"({pl})",
                fill=INK, font=paren_font,
            )
            cy += paren_font.getbbox("Hg")[3] - paren_font.getbbox("Hg")[1] + 4
        cy += 4
    for ln in lines:
        draw.text((box_x + pad, cy), ln, fill=INK, font=font)
        cy += line_h


# ---- Slug bar ----

def _draw_slug(draw: ImageDraw.ImageDraw, heading: str):
    W, _ = CANVAS
    bar_h = 56
    draw.rectangle((0, 0, W, bar_h), fill=SLUG_BG)
    f = _font(26, bold=True)
    draw.text((28, 14), heading.upper(), fill=SLUG_FG, font=f)


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


# ---- Public render ----

def render_pose(shot: Shot, pose_index: int, *, seed_salt: int = 0) -> Image.Image:
    """Render one pose of one shot. Returns a fresh PIL Image.

    Determinism: the same (shot_id, pose_index, seed_salt) will produce
    the same wobble pattern. The stitcher passes pose_index for the
    "stop-motion held pose" cycling and uses seed_salt only when it
    wants per-frame jitter regenerated.
    """
    img = Image.new("RGB", CANVAS, BG)
    draw = ImageDraw.Draw(img)
    rng = random.Random(
        hash((shot.kind, shot.scene_index, shot.text[:32], pose_index, seed_salt))
        & 0xFFFFFFFF
    )

    _draw_slug(draw, shot.scene_heading)
    W, H = CANVAS

    if shot.kind == "slug":
        # Big centred title card. No background furniture — the slug is
        # purely a chapter break.
        f = _font(72, bold=True)
        sub = _font(34)
        label = f"SCENE {shot.scene_index + 1}"
        bbox = f.getbbox(label)
        tw = bbox[2] - bbox[0]
        draw.text(((W - tw) / 2, H / 2 - 80), label, fill=INK, font=f)
        bbox2 = sub.getbbox(shot.scene_heading.upper())
        tw2 = bbox2[2] - bbox2[0]
        draw.text(((W - tw2) / 2, H / 2 + 10), shot.scene_heading.upper(),
                  fill=INK, font=sub)
        # A subtle wobbly underline.
        _wobble_line(
            draw, ((W - tw2) / 2 - 20, H / 2 + 70),
            ((W - tw2) / 2 + tw2 + 20, H / 2 + 70),
            rng=rng, jitter=2.0, segments=24,
        )
    elif shot.kind == "transition":
        # Bold centred transition keyword (CUT TO:, FADE OUT.).
        f = _font(96, bold=True)
        bbox = f.getbbox(shot.text.upper())
        tw = bbox[2] - bbox[0]
        draw.text(((W - tw) / 2, H / 2 - 60), shot.text.upper(), fill=INK, font=f)
    elif shot.kind == "action":
        # Background hint + narrator-style caption box at bottom.
        _draw_background(draw, shot.location, rng=rng)
        _draw_caption(draw, shot.text, rng=rng)
    elif shot.kind == "dialogue":
        # Floor-only background (windows would clash with the figure).
        floor_y = H - 140
        _wobble_line(
            draw, (40, floor_y), (W - 40, floor_y),
            rng=rng, jitter=2.0, segments=24,
        )
        cx = 320
        cy = H - 200
        _draw_figure(
            draw, cx, cy,
            rng=rng,
            pose=pose_index % 3,
            talking=True,
            mouth_cycle=pose_index,
        )
        # Character name plate just above the head.
        if shot.character:
            f = _font(28, bold=True)
            name = shot.character.upper()
            bbox = f.getbbox(name)
            nw = bbox[2] - bbox[0]
            draw.text((cx - nw / 2, cy - 270), name, fill=INK, font=f)
        # Bubble tail anchor at the speaker's mouth area.
        anchor = (cx + 20, cy - 160)
        _draw_bubble(
            draw, shot.text,
            rng=rng,
            anchor=anchor,
            font=_font(28),
            parenthetical=shot.parenthetical,
        )

    return img


def jitter_frame(img: Image.Image, dx: int, dy: int) -> Image.Image:
    """Translate the image by (dx, dy) on the same canvas, filling the
    revealed strip with the paper colour. Used by the stitcher for the
    per-frame stop-motion shake."""
    out = Image.new("RGB", img.size, BG)
    out.paste(img, (dx, dy))
    return out
