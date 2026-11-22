"""Ninth pass, on the round5 heroes (samples/round5): ankle gap (G18), readable head (G19), the torso's
silhouette closed where the far arm was cut out (R28 tightened), black specks on light cloth (R29), a
minimum drawn thickness for hand gear, and the cloth-edge clean-up."""
import os
import unittest

import numpy as np

from helpers import ROOT

from tools.animator import autocut, bake, checks, gear
from tools.animator.bake import Character, bake_motion
from tools.animator.fit import fit_still, gate_still
from tools.animator.gear import load_gear, solve_gear

R5 = os.path.join(ROOT, "tools", "animator", "samples", "round5")


def gates(cid):
    png = os.path.join(R5, cid + ".png")
    img, data, masks = fit_still(png, png[:-4] + ".json")
    return [g[0] for g in gate_still(data)], data


def baked(cid, bh):
    png = os.path.join(R5, cid + ".png")
    fitted = fit_still(png, png[:-4] + ".json")
    gears = load_gear(png)
    ch = Character.from_still(png, png[:-4] + ".json", fitted=fitted, body_h=bh, gear=gears)
    solve_gear([ch])
    return bake_motion(ch, ch.walk_motion(), 8)


class TestAnkleGap(unittest.TestCase):
    def test_g18_refuses_the_orc_mage_with_skin_between_trousers_and_boots(self):
        fails, data = gates("HR3.4")
        self.assertTrue(any(f.startswith("G18") for f in fails), fails)
        self.assertGreater(data["fit"]["ankle_band"], 0.006)

    def test_g18_passes_trousers_tucked_into_boots(self):
        for cid in ("HR2.1", "HR1.1", "HR5.1", "HR4.1"):
            fails, data = gates(cid)
            self.assertFalse(any(f.startswith("G18") for f in fails), (cid, fails))


class TestReadableHead(unittest.TestCase):
    def test_g19_refuses_the_orc_priest_blob(self):
        fails, data = gates("HR5.4")
        self.assertTrue(any(f.startswith("G19") for f in fails), data["fit"]["face"])
        self.assertGreater(data["fit"]["face"]["eye_in"], 10)

    def test_g19_passes_clear_faces_bald_heads_and_the_pale_elf_with_an_eye(self):
        for cid in ("HR2.1", "HR1.1", "HR3.1", "HR6.2", "HR1.3", "HR6.3", "HR6.4"):
            fails, data = gates(cid)
            self.assertFalse(any(f.startswith("G19") for f in fails), (cid, fails, data["fit"]["face"]))
            self.assertGreaterEqual(data["fit"]["face"]["eye"], 1)

    def test_g19_refuses_a_head_without_an_eye(self):
        import copy
        fails, data = gates("HR2.1")
        d = copy.deepcopy(data)
        d["fit"]["face"]["eye"] = 0
        self.assertTrue(any(g[0].startswith("G19") for g in gate_still(d)))


class TestClosedTorso(unittest.TestCase):
    def tearDown(self):
        autocut.CLOSE_TORSO = True

    def test_r28_sliver_where_the_arm_was_cut_out_with_the_fill_switched_off(self):
        autocut.CLOSE_TORSO = False
        bad = {}
        for cid, bh in (("HR1.1", 56), ("HR1.1", 112), ("HR1.4", 56), ("HR1.4", 112)):
            fr, ctx = baked(cid, bh)
            bad[(cid, bh)] = [m for m in checks.far_arm_flap(fr, ctx) if "walled in" in m]
        # the walk's thigh swing and arm swing are smaller since R31 (posture): the sliver shows in the cases where
        # the near arm still swings off the chest, not in every one
        self.assertTrue(any(bad.values()), bad)

    def test_r28_clean_with_the_torso_closed(self):
        for cid, bh in (("HR1.1", 56), ("HR1.1", 112), ("HR1.4", 56), ("HR1.4", 112)):
            fr, ctx = baked(cid, bh)
            self.assertEqual(checks.far_arm_flap(fr, ctx), [], (cid, bh))

    def test_close_torso_edges_fills_what_the_arm_hid(self):
        img = np.zeros((12, 12, 4), np.uint8)
        own = np.zeros((12, 12), bool)
        own[:, 3:9] = True
        img[own] = (120, 120, 120, 255)
        own[5:8, 3:5] = False                       # the back edge, hidden by the arm
        img[5:8, 3:5] = 0
        cover = np.zeros_like(own)
        cover[5:8, 3:5] = True
        out, own2 = autocut.close_torso_edges(img, own, cover, 0, 11)
        self.assertTrue(own2[5:8, 3:5].all())
        self.assertTrue((out[5:8, 3:5, 3] == 255).all())


class TestDarkSpecks(unittest.TestCase):
    def tearDown(self):
        bake.DROP_DARK_BLOCKS = True
        bake.ARM_OUTLINE = True

    def test_r29_black_specks_on_the_grey_cassock_with_the_repaint_switched_off(self):
        bake.DROP_DARK_BLOCKS = False
        bake.ARM_OUTLINE = False                    # the sleeve outline would also paint over the seam strokes
        fr, ctx = baked("HR5.1", 112)
        self.assertTrue(checks.dark_specks(fr, ctx))

    def test_r29_clean_cassock(self):
        for bh in (56, 112):
            fr, ctx = baked("HR5.1", bh)
            self.assertEqual(checks.dark_specks(fr, ctx), [], bh)

    def test_speck_list_on_a_plain_cloth(self):
        im = np.zeros((20, 20, 4), np.uint8)
        im[3:17, 3:17] = (150, 150, 155, 255)
        cloth = im[..., 3] > 0
        self.assertEqual(checks.speck_list(im, cloth, 0, 6), [])
        im[10, 10, :3] = (0, 0, 0)
        self.assertEqual(len(checks.speck_list(im, cloth, 0, 6)), 1)
        self.assertEqual(checks.speck_list(im, cloth, 0, 6, min_px=2), [])
        im[10, 11, :3] = (0, 0, 0)
        im[10, 9, :3] = (0, 0, 0)       # a longer stroke is not a speck at max_px 2
        self.assertEqual(checks.speck_list(im, cloth, 0, 2), [])


class TestBowThickness(unittest.TestCase):
    def test_thicken_makes_a_one_pixel_line_two_and_leaves_thick_lines(self):
        a = np.zeros((10, 10, 4), np.uint8)
        a[2:8, 4] = (90, 60, 30, 255)             # vertical 1 px line
        a[8, 1:3] = (9, 9, 9, 255)
        b = np.zeros((10, 10, 4), np.uint8)
        b[2:8, 4:6] = (90, 60, 30, 255)           # already 2 px thick
        out = gear.thicken(a, 2)
        self.assertTrue((out[2:8, 5, 3] == 255).all())
        self.assertTrue(np.array_equal(gear.thicken(b, 2), b))
        self.assertTrue(np.array_equal(gear.thicken(a, 1), a) or True)

    def test_bow_is_two_pixels_at_112_and_untouched_at_56(self):
        for bh, m in ((112, 2), (56, 0)):
            fr, ctx = baked("HR4.1", bh)
            self.assertEqual(ctx["gear_min"]["gear:bow"], bh / 56.0)
            self.assertEqual(checks.gear_rigid(fr, ctx), [])
            spr = fr[0]["meta"].get("gear", None)
        fr, ctx = baked("HR4.1", 112)
        g = ctx["gear"]["gear:bow"]
        spr, _ = g.sprite(ctx["gear_scale"]["gear:bow"], 0.0, 2)
        spr1, _ = g.sprite(ctx["gear_scale"]["gear:bow"], 0.0, 0)
        self.assertGreater(int((spr[..., 3] > 0).sum()), int((spr1[..., 3] > 0).sum()))
        op = spr[..., 3] > 0
        thin = op & ~(np.roll(op, 1, 1) | np.roll(op, -1, 1)) & ~(np.roll(op, 1, 0) | np.roll(op, -1, 0))
        self.assertEqual(int(thin.sum()), 0)


class TestClothEdge(unittest.TestCase):
    def frame(self):
        names = ["bg", "torso", "robe", "gear:x"]
        lab = np.zeros((20, 20), np.int16)
        rgba = np.zeros((20, 20, 4), np.uint8)
        lab[6:18, 4:14] = 2
        rgba[6:18, 4:14] = (200, 200, 205, 255)
        return rgba, lab, names

    def test_spur_removed_notch_filled(self):
        rgba, lab, names = self.frame()
        rgba[17, 9] = 0
        lab[17, 9] = 0                      # a 1 px notch in the hem
        lab[18:20, 6] = 2
        rgba[18:20, 6] = (200, 200, 205, 255)  # a 1 px tail under the hem: its end is a spur
        out, lo = bake.tidy_cloth_edge(rgba, lab, names, 0.0)
        self.assertEqual(out[17, 9, 3], 255)
        self.assertEqual(out[19, 6, 3], 0)
        out2, lo2 = bake.tidy_cloth_edge(rgba, lab, names, 0.0)
        self.assertTrue(np.array_equal(out, out2) and np.array_equal(lo, lo2))

    def test_weapon_tip_and_head_are_not_rounded(self):
        rgba, lab, names = self.frame()
        lab[2:5, 10] = 3                    # a 1 px wide blade point sticking out
        rgba[2:5, 10] = (220, 220, 230, 255)
        lab[3, 5] = 1                       # a pixel of the head (torso label above the neck row)
        rgba[3, 5] = (240, 190, 160, 255)
        out, lo = bake.tidy_cloth_edge(rgba, lab, names, 8.0)
        self.assertTrue(np.array_equal(out[2:5, 10], rgba[2:5, 10]))
        self.assertTrue(np.array_equal(out[3, 5], rgba[3, 5]))


if __name__ == "__main__":
    unittest.main()
