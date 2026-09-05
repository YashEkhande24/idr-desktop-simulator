"""Synthetic ground-truth trajectory and sensor stream for the IDR simulator.

The road geometry is built once in arc-length space (curvature + grade profile),
so the vehicle speed schedule can change without disturbing the shape of the
road.  Sensors are then sampled from the exact kinematics:

* IMU        100 Hz, arbitrary phone mounting rotation, bias/noise/shock errors
* Barometer   10 Hz, ISA pressure altitude with slow drift
* GNSS         1 Hz, HDOP-driven noise, multipath in canyons, denial in tunnels
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from ..common import (
    G,
    pressure_from_altitude,
    altitude_from_pressure,
    rot_body_to_world,
    body_rates,
    wrap_angle,
)

# Road tag bit flags carried along the arc-length grid.
TAG_ROUGH = 1 << 0
TAG_FLYOVER = 1 << 1
TAG_TUNNEL = 1 << 2
TAG_CANYON = 1 << 3
TAG_SPLIT = 1 << 4


@dataclass
class Segment:
    """One stretch of road, described in the arc-length domain."""

    length: float
    kappa: float = 0.0          # signed curvature [1/m], positive = left turn
    grade: float = 0.0          # dz/ds, e.g. 0.05 = 5 % climb
    tags: int = 0
    speed_limit: float = 16.5   # m/s target cruise for this stretch


def default_route() -> list[Segment]:
    """Straight -> curve -> potholes -> flyover split -> canyon -> 180 s tunnel."""
    return [
        Segment(250.0, 0.0, 0.0, 0, 16.5),
        Segment(314.0, 1.0 / 200.0, 0.0, 0, 13.0),
        Segment(170.0, 0.0, 0.0, TAG_ROUGH, 11.0),
        Segment(130.0, -1.0 / 400.0, 0.055, TAG_FLYOVER | TAG_SPLIT, 13.5),
        Segment(150.0, 0.0, 0.0, TAG_FLYOVER, 16.0),
        Segment(130.0, 1.0 / 400.0, -0.055, TAG_FLYOVER, 15.0),
        Segment(220.0, 0.0, 0.0, TAG_CANYON, 14.0),
        Segment(800.0, 0.0, -0.012, TAG_TUNNEL, 15.5),
        Segment(500.0, -1.0 / 500.0, 0.0, TAG_TUNNEL, 15.0),
        Segment(700.0, 0.0, 0.0, TAG_TUNNEL, 16.0),
        Segment(400.0, 1.0 / 600.0, 0.010, TAG_TUNNEL, 15.0),
        Segment(300.0, 0.0, 0.008, TAG_TUNNEL, 15.5),
        Segment(400.0, 0.0, 0.0, 0, 16.5),
    ]


class RoadGeometry:
    """Arc-length sampled road: position, heading, curvature, grade and tags."""

    def __init__(self, segments: list[Segment] | None = None, ds: float = 0.5,
                 smooth_m: float = 25.0):
        self.segments = segments if segments is not None else default_route()
        self.ds = float(ds)
        total = float(sum(seg.length for seg in self.segments))
        n = int(round(total / self.ds)) + 1
        self.s = np.arange(n) * self.ds

        kappa = np.zeros(n)
        grade = np.zeros(n)
        v_lim = np.zeros(n)
        tags = np.zeros(n, dtype=np.int32)

        edge = 0.0
        for seg in self.segments:
            i0 = int(round(edge / self.ds))
            i1 = min(n, int(round((edge + seg.length) / self.ds)) + 1)
            kappa[i0:i1] = seg.kappa
            grade[i0:i1] = seg.grade
            v_lim[i0:i1] = seg.speed_limit
            tags[i0:i1] |= seg.tags
            edge += seg.length

        # Real roads use transition spirals and vertical curves; a boxcar filter
        # keeps yaw/pitch rates finite without changing the overall shape.
        self.kappa = _smooth(kappa, smooth_m, self.ds)
        self.grade = _smooth(grade, smooth_m, self.ds)
        self.speed_limit = _smooth(v_lim, 60.0, self.ds)
        self.tags = tags

        self.yaw = np.cumsum(self.kappa) * self.ds
        self.yaw -= self.yaw[0]
        self.pitch = np.arctan(self.grade)

        cp = np.cos(self.pitch)
        dx = cp * np.cos(self.yaw) * self.ds
        dy = cp * np.sin(self.yaw) * self.ds
        dz = self.grade * cp * self.ds
        self.x = np.concatenate(([0.0], np.cumsum(dx[:-1])))
        self.y = np.concatenate(([0.0], np.cumsum(dy[:-1])))
        self.z = np.concatenate(([0.0], np.cumsum(dz[:-1])))

    @property
    def total_length(self) -> float:
        return float(self.s[-1])

    def index_of(self, s: float) -> int:
        return int(np.clip(round(s / self.ds), 0, len(self.s) - 1))

    def sample(self, s: float) -> dict:
        """Interpolate the road state at arc length ``s``."""
        s = float(np.clip(s, 0.0, self.total_length))
        i = self.index_of(s)
        return {
            "pos": np.array([
                np.interp(s, self.s, self.x),
                np.interp(s, self.s, self.y),
                np.interp(s, self.s, self.z),
            ]),
            "yaw": float(np.interp(s, self.s, self.yaw)),
            "pitch": float(np.interp(s, self.s, self.pitch)),
            "kappa": float(np.interp(s, self.s, self.kappa)),
            "grade": float(np.interp(s, self.s, self.grade)),
            "speed_limit": float(np.interp(s, self.s, self.speed_limit)),
            "tags": int(self.tags[i]),
        }

    def centerline(self, step_m: float = 5.0) -> np.ndarray:
        """Down-sampled (N, 3) polyline used as the map-matching reference."""
        stride = max(1, int(round(step_m / self.ds)))
        return np.column_stack((self.x, self.y, self.z))[::stride].copy()

    def decoy_branch(self, step_m: float = 5.0, max_offset: float = 14.0) -> np.ndarray:
        """At-grade road running under the flyover.

        Same corridor, laterally offset and held at ground level, so the
        map snapper can only pick the right branch by trusting the barometer.
        """
        flyover = np.flatnonzero(self.tags & TAG_FLYOVER)
        if flyover.size == 0:
            return np.empty((0, 3))
        i0 = max(0, flyover[0] - int(60.0 / self.ds))
        i1 = min(len(self.s) - 1, flyover[-1] + int(60.0 / self.ds))
        idx = np.arange(i0, i1 + 1)

        u = (idx - idx[0]) / max(1, idx[-1] - idx[0])
        offset = max_offset * np.sin(np.pi * u) ** 2
        nx = -np.sin(self.yaw[idx])
        ny = np.cos(self.yaw[idx])

        pts = np.column_stack((
            self.x[idx] + offset * nx,
            self.y[idx] + offset * ny,
            np.zeros(idx.size),
        ))
        stride = max(1, int(round(step_m / self.ds)))
        return pts[::stride].copy()


def _smooth(values: np.ndarray, window_m: float, ds: float) -> np.ndarray:
    k = max(1, int(round(window_m / ds)))
    if k <= 1:
        return values.astype(float)
    kernel = np.ones(k) / k
    pad = k // 2
    padded = np.pad(values.astype(float), pad, mode="edge")
    return np.convolve(padded, kernel, mode="same")[pad:pad + values.size]


@dataclass
class VibrationModel:
    """Speed-dependent excitation that makes speed observable from the IMU.

    Three physical mechanisms, all of which scale with velocity and are what an
    IMU-only speed regressor actually learns from:

    * broadband tyre/road texture, amplitude growing with speed and roughness
    * a harmonic at wheel rotation frequency ``v / (2*pi*r)`` from tyre
      out-of-roundness, i.e. a direct spectral encoding of speed
    * suspension wheel-hop near 12 Hz plus a gear-dependent engine order
    """

    wheel_radius: float = 0.31
    texture_gain: float = 0.17
    wheel_gain: float = 0.11
    hop_gain: float = 0.13
    engine_gain: float = 0.075
    hop_hz: float = 12.0
    gear_ratios: tuple[float, float, float, float, float] = (5.2, 3.1, 2.1, 1.6, 1.25)

    def engine_hz(self, speed: float) -> float:
        gear = int(np.clip(speed / 7.0, 0, len(self.gear_ratios) - 1))
        return 11.0 + 0.55 * self.gear_ratios[gear] * max(speed, 0.5)


@dataclass
class ImuErrorModel:
    """Consumer-grade smartphone MEMS error budget."""

    accel_noise: float = 0.06          # m/s^2 rms
    gyro_noise: float = 0.004          # rad/s rms
    accel_bias: np.ndarray = field(default_factory=lambda: np.array([0.08, -0.05, 0.11]))
    gyro_bias: np.ndarray = field(default_factory=lambda: np.array([0.004, -0.003, 0.006]))
    accel_walk: float = 0.004          # m/s^2 per sqrt(s)
    gyro_walk: float = 2.0e-4          # rad/s per sqrt(s)
    accel_scale: np.ndarray = field(default_factory=lambda: np.array([1.004, 0.997, 1.006]))


@dataclass
class SimConfig:
    dt: float = 0.01
    mount_euler_deg: tuple[float, float, float] = (12.0, -35.0, 24.0)
    enable_potholes: bool = True
    enable_gnss_outage: bool = True
    seed: int = 20260905
    baro_rate_hz: float = 10.0
    gnss_rate_hz: float = 1.0


class SensorSimulator:
    """Drives the vehicle along :class:`RoadGeometry` and emits sensor packets."""

    def __init__(self, config: SimConfig | None = None,
                 geometry: RoadGeometry | None = None):
        self.cfg = config or SimConfig()
        self.geometry = geometry or RoadGeometry()
        self.error = ImuErrorModel()
        self.vibration = VibrationModel()
        self.mount = rot_body_to_world(*np.radians(self.cfg.mount_euler_deg))
        self.reset()

    # ------------------------------------------------------------------ setup
    def reset(self) -> None:
        cfg = self.cfg
        self.rng = np.random.default_rng(cfg.seed)
        self.t = 0.0
        self.s = 0.0
        self.speed = self.geometry.sample(0.0)["speed_limit"]
        self.prev_yaw = self.geometry.sample(0.0)["yaw"]
        self.prev_pitch = self.geometry.sample(0.0)["pitch"]
        self.finished = False

        self._accel_bias = self.error.accel_bias.copy()
        self._gyro_bias = self.error.gyro_bias.copy()
        self._baro_drift = 0.0
        self._shock = np.zeros(3)
        self._shock_gyro = np.zeros(3)
        self._texture = np.zeros(3)
        self._phase = np.zeros(3)   # wheel, hop, engine
        self._next_pothole_s = 0.0
        self._baro_period = max(1, int(round(1.0 / (cfg.baro_rate_hz * cfg.dt))))
        self._gnss_period = max(1, int(round(1.0 / (cfg.gnss_rate_hz * cfg.dt))))
        self._tick = 0
        self._gnss_bias = np.zeros(3)

    @property
    def progress(self) -> float:
        return float(np.clip(self.s / self.geometry.total_length, 0.0, 1.0))

    # ------------------------------------------------------------------- step
    def step(self) -> dict:
        cfg = self.cfg
        dt = cfg.dt
        rng = self.rng

        road = self.geometry.sample(self.s)
        tags = road["tags"]

        # Speed schedule: first-order lag onto the local limit plus mild traffic
        # modulation, so the TCN sees genuine accelerate/brake transients.
        target = road["speed_limit"] * (1.0 + 0.06 * np.sin(0.09 * self.t))
        accel_cmd = np.clip((target - self.speed) / 3.0, -2.2, 1.6)
        self.speed = max(0.0, self.speed + accel_cmd * dt)

        yaw_rate = self.speed * road["kappa"]
        pitch_rate = wrap_angle(road["pitch"] - self.prev_pitch) / dt if self.t > 0 else 0.0

        self.s += self.speed * dt
        nxt = self.geometry.sample(self.s)
        yaw, pitch = nxt["yaw"], nxt["pitch"]
        # Body roll from lateral load transfer on a compliant suspension.
        roll = float(np.clip(-0.045 * self.speed * nxt["kappa"] * self.speed, -0.12, 0.12))

        true_pos = nxt["pos"]
        heading = np.array([np.cos(pitch) * np.cos(yaw),
                            np.cos(pitch) * np.sin(yaw),
                            np.sin(pitch)])
        true_vel = self.speed * heading

        # --- ideal specific force in the vehicle frame -----------------------
        a_body = np.array([accel_cmd,
                           self.speed * yaw_rate,
                           self.speed * pitch_rate])
        r_wb = rot_body_to_world(roll, pitch, yaw)
        a_body = a_body + r_wb.T @ np.array([0.0, 0.0, G])
        gyro_body = body_rates(roll, pitch, np.array([0.0, pitch_rate, yaw_rate]))

        # --- road shocks -----------------------------------------------------
        rough = bool(tags & TAG_ROUGH) and cfg.enable_potholes
        pothole_hit = False
        if rough and self.s >= self._next_pothole_s:
            self._next_pothole_s = self.s + rng.uniform(6.0, 18.0)
            mag = rng.uniform(9.0, 22.0)
            self._shock = np.array([rng.normal(0.0, 0.35 * mag),
                                    rng.normal(0.0, 0.35 * mag),
                                    -mag])
            self._shock_gyro = rng.normal(0.0, 0.25, 3)
            pothole_hit = True
        elif not rough:
            self._next_pothole_s = self.s

        # Decaying oscillation reproduces the suspension ring-down after a hit.
        self._shock *= 0.72
        self._shock_gyro *= 0.72
        if np.linalg.norm(self._shock) < 1e-3:
            self._shock[:] = 0.0
        texture = self._road_excitation(self.speed, rough, dt)

        # --- IMU output in the (tilted) phone frame --------------------------
        err = self.error
        self._accel_bias += rng.normal(0.0, err.accel_walk * np.sqrt(dt), 3)
        self._gyro_bias += rng.normal(0.0, err.gyro_walk * np.sqrt(dt), 3)

        a_true_body = a_body + self._shock + texture
        w_true_body = gyro_body + self._shock_gyro

        acc_phone = self.mount.T @ a_true_body
        gyro_phone = self.mount.T @ w_true_body
        acc_phone = acc_phone * err.accel_scale + self._accel_bias
        acc_phone = acc_phone + rng.normal(0.0, err.accel_noise, 3)
        gyro_phone = gyro_phone + self._gyro_bias + rng.normal(0.0, err.gyro_noise, 3)

        # --- barometer -------------------------------------------------------
        self._baro_drift += rng.normal(0.0, 0.02 * np.sqrt(dt))
        baro_alt = None
        baro_pressure = None
        if self._tick % self._baro_period == 0:
            # Tunnels see a static pressure offset from the piston effect.
            bias = -0.9 if (tags & TAG_TUNNEL) else 0.0
            baro_pressure = float(pressure_from_altitude(true_pos[2] + bias + self._baro_drift)
                                  + rng.normal(0.0, 0.03))
            baro_alt = float(altitude_from_pressure(baro_pressure) + rng.normal(0.0, 0.12))

        # --- GNSS ------------------------------------------------------------
        gnss_pos = None
        gnss_speed = None
        gnss_course = None
        gnss_valid = False
        hdop = 0.8
        if tags & TAG_TUNNEL:
            hdop = 30.0
        elif tags & TAG_CANYON:
            hdop = 4.2 + 1.4 * np.sin(0.7 * self.t)
        elif tags & TAG_FLYOVER:
            hdop = 1.6
        else:
            hdop = 0.85 + 0.15 * np.sin(0.3 * self.t)

        if self._tick % self._gnss_period == 0:
            denied = bool(tags & TAG_TUNNEL) and cfg.enable_gnss_outage
            self._gnss_bias = 0.85 * self._gnss_bias + rng.normal(0.0, 0.35, 3)
            if denied:
                # Total loss of lock: no fix is reported at all.
                gnss_pos, gnss_valid = None, False
            else:
                sigma = 0.9 * max(hdop, 0.5)
                noise = rng.normal(0.0, sigma, 3) * np.array([1.0, 1.0, 1.8])
                if hdop > 3.0 and rng.random() < 0.35:
                    noise += rng.normal(0.0, 6.0 * hdop, 3)   # canyon multipath
                gnss_pos = true_pos + self._gnss_bias + noise
                gnss_valid = True
                # Doppler speed/course are far more accurate than position.
                gnss_speed = float(max(0.0, self.speed + rng.normal(0.0, 0.06 * max(hdop, 0.5))))
                gnss_course = float(yaw + rng.normal(0.0, 0.01 * max(hdop, 0.5)))

        self.t += dt
        self._tick += 1
        self.prev_yaw, self.prev_pitch = yaw, pitch
        if self.s >= self.geometry.total_length - 1e-6:
            self.finished = True

        return {
            "t": self.t,
            "dt": dt,
            "s": self.s,
            "true_pos": true_pos.copy(),
            "true_vel": true_vel,
            "true_speed": float(self.speed),
            "true_yaw": float(yaw),
            "true_pitch": float(pitch),
            "true_roll": float(roll),
            "yaw_rate": float(yaw_rate),
            "imu_acc": acc_phone,
            "imu_gyro": gyro_phone,
            "acc_vehicle_true": a_true_body,
            "gnss_pos": gnss_pos,
            "gnss_valid": gnss_valid,
            "gnss_speed": gnss_speed,
            "gnss_course": gnss_course,
            "hdop": float(hdop),
            "baro_alt": baro_alt,
            "baro_pressure": baro_pressure,
            "tags": tags,
            "is_tunnel": bool(tags & TAG_TUNNEL),
            "is_rough": rough,
            "pothole_hit": pothole_hit,
            "is_flyover": bool(tags & TAG_FLYOVER),
            "is_canyon": bool(tags & TAG_CANYON),
        }

    # ------------------------------------------------------------- vibration
    def _road_excitation(self, speed: float, rough: bool, dt: float) -> np.ndarray:
        vm = self.vibration
        rng = self.rng
        v = max(float(speed), 0.2)
        roughness = 3.4 if rough else 1.0
        ratio = v / 12.0

        amp = vm.texture_gain * roughness * ratio ** 1.25
        self._texture = 0.55 * self._texture + rng.normal(0.0, amp, 3) * np.array([0.5, 0.55, 1.0])

        f_wheel = v / (2.0 * np.pi * vm.wheel_radius)
        f_engine = vm.engine_hz(v)
        self._phase = (self._phase + 2.0 * np.pi * dt *
                       np.array([f_wheel, vm.hop_hz, f_engine])) % (2.0 * np.pi)
        pw, ph, pe = self._phase

        a_wheel = vm.wheel_gain * roughness * ratio * np.array([
            0.28 * np.sin(pw), 0.32 * np.cos(pw + 0.7), np.sin(pw)])
        a_hop = vm.hop_gain * roughness * ratio ** 1.5 * np.array([
            0.2 * np.cos(ph), 0.22 * np.sin(ph + 1.1), np.sin(ph)])
        a_engine = vm.engine_gain * (0.5 + 0.5 * ratio) * np.array([
            0.6 * np.sin(pe), 0.45 * np.sin(0.5 * pe), 0.8 * np.cos(pe)])
        return self._texture + a_wheel + a_hop + a_engine
