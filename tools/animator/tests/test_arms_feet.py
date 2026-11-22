"""Arms (R17, R18, G8, the real far arm), the foot model (R6 by construction, G9) and the
still spec (a character drawn on STILL_SPEC.md passes every G rule)."""
import copy
import json
import contextlib
import io
import os
import shutil
import tempfile
import unittest

import numpy as np

from helpers import ROOT

from tools.animator import checks, foot, spec
from tools.animator.autocut import gate_cut
from tools.animator.bake import Character, bake_all
from tools.animator.fit import fit_still, gate_still
from tools.animator.motion import Gait, SWING_ANKLE, STANCE_DORSI_MAX
from tools.animator.rig import joint_angles

import test_animator

STILLS = os.path.join(ROOT, "tools", "animator", "samples", "stills")


def still(name):
    png = os.path.join(STILLS, name + ".png")
    return png, png[:-4] + ".json"


class TestArms(test_animator.Base):
    """R17 / R18 on baked frames, G8 on the input, and the far arm cut from its own pixels."""

    # ---- R17: counted on the pixels
    def test_good_walk_has_two_arms(self):
        fr, ctx = self.fresh()
        self.assertTrue(ctx["hand_colours"])
        self.assertEqual(checks.arm_count(fr, ctx), [])

    def test_third_hand_on_torso(self):
        # the owner's catch: an arm left painted on the torso, its hand at the hip
        fr, ctx = self.fresh()
        f = fr[3]
        J = f["meta"]["joints"]
        col = sorted(ctx["hand_colours"])[0]
        x, y = int(J["pelvis"][0]) - 2, int(J["near.hip"][1]) - 6
        ti = f["meta"]["labels"].index("torso")
        f["rgba"][y:y + 4, x:x + 4] = list(col) + [255]
        f["label"][y:y + 4, x:x + 4] = ti
        self.rule_fails(checks.arm_count, fr, ctx, "third hand")
        self.assertEqual(checks.rule_id(checks.arm_count(fr, ctx)[0]), "R17")

    def test_hand_off_its_forearm_pixels(self):
        # a hand-coloured blob labelled as forearm but far from that forearm's end
        fr, ctx = self.fresh()
        f = fr[3]
        J = f["meta"]["joints"]
        col = sorted(ctx["hand_colours"])[0]
        li = f["meta"]["labels"].index("far_fore")
        x, y = int(J["far.shoulder"][0]) - 12, int(J["far.shoulder"][1]) + 2
        f["rgba"][y:y + 4, x:x + 4] = list(col) + [255]
        f["label"][y:y + 4, x:x + 4] = li
        self.rule_fails(checks.arm_count, fr, ctx, "off the end of its forearm")

    # ---- R18: swing
    def test_good_walk_swings(self):
        fr, ctx = self.fresh()
        self.assertEqual(checks.arm_swing(fr, ctx), [])

    def _turn_arm(self, J, s, deg):
        """Turn one whole arm about its shoulder by deg (+ = forward)."""
        r = np.radians(-deg)
        c, sn = np.cos(r), np.sin(r)
        sh = np.array(J[s + ".shoulder"], float)
        for k in ("elbow", "wrist", "hand_tip"):
            v = np.array(J[s + "." + k], float) - sh
            J[s + "." + k] = sh + [c * v[0] - sn * v[1], sn * v[0] + c * v[1]]

    def test_arm_held_out_in_front(self):
        # what the owner saw: the near arm stretched out in front in every frame
        fr, ctx = self.fresh()
        for f in fr:
            self._turn_arm(f["meta"]["joints"], "near", 50.0)
        out = checks.arm_swing(fr, ctx)
        self.assertTrue(any("held out" in o for o in out), out)
        self.assertTrue(any("mid-stance" in o for o in out), out)
        self.assertEqual(checks.rule_id(out[0]), "R18")

    def test_arms_in_step_with_legs(self):
        fr, ctx = self.fresh()
        for f in fr:                       # swap the two arms' poses: same-side arm and leg together
            J = f["meta"]["joints"]
            d = np.array(J["far.shoulder"], float) - np.array(J["near.shoulder"], float)
            for k in ("elbow", "wrist", "hand_tip"):
                n, fa = np.array(J["near." + k], float), np.array(J["far." + k], float)
                J["near." + k], J["far." + k] = fa - d, n + d
        self.rule_fails(checks.arm_swing, fr, ctx, "opposite to the legs")

    def test_stiff_arms(self):
        fr, ctx = self.fresh()
        ref = copy.deepcopy(fr[0]["meta"]["joints"])
        for f in fr:                       # both arms frozen hanging: no swing at all
            J = f["meta"]["joints"]
            for s in ("near", "far"):
                sh = np.array(J[s + ".shoulder"], float)
                for k, dy in (("elbow", 6.0), ("wrist", 12.0), ("hand_tip", 14.0)):
                    J[s + "." + k] = sh + [0.0, dy]
        self.rule_fails(checks.arm_swing, fr, ctx, "stiff")
        self.assertTrue(ref)

    def test_free_arm_is_normalised_to_hanging(self):
        # the still's own arm pose must not leak into the walk: draw the arm anywhere, the
        # posed upper arm is the table's angle about straight down
        m = self.ch.walk_motion()
        g = Gait(self.ch.rig, m)
        rig2 = copy.deepcopy(self.ch.rig)
        rig2.rest["upper"], rig2.rest["fore"] = 70.0, 150.0      # "drawn" stretched forward
        g2 = Gait(rig2, m)
        ups = []
        for i in range(16):
            for s in ("near", "far"):
                self.assertEqual(g.arm_angles(s, i / 16), g2.arm_angles(s, i / 16))
            ups.append(g.arm_angles("near", i / 16)[0])
        self.assertLess(abs(float(np.mean(ups))), 5.0)            # centred on hanging
        self.assertTrue(18.0 <= max(ups) - np.mean(ups) <= 24.0, ups)   # about +/- 20 deg
        # opposite phase: near arm furthest back at near heel strike, far arm the mirror
        self.assertLess(g.arm_angles("near", 0.0)[0], -15.0)
        self.assertGreater(g.arm_angles("far", 0.0)[0], 15.0)
        el = [g.arm_angles("near", i / 16)[1] - g.arm_angles("near", i / 16)[0] for i in range(16)]
        self.assertTrue(5.0 <= min(el) and max(el) <= 30.0, el)   # slight elbow bend

    # ---- G8: the input
    def test_g8_arm_on_body_real_stills(self):
        # HR6.1 (the owner's "three arms"), HR1.1 and HR6.3 draw the near arm over the body
        for name in ("HR6.1", "HR1.1", "HR6.3"):
            _, data, _ = fit_still(*still(name))
            out = [t for t, _ in gate_still(data)]
            self.assertTrue(any(t.startswith("G8:") for t in out), (name, out))

    def test_g8_hand_blob_inside(self):
        _, data, _ = fit_still(*still("HR4.2"))
        self.assertEqual(gate_still(data), [])
        d = copy.deepcopy(data)
        d["fit"]["hands"].append({"at": [120.0, 230.0], "area": 1.2, "zone": "inside", "w": 14, "h": 15,
                                  "kind": "hand", "reach": 0.9})
        out = [t for t, _ in gate_still(d)]
        self.assertTrue(any(t.startswith("G8:") and "painted on" in t for t in out), out)

    # ---- the far arm: own pixels when the still shows it, a copy only when it does not
    def test_visible_far_arm_is_cut_from_its_own_pixels(self):
        fitted = fit_still(*still("HR3.1"))                  # far hand visible behind the back
        img, data, masks = fitted
        self.assertEqual(data["far_arm"], "visible")
        ch = Character.from_still(*still("HR3.1"), fitted=fitted)
        self.assertEqual(ch.info["far_arm"], "own pixels")
        far = masks["far_hand"]
        # nothing of that hand is left on the torso, cape or robe
        for nm in ("torso", "cape", "robe"):
            if nm in ch.parts:
                self.assertFalse((ch.info["labels"] == ch.info["codes"][nm])[far].any(), nm)
        # the far forearm carries the hand's own (unshaded) colours: more of the still's
        # hand pixels' colours than a shaded copy would have
        hand_cols = {tuple(c) for c in ch.info["image"][far][:, :3]}
        ff = ch.parts["far_fore"].img
        own = sum(tuple(c) in hand_cols for c in ff[ff[..., 3] > 0][:, :3])
        self.assertGreater(own, 0.5 * far.sum() * 0.5)

    def test_hidden_far_arm_is_a_copy(self):
        d = tempfile.mkdtemp()
        try:
            p = spec.write("human", d)
            ch = Character.from_still(p["reference"], p["joints"])
        finally:
            shutil.rmtree(d, ignore_errors=True)
        self.assertEqual(ch.rig.data["far_arm"], "hidden")
        self.assertEqual(ch.info["far_arm"], "copy of the near arm")
        self.assertTrue(ch.parts["far_fore"].mask.any())


class TestFoot(unittest.TestCase):
    """The foot model: heel seated on the shin's back edge, length from the drawn boot."""

    def leg(self, boot_len, shin_w=10, heel_out=0, lean=0.0):
        """A shin (vertical, or leaning) on a flat boot; the boot's heel sticks out
        heel_out px behind the shin's back edge.  Returns mask, knee, ankle."""
        m = np.zeros((120, 160), bool)
        knee, ankle = np.array([60.0 - lean * 60, 30.0]), np.array([60.0, 90.0])
        for y in range(30, 96):
            cx = knee[0] + (ankle[0] - knee[0]) * (y - 30) / 60.0
            m[y, int(cx - shin_w / 2):int(cx + shin_w / 2)] = True
        x0 = int(60 - shin_w / 2 - heel_out)
        m[96:108, x0:x0 + boot_len] = True
        return m, knee, ankle

    def test_heel_is_seated_flush_and_foot_runs_forward(self):
        for heel_out in (0, 4, 7):
            m, knee, ankle = self.leg(34, heel_out=heel_out)
            f = foot.fit_foot(m, knee, ankle, 5.0)
            self.assertAlmostEqual(f["length"], 34.0, delta=1.0)            # the drawn boot, not stretched
            self.assertAlmostEqual(f["pitch"], 0.0, delta=1.0)
            # re-seated: the heel's rear end is exactly `back` behind the ankle joint
            self.assertAlmostEqual(f["ankle"][0] - f["heel"][0], f["back"], delta=1.0)
            self.assertAlmostEqual(f["seat"][0], heel_out, delta=1.5)       # moved forward by the overhang
            self.assertGreater(f["toe"][0], f["ankle"][0] + f["front"])     # toe ahead of the front edge
            self.assertAlmostEqual(f["toe"][0] - f["heel"][0], f["length"], delta=0.01)

    def test_reseat_moves_pixels_without_stretching(self):
        img = np.zeros((20, 30, 4), np.uint8)
        img[10:14, 5:15] = 255
        out = foot.reseat(img, (4, -1))
        self.assertEqual(int((out[..., 3] > 0).sum()), int((img[..., 3] > 0).sum()))
        self.assertTrue((out[9:13, 9:19, 3] > 0).all())

    def test_plantar_limit_keeps_heel_on_the_back_edge(self):
        back, h, tol = 20.0, 14.0, 5.6
        lim = foot.plantar_limit(back, h, tol)
        r = np.radians(lim)
        self.assertLessEqual(h * np.sin(r) - back * (1 - np.cos(r)), tol)
        self.assertGreater(lim, 5.0)
        self.assertLess(foot.plantar_limit(back, 40.0, tol), lim)   # a taller ankle allows less

    def test_walk_never_plantarflexes_past_the_limit(self):
        png, js = still("HR4.2")
        ch = Character.from_still(png, js)
        g = Gait(ch.rig, ch.walk_motion())
        self.assertLessEqual(g.plantar_max, -SWING_ANKLE[0])
        for i in range(32):
            a = joint_angles(ch.rig.fk(g.pose(i / 32)[0]), ch.rig.rest["lean"])
            for s in ("near", "far"):
                self.assertGreaterEqual(a[s + ".ankle"], -g.plantar_max - 0.6, (i, s))

    def test_r6_holds_for_three_stills_the_old_model_refused(self):
        # HR1.2, HR2.2 were R6 rejections ("short boots on steep shins"): the boots are long
        # enough, the old model measured them from the wrong heel
        for name in ("HR1.2", "HR2.2"):
            ch = Character.from_still(*still(name))
            for n, (fr, ctx, fails) in bake_all(ch, (4, 8)).items():
                self.assertEqual([f for f in fails if "heel_flush" in f], [], name)

    def test_g9_short_boot(self):
        t = foot.foot_faults(30.0, 170.0, 12.0, 9.0, 9.0, (SWING_ANKLE[0], STANCE_DORSI_MAX))
        self.assertTrue(any("too short" in x and "not stretched" in x for x in t), t)
        self.assertEqual(foot.foot_faults(48.0, 170.0, 12.0, 9.0, 12.0, (SWING_ANKLE[0], STANCE_DORSI_MAX)), [])
        # and through the gate, on a real fitted still with its boot shortened
        _, data, _ = fit_still(*still("HR4.2"))
        d = copy.deepcopy(data)
        d["foot_fit"]["length"] = 0.15 * 170
        out = [x for x, _ in gate_still(d)]
        self.assertTrue(any(x.startswith("G9:") and "too short" in x for x in out), out)

    def test_g9_boot_shorter_than_shin_is_wide(self):
        t = foot.foot_faults(46.0, 160.0, 23.0, 30.0, 12.0, (SWING_ANKLE[0], STANCE_DORSI_MAX))
        self.assertTrue(any("shin's width" in x for x in t), t)
        _, data, _ = fit_still(*still("HR2.4"))        # a sword along the leg widens the shin
        out = [x for x, _ in gate_still(data)]
        self.assertTrue(any(x.startswith("G9:") for x in out), out)


class TestSpec(unittest.TestCase):
    """A character drawn exactly on STILL_SPEC.md passes every G rule (and then every R rule)."""

    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix="anim_spec_")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.dir, ignore_errors=True)

    def test_spec_writes_pose_and_joints(self):
        from PIL import Image
        for b in spec.BUILDS:
            p = spec.write(b, self.dir)
            with Image.open(p["pose"]) as im:
                self.assertEqual(im.size, spec.CANVAS)
            with open(p["joints"]) as f:
                lay = json.load(f)
            for k in ("head", "neck", "pelvis", "near_shoulder", "near_elbow", "near_wrist", "near_hip",
                      "near_knee", "near_ankle", "near_toe", "far_hip", "far_knee", "far_ankle", "far_toe"):
                self.assertIn(k, lay["joints"])
            self.assertEqual(lay["ground_y"], spec.GROUND_Y)
            self.assertGreaterEqual(spec.arm_gap(b), spec.ARM_GAP * spec.BUILDS[b]["bh"], b)
            J = {k: np.array(v) for k, v in spec.joints(b).items()}
            self.assertGreater(J["near_toe"][0], J["near_heel"][0])      # feet point right
            self.assertGreater(J["far_toe"][0], J["far_heel"][0])
            self.assertGreater(J["near_ankle"][0], J["far_ankle"][0])    # near leg forward
            step = (J["near_heel"][0] - J["far_heel"][0]) / spec.BUILDS[b]["bh"]
            self.assertAlmostEqual(step, spec.STEP, places=2)

    def test_character_on_spec_passes_every_g_rule(self):
        for b in spec.BUILDS:
            p = spec.write(b, self.dir)
            fitted = fit_still(p["reference"], p["joints"])
            self.assertEqual(gate_still(fitted[1]), [], b)
            self.assertGreaterEqual(fitted[1]["fit"]["score"], 0.99, b)
            ch = Character.from_still(p["reference"], p["joints"], fitted=fitted)
            self.assertEqual(gate_cut(ch.info), [], b)

    def test_character_on_spec_walks_clean(self):
        for b in spec.BUILDS:
            p = spec.write(b, self.dir)
            ch = Character.from_still(p["reference"], p["joints"])
            for n, (fr, ctx, fails) in bake_all(ch, (4, 8)).items():
                self.assertEqual(fails, [], f"{b} walk{n}")

    def test_cli(self):
        from tools.animator.__main__ import main
        out = os.path.join(self.dir, "cli")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(["spec", "--build", "dwarf", "--out", out]), 0)
        self.assertEqual(sorted(os.listdir(out)), ["dwarf_joints.json", "dwarf_pose.png", "dwarf_reference.png"])


if __name__ == "__main__":
    unittest.main()
