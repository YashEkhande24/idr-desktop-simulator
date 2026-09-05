"""Orchestrator wiring the full IDR pipeline and the classic DR baseline.

One :meth:`IDRPipeline.step` advances the simulated vehicle by one IMU tick and
returns a flat telemetry record. Both the desktop GUI and the headless
benchmark run this identical code path.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .common import G
from .fusion.classic_dr import ClassicDeadReckoning
from .fusion.ekf_3d import IntelligentEKF
from .fusion.map_snapper import MapSnapper, branches_from_geometry
from .models.tcn_speed_engine import SpeedEngine
from .models.vibration_gate import VibrationGate
from .sensors.cabin_alignment import CabinAligner
from .sensors.generator import RoadGeometry, SensorSimulator, SimConfig


@dataclass
class PipelineOptions:
    enable_potholes: bool = True
    enable_gnss_outage: bool = True
    enable_vibration_gate: bool = True
    enable_nhc: bool = True
    enable_map_snapping: bool = True
    enable_baro: bool = True
    enable_tcn: bool = True
    seed: int = 20260905
    mount_euler_deg: tuple[float, float, float] = (12.0, -35.0, 24.0)
    map_update_hz: float = 5.0
    backend_preference: str | None = None


@dataclass
class RunStats:
    n: int = 0
    idr_sq: float = 0.0
    classic_sq: float = 0.0
    idr_max: float = 0.0
    classic_max: float = 0.0
    idr_final: float = 0.0
    classic_final: float = 0.0
    speed_sq: float = 0.0
    tunnel_n: int = 0
    tunnel_idr_sq: float = 0.0
    tunnel_idr_max: float = 0.0
    tunnel_classic_max: float = 0.0
    shock_events: int = 0

    def as_dict(self) -> dict:
        rms = lambda s, n: float(np.sqrt(s / n)) if n else 0.0  # noqa: E731
        return {
            "samples": self.n,
            "idr_rmse_m": rms(self.idr_sq, self.n),
            "classic_rmse_m": rms(self.classic_sq, self.n),
            "idr_max_m": self.idr_max,
            "classic_max_m": self.classic_max,
            "idr_final_m": self.idr_final,
            "classic_final_m": self.classic_final,
            "speed_rmse_mps": rms(self.speed_sq, self.n),
            "tunnel_idr_rmse_m": rms(self.tunnel_idr_sq, self.tunnel_n),
            "tunnel_idr_max_m": self.tunnel_idr_max,
            "tunnel_classic_max_m": self.tunnel_classic_max,
            "shock_events": self.shock_events,
        }


class IDRPipeline:
    def __init__(self, options: PipelineOptions | None = None):
        self.options = options or PipelineOptions()
        self.geometry = RoadGeometry()
        self.reset()

    # ------------------------------------------------------------------- setup
    def reset(self, options: PipelineOptions | None = None) -> None:
        if options is not None:
            self.options = options
        opt = self.options

        self.sim = SensorSimulator(
            SimConfig(seed=opt.seed, mount_euler_deg=opt.mount_euler_deg,
                      enable_potholes=opt.enable_potholes,
                      enable_gnss_outage=opt.enable_gnss_outage),
            geometry=self.geometry,
        )
        dt = self.sim.cfg.dt
        self.dt = dt

        self.aligner = CabinAligner(dt=dt)
        self.gate = VibrationGate(dt=dt)
        if not hasattr(self, "speed_engine") or self.speed_engine is None:
            self.speed_engine = SpeedEngine(dt=dt, prefer=opt.backend_preference)
        self.ekf = IntelligentEKF(dt=dt)
        self.classic = ClassicDeadReckoning(dt=dt)
        if not hasattr(self, "snapper") or self.snapper is None:
            self.snapper = MapSnapper(branches_from_geometry(self.geometry))

        start = self.geometry.sample(0.0)
        v0 = start["speed_limit"] * np.array([np.cos(start["yaw"]), np.sin(start["yaw"]), 0.0])
        self.ekf.initialise(start["pos"], v0, yaw=start["yaw"], pitch=start["pitch"])
        self.classic.initialise(start["pos"], v0, pitch=start["pitch"], yaw=start["yaw"])
        self.speed_engine.reset(float(start["speed_limit"]))

        self._map_period = max(1, int(round(1.0 / (opt.map_update_hz * dt))))
        self._tick = 0
        self.stats = RunStats()
        self.history = {k: [] for k in ("t", "truth", "idr", "classic", "gnss",
                                        "speed_true", "speed_tcn", "speed_idr",
                                        "speed_classic", "jerk_raw",
                                        "jerk_gated", "alt_true", "alt_baro",
                                        "alt_idr", "err_idr", "err_classic", "hdop")}
        self.last: dict = {}

    @property
    def finished(self) -> bool:
        return self.sim.finished

    @property
    def backend(self) -> str:
        return self.speed_engine.backend

    # -------------------------------------------------------------------- step
    def step(self) -> dict:
        opt = self.options
        pkt = self.sim.step()
        self._tick += 1

        align = self.aligner.update(pkt["imu_acc"], pkt["imu_gyro"])
        acc_v = align["acc_vehicle"]
        acc_dyn = align["acc_dynamic"]
        gyro_v = align["gyro_vehicle"]

        gate = (self.gate.update(acc_v) if opt.enable_vibration_gate
                else {"is_shock": False, "variance": 0.0,
                      "raw_jerk": 0.0, "gated_jerk": 0.0, "events": 0})
        shock = bool(gate["is_shock"])

        spd = self.speed_engine.update(acc_dyn, float(gyro_v[2]), shock)
        v_hat = spd["v_hat"] if opt.enable_tcn else spd["v_heuristic"]

        standstill = v_hat < 0.35 and abs(float(gyro_v[2])) < 0.03
        q_scale = self.gate.process_noise_scale() if opt.enable_vibration_gate else 1.0
        self.ekf.predict(acc_v, gyro_v, q_scale=q_scale, standstill=standstill)

        if not shock:
            self.ekf.update_speed(v_hat, sigma=spd["sigma"])
        if opt.enable_nhc:
            self.ekf.update_nhc()
        self.ekf.update_tilt(acc_v, float(np.linalg.norm(acc_dyn)))
        if standstill:
            self.ekf.update_zero_velocity()

        if opt.enable_baro and pkt["baro_alt"] is not None:
            self.ekf.update_baro(float(pkt["baro_alt"]), pkt["t"])

        gnss_used = False
        if pkt["gnss_pos"] is not None:
            gnss_used = self.ekf.update_gnss(pkt["gnss_pos"], pkt["hdop"])
        if pkt["gnss_speed"] is not None and pkt["hdop"] < 6.0:
            self.ekf.update_course(float(pkt["gnss_course"]), float(pkt["gnss_speed"]),
                                   sigma_deg=1.5 * max(pkt["hdop"], 0.5))
            self.speed_engine.calibrate(float(pkt["gnss_speed"]))

        match = None
        if opt.enable_map_snapping and self._tick % self._map_period == 0:
            vel = self.ekf.velocity
            match = self.snapper.match(self.ekf.position, vel, pkt["hdop"])
            if match is not None:
                sigma = self.snapper.lateral_sigma(pkt["hdop"], match)
                self.ekf.update_map(match.cross_track, match.normal, sigma=sigma)

        self.classic.update(acc_v, gyro_v)

        truth = pkt["true_pos"]
        err_idr = float(np.linalg.norm(self.ekf.position[:2] - truth[:2]))
        err_classic = float(np.linalg.norm(self.classic.pos[:2] - truth[:2]))
        self._accumulate(pkt, err_idr, err_classic, v_hat)

        record = {
            "t": pkt["t"],
            "truth": truth,
            "truth_speed": pkt["true_speed"],
            "idr_pos": self.ekf.position,
            "idr_vel": self.ekf.velocity,
            "idr_speed": self.ekf.speed,
            "idr_yaw": self.ekf.yaw,
            "yaw_err_deg": float(np.degrees(np.arctan2(
                np.sin(self.ekf.yaw - pkt["true_yaw"]),
                np.cos(self.ekf.yaw - pkt["true_yaw"])))),
            "gyro_bias_z": self.ekf.gyro_bias_z,
            "classic_pos": self.classic.pos.copy(),
            "classic_speed": self.classic.speed,
            "gnss_pos": pkt["gnss_pos"],
            "gnss_used": gnss_used,
            "hdop": pkt["hdop"],
            "lambda_hdop": self.ekf.last_lambda,
            "gnss_r": self.ekf.last_gnss_r,
            "gnss_rejects": self.ekf.gnss_rejects,
            "baro_alt": pkt["baro_alt"],
            "v_tcn": v_hat,
            "v_raw": spd["v_raw"],
            "speed_backend": spd["backend"],
            "shock": shock,
            "jerk_raw": gate["raw_jerk"],
            "jerk_gated": gate["gated_jerk"],
            "jerk_var": gate["variance"],
            "shock_events": gate["events"],
            "align_conf": align["confidence"],
            "align_locked": align["locked"],
            "mount_roll": align["roll_mount"],
            "mount_pitch": align["pitch_mount"],
            "match": match,
            "err_idr": err_idr,
            "err_classic": err_classic,
            "is_tunnel": pkt["is_tunnel"],
            "is_rough": pkt["is_rough"],
            "is_flyover": pkt["is_flyover"],
            "is_canyon": pkt["is_canyon"],
            "progress": self.sim.progress,
            "finished": self.sim.finished,
        }
        self.last = record
        self._log(record, pkt)
        return record

    # ------------------------------------------------------------------ logging
    def _accumulate(self, pkt: dict, err_idr: float, err_classic: float,
                    v_hat: float) -> None:
        st = self.stats
        st.n += 1
        st.idr_sq += err_idr ** 2
        st.classic_sq += err_classic ** 2
        st.idr_max = max(st.idr_max, err_idr)
        st.classic_max = max(st.classic_max, err_classic)
        st.idr_final = err_idr
        st.classic_final = err_classic
        st.speed_sq += (v_hat - pkt["true_speed"]) ** 2
        st.shock_events = self.gate.shock_events
        if pkt["is_tunnel"]:
            st.tunnel_n += 1
            st.tunnel_idr_sq += err_idr ** 2
            st.tunnel_idr_max = max(st.tunnel_idr_max, err_idr)
            st.tunnel_classic_max = max(st.tunnel_classic_max, err_classic)

    def _log(self, rec: dict, pkt: dict) -> None:
        h = self.history
        h["t"].append(rec["t"])
        h["truth"].append(rec["truth"].copy())
        h["idr"].append(rec["idr_pos"].copy())
        h["classic"].append(rec["classic_pos"].copy())
        h["speed_true"].append(rec["truth_speed"])
        h["speed_tcn"].append(rec["v_tcn"])
        h["speed_idr"].append(rec["idr_speed"])
        h["speed_classic"].append(rec["classic_speed"])
        h["jerk_raw"].append(rec["jerk_raw"])
        h["jerk_gated"].append(rec["jerk_gated"])
        h["alt_true"].append(float(rec["truth"][2]))
        h["alt_idr"].append(float(rec["idr_pos"][2]))
        h["hdop"].append(rec["hdop"])
        h["err_idr"].append(rec["err_idr"])
        h["err_classic"].append(rec["err_classic"])
        if pkt["baro_alt"] is not None:
            h["alt_baro"].append((rec["t"], float(pkt["baro_alt"])))
        if rec["gnss_pos"] is not None:
            h["gnss"].append(np.asarray(rec["gnss_pos"]).copy())

    def summary(self) -> dict:
        out = self.stats.as_dict()
        out["speed_backend"] = self.backend
        out["gnss_accepts"] = self.ekf.gnss_accepts
        out["gnss_rejects"] = self.ekf.gnss_rejects
        return out
