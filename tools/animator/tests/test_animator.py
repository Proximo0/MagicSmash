import copy
import glob
import json
import math
import os
import unittest

import numpy as np

from helpers import make_files, ROOT, JOINTS

from tools.animator import checks
from tools.animator.bake import Character, bake_motion, render, reduce, FOOT_Y
from tools.animator.cut import auto_joints, load_still, split_strip, load_rgba
from tools.animator.motion import walk, Gait, Curve
from tools.animator.rig import Rig, ik2, joint_angles, JOINT_LIMITS

SAMPLES = os.path.join(ROOT, "tools", "animator", "samples")


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.png, cls.js, cls.tmp = make_files()
        cls.ch = Character(cls.png, cls.js)
        cls.frames, cls.ctx = bake_motion(cls.ch, cls.ch.walk_motion(), 8)

    def fresh(self):
        return copy.deepcopy(self.frames), copy.deepcopy(self.ctx)

    def rule_fails(self, rule, frames, ctx, word):
        out = rule(frames, ctx)
        self.assertTrue(out, f"{rule.__name__} should fail")
        self.assertTrue(any(word in o for o in out), out)
        self.assertTrue(all(o.startswith("frame ") for o in out), out)


class TestRig(Base):
    def test_rest_pose_reproduces_still(self):
        rig = self.ch.rig
        J = rig.fk(rig.rest_pose())
        for n in ("neck", "head_top", "shoulder", "elbow", "wrist", "hip", "knee", "ankle", "heel", "toe"):
            key = n if n in ("neck", "head_top") else "near." + n
            self.assertLess(np.hypot(*(J[key] - rig.j[n])), 1e-6, n)

    def test_json_roundtrip(self):
        p = os.path.join(self.tmp, "rt.json")
        self.ch.rig.save(p)
        r2 = Rig.load(p)
        self.assertEqual(r2.lengths, self.ch.rig.lengths)

    def test_ik_knee_bends_backwards_only(self):
        knee, end = ik2([0, 0], [0, 30], 20, 20)
        self.assertGreater(knee[0], 0)       # knee ahead of the hip-ankle line
        self.assertAlmostEqual(float(np.hypot(*knee)), 20, 6)

    def test_limits_table(self):
        self.assertEqual(JOINT_LIMITS["knee"], (0.0, 150.0))
        self.assertEqual(JOINT_LIMITS["elbow"][0], 0.0)

    def test_curve_periodic(self):
        c = Curve([0, 0.5], [1, 3])
        self.assertAlmostEqual(c(0.0), c(1.0))


class TestCut(Base):
    def test_parts(self):
        p = self.ch.parts
        for n in ("torso", "near_upper", "near_fore", "near_thigh", "near_shin", "near_foot",
                  "far_upper", "far_thigh", "gear:shield"):
            self.assertIn(n, p)
            self.assertTrue(p[n].mask.any(), n)

    def test_far_is_darker_copy(self):
        n, f = self.ch.parts["near_thigh"].img, self.ch.parts["far_thigh"].img
        self.assertTrue(np.array_equal(n[..., 3] > 0, f[..., 3] > 0))
        m = n[..., 3] > 0
        self.assertLess(f[m][:, :3].astype(int).sum(), n[m][:, :3].astype(int).sum() * 0.85)

    def test_far_leg_erased_from_torso(self):
        # the far foot pixels of the still must not survive in any rigid part
        t = self.ch.parts["torso"].img
        self.assertFalse((t[118:126, 2:18, 3] > 0).any())

    def test_split_strip(self):
        segs = split_strip(load_rgba(self.png))
        self.assertEqual(len(segs), 4)


class TestWalk(Base):
    def test_good_walk_passes_every_rule(self):
        self.assertEqual(checks.run_all(self.frames, self.ctx), [])

    def test_canvas_palette_alpha(self):
        f = self.frames[0]["rgba"]
        self.assertEqual(f.shape[:2], (80, 96))
        self.assertTrue(np.isin(f[..., 3], (0, 255)).all())

    def test_stride_and_bob(self):
        g = Gait(self.ch.rig, walk())
        self.assertGreater(g.stride, 0.9 * g.leg)
        ys = [g.pelvis_y(i / 16) for i in range(16)]
        # pelvis highest (smallest y) twice per cycle, near mid-stance of each leg
        hi = [i for i in range(16) if ys[i] < ys[i - 1] and ys[i] <= ys[(i + 1) % 16]]
        self.assertEqual(len(hi), 2, ys)


class TestBrokenInputs(Base):
    """Each rule must fail on a deliberately broken input."""

    def test_third_leg(self):
        fr, ctx = self.fresh()
        f = fr[0]
        J = f["meta"]["joints"]
        y0 = int(max(J["near.knee"][1], J["far.knee"][1])) + 1
        x = int(max(J["near.toe"][0], J["far.toe"][0])) + 4
        f["rgba"][y0:FOOT_Y, x:x + 5] = f["rgba"][y0:FOOT_Y, int(J["near.ankle"][0])][:, None]
        f["rgba"][y0:FOOT_Y, x:x + 5, 3] = 255
        f["label"][y0:FOOT_Y, x:x + 5] = 0
        self.rule_fails(checks.two_legs, fr, ctx, "third leg")

    def test_knee_bent_forward(self):
        fr, ctx = self.fresh()
        J = fr[2]["meta"]["joints"]
        h, a, k = np.array(J["near.hip"]), np.array(J["near.ankle"]), np.array(J["near.knee"])
        u = (a - h) / np.hypot(*(a - h))
        proj = h + u * ((k - h) @ u)
        J["near.knee"] = 2 * proj - k        # mirror the knee behind the line
        self.rule_fails(checks.joint_limits, fr, ctx, "near.knee")

    def test_sliding_foot(self):
        fr, ctx = self.fresh()
        i = next(i for i, f in enumerate(fr) if f["meta"]["contact"]["near"]
                 and fr[i + 1]["meta"]["contact"]["near"])
        for k in ("heel", "toe", "ankle"):
            fr[i + 1]["meta"]["joints"]["near." + k] = np.array(fr[i + 1]["meta"]["joints"]["near." + k]) + [3.0, 0]
        self.rule_fails(checks.stance_foot, fr, ctx, "foot_slide")

    def test_sinking_foot(self):
        fr, ctx = self.fresh()
        for k in ("heel", "toe", "ankle"):
            fr[1]["meta"]["joints"]["near." + k] = np.array(fr[1]["meta"]["joints"]["near." + k]) + [0, 3.0]
        self.rule_fails(checks.stance_foot, fr, ctx, "sink")

    def test_swapped_legs(self):
        fr, ctx = self.fresh()
        o = fr[3]["meta"]["draw_order"]
        a, b = o.index("far_thigh"), o.index("near_thigh")
        o[a], o[b] = o[b], o[a]
        self.rule_fails(checks.draw_order, fr, ctx, "draw_order")

    def test_changed_shield(self):
        ch = self.ch
        saved = ch.parts["gear:shield"].img.copy()
        try:
            img = ch.parts["gear:shield"].img
            ys, xs = np.where(img[..., 3] > 0)
            img[ys[len(ys) // 2], xs[len(xs) // 2], :3] = 255 - img[ys[len(ys) // 2], xs[len(xs) // 2], :3]
            fr, ctx = self.fresh()
            fr[5]["meta"]["digests"]["gear:shield"] = ch.parts["gear:shield"].digest()
        finally:
            ch.parts["gear:shield"].img[...] = saved
        self.rule_fails(checks.rigid_parts, fr, ctx, "gear:shield")

    def test_bone_stretched(self):
        fr, ctx = self.fresh()
        fr[4]["meta"]["joints"]["near.wrist"] = np.array(fr[4]["meta"]["joints"]["near.wrist"]) + [4.0, 0]
        self.rule_fails(checks.bone_lengths, fr, ctx, "near.fore")

    def test_foot_backwards(self):
        fr, ctx = self.fresh()
        J = fr[6]["meta"]["joints"]
        J["far.heel"], J["far.toe"] = J["far.toe"], J["far.heel"]
        self.rule_fails(checks.feet_facing, fr, ctx, "backwards")

    def test_foot_shifted_backwards_rig(self):
        fr, ctx = self.fresh()
        J = fr[2]["meta"]["joints"]
        for k in ("heel", "toe"):
            J["near." + k] = np.array(J["near." + k]) - [ctx["foot_len"] * 0.6, 0]
        self.rule_fails(checks.heel_flush, fr, ctx, "behind the shin")

    def test_foot_shifted_backwards_pixels(self):
        fr, ctx = self.fresh()
        f = fr[0]
        names = f["meta"]["labels"]
        li = names.index("near_foot")
        m = f["label"] == li
        self.assertTrue(m.any())
        sh = 4
        moved = np.zeros_like(m)
        moved[:, :-sh] = m[:, sh:]
        f["rgba"][moved] = f["rgba"][np.roll(moved, sh, 1)]
        f["label"][moved] = li
        self.rule_fails(checks.heel_flush, fr, ctx, "sticks out")

    def test_cycle_not_closed(self):
        fr, ctx = self.fresh()
        ctx["closing"]["joints"]["near.knee"] = np.array(ctx["closing"]["joints"]["near.knee"]) + [5.0, 0]
        self.rule_fails(checks.cycle_closes, fr, ctx, "cycle_closes")

    def test_uneven_steps(self):
        fr, ctx = self.fresh()
        ctx["stance"]["far"] = (0.45, ctx["stance"]["far"][1])
        self.rule_fails(checks.mirror_timing, fr, ctx, "mirror_timing")

    def test_new_colour(self):
        fr, ctx = self.fresh()
        ys, xs = np.where(fr[0]["rgba"][..., 3] > 0)
        fr[0]["rgba"][ys[0], xs[0], :3] = (1, 254, 3)
        self.rule_fails(checks.palette, fr, ctx, "palette")

    def test_elbow_bent_backwards(self):
        fr, ctx = self.fresh()
        J = fr[3]["meta"]["joints"]
        e = np.array(J["near.elbow"], float)
        up = e - np.array(J["near.shoulder"], float)
        a = math.radians(60)                   # forearm folded 60 deg behind the upper arm
        r = np.array([[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]])
        J["near.wrist"] = e + r @ (up / np.hypot(*up)) * ctx["lengths"]["near.fore"]
        out = [o for o in checks.joint_limits(fr, ctx) if "near.elbow" in o]
        self.assertTrue(out, "elbow bent backwards must fail joint_limits")
        self.assertTrue(all(checks.rule_id(o) == "R4" for o in out), out)

    def test_hip_overextended(self):
        fr, ctx = self.fresh()
        J = fr[3]["meta"]["joints"]
        h = np.array(J["near.hip"], float)
        a = math.radians(70)                   # swing the whole leg 70 deg backwards
        r = np.array([[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]])
        for k in ("knee", "ankle", "heel", "toe"):
            J["near." + k] = h + r @ (np.array(J["near." + k], float) - h)
        out = [o for o in checks.joint_limits(fr, ctx) if "near.hip" in o]
        self.assertTrue(out, "hip overextended must fail joint_limits")
        self.assertEqual(checks.rule_id(out[0]), "R10")

    def test_third_arm(self):
        fr, ctx = self.fresh()
        fr[2]["meta"]["draw_order"].append("extra_upper")
        self.rule_fails(checks.two_arms, fr, ctx, "two_arms")

    def test_hand_off_forearm(self):
        fr, ctx = self.fresh()
        fr[2]["meta"]["joints"]["far.wrist"] = np.array(fr[2]["meta"]["joints"]["far.wrist"]) + [0, 5.0]
        self.rule_fails(checks.two_arms, fr, ctx, "not on its forearm")

    def test_foot_jitter(self):
        fr, ctx = self.fresh()
        self.assertEqual(checks.foot_jitter(fr, ctx), [])
        n = len(fr)
        i = next(i for i in range(n - 1) if fr[i]["meta"]["contact"]["near"]
                 and fr[i + 1]["meta"]["contact"]["near"])
        f = fr[i + 1]
        li = f["meta"]["labels"].index("near_foot")
        m = f["label"] == li
        f["label"][m] = 0
        f["label"][np.roll(m, 3, 1)] = li            # the baked foot jumps 3 px forward
        self.rule_fails(checks.foot_jitter, fr, ctx, "jumps")

    def test_rule_ids(self):
        self.assertEqual(checks.rule_id("frame 1: two_legs: third leg"), "R1")
        self.assertEqual(checks.rule_id("frame 1: joint_limit: far.knee -9 deg"), "R3")
        self.assertEqual(checks.rule_id("frame 1: joint_limit: near.ankle 40 deg"), "R10")


class TestSamples(unittest.TestCase):
    def test_paladins_pass(self):
        from tools.animator.bake import bake_all
        from tools.animator.fit import fit_still, gate_still
        from tools.animator.autocut import gate_cut
        for name in ("HR6.1", "HR6.4"):     # HR6.2 is rejected at the input (G7, sliced shield)
            png = os.path.join(SAMPLES, "stills", name + ".png")
            fitted = fit_still(png, png[:-4] + ".json")
            self.assertEqual(gate_still(fitted[1]), [], name)
            ch = Character.from_still(png, png[:-4] + ".json", fitted=fitted)
            self.assertEqual(gate_cut(ch.info), [], name)
            for n, (fr, ctx, fails) in bake_all(ch, (4, 8)).items():
                self.assertEqual(fails, [], f"{name} walk{n}")

    def test_auto_joints_close_to_hand_joints(self):
        errs = []
        for js in sorted(glob.glob(os.path.join(SAMPLES, "*.json"))):
            with open(js) as fh:
                d = json.load(fh)
            still, _, _ = load_still(js[:-5] + ".png", d)
            a = auto_joints(still)
            for k in ("hip", "ankle", "toe", "heel", "knee"):
                errs.append(math.hypot(*(np.subtract(a["joints"][k], d["joints"][k]))))
        self.assertLess(float(np.median(errs)), 10.0)


if __name__ == "__main__":
    unittest.main()
