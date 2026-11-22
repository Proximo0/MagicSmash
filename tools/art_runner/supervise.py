"""Keeps runner2.py (two-phase: SDXL layouts, then Klein) going until the queue is finished: restarts it 60 s after any crash or exit.
Stops when STOP exists (stop_runner.ps1) or status.txt says FINISHED. Logs to runner.log."""
import subprocess, sys, time
from pathlib import Path
ROOT = Path(r"D:\projects\hh_art")
PY = ROOT / "venv" / "Scripts" / "pythonw.exe"


def log(m):
    with open(ROOT / "runner.log", "a", encoding="utf-8") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + "supervisor: " + m + "\n")


fails = 0
while True:
    if (ROOT / "STOP").exists():
        log("STOP file, not restarting"); break
    t = time.time()
    rc = subprocess.call([str(PY), str(ROOT / "runner2.py")], cwd=ROOT, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    st = (ROOT / "status.txt").read_text(encoding="utf-8") if (ROOT / "status.txt").exists() else ""
    if "FINISHED" in st or (ROOT / "STOP").exists():
        log(f"runner ended ({st.strip()[:80]}), done"); break
    fails = fails + 1 if time.time() - t < 300 else 0
    wait = min(60 * 2 ** min(fails, 4), 1800)  # back off if it keeps dying at once
    log(f"runner exited rc={rc} ({st.strip()[:80]}); restarting in {wait}s")
    time.sleep(wait)
