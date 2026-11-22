"""Intake (key colour G10 / R19, gear placement G11, the tightened G8), the native grid and the
two baked sizes, on the stills the art PC drew to STILL_SPEC.md (samples/stills_spec)."""
import copy
import os
import shutil
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw

from helpers import ROOT

from tools.animator import checks, fit, foot, intake, spec
from tools.animator.bake import BODY_SIZES, Character, bake_all
from tools.animator.fit import fit_still, gate_still, load_single

import test_animator

HERE = os.path.join(ROOT, "tools", "animator")
SPEC_STILLS = os.path.join(HERE, "samples", "stills_spec")
STILLS = os.path.join(HERE, "samples", "stills")
_FIT = {}


def spec_still(name):
    png = os.path.join(SPEC_STILLS, name + ".png")
    return png, png[:-4] + ".json"


def fitted(name):
    if name not in _FIT:
        _FIT[name] = fit_still(*spec_still(name))
    return _FIT[name]


def rules(data):
    return sorted({t.split(":")[0] for t, _ in gate_still(data)})


def figure(rim=None, patch=None):
    """A grey body with a dark outline; rim = colour of a 1-px rim round it (the half-keyed
    background), patch = colour of a 12 x 12 square in its middle (unkeyed background)."""
    im = Image.new("RGBA", (80, 120), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if rim:
        d.rectangle([19, 9, 60, 110], fill=rim + (255,))
    d.rectangle([20, 10, 59, 109], fill=(20, 18, 18, 255))
    d.rectangle([22, 12, 57, 107], fill=(120, 124, 130, 255))
    if patch:
        d.rectangle([34, 50, 45, 61], fill=patch + (255,))
    return np.array(im)


class TestKeyColour(test_animator.Base):
    """G10 (still) and R19 (baked frames): nothing of the background key's colour."""

    def test_clean_key_removes_fringe(self):
        a = figure(rim=(132, 8, 134))
        self.assertGreater(intake.key_mask(a).sum(), 200)
        out, n = intake.clean_key(a)
        self.assertGreater(n, 200)
        self.assertEqual(int(intake.key_mask(out).sum()), 0)
        self.assertTrue(((out[..., 3] > 0) == (a[..., 3] > 0)).all())       # same silhouette
        self.assertTrue(np.isin(out[..., 3], (0, 255)).all())               # hard alpha
        rim = (a[..., 3] > 0) & intake.key_mask(a)
        self.assertTrue((out[rim][:, :3] == (20, 18, 18)).all())            # the nearest inside colour
        inside = ~rim
        self.assertTrue((out[inside] == a[inside]).all())                   # nothing else touched

    def test_clean_key_leaves_real_purple_inside(self):
        a = figure(patch=(150, 60, 190))          # a purple cloth patch: not the key's colour
        out, n = intake.clean_key(a)
        self.assertEqual(n, 0)
        self.assertTrue((out == a).all())

    def test_spec_stills_fringe_is_cleaned_at_intake(self):
        for name in ("HR6.1", "HR6.2", "HR6.4"):
            raw = np.array(Image.open(spec_still(name)[0]).convert("RGBA"))
            self.assertGreater(int(intake.key_mask(raw).sum()), 800, name)   # the purple rim
            self.assertEqual(int(intake.key_mask(load_single(spec_still(name)[0])).sum()), 0, name)
            self.assertEqual(fitted(name)[1]["fit"]["key_px"], 0, name)

    def test_g10_key_colour_left_in_still(self):
        # failing example: a patch of unkeyed magenta in the middle of the body is not a rim,
        # clean_key leaves it, and the gate refuses the still
        tmp = tempfile.mkdtemp()
        try:
            png, js = spec_still("HR6.1")
            a = np.array(Image.open(png).convert("RGBA"))
            a[150:162, 170:182] = (255, 0, 255, 255)
            p2 = os.path.join(tmp, "K.png")
            Image.fromarray(a).save(p2)
            _, data, _ = fit_still(p2, js)
            self.assertEqual(data["fit"]["key_px"], 144)
            out = [t for t, _ in gate_still(data)]
            self.assertTrue(any(t.startswith("G10: key_colour") for t in out), out)
        finally:
            shutil.rmtree(tmp)
        self.assertNotIn("G10", rules(fitted("HR6.1")[1]))

    def test_r19_key_colour_in_frame(self):
        fr, ctx = self.fresh()
        self.assertEqual(checks.key_colour(fr, ctx), [])
        ys, xs = np.where(fr[3]["rgba"][..., 3] > 0)
        fr[3]["rgba"][ys[0], xs[0], :3] = (131, 9, 133)        # one pixel of the rim's purple
        self.rule_fails(checks.key_colour, fr, ctx, "key_colour")
        self.assertEqual(checks.rule_id(checks.key_colour(fr, ctx)[0]), "R19")

    def test_baked_frames_of_a_fringed_still_have_no_key_colour(self):
        png, js = spec_still("HR6.1")
        for bh in BODY_SIZES:
            ch = Character.from_still(png, js, fitted=fitted("HR6.1"), body_h=bh)
            fr, ctx, fails = bake_all(ch, (8,))[8]
            self.assertEqual(sum(int(intake.key_mask(f["rgba"]).sum()) for f in fr), 0, bh)
            self.assertEqual(fails, [], bh)


class TestGearPlacement(unittest.TestCase):
    """G11: a shield (rimmed gear blob) over the torso's front / the near arm is refused."""

    def test_g11_shield_on_near_side(self):
        # failing example: HR6.2 on spec carries its shield on the near side, over the arm
        data = fitted("HR6.2")[1]
        blobs = data["fit"]["gear_blobs"]
        self.assertEqual(len(blobs), 1)
        self.assertGreater(blobs[0]["front"], 0.8)                 # 0.88 measured, limit 0.25
        self.assertGreater(blobs[0]["area"], 4 * intake.GEAR_MIN)
        out = [t for t, _ in gate_still(data)]
        self.assertTrue(any(t.startswith("G11: gear_on_near_side") and "shield" in t for t in out), out)

    def test_shield_on_the_back_passes(self):
        data = fitted("HR6.1")[1]
        blobs = data["fit"]["gear_blobs"]
        self.assertEqual(len(blobs), 1)                            # its shield is found too ...
        self.assertLess(blobs[0]["front"], 0.05)                   # ... wholly behind the trunk axis
        self.assertNotIn("G11", rules(data))

    def test_g11_threshold(self):
        d = copy.deepcopy(fitted("HR6.1")[1])
        d["fit"]["gear_blobs"][0]["front"] = intake.GEAR_FRONT_MAX + 0.01
        self.assertIn("G11", rules(d))
        d["fit"]["gear_blobs"][0]["front"] = intake.GEAR_FRONT_MAX - 0.01
        self.assertNotIn("G11", rules(d))

    def test_rimmed_blob_is_found_and_plain_cloth_is_not(self):
        im = Image.new("RGBA", (200, 300), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rectangle([60, 20, 140, 280], fill=(90, 96, 110, 255))                       # a plain body
        body = np.array(im)[..., 3] > 0
        self.assertEqual(intake.rimmed_blobs(np.array(im), body, 260.0), [])
        d.ellipse([70, 90, 130, 170], fill=(200, 160, 40, 255))                        # a gold rim ...
        d.ellipse([75, 95, 125, 165], fill=(60, 20, 20, 255))                          # ... round a field
        blobs = intake.rimmed_blobs(np.array(im), body, 260.0)
        self.assertEqual(len(blobs), 1)
        ys, xs = np.where(blobs[0][0])
        self.assertTrue(68 <= xs.min() <= 76 and 124 <= xs.max() <= 132, (xs.min(), xs.max()))


class TestArmOverlap(unittest.TestCase):
    """G8 tightened: hand-coloured area over the body is summed and refused from 0.15 of a hand
    (one blob of 0.50 was needed before, and the hand's colour was read off a held hammer)."""

    def test_g8_partly_overlapping_arm_on_spec_still(self):
        # failing example: HR6.4 on spec, a fist over the shield and the body
        s = {n: fitted(n)[1]["fit"]["arm_overlap"] for n in ("HR6.1", "HR6.2", "HR6.4")}
        self.assertEqual((s["HR6.1"], s["HR6.2"]), (0, 0), s)
        self.assertGreater(s["HR6.4"], 10 * fit.ARM_OVERLAP_MAX, s)        # 2.62 measured, limit 0.15
        self.assertIn("G8", rules(fitted("HR6.4")[1]))
        self.assertNotIn("G8", rules(fitted("HR6.1")[1]))
        self.assertNotIn("G8", rules(fitted("HR6.2")[1]))
        self.assertTrue(fitted("HR6.4")[1]["fit"]["arm_from_layout"])      # the hand, not the hammer

    def test_g8_small_blobs_add_up(self):
        base = copy.deepcopy(fitted("HR6.1")[1])
        hand = {"at": [190.0, 240.0], "zone": "inside", "w": 9, "h": 9, "kind": "hand", "reach": 0.9}
        d = copy.deepcopy(base)
        d["fit"]["hands"] = [dict(hand, area=0.2)]              # passed the old 0.50 limit
        self.assertIn("G8", rules(d))
        d["fit"]["hands"] = [dict(hand, area=0.08), dict(hand, area=0.08)]      # two knuckles: 0.16
        self.assertIn("G8", rules(d))
        d["fit"]["hands"] = [dict(hand, area=0.10)]             # under the limit
        self.assertNotIn("G8", rules(d))
        self.assertLess(fit.ARM_OVERLAP_MAX, fit.HAND_AREA[0])  # tightened, never loosened


class TestNativeGrid(unittest.TestCase):
    def blocks(self, cell, n=(24, 30), seed=5):
        rng = np.random.RandomState(seed)
        pal = rng.randint(30, 255, (9, 3))
        idx = rng.randint(0, 9, (n[1], n[0]))
        small = np.concatenate([pal[idx], np.full((n[1], n[0], 1), 255)], -1).astype(np.uint8)
        return np.array(Image.fromarray(small, "RGBA").resize((n[0] * cell, n[1] * cell), Image.NEAREST)), small

    def test_detect_grid_on_enlarged_pixel_art(self):
        big, _ = self.blocks(6)
        g = intake.detect_grid(big)
        self.assertTrue(g["found"], g)
        self.assertAlmostEqual(g["cell"][0], 6.0, delta=0.1)
        self.assertAlmostEqual(g["cell"][1], 6.0, delta=0.1)

    def test_real_stills(self):
        g = intake.detect_grid(load_single(os.path.join(STILLS, "HR3.1.png")))
        self.assertTrue(g["found"], g)                         # real pixel art, 6 px blocks
        self.assertAlmostEqual(g["cell"][0], 6.0, delta=0.15)
        for name in ("HR6.1", "HR6.2", "HR6.4"):               # fake pixel art: no rigid grid
            g = intake.detect_grid(load_single(spec_still(name)[0]))
            self.assertFalse(g["found"], (name, g))
            self.assertLess(max(g["score"]), intake.GRID_SCORE)
            self.assertTrue(2.0 <= g["texel"] <= 5.0, g)

    def test_snap_gives_one_colour_per_block_from_the_picture(self):
        big, small = self.blocks(6)
        rng = np.random.RandomState(1)
        noisy = big.copy()
        m = rng.rand(*big.shape[:2]) < 0.2                     # 20 % of the pixels swapped about
        noisy[m] = big[rng.randint(0, big.shape[0], m.sum()), rng.randint(0, big.shape[1], m.sum())]
        out = intake.snap_to_grid(noisy, (6.0, 6.0), (0.0, 0.0))
        self.assertTrue((out == big).all())                    # the mode restores every block
        cols = {tuple(c) for c in out.reshape(-1, 4)}
        self.assertTrue(cols <= {tuple(c) for c in noisy.reshape(-1, 4)})

    def test_parts_are_flat_blocks_and_frames_keep_the_palette(self):
        png, js = spec_still("HR6.1")
        for bh in BODY_SIZES:
            ch = Character.from_still(png, js, fitted=fitted("HR6.1"), body_h=bh)
            self.assertTrue(ch.native)
            self.assertEqual(ch.canvas, (96 * bh // 56, 80 * bh // 56))
            c = 390.0 / bh                                      # still px per output pixel
            self.assertAlmostEqual(ch.grid["used_cell"][0], c, places=3)
            img = ch.parts["torso"].img
            ox, oy = ch.rig.j["pelvis"][0], ch.rig.ground_y
            ys, xs = np.where(img[..., 3] > 0)
            cid = np.floor((ys + 0.5 - oy) / c).astype(int) * 1000 + np.floor((xs + 0.5 - ox) / c).astype(int)
            col = img[ys, xs, 0].astype(int) * 65536 + img[ys, xs, 1].astype(int) * 256 + img[ys, xs, 2]
            order = np.argsort(cid)
            same = cid[order][1:] == cid[order][:-1]
            self.assertTrue((col[order][1:][same] == col[order][:-1][same]).all(), bh)
            fr, ctx, fails = bake_all(ch, (8,))[8]
            self.assertEqual(checks.palette(fr, ctx), [])
            self.assertEqual(fr[0]["rgba"].shape[:2], (ch.canvas[1], ch.canvas[0]))
            rows = np.flatnonzero((fr[2]["rgba"][..., 3] > 0).any(1))
            self.assertAlmostEqual(rows[-1] - rows[0] + 1, bh * ch.rig.body_height / 390.0, delta=0.05 * bh)

    def test_unturned_part_is_one_output_pixel_per_block(self):
        # the rest pose rendered at 112 px: the torso's pixels are its blocks, one to one
        from tools.animator.bake import render, reduce
        png, js = spec_still("HR6.1")
        ch = Character.from_still(png, js, fitted=fitted("HR6.1"), body_h=112)
        J = ch.rig.fk(ch.rig.rest_pose())
        rgba4, lab4, names = render(ch, J, order=["torso"])
        out, lab = reduce(rgba4, lab4, ch.ss, ch.native)
        ys, xs = np.where(out[..., 3] > 0)
        src = ch.from_game(np.stack([xs + 0.5, ys + 0.5], 1))
        want = ch.parts["torso"].img[src[:, 1].astype(int), src[:, 0].astype(int)]
        agree = (want[:, :3] == out[ys, xs, :3]).all(1) & (want[:, 3] > 0)
        self.assertGreater(agree.mean(), 0.97)


class TestTwoSizes(unittest.TestCase):
    def test_batch_bakes_56_and_112_and_shows_both(self):
        tmp = tempfile.mkdtemp()
        try:
            src = os.path.join(tmp, "in")
            os.makedirs(src)
            for ext in (".png", ".json"):
                shutil.copy(os.path.join(SPEC_STILLS, "HR6.1" + ext), os.path.join(src, "HR6.1" + ext))
            from tools.animator.batch import run
            acc, rej = run(src, os.path.join(tmp, "out"), skf=False, log=lambda *a: None)
            self.assertEqual(([c for c, _ in acc], rej), (["HR6.1"], []))
            d = os.path.join(tmp, "out", "accepted", "HR6.1")
            with Image.open(os.path.join(d, "HR6.1_walk8_r.png")) as a, \
                    Image.open(os.path.join(d, "h112", "HR6.1_walk8_r.png")) as b:
                self.assertEqual(a.size, (96 * 8, 80))
                self.assertEqual(b.size, (192 * 8, 160))
            with Image.open(os.path.join(tmp, "out", "contact.png")) as c:
                self.assertEqual(c.size[1], 16 + 2 * 80 * 4)        # two rows, the same height
        finally:
            shutil.rmtree(tmp)

    def test_pixel_tolerances_are_56px_pixels(self):
        self.assertEqual(checks._tol({}), 1.0)
        self.assertEqual(checks._tol({"size_x": 2.0}), 2.0)


class TestBoots(unittest.TestCase):
    """The dwarf layout asks for boots that are clearly long (G9 refused 6 of 6 dwarf stills)."""

    def test_layout_boots_are_long_in_every_build(self):
        for b in spec.BUILDS:
            n = spec.foot_numbers(b)
            self.assertGreaterEqual(n["foot_per_shin_width"], 1.6, b)
            self.assertGreaterEqual(n["toe_ahead"], 0.045, b)
            self.assertTrue(foot.FOOT_LEG[0] <= n["foot_per_leg"] <= foot.FOOT_LEG_STOCKY, (b, n))
        d = spec.foot_numbers("dwarf")
        self.assertGreaterEqual(d["foot_per_shin_width"], 2.2)
        self.assertGreaterEqual(d["toe_ahead"], 0.12)

    def test_dwarf_boot_survives_what_the_image_model_does_to_it(self):
        # shin 1.4 x as thick, boot 0.8 x as long as the layout asks: still no G9 fault
        from tools.animator.motion import STANCE_DORSI_MAX, SWING_ANKLE
        b = spec.BUILDS["dwarf"]
        bh = b["bh"]
        length = 0.8 * b["foot"] * bh
        half = 1.4 * b["r_shin"] * bh
        leg = (b["hip"] - b["ankle"]) * bh
        ah = b["ankle"] * bh
        flex = (-min(-SWING_ANKLE[0], foot.plantar_limit(half, ah, 5.5)), STANCE_DORSI_MAX)
        self.assertEqual(foot.foot_faults(length, leg, half, half, ah, flex), [])
        # the first layout (foot 0.150, shin 0.048, hip 0.38) did not survive it
        old = foot.foot_faults(0.8 * 0.150 * bh, (0.38 - 0.065) * bh, 1.4 * 0.048 * bh, 1.4 * 0.048 * bh, ah,
                               (-min(-SWING_ANKLE[0], foot.plantar_limit(1.4 * 0.048 * bh, ah, 5.5)), STANCE_DORSI_MAX))
        self.assertTrue(old)

    def test_heel_block_boot_stands_on_its_heel_and_toe(self):
        # a boot with a heel block and a sprung toe: the sole passes within 2 px of both the
        # block's rear corner and the toe's lowest pixel (the hull edge alone left the heel 5 px
        # in the air)
        m = np.zeros((120, 120), bool)
        m[10:92, 40:60] = True                 # shin
        m[88:100, 38:60] = True                # heel block, bottom row 99
        for x in range(60, 96):                # sole rising to the toe
            y = 99 - int(round((x - 60) * 0.22))
            m[y - 9:y + 1, x] = True
        f = foot.fit_foot(m, (50.0, 10.0), (50.0, 86.0), 10.0)
        self.assertIsNotNone(f)
        d = np.array(f["cut"][2:])
        sole = float((f["heel"] - np.array(f["seat"])) @ d)
        rear = float(np.array([38.5, 100.0]) @ d)
        toe = float(np.array([95.5, 99 - 8 + 1.0]) @ d)
        self.assertLess(abs(sole - rear), 4.5)
        self.assertLess(abs(sole - toe), 2.0)


if __name__ == "__main__":
    unittest.main()
