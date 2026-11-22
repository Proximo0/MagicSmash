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
HEEL_STRIKE_PITCH = 20.0      # deg: toe-up at heel strike at most (Perry: ~20-25 deg)
STANCE_DORSI_MAX = 26.0       # deg: a planted foot rises on its toe before the ankle passes this
SWING_ANKLE = (-20.0, 22.0)   # deg: ankle range of a swinging foot (Perry: -15 .. +5, cartoon slack)

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


# Stride retargeting (owner: "the stride reads short and stiff").  The published table is a
# 1.3-1.4 m adult stride; the stills are drawn with a cartoon stride of ~0.55-0.6 body heights
# per step.  `walk(gain)` scales the thigh swing about THIGH_C, lifts the swing knee by
# KNEE_LIFT per unit of extra gain and widens the arm swing; `fit_walk` picks the gain whose
# solved stride equals the still's own heel-to-heel step x 2 x STRIDE_MATCH.
THIGH_C = 8.0         # deg: centre of the table's thigh swing (-10 .. +30)
KNEE_LIFT = 0.30      # swing-knee flexion x (1 + KNEE_LIFT (gain - 1)) above 20 deg
ARM_SWING = 20.0      # deg: shoulder swing amplitude at gain 1 (Murray 1967: 30-40 deg total, brisk)
ARM_MAX = 23.0        # deg: arm swing amplitude cap (gain 2)
ARM_CENTRE = 2.0      # deg: the swing is centred on the arm hanging straight down
CARRY_UPPER = 20.0     # deg, pass 8: carry pose of a long hand gear: upper arm forward of hanging ...
FAR_HOLD = (-25.0, 80.0)   # pass 10: (upper arm, elbow) of the far arm holding an off-hand weapon
CARRY_POSES = {"upright": (20.0, 55.0), "level": (15.0, 70.0), "chest": (10.0, 125.0)}   # pass 10: (upper arm, elbow)
CARRY_ELBOW = 55.0     # ... elbow flexion (forearm 75 deg from hanging: forward, a little down)
FAR_BACK = 0.25       # R27: deg the far upper arm leans back per deg of extra far-elbow flexion ...
FAR_BACK_MAX = 10.0   # ... at most this much
ELBOW = (8.0, 28.0)   # deg: elbow flexion, arm back .. arm forward (Murray: 10-35)
GAIN_MAX = 2.0
GAIN_MIN = 0.8   # a still with a short step gets a smaller thigh swing, so the legs reach the feet it plants
BASE_LEAN = (0.0, 3.5)   # deg: the trunk's lean before the walk's own 1-2.5 deg: a still leaning back is stood upright,
                         # one leaning far forward is brought back to a slight stoop (R31: baked lean 0 .. +6)
STANCE_KNEE_MAX = 55.0   # deg: a planted leg's knee never folds further (Perry: ~40 at toe off)
STANCE_PITCH_MIN = -45.0  # deg: a planted foot never stands steeper on its toe
STRIDE_MATCH = 0.95   # a touch under the drawn step, so frame 0 never overshoots the still


def walk(gain=1.0, arm=1.0):
    g = float(gain)
    legs = []
    for ph, th, kn, an in WALK_LEGS:
        th2 = THIGH_C + g * (th - THIGH_C)
        kn2 = kn if kn <= 20 else 20 + (kn - 20) * (1 + KNEE_LIFT * (g - 1))
        legs.append((ph, th2, kn2, an))
    # arms: the shoulder swings ARM_SWING about hanging (ARM_CENTRE), a little wider on a long
    # stride; the elbow is slightly bent, most when the arm is forward.  Opposite phase to the
    # same-side leg: furthest back at that leg's heel strike.  `arm` (< 1 = the hand carries
    # long gear) is applied in Gait.arm_angles, to the near arm only.
    amp = min(ARM_SWING * (1 + 0.15 * (g - 1)), ARM_MAX)
    arms = {
        "upper": (_arm_k, [ARM_CENTRE - amp * math.cos(2 * math.pi * (k - 0.02)) for k in _arm_k]),
        "elbow": (_arm_k, [ELBOW[0] + (ELBOW[1] - ELBOW[0]) * (1 - math.cos(2 * math.pi * (k - 0.02))) / 2
                           for k in _arm_k]),
    }
    extra = {"lean": ([0, 0.25, 0.5, 0.75], [2.5, 1.0, 2.5, 1.0])}
    ch, st = _sym(legs, arms, extra, WALK_TOE_OFF)
    m = Motion("walk", ch, st, travels=True, frames=8,
               source="Winter 2009; Perry & Burnfield 2010; Murray et al. 1967")
    m.gain = g
    m.arm = arm
    return m


def fit_walk(rig, step_px, exact=None, quantum=None, arm=1.0):
    """The walk whose stride (still px per cycle) matches 2 x step_px x STRIDE_MATCH (or
    `exact`); the returned motion carries the exact stride so the planted foot moves a whole
    number of game px per frame."""
    target = float(exact) if exact else 2.0 * step_px * STRIDE_MATCH
    m = _fit_gain(rig, target, arm)
    # a long stride must not overextend the trailing hip: step the gain (and the stride)
    # down until a sampled cycle stays inside the hip and knee limits
    from .rig import joint_angles, JOINT_LIMITS
    lo_hip = JOINT_LIMITS["hip"][0] + 2.0
    for _ in range(12):
        m.stride_exact = target
        gt = Gait(rig, m)
        worst = 0.0
        for i in range(16):
            pose, contact = gt.pose(i / 16)
            J = rig.fk(pose)
            a = joint_angles(J, rig.rest["lean"])
            worst = min(worst, a["near.hip"] - lo_hip, a["far.hip"] - lo_hip)
            # a stride the legs cannot reach shows as a planted foot standing on its toe
            # with the knee folded: step down until stance looks like stance
            for s in SIDES:
                if contact[s]:
                    worst = min(worst, STANCE_KNEE_MAX - a[s + ".knee"], pose[s]["pitch"] - STANCE_PITCH_MIN)
        if worst >= 0 or m.gain <= GAIN_MIN:
            break
        target = max(quantum, target - quantum) if quantum else target * 0.94
        m = _fit_gain(rig, target, arm)
    m.stride_exact = target
    return m


def _fit_gain(rig, target, arm=1.0):
    lo, hi = GAIN_MIN, GAIN_MAX
    if Gait(rig, walk(lo, arm)).stride >= target:
        return walk(lo, arm)
    if Gait(rig, walk(hi, arm)).stride <= target:
        return walk(hi, arm)
    for _ in range(10):
        mid = (lo + hi) / 2
        if Gait(rig, walk(mid, arm)).stride < target:
            lo = mid
        else:
            hi = mid
    return walk((lo + hi) / 2, arm)


MOTIONS = {"walk": walk}


# ---------------------------------------------------------------------------------- solver
def wrap(a):
    return (a + 180.0) % 360.0 - 180.0


def _smooth(x0, x1, x):
    if x1 <= x0:
        return 1.0 if x >= x1 else 0.0
    t = min(1.0, max(0.0, (x - x0) / (x1 - x0)))
    return t * t * (3 - 2 * t)


class Gait:
    """Solves a Motion for one rig. All positions in still pixels; the character walks in
    place (pelvis x fixed), so a planted foot moves back at the forward speed."""

    GRID = 240
    far_tuck = 0.0      # extra elbow flexion (deg) of the far arm ...
    far_tucks = None    # ... or its profile round the cycle (solve_far_tuck): keeps its hand behind back gear

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
        self.base_lean = min(max(self.rest_lean, BASE_LEAN[0]), BASE_LEAN[1])   # the walk's trunk: upright .. slight stoop
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
        if getattr(motion, "stride_exact", None) and motion.travels:
            self.stride = float(motion.stride_exact)
        if not motion.travels:
            for s in SIDES:  # stand on the table's foot placement
                hp = self._hip_xy(s, 0.0, 0.0)
                a = self._fk_ankle(s, 0.0, hp)
                heel, toe = rig.foot_points(a, 0.0)
                self.hx0[s] = heel[0]
        self._solve_pelvis()

    @property
    def plantar_max(self):
        """deg: how far the ankle may plantarflex.  The heel is seated on the shin's back
        edge (foot.py); turning the foot toe-down swings the heel out behind that line, so the
        walk stops at the angle that keeps it within the rule's pixel (rig.data heel_tol_px,
        set by the baker from the game scale).  Never more than the swing range allows."""
        if not hasattr(self, "_plantar"):
            lim = -SWING_ANKLE[0]
            ff = self.rig.data.get("foot_fit")
            tol = self.rig.data.get("heel_tol_px")
            if ff and tol:
                from .foot import plantar_limit
                h = abs(float(self.rig.foot_local["ankle"][1]))
                lim = min(lim, plantar_limit(float(ff["back"]), h, float(tol)))
            self._plantar = lim
        return self._plantar

    # ---- helpers
    def lean(self, p):
        return self.base_lean + self.m.get("lean", p)

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
        return w1 * min(max(pf, 0.0), HEEL_STRIKE_PITCH) + w2 * min(pf, 0.0)

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
            # keep the ankle inside its range: a long stride makes the trailing foot rise on
            # its toe earlier (forefoot rocker about the fixed toe); a swing foot is turned
            # about the ankle into the swing range
            for _ in range(4):
                shin_a = limb_angle(end - knee)
                ank = pitch - shin_a
                if on and ank > STANCE_DORSI_MAX:
                    heel0, toe0 = rig.foot_points(ankle, pitch)
                    pitch = shin_a + STANCE_DORSI_MAX
                    if pitch < 0:      # heel up: turn about the toe, which stays planted
                        heel2 = toe0 - rot(rig.foot_local["toe"], -pitch)
                    else:              # still toe up: turn about the heel
                        heel2 = heel0
                    ankle = rig.ankle_from_foot(heel2, pitch)
                    knee, end = ik2(hip, ankle, self.L1, self.L2, forward=1.0)
                elif on and ank < -self.plantar_max - 1e-6:
                    # heel-off: the foot may not point further down than plantar_max; it
                    # turns back about the toe, which stays planted
                    heel0, toe0 = rig.foot_points(ankle, pitch)
                    pitch = shin_a - self.plantar_max
                    heel2 = toe0 - rot(rig.foot_local["toe"], -pitch)
                    ankle = rig.ankle_from_foot(heel2, pitch)
                    knee, end = ik2(hip, ankle, self.L1, self.L2, forward=1.0)
                elif not on and not (-self.plantar_max <= ank <= SWING_ANKLE[1]):
                    pitch = shin_a + min(max(ank, -self.plantar_max), SWING_ANKLE[1])
                    break
                else:
                    break
            thigh = limb_angle(knee - hip)
            shin = limb_angle(end - knee)
            upper, fore = self.arm_angles(s, p)
            pose[s] = {"thigh": thigh, "shin": shin, "pitch": pitch, "upper": upper, "fore": fore}
            contact[s] = bool(on)
        return pose, contact

    def arm_angles(self, s, p):
        """Arm retargeting.  A free arm is NORMALISED TO HANGING before the swing is applied:
        whatever pose the still drew it in (stretched forward, bent at the belt), the posed
        upper arm is the table's absolute angle about straight down and the elbow the table's
        slight flexion; the part is turned from the still's angle to that one, so the still's
        arm pose never leaks into the walk.  The far arm is always free.  Only a near arm
        that carries long gear (m.arm < 1: a staff, a levelled crossbow) keeps the still's own
        upper-arm angle and elbow, with the swing scaled by m.arm, so the staff stays upright
        instead of sweeping the ground."""
        up = self.m.get(s + ".upper", p)
        el = self.m.get(s + ".elbow", p)
        k = getattr(self.m, "arm", 1.0)
        if k < 1.0 and s == "near":
            if not hasattr(self, "_arm_mean"):
                ks = [i / 32 for i in range(32)]
                self._arm_mean = {c: float(np.mean([self.m.get("near." + c, q) for q in ks]))
                                  for c in ("upper", "elbow")}
            r = self.rest_arm = self.rig.rest
            rest_up = min(max(r["upper"], -40.0), 60.0)
            rest_el = min(max(wrap(r["fore"] - r["upper"]), 0.0), 130.0)
            if getattr(self.m, "carry", False):
                # CARRY POSE (pass 8): the upper arm a little forward, the elbow bent so the forearm
                # points forward and a little down: the hand sits ahead of the torso at belt height
                # and bobs; the gear is held upright from there, clear of legs and face by position
                pose_ = self.m.carry if isinstance(self.m.carry, str) else "upright"
                rest_up, rest_el = CARRY_POSES.get(pose_, (CARRY_UPPER, CARRY_ELBOW))
            up = rest_up + k * (up - self._arm_mean["upper"])
            el = rest_el + k * (el - self._arm_mean["elbow"])
        if s == "far" and getattr(self.m, "far_hold", False):
            # pass 10: the far hand holds an off-hand weapon in front of the hip: a fixed pose, upper arm a little
            # back, forearm forward and up, the hand just touching the torso's front above the hip row
            return FAR_HOLD[0], FAR_HOLD[0] + FAR_HOLD[1]
        if s == "far":
            up, el = self.tucked(up, el, self.far_tuck_at(p))
        el = min(max(el, 1.0), 145.0)
        return up, up + el

    @staticmethod
    def tucked(up, el, tuck):
        """Far arm with `tuck` deg more elbow flexion; the upper arm leans back by a quarter of it
        (at most FAR_BACK_MAX) so the folded forearm's hand stays near the line under the shoulder."""
        return up - min(FAR_BACK * tuck, FAR_BACK_MAX), el + tuck

    def far_tuck_at(self, p):
        """Far-elbow flexion (deg) added at cycle phase p: 0 unless solve_far_tuck set a profile."""
        t = self.far_tucks
        if t is None:
            return self.far_tuck
        x = (p % 1.0) * len(t)
        i = int(x) % len(t)
        f = x - int(x)
        return t[i] * (1 - f) + t[(i + 1) % len(t)] * f

    def solve_far_tuck(self, step=5.0, top=130.0, margin=0.0, n=32):
        """R27: per phase, the least far-elbow flexion (deg, multiples of `step`) with which the far
        hand (wrist and hand tip) hangs no lower than the far hip (`margin` px above it), smoothed
        round the cycle (never below that least value).  Back gear or the torso then keep the hand
        out of sight; where the arm swings forward it needs little or no fold, so no stub of
        forearm sticks out ahead of the chest.  Sets far_tucks (a profile of n values)."""
        self.far_tucks = None
        self.far_tuck = 0.0
        poses = [self.pose(i / n)[0] for i in range(n)]
        need = []
        for pose in poses:
            tuck = 0.0
            while tuck < top:
                up, el = self.tucked(pose["far"]["upper"], pose["far"]["fore"] - pose["far"]["upper"], tuck)
                el = min(max(el, 1.0), 145.0)
                q = {k: (dict(v) if isinstance(v, dict) else v) for k, v in pose.items()}
                q["far"]["upper"], q["far"]["fore"] = up, up + el
                J = self.rig.fk(q)
                if max(J["far.wrist"][1], J["far.hand_tip"][1]) - J["far.hip"][1] <= margin:
                    break
                tuck += step
            need.append(tuck)
        m = [max(need[(i + d) % n] for d in range(-2, 3)) for i in range(n)]
        self.far_tucks = [sum(m[(i + d) % n] for d in (-1, 0, 1)) / 3.0 for i in range(n)]
        return self.far_tucks

    def _stance_rel(self, s, p):
        ankle, _ = self._stance_foot(s, p)
        hip = np.array([self.px, self.pelvis_y(p)]) + rot(self.hip_off[s], self.lean(p))
        return ankle - hip

    def _fk_rel(self, s, p):
        hip = np.array([0.0, 0.0])
        return self._fk_ankle(s, p, hip)
