#!/usr/bin/env python3
"""Self-test of tools/balance_compare.py: no engine, no network. Prints failures, then
BALANCE_COMPARE_TESTS passed=N failed=M, and exits 1 on a failure. Run: python3 tools/balance_compare_test.py"""
import contextlib
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import balance_compare as bc  # noqa: E402

HEAD = "label,ref,commit,seed,wizards,persona,runs,won,unfinished,state\n"


def table(label, jobs):
    """A balance.csv text: jobs = [(first seed, runs, won, state)]."""
    return HEAD + "".join("%s,try/x,abc,%d,2,casual,%d,%d,0,%s\n" % (label, s, n, k, st) for s, n, k, st in jobs)


class Wilson(unittest.TestCase):
    def test_textbook_values(self):
        for (k, n), (lo, hi) in {(5, 10): (0.2366, 0.7634), (0, 10): (0.0, 0.2775), (10, 10): (0.7225, 1.0),
                                 (16, 27): (0.4073, 0.7548)}.items():
            got = bc.wilson(k, n)
            self.assertAlmostEqual(got[0], lo, places=3, msg=(k, n))
            self.assertAlmostEqual(got[1], hi, places=3, msg=(k, n))

    def test_no_runs_is_the_whole_range(self):
        self.assertEqual(bc.wilson(0, 0), (0.0, 1.0))


class Newcombe(unittest.TestCase):
    def test_the_papers_example(self):
        # Newcombe (1998), example (a): 56/70 against 48/80, method 10 gives 0.0524 to 0.3339.
        d, lo, hi = bc.newcombe(48, 80, 56, 70)
        self.assertAlmostEqual(d, 0.2, places=6)
        self.assertAlmostEqual(lo, 0.0524, places=3)
        self.assertAlmostEqual(hi, 0.3339, places=3)


class Compare(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="balance_test.")

    def write(self, name, text):
        p = os.path.join(self.dir, name)
        with open(p, "w") as f:
            f.write(text)
        return p

    def run_main(self, a, b):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = bc.main(["--csv", a, b])
        return rc, out.getvalue()

    def test_only_seeds_both_played_count_and_broken_jobs_drop(self):
        a = self.write("a.csv", table("base", [(1, 5, 3, "ok"), (6, 5, 3, "ok"), (11, 5, 3, "ok")]))
        b = self.write("b.csv", table("change", [(1, 5, 2, "ok"), (6, 0, 0, "broken"), (16, 5, 5, "ok")]))
        c = bc.compare(bc.read_rows(a), bc.read_rows(b))
        self.assertEqual((c["seeds"], c["n_a"], c["k_a"], c["n_b"], c["k_b"]), (1, 5, 3, 5, 2))

    def test_verdicts(self):
        base = [(s, 5, 3, "ok") for s in range(1, 101, 5)]   # 60 of 100
        same = [(s, 5, 3, "ok") for s in range(1, 101, 5)]
        low = [(s, 5, 1, "ok") for s in range(1, 101, 5)]    # 20 of 100
        high = [(s, 5, 5, "ok") for s in range(1, 101, 5)]   # 100 of 100
        a = bc.read_rows(self.write("a.csv", table("a", base)))
        self.assertEqual(bc.compare(a, bc.read_rows(self.write("s.csv", table("s", same))))["verdict"], "same")
        self.assertEqual(bc.compare(a, bc.read_rows(self.write("l.csv", table("l", low))))["verdict"], "lower")
        self.assertEqual(bc.compare(a, bc.read_rows(self.write("h.csv", table("h", high))))["verdict"], "higher")

    def test_the_line(self):
        a = self.write("a.csv", table("base", [(1, 5, 3, "ok"), (6, 5, 3, "ok")]))
        b = self.write("b.csv", table("change", [(1, 5, 2, "ok"), (6, 5, 2, "ok")]))
        rc, out = self.run_main(a, b)
        self.assertEqual(rc, 0)
        last = out.strip().splitlines()[-1]
        self.assertTrue(last.startswith("COMPARE a=base b=change seeds=2 a_won=6/10 b_won=4/10 diff=-0.200 "), last)
        self.assertTrue(last.endswith(" verdict=same"), last)

    def test_no_usable_row_fails(self):
        a = self.write("a.csv", table("base", [(1, 5, 3, "ok")]))
        b = self.write("b.csv", table("change", [(6, 5, 3, "ok")]))
        rc, out = self.run_main(a, b)
        self.assertEqual(rc, 1)
        self.assertIn("FAIL", out)

    def test_usage(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(bc.main([]), 2)
            self.assertEqual(bc.main(["--csv", "only_one"]), 2)


if __name__ == "__main__":
    result = unittest.TextTestRunner(stream=io.StringIO(), verbosity=0).run(
        unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    for case, trace in result.failures + result.errors:
        print("FAIL %s\n%s" % (case.id(), trace))
    bad = len(result.failures) + len(result.errors)
    print("BALANCE_COMPARE_TESTS passed=%d failed=%d" % (result.testsRun - bad, bad))
    sys.exit(1 if bad else 0)
