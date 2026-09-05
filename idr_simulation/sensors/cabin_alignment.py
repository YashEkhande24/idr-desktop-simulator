"""Dynamic in-cabin alignment: arbitrary phone pose -> vehicle body frame.

Two stages, both driven only by the IMU stream:

1. Gravity tracking. A slow low-pass of the accelerometer gives the phone-frame
   gravity direction, which fixes roll and pitch of the mount.
2. Horizontal PCA. Within the levelled frame, the dominant eigenvector of the
   horizontal acceleration covariance is the longitudinal axis (braking and
   throttle dominate lateral dynamics). Yaw-rate correlation resolves the
   remaining 180 degree ambiguity.
"""

from __future__ import annotations

from collections import deque

import numpy as np

from ..common import G, unit


class CabinAligner:
    def __init__(self, dt: float = 0.01, gravity_tau: float = 2.0,
                 pca_window_s: float = 6.0, warmup_s: float = 1.5):
        self.dt = dt
        self.gravity_alpha = dt / max(gravity_tau, dt)
        self.window = max(64, int(round(pca_window_s / dt)))
        self.warmup = max(16, int(round(warmup_s / dt)))

        self._g_lp: np.ndarray | None = None
        self._level_acc: deque[np.ndarray] = deque(maxlen=self.window)
        self._yaw_rate_hist: deque[float] = deque(maxlen=self.window)
        self._lat_hist: deque[float] = deque(maxlen=self.window)
        self._fwd_2d = np.array([1.0, 0.0])
        self._n = 0
        self.confidence = 0.0
        self.locked = False

    # ------------------------------------------------------------------ helpers
    @staticmethod
    def _level_basis(g_hat: np.ndarray) -> np.ndarray:
        """Rows are the levelled axes (e1, e2, up) expressed in phone axes."""
        up = unit(g_hat, [0.0, 0.0, 1.0])
        seed = np.array([1.0, 0.0, 0.0])
        if abs(up @ seed) > 0.9:
            seed = np.array([0.0, 1.0, 0.0])
        e1 = unit(seed - (seed @ up) * up)
        e2 = np.cross(up, e1)
        return np.vstack((e1, e2, up))

    # --------------------------------------------------------------------- api
    def update(self, acc: np.ndarray, gyro: np.ndarray) -> dict:
        """Feed one raw IMU sample; returns the vehicle-frame measurements."""
        acc = np.asarray(acc, dtype=float)
        gyro = np.asarray(gyro, dtype=float)
        self._n += 1

        if self._g_lp is None:
            self._g_lp = acc.copy()
        else:
            self._g_lp += self.gravity_alpha * (acc - self._g_lp)
        g_hat = unit(self._g_lp, [0.0, 0.0, 1.0])

        level = self._level_basis(g_hat)
        acc_level = level @ acc
        gyro_level = level @ gyro
        yaw_rate = float(gyro_level[2])

        horiz = acc_level[:2] - np.array([0.0, 0.0])
        self._level_acc.append(horiz.copy())
        self._yaw_rate_hist.append(yaw_rate)

        if len(self._level_acc) >= self.warmup:
            self._update_forward_axis()

        fwd = self._fwd_2d
        lat = np.array([-fwd[1], fwd[0]])
        r_level_to_vehicle = np.array([
            [fwd[0], fwd[1], 0.0],
            [lat[0], lat[1], 0.0],
            [0.0, 0.0, 1.0],
        ])

        # Phone -> vehicle rotation; rows of the product are the vehicle axes.
        r_pv = r_level_to_vehicle @ level
        acc_vehicle = r_pv @ acc
        gyro_vehicle = r_pv @ gyro
        acc_dynamic = acc_vehicle - np.array([0.0, 0.0, G])

        self._lat_hist.append(float(acc_dynamic[1]))
        return {
            "acc_vehicle": acc_vehicle,
            "acc_dynamic": acc_dynamic,
            "gyro_vehicle": gyro_vehicle,
            "gravity_phone": g_hat,
            "R_phone_to_vehicle": r_pv,
            "roll_mount": float(np.arctan2(g_hat[1], g_hat[2])),
            "pitch_mount": float(-np.arcsin(np.clip(g_hat[0], -1.0, 1.0))),
            "confidence": self.confidence,
            "locked": self.locked,
        }

    def _update_forward_axis(self) -> None:
        data = np.asarray(self._level_acc)
        data = data - data.mean(axis=0)
        cov = np.cov(data, rowvar=False)
        if not np.all(np.isfinite(cov)):
            return
        vals, vecs = np.linalg.eigh(cov)
        order = np.argsort(vals)[::-1]
        vals, vecs = vals[order], vecs[:, order]
        candidate = unit(np.append(vecs[:, 0], 0.0))[:2]

        total = float(vals.sum())
        self.confidence = float(vals[0] / total) if total > 1e-9 else 0.0

        # Sign disambiguation: during a left turn (yaw_rate > 0) the lateral
        # specific force is positive along +y = left, so a_fwd x omega should
        # correlate positively with the projection on the lateral axis.
        proj_a = data @ candidate
        lat_axis = np.array([-candidate[1], candidate[0]])
        proj_lat = data @ lat_axis
        omega = np.asarray(self._yaw_rate_hist)[-len(proj_lat):]
        if omega.size == proj_lat.size and np.std(omega) > 1e-3:
            if float(np.dot(proj_lat, omega)) < 0.0:
                candidate = -candidate
        elif float(np.sum(proj_a**3)) < 0.0:
            # No turning information: throttle transients skew positive.
            candidate = -candidate

        # Slew the axis instead of snapping, to keep the estimate smooth.
        if float(candidate @ self._fwd_2d) < 0.0 and self.locked:
            candidate = candidate  # allow deliberate flips once evidence is strong
        blend = 0.02 if self.locked else 0.15
        merged = unit(np.append((1.0 - blend) * self._fwd_2d + blend * candidate, 0.0))[:2]
        if np.linalg.norm(merged) > 1e-6:
            self._fwd_2d = merged / np.linalg.norm(merged)
        if self._n > self.window and self.confidence > 0.6:
            self.locked = True
