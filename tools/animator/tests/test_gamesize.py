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


class Bake(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.r = gs.bake_hero(PNG, PNG[:-4] + ".json")
        cls.again = gs.bake_hero(PNG, PNG[:-4] + ".json")

    def test_rigid_parts_do_not_change(self):
        for key in ("A56", "A112", "B112"):
            fs = self.r[key]
            m = gs.measure(fs)
            for nm in ("head", "torso", "robe", "gear:shield"):
                if nm in m:
                    self.assertEqual(m[nm]["all"][1], 0.0, (key, nm))

    def test_prop_is_rigid_within_a_carry_angle(self):
        for key in ("A56", "B112"):
            fs = self.r[key]
            m = gs.measure(fs)
            self.assertEqual(m["gear:hammer"]["same"][1], 0.0, key)
            carries = {f["variant"]["gear:hammer"] for f in fs.frames}
            self.assertLessEqual(len(carries), 3)

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
                        self.assertIsInstance(v, int)

    def test_whole_pixel_offsets_and_torso_only_translates(self):
        fs = self.r["A56"]
        for f in fs.frames:
            for nm, (x, y) in f["offset"].items():
                self.assertIsInstance(x, int)
        # head and torso: same sprite, x never moves, y moves only by the bob
        xs = {f["offset"]["torso"][0] for f in fs.frames}
        self.assertEqual(len(xs), 1)
        ys = [f["offset"]["torso"][1] for f in fs.frames]
        self.assertLessEqual(max(ys) - min(ys), 3)

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
