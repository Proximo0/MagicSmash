"""Motions as joint-angle tables over one cycle, and the solver that turns a table into poses
for one character (retargeted to its bone lengths, stance foot held on the ground by IK).

Channel names (degrees, picture angles as defined in rig.py):
  near.thigh / far.thigh   thigh angle from vertical (+ = forward)
  near.knee  / far.knee    knee flexion (+ = shin folded back)
  near.ankle / far.ankle   ankle dorsiflexion (+) / plantarflexion (-)
  near.upper / far.upper   upper-arm angle from vertical (+ = forward)
  near.elbow / far.elbow   elbow flexion (+ = forearm folded forward)
  lean                     trunk lean added to the still's own lean (+ = forward)
  pelvis_dy                pelvis drop in leg lengths (+ = down) added after the stance solve
A motion also has per-side stance windows (start phase, duration) and whether it travels.
"""
import math

import numpy as np

from .rig import Rig, ik2, limb_angle, limb_dir, rot, SIDES


class Curve:
    """Periodic Catmull-Rom (non-uniform) through (phase, value) knots on [0, 1)."""

    def __init__(self, knots, values):
        k = np.asarray(knots, float) % 1.0
        o = np.argsort(k)
        self.k = k[o]
        self.v = np.asarray(values, float)[o]
        if len(self.k) and self.k[0] == 0.0 and len(self.k) > 1 and abs(self.k[-1] - 1.0) < 1e-9:
            self.k, self.v = self.k[:-1], self.v[:-1]

    def __call__(self, p):
        k, v = self.k, self.v
        n = len(k)
        if n == 1:
            return float(v[0])
        K = np.concatenate([k - 1.0, k, k + 1.0])
        V = np.concatenate([v, v, v])
        p = p % 1.0
        i = int(np.searchsorted(K, p, side="right") - 1)
        t0, t1 = K[i], K[i + 1]
        tm, t2 = K[i - 1], K[i + 2]
        h = t1 - t0
        u = (p - t0) / h
        m0 = (V[i + 1] - V[i - 1]) / (t1 - tm)
        m1 = (V[i + 2] - V[i]) / (t2 - t0)
        u2, u3 = u * u, u * u * u
        return float((2 * u3 - 3 * u2 + 1) * V[i] + (u3 - 2 * u2 + u) * h * m0 +
                     (-2 * u3 + 3 * u2) * V[i + 1] + (u3 - u2) * h * m1)


class Motion:
    def __init__(self, name, channels, stance, travels=True, frames=8, flight_hop=0.0,
                 source=""):
        self.name = name
        self.ch = {k: (c if isinstance(c, Curve) else Curve(*c)) for k, c in channels.items()}
        self.stance = stance            # side -> (start phase, duration)
        self.travels = travels
        self.frames = frames
        self.flight_hop = flight_hop    # extra pelvis rise mid-flight (leg lengths)
        self.source = source

    def get(self, name, p, default=0.0):
        c = self.ch.get(name)
        return c(p) if c is not None else default


def _shifted(knots, values, shift):
    return [((k + shift) % 1.0) for k in knots], list(values)


def _sym(table, arms, extra, stance_dur, shift=0.5):
    """Near-side tables + far side = the same curves half a cycle later."""
    ch = {}
    ph = [r[0] / 100.0 for r in table]
    for i, n in enumerate(("thigh", "knee", "ankle")):
        vals = [r[i + 1] for r in table]
        ch["near." + n] = (ph, vals)
        ch["far." + n] = _shifted(ph, vals, shift)
    for n, (k, v) in arms.items():
        ch["near." + n] = (k, v)
        ch["far." + n] = _shifted(k, v, shift)
    ch.update(extra)
    stance = {"near": (0.0, stance_dur), "far": (shift % 1.0, stance_dur)}
    return ch, stance


# ---------------------------------------------------------------------------------- walk
# Normal adult walking, sagittal plane, % gait cycle from heel strike of the same leg.
# Read at 5-10 % steps from the published normal curves: Winter D.A., "Biomechanics and
# Motor Control of Human Movement", 4th ed. (2009), ch. 4 / appendix gait data, and
# Perry J. & Burnfield J.M., "Gait Analysis: Normal and Pathological Function", 2nd ed.
# (2010), ch. 4-6 (hip, knee, ankle).  Thigh here is the thigh-to-vertical angle.
WALK_LEGS = [
    #  %   thigh  knee  ankle
    (0, 25.0, 4.0, 0.0),
    (5, 24.0, 10.0, -4.0),
    (10, 22.5, 15.0, -5.0),
    (15, 20.0, 18.0, -2.0),
    (20, 16.0, 16.0, 2.0),
    (30, 8.0, 9.0, 6.0),
    (40, 0.0, 5.0, 9.0),
    (50, -8.0, 8.0, 6.0),
    (55, -10.0, 18.0, -2.0),
    (60, -6.0, 36.0, -14.0),
    (65, 2.0, 52.0, -18.0),
    (70, 12.0, 62.0, -10.0),
    (75, 20.0, 62.0, -4.0),
    (80, 26.0, 52.0, 0.0),
    (85, 29.0, 38.0, 2.0),
    (90, 30.0, 22.0, 2.0),
    (95, 28.0, 10.0, 1.0),
]
WALK_TOE_OFF = 0.62   # stance = 62 % of the cycle (Perry: 60-62 %)

# Arm swing opposite the legs (Murray, Sepic & Barnard, "Patterns of sagittal rotation of
# the upper limbs in walking", Phys Ther 47:272, 1967): the near arm is furthest back at near
# heel strike and furthest forward half a cycle later; shoulder excursion ~30-35 deg total
# at brisk speed, elbow 10-35 deg flexion, more flexed when the arm is forward.
_arm_k = [i / 8.0 for i in range(8)]
WALK_ARMS = {
    "upper": (_arm_k, [2 - 17 * math.cos(2 * math.pi * (k - 0.02)) for k in _arm_k]),
    "elbow": (_arm_k, [10 + 25 * (1 - math.cos(2 * math.pi * (k - 0.02))) / 2 for k in _arm_k]),
}
# Trunk: ~2 deg extra forward lean, +-1 deg pitch twice a cycle (Thorstensson et al. 1984).
WALK_EXTRA = {"lean": ([0, 0.25, 0.5, 0.75], [2.5, 1.5, 2.5, 1.5])}


def walk():
    ch, st = _sym(WALK_LEGS, WALK_ARMS, WALK_EXTRA, WALK_TOE_OFF)
    return Motion("walk", ch, st, travels=True, frames=8,
                  source="Winter 2009; Perry & Burnfield 2010; Murray et al. 1967")


MOTIONS = {"walk": walk}


# ---------------------------------------------------------------------------------- solver
def _smooth(x0, x1, x):
    if x1 <= x0:
        return 1.0 if x >= x1 else 0.0
    t = min(1.0, max(0.0, (x - x0) / (x1 - x0)))
    return t * t * (3 - 2 * t)


class Gait:
    """Solves a Motion for one rig. All positions in still pixels; the character walks in
    place (pelvis x fixed), so a planted foot moves back at the forward speed."""

    GRID = 240

    def __init__(self, rig, motion):
        self.rig = rig
        self.m = motion
        L = rig.lengths
        self.L1, self.L2 = L["thigh"], L["shin"]
        self.leg = self.L1 + self.L2
        self.ground = rig.ground_y
        self.px = float(rig.j["pelvis"][0])
        self.flen = float(np.hypot(*rig.foot_local["toe"]))
        self.rest_lean = rig.rest["lean"]
        self.hip_off = {s: self._hip_local(s) for s in SIDES}
        # footprint: heel x at heel strike, from the table's own FK; stride from toe-off FK.
        self.hx0, est = {}, []
        for s in SIDES:
            st, du = motion.stance[s]
            hp = self._hip_xy(s, st, 0.0)
            a = self._fk_ankle(s, st, hp)
            heel, toe = rig.foot_points(a, self._fk_pitch(s, st))
            self.hx0[s] = heel[0]
            if motion.travels:
                hp2 = self._hip_xy(s, st + du, 0.0)
                a2 = self._fk_ankle(s, st + du, hp2)
                h2, t2 = rig.foot_points(a2, self._fk_pitch(s, st + du))
                est.append((heel[0] + self.flen - t2[0]) / du)
        self.stride = float(np.mean(est)) if est else 0.0   # still px per cycle
        if not motion.travels:
            for s in SIDES:  # stand on the table's foot placement
                hp = self._hip_xy(s, 0.0, 0.0)
                a = self._fk_ankle(s, 0.0, hp)
                heel, toe = rig.foot_points(a, 0.0)
                self.hx0[s] = heel[0]
        self._solve_pelvis()

    # ---- helpers
    def lean(self, p):
        return self.rest_lean + self.m.get("lean", p)

    def _hip_local(self, s):
        v = self.rig.torso_local["hip"].copy()
        if s == "far":
            v = v + self.rig.far_hip_offset
        return v

    def _hip_xy(self, s, p, pel_y):
        return np.array([self.px, pel_y]) + rot(self.hip_off[s], self.lean(p))

    def _fk_angles(self, s, p):
        th = self.m.get(s + ".thigh", p)
        kn = self.m.get(s + ".knee", p)
        an = self.m.get(s + ".ankle", p)
        return th, th - kn, an

    def _fk_pitch(self, s, p):
        th, sh, an = self._fk_angles(s, p)
        return sh + an

    def _fk_ankle(self, s, p, hip):
        th, sh, an = self._fk_angles(s, p)
        return hip + self.L1 * limb_dir(th) + self.L2 * limb_dir(sh)

    def stance_q(self, s, p):
        st, du = self.m.stance[s]
        q = (p - st) % 1.0
        return q, du, q < du - 1e-9 or du >= 1.0

    def _stance_pitch(self, s, p):
        if not self.m.travels:
            return 0.0
        q, du, _ = self.stance_q(s, p)
        pf = self._fk_pitch(s, p)
        w1 = 1.0 - _smooth(0.13 * du, 0.29 * du, q)
        w2 = _smooth(0.62 * du, 0.78 * du, q)
        return w1 * max(pf, 0.0) + w2 * min(pf, 0.0)

    def _stance_foot(self, s, p):
        """heel, toe, ankle of a planted foot at phase p."""
        q, du, _ = self.stance_q(s, p)
        hx = self.hx0[s] - self.stride * q
        heel_flat = np.array([hx, self.ground])
        toe_flat = heel_flat + np.array([self.flen, 0.0])
        pitch = self._stance_pitch(s, p)
        if pitch >= 0:   # heel rocker: turn about the heel
            ankle = self.rig.ankle_from_foot(heel_flat, pitch)
        else:            # forefoot rocker: turn about the toe
            heel = toe_flat - rot(self.rig.foot_local["toe"], -pitch)
            ankle = self.rig.ankle_from_foot(heel, pitch)
        return ankle, pitch

    def _solve_pelvis(self):
        n = self.GRID
        ys = np.full(n, np.nan)
        for i in range(n):
            p = i / n
            need = []
            for s in SIDES:
                q, du, on = self.stance_q(s, p)
                if not on:
                    continue
                ankle, _ = self._stance_foot(s, p)
                kn = max(self.m.get(s + ".knee", p), 2.0)
                r = math.sqrt(self.L1 ** 2 + self.L2 ** 2 + 2 * self.L1 * self.L2 * math.cos(math.radians(kn)))
                hip0 = self._hip_xy(s, p, 0.0)
                dx = ankle[0] - hip0[0]
                dy = math.sqrt(max(r * r - dx * dx, 1.0))
                need.append(ankle[1] - dy - hip0[1])
            if need:
                ys[i] = max(need)
        raw = ys.copy()
        # flight phases: interpolate across, plus a ballistic hop
        if np.isnan(ys).any():
            idx = np.arange(n)
            ok = ~np.isnan(ys)
            xs = np.concatenate([idx[ok] - n, idx[ok], idx[ok] + n])
            vs = np.concatenate([ys[ok]] * 3)
            interp = np.interp(idx, xs, vs)
            hop = np.zeros(n)
            # parabola over each nan run
            run = None
            for i in range(2 * n):
                k = i % n
                if np.isnan(raw[k]) and run is None:
                    run = i
                if not np.isnan(raw[k]) and run is not None:
                    ln = i - run
                    for t in range(ln):
                        u = (t + 0.5) / ln
                        hop[(run + t) % n] = 4 * u * (1 - u)
                    run = None
                if i >= n and run is None and not np.isnan(raw[k]):
                    break
            ys = interp - hop * self.m.flight_hop * self.leg
            raw = ys.copy()
        # gentle circular smoothing; never higher than the legs reach (y down: max)
        w = max(1, n // 40)
        ker = np.ones(2 * w + 1) / (2 * w + 1)
        sm = np.convolve(np.concatenate([ys[-w:], ys, ys[:w]]), ker, mode="valid")
        self.pel_y = np.maximum(sm, raw)

    def pelvis_y(self, p):
        n = self.GRID
        x = (p % 1.0) * n
        i = int(math.floor(x))
        f = x - i
        y = self.pel_y[i % n] * (1 - f) + self.pel_y[(i + 1) % n] * f
        return y + self.m.get("pelvis_dy", p) * self.leg

    # ---- main
    def pose(self, p):
        """Returns (pose dict for Rig.fk, contact dict side -> bool)."""
        rig = self.rig
        pel = np.array([self.px, self.pelvis_y(p)])
        lean = self.lean(p)
        pose = {"pelvis": pel, "lean": lean}
        contact = {}
        for s in SIDES:
            hip = pel + rot(self.hip_off[s], lean)
            q, du, on = self.stance_q(s, p)
            if on:
                ankle, pitch = self._stance_foot(s, p)
            else:
                st = self.m.stance[s][0]
                p_off, p_on = st + du, st + 1.0
                u = _smooth(0.0, 1.0, (q - du) / (1.0 - du))
                rel = self._fk_ankle(s, p, hip) - hip
                e0 = self._stance_rel(s, p_off - 1e-6) - self._fk_rel(s, p_off)
                e1 = self._stance_rel(s, p_on) - self._fk_rel(s, p_on)
                ankle = hip + rel + e0 * (1 - u) + e1 * u
                pf = self._fk_pitch(s, p)
                pe0 = self._stance_pitch(s, p_off - 1e-6) - self._fk_pitch(s, p_off)
                pe1 = self._stance_pitch(s, p_on) - self._fk_pitch(s, p_on)
                pitch = pf + pe0 * (1 - u) + pe1 * u
                heel, toe = rig.foot_points(ankle, pitch)
                low = max(heel[1], toe[1])
                if low > self.ground:   # swing foot never goes through the floor
                    ankle = ankle - np.array([0.0, low - self.ground])
            knee, end = ik2(hip, ankle, self.L1, self.L2, forward=1.0)
            thigh = limb_angle(knee - hip)
            shin = limb_angle(end - knee)
            upper = self.m.get(s + ".upper", p)
            fore = upper + self.m.get(s + ".elbow", p)
            pose[s] = {"thigh": thigh, "shin": shin, "pitch": pitch, "upper": upper, "fore": fore}
            contact[s] = bool(on)
        return pose, contact

    def _stance_rel(self, s, p):
        ankle, _ = self._stance_foot(s, p)
        hip = np.array([self.px, self.pelvis_y(p)]) + rot(self.hip_off[s], self.lean(p))
        return ankle - hip

    def _fk_rel(self, s, p):
        hip = np.array([0.0, 0.0])
        return self._fk_ankle(s, p, hip)
