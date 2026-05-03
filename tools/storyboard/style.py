"""Visual style configuration for the storyboard renderer.

A `Style` is the bag of constants the renderer normally hard-codes:
canvas colours, stroke widths, line wobble, figure proportions, eye
shape, ground shadow on/off. A handful of built-in presets ship with
the tool, and users can save their own as JSON to `~/.config/storyboard
/styles/<name>.json` (or load via `--style-file`) to keep their
preferred look across projects.

Public surface:
    Style                       — dataclass, all knobs in one place.
    list_presets()              — names of built-in + on-disk styles.
    load(name_or_path) -> Style — built-in name OR path to a json file.
    Style.save(path)            — dump to a json file.

Style is intentionally JSON-friendly: tuples become lists on disk and
are coerced back on load. No imports of PIL or render here so the
config stays cheap to import from the CLI.
"""
from __future__ import annotations
from dataclasses import dataclass, asdict, field, fields
from typing import Dict, List, Tuple, Optional, Union
import json
import os


# ---- The Style dataclass -------------------------------------------

RGB = Tuple[int, int, int]


@dataclass
class Style:
    name: str = "calvin"

    # ---- Palette ---------------------------------------------------
    bg:        RGB = (252, 248, 240)   # paper
    ink:       RGB = (20, 20, 24)      # primary stroke
    ink_faint: RGB = (110, 110, 118)   # listener / background figure
    slug_bg:   RGB = (20, 20, 24)
    slug_fg:   RGB = (252, 248, 240)

    # ---- Stroke ----------------------------------------------------
    stroke:           int   = 4
    line_jitter:      float = 2.4   # px max deviation per segment
    line_segments:    int   = 10    # interpolation samples per stroke
    circle_jitter:    float = 1.8
    circle_segments:  int   = 36
    background_jitter_mul: float = 1.0   # multiplier on wobble for bg

    # ---- Figure proportions (px at scale=1.0) ----------------------
    head_r:           int  = 46
    head_attach:      float = 0.78   # head_cy = neck_top - r * head_attach
    neck_len:         int  = 10
    shoulder_to_hip:  int  = 95
    shoulder_dx:      int  = 26
    hip_dx:           int  = 22
    leg_upper:        int  = 55
    leg_lower:        int  = 55
    arm_upper:        int  = 52
    arm_lower:        int  = 52

    # ---- Face ------------------------------------------------------
    eye_style:  str  = "round_pupil"   # "round_pupil" | "dot"
    eye_radius: int  = 6
    pupil_radius: int = 2
    eye_dx:     int  = 17
    eye_offset_y_factor: float = -0.10  # eye_y = head_cy + factor * head_r

    # ---- Extras ----------------------------------------------------
    ground_shadow:    bool = True
    body_mask:        bool = True
    bubble_margin:    int  = 8       # paper-fill margin around bubble

    # ---- Layout ----------------------------------------------------
    canvas_w:    int = 1280
    canvas_h:    int = 720
    slug_bar_h:  int = 56
    name_plate_offset: int = 250    # plate y = figure_cy - this

    # ---- Serialization ---------------------------------------------

    def to_dict(self) -> Dict:
        return asdict(self)

    def save(self, path: str) -> None:
        os.makedirs(os.path.dirname(os.path.abspath(path)) or ".",
                    exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2)

    @classmethod
    def from_dict(cls, d: Dict) -> "Style":
        # Coerce list -> tuple for RGB fields.
        rgb_fields = {"bg", "ink", "ink_faint", "slug_bg", "slug_fg"}
        clean = {}
        valid = {f.name for f in fields(cls)}
        for k, v in d.items():
            if k not in valid:
                continue
            if k in rgb_fields and isinstance(v, list):
                v = tuple(v)
            clean[k] = v
        return cls(**clean)


# ---- Built-in presets ----------------------------------------------

_PRESETS: Dict[str, Style] = {
    # Calvin & Hobbes-ish: big head, lively wobble, expressive eyes,
    # ground hatching. The current default look.
    "calvin": Style(name="calvin"),

    # Original lean stickman: smaller head, longer legs, dot eyes,
    # tight wobble — the look the tool shipped with.
    "classic": Style(
        name="classic",
        line_jitter=1.6,
        line_segments=8,
        circle_jitter=1.4,
        head_r=32,
        head_attach=0.85,
        neck_len=14,
        shoulder_to_hip=130,
        shoulder_dx=28,
        hip_dx=20,
        leg_upper=68,
        leg_lower=68,
        eye_style="dot",
        eye_radius=2,
        pupil_radius=0,
        eye_dx=13,
        eye_offset_y_factor=-0.55,
        ground_shadow=False,
    ),

    # Bold marker — chunky stroke, low wobble, no shadow. Reads well
    # at thumbnail size. Good for animatic exports.
    "bold": Style(
        name="bold",
        stroke=6,
        line_jitter=1.2,
        line_segments=6,
        circle_jitter=0.8,
        background_jitter_mul=0.6,
        ground_shadow=False,
        head_r=44,
        bubble_margin=10,
    ),

    # Sketchy — extra wobble, looser feel, like ballpoint draft.
    "sketchy": Style(
        name="sketchy",
        stroke=3,
        line_jitter=3.4,
        line_segments=14,
        circle_jitter=2.6,
        background_jitter_mul=1.4,
        ground_shadow=True,
    ),
}


# ---- Lookup --------------------------------------------------------

def _config_dir() -> str:
    """Where user-saved styles live: $STORYBOARD_STYLES_DIR or
    ~/.config/storyboard/styles/."""
    env = os.environ.get("STORYBOARD_STYLES_DIR")
    if env:
        return env
    return os.path.join(
        os.path.expanduser("~"), ".config", "storyboard", "styles",
    )


def list_presets() -> List[str]:
    """Built-in preset names + any user styles found on disk."""
    out = list(_PRESETS.keys())
    d = _config_dir()
    if os.path.isdir(d):
        for fn in sorted(os.listdir(d)):
            if fn.endswith(".json"):
                out.append(os.path.splitext(fn)[0])
    return out


def load(name_or_path: Union[str, "Style", None]) -> Style:
    """Resolve a style argument.

    • None / "default" / "" → calvin preset.
    • A built-in preset name → the preset.
    • An existing path that ends in `.json` → load from that file.
    • A bare name (no `.json`) → look up `<config_dir>/<name>.json`.
    • An already-loaded `Style` → returned as-is.
    """
    if isinstance(name_or_path, Style):
        return name_or_path
    if name_or_path in (None, "", "default"):
        return _PRESETS["calvin"]
    s = str(name_or_path)
    if s in _PRESETS:
        # Return a fresh copy so callers can safely mutate.
        return Style.from_dict(_PRESETS[s].to_dict())
    if os.path.isfile(s):
        with open(s, "r", encoding="utf-8") as f:
            return Style.from_dict(json.load(f))
    candidate = os.path.join(_config_dir(), f"{s}.json")
    if os.path.isfile(candidate):
        with open(candidate, "r", encoding="utf-8") as f:
            return Style.from_dict(json.load(f))
    raise ValueError(
        f"Unknown style {s!r}. Built-ins: {list(_PRESETS.keys())}. "
        f"Looked in: {_config_dir()}"
    )


def save_named(style: Style, name: Optional[str] = None) -> str:
    """Save a Style to the user config dir under `<name>.json` (or
    `style.name` if not given). Returns the written path."""
    n = name or style.name
    path = os.path.join(_config_dir(), f"{n}.json")
    style.save(path)
    return path
