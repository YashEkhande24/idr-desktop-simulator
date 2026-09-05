"""9-state Extended Kalman Filter with non-holonomic constraints.

State
-----
``x = [p_x, p_y, p_z, v_x, v_y, v_z, roll, pitch, yaw]``, position and velocity
in the world frame (X east, Y north, Z up), attitude as ZYX Euler angles.

Measurements
------------
* TCN forward speed        -> projection of ``v`` onto the vehicle longitudinal axis
* accelerometer levelling  -> roll / pitch, gated by dynamic acceleration
* barometric altitude      -> ``p_z`` at 10 Hz, with an internal climb-rate estimate
* GNSS position            -> covariance scheduled by a sigmoid in HDOP
* NHC pseudo-measurements  -> lateral velocity ~ 0, vertical velocity ~ climb rate
* map cross-track          -> distance to the matched road centre line

The gyroscope drives the attitude propagation; its z bias is trimmed by a
zero-rotation update whenever a standstill is detected.
"""

from __future__ import annotations

import numpy as np

from ..common import (
    G,
    euler_rate_jacobian,
    euler_rates,
    forward_axis,
    rot_body_to_world,
    sigmoid,
    wrap_angle,
)

N = 9
P_ = slice(0, 3)
V_ = slice(3, 6)
A_ = slice(6, 9)


class IntelligentEKF:
    def __init__(self, dt: float = 0.01):
        self.dt = dt
        self.x = np.zeros(N)
        self.P = np.diag([4.0, 4.0, 4.0, 1.0, 1.0, 0.5,
                          0.02, 0.02, 0.05])

        self.sigma_acc = 0.35          # m/s^2 /sqrt(Hz), driving velocity Q
        self.sigma_gyro = 0.01         # rad/s /sqrt(Hz), driving attitude Q
        self.sigma_nhc_lat = 0.05
        self.sigma_nhc_vert = 0.18
        self.sigma_tilt = 0.05
        self.gnss_r_nominal = 2.0
        self.gnss_r_max = 5.0e3
        self.gnss_hdop_gain = 1.4
        self.gnss_hdop_centre = 4.0
        self.gnss_chi2_gate = 25.0
        self.gnss_reject_limit = 4          # forced re-acquisition after a lockout

        self.gyro_bias_z = 0.0
        self.bias_learn_gain = 0.02         # integral term of the heading loop
        self._climb_rate = 0.0
        self._baro_prev: tuple[float, float] | None = None
        self.gnss_rejects = 0
        self.gnss_accepts = 0
        self._consecutive_rejects = 0
        self.last_gnss_r = self.gnss_r_nominal
        self.last_lambda = 0.0

    # ------------------------------------------------------------------- setup
    def initialise(self, pos, vel, yaw: float = 0.0, pitch: float = 0.0,
                   roll: float = 0.0) -> None:
        self.x[P_] = np.asarray(pos, dtype=float)
        self.x[V_] = np.asarray(vel, dtype=float)
        self.x[A_] = [roll, pitch, yaw]

    @property
    def position(self) -> np.ndarray:
        return self.x[P_].copy()

    @property
    def velocity(self) -> np.ndarray:
        return self.x[V_].copy()

    @property
    def speed(self) -> float:
        return float(np.linalg.norm(self.x[V_]))

    @property
    def yaw(self) -> float:
        return float(self.x[8])

    @property
    def climb_rate(self) -> float:
        return float(self._climb_rate)

    # --------------------------------------------------------------- prediction
    def predict(self, acc_vehicle, gyro_vehicle, dt: float | None = None,
                q_scale: float = 1.0, standstill: bool = False) -> None:
        dt = self.dt if dt is None else dt
        acc = np.asarray(acc_vehicle, dtype=float)
        gyro = np.asarray(gyro_vehicle, dtype=float).copy()
        gyro[2] -= self.gyro_bias_z
        if standstill:
            self.gyro_bias_z += 0.01 * (float(gyro[2]))

        roll, pitch, yaw = self.x[A_]
        r_wb = rot_body_to_world(roll, pitch, yaw)
        a_world = r_wb @ acc - np.array([0.0, 0.0, G])
        edot = euler_rates(roll, pitch, gyro)

        # Attitude sensitivity of the specific-force rotation; finite differences
        # keep the mechanisation readable without hand-expanding dR/dEuler.
        d_att = np.zeros((3, 3))
        eps = 1e-6
        for i in range(3):
            pert = self.x[A_].copy()
            pert[i] += eps
            d_att[:, i] = (rot_body_to_world(*pert) @ acc - (r_wb @ acc)) / eps

        f = np.eye(N)
        f[P_, V_] = np.eye(3) * dt
        f[V_, A_] = d_att * dt
        f[P_, A_] = 0.5 * d_att * dt * dt

        self.x[P_] = self.x[P_] + self.x[V_] * dt + 0.5 * a_world * dt * dt
        self.x[V_] = self.x[V_] + a_world * dt
        self.x[A_] = wrap_angle(self.x[A_] + edot * dt)

        qa = (self.sigma_acc * q_scale) ** 2
        qg = self.sigma_gyro ** 2
        j_euler = euler_rate_jacobian(roll, pitch)
        q = np.zeros((N, N))
        q[P_, P_] = np.eye(3) * (qa * dt ** 3 / 3.0)
        q[P_, V_] = np.eye(3) * (qa * dt ** 2 / 2.0)
        q[V_, P_] = q[P_, V_]
        q[V_, V_] = np.eye(3) * (qa * dt)
        q[A_, A_] = j_euler @ j_euler.T * (qg * dt)

        self.P = f @ self.P @ f.T + q
        self._symmetrise()

    # ------------------------------------------------------------------ updates
    def update_speed(self, v_fwd: float, sigma: float = 0.6) -> None:
        roll, pitch, yaw = self.x[A_]
        f_hat = forward_axis(pitch, yaw)
        h = np.zeros((1, N))
        h[0, V_] = f_hat
        v = self.x[V_]
        cp, sp = np.cos(pitch), np.sin(pitch)
        cy, sy = np.cos(yaw), np.sin(yaw)
        h[0, 7] = float(v @ np.array([-sp * cy, -sp * sy, cp]))
        h[0, 8] = float(v @ np.array([-cp * sy, cp * cy, 0.0]))
        self._update(h, np.array([v_fwd - float(v @ f_hat)]),
                     np.array([[sigma ** 2]]))

    def update_nhc(self, sigma_lat: float | None = None,
                   sigma_vert: float | None = None,
                   vertical_reference: float | None = None) -> None:
        """Lateral velocity ~= 0 and vertical velocity ~= barometric climb rate."""
        sigma_lat = self.sigma_nhc_lat if sigma_lat is None else sigma_lat
        sigma_vert = self.sigma_nhc_vert if sigma_vert is None else sigma_vert
        ref_vz = self._climb_rate if vertical_reference is None else vertical_reference

        yaw = self.x[8]
        v = self.x[V_]
        lat = np.array([-np.sin(yaw), np.cos(yaw), 0.0])

        h = np.zeros((2, N))
        h[0, V_] = lat
        h[0, 8] = float(v @ np.array([-np.cos(yaw), -np.sin(yaw), 0.0]))
        h[1, 5] = 1.0

        y = np.array([0.0 - float(v @ lat), ref_vz - float(v[2])])
        r = np.diag([sigma_lat ** 2, sigma_vert ** 2])
        self._update(h, y, r)

    def update_tilt(self, acc_vehicle, dynamic_norm: float) -> None:
        """Accelerometer levelling, de-weighted while the vehicle manoeuvres."""
        acc = np.asarray(acc_vehicle, dtype=float)
        norm = float(np.linalg.norm(acc))
        if norm < 1e-3:
            return
        roll_m = float(np.arctan2(acc[1], acc[2]))
        pitch_m = float(-np.arcsin(np.clip(acc[0] / norm, -1.0, 1.0)))
        inflate = 1.0 + 40.0 * min(dynamic_norm, 6.0) ** 2
        h = np.zeros((2, N))
        h[0, 6] = 1.0
        h[1, 7] = 1.0
        y = wrap_angle(np.array([roll_m - self.x[6], pitch_m - self.x[7]]))
        r = np.eye(2) * (self.sigma_tilt ** 2 * inflate)
        self._update(h, y, r)

    def update_course(self, course: float, speed: float, sigma_deg: float = 1.5,
                      sigma_speed: float = 0.15) -> None:
        """GNSS Doppler heading and speed.

        Doppler observables are an order of magnitude more accurate than code
        position, so this is the update that actually pins down yaw and trims the
        gyro z bias. The bias correction is an integral term on the heading
        residual: without it, yaw error re-accumulates as soon as GNSS drops.
        """
        if speed < 1.5:
            return
        resid = float(wrap_angle(course - self.x[8]))
        h = np.zeros((1, N))
        h[0, 8] = 1.0
        self._update(h, np.array([resid]),
                     np.array([[np.radians(sigma_deg) ** 2]]))
        self.gyro_bias_z -= self.bias_learn_gain * resid
        self.gyro_bias_z = float(np.clip(self.gyro_bias_z, -0.05, 0.05))
        self.update_speed(speed, sigma=sigma_speed)

    def update_baro(self, altitude: float, t: float, sigma: float = 0.45) -> None:
        if self._baro_prev is not None:
            t_prev, z_prev = self._baro_prev
            dt = t - t_prev
            if dt > 1e-4:
                raw = (altitude - z_prev) / dt
                self._climb_rate += 0.25 * (np.clip(raw, -3.0, 3.0) - self._climb_rate)
        self._baro_prev = (t, altitude)

        h = np.zeros((1, N))
        h[0, 2] = 1.0
        self._update(h, np.array([altitude - self.x[2]]),
                     np.array([[sigma ** 2]]))

    def gnss_covariance(self, hdop: float) -> tuple[np.ndarray, float]:
        lam = sigmoid(hdop, self.gnss_hdop_gain, self.gnss_hdop_centre)
        r_val = self.gnss_r_nominal * max(hdop, 0.5) ** 2 + lam * self.gnss_r_max
        self.last_lambda = lam
        self.last_gnss_r = r_val
        # Vertical GNSS accuracy is roughly two to three times worse than horizontal.
        return np.diag([r_val, r_val, r_val * 4.0]), lam

    def update_gnss(self, gnss_pos, hdop: float) -> bool:
        z = np.asarray(gnss_pos, dtype=float)
        r, lam = self.gnss_covariance(hdop)
        h = np.zeros((3, N))
        h[:, P_] = np.eye(3)
        y = z - self.x[P_]
        s = h @ self.P @ h.T + r
        try:
            d2 = float(y @ np.linalg.solve(s, y))
        except np.linalg.LinAlgError:
            return False
        if d2 > self.gnss_chi2_gate and lam < 0.98:
            self._consecutive_rejects += 1
            self.gnss_rejects += 1
            # Persistent rejection means the filter, not the fix, has diverged.
            # Inflate position covariance so the next fix can pull it back.
            if self._consecutive_rejects >= self.gnss_reject_limit:
                self.P[P_, P_] += np.eye(3) * 25.0
                self._consecutive_rejects = 0
            return False
        self._update(h, y, r)
        self._consecutive_rejects = 0
        self.gnss_accepts += 1
        return True

    def update_map(self, cross_track: float, normal, sigma: float = 1.2,
                   altitude: float | None = None, sigma_alt: float = 2.5) -> None:
        """Constrain the cross-track offset from the matched centre line."""
        n = np.asarray(normal, dtype=float)
        h = np.zeros((1, N))
        h[0, 0] = n[0]
        h[0, 1] = n[1]
        self._update(h, np.array([-cross_track]), np.array([[sigma ** 2]]))
        if altitude is not None:
            hz = np.zeros((1, N))
            hz[0, 2] = 1.0
            self._update(hz, np.array([altitude - self.x[2]]),
                         np.array([[sigma_alt ** 2]]))

    def update_zero_velocity(self, sigma: float = 0.05) -> None:
        h = np.zeros((3, N))
        h[:, V_] = np.eye(3)
        self._update(h, -self.x[V_], np.eye(3) * sigma ** 2)

    # ------------------------------------------------------------------ internals
    def _update(self, h: np.ndarray, y: np.ndarray, r: np.ndarray) -> None:
        s = h @ self.P @ h.T + r
        try:
            k = np.linalg.solve(s.T, (self.P @ h.T).T).T
        except np.linalg.LinAlgError:
            return
        self.x = self.x + k @ y
        self.x[A_] = wrap_angle(self.x[A_])
        i_kh = np.eye(N) - k @ h
        self.P = i_kh @ self.P @ i_kh.T + k @ r @ k.T   # Joseph form
        self._symmetrise()

    def _symmetrise(self) -> None:
        self.P = 0.5 * (self.P + self.P.T)
        np.fill_diagonal(self.P, np.maximum(np.diag(self.P), 1e-9))
