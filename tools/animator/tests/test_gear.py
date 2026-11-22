"""Gear as attachments (gear.py): body + gear format, rules R20-R25 and G12-G15, each with a
failing example; the worked example and the split HR6.1 paladin at 56 and 112 px."""
import copy
import json
import os
import shutil
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw

from helpers import ROOT

from tools.animator import batch, checks, gear, spec
from tools.animator.bake import Character, bake_motion
from tools.animator.fit import fit_still, gate_still

import fixtures

HERE = os.path.join(ROOT, "tools", "animator")


def rules_of(fails):
    return {t.split(":")[0] for t, _ in fails}


class GearBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix="anim_gear_")
        cls.png = spec.write_example(cls.dir)
        cls.ch = Character.from_still(cls.png, cls.png[:-4] + ".json")
        cls.frames, cls.ctx = bake_motion(cls.ch, cls.ch.walk_motion(), 8)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.dir, ignore_errors=True)

    def fresh(self):
        fr = [{"rgba": f["rgba"].copy(), "label": f["label"].copy(), "meta": copy.deepcopy(f["meta"]),
               "body": {k: v.copy() for k, v in f["body"].items()}} for f in self.frames]
        return fr, self.ctx

    def rule_fails(self, rule, frames, ctx, word):
        out = rule(frames, ctx)
        self.assertTrue(out, f"{rule.__name__} should fail")
        self.assertTrue(any(word in o for o in out), out)
        self.assertTrue(all(checks.rule_id(o) != "R?" for o in out), out)

    def body_variant(self, name, draw=None, edit=None, layout=None):
        """The example's body still, changed, fitted and gated: the set of failed G rules."""
        im = Image.open(self.png).convert("RGBA")
        if draw:
            draw(ImageDraw.Draw(im))
        a = np.array(im)
        if edit:
            edit(a)
        d = os.path.join(self.dir, name)
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, name + ".png")
        Image.fromarray(a, "RGBA").save(p)
        with open(self.png[:-4] + ".json") as f:
            lay = json.load(f)
        lay.update(layout or {})
        with open(p[:-4] + ".json", "w") as f:
            json.dump(lay, f)
        fails = gate_still(fit_still(p, p[:-4] + ".json")[1])
        return rules_of(fails), [t for t, _ in fails]


class TestGearBake(GearBase):
    def test_example_passes_every_rule(self):
        self.assertEqual(checks.run_all(self.frames, self.ctx), [])
        self.assertEqual(gate_still(fit_still(self.png, self.png[:-4] + ".json")[1]), [])
        self.assertEqual(gear.gate_gear(self.ch.gear), [])

    def test_gear_is_layered_not_merged(self):
        names = self.frames[0]["meta"]["labels"]
        self.assertIn("gear:shield", names)
        self.assertIn("gear:hammer", names)
        self.assertNotIn("gear:shield", self.ch.parts)           # never a cut part of the body
        for f in self.frames:
            g = f["label"] >= min(names.index("gear:hammer"), names.index("gear:shield"))
            # where no gear shows, the frame is the body frame untouched
            self.assertTrue((f["rgba"][~g] == f["body"]["rgba"][~g]).all())
            # the shield is behind the torso and the near arm, in front of the far arm
            L = f["meta"]["gear"]["gear:shield"]
            self.assertLess(L["rank"], names.index("torso"))
            self.assertGreater(L["rank"], names.index("far_fore"))
            self.assertTrue((f["label"] == names.index("gear:shield")).any())

    def test_back_gear_has_one_hash_in_all_frames(self):
        hs = {f["meta"]["gear"]["gear:shield"]["rgba"].tobytes() for f in self.frames}
        self.assertEqual(len(hs), 1)

    def test_r20_gear_pixel_changed(self):
        fr, ctx = self.fresh()
        names = fr[3]["meta"]["labels"]
        ys, xs = np.where(fr[3]["label"] == names.index("gear:shield"))
        fr[3]["rgba"][ys[0], xs[0], :3] = fr[3]["rgba"][ys[0], xs[0], :3] // 2 + 60
        self.rule_fails(checks.gear_rigid, fr, ctx, "gear:shield")
        fr, ctx = self.fresh()                                   # the layer itself redrawn
        L = fr[5]["meta"]["gear"]["gear:hammer"]
        L["rgba"] = L["rgba"].copy()
        ys, xs = np.where(L["rgba"][..., 3] > 0)
        L["rgba"][ys[0], xs[0]] = 0
        self.rule_fails(checks.gear_rigid, fr, ctx, "gear:hammer")

    def test_r21_grip_off_the_hand(self):
        fr, ctx = self.fresh()
        fr[2]["meta"]["gear"]["gear:hammer"]["grip"][0] += 2.0
        self.rule_fails(checks.gear_grip, fr, ctx, "gear:hammer")
        self.assertEqual(checks.gear_grip(*self.fresh()), [])

    def test_r22_back_gear_over_the_near_arm(self):
        fr, ctx = self.fresh()
        names = fr[1]["meta"]["labels"]
        arm = fr[1]["body"]["label"] == names.index("near_upper")
        self.assertTrue(arm.any())
        fr[1]["label"][arm] = names.index("gear:shield")
        self.rule_fails(checks.gear_back, fr, ctx, "near arm")

    def test_r23_gear_over_the_head(self):
        fr, ctx = self.fresh()
        names = fr[0]["meta"]["labels"]
        neck = int(fr[0]["meta"]["joints"]["neck"][1])
        head = fr[0]["body"]["label"] > 0
        head[neck:] = False
        fr[0]["label"][head] = names.index("gear:hammer")
        self.rule_fails(checks.gear_head, fr, ctx, "head")

    def test_r24_loose_blob_in_a_frame(self):
        fr, ctx = self.fresh()
        fr[4]["rgba"][70:72, 6:10] = (90, 60, 30, 255)           # a loose stick behind the heels
        self.rule_fails(checks.loose_blobs, fr, ctx, "loose_blob")
        self.assertEqual(checks.loose_blobs(*self.fresh()), [])

    def test_r25_weapon_across_the_legs(self):
        fr, ctx = self.fresh()
        names = fr[0]["meta"]["labels"]
        L = fr[0]["meta"]["gear"]["gear:hammer"]
        ys, xs = np.where(fr[0]["body"]["label"] == names.index("near_shin"))
        L["at"] = [int(xs.mean()) - L["rgba"].shape[1] // 2, int(ys.mean()) - L["rgba"].shape[0] // 2]
        self.rule_fails(checks.gear_legs, fr, ctx, "gear:hammer")

    def test_hand_gear_makes_a_carried_arm(self):
        self.assertIn("near", self.ctx["steady_arms"])


class TestBodyStill(GearBase):
    """G12, G13, G15: what a bare body still may not contain."""

    def test_layout_marks_the_still_as_body_only(self):
        for b in spec.BUILDS:
            self.assertEqual(spec.layout(b)["format"], "body")

    def test_g12_shield_drawn_into_the_body(self):
        def draw(d):
            d.ellipse([70, 150, 170, 290], fill=(200, 160, 40, 255))
            d.ellipse([80, 160, 160, 280], fill=(60, 20, 20, 255))
        ids, texts = self.body_variant("shield_in", draw)
        self.assertIn("G12", ids)
        self.assertTrue(any("rimmed blob" in t for t in texts), texts)

    def test_g12_staff_drawn_into_the_body(self):
        ids, texts = self.body_variant("staff_in", lambda d: d.line([(262, 60), (262, 330)], fill=(120, 84, 48, 255), width=8))
        self.assertIn("G12", ids)
        self.assertTrue(any("long thin rigid" in t for t in texts), texts)

    def test_g12_hammer_in_the_hand(self):
        def draw(d):
            d.rectangle([272, 196, 318, 244], fill=(150, 154, 166, 255), outline=(16, 14, 14, 255))
        ids, texts = self.body_variant("hammer_in", draw)
        self.assertIn("G12", ids)
        self.assertTrue(any("something is held" in t for t in texts), texts)

    def test_g12_cape_drawn_into_the_body(self):
        ids, texts = self.body_variant("cape_in", lambda d: d.polygon([(150, 120), (150, 250), (70, 260), (100, 120)],
                                                                      fill=(120, 30, 40, 255)))
        self.assertIn("G12", ids)
        self.assertTrue(any("behind the back" in t for t in texts), texts)

    def test_g12_real_still_with_gear_drawn_in(self):
        # HR6.1 as it was drawn (shield and hammer in the picture), handed in as a body still
        src = os.path.join(HERE, "samples", "stills_spec", "HR6.1")
        d = os.path.join(self.dir, "hr61_body")
        os.makedirs(d, exist_ok=True)
        shutil.copy(src + ".png", os.path.join(d, "X.png"))
        with open(src + ".json") as f:
            lay = json.load(f)
        lay["format"] = "body"
        with open(os.path.join(d, "X.json"), "w") as f:
            json.dump(lay, f)
        texts = [t for t, _ in gate_still(fit_still(os.path.join(d, "X.png"), os.path.join(d, "X.json"))[1])]
        self.assertTrue(any(t.startswith("G12") and "rimmed blob" in t for t in texts), texts)
        self.assertTrue(any(t.startswith("G12") and "something is held" in t for t in texts), texts)

    def test_g13_loose_stick_in_the_still(self):
        ids, texts = self.body_variant("loose", lambda d: d.line([(60, 418), (96, 410)], fill=(120, 84, 48, 255), width=5))
        self.assertIn("G13", ids)
        ids, _ = self.body_variant("dust", lambda d: d.rectangle([40, 40, 41, 41], fill=(120, 84, 48, 255)))
        self.assertNotIn("G13", ids)                             # 4 px of keying dust are dropped

    def test_g15_bare_legs(self):
        def edit(a):
            for c in ((72, 78, 104), (46, 50, 68)):                 # both trouser colours -> skin
                a[(a[..., :3] == c).all(-1), :3] = (226, 172, 132)
        ids, texts = self.body_variant("bare", edit=edit)
        self.assertIn("G15", ids)
        self.assertTrue(any("different from the skin" in t for t in texts), texts)


class TestGearPictures(GearBase):
    def make(self, **kw):
        s = dict(spec.GEAR_GUIDES["one_hand_weapon"]["json"])
        s.update(kw)
        return gear.Gear("g", spec.example_gear("one_hand_weapon"), s)

    def test_g14_gear_picture(self):
        bad = {"slot": dict(slot="belt"), "size": dict(size=2.0), "anchor": dict(anchor=[500, 20]),
               "grip": dict(anchor=[34, 300])}
        for word, kw in bad.items():
            out = gear.gate_gear([self.make(**kw)])
            self.assertTrue(out and all(t.startswith("G14: gear_picture") for t, _ in out), (word, out))
        im = spec.example_gear("one_hand_weapon")
        ImageDraw.Draw(im).rectangle([4, 300, 20, 320], fill=(200, 0, 0, 255))      # a second piece
        out = gear.gate_gear([gear.Gear("g", im, spec.GEAR_GUIDES["one_hand_weapon"]["json"])])
        self.assertTrue(any("loose piece" in t for t, _ in out), out)
        two = [self.make(), self.make()]
        self.assertTrue(any("already taken" in t for t, _ in gear.gate_gear(two)))
        self.assertEqual(gear.gate_gear([self.make()]), [])

    def test_every_guide_kind_bakes_clean(self):
        # staff + cape on the elf, two-hand weapon on the orc: every rule at 56 px
        for build, gs in (("elf", (("staff", "staff"), ("cape", "cape"))), ("orc", (("maul", "two_hand_weapon"),)),
                          ("dwarf", (("shield", "shield"), ("axe", "one_hand_weapon")))):
            png = spec.write_example(os.path.join(self.dir, build), "X_" + build, build, gs)
            fitted = fit_still(png, png[:-4] + ".json")
            self.assertEqual(gate_still(fitted[1]), [], build)
            ch = Character.from_still(png, png[:-4] + ".json", fitted=fitted)
            self.assertEqual(gear.gate_gear(ch.gear), [], build)
            fr, ctx = bake_motion(ch, ch.walk_motion(), 8)
            self.assertEqual(checks.run_all(fr, ctx), [], build)

    def test_spec_gear_cli(self):
        from tools.animator.__main__ import main
        out = os.path.join(self.dir, "guides")
        self.assertEqual(main(["spec", "--gear", "--out", out]), 0)
        for kind, g in spec.GEAR_GUIDES.items():
            with Image.open(os.path.join(out, f"gear_{kind}_guide.png")) as im:
                self.assertEqual(im.size, g["size"])
                self.assertEqual(im.getpixel(tuple(g["anchor"]))[:3], (255, 255, 0))   # the anchor cross
            with open(os.path.join(out, f"gear_{kind}.json")) as f:
                j = json.load(f)
            self.assertIn(j["slot"], gear.SLOTS)
            self.assertEqual(j["anchor"], list(g["anchor"]))


class TestGearBatch(unittest.TestCase):
    """The worked example and the split HR6.1 through the whole batch at 56 and 112 px."""

    def test_example_and_split_paladin_are_accepted_at_both_sizes(self):
        tmp = tempfile.mkdtemp(prefix="anim_gearbatch_")
        try:
            src = os.path.join(tmp, "in")
            spec.write_example(src)
            fixtures.split_hr61(src)
            acc, rej = batch.run(src, os.path.join(tmp, "out"), skf=False, log=lambda *_: None)
            self.assertEqual(rej, [])
            self.assertEqual(sorted(c for c, _ in acc), ["HR6.1_SPLIT", "PAL_SYN"])
            for cid in ("HR6.1_SPLIT", "PAL_SYN"):
                for sub in ("", "h112"):
                    self.assertTrue(os.path.exists(os.path.join(tmp, "out", "accepted", cid, sub, cid + "_walk8_r.png")))
                with open(os.path.join(tmp, "out", "accepted", cid, cid + "_parts", "rig.json")) as f:
                    parts = json.load(f)["parts"]
                self.assertEqual(parts["gear:shield"]["slot"], "back")
                self.assertEqual(parts["gear:hammer"]["parent"], "near_fore")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_samples_folder_matches_the_generators(self):
        d = os.path.join(HERE, "samples", "stills_gear")
        for cid in ("PAL_SYN", "HR6.1_SPLIT"):
            for f in (cid + ".png", cid + ".json", cid + "_gear/shield.png", cid + "_gear/shield.json",
                      cid + "_gear/hammer.png", cid + "_gear/hammer.json"):
                self.assertTrue(os.path.exists(os.path.join(d, f)), f)


if __name__ == "__main__":
    unittest.main()
