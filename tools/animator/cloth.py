"""Secondary motion for cloth parts (cape, robe), deterministic and cycle-closing.

Damped pendulum lag: a cloth coordinate h follows a driver u (from the parent's motion) as
    h'' = w^2 (u - h) - 2 z w h'
For a periodic driver the steady state is periodic, so instead of integrating (which needs
warm-up cycles and never closes exactly) the response is solved per harmonic over one cycle:
    H(k) = w^2 / (w^2 - (2 pi k)^2 + 2 i z w (2 pi k)),   k = harmonics per walk cycle.
No randomness; phase 1.0 equals phase 0.0 exactly.

* cape (hangs behind the torso): rotates about its top anchor by CAPE_DRAG (trails while
  walking) + the pendulum response to the pelvis bob and trunk pitch, CAPE_SWING deg peak.
* robe (below the pelvis, not leg): each row is stretched/sheared horizontally so its back
  edge follows the hindmost leg and its front edge the foremost leg at that height (between
  the two knees, not a rigid rotation), weighted from 0 at the hip to 1 at knee height;
  the hem also trails by the pendulum-lagged mean leg shift (ROBE_LAG), weighted by
  depth squared.
"""
import math

import numpy as np

from .rig import rot

CLOTH_HZ = 1.6       # natural frequency, swings per walk cycle (1 s cycle): a cape of ~0.6 m
CLOTH_ZETA = 0.35    # damping ratio
CAPE_DRAG = 3.0      # deg the cape trails while walking
CAPE_SWING = 5.0     # deg peak sway driven by the pelvis bob
ROBE_LAG = 0.6       # hem follow-through (x the difference between lagged and direct shift)
ROBE_MIN_G = -0.45   # a robe row is never squeezed below 55 % of its width
GRID = 64


def pendulum(u, hz=CLOTH_HZ, zeta=CLOTH_ZETA):
    """Steady-state periodic response of the damped pendulum to samples u over one cycle."""
    u = np.asarray(u, float)
    n = len(u)
    U = np.fft.rfft(u)
    k = np.arange(len(U))
    w = 2 * math.pi * hz
    om = 2 * math.pi * k
    Hk = w * w / (w * w - om * om + 2j * zeta * w * om)
    return np.fft.irfft(U * Hk, n)


def _interp(series, p):
    n = len(series)
    x = (p % 1.0) * n
    i = int(math.floor(x))
    f = x - i
    return series[i % n] * (1 - f) + series[(i + 1) % n] * f


def _leg_x(poly, y):
    """x of a hip->knee->ankle polyline at height y (clamped to its ends)."""
    (hx, hy), (kx, ky), (ax, ay) = poly
    if y <= hy:
        return hx
    if y <= ky:
        t = (y - hy) / max(ky - hy, 1e-6)
        return hx + t * (kx - hx)
    if y <= ay:
        t = (y - ky) / max(ay - ky, 1e-6)
        return kx + t * (ax - kx)
    return ax


class ClothSim:
    def __init__(self, ch, gait):
        self.ch = ch
        self.gait = gait
        rig = ch.rig
        self.rig = rig
        self.pel_rest = rig.j["pelvis"].copy()
        self.lean_rest = rig.rest["lean"]
        far = {k: np.array(v, float) for k, v in rig.data.get("far", {}).items()}
        self.rest_legs = [(rig.j["hip"], rig.j["knee"], rig.j["ankle"])]
        if {"hip", "knee", "ankle"} <= far.keys():
            self.rest_legs.append((far["hip"], far["knee"], far["ankle"]))
        else:
            self.rest_legs.append(self.rest_legs[0])
        self.hip_y = float(rig.j["hip"][1])
        self.knee_y = float(np.mean([l[1][1] for l in self.rest_legs]))
        robe = ch.parts.get("robe")
        self.robe = robe
        if robe is not None:
            m = robe.mask
            ys = np.flatnonzero(m.any(1))
            self.r0, self.r1 = int(ys.min()), int(ys.max()) + 1
            first = np.argmax(m, 1)
            last = m.shape[1] - 1 - np.argmax(m[:, ::-1], 1)
            self.xl = first.astype(float)
            self.xr = last.astype(float) + 1
            self.hem_y = float(self.r1)
        # drivers over one cycle
        ps = np.arange(GRID) / GRID
        bob = np.array([gait.pelvis_y(p) for p in ps])
        bob = (bob - bob.mean()) / max(np.abs(bob - bob.mean()).max(), 1e-6)
        self.cape_theta = CAPE_DRAG + CAPE_SWING * pendulum(bob)
        if robe is not None:
            mean_shift = []
            for p in ps:
                J = ch.rig.fk(gait.pose(p)[0])
                dF, dB = self._edge_shift(J, self.hem_y - 1)
                mean_shift.append((dF + dB) / 2)
            mean_shift = np.array(mean_shift)
            self.hem_lag = ROBE_LAG * (pendulum(mean_shift) - mean_shift)
        self.theta_series = self.cape_theta

    # ---- torso transform (still -> posed still coords) and its inverse
    def torso_inv(self, J, Q):
        """Q (...,2) posed still coords -> rest still coords for torso-borne parts."""
        from .rig import lean_angle
        d = lean_angle(J["neck"] - J["pelvis"]) - self.lean_rest
        r = math.radians(-d)
        c, s = math.cos(r), math.sin(r)
        q = Q - J["pelvis"]
        return np.stack([c * q[..., 0] - s * q[..., 1], s * q[..., 0] + c * q[..., 1]], -1) + self.pel_rest

    def _posed_legs_rest_frame(self, J):
        out = []
        for s in ("near", "far"):
            pts = np.stack([J[s + ".hip"], J[s + ".knee"], J[s + ".ankle"]])
            out.append(self.torso_inv(J, pts))
        return out

    def _edge_shift(self, J, y):
        posed = self._posed_legs_rest_frame(J)
        xr = [_leg_x(l, y) for l in self.rest_legs]
        xp = [_leg_x(l, y) for l in posed]
        return max(xp) - max(xr), min(xp) - min(xr)

    def cape_angle(self, p):
        return float(_interp(self.cape_theta, p))

    def robe_rows(self, J, p):
        """Per robe row y (r0..r1): (w, dB, g, lag) so that a rest x maps to
        x' = x + w * (dB + (x - xl) * g) + lag."""
        rows = np.arange(self.r0, self.r1)
        lag_now = float(_interp(self.hem_lag, p))
        out = np.zeros((len(rows), 4))
        span = max(self.knee_y - self.hip_y, 1.0)
        for i, y in enumerate(rows):
            yc = y + 0.5
            t = min(max((yc - self.hip_y) / span, 0.0), 1.0)
            w = t * t * (3 - 2 * t)
            dF, dB = self._edge_shift(J, yc)
            width = max(self.xr[y] - self.xl[y], 1.0)
            g = max((dF - dB) / width, ROBE_MIN_G)
            d2 = min(max((yc - self.hip_y) / max(self.hem_y - self.hip_y, 1.0), 0.0), 1.0)
            out[i] = (w, dB, g, lag_now * d2 * d2)
        return rows, out
