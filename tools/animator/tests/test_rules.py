"""Rulebook (RULES.md), input gate, cloth, skf and batch tests."""
import copy
import inspect
import io
import json
import os
import re
import shutil
import tempfile
import unittest
import zipfile

import numpy as np

from helpers import ROOT

from tools.animator import autocut, checks, fit
from tools.animator.cloth import pendulum
from tools.animator.fit import fit_still, gate_still

import test_animator

HERE = os.path.join(ROOT, "tools", "animator")
STILLS = os.path.join(HERE, "samples", "stills")
GOOD = "HR4.2"       # a still that passes every rule (HR6.1 was the example until the owner saw
                     # its third arm: it now fails G8)
OWNER_RULES = {"R1", "R4", "R5", "R6", "R17", "R19", "G8", "G9", "G10", "G11"}   # third leg, crooked elbow, backwards foot,
                                                            # heel, third arm (output and input), short boot


def read_rulebook():
    """RULES.md lines "R1 | owner | text | check: module.func | test: Class.test_name"."""
    rules = {}
    with open(os.path.join(HERE, "RULES.md")) as f:
        for line in f:
            m = re.match(r"^\s*([RG]\d+)\s*\|(.*)$", line)
            if not m:
                continue
            cols = [c.strip() for c in m.group(2).split("|")]
            rec = {"owner": cols[0] == "owner", "text": cols[1]}
            for c in cols[2:]:
                k, _, v = c.partition(":")
                rec[k.strip()] = v.strip()
            rules[m.group(1)] = rec
    return rules


def test_classes():
    import test_rules
    import test_arms_feet
    import test_intake
    out = {}
    for mod in (test_animator, test_rules, test_arms_feet, test_intake):
        for name, obj in inspect.getmembers(mod, inspect.isclass):
            if issubclass(obj, unittest.TestCase):
                out[name] = obj
    return out


class TestRulebook(unittest.TestCase):
    def test_every_rule_has_check_and_failing_test(self):
        rules = read_rulebook()
        self.assertTrue(rules)
        classes = test_classes()
        mods = {"checks": checks, "fit": fit, "autocut": autocut}
        for rid, r in rules.items():
            self.assertTrue(r["text"], rid)
            mod, _, fn = r.get("check", "").partition(".")
            self.assertIn(mod, mods, f"{rid}: no check")
            self.assertTrue(callable(getattr(mods[mod], fn, None)), f"{rid}: check {r.get('check')} missing")
            tests = [t.strip() for t in r.get("test", "").split(",") if t.strip()]
            self.assertTrue(tests, f"{rid}: no failing-example test")
            for t in tests:
                cls, _, meth = t.partition(".")
                self.assertIn(cls, classes, f"{rid}: test class {cls} missing")
                self.assertTrue(meth.startswith("test_") and hasattr(classes[cls], meth),
                                f"{rid}: test {t} missing")

    def test_owner_rules_kept(self):
        rules = read_rulebook()
        for rid in OWNER_RULES:
            self.assertIn(rid, rules, f"owner rule {rid} dropped")
            self.assertTrue(rules[rid]["owner"], f"{rid} lost its owner mark")

    def test_every_check_and_rule_number_is_listed(self):
        rules = read_rulebook()
        listed = {r["check"] for r in rules.values()}
        for f in checks.RULES:
            self.assertIn("checks." + f.__name__, listed, f"checks.{f.__name__} not in RULES.md")
        for rid in set(checks.RULE_IDS.values()):
            self.assertIn(rid, rules, f"{rid} used by checks.rule_id but not in RULES.md")
        for name, fn in (("fit.gate_still", fit.gate_still), ("autocut.gate_cut", autocut.gate_cut)):
            for gid in set(re.findall(r'"(G\d+):', inspect.getsource(fn))):
                self.assertIn(gid, rules, f"{gid} used by the gate but not in RULES.md")
                self.assertEqual(rules[gid]["check"], name, gid)


class TestGate(unittest.TestCase):
    """Each input-gate rule must reject a deliberately broken fitted still."""

    @classmethod
    def setUpClass(cls):
        png = os.path.join(STILLS, GOOD + ".png")
        cls.img, cls.data, cls.masks = fit_still(png, png[:-4] + ".json")

    def broken(self):
        return copy.deepcopy(self.data)

    def gate_fails(self, data, gid):
        out = [t for t, _ in gate_still(data)]
        self.assertTrue(any(t.startswith(gid + ":") for t in out), (gid, out))

    def test_good_still_passes(self):
        self.assertEqual(gate_still(self.data), [])

    def test_g1_missing_leg(self):
        d = self.broken()
        d["fit"]["flags"].append("two feet not found")
        self.gate_fails(d, "G1")

    def test_g2_long_thigh(self):
        d = self.broken()
        J = d["joints"]
        hip, knee = np.array(J["hip"], float), np.array(J["knee"], float)
        shift = (knee - hip) * 1.5
        for k in ("knee", "ankle", "heel", "toe"):
            J[k] = list(np.array(J[k], float) + shift)
        self.gate_fails(d, "G2")

    def test_g3_knee_bent_forward(self):
        d = self.broken()
        J = d["joints"]
        h, a, k = (np.array(J[n], float) for n in ("hip", "ankle", "knee"))
        u = (a - h) / np.hypot(*(a - h))
        proj = h + u * ((k - h) @ u)
        J["knee"] = list(proj - [0.25 * np.hypot(*(a - h)), 0])   # knee well behind the hip-ankle line
        self.gate_fails(d, "G3")

    def test_g3_elbow_bent_backwards(self):
        d = self.broken()
        J = d["joints"]
        s, e = np.array(J["shoulder"], float), np.array(J["elbow"], float)
        up = e - s
        a = np.radians(60)
        r = np.array([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
        J["wrist"] = list(e + r @ up)
        self.gate_fails(d, "G3")

    def test_g4_foot_backwards(self):
        d = self.broken()
        J = d["joints"]
        J["heel"], J["toe"] = J["toe"], J["heel"]
        self.gate_fails(d, "G4")

    def test_g5_low_score(self):
        d = self.broken()
        d["fit"]["score"] = 0.2
        self.gate_fails(d, "G5")

    def test_g6_arm_over_body(self):
        d = self.broken()
        d["fit"]["flags"].append("arm drawn over the body (hand blob on the torso)")
        self.gate_fails(d, "G6")


    def test_g7_shield_cut_through(self):
        # real failing example: HR6.2's strapped shield is split between forearm and torso
        from tools.animator.bake import Character
        png = os.path.join(STILLS, "HR6.2.png")
        ch = Character.from_still(png, png[:-4] + ".json")
        out = [t for t, _ in autocut.gate_cut(ch.info)]
        self.assertTrue(any(t.startswith("G7:") for t in out), out)
        good = Character.from_still(os.path.join(STILLS, GOOD + ".png"), os.path.join(STILLS, GOOD + ".json"),
                                    fitted=(self.img, self.data, self.masks))
        self.assertEqual(autocut.gate_cut(good.info), [])


class TestCloth(unittest.TestCase):
    def test_pendulum_periodic_and_lags(self):
        n = 64
        p = np.arange(n) / n
        u = np.sin(2 * np.pi * p)
        h = pendulum(u)
        self.assertEqual(len(h), n)
        self.assertTrue(np.isfinite(h).all())
        self.assertAlmostEqual(float(np.mean(h)), 0.0, 9)
        # a lag: the response peaks after the driver
        self.assertGreater(int(np.argmax(h)), int(np.argmax(u)))
        np.testing.assert_array_equal(h, pendulum(u))        # deterministic


class TestSkf(test_animator.Base):
    def test_zip_and_json_well_formed(self):
        from tools.animator.skf import write_skf
        path = os.path.join(self.tmp, "t.skf")
        write_skf(self.ch, self.frames, self.ctx, path)
        with zipfile.ZipFile(path) as z:
            self.assertIsNone(z.testzip())
            self.assertEqual(set(z.namelist()), {"armature.json", "atlas0.png", "readme.md"})
            arm = json.loads(z.read("armature.json"))
            from PIL import Image
            atlas = Image.open(io.BytesIO(z.read("atlas0.png")))
            self.assertIn("UNVERIFIED", z.read("readme.md").decode())
        ids = [b["id"] for b in arm["bones"]]
        self.assertEqual(ids, list(range(len(ids))))
        names = {b["name"] for b in arm["bones"]}
        for b in arm["bones"]:
            self.assertLess(b["parent_id"], b["id"])            # parents first
        tex = {t["name"]: t for t in arm["styles"][0]["textures"]}
        for b in arm["bones"]:
            if b["tex"]:
                self.assertIn(b["tex"], tex)
        aw, ah = arm["atlases"][0]["size"]["x"], arm["atlases"][0]["size"]["y"]
        self.assertEqual(atlas.size, (aw, ah))
        for t in tex.values():
            self.assertLessEqual(t["offset"]["x"] + t["size"]["x"], aw)
            self.assertLessEqual(t["offset"]["y"] + t["size"]["y"], ah)
        kfs = arm["animations"][0]["keyframes"]
        self.assertTrue(kfs)
        self.assertEqual({k["frame"] for k in kfs}, set(range(len(self.frames))))
        for k in kfs:
            self.assertIn(k["bone_name"], names)
            self.assertTrue(np.isfinite(k["value"]))


class TestBatch(unittest.TestCase):
    def test_rejected_still_writes_nothing_accepted(self):
        tmp = tempfile.mkdtemp()
        try:
            src = os.path.join(tmp, "in")
            os.makedirs(src)
            for ext in (".png", ".json"):
                shutil.copy(os.path.join(STILLS, GOOD + ext), os.path.join(src, GOOD + ext))
            # a broken copy: the layout's front leg is replaced by nonsense, so the fit fails
            shutil.copy(os.path.join(STILLS, GOOD + ".png"), os.path.join(src, "BAD.png"))
            with open(os.path.join(STILLS, GOOD + ".json")) as f:
                lay = json.load(f)
            from PIL import Image
            im = np.array(Image.open(os.path.join(src, "BAD.png")).convert("RGBA"))
            im[int(im.shape[0] * 0.55):, :, 3] = 0             # legs cut off
            Image.fromarray(im).save(os.path.join(src, "BAD.png"))
            with open(os.path.join(src, "BAD.json"), "w") as f:
                json.dump(lay, f)
            from tools.animator.batch import run
            acc, rej = run(src, os.path.join(tmp, "out"), skf=False, log=lambda *a: None)
            self.assertEqual([c for c, _ in acc], [GOOD])
            self.assertEqual([c for c, _ in rej], ["BAD"])
            self.assertEqual(os.listdir(os.path.join(tmp, "out", "accepted")), [GOOD])
            self.assertTrue(os.path.exists(os.path.join(tmp, "out", "needs_attention", "BAD.png")))
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main()
