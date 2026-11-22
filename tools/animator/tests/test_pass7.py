"""Seventh pass, on the real run24 stills (samples/run24): hand gear solved clear of the legs and
head (R23, R25), the far hand tucked on the pixels (R27), one far-arm treatment (R28), and bare
shins refused at the input (G16)."""
import copy
import os
import unittest

import numpy as np

from helpers import ROOT

from tools.animator import bake, checks, gear
from tools.animator.bake import Character, bake_motion
from tools.animator.fit import fit_still, gate_still
from tools.animator.gear import load_gear, solve_gear

RUN = os.path.join(ROOT, "tools", "animator", "samples", "run24")


def png_of(cid):
    p = os.path.join(RUN, cid + ".png")
    return p if os.path.exists(p) else os.path.join(RUN, "refused", cid + ".png")


def build(cid, sizes=(56, 112), solve=True):
    png = png_of(cid)
    fitted = fit_still(png, png[:-4] + ".json")
    gears = load_gear(png)
    chs = {bh: Character.from_still(png, png[:-4] + ".json", fitted=fitted, body_h=bh, gear=gears)
           for bh in sizes}
    solved = solve_gear(list(chs.values())) if solve else {}
    return chs, solved


def bake8(ch):
    return bake_motion(ch, ch.walk_motion(), 8)


class TestGearSolved(unittest.TestCase):
    """Fault A: R25 (and R23) true by construction, per character, at both sizes."""

    def test_greatsword_solved_clear_and_upright_at_both_sizes(self):
        chs, solved = build("HR2.3")
        rec = solved["gear:greatsword"]
        self.assertLessEqual(abs(rec["angle"] - rec["guide_angle"]), gear.SOLVE_SPAN)
        self.assertLessEqual(max(abs(t) for t in rec["tilt_deg"]), gear.SOLVE_UPRIGHT)
        for bh, ch in chs.items():
            fr, ctx = bake8(ch)
            self.assertEqual(checks.gear_legs(fr, ctx), [], bh)
            self.assertEqual(checks.gear_head(fr, ctx), [], bh)
            self.assertEqual(checks.run_all(fr, ctx), [], bh)

    def test_staff_gets_a_size_cap_when_the_angle_alone_cannot_clear_the_legs(self):
        chs, solved = build("HR3.1")
        rec = solved["gear:mage_staff"]
        self.assertLess(rec["cap"], 1.0)
        self.assertAlmostEqual(rec["size"], rec["guide_size"] * rec["cap"], 3)
        self.assertGreaterEqual(rec["clear_px"], 1)
        for bh, ch in chs.items():
            fr, ctx = bake8(ch)
            self.assertEqual(checks.run_all(fr, ctx), [], bh)

    def test_solved_values_are_recorded_in_the_batch_summary(self):
        import json
        import shutil
        import tempfile
        from tools.animator import batch
        d, o = tempfile.mkdtemp(), tempfile.mkdtemp()
        try:
            for f in ("HR2.1.png", "HR2.1.json"):
                shutil.copy(os.path.join(RUN, "refused", f), d)
            shutil.copytree(os.path.join(RUN, "refused", "HR2.1_gear"), os.path.join(d, "HR2.1_gear"))
            acc, rej = batch.run(d, o, counts=(8,), skf=False, log=lambda *a: None)
            self.assertEqual(rej, [])
            with open(os.path.join(o, "summary.json")) as fh:
                rec = json.load(fh)["HR2.1"]
            self.assertIn("angle", rec["gear_solved"]["gear:greatsword"])
        finally:
            shutil.rmtree(d, ignore_errors=True)
            shutil.rmtree(o, ignore_errors=True)


class TestCarryPose(unittest.TestCase):
    """Pass 8: long hand gear is carried upright from a forearm held forward at belt height."""

    def test_staff_upright_in_every_frame_with_the_hand_ahead_of_the_torso(self):
        chs, solved = build("HR5.2", sizes=(112,))
        rec = solved["gear:candle_staff"]
        self.assertTrue(rec["long"])
        self.assertLessEqual(max(abs(t) for t in rec["tilt_deg"]), gear.SOLVE_UPRIGHT)
        self.assertGreaterEqual(rec["clear_px"], 2)
        fr, ctx = bake8(chs[112])
        self.assertEqual(checks.run_all(fr, ctx), [])
        for f in fr:                         # the wrist is ahead of the shoulder, below it, near belt height
            J = f["meta"]["joints"]
            self.assertGreater(J["near.wrist"][0] - J["near.shoulder"][0], 0.1 * ctx["body_h"])
            self.assertLess(J["near.wrist"][1], J["near.hip"][1] + 0.1 * ctx["body_h"])
        sw = [f["meta"]["pose"]["near"]["upper"] for f in fr]
        self.assertLess(max(sw) - min(sw), 12.0)                  # a bob, not a swing

    def test_short_gear_keeps_its_swing_pose(self):
        chs, solved = build("HR6.1", sizes=(56,))
        self.assertFalse(solved["gear:hammer"]["long"])
        self.assertFalse(getattr(chs[56].walk_motion(), "carry", False))

    def test_grip_a_third_up_the_staff(self):
        chs, solved = build("HR5.2", sizes=(56,))
        o = solved["gear:candle_staff"]["orientation"]
        g = chs[56].gear[0]
        ys = np.flatnonzero(g.mask.any(1))
        frac = (ys[-1] + 1 - g.anchor[1]) / (ys[-1] - ys[0] + 1)
        self.assertAlmostEqual(frac, 0.33, delta=0.03)
        self.assertIn("anchor moved", o["status"])


class TestGrip(unittest.TestCase):
    """G17: the hand grips the handle (pass 8: the knight held the greatsword by its tip)."""

    def _gear(self, keep):
        import json
        from PIL import Image
        d = os.path.join(RUN, "refused", "HR2.1_gear")
        spec_ = json.load(open(os.path.join(d, "greatsword.json")))
        if keep:
            spec_["orient"] = "keep"
        return gear.Gear("greatsword", Image.open(os.path.join(d, "greatsword.png")).convert("RGBA"), spec_)

    def test_g17_greatsword_gripped_by_the_blade(self):
        g = self._gear(keep=True)            # as drawn: pommel at the top, the anchor low on the blade
        out = gear.gate_gear([g])
        self.assertTrue(any(t.startswith("G17") for t, _ in out), out)
        self.assertEqual(g.orient["status"], "wrong (kept)")

    def test_g17_passes_when_turned(self):
        g = self._gear(keep=False)
        self.assertEqual(gear.gate_gear([g]), [])
        self.assertTrue(g.orient["status"].startswith("turned"))
        self.assertEqual(g.orient["grip_end"], "bottom")
        # the anchor is on the hilt: below the crossguard (the widest row), above the pommel end
        ys = np.flatnonzero(g.mask.any(1))
        guard = ys[0] + int(np.argmax(g.mask[ys[0]:ys[-1] + 1].sum(1)))
        self.assertGreater(g.anchor[1], guard)
        self.assertLess(g.anchor[1], ys[-1])

    def test_hammers_dirks_and_staffs_are_left_alone(self):
        for cid, nm in (("HR6.1", "hammer"), ("HR1.1", "dirk")):
            g = [x for x in load_gear(png_of(cid)) if x.name == nm][0]
            self.assertEqual(g.orient["status"], "ok", cid)
            self.assertEqual(g.orient["anchor"], g.orient["anchor_before"], cid)

    def test_batch_summary_records_the_turn(self):
        chs, solved = build("HR2.1", sizes=(56,))
        o = solved["gear:greatsword"]["orientation"]
        self.assertIn("turned", o["status"])
        self.assertNotEqual(o["anchor"], o["anchor_before"])


class TestFarHandTuck(unittest.TestCase):
    def test_elf_paladin_far_hand_hidden_at_both_sizes(self):
        chs, _ = build("HR6.2")
        for bh, ch in chs.items():
            fr, ctx = bake8(ch)
            self.assertEqual(checks.far_hand_hidden(fr, ctx), [], bh)
            self.assertEqual(checks.run_all(fr, ctx), [], bh)

    def test_the_far_forearm_is_the_shaded_near_one_not_the_skirt(self):
        """HR6.2's far hand "dangled" because the cut took its white skirt (hand-coloured) for the far
        hand and made it the far forearm (4220 px against the near one's 1589)."""
        chs, _ = build("HR6.2", sizes=(56,))
        ch = chs[56]
        self.assertEqual(ch.info["far_arm"], "copy of the near arm")
        self.assertLessEqual(int(ch.parts["far_fore"].mask.sum()), int(ch.parts["near_fore"].mask.sum()))


class TestFarArm(unittest.TestCase):
    """Fault C: one far-arm treatment, rule R28."""

    @classmethod
    def setUpClass(cls):
        chs, _ = build("HR1.2", sizes=(112,))
        cls.frames, cls.ctx = bake8(chs[112])

    def fresh(self):
        return [{"rgba": f["rgba"].copy(), "label": f["label"].copy(), "meta": copy.deepcopy(f["meta"])}
                for f in self.frames], self.ctx

    def test_passing_walk(self):
        self.assertEqual(checks.far_arm_flap(*self.fresh()), [])

    def test_r28_far_arm_behind_the_back(self):
        fr, ctx = self.fresh()
        names = fr[3]["meta"]["labels"]
        tm = fr[3]["label"] == names.index("torso")
        y = int(np.flatnonzero(tm.any(1))[len(np.flatnonzero(tm.any(1))) // 2])
        x = int(np.flatnonzero(tm[y])[0])
        fr[3]["label"][y, x - 3:x - 1] = names.index("far_fore")
        out = checks.far_arm_flap(fr, ctx)
        self.assertTrue(any("behind the torso's back edge" in o for o in out), out)
        self.assertEqual(checks.rule_id(out[0]), "R28")

    def test_r28_detached_far_arm(self):
        fr, ctx = self.fresh()
        names = fr[2]["meta"]["labels"]
        H, W = fr[2]["label"].shape
        fr[2]["label"][H - 10:H - 7, W - 12:W - 8] = names.index("far_upper")      # floats in the air
        out = checks.far_arm_flap(fr, ctx)
        self.assertTrue(any("detached arm" in o for o in out), out)

    def test_r28_gap_in_the_torso(self):
        fr, ctx = self.fresh()
        names = fr[1]["meta"]["labels"]
        lab = fr[1]["label"]
        tm = lab == names.index("torso")
        J = fr[1]["meta"]["joints"]
        y = int((J["neck"][1] + J["pelvis"][1]) / 2)
        xs = np.flatnonzero(tm[y])
        lab[y, xs[0] + 3:xs[0] + 5] = 0
        out = checks.far_arm_flap(fr, ctx)
        self.assertTrue(any("gap in the torso" in o for o in out), out)

    def test_real_flap_of_the_still_without_the_hiding(self):
        """HR1.1 frame 5: the grey flap behind the back hip came back when the cut's far arm is drawn
        as it was."""
        chs, _ = build("HR1.1", sizes=(112,))
        real = bake.hide_far_behind_torso
        try:
            bake.hide_far_behind_torso = lambda rgba, lab, names: (rgba, lab)
            fr, ctx = bake8(chs[112])
        finally:
            bake.hide_far_behind_torso = real
        self.assertTrue(checks.far_arm_flap(fr, ctx))
        fr, ctx = bake8(chs[112])
        self.assertEqual(checks.far_arm_flap(fr, ctx), [])

    def test_r28_real_elf_archer_arm_cut_into_the_cape(self):
        """HR4.2: the drawn far arm's sleeve behind the back went into the cape cut: a wedge behind the
        shoulder and a ribbon down the back, in frames where R28 had nothing to say."""
        from tools.animator import autocut
        png = png_of("HR4.2")
        fitted = fit_still(png, png[:-4] + ".json")
        try:
            autocut.FAR_ARM_TO_ARM = False
            ch = Character.from_still(png, png[:-4] + ".json", fitted=fitted, body_h=112)
            fr, ctx = bake8(ch)
        finally:
            autocut.FAR_ARM_TO_ARM = True
        out = checks.far_arm_flap(fr, ctx)
        self.assertTrue(any("px of cape in the sleeve" in o for o in out), out)
        ch = Character.from_still(png, png[:-4] + ".json", fitted=fitted, body_h=112)
        fr, ctx = bake8(ch)
        self.assertEqual(checks.far_arm_flap(fr, ctx), [])

    def test_elf_archer_keeps_her_drawn_far_arm_and_the_paladin_loses_her_skirt_blob(self):
        png = png_of("HR4.2")           # the still draws a second arm behind the back: cut out, not left on the torso
        img, data, masks = fit_still(png, png[:-4] + ".json")
        self.assertEqual(data["far_arm"], "visible")
        png = png_of("HR6.2")           # the white skirt is no arm
        img, data, masks = fit_still(png, png[:-4] + ".json")
        self.assertEqual(data["far_arm"], "hidden")
        self.assertGreater(data["fit"]["far_blob_dropped"], 3000)


class TestBareShin(unittest.TestCase):
    """Fault D: G16."""

    def test_g16_refuses_the_pale_bare_shin_of_the_elf_mage_and_the_orc(self):
        for cid in ("HR3.2", "HR4.4"):
            png = png_of(cid)
            img, data, masks = fit_still(png, png[:-4] + ".json")
            self.assertTrue(any(g[0].startswith("G16") for g in gate_still(data)), cid)

    def test_g16_passes_trousers_boots_and_the_dwarf_whose_drawn_back_calf_is_bare(self):
        for cid in ("HR1.1", "HR2.2", "HR6.1", "HR3.3", "HR6.3"):
            png = png_of(cid)
            img, data, masks = fit_still(png, png[:-4] + ".json")
            self.assertFalse(any(g[0].startswith("G16") for g in gate_still(data)), cid)


if __name__ == "__main__":
    unittest.main()
