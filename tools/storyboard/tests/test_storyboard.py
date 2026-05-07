"""Tests for the storyboard pipeline.

Run from repo root:
    python3 tools/storyboard/tests/test_storyboard.py
"""
from __future__ import annotations
import os
import sys
import tempfile
import unittest

THIS = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.dirname(THIS)
ROOT = os.path.dirname(os.path.dirname(TOOL))
sys.path.insert(0, TOOL)

import fountain  # noqa: E402
import shotlist  # noqa: E402


SAMPLE_PATH = os.path.join(TOOL, "samples", "chai.fountain")


# ---- Parser ---------------------------------------------------------

class FountainParserTests(unittest.TestCase):

    def setUp(self):
        with open(SAMPLE_PATH, encoding="utf-8") as f:
            self.doc = fountain.parse(f.read())

    def test_title_page(self):
        self.assertEqual(self.doc.title_page.get("title"), "A CUP OF CHAI")
        self.assertEqual(self.doc.title_page.get("author"), "Penova Test")

    def test_scene_count(self):
        self.assertEqual(len(self.doc.scenes), 2)

    def test_first_scene_heading(self):
        self.assertEqual(
            self.doc.scenes[0].heading,
            "INT. MUMBAI TEA STALL - DAY",
        )

    def test_character_cues_extracted(self):
        cues = [
            e.text for s in self.doc.scenes for e in s.elements
            if e.kind == "character"
        ]
        self.assertIn("PRIYA", cues)
        self.assertIn("RAJA", cues)

    def test_dialogue_carries_speaker(self):
        for s in self.doc.scenes:
            for e in s.elements:
                if e.kind == "dialogue":
                    self.assertIsNotNone(e.character,
                                         f"dialogue without speaker: {e.text!r}")

    def test_first_dialogue_text(self):
        first_dialogue = next(
            e for s in self.doc.scenes for e in s.elements
            if e.kind == "dialogue"
        )
        self.assertEqual(first_dialogue.character, "PRIYA")
        self.assertEqual(first_dialogue.text, "One chai. Extra strong.")

    def test_parenthetical_recognised(self):
        parens = [
            e for s in self.doc.scenes for e in s.elements
            if e.kind == "parenthetical"
        ]
        self.assertGreaterEqual(len(parens), 2)
        self.assertTrue(all(e.text.startswith("(") and e.text.endswith(")")
                            for e in parens))

    def test_transitions_recognised(self):
        kinds = [
            e.kind for s in self.doc.scenes for e in s.elements
        ]
        self.assertIn("transition", kinds)
        # Both CUT TO: and FADE OUT.
        transitions = [
            e.text for s in self.doc.scenes for e in s.elements
            if e.kind == "transition"
        ]
        self.assertTrue(any("CUT TO" in t for t in transitions))
        self.assertTrue(any("FADE OUT" in t for t in transitions))

    def test_action_present(self):
        actions = [
            e.text for s in self.doc.scenes for e in s.elements
            if e.kind == "action"
        ]
        self.assertGreater(len(actions), 0)
        # First action paragraph should mention the kettle.
        self.assertTrue(any("kettle" in a.lower() for a in actions))

    def test_no_blank_elements(self):
        for s in self.doc.scenes:
            for e in s.elements:
                self.assertTrue(e.text.strip(),
                                f"empty {e.kind} element survived")

    def test_extra_strong_dialogue_not_swallowed_as_cue(self):
        # "One chai. Extra strong." has periods — must not be misclassified
        # as a character cue even though the line is short.
        cues = {e.text for s in self.doc.scenes for e in s.elements
                if e.kind == "character"}
        self.assertNotIn("ONE CHAI. EXTRA STRONG.", cues)

    def test_cue_with_voiceover_suffix_stripped(self):
        # Synthetic check: parse a snippet with (V.O.).
        snippet = (
            "INT. ROOM - NIGHT\n\n"
            "RAJA (V.O.)\n"
            "I remember.\n"
        )
        d = fountain.parse(snippet)
        cues = [e.text for s in d.scenes for e in s.elements
                if e.kind == "character"]
        self.assertEqual(cues, ["RAJA"])


# ---- Shot list ------------------------------------------------------

class ShotListTests(unittest.TestCase):

    def setUp(self):
        with open(SAMPLE_PATH, encoding="utf-8") as f:
            self.doc = fountain.parse(f.read())
        self.shots = shotlist.build(self.doc)

    def test_first_shot_is_slug(self):
        self.assertEqual(self.shots[0].kind, "slug")

    def test_one_slug_per_scene(self):
        slug_count = sum(1 for s in self.shots if s.kind == "slug")
        self.assertEqual(slug_count, len(self.doc.scenes))

    def test_all_dialogue_has_speaker(self):
        for s in self.shots:
            if s.kind == "dialogue":
                self.assertIsNotNone(s.character)

    def test_durations_positive(self):
        for s in self.shots:
            self.assertGreater(s.duration_s, 0)

    def test_total_duration_reasonable(self):
        # For the chai sample: total animatic should fall between 30 and
        # 180 s — sanity bound that catches runaway timing heuristics.
        total = sum(s.duration_s for s in self.shots)
        self.assertGreater(total, 30)
        self.assertLess(total, 180)

    def test_locations_classified(self):
        locs = {s.location for s in self.shots if s.kind == "slug"}
        self.assertIn("INT", locs)
        self.assertIn("EXT", locs)

    def test_parenthetical_attached_to_following_dialogue(self):
        # First dialogue with a parenthetical in the sample is RAJA's
        # "Strong like pichhle baar?" preceded by "(without looking up)".
        for i, s in enumerate(self.shots):
            if (s.kind == "dialogue"
                    and s.character == "RAJA"
                    and "pichhle" in s.text):
                self.assertIsNotNone(s.parenthetical)
                self.assertIn("looking up", s.parenthetical or "")
                return
        self.fail("expected dialogue not found")


# ---- Renderer & stitcher (smoke) -----------------------------------

class RenderSmokeTests(unittest.TestCase):

    def test_render_pose_returns_image(self):
        # Imported lazily so parser tests still run on machines without
        # Pillow installed.
        from render import render_pose
        with open(SAMPLE_PATH, encoding="utf-8") as f:
            doc = fountain.parse(f.read())
        shots = shotlist.build(doc)
        # First dialogue shot — exercises figure + bubble path.
        d = next(s for s in shots if s.kind == "dialogue")
        img = render_pose(d, 0)
        self.assertEqual(img.size, (1280, 720))

    def test_pipeline_writes_mp4(self):
        # Full end-to-end smoke. Trim shots so the test is fast.
        from stitch import write_mp4
        with open(SAMPLE_PATH, encoding="utf-8") as f:
            doc = fountain.parse(f.read())
        shots = shotlist.build(doc)[:3]   # slug + first action + first dialogue
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "smoke.mp4")
            n = write_mp4(shots, out, fps=8, hold=2)
            self.assertGreater(n, 0)
            self.assertGreater(os.path.getsize(out), 1024)
            # Read it back to confirm it's a valid file ffmpeg-side.
            import imageio.v2 as imageio
            r = imageio.get_reader(out)
            try:
                first = r.get_data(0)
                self.assertEqual(first.shape[2], 3)
            finally:
                r.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
