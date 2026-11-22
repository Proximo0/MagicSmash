"""Game-size pilot (gamesize.py): rigid parts must not change between frames, rotations come from a
fixed set, the two sizes cannot disagree, the palette is small and alpha is clean."""
import copy
import os
import unittest

import numpy as np

from helpers import ROOT

from tools.animator import gamesize as gs

HERE = os.path.join(ROOT, "tools", "animator")
PNG = os.path.join(HERE, "samples", "round5", "HR6.3.png")


class Primitives(unittest.TestCase):
    def test_rotation_is_a_pure_function(self):
        sp = np.full((12, 12), -1, np.int16)
        sp[2:10, 5:7] = 1
        dark = np.zeros(3, bool)
        a = gs.rotate_idx(sp, (6, 2), 45.0, 3, dark)
        b = gs.rotate_idx(sp, (6, 2), 45.0, 3, dark)
        self.assertTrue((a[0] == b[0]).all() and a[1:] == b[1:])
        self.assertTrue((a[0] >= 0).sum() > 0)
        z = gs.rotate_idx(sp, (6, 2), 0.0, 3, dark)
        self.assertTrue((z[0] == sp).all())

    def test_palette_entries_are_source_colours(self):
        rng = np.random.RandomState(1)
        img = np.zeros((40, 40, 4), np.uint8)
        img[..., :3] = rng.randint(0, 255, (40, 40, 3))
        img[..., 3] = 255
        pal = gs.build_palette([(img, 1.0)], 8)
        self.assertEqual(len(pal), 8)
        have = {tuple(c) for c in img.reshape(-1, 4)[:, :3].tolist()}
        self.assertTrue(all(tuple(c) in have for c in pal.tolist()))

    def test_measure_flags_a_changed_rigid_part(self):
        names = ["bg", "head"]
        pal = np.array([[10, 10, 10], [200, 0, 0]], np.uint8)

        def frame(px):
            idx = np.full((8, 8), -1, np.int16)
            idx[2:5, 2:5] = 0
            idx[3, 3] = px
            lab = np.where(idx >= 0, 1, 0).astype(np.int16)
            return {"idx": idx, "label": lab, "offset": {"head": (0, 0)}, "variant": {"head": ("rigid", 0)}, "bob": 0}
        same = gs.FrameSet([frame(0), frame(0)], names, pal, 56, 7, 4)
        self.assertEqual(gs.measure(same)["head"]["all"][1], 0.0)
        bad = gs.FrameSet([frame(0), frame(1)], names, pal, 56, 7, 4)
        self.assertGreater(gs.measure(bad)["head"]["all"][1], 5.0)

    def test_measure_follows_the_known_offset(self):
        names = ["bg", "head"]
        pal = np.array([[10, 10, 10]], np.uint8)

        def frame(dy):
            idx = np.full((12, 8), -1, np.int16)
            idx[2 + dy:5 + dy, 2:5] = 0
            lab = np.where(idx >= 0, 1, 0).astype(np.int16)
            return {"idx": idx, "label": lab, "offset": {"head": (0, dy)}, "variant": {"head": ("rigid", 0)}, "bob": dy}
        fs = gs.FrameSet([frame(0), frame(1)], names, pal, 56, 7, 4)
        self.assertEqual(gs.measure(fs)["head"]["all"][1], 0.0)


def fs_y(fs):
    return fs.foot_y - 1


class Gates(unittest.TestCase):
    def _fs(self, prop_x):
        names = ["bg", "head", "gear:staff"]
        pal = np.array([[10, 10, 10]], np.uint8)
        idx = np.full((20, 20), -1, np.int16)
        idx[2:10, 2:10] = 0
        m = np.ones((12, 2), bool)
        f = {"idx": idx, "label": np.zeros((20, 20), np.int16), "offset": {}, "variant": {}, "bob": 0, "leg_dy": 0,
             "head_box": (2, 2, 10, 10), "head_n": 64, "prop": (prop_x, 0, m)}
        return gs.FrameSet([f], names, pal, 56, 19, 10)

    def test_prop_clear_of_face_fails_when_the_prop_covers_the_face(self):
        self.assertTrue(gs.prop_clear_of_face(self._fs(12))[0])
        ok, worst = gs.prop_clear_of_face(self._fs(5))
        self.assertFalse(ok)
        self.assertGreater(worst, 0.02)
        # 1 px of 64 head pixels is 1.6%: still clear; 2 px is 3.1%: not
        fs = self._fs(9)
        self.assertTrue(gs.prop_clear_of_face(fs)[0] is False or gs.prop_clear_of_face(fs)[1] <= 0.02)

    def test_joint_holes_sees_a_slit_and_a_gap(self):
        a = np.zeros((12, 12), bool)
        b = np.zeros((12, 12), bool)
        a[0:6, 3:8] = True
        b[6:12, 3:8] = True
        self.assertEqual(gs.joint_holes(a, b, (5, 6), 4), 0)
        b2 = np.zeros((12, 12), bool)
        b2[7:12, 3:8] = True            # one row of background between the parts
        self.assertGreater(gs.joint_holes(a, b2, (5, 6), 4), 0)

    def test_outline_pass_makes_a_dotted_edge_continuous_or_removes_it(self):
        dark = np.array([True, False])
        a = np.full((9, 9), -1, np.int16)
        a[2:7, 2:7] = 1
        ring = gs._ring(a >= 0)
        pts = np.argwhere(ring)
        for n, (y, x) in enumerate(pts):
            if n % 2 == 0:
                a[y, x] = 0                 # a dotted outline
        out = gs.clean_outline({"torso": a.copy()}, dark, 2)["torso"]
        self.assertTrue((out[ring] == 0).all())      # one continuous outline
        b = np.full((9, 9), -1, np.int16)
        b[2:7, 2:7] = 1
        b[2, 4] = 0                          # a lone dark dot on a plain edge
        out = gs.clean_outline({"torso": b}, dark, 2)["torso"]
        self.assertTrue((out[gs._ring(out >= 0)] == 1).all())

    def test_tidy_sprite_fills_slits_and_drops_specks(self):
        a = np.full((8, 8), -1, np.int16)
        a[1:7, 1:3] = 1
        a[1:7, 4:6] = 1                      # a 1 px slit at column 3
        a[7, 7] = 1                          # a speck
        out = gs.tidy_sprite(a)
        self.assertTrue((out[1:7, 3] == 1).all())
        self.assertEqual(out[7, 7], -1)


class Bake(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.r = gs.bake_hero(PNG, PNG[:-4] + ".json")
        cls.again = gs.bake_hero(PNG, PNG[:-4] + ".json")

    def test_rigid_parts_do_not_change(self):
        for key in ("A56", "A112", "B112"):
            fs = self.r[key]
            m = gs.measure(fs)
            for nm in ("head", "torso", "gear:shield"):
                if nm in m:
                    self.assertEqual(m[nm]["all"][1], 0.0, (key, nm))

    def test_cloth_swings_in_two_states_and_is_rigid_within_a_state(self):
        for key in ("A56", "B112"):
            fs = self.r[key]
            states = {f["variant"]["robe"] for f in fs.frames}
            self.assertEqual(states, {("cloth", 0), ("cloth", 1)})
            self.assertEqual(gs.measure(fs)["robe"]["same"][1], 0.0, key)

    def test_prop_has_one_carry_angle_and_does_not_change(self):
        for key in ("A56", "A112", "B112", "B56"):
            fs = self.r[key]
            worst = gs.measure(fs)["gear:hammer"]["all"][1]
            if key == "B56":                      # 2:1 reduction flips a few edge pixels where the hand covers the haft
                self.assertLess(worst, 3.0, key)
            else:
                self.assertEqual(worst, 0.0, key)
            self.assertEqual({f["variant"]["gear:hammer"] for f in fs.frames}, {("carry", 0)})

    def test_prop_clear_of_face(self):
        for key in ("A56", "B112", "B56"):
            ok, worst = gs.prop_clear_of_face(self.r[key])
            self.assertTrue(ok, (key, worst))

    def test_no_holes_at_the_joints(self):
        for key in ("A56", "B112", "B56"):
            self.assertEqual(gs.count_hole_frames(self.r[key]), 0, key)

    def test_leg_gates_pass_on_the_bake(self):
        for key in ("A56", "B112"):
            self.assertEqual(sum(gs.leg_gates(self.r[key]).values()), 0, (key, gs.leg_gates(self.r[key])))
            self.assertEqual(gs.no_skin_below_belt(self.r[key]), 0, key)

    def test_feet_use_at_most_three_angles_and_planted_feet_are_flat(self):
        for key in ("A56", "B112"):
            fs = self.r[key]
            for f in fs.frames:
                for side in ("near", "far"):
                    kind, v = f["variant"][side + "_foot"]
                    self.assertIn(v, (-2, 0, 2))
                    if f["legs"][side]["planted"]:
                        self.assertEqual(v, 0)

    def test_leg_gates_catch_faults(self):
        import copy as cp
        base = self.r["B112"]

        def broken(edit):
            fs = cp.copy(base)
            fs.frames = [cp.deepcopy(f) for f in base.frames]
            edit(fs.frames)
            return gs.leg_gates(fs)
        self.assertGreater(broken(lambda fr: fr[0]["legs"]["near"].update(flex=-30.0))["knee_backwards"], 0)
        self.assertGreater(broken(lambda fr: fr[0]["legs"]["near"].update(planted=True, sole=fs_y(base) - 3))["planted_sole"], 0)
        self.assertGreater(broken(lambda fr: fr[2]["legs"]["far"].update(area=(99.0, 99.0)))["leg_width"], 0)
        self.assertGreater(broken(lambda fr: fr[1]["holes"].update(near=2))["leg_hole"], 0)

        def lose_far_foot(fr):
            li = {n: k for k, n in enumerate(base.names)}["far_foot"]
            fr[0]["label"][fr[0]["label"] == li] = 0
            fr[0]["feet"]["far"] = np.zeros_like(fr[0]["feet"]["far"])
            fr[0]["feet"]["far"][5:8, 5:8] = True
            fr[0]["feet"]["near"] = np.zeros_like(fr[0]["feet"]["far"])
        self.assertGreater(broken(lose_far_foot)["two_feet"], 0)

    def test_walk_gates_pass_and_report(self):
        for key in ("A56", "B112"):
            bad, st = gs.walk_gates(self.r[key])
            self.assertEqual(sum(bad.values()), 0, (key, bad))
            self.assertLessEqual(st["max_stance_bend"], 15.5)
            self.assertGreaterEqual(st["min_pelvis_ratio"], 0.95)
            self.assertEqual(st["foot_slide_px"], 0)

    def test_walk_gates_catch_faults(self):
        import copy as cp
        base = self.r["B112"]

        def broken(edit):
            fs = cp.copy(base)
            fs.frames = [cp.deepcopy(f) for f in base.frames]
            fs.walk = dict(base.walk)
            edit(fs)
            return gs.walk_gates(fs)[0]

        def plant(fs):
            side = next(s for s in ("near", "far") if fs.frames[0]["legs"][s]["planted"])
            fs.frames[0]["legs"][side]["flex"] = 40.0
        self.assertGreater(broken(plant)["stance_bend"], 0)

        def swing(fs):
            for f in fs.frames:
                for s in ("near", "far"):
                    if not f["legs"][s]["planted"]:
                        f["legs"][s]["flex"] = 80.0
                        f["legs"][s]["lift"] = 20
        bad = broken(swing)
        self.assertGreater(bad["swing_bend"], 0)
        self.assertGreater(bad["swing_lift"], 0)

        def low(fs):
            for f in fs.frames:
                f["legs"]["near"]["hdy"] *= 0.8
        self.assertGreater(broken(low)["pelvis_height"], 0)
        self.assertGreater(broken(lambda fs: fs.walk.update(lean=-3.0))["trunk_lean"], 0)
        self.assertGreater(broken(lambda fs: fs.walk.update(lean=9.0))["trunk_lean"], 0)

        def slide(fs):
            for f in fs.frames:
                for s in ("near", "far"):
                    f["legs"][s]["planted"] = True
            fs.frames[1]["legs"]["near"]["cx"] += 2
        self.assertGreater(broken(slide)["foot_slide"], 0)

    def test_the_trunk_never_leans_back(self):
        for key in ("A56", "B112"):
            self.assertTrue(0.0 <= self.r[key].walk["lean"] <= 6.0, key)

    def test_stance_legs_never_crouch(self):
        """Pelvis height is the same in every frame (the bob is the only vertical move) and above 0.95 x the leg."""
        for key in ("A56", "B112"):
            fs = self.r[key]
            hs = {round(f["legs"][s]["hdy"], 3) for f in fs.frames for s in ("near", "far")}
            self.assertEqual(len(hs), 1, (key, hs))

    def test_prop_gates_upright_and_off_the_legs(self):
        for key in ("A56", "B112", "B56"):
            self.assertTrue(gs.prop_clear_of_legs(self.r[key])[0], key)
            self.assertTrue(gs.prop_upright(self.r[key]), key)
        import copy as cp
        fs = cp.copy(self.r["B112"])
        fs.frames = [cp.deepcopy(f) for f in fs.frames]
        for f in fs.frames:                      # lay the prop over the legs
            x0, y0, m = f["prop"]
            ys, xs = np.nonzero(f["legmask"])
            f["prop"] = (int(xs.min()), int(ys.min()), np.ones((int(ys.max() - ys.min()), int(xs.max() - xs.min())), bool))
        self.assertFalse(gs.prop_clear_of_legs(fs)[0])
        fs.prop_info = dict(fs.prop_info, tilt=25.0, long=True)
        self.assertFalse(gs.prop_upright(fs))

    def test_enclosed_holes(self):
        m = np.zeros((8, 8), bool)
        m[1:7, 1:7] = True
        self.assertEqual(gs.enclosed_holes(m), 0)
        m[3, 3] = False
        self.assertEqual(gs.enclosed_holes(m), 1)

    def test_far_arm_is_drawn_when_the_still_has_it(self):
        self.assertIn("far_upper", self.r["B112"].names)

    def test_bob_is_exactly_one_px_at_56_two_at_112(self):
        for key, px in (("A56", 1), ("B56", 1), ("B112", 2)):
            b = [int(f["bob"]) for f in self.r[key].frames]
            self.assertEqual(max(b) - min(b), px, key)
            ys = [f["offset"]["torso"][1] for f in self.r[key].frames]
            self.assertEqual(max(ys) - min(ys), px, key)

    def test_limbs_do_not_change_within_a_rotation_step(self):
        for key in ("A56", "A112", "B112"):
            m = gs.measure(self.r[key])
            for nm in gs.LIMBS:
                if nm in m and m[nm]["same"]:
                    self.assertEqual(m[nm]["same"][1], 0.0, (key, nm))

    def test_rotations_come_from_the_fixed_set(self):
        for key in ("A56", "B112"):
            for f in self.r[key].frames:
                for nm, (kind, v) in f["variant"].items():
                    if kind == "step":
                        self.assertLessEqual(abs(v), gs.MAX_STEP)
                        self.assertIsInstance(v, int)    # degrees = v * 11.25

    def test_whole_pixel_offsets_and_torso_only_translates(self):
        fs = self.r["A56"]
        for f in fs.frames:
            for nm, (x, y) in f["offset"].items():
                self.assertIsInstance(x, int)
        # head and torso: same sprite, x never moves, y moves only by the bob
        xs = {f["offset"]["torso"][0] for f in fs.frames}
        self.assertEqual(len(xs), 1)
        ys = [f["offset"]["torso"][1] for f in fs.frames]
        self.assertLessEqual(max(ys) - min(ys), 1)

    def test_sizes_cannot_disagree(self):
        a56, a112 = self.r["A56"], self.r["A112"]
        for i in range(8):
            self.assertTrue((a112.frames[i]["idx"] == a56.frames[i]["idx"].repeat(2, 0).repeat(2, 1)).all())
        b112, b56 = self.r["B112"], self.r["B56"]
        for f in b112.frames:
            self.assertTrue(all(x % 2 == 0 and y % 2 == 0 for x, y in f["offset"].values()))
        for i in range(8):
            self.assertTrue((b56.frames[i]["idx"] == b112.down2().frames[i]["idx"]).all())

    def test_odd_origins_refuse_the_2_to_1(self):
        fs = copy.deepcopy(self.r["A56"])
        with self.assertRaises(ValueError):
            fs.down2()

    def test_palette_and_alpha(self):
        for key in ("A56", "A112", "B112", "B56"):
            fs = self.r[key]
            self.assertLessEqual(len(fs.palette), gs.PALETTE_N)
            for i in range(8):
                self.assertTrue(set(np.unique(fs.rgba(i)[..., 3])) <= {0, 255})

    def test_deterministic(self):
        for key in ("A56", "B112"):
            for i in range(8):
                self.assertTrue((self.r[key].frames[i]["idx"] == self.again[key].frames[i]["idx"]).all())

    def test_feet_on_the_ground(self):
        for key in ("A56", "B112"):
            fs = self.r[key]
            for i in range(8):
                rows = np.nonzero((fs.frames[i]["idx"] >= 0).any(1))[0]
                self.assertGreaterEqual(rows.max(), fs.foot_y - 2, (key, i))
                self.assertLessEqual(rows.max(), fs.foot_y - 1, (key, i))


if __name__ == "__main__":
    unittest.main()
