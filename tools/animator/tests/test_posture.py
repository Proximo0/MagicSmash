"""R31 posture: the walker stands up (trunk upright to slightly forward, standing leg nearly straight, pelvis at
walking height), and the gait stands a still that leans back upright."""
import copy
import unittest

from helpers import make_files

from tools.animator import checks
from tools.animator.bake import Character, bake_motion
from tools.animator.motion import Gait, walk, fit_walk, GAIN_MIN
from tools.animator.rig import Rig


class TestPosture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        png, js, cls.tmp = make_files()
        cls.ch = Character(png, js)
        cls.frames, cls.ctx = bake_motion(cls.ch, cls.ch.walk_motion(), 8)

    def test_r31_passes_the_baked_walk(self):
        self.assertEqual(checks.posture(self.frames, self.ctx), [])

    def test_r31_refuses_a_trunk_leaning_back_and_a_seated_stance(self):
        frames, ctx = copy.deepcopy(self.frames), copy.deepcopy(self.ctx)
        for f in frames:
            J = f["meta"]["joints"]
            J["neck"] = [J["pelvis"][0] - 8.0, J["neck"][1]]     # shoulders behind the hips
        out = checks.posture(frames, ctx)
        self.assertTrue(any("trunk leans" in o and "back" in o for o in out), out)
        self.assertTrue(all(o.startswith("frame ") for o in out), out)
        self.assertEqual(checks.rule_id(out[0]), "R31")
        frames, ctx = copy.deepcopy(self.frames), copy.deepcopy(self.ctx)
        for f in frames:
            f["meta"]["joints"]["pelvis"][1] += 0.4 * (ctx["lengths"]["near.thigh"] + ctx["lengths"]["near.shin"])   # pelvis dropped: a squat
        out = checks.posture(frames, ctx)
        self.assertTrue(any("seated" in o for o in out), out)

    def test_a_still_leaning_back_is_stood_upright(self):
        data = copy.deepcopy(self.ch.rig.data)
        data["joints"]["neck"] = [data["joints"]["pelvis"][0] - 12.0, data["joints"]["neck"][1]]
        rig = Rig(data)
        self.assertLess(rig.rest["lean"], -5.0)
        gait = Gait(rig, fit_walk(rig, 20.0))
        for i in range(8):
            self.assertTrue(0.0 <= gait.lean(i / 8) <= 6.0, gait.lean(i / 8))

    def test_gain_goes_below_one_for_a_short_step(self):
        self.assertLess(fit_walk(self.ch.rig, 10.0).gain, 1.0)
        self.assertGreaterEqual(fit_walk(self.ch.rig, 1.0).gain, GAIN_MIN)


if __name__ == "__main__":
    unittest.main()
