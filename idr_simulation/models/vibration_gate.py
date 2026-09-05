"""Kinetic vibration gate.

Potholes, expansion joints and speed bumps inject high-frequency specific force
that double integration reads as real translation. The gate differentiates the
aligned acceleration, tracks the sliding variance of the jerk, and raises a
shock flag with hysteresis so the speed estimator can hold its last value and
the EKF can inflate its process noise.
"""

from __future__ import annotations

from collections import deque

import numpy as np


class VibrationGate:
    def __init__(self, dt: float = 0.01, window_s: float = 0.25,
                 enter_threshold: float = 4.0e3, exit_ratio: float = 0.45,
                 hold_s: float = 0.35, vertical_weight: float = 1.6):
        self.dt = dt
        self.window = max(4, int(round(window_s / dt)))
        self.enter_threshold = enter_threshold
        self.exit_threshold = enter_threshold * exit_ratio
        self.hold_ticks = max(1, int(round(hold_s / dt)))
        self.vertical_weight = vertical_weight

        self._prev_acc: np.ndarray | None = None
        self._jerk_hist: deque[float] = deque(maxlen=self.window)
        self._hold = 0
        self.is_shock = False
        self.variance = 0.0
        self.raw_jerk = 0.0
        self.gated_jerk = 0.0
        self.shock_events = 0

    def reset(self) -> None:
        self._prev_acc = None
        self._jerk_hist.clear()
        self._hold = 0
        self.is_shock = False
        self.variance = 0.0
        self.raw_jerk = 0.0
        self.gated_jerk = 0.0
        self.shock_events = 0

    def update(self, acc_vehicle: np.ndarray) -> dict:
        acc = np.asarray(acc_vehicle, dtype=float)
        if self._prev_acc is None:
            self._prev_acc = acc.copy()
            return self._state()

        jerk = (acc - self._prev_acc) / self.dt
        self._prev_acc = acc.copy()

        weighted = jerk * np.array([1.0, 1.0, self.vertical_weight])
        magnitude = float(np.linalg.norm(weighted))
        self._jerk_hist.append(magnitude)
        self.raw_jerk = magnitude
        self.variance = float(np.var(self._jerk_hist)) if len(self._jerk_hist) > 2 else 0.0

        was_shock = self.is_shock
        if self.variance > self.enter_threshold:
            self.is_shock = True
            self._hold = self.hold_ticks
        elif self.is_shock:
            if self.variance < self.exit_threshold and self._hold <= 0:
                self.is_shock = False
            else:
                self._hold -= 1
        if self.is_shock and not was_shock:
            self.shock_events += 1

        self.gated_jerk = 0.0 if self.is_shock else magnitude
        return self._state()

    def _state(self) -> dict:
        return {
            "is_shock": self.is_shock,
            "variance": self.variance,
            "raw_jerk": self.raw_jerk,
            "gated_jerk": self.gated_jerk,
            "events": self.shock_events,
        }

    def process_noise_scale(self) -> float:
        """Multiplier applied to the EKF velocity process noise during a shock."""
        return 25.0 if self.is_shock else 1.0
