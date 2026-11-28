#!/usr/bin/env python3
"""Compares two arms of the balance workflow (.github/workflows/balance.yml): how often the bots won in each, the
difference and its 95% interval, and a verdict. Standard library only; it calls `gh` to fetch the artifacts.

Usage:
  python3 tools/balance_compare.py <run id A> <run id B>     two runs of the workflow (A the base, B the change)
  python3 tools/balance_compare.py --csv <a.csv> <b.csv>       two balance.csv files (the artifacts' table)

Only the seeds both arms played count, so an arm that is still missing a job is compared on what both have.
Prints one line per arm, then
  COMPARE a=<label> b=<label> seeds=<n> a_won=<k>/<n> b_won=<k>/<n> diff=<b-a> lo=<..> hi=<..> verdict=lower|same|higher
`lower` means B wins less often than A with 95% confidence (Newcombe's interval of the difference, from the two
Wilson intervals). Exit 0 after a comparison, 2 on a usage error, 1 when an arm has no usable row.
"""
import csv
import math
import os
import subprocess
import sys
import tempfile

Z = 1.959964  # two-sided 95%


def wilson(k, n, z=Z):
    """The Wilson score interval of k successes in n trials, as (low, high)."""
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    s = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (max(0.0, (c - s) / d), min(1.0, (c + s) / d))


def newcombe(k1, n1, k2, n2):
    """Newcombe's hybrid score interval of p2 - p1 (method 10), as (diff, low, high)."""
    p1, p2 = k1 / n1, k2 / n2
    l1, u1 = wilson(k1, n1)
    l2, u2 = wilson(k2, n2)
    d = p2 - p1
    lo = d - math.sqrt((p2 - l2) ** 2 + (u1 - p1) ** 2)
    hi = d + math.sqrt((u2 - p2) ** 2 + (p1 - l1) ** 2)
    return (d, lo, hi)


def read_rows(path):
    """{first seed of a job: row} of the jobs that played, from a balance.csv."""
    rows = {}
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            if r.get("state") != "ok":
                continue
            rows[int(r["seed"])] = r
    return rows


def fetch(run_id, into):
    """Downloads the `balance` artifact of one workflow run; returns its balance.csv path."""
    if not run_id.isdigit():
        raise SystemExit("FAIL run id must be a number: " + run_id)
    d = os.path.join(into, run_id)
    subprocess.run(["gh", "run", "download", run_id, "-n", "balance", "-D", d], check=True,
                   stdout=subprocess.DEVNULL)
    return os.path.join(d, "balance.csv")


def compare(rows_a, rows_b):
    """The comparison line's numbers on the jobs both arms played."""
    both = sorted(set(rows_a) & set(rows_b))
    pick = lambda rows, key: sum(int(rows[s][key]) for s in both)
    n_a, k_a = pick(rows_a, "runs"), pick(rows_a, "won")
    n_b, k_b = pick(rows_b, "runs"), pick(rows_b, "won")
    if n_a == 0 or n_b == 0:
        return None
    d, lo, hi = newcombe(k_a, n_a, k_b, n_b)
    verdict = "lower" if hi < 0 else ("higher" if lo > 0 else "same")
    return {"seeds": len(both), "n_a": n_a, "k_a": k_a, "n_b": n_b, "k_b": k_b, "diff": d, "lo": lo, "hi": hi,
            "verdict": verdict}


def arm_line(name, rows):
    n = sum(int(r["runs"]) for r in rows.values())
    k = sum(int(r["won"]) for r in rows.values())
    lo, hi = wilson(k, n)
    first = next(iter(rows.values())) if rows else {}
    return "ARM %s label=%s ref=%s commit=%s wizards=%s persona=%s runs=%d won=%d rate=%.3f lo=%.3f hi=%.3f" % (
        name, first.get("label") or "-", first.get("ref", "-"), first.get("commit", "-"), first.get("wizards", "-"),
        first.get("persona", "-"), n, k, k / n if n else 0.0, lo, hi)


def main(argv):
    if len(argv) == 3 and argv[0] == "--csv":
        a_path, b_path = argv[1], argv[2]
        tmp = None
    elif len(argv) == 2 and not argv[0].startswith("-"):
        tmp = tempfile.mkdtemp(prefix="balance.")
        a_path, b_path = fetch(argv[0], tmp), fetch(argv[1], tmp)
    else:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    rows_a, rows_b = read_rows(a_path), read_rows(b_path)
    print(arm_line("a", rows_a))
    print(arm_line("b", rows_b))
    c = compare(rows_a, rows_b)
    if c is None:
        print("FAIL an arm has no usable row on the seeds both played")
        return 1
    la = next(iter(rows_a.values())).get("label") or "a"
    lb = next(iter(rows_b.values())).get("label") or "b"
    print("COMPARE a=%s b=%s seeds=%d a_won=%d/%d b_won=%d/%d diff=%+.3f lo=%+.3f hi=%+.3f verdict=%s" % (
        la, lb, c["seeds"], c["k_a"], c["n_a"], c["k_b"], c["n_b"], c["diff"], c["lo"], c["hi"], c["verdict"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
