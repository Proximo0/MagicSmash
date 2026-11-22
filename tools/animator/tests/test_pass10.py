"""Tenth pass: the new gear kinds (crossbow, censer, book, scroll, banner, halo, off-hand weapon), the near arm
that vanishes into a coat of its own colour (R30), the key colour against violet and purple (G10), and thin gear
that stays one unbroken stroke."""
import os
import shutil
import tempfile
import unittest

import numpy as np

from helpers import ROOT

from tools.animator import bake, checks, gear, intake, spec
from tools.animator.bake import Character, bake_motion
from tools.animator.fit import fit_still
from tools.animator.gear import load_gear, solve_gear
from tools.animator.imgops import components

R5 = os.path.join(ROOT, "tools", "animator", "samples", "round5")
NEW = ("crossbow", "censer", "book", "scroll", "banner", "halo", "offhand_weapon")


def example(kind, bh=112):
    d = tempfile.mkdtemp()
    try:
        png = spec.write_example(d, "EX", "human", gear=((kind, kind),))
        fitted = fit_still(png, png[:-4] + ".json")
        gears = load_gear(png)
        ch = Character.from_still(png, png[:-4] + ".json", fitted=fitted, body_h=bh, gear=gears)
        solve_gear([ch])
        fr, ctx = bake_motion(ch, ch.walk_motion(), 8)
        return ch, fr, ctx
    finally:
        shutil.rmtree(d, ignore_errors=True)


class TestGuides(unittest.TestCase):
    def test_every_guide_has_picture_json_sentence_and_an_example_that_passes_g14(self):
        d = tempfile.mkdtemp()
        try:
            paths = spec.write_gear(d)
            self.assertEqual(set(paths), set(spec.GEAR_GUIDES))
            for k in NEW:
                self.assertIn(k, paths)
                g = spec.GEAR_GUIDES[k]
                self.assertIn(g["json"]["slot"], gear.SLOTS, k)
                self.assertEqual(g["json"]["guide"], k)
                self.assertTrue(g["words"])
                self.assertTrue(os.path.exists(paths[k][0]) and os.path.exists(paths[k][1]))
                gr = gear.Gear(k, spec.example_gear(k), g["json"])
                self.assertEqual(gear.gate_gear([gr]), [], k)
        finally:
            shutil.rmtree(d, ignore_errors=True)

    def test_shield_guide_asks_for_a_face_on_back_shield(self):
        self.assertIn("FACE-ON", spec.GEAR_GUIDES["shield"]["words"])

    def test_still_spec_lists_every_kind(self):
        with open(os.path.join(ROOT, "tools", "animator", "STILL_SPEC.md")) as f:
            txt = f.read()
        for k in spec.GEAR_GUIDES:
            self.assertIn("| " + k + " |", txt, k)


class TestNewGear(unittest.TestCase):
    def test_each_new_kind_bakes_clean_on_a_human(self):
        for k in NEW:
            ch, fr, ctx = example(k)
            self.assertEqual(checks.run_all(fr, ctx), [], k)

    def test_censer_hangs_straight_down_in_every_frame(self):
        ch, fr, ctx = example("censer")
        phis = {f["meta"]["gear"]["gear:censer"]["phi"] if "gear" in f["meta"] else None for f in fr}
        hashes = set()
        for f in fr:
            L = [v for k, v in f["gear_layers"].items()] if "gear_layers" in f else None
        g = ctx["gear"]["gear:censer"]
        # the sprite is the same picture at the same turn in all frames (R20 compares each frame with it)
        self.assertEqual(checks.gear_rigid(fr, ctx), [])
        ph = set()
        for f in fr:
            for nm, L in checks._gear_layers(f).items():
                ph.add(L["phi"])
        self.assertEqual(len(ph), 1)
        self.assertEqual(list(ph)[0], 0.0)

    def test_crossbow_is_carried_level_forward_and_a_little_down(self):
        ch, fr, ctx = example("crossbow")
        g = ctx["gear"]["gear:crossbow"]
        self.assertEqual(g.carry, "level")
        lo, hi = gear.HOLD_OF["level"]
        tl = gear._tilts(ch, g, gear._solve_frames(ch))
        self.assertTrue(all(lo <= t <= hi for t in tl), tl)
        self.assertTrue(all(t > 80 for t in tl))          # at or below the horizontal: not upright

    def test_book_held_against_the_chest_forearm_bent_up(self):
        ch, fr, ctx = example("book")
        self.assertEqual(ch.walk_motion().carry, "chest")
        for f in fr:
            J = f["meta"]["joints"]
            fore = np.array(J["near.wrist"]) - np.array(J["near.elbow"])
            self.assertLess(fore[1], 0)                    # the wrist is above the elbow

    def test_banner_cloth_stays_above_the_head(self):
        ch, fr, ctx = example("banner")
        g = ctx["gear"]["gear:banner"]
        self.assertTrue(g.long)
        for f in fr:
            L = checks._gear_layers(f)["gear:banner"]
            spr, (ox, oy) = L["rgba"], L["at"]
            op = spr[..., 3] > 0
            rows = np.flatnonzero(op.any(1))
            cloth_bottom = oy + rows[0] + int(0.30 * (rows[-1] - rows[0]))      # the top 30 % of the banner
            head_top = float(np.floor(f["meta"]["joints"]["head_top"][1]))
            self.assertLess(cloth_bottom, head_top)
            self.assertGreaterEqual(oy + rows[0], 0)                           # and the cloth is inside the canvas

    def test_halo_is_pinned_above_the_head_behind_it_and_bobs_with_it(self):
        ch, fr, ctx = example("halo")
        ys = []
        for f in fr:
            L = checks._gear_layers(f)["gear:halo"]
            self.assertEqual(L["slot"], "head")
            names = f["meta"]["labels"]
            self.assertLess(L["rank"], names.index("torso"))
            head_top = f["meta"]["joints"]["head_top"][1]
            ys.append(L["grip"][1] - head_top)
            op = L["rgba"][..., 3] > 0
            self.assertTrue(op.any())
        self.assertLess(max(ys) - min(ys), 1.5)           # it keeps its place on the head (whole pixels)
        tops = [checks._gear_layers(f)["gear:halo"]["at"][1] for f in fr]
        hts = [f["meta"]["joints"]["head_top"][1] for f in fr]
        self.assertGreater(len(set(hts)), 1)
        self.assertGreater(len(set(tops)), 1)             # it follows the head bob

    def test_offhand_weapon_shows_in_front_of_the_body_without_a_second_arm(self):
        ch, fr, ctx = example("offhand_weapon")
        self.assertEqual(checks.far_arm_flap(fr, ctx), [])
        self.assertEqual(checks.far_hand_hidden(fr, ctx), [])
        self.assertEqual(checks.arm_count(fr, ctx), [])
        for f in fr:
            names = f["meta"]["labels"]
            far = np.isin(f["label"], [names.index("far_upper"), names.index("far_fore")])
            w = f["label"] == names.index("gear:offhand_weapon")
            self.assertTrue(w.any())
            self.assertLess(int(far.sum()), 120)           # only the hand's disc, never an arm
            under = f["body"]["label"][w] if f.get("body") is not None else None
            if under is not None:
                self.assertTrue((under == names.index("torso")).any() or (under == 0).any())

    def test_far_hand_gear_without_in_front_is_unchanged_behind_the_far_arm(self):
        g = gear.Gear("a", spec.example_gear("offhand_weapon"), dict(spec.GEAR_GUIDES["offhand_weapon"]["json"],
                                                                      in_front=False))
        names = ["bg", "far_upper", "far_fore", "torso", "near_upper"]
        self.assertLess(gear.layer_rank(g, names), names.index("far_fore"))


class TestArmContrast(unittest.TestCase):
    def frame(self, sleeve, coat, h=24, w=24):
        names = ["bg", "far_upper", "torso", "near_upper"]
        lab = np.zeros((h, w), np.int16)
        rgba = np.zeros((h, w, 4), np.uint8)
        lab[2:22, 4:20] = 2
        rgba[2:22, 4:20] = (*coat, 255)
        lab[6:20, 8:14] = 3
        rgba[6:20, 8:14] = (*sleeve, 255)
        return {"label": lab, "rgba": rgba, "meta": {"labels": names, "joints": {}}}

    def test_r30_white_sleeve_on_a_white_robe_is_refused(self):
        f = self.frame((250, 250, 250), (252, 252, 252))
        self.assertTrue(checks.arm_contrast([f], {"size_x": 1}))

    def test_r30_passes_a_dark_sleeve_a_red_coat_and_the_outlined_white_one(self):
        self.assertEqual(checks.arm_contrast([self.frame((60, 60, 70), (200, 40, 40))], {"size_x": 1}), [])
        f = self.frame((250, 250, 250), (252, 252, 252))
        pal = [(250, 250, 250), (252, 252, 252), (150, 150, 155), (20, 20, 20)]
        rgba, lab = bake.outline_near_arm(f["rgba"], f["label"], f["meta"]["labels"], pal, 1)
        f["rgba"], f["label"] = rgba, lab
        self.assertEqual(checks.arm_contrast([f], {"size_x": 1}), [])
        edge, _, _ = checks.edge_pairs(lab, f["meta"]["labels"])
        c = rgba[edge][:, :3]
        self.assertTrue((c.max(1) < 250).all() and (c.max(1) > 30).all())     # a shade of the sleeve, not black

    def test_the_baked_fixtures_fail_r30_without_the_outline_and_pass_with_it(self):
        png = os.path.join(R5, "HR5.1.png")
        fitted = fit_still(png, png[:-4] + ".json")
        gears = load_gear(png)
        res = {}
        for flag in (False, True):
            bake.ARM_OUTLINE = flag
            try:
                ch = Character.from_still(png, png[:-4] + ".json", fitted=fitted, body_h=112, gear=gears)
                solve_gear([ch])
                fr, ctx = bake_motion(ch, ch.walk_motion(), 8)
                res[flag] = checks.arm_contrast(fr, ctx)
            finally:
                bake.ARM_OUTLINE = True
        self.assertTrue(res[False])
        self.assertEqual(res[True], [])


class TestVioletKey(unittest.TestCase):
    def fig(self, col, rim=None):
        a = np.zeros((40, 40, 4), np.uint8)
        a[4:36, 8:32] = (*col, 255)
        if rim:
            a[4:36, 8:10] = (*rim, 255)
        return a

    def test_violet_and_purple_robes_pass_g10_and_r19(self):
        for col in ((90, 20, 100), (70, 10, 80), (120, 40, 150), (150, 60, 190), (60, 30, 70)):
            a = self.fig(col)
            self.assertEqual(int(intake.key_mask(a).sum()), 0, col)
            out, n = intake.clean_key(a)
            self.assertEqual(int(intake.key_mask(out).sum()), 0, col)

    def test_real_magenta_fringe_still_fails(self):
        self.assertGreater(int(intake.key_mask(self.fig((90, 20, 100), rim=(255, 0, 255))).sum()), 0)
        self.assertGreater(int(intake.key_mask(self.fig((90, 20, 100), rim=(132, 8, 134))).sum()), 0)   # blended with ink
        self.assertGreater(int(intake.key_mask(self.fig((255, 0, 255))).sum()), 0)                     # pure, anywhere


class TestThinGear(unittest.TestCase):
    def test_synthetic_bow_is_one_unbroken_line_at_both_sizes_and_every_turn(self):
        for bh in (56, 112):
            g = gear.Gear("bow", spec.example_gear("bow"), dict(spec.GEAR_GUIDES["bow"]["json"], guide="bow"))
            scale = g.size * 390.0 * (bh / 390.0) / g.extent
            for phi in (-30.0, -12.0, 0.0, 7.5, 20.0, 41.0):
                spr, _ = g.sprite(scale, phi, bh / 56.0)
                self.assertEqual(len(components(spr[..., 3] > 0)[1]), 1, (bh, phi))

    def test_thin_stroke_picture_stays_connected(self):
        im = np.zeros((448, 128, 4), np.uint8)
        for y in range(8, 440):
            x = int(100 - (1 - (2 * (y - 8) / 432 - 1) ** 2) * 60)
            im[y, x:x + 12] = (90, 60, 30, 255)         # a 12 px limb in a 448 px picture: 0.6 px thick at 56 px
        g = gear.Gear("t", im, {"slot": "near_hand", "anchor": [int(100 - 60 + 6), 224], "up": [0, -1], "size": 0.40})
        for bh in (56, 112):
            for phi in (0.0, 13.0, -27.0):
                spr, _ = g.sprite(g.size * 390.0 * (bh / 390.0) / g.extent, phi, bh / 56.0)
                self.assertEqual(len(components(spr[..., 3] > 0)[1]), 1, (bh, phi))

    def test_real_archer_bows_are_unbroken_and_two_px_thick_at_112(self):
        for cid in ("HR4.1", "HR4.2", "HR4.3", "HR4.4"):
            png = os.path.join(R5, cid + ".png")
            fitted = fit_still(png, png[:-4] + ".json")
            gears = load_gear(png)
            for bh in (56, 112):
                ch = Character.from_still(png, png[:-4] + ".json", fitted=fitted, body_h=bh, gear=gears)
                b = [g for g in ch.gear if g.name == "bow"][0]
                for phi in (-20.0, 0.0, 25.0):
                    spr, _ = b.sprite(gear.scale_of(ch, b), phi, gear.min_of(ch, b))
                    self.assertEqual(len(components(spr[..., 3] > 0)[1]), 1, (cid, bh, phi))
                    if bh == 112:
                        op = spr[..., 3] > 0
                        thin = op & ~(np.roll(op, 1, 1) | np.roll(op, -1, 1)) & ~(np.roll(op, 1, 0) | np.roll(op, -1, 0))
                        self.assertEqual(int(thin.sum()), 0, (cid, phi))


if __name__ == "__main__":
    unittest.main()
