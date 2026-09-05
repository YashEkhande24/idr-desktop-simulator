"""Classic strapdown dead reckoning baseline.

Deliberately naive, and that is the point of the comparison: raw gyro
integration for attitude, gravity removed with the estimated attitude, and
double integration of the residual specific force. No speed model, no
non-holonomic constraints, no vibration gate, no map. Bias and levelling errors
therefore grow as t^2, which is the drift the IDR pipeline is measured against.
"""

from __future__ import annotations

import numpy as np

from ..common import G, euler_rates, rot_body_to_world, wrap_angle


class ClassicDeadReckoning:
    def __init__(self, dt: float = 0.01):
        self.dt = dt
        self.pos = np.zeros(3)
        self.vel = np.zeros(3)
        self.att = np.zeros(3)   # roll, pitch, yaw

    def initialise(self, pos, vel, roll: float = 0.0, pitch: float = 0.0,
                   yaw: float = 0.0) -> None:
        self.pos = np.asarray(pos, dtype=float).copy()
        self.vel = np.asarray(vel, dtype=float).copy()
        self.att = np.array([roll, pitch, yaw], dtype=float)

    def update(self, acc_vehicle, gyro_vehicle, dt: float | None = None) -> None:
        dt = self.dt if dt is None else dt
        acc = np.asarray(acc_vehicle, dtype=float)
        gyro = np.asarray(gyro_vehicle, dtype=float)

        self.att = wrap_angle(self.att + euler_rates(*self.att[:2], gyro) * dt)
        a_world = rot_body_to_world(*self.att) @ acc - np.array([0.0, 0.0, G])
        self.vel = self.vel + a_world * dt
        self.pos = self.pos + self.vel * dt

    @property
    def speed(self) -> float:
        return float(np.linalg.norm(self.vel))
