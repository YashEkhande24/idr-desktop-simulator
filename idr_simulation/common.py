"""Frames, constants and small maths helpers shared across the IDR simulator.

Frame conventions
-----------------
World frame   : X east, Y north, Z up, metres.
Vehicle frame : X forward, Y left, Z up.
                Positive yaw   = counter-clockwise from world +X.
                Positive pitch = nose up.
                Positive roll  = left side up.

Accelerometers report *specific force*, so a level stationary sensor reads +G on
its vertical axis (not -G).
"""

from __future__ import annotations

import numpy as np

G = 9.80665
P_SEA_LEVEL_HPA = 1013.25
_BARO_EXP = 0.190263236  # 1 / 5.25588, ISA troposphere exponent

EPS = 1e-12


def wrap_angle(angle):
    """Wrap radians into [-pi, pi)."""
    return (np.asarray(angle) + np.pi) % (2.0 * np.pi) - np.pi


def unit(vector, fallback=None):
    v = np.asarray(vector, dtype=float)
    n = float(np.linalg.norm(v))
    if n < 1e-9:
        return np.zeros(3) if fallback is None else np.asarray(fallback, dtype=float)
    return v / n


def rot_body_to_world(roll: float, pitch: float, yaw: float) -> np.ndarray:
    """Rotation matrix mapping vehicle-frame vectors into the world frame."""
    cr, sr = np.cos(roll), np.sin(roll)
    cp, sp = np.cos(pitch), np.sin(pitch)
    cy, sy = np.cos(yaw), np.sin(yaw)
    rz = np.array([[cy, -sy, 0.0], [sy, cy, 0.0], [0.0, 0.0, 1.0]])
    ry = np.array([[cp, 0.0, -sp], [0.0, 1.0, 0.0], [sp, 0.0, cp]])
    rx = np.array([[1.0, 0.0, 0.0], [0.0, cr, -sr], [0.0, sr, cr]])
    return rz @ ry @ rx


def forward_axis(pitch: float, yaw: float) -> np.ndarray:
    """Unit vector along the vehicle longitudinal axis, expressed in world axes."""
    cp = np.cos(pitch)
    return np.array([cp * np.cos(yaw), cp * np.sin(yaw), np.sin(pitch)])


def euler_rates(roll: float, pitch: float, gyro) -> np.ndarray:
    """Convert body angular rates [p, q, r] into [roll_dot, pitch_dot, yaw_dot]."""
    p, q, r = float(gyro[0]), float(gyro[1]), float(gyro[2])
    cp = np.cos(pitch)
    cp = np.sign(cp) * max(abs(cp), 1e-4) if cp != 0.0 else 1e-4
    sr, cr = np.sin(roll), np.cos(roll)
    yaw_dot = (q * sr + r * cr) / cp
    pitch_dot = -q * cr + r * sr
    roll_dot = p + yaw_dot * np.sin(pitch)
    return np.array([roll_dot, pitch_dot, yaw_dot])


def euler_rate_jacobian(roll: float, pitch: float) -> np.ndarray:
    """d(euler_rates)/d(gyro): maps body-rate errors into Euler-rate errors."""
    cp = np.cos(pitch)
    cp = np.sign(cp) * max(abs(cp), 1e-4) if cp != 0.0 else 1e-4
    tp = np.sin(pitch) / cp
    sr, cr = np.sin(roll), np.cos(roll)
    return np.array([
        [1.0, tp * sr, tp * cr],
        [0.0, -cr, sr],
        [0.0, sr / cp, cr / cp],
    ])


def body_rates(roll: float, pitch: float, euler_dot) -> np.ndarray:
    """Inverse of :func:`euler_rates`: Euler rates back to body rates [p, q, r]."""
    roll_dot, pitch_dot, yaw_dot = (float(v) for v in euler_dot)
    a = yaw_dot * np.cos(pitch)
    sr, cr = np.sin(roll), np.cos(roll)
    q = a * sr - pitch_dot * cr
    r = a * cr + pitch_dot * sr
    p = roll_dot - yaw_dot * np.sin(pitch)
    return np.array([p, q, r])


def altitude_from_pressure(pressure_hpa: float) -> float:
    """ISA pressure altitude [m] used by the barometric elevation update."""
    return 44330.0 * (1.0 - (pressure_hpa / P_SEA_LEVEL_HPA) ** _BARO_EXP)


def pressure_from_altitude(altitude_m: float) -> float:
    return P_SEA_LEVEL_HPA * (1.0 - altitude_m / 44330.0) ** (1.0 / _BARO_EXP)


def sigmoid(x: float, gain: float = 1.0, centre: float = 0.0) -> float:
    """Numerically safe logistic used for the HDOP covariance schedule."""
    z = gain * (x - centre)
    if z >= 0.0:
        return 1.0 / (1.0 + np.exp(-min(z, 60.0)))
    e = np.exp(max(z, -60.0))
    return e / (1.0 + e)
