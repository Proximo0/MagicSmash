"""Monsters (monster.py, monster_checks.py, monster_example.py): the table, every plan's cycle, rules M1-M12 each with a
failing and a passing example, the spec files and the examples."""
import copy
import inspect
import json
import math
import os
import re
import tempfile
import unittest

import numpy as np
from PIL import Image

from helpers import ROOT

from tools.animator import monster as mo, monster_checks as mc, monster_example as ex

HERE = os.path.join(ROOT, "tools", "animator")
_CACHE = {}


def example(name):
    """(baked {(n, size): Baked}, still rgba, data, layout) of a synthetic example (cached)."""
    if name not in _CACHE:
        plan, style, size, speed = ex.EXAMPLES[name]
        lay = mo.make_layout(plan, style)
        rgba = ex.draw_creature(lay)
        data = ex.joints_json(lay, plan, style, size=size, speed=speed, note=False)
        r, errs = mo.resolve(data)
        assert not errs, errs
        baked = {}
        for sc in mo.SIZES:
            for n, b in mo.bake_set(lay, style, rgba, data, size, speed, sc).items():
                baked[(n, sc)] = b
        _CACHE[name] = (baked, rgba, data, lay)
    return _CACHE[name]


def broken(name, n=8, sc=112):
    b = example(name)[0][(n, sc)]
    return copy.deepcopy(b)


def find_gap(frame, width=4, y_rows=None):
    """x of `width` empty columns inside the frame's ground band (a place for a stray leg)."""
    a = frame["rgba"][..., 3] > 0
    H, W = a.shape
    col = a[H - 8:].any(0)
    for x in range(6, W - width - 6):
        if not col[x - 1:x + width + 1].any():
            return x
    raise AssertionError("no gap")


class TestTable(unittest.TestCase):
    def test_42_kinds_each_with_a_plan(self):
        rows = mo.load_table()
        self.assertEqual(len(rows), 42)
        names = [r["kind"] for r in rows]
        self.assertEqual(len(set(names)), 42)
        src = open(os.path.join(ROOT, "realm", "core", "src", "tables", "kinds.rs")).read()
        self.assertEqual(re.findall(r'k\("([^"]+)", \d,', src), names)
        for r in rows:
            self.assertIn(r["plan"], mo.STYLES, r["kind"])
            self.assertIn(r["style"], mo.STYLES[r["plan"]], r["kind"])
            self.assertGreaterEqual(r["size_px"], 24)

    def test_sizes_follow_the_creature(self):
        s = {r["kind"]: r["size_px"] for r in mo.load_table()}
        self.assertLess(s["plague rat"], s["hound"])
        self.assertLess(s["hound"], s["scarecrow"])
        self.assertGreater(s["gravedigger"], 112)
        self.assertEqual(max(s.values()), 176)

    def test_markdown_is_generated_from_the_data(self):
        with open(os.path.join(HERE, "monsters.md")) as f:
            self.assertEqual(f.read(), mo.table_md())

    def test_plan_counts(self):
        c = {}
        for r in mo.load_table():
            c[r["plan"]] = c.get(r["plan"], 0) + 1
        self.assertEqual(c, {"biped": 19, "quadruped": 4, "crawler": 5, "flyer": 6, "floater": 4, "construct": 4})


class TestCycles(unittest.TestCase):
    def test_every_example_loops_exactly_at_every_size(self):
        for name in ex.EXAMPLES:
            for (n, sc), b in example(name)[0].items():
                self.assertEqual(mc.loop_closes(b), [], (name, n, sc))

    def test_four_frame_cycle_is_every_second_frame_of_the_eight(self):
        for name in ex.EXAMPLES:
            baked = example(name)[0]
            for sc in mo.SIZES:
                for k in range(4):
                    self.assertTrue(np.array_equal(baked[(4, sc)].frames[k]["rgba"], baked[(8, sc)].frames[2 * k]["rgba"]), (name, sc, k))

    def test_feet_plant_and_stride_matches_travel(self):
        for name in ("ex_biped", "ex_quadruped", "ex_crawler_skitter"):
            for key, b in example(name)[0].items():
                self.assertEqual(mc.foot_slide(b), [], (name, key))
                self.assertGreater(b.meta["stride_px"], 0)
                m = b.meta
                # the game plays it at speed / stride cycles a second
                self.assertAlmostEqual(m["cycles_per_s"] * m["stride_px"] * 112 / m["size"], m["speed_px_s"], 6)

    def test_stance_foot_moves_back_by_the_travel_of_a_frame(self):
        b = example("ex_quadruped")[0][(8, 112)]
        f = [x["meta"]["feet"]["front_near"] for x in b.frames + [b.closing]]
        steps = [f[k + 1][0] - f[k][0] for k in range(8) if f[k][2] and f[k + 1][2]]
        self.assertTrue(steps)
        for s in steps:
            self.assertAlmostEqual(s, -b.meta["travel_per_frame"], 5)

    def test_squash_keeps_area(self):
        lay = mo.make_layout("crawler", "squash")
        geo = mo.Geo(lay, "squash", {k: list(v) for k, v in lay.joints.items()}, 1.0, 100.0)
        for k in range(16):
            ang, dx, dy, sx, sy, z = mo.pose_for(lay, geo, k / 16)[0]["body"]
            self.assertAlmostEqual(sx * sy, 1.0, 9)

    def test_flap_and_bob_are_whole_harmonics(self):
        lay = mo.make_layout("flyer", "flap")
        geo = mo.Geo(lay, "flap", {k: list(v) for k, v in lay.joints.items()}, 1.0, 100.0)
        a, b = mo.pose_for(lay, geo, 0.0)[0], mo.pose_for(lay, geo, 1.0)[0]
        for k in a:
            for u, v in zip(a[k][:5], b[k][:5]):
                self.assertAlmostEqual(u, v, 9)

    def test_a_frame_holds_only_colours_of_the_still(self):
        baked, rgba, data, lay = example("ex_quadruped")
        b = baked[(8, 112)]
        img, _, _ = mo._scaled(rgba, b.meta["target"] / mo.bbox_long(rgba))
        pal = {tuple(p) for p in img[img[..., 3] > 0][:, :3]}
        for f in b.frames:
            got = {tuple(p) for p in f["rgba"][f["rgba"][..., 3] > 0][:, :3]}
            self.assertTrue(got <= pal)


class TestMonsterRules(unittest.TestCase):
    # M1
    def test_m1_fifth_leg_in_a_frame(self):
        b = broken("ex_quadruped")
        f = b.frames[7]
        g = int(b.meta["ground_row"])
        for _ in range(2):
            x = find_gap(f)
            f["rgba"][g - 6:g, x:x + 3] = (90, 70, 50, 255)
        self.assertTrue(any("legs stand on the ground" in t for t in mc.limb_count(b)))

    def test_m1_a_leg_with_no_pixels(self):
        b = broken("ex_biped")
        for f in b.frames:
            for p in b.meta["limb_groups"]["far_leg"]:
                f["meta"]["area"][p] = 0
                f["meta"]["visible"][p] = 0
        self.assertTrue(any("no pixels of its own" in t for t in mc.limb_count(b)))

    def test_m1_passes_every_example_with_the_documented_occlusion(self):
        for name in ex.EXAMPLES:
            for key, b in example(name)[0].items():
                self.assertEqual(mc.limb_count(b), [], (name, key))

    # M2
    def test_m2_loose_piece(self):
        b = broken("ex_floater")
        b.frames[2]["rgba"][4:7, 4:7] = (200, 50, 50, 255)
        b.frames[2]["label"][4:7, 4:7] = 0
        self.assertTrue(any("not connected" in t for t in mc.detached(b)))

    def test_m2_passes_and_allows_only_orbit_parts_apart(self):
        for name in ex.EXAMPLES:
            for key, b in example(name)[0].items():
                self.assertEqual(mc.detached(b), [], (name, key))
        # the orbit pieces are really apart from the core in some frame
        b = example("ex_flyer_orbit")[0][(8, 112)]
        self.assertTrue(any(len(mo and __import__("tools.animator.imgops", fromlist=["x"]).components(f["rgba"][..., 3] > 0)[1]) > 1
                            for f in b.frames))

    # M3
    def test_m3_part_on_the_canvas_edge(self):
        b = broken("ex_biped")
        b.frames[1]["rgba"][0, 10] = (1, 2, 3, 255)
        self.assertTrue(mc.canvas(b))

    def test_m3_passes(self):
        for name in ex.EXAMPLES:
            for key, b in example(name)[0].items():
                self.assertEqual(mc.canvas(b), [], (name, key))

    # M4
    def test_m4_cycle_not_closed(self):
        b = broken("ex_quadruped")
        b.closing["rgba"][10, 10] = (9, 9, 9, 255)
        self.assertTrue(mc.loop_closes(b))

    def test_m4_passes(self):
        self.assertEqual(mc.loop_closes(example("ex_flyer_flap")[0][(4, 56)]), [])

    # M5
    def test_m5_foot_sliding(self):
        b = broken("ex_quadruped")
        b.meta["travel_per_frame"] *= 1.7
        self.assertTrue(any("slides" in t for t in mc.foot_slide(b)))

    def test_m5_foot_off_the_ground(self):
        b = broken("ex_biped")
        for f in b.frames:
            for q in b.meta["leg_parts"]["near_leg"]:
                f["meta"]["bottom"][q] -= 5
        self.assertTrue(any("off the ground" in t for t in mc.foot_slide(b)))

    def test_m5_wrong_speed(self):
        b = broken("ex_quadruped")
        b.meta["speed_px_s"] *= 1.5
        self.assertTrue(any("speed" in t for t in mc.foot_slide(b)))

    def test_m5_passes_and_skips_legless(self):
        for name in ("ex_biped", "ex_quadruped", "ex_crawler_skitter", "ex_floater"):
            for key, b in example(name)[0].items():
                self.assertEqual(mc.foot_slide(b), [], (name, key))

    # M6
    def test_m6_area_jumps(self):
        b = broken("ex_crawler_squash")
        b.frames[3]["rgba"][:, : b.frames[3]["rgba"].shape[1] // 2] = 0
        self.assertTrue(mc.area_stable(b))

    def test_m6_passes_squash_and_flap(self):
        for name in ex.EXAMPLES:
            for key, b in example(name)[0].items():
                self.assertEqual(mc.area_stable(b), [], (name, key))

    # M7
    def test_m7_key_colour_in_a_frame(self):
        b = broken("ex_biped", 8, 56)
        b.frames[4]["rgba"][20, 20] = (255, 0, 255, 255)
        self.assertTrue(mc.key_colour(b))

    def test_m7_passes(self):
        self.assertEqual(mc.key_colour(example("ex_biped")[0][(8, 56)]), [])

    # M8
    def test_m8_no_eye(self):
        b = broken("ex_quadruped")
        hi = b.meta["parts"].index("head")
        for f in b.frames:
            f["rgba"][(f["label"] == hi) & (mc.luma(f["rgba"]) < mc.DARK_LUMA)] = (210, 200, 180, 255)
        self.assertTrue(mc.head_eye(b))

    def test_m8_passes_where_there_is_a_head_and_skips_headless(self):
        for name in ex.EXAMPLES:
            for key, b in example(name)[0].items():
                self.assertEqual(mc.head_eye(b), [], (name, key))
        b = broken("ex_construct_hop")
        self.assertIsNone(b.meta["head_part"])

    # M9
    def test_m9_wrong_size(self):
        b = broken("ex_biped")
        b.meta["target"] *= 2.5
        self.assertTrue(mc.size_band(b))

    def test_m9_passes(self):
        for name in ex.EXAMPLES:
            for key, b in example(name)[0].items():
                self.assertEqual(mc.size_band(b), [], (name, key))
        # at 56 the sprite is half of the 112 one
        e = example("ex_quadruped")[0]
        self.assertAlmostEqual(e[(8, 56)].meta["target"] * 2, e[(8, 112)].meta["target"])


class TestStillGate(unittest.TestCase):
    def gate(self, name, rgba=None, data=None):
        baked, r, d, lay = example(name)
        return mc.gate_still(r if rgba is None else rgba, d if data is None else data, lay)

    def test_every_example_still_passes(self):
        for name in ex.EXAMPLES:
            self.assertEqual(self.gate(name), [], name)

    # M10
    def test_m10_skeleton_off_the_drawing(self):
        d = copy.deepcopy(example("ex_quadruped")[2])
        for k in d["joints"]:
            if k.startswith("front_near"):
                d["joints"][k][0] += 120
        self.assertTrue(any(r == "M10" for r, _ in self.gate("ex_quadruped", data=d)))

    def test_m10_creature_touching_the_picture_edge(self):
        r = example("ex_quadruped")[1].copy()
        r[100:300, :6] = (150, 112, 80, 255)
        self.assertTrue(any(r_ == "M10" and "edge" in t for r_, t in self.gate("ex_quadruped", rgba=r)))

    def test_m10_thin_limbs_of_a_tiny_creature(self):
        lay = mo.make_layout("quadruped", "scurry")
        rgba = ex.draw_creature(lay)
        d = ex.joints_json(lay, "quadruped", "scurry", kind="plague rat", note=False)
        out = mc.gate_still(rgba, d, lay)
        self.assertTrue(any(r == "M10" and "px wide" in t for r, t in out), out)
        thick = {p.name: p.r * 2.2 for p in lay.parts if p.role in mc.LIMB_ROLES}
        d["radius"] = thick
        self.assertEqual(mc.gate_still(ex.draw_creature(lay, thick=thick), d, lay), [])

    def test_m10_passes(self):
        self.assertEqual([t for r, t in self.gate("ex_flyer_orbit") if r == "M10"], [])

    # M11
    def test_m11_five_legs(self):
        r = example("ex_quadruped")[1].copy()
        r[400:471, 232:246] = (118, 88, 64, 255)       # a fifth leg between the pairs, touching the belly
        r[290:400, 232:246] = (118, 88, 64, 255)
        out = self.gate("ex_quadruped", rgba=r)
        self.assertTrue(any(r_ == "M11" and "extra leg" in t for r_, t in out), out)

    def test_m11_leg_missing(self):
        r = example("ex_quadruped")[1].copy()
        r[300:, 300:350] = 0                            # front_near and front_far cut away
        self.assertTrue(any(r_ == "M11" and "no foot" in t for r_, t in self.gate("ex_quadruped", rgba=r)))

    def test_m11_loose_piece_and_key_colour(self):
        r = example("ex_floater")[1].copy()
        r[20:40, 20:40] = (10, 200, 10, 255)
        self.assertTrue(any("separate pieces" in t for _, t in self.gate("ex_floater", rgba=r)))
        r = example("ex_floater")[1].copy()
        r[250:254, 250:254] = (255, 0, 255, 255)
        self.assertTrue(any("key's colour" in t for _, t in self.gate("ex_floater", rgba=r)))

    def test_m11_orbit_plan_needs_its_pieces(self):
        r = example("ex_flyer_orbit")[1].copy()
        r[:, 400:] = 0
        self.assertTrue(any("floating pieces" in t for _, t in self.gate("ex_flyer_orbit", rgba=r)))

    def test_m11_passes(self):
        self.assertEqual([t for r, t in self.gate("ex_crawler_skitter") if r == "M11"], [])

    # M12
    def test_m12_missing_joint(self):
        d = copy.deepcopy(example("ex_biped")[2])
        del d["joints"]["near_leg_toe"]
        self.assertTrue(any(r == "M12" for r, _ in self.gate("ex_biped", data=d)))

    def test_m12_facing_left(self):
        d = copy.deepcopy(example("ex_quadruped")[2])
        d["joints"]["nose"][0] = 10
        self.assertTrue(any("face right" in t for _, t in self.gate("ex_quadruped", data=d)))

    def test_m12_bad_format_and_plan(self):
        self.assertTrue(mo.resolve({"format": "hero", "plan": "quadruped", "size_px": 80})[1])
        self.assertTrue(mo.resolve({"format": "monster", "plan": "dragon", "size_px": 80})[1])
        self.assertTrue(mo.resolve({"format": "monster", "plan": "flyer", "style": "trot", "size_px": 80})[1])
        self.assertTrue(mo.resolve({"format": "monster", "plan": "flyer", "kind": "nobody"})[1])

    def test_m12_passes(self):
        self.assertEqual([t for r, t in self.gate("ex_biped") if r == "M12"], [])


class TestFilesAndExamples(unittest.TestCase):
    def test_every_kind_mannequin_bakes_and_is_accepted_at_its_size(self):
        done = set()
        for r in mo.load_table():
            if r["size_px"] < 48:
                continue                     # the tiny ones need chunky limbs: test_m10_thin_limbs_of_a_tiny_creature
            if r["kind"] == "noose spider":
                continue
            key = (r["plan"], r["style"], r["size_px"])
            if key in done:
                continue
            done.add(key)
            lay = mo.make_layout(r["plan"], r["style"])
            rgba = ex.draw_creature(lay)
            data = ex.joints_json(lay, r["plan"], r["style"], kind=r["kind"], note=False)
            self.assertEqual(mc.gate_still(rgba, data, lay), [], r["kind"])
            for sc in mo.SIZES:
                for n, b in mo.bake_set(lay, r["style"], rgba, data, r["size_px"], r["speed"], sc).items():
                    self.assertEqual(mc.check_all(b), [], (r["kind"], n, sc))

    def test_spec_monster_writes_pose_joints_reference_prompt(self):
        with tempfile.TemporaryDirectory() as d:
            files = ex.write_spec("all", d)
            self.assertEqual(set(files), set(mo.LAYOUTS))
            for name, base in files.items():
                for suf in ("_pose.png", "_joints.json", "_reference.png", "_prompt.txt"):
                    self.assertTrue(os.path.getsize(base + suf) > 0, base + suf)
                j = json.load(open(base + "_joints.json"))
                self.assertEqual(j["format"], "monster")
                p = open(base + "_prompt.txt").read()
                for w in ("side view facing right", "flat pure magenta", "Dark outline", "inside the frame"):
                    self.assertIn(w, p)
                lay = mo.LAYOUTS[name]()
                ref = np.array(Image.open(base + "_reference.png").convert("RGBA"))
                j["size_px"] = 80
                self.assertEqual(mc.gate_still(ref, j, lay), [], name)

    def test_examples_for_every_plan_are_accepted(self):
        with tempfile.TemporaryDirectory() as d:
            acc, rej = ex.write_examples(d)
            self.assertEqual(rej, [])
            self.assertEqual(set(acc), set(ex.EXAMPLES))
            self.assertEqual({v[0] for v in ex.EXAMPLES.values()}, set(mo.STYLES))
            for name in acc:
                for n in (8, 4):
                    for sc in (112, 56):
                        self.assertTrue(os.path.exists(os.path.join(d, "accepted", name, f"{name}_move{n}_{sc}.png")))

    def test_folder_run_refuses_a_five_legged_still(self):
        with tempfile.TemporaryDirectory() as d:
            inp = os.path.join(d, "in")
            os.makedirs(inp)
            baked, r, data, lay = example("ex_quadruped")
            r = r.copy()
            r[290:471, 232:246] = (118, 88, 64, 255)
            Image.fromarray(r).save(os.path.join(inp, "dog.png"))
            json.dump(data, open(os.path.join(inp, "dog.json"), "w"))
            acc, rej = ex.run_folder(inp, os.path.join(d, "out"))
            self.assertEqual((acc, rej), ([], ["dog"]))
            self.assertTrue(os.path.exists(os.path.join(d, "out", "needs_attention", "dog.txt")))


def read_monster_rules():
    rules = {}
    with open(os.path.join(HERE, "RULES.md")) as f:
        for line in f:
            m = re.match(r"^\s*(M\d+)\s*\|(.*)$", line)
            if m:
                cols = [c.strip() for c in m.group(2).split("|")]
                rec = {"text": cols[1]}
                for c in cols[2:]:
                    k, _, v = c.partition(":")
                    rec[k.strip()] = v.strip()
                rules[m.group(1)] = rec
    return rules


class TestMonsterRulebook(unittest.TestCase):
    def test_m1_to_m12_listed_with_check_and_failing_and_passing_tests(self):
        rules = read_monster_rules()
        self.assertEqual(sorted(rules, key=lambda r: int(r[1:])), [f"M{i}" for i in range(1, 13)])
        classes = {n: o for n, o in globals().items() if inspect.isclass(o) and issubclass(o, unittest.TestCase)}
        for rid, r in rules.items():
            mod, _, fn = r["check"].partition(".")
            self.assertEqual(mod, "monster_checks", rid)
            self.assertTrue(callable(getattr(mc, fn, None)), rid)
            tests = [t.strip() for t in r["test"].split(",")]
            self.assertGreaterEqual(len(tests), 2, f"{rid}: a failing and a passing example")
            for t in tests:
                cls, _, meth = t.partition(".")
                self.assertTrue(hasattr(classes[cls], meth), f"{rid}: {t}")
            self.assertTrue(any("passes" in t for t in tests), f"{rid}: no passing example")

    def test_every_rule_id_used_by_the_code_is_listed(self):
        rules = read_monster_rules()
        used = {rid for rid, _ in mc.BAKED_RULES} | set(re.findall(r'"(M\d+)"', inspect.getsource(mc.gate_still)))
        self.assertEqual(used, set(rules))


if __name__ == "__main__":
    unittest.main()
