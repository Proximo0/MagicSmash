"""Licence gate: a model repo may be loaded only if licences.json (next to this file) lists it with commercial_ok true."""
import json
from pathlib import Path

FILE = Path(__file__).with_name("licences.json")


def _models():
    if not FILE.exists():
        raise RuntimeError(f"licence gate: {FILE} missing, refusing to load any model")
    return json.loads(FILE.read_text(encoding="utf-8"))["models"]


def allow(repo):
    """Return repo if it is cleared for commercial use, else raise."""
    m = _models().get(repo)
    if m is None:
        raise RuntimeError(f"licence gate: {repo} is not in {FILE.name}; add it with its licence before loading")
    if m.get("commercial_ok") is not True:
        raise RuntimeError(f"licence gate: {repo} ({m.get('licence')}) is not cleared for commercial use")
    return repo


def check_all(repos):
    bad = []
    for r in repos:
        try:
            allow(r)
        except RuntimeError as e:
            bad.append(str(e))
    if bad:
        raise RuntimeError("refusing to start:\n" + "\n".join(bad))
