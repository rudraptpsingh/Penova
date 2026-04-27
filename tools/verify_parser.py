#!/usr/bin/env python3
"""
verify_parser.py — Real-PDF validator for PDFScreenplayParser.

Why this exists: PDFScreenplayParser is Swift, so its behaviour can't be
reproduced on a Linux CI box without a Swift toolchain. This script
mirrors the parser's classification logic in Python and runs it against
real PDFs (either synthetic ones we render here, or anything dropped
into PenovaTests/Fixtures/screenplays/) — proving the algorithm holds
up on the same kind of input PDFKit will hand it on iOS.

Two modes:
  1. Synthetic     — generate a Final-Draft-style PDF with reportlab
                     (industry indents, real Courier 12pt, page numbers,
                     CONT'D markers, transitions), extract via pdftotext
                     -bbox-layout, classify, assert.
  2. Real fixtures — for every PDF in PenovaTests/Fixtures/screenplays/,
                     parse it and emit a per-script report (scene count,
                     character cues, dialogue blocks, columns inferred).
                     Asserts only minimal invariants so any
                     well-formed screenplay passes regardless of style.

Usage:
    python3 tools/verify_parser.py
    python3 tools/verify_parser.py PenovaTests/Fixtures/screenplays/foo.pdf
"""
from __future__ import annotations
import os
import re
import sys
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIXTURES = os.path.join(ROOT, "PenovaTests", "Fixtures", "screenplays")

# ----------------------------------------------------------------------
# Industry-standard layout constants.  Mirror ScriptPDFRenderer.swift.
# Page is US Letter (612 x 792 pt). Origin is lower-left in PDF space.
# Column x-coordinates (left edge of the text):
#   Action / Heading          108  (1.5")
#   Dialogue                  180  (2.5")
#   Parenthetical             223  (3.1")
#   Character cue             266  (3.7")
#   Transition (right-edge)  ~432-540  (right-aligned)
# ----------------------------------------------------------------------

@dataclass
class Line:
    text: str
    x: float
    y_top: float            # PDF space (origin lower-left); larger = higher
    page_height: float
    page_index: int


@dataclass
class Diagnostics:
    page_count: int = 0
    body_line_count: int = 0
    dropped_chrome_count: int = 0
    scene_count: int = 0
    action_x: Optional[float] = None
    character_x: Optional[float] = None
    parenthetical_x: Optional[float] = None
    dialogue_x: Optional[float] = None
    transition_x: Optional[float] = None
    had_title_page: bool = False


@dataclass
class Element:
    kind: str
    text: str


@dataclass
class Scene:
    heading: str
    elements: List[Element] = field(default_factory=list)


@dataclass
class ParsedDocument:
    title_page: dict = field(default_factory=dict)
    scenes: List[Scene] = field(default_factory=list)


# ----------------------------------------------------------------------
# Patterns — mirror PDFScreenplayParser.swift
# ----------------------------------------------------------------------

SCENE_HEADING_PREFIXES = (
    "INT.", "EXT.", "EST.",
    "INT/EXT.", "INT./EXT.", "EXT/INT.", "EXT./INT.",
    "I/E.", "I./E.",
)

PAGE_NUMBER_RE = re.compile(r"^[0-9]{1,4}\.?$")
ROMAN_RE = re.compile(r"^[ivxlcdm]{1,5}\.?$", re.IGNORECASE)
SCENE_NUMBER_PREFIX_RE = re.compile(r"^[A-Z]?[0-9]{1,4}[A-Z]?\s+")
SCENE_NUMBER_SUFFIX_RE = re.compile(r"\s+[A-Z]?[0-9]{1,4}[A-Z]?$")
CUE_SUFFIX_RE = re.compile(r"\s*\([^)]*\)\s*$")
CHROME_TOKEN_RE = re.compile(r"^[A-Z0-9 .,/\-:]+$")


def is_uppercase_letters(s: str) -> bool:
    saw = False
    for ch in s:
        if ch.isalpha():
            saw = True
            if ch.islower():
                return False
    return saw


def strip_scene_number(text: str) -> str:
    out = SCENE_NUMBER_PREFIX_RE.sub("", text)
    out = SCENE_NUMBER_SUFFIX_RE.sub("", out)
    return out


def strip_cue_suffix(text: str) -> str:
    out = text
    while True:
        nxt = CUE_SUFFIX_RE.sub("", out)
        if nxt == out:
            break
        out = nxt
    return out.strip()


def is_scene_heading(text: str) -> bool:
    t = strip_scene_number(text.strip())
    upper = t.upper()
    for p in SCENE_HEADING_PREFIXES:
        if upper.startswith(p) or upper.startswith(p + " "):
            return True
    if upper.startswith(".INT") or upper.startswith(".EXT"):
        return True
    return False


def is_transition(text: str) -> bool:
    if not is_uppercase_letters(text):
        return False
    upper = text.upper()
    if upper.endswith("TO:"):
        return True
    if upper in {
        "FADE OUT.", "FADE TO BLACK.", "FADE OUT", "FADE TO BLACK",
        "THE END", "THE END.", "TO BE CONTINUED.", "TO BE CONTINUED",
    }:
        return True
    return False


def is_chrome(line: Line) -> bool:
    t = line.text.strip()
    if PAGE_NUMBER_RE.match(t):
        return True
    if ROMAN_RE.match(t.lower()) and len(t) <= 5:
        return True
    upper = t.upper()
    if upper == "(MORE)":
        return True
    if upper == "(CONTINUED)":
        return True
    if upper == "CONTINUED:":
        return True
    if (
        upper.endswith("(CONT'D)")
        and upper.startswith("(")
        and line.y_top > line.page_height - 90
    ):
        return True
    near_top = line.y_top > line.page_height - 54
    near_bottom = line.y_top < 54
    if (near_top or near_bottom) and len(t) <= 16:
        if CHROME_TOKEN_RE.match(t):
            return True
    return False


# ----------------------------------------------------------------------
# X-clustering — mirror PDFScreenplayParser.inferColumns
# ----------------------------------------------------------------------

@dataclass
class Columns:
    action: Optional[float] = None
    character: Optional[float] = None
    parenthetical: Optional[float] = None
    dialogue: Optional[float] = None
    transition: Optional[float] = None


def infer_columns(lines: List[Line]) -> Columns:
    if not lines:
        return Columns()
    counts: dict = {}
    for line in lines:
        bucket = round(line.x / 6) * 6
        counts[bucket] = counts.get(bucket, 0) + 1
    buckets = sorted(b for b, c in counts.items() if c >= 2)
    cols = Columns()
    if not buckets:
        return cols
    if len(buckets) >= 1:
        cols.action = buckets[0]
    if len(buckets) >= 2:
        cols.dialogue = buckets[1]
    if len(buckets) >= 3:
        cols.parenthetical = buckets[2]
    if len(buckets) >= 4:
        cols.character = buckets[3]
    if len(buckets) >= 5:
        cols.transition = buckets[-1]
    if len(buckets) == 2:
        cols.action = buckets[0]
        cols.dialogue = buckets[1]
    return cols


def validate_columns(cols: Columns, lines: List[Line]) -> Columns:
    """Demote a labelled column whose content doesn't match the label.
    Mirrors PDFScreenplayParser.validateColumns(_:against:)."""
    tol = 6.0

    if cols.parenthetical is not None:
        sample = [l for l in lines if abs(l.x - cols.parenthetical) <= tol]
        if sample:
            paren_starts = sum(1 for l in sample
                               if l.text.strip().startswith("(")
                               and l.text.strip().endswith(")"))
            if paren_starts / len(sample) < 0.5:
                # If the demoted column had more lines than the inferred
                # dialogue column, it was the real dialogue (Big Fish).
                dlg_count = 0
                if cols.dialogue is not None:
                    dlg_count = sum(1 for l in lines if abs(l.x - cols.dialogue) <= tol)
                if len(sample) > dlg_count or cols.dialogue is None:
                    cols.dialogue = cols.parenthetical
                cols.parenthetical = None

    if cols.character is not None:
        sample = [l for l in lines if abs(l.x - cols.character) <= tol]
        if sample:
            cue_shaped = sum(1 for l in sample
                             if is_uppercase_letters(l.text.strip())
                             and 2 <= len(l.text.strip()) <= 32
                             and "." not in l.text.strip()
                             and "," not in l.text.strip())
            if cue_shaped / len(sample) < 0.4:
                cols.character = None

    return cols


def classify(line: Line, cols: Columns) -> str:
    t = line.text.strip()
    is_caps = is_uppercase_letters(t)
    if is_scene_heading(t):
        return "heading"
    if is_transition(t):
        return "transition"
    if cols.transition is not None and line.x >= cols.transition - 6:
        return "transition"
    if t.startswith("(") and t.endswith(")"):
        return "parenthetical"
    if cols.character is not None and abs(line.x - cols.character) <= 10 and is_caps:
        return "character"
    # Wonky-template promotion: no character column was inferred, so
    # ALL CAPS short non-punctuated lines must be character cues before
    # the action-column match swallows them.
    if (cols.character is None
            and is_caps and 2 <= len(t) <= 32
            and "." not in t and "," not in t):
        return "character"
    if cols.parenthetical is not None and abs(line.x - cols.parenthetical) <= 10:
        return "parenthetical"
    if cols.dialogue is not None and abs(line.x - cols.dialogue) <= 10:
        return "dialogue"
    if cols.action is not None and abs(line.x - cols.action) <= 10:
        return "action"
    if is_caps and 2 <= len(t) <= 32 and "." not in t and "," not in t:
        return "character"
    return "action"


# ----------------------------------------------------------------------
# Title page — mirror extractTitlePage()
# ----------------------------------------------------------------------

KEY_VALUE_RE = re.compile(r"^([A-Za-z][A-Za-z ]{0,31}):\s*(.*)$")


def parse_title_page(page0: List[Line]) -> Optional[dict]:
    if not page0:
        return None
    fields: dict = {}
    for line in page0:
        m = KEY_VALUE_RE.match(line.text.strip())
        if m:
            fields[m.group(1).lower()] = m.group(2).strip()
    if fields:
        return fields
    sorted_lines = sorted(page0, key=lambda l: -l.y_top)
    topish = [l.text.strip() for l in sorted_lines[:12] if l.text.strip()]
    if not topish:
        return None
    fields["title"] = topish[0]

    i = 1
    while i < len(topish):
        line = topish[i]
        low = line.lower()
        # Standalone label ("written by"). The author's name is the
        # next non-empty line.
        if low == "by" or low == "written by":
            if i + 1 < len(topish):
                fields["author"] = topish[i + 1]
                i += 2
                continue
            i += 1
            continue
        # Inline form ("by John August" / "Written by John August").
        if low.startswith("by ") or low.startswith("written by "):
            cleaned = re.sub(r"^(?:written\s+by|by)\s+", "", line, flags=re.IGNORECASE).strip()
            if cleaned:
                fields["author"] = cleaned
            i += 1
            continue
        i += 1
    return fields


# ----------------------------------------------------------------------
# Parser — mirror PDFScreenplayParser.parse()
# ----------------------------------------------------------------------

def parse(lines_per_page: List[List[Line]]) -> Tuple[ParsedDocument, Diagnostics]:
    diag = Diagnostics()
    diag.page_count = len(lines_per_page)
    all_lines = [l for page in lines_per_page for l in page]
    body = []
    for l in all_lines:
        if is_chrome(l):
            diag.dropped_chrome_count += 1
            continue
        body.append(l)

    page0 = [l for l in body if l.page_index == 0]
    page0_has_heading = any(is_scene_heading(l.text) for l in page0)
    doc = ParsedDocument()
    if not page0_has_heading:
        tp = parse_title_page(page0)
        if tp:
            doc.title_page = tp
            diag.had_title_page = True
            body = [l for l in body if l.page_index > 0]
    diag.body_line_count = len(body)

    cols = infer_columns(body)
    cols = validate_columns(cols, body)
    diag.action_x = cols.action
    diag.dialogue_x = cols.dialogue
    diag.parenthetical_x = cols.parenthetical
    diag.character_x = cols.character
    diag.transition_x = cols.transition

    current: Optional[Scene] = None
    pending_action: List[str] = []

    def flush_action():
        nonlocal current, pending_action
        joined = " ".join(pending_action).strip()
        pending_action = []
        if joined and current is not None:
            current.elements.append(Element("action", joined))

    for line in body:
        kind = classify(line, cols)
        text = line.text.strip()
        if kind == "heading":
            flush_action()
            if current is not None:
                doc.scenes.append(current)
            current = Scene(strip_scene_number(text), [])
        elif kind == "action":
            pending_action.append(text)
        elif kind == "character":
            flush_action()
            if current is not None:
                current.elements.append(Element("character", strip_cue_suffix(text)))
        elif kind == "parenthetical":
            flush_action()
            if current is not None:
                current.elements.append(Element("parenthetical", text))
        elif kind == "dialogue":
            flush_action()
            if current is not None:
                last = current.elements[-1] if current.elements else None
                if last and last.kind == "dialogue":
                    last.text = (last.text + " " + text).strip()
                else:
                    current.elements.append(Element("dialogue", text))
        elif kind == "transition":
            flush_action()
            if current is not None:
                current.elements.append(Element("transition", text))

    flush_action()
    if current is not None:
        doc.scenes.append(current)
    diag.scene_count = len(doc.scenes)
    return doc, diag


# ----------------------------------------------------------------------
# PDF -> Line[] via pdftotext -bbox-layout
# ----------------------------------------------------------------------

def extract_lines(pdf_path: str) -> List[List[Line]]:
    """Run pdftotext -bbox-layout to get a pseudo-HTML with per-word
    bounding boxes, then group into lines per page. Words sharing a
    yMin within 3pt are merged into a single line — pdftotext sometimes
    splits visually-same-line content (e.g. "INT. WILL'S BEDROOM" gets
    cut at the period) into separate <line> records, which would
    otherwise break scene-heading detection on real Hollywood scripts."""
    if shutil.which("pdftotext") is None:
        raise RuntimeError("pdftotext not installed")
    proc = subprocess.run(
        ["pdftotext", "-bbox-layout", pdf_path, "-"],
        capture_output=True, text=True, check=True,
    )
    xml_text = proc.stdout
    xml_text = re.sub(r'\sxmlns="[^"]+"', "", xml_text, count=1)
    root = ET.fromstring(xml_text)
    pages: List[List[Line]] = []
    for page_idx, page in enumerate(root.iter("page")):
        page_h = float(page.attrib.get("height", "792"))
        # First pass: collect every (text, x, yMin) word fragment.
        fragments: List[tuple] = []  # (yMin, xMin, text)
        for word in page.iter("word"):
            txt = (word.text or "").strip()
            if not txt:
                continue
            try:
                y_min = float(word.attrib["yMin"])
                x_min = float(word.attrib["xMin"])
            except (KeyError, ValueError):
                continue
            fragments.append((y_min, x_min, txt))
        if not fragments:
            pages.append([])
            continue
        fragments.sort(key=lambda f: (f[0], f[1]))

        # Second pass: bucket by yMin within ±3pt tolerance.
        page_lines: List[Line] = []
        cur_y: Optional[float] = None
        cur_min_x: Optional[float] = None
        cur_words: List[str] = []
        TOL = 3.0
        for y_min, x_min, txt in fragments:
            if cur_y is None or abs(y_min - cur_y) > TOL:
                if cur_words and cur_y is not None and cur_min_x is not None:
                    page_lines.append(Line(
                        " ".join(cur_words), cur_min_x,
                        page_h - cur_y, page_h, page_idx
                    ))
                cur_y = y_min
                cur_min_x = x_min
                cur_words = [txt]
            else:
                cur_words.append(txt)
                if x_min < (cur_min_x or x_min):
                    cur_min_x = x_min
        if cur_words and cur_y is not None and cur_min_x is not None:
            page_lines.append(Line(
                " ".join(cur_words), cur_min_x,
                page_h - cur_y, page_h, page_idx
            ))

        page_lines.sort(key=lambda l: -l.y_top)
        pages.append(page_lines)
    return pages


# ----------------------------------------------------------------------
# Synthetic-PDF generator — industry-standard indents
# ----------------------------------------------------------------------

def generate_industry_sample(out_path: str) -> None:
    """Minimal industry-format PDF — clean, no chrome."""
    from reportlab.pdfgen import canvas
    from reportlab.lib.pagesizes import letter

    c = canvas.Canvas(out_path, pagesize=letter)
    PAGE_W, PAGE_H = letter
    c.setFont("Courier", 12)

    LEAD = 14
    y = PAGE_H - 72   # 1" top margin

    def blank():
        nonlocal y
        y -= LEAD

    def emit(text: str, x: float):
        nonlocal y
        if y < 72:
            c.showPage()
            c.setFont("Courier", 12)
            y = PAGE_H - 72
        c.drawString(x, y, text)
        y -= LEAD

    # Title page (page 0).
    c.setFont("Courier", 12)
    c.drawCentredString(PAGE_W / 2, PAGE_H / 2 + 60, "EK RAAT MUMBAI MEIN")
    c.drawCentredString(PAGE_W / 2, PAGE_H / 2 + 30, "by")
    c.drawCentredString(PAGE_W / 2, PAGE_H / 2, "Penova Test Author")
    c.drawString(72, 100, "penova-test@example.com")
    c.drawString(72, 86, "+91 99999 99999")
    c.showPage()

    # Body — page 1+.
    c.setFont("Courier", 12)
    y = PAGE_H - 72

    emit("INT. MUMBAI LOCAL TRAIN - NIGHT", 108)
    blank()
    emit("Rain hammers the roof. IQBAL (mid-40s) clutches a thermos.", 108)
    blank()
    emit("IQBAL", 266)
    emit("(to himself)", 223)
    emit("Not late. Not yet.", 180)
    blank()
    emit("RAVI (V.O.)", 266)
    emit("Iqbal? Step back from the edge.", 180)
    blank()
    emit("CUT TO:", 432)
    blank()

    emit("INT. SIGNAL CONTROL ROOM - CONTINUOUS", 108)
    blank()
    emit("Fluorescent light. RAVI (early-30s) flicks between two", 108)
    emit("monitors. Board A is full. Board B is dark.", 108)
    blank()
    emit("RAVI", 266)
    emit("Whose shift was it the last time this happened?", 180)
    blank()
    emit("MEENA", 266)
    emit("(quietly)", 223)
    emit("The last time what happened?", 180)
    blank()
    emit("FADE OUT.", 432)

    c.save()


def generate_final_draft_style(out_path: str) -> None:
    """Multi-page Final Draft-style PDF with full chrome:
       - page numbers top-right
       - scene numbers in both margins (which share y with the heading
         and get merged into the heading line by mergeSameYLines —
         exercising stripSceneNumberPrefix's single-space tolerance)
       - MORE / CONT'D continuation markers across page breaks
       - multi-paragraph action
       - enough dialogue to form a robust column for the inferrer
    """
    from reportlab.pdfgen import canvas
    from reportlab.lib.pagesizes import letter

    c = canvas.Canvas(out_path, pagesize=letter)
    PAGE_W, PAGE_H = letter
    c.setFont("Courier", 12)
    LEAD = 14
    page_num = [0]
    y = [PAGE_H - 72]

    def page_break():
        # Page number top-right "N.".
        c.setFont("Courier", 12)
        c.drawRightString(PAGE_W - 72, PAGE_H - 36,
                          f"{page_num[0] + 1}.")
        c.showPage()
        c.setFont("Courier", 12)
        page_num[0] += 1
        y[0] = PAGE_H - 72

    def line(text: str, x: float):
        if y[0] < 72:
            page_break()
        c.drawString(x, y[0], text)
        y[0] -= LEAD

    def blank():
        y[0] -= LEAD

    # Title page.
    c.drawCentredString(PAGE_W / 2, PAGE_H / 2 + 60, "THE LAST TRAIN")
    c.drawCentredString(PAGE_W / 2, PAGE_H / 2 + 30, "by")
    c.drawCentredString(PAGE_W / 2, PAGE_H / 2, "Penova Test")
    c.showPage()
    page_num[0] = 1
    y[0] = PAGE_H - 72

    def heading(num: int, suffix: str, text: str):
        # Final Draft prints scene numbers in BOTH left and right margins.
        # Three blank cells of separation match what FD outputs.
        c.drawString(54, y[0], f"{num}{suffix}")
        c.drawString(108, y[0], text)
        c.drawRightString(PAGE_W - 54, y[0], f"{num}{suffix}")
        y[0] -= LEAD

    # Scenes ----------------------------------------------------------
    heading(1, "", "INT. BOMBAY CENTRAL - PLATFORM 7 - NIGHT")
    blank()
    line("Rain hammers the metal roof. The platform is empty except for", 108)
    line("a thermos, a lantern, and IQBAL (mid-40s) -- night porter,", 108)
    line("back straight, shoes polished to a shine that only old habits", 108)
    line("produce.", 108)
    blank()
    line("The station clock reads 23:44.", 108)
    blank()
    line("IQBAL", 266)
    line("(to himself)", 223)
    line("Not late. Not yet.", 180)
    blank()
    line("A muffled RADIO hiss. Iqbal lifts a battered handset.", 108)
    blank()
    line("RAVI (V.O.)", 266)
    line("Seven, do you copy? The twenty-three forty-five isn't on my", 180)
    # Force a page break inside dialogue so MORE/CONT'D pattern fires.
    line("(MORE)", 266)
    page_break()
    line("RAVI (V.O.) (CONT'D)", 266)
    line("board.", 180)
    blank()
    line("IQBAL", 266)
    line("It's on mine.", 180)
    blank()
    line("CUT TO:", 432)
    blank()

    heading(2, "", "INT. SIGNAL CONTROL ROOM - CONTINUOUS")
    blank()
    line("Fluorescent light. RAVI (early-30s) flicks between two monitors.", 108)
    line("Board A is full. Board B -- the official one -- shows Platform 7", 108)
    line("as DARK.", 108)
    blank()
    line("RAVI", 266)
    line("(into radio)", 223)
    line("Iqbal. Uncle. Step back from the edge, yeah?", 180)
    blank()
    line("The door opens. MEENA (38), compliance officer, coat wet,", 108)
    line("notebook already open.", 108)
    blank()
    line("MEENA", 266)
    line("Whose shift was it the last time this happened?", 180)
    blank()
    line("RAVI", 266)
    line("The last time what happened?", 180)
    blank()
    line("MEENA", 266)
    line("(reading her notebook)", 223)
    line("Twelve years, four months, three days.", 180)
    blank()
    line("RAVI", 266)
    line("That's exactly the answer of someone", 180)
    line("who has been counting.", 180)
    blank()
    line("MEENA", 266)
    line("My brother was on that train.", 180)
    blank()
    line("RAVI", 266)
    line("(softly)", 223)
    line("Then we should probably compare notes.", 180)
    blank()
    line("MEENA", 266)
    line("Quickly.", 180)
    blank()
    line("FADE OUT.", 432)

    page_break()
    c.save()


def generate_wonky_template(out_path: str) -> None:
    """A document where action and character are both flush left at the
    same indent — the classifier's column heuristic can't help, so the
    content-fallback ('ALL CAPS short = character cue') has to carry the
    weight.
    """
    from reportlab.pdfgen import canvas
    from reportlab.lib.pagesizes import letter

    c = canvas.Canvas(out_path, pagesize=letter)
    PAGE_W, PAGE_H = letter
    c.setFont("Courier", 12)
    LEAD = 14
    y = [PAGE_H - 72]

    def line(text: str, x: float):
        c.drawString(x, y[0], text)
        y[0] -= LEAD

    def blank():
        y[0] -= LEAD

    # Skip title page entirely — opens straight on a scene.
    line("INT. WAREHOUSE - NIGHT", 130)
    blank()
    line("A dim bulb sways. SHADOWS lengthen.", 130)
    blank()
    line("BOB", 130)
    line("This is a problem.", 130)
    blank()
    line("ALICE", 130)
    line("Indeed it is.", 130)
    blank()
    line("EXT. STREET - LATER", 130)
    blank()
    line("Wind through wires.", 130)

    c.save()


# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------

def report(label: str, doc: ParsedDocument, diag: Diagnostics) -> None:
    print(f"\n=== {label} ===")
    print(f"  pages:        {diag.page_count}")
    print(f"  body lines:   {diag.body_line_count}")
    print(f"  dropped:      {diag.dropped_chrome_count}")
    print(f"  scenes:       {diag.scene_count}")
    print(f"  cols (a/d/p/c/t): "
          f"{diag.action_x}/{diag.dialogue_x}/"
          f"{diag.parenthetical_x}/{diag.character_x}/{diag.transition_x}")
    print(f"  title page:   {diag.had_title_page}  {doc.title_page}")
    for i, scene in enumerate(doc.scenes[:6]):
        kinds = [e.kind for e in scene.elements]
        print(f"  scene {i+1}: {scene.heading!r}  ({len(scene.elements)} elements)")
        print(f"           kinds: {kinds}")
        for e in scene.elements[:6]:
            preview = (e.text[:60] + "…") if len(e.text) > 60 else e.text
            print(f"           {e.kind:14s} {preview}")
    if len(doc.scenes) > 6:
        print(f"  …and {len(doc.scenes) - 6} more scenes")


def main(argv):
    failures: List[str] = []

    if len(argv) > 1:
        # Targeted mode.
        targets = argv[1:]
    else:
        targets = []
        out_dir = "/tmp/pdfverify"
        os.makedirs(out_dir, exist_ok=True)

        industry = os.path.join(out_dir, "industry-sample.pdf")
        generate_industry_sample(industry)
        targets.append(industry)

        finaldraft = os.path.join(out_dir, "final-draft-style.pdf")
        generate_final_draft_style(finaldraft)
        targets.append(finaldraft)

        wonky = os.path.join(out_dir, "wonky-template.pdf")
        generate_wonky_template(wonky)
        targets.append(wonky)

        if os.path.isdir(FIXTURES):
            for name in sorted(os.listdir(FIXTURES)):
                p = os.path.join(FIXTURES, name)
                if name.lower().endswith(".pdf") and os.path.isfile(p):
                    targets.append(p)

    for path in targets:
        label = os.path.relpath(path, ROOT) if path.startswith(ROOT) else path
        pages = extract_lines(path)
        doc, diag = parse(pages)
        report(label, doc, diag)

        if "industry-sample" in path:
            try:
                assert diag.scene_count == 2, f"expected 2 scenes, got {diag.scene_count}"
                assert diag.had_title_page, "expected a title page"
                assert doc.title_page.get("title", "").upper() == "EK RAAT MUMBAI MEIN", \
                    f"title mismatch: {doc.title_page}"
                kinds = [e.kind for s in doc.scenes for e in s.elements]
                for k in ("character", "dialogue", "parenthetical", "transition", "action"):
                    assert k in kinds, f"missing element kind {k!r} in {kinds}"
                print("\n  ✅ industry-sample: all invariants passed")
            except AssertionError as e:
                failures.append(f"industry-sample: {e}")
                print(f"\n  ❌ industry-sample: {e}")
        elif "final-draft-style" in path:
            try:
                assert diag.scene_count == 2, f"expected 2 scenes, got {diag.scene_count}"
                assert diag.had_title_page, "expected a title page"
                cues = [e.text for s in doc.scenes for e in s.elements
                        if e.kind == "character"]
                # MORE / CONT'D markers must be stripped — final cue list
                # should be only real character names.
                assert "(MORE)" not in cues, "(MORE) leaked into character cues"
                # No cue should still carry "(CONT'D)" or "(V.O.)" suffix.
                for c in cues:
                    assert not c.endswith(")"), f"unstripped suffix on cue {c!r}"
                # Scene-number prefix must NOT have ended up in the heading.
                for s in doc.scenes:
                    assert not s.heading.startswith("1 "), \
                        f"scene number leaked into heading: {s.heading!r}"
                    assert not s.heading.startswith("2 "), \
                        f"scene number leaked into heading: {s.heading!r}"
                # Stitched dialogue: "RAVI (V.O.)" said two lines split by a
                # page break with (MORE)/(CONT'D). The combined dialogue
                # should contain both halves of the sentence.
                ravi_lines = [
                    e.text for s in doc.scenes for e in s.elements
                    if e.kind == "dialogue"
                ]
                joined = " ".join(ravi_lines)
                assert "twenty-three forty-five" in joined, \
                    "missing first half of split dialogue"
                # The second half ("board.") was on the next page; the
                # parser should still have it as a dialogue block.
                assert any("board" in t for t in ravi_lines), \
                    "missing second half of split dialogue"
                print("\n  ✅ final-draft-style: all invariants passed")
            except AssertionError as e:
                failures.append(f"final-draft-style: {e}")
                print(f"\n  ❌ final-draft-style: {e}")
        elif "wonky-template" in path:
            try:
                assert diag.scene_count == 2, f"expected 2 scenes, got {diag.scene_count}"
                cue_count = sum(1 for s in doc.scenes for e in s.elements
                                if e.kind == "character")
                assert cue_count >= 2, f"expected ≥2 character cues, got {cue_count}"
                # Even with no column structure, ALL CAPS short lines
                # must be promoted to character cues by the fallback.
                names = {e.text for s in doc.scenes for e in s.elements
                         if e.kind == "character"}
                assert "BOB" in names and "ALICE" in names, \
                    f"missing expected cues, got {names}"
                print("\n  ✅ wonky-template: all invariants passed")
            except AssertionError as e:
                failures.append(f"wonky-template: {e}")
                print(f"\n  ❌ wonky-template: {e}")
        else:
            if diag.scene_count == 0:
                failures.append(f"{label}: zero scenes detected")
            else:
                print(f"\n  ✅ {label}: {diag.scene_count} scenes parsed")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(" -", f)
        return 1
    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
