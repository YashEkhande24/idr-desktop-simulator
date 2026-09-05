"""TCN speed engine: IMU window -> forward speed.

The regressor is a causal, dilated 1-D convolutional network over the last two
seconds of aligned IMU data ``[a_fwd, a_lat, a_vert, w_yaw]`` at 100 Hz.

Backends are tried in order, so the simulator always has a working estimator:

1. ``torch``     - trained ``tcn_speed.pt`` weights
2. ``onnx``      - ``tcn_speed.onnx`` through onnxruntime
3. ``numpy``     - ``tcn_speed.npz`` weights, pure NumPy causal convolutions
4. ``heuristic`` - drag-damped integration of a_fwd with zero-velocity updates

Run ``python -m idr_simulation.models.tcn_speed_engine --train`` to fit the
network against the synthetic generator and write all three artefacts.
"""

from __future__ import annotations

import argparse
from collections import deque
from dataclasses import dataclass
from pathlib import Path

import numpy as np

WINDOW = 200          # samples, 2.0 s at 100 Hz
CHANNELS_IN = 4
WEIGHTS_DIR = Path(__file__).resolve().parent / "weights"
PT_PATH = WEIGHTS_DIR / "tcn_speed.pt"
ONNX_PATH = WEIGHTS_DIR / "tcn_speed.onnx"
NPZ_PATH = WEIGHTS_DIR / "tcn_speed.npz"

# Channel-wise normalisation, matched by every backend.
INPUT_MEAN = np.array([0.0, 0.0, 0.0, 0.0], dtype=np.float32)
INPUT_SCALE = np.array([2.0, 2.0, 3.0, 0.2], dtype=np.float32)
SPEED_SCALE = 20.0    # network predicts v / SPEED_SCALE


@dataclass
class TCNConfig:
    channels: tuple[int, ...] = (32, 32, 64)
    dilations: tuple[int, ...] = (1, 2, 4)
    kernel_size: int = 3
    head_units: int = 32
    dropout: float = 0.05
    window: int = WINDOW


# --------------------------------------------------------------------- PyTorch
def _build_torch_model(cfg: TCNConfig):
    import torch
    from torch import nn

    class CausalConv1d(nn.Conv1d):
        def __init__(self, c_in, c_out, kernel_size, dilation):
            super().__init__(c_in, c_out, kernel_size, dilation=dilation)
            self._pad = (kernel_size - 1) * dilation

        def forward(self, x):  # type: ignore[override]
            return super().forward(nn.functional.pad(x, (self._pad, 0)))

    class ResidualBlock(nn.Module):
        def __init__(self, c_in, c_out, kernel_size, dilation, dropout):
            super().__init__()
            self.conv1 = CausalConv1d(c_in, c_out, kernel_size, dilation)
            self.conv2 = CausalConv1d(c_out, c_out, kernel_size, dilation)
            self.act = nn.ReLU()
            self.drop = nn.Dropout(dropout)
            self.skip = nn.Conv1d(c_in, c_out, 1) if c_in != c_out else nn.Identity()

        def forward(self, x):
            y = self.drop(self.act(self.conv1(x)))
            y = self.drop(self.act(self.conv2(y)))
            return self.act(y + self.skip(x))

    class TCNSpeedNet(nn.Module):
        """(B, 4, T) -> (B, 1) normalised forward speed."""

        def __init__(self, config: TCNConfig):
            super().__init__()
            blocks = []
            c_prev = CHANNELS_IN
            for c_out, dil in zip(config.channels, config.dilations):
                blocks.append(ResidualBlock(c_prev, c_out, config.kernel_size,
                                            dil, config.dropout))
                c_prev = c_out
            self.blocks = nn.Sequential(*blocks)
            # Global pooling makes the prediction depend on the whole 2 s window
            # even though a single conv stack spans fewer samples.
            self.pool = nn.AdaptiveAvgPool1d(1)
            self.head = nn.Sequential(
                nn.Linear(c_prev, config.head_units),
                nn.ReLU(),
                nn.Linear(config.head_units, 1),
            )

        def forward(self, x):
            h = self.blocks(x)
            h = self.pool(h).squeeze(-1)
            return self.head(h)

    return TCNSpeedNet(cfg)


# ------------------------------------------------------------------ NumPy path
def _causal_conv1d(x: np.ndarray, w: np.ndarray, b: np.ndarray, dilation: int) -> np.ndarray:
    """x: (C_in, T); w: (C_out, C_in, K) -> (C_out, T), left-padded (causal)."""
    _, _, k = w.shape
    pad = (k - 1) * dilation
    t = x.shape[1]
    xp = np.pad(x, ((0, 0), (pad, 0)))
    out = np.zeros((w.shape[0], t), dtype=np.float32)
    for i in range(k):
        out += w[:, :, i] @ xp[:, i * dilation:i * dilation + t]
    return out + b[:, None]


class NumpyTCN:
    """Inference-only NumPy mirror of :func:`_build_torch_model`."""

    def __init__(self, params: dict[str, np.ndarray], dilations: tuple[int, ...]):
        self.p = {k: np.asarray(v, dtype=np.float32) for k, v in params.items()}
        self.dilations = dilations
        self.n_blocks = len(dilations)

    def __call__(self, window: np.ndarray) -> float:
        h = np.ascontiguousarray(window.T.astype(np.float32))  # (C, T)
        for i, dil in enumerate(self.dilations):
            skip = h
            y = np.maximum(_causal_conv1d(h, self.p[f"b{i}.c1.w"], self.p[f"b{i}.c1.b"], dil), 0.0)
            y = np.maximum(_causal_conv1d(y, self.p[f"b{i}.c2.w"], self.p[f"b{i}.c2.b"], dil), 0.0)
            key = f"b{i}.skip.w"
            if key in self.p:
                skip = self.p[key][:, :, 0] @ h + self.p[f"b{i}.skip.b"][:, None]
            h = np.maximum(y + skip, 0.0)
        pooled = h.mean(axis=1)
        z = np.maximum(self.p["h0.w"] @ pooled + self.p["h0.b"], 0.0)
        return float(self.p["h1.w"] @ z + self.p["h1.b"])


def torch_state_to_numpy(state: dict, cfg: TCNConfig) -> dict[str, np.ndarray]:
    out: dict[str, np.ndarray] = {}
    for i in range(len(cfg.dilations)):
        out[f"b{i}.c1.w"] = state[f"blocks.{i}.conv1.weight"].numpy()
        out[f"b{i}.c1.b"] = state[f"blocks.{i}.conv1.bias"].numpy()
        out[f"b{i}.c2.w"] = state[f"blocks.{i}.conv2.weight"].numpy()
        out[f"b{i}.c2.b"] = state[f"blocks.{i}.conv2.bias"].numpy()
        if f"blocks.{i}.skip.weight" in state:
            out[f"b{i}.skip.w"] = state[f"blocks.{i}.skip.weight"].numpy()
            out[f"b{i}.skip.b"] = state[f"blocks.{i}.skip.bias"].numpy()
    out["h0.w"] = state["head.0.weight"].numpy()
    out["h0.b"] = state["head.0.bias"].numpy()
    out["h1.w"] = state["head.2.weight"].numpy()
    out["h1.b"] = state["head.2.bias"].numpy()
    return out


# ------------------------------------------------------------------- heuristic
class HeuristicSpeed:
    """Vibration-energy speed regressor with online GNSS calibration.

    Tyre/road excitation energy grows monotonically with speed, so a rolling RMS
    of the high-passed vertical acceleration is a usable speed proxy once its
    gain is calibrated. Recursive least squares fits ``v ~ a*e + b`` whenever
    GNSS Doppler speed is available; the fit is then held frozen through the
    outage. Forward acceleration supplies the short-term dynamics through a
    complementary filter, which prevents the proxy's lag from smearing braking
    and throttle transients.
    """

    def __init__(self, dt: float = 0.01, energy_window_s: float = 1.0,
                 hp_tau: float = 0.25, lp_tau: float = 0.5):
        self.dt = dt
        self.hp_alpha = dt / max(hp_tau, dt)
        self.lp_alpha = dt / max(lp_tau, dt)
        self.win = max(16, int(round(energy_window_s / dt)))
        self._energy: deque[float] = deque(maxlen=self.win)
        self._still: deque[bool] = deque(maxlen=max(8, int(round(0.8 / dt))))
        self._acc_lp = np.zeros(3)
        # RLS state for [gain, offset], seeded with a plausible prior.
        self.theta = np.array([18.0, 2.0])
        self.covar = np.diag([80.0, 20.0])
        self.forgetting = 0.999
        self.v_int = 0.0
        self.v_out = 0.0
        self.v_vib = 0.0
        self.calibrated = False
        self._n_fits = 0

    def reset(self, v0: float = 0.0) -> None:
        self.v_int = v0
        self.v_out = v0
        self.v_vib = v0
        self._energy.clear()
        self._still.clear()
        self._acc_lp = np.zeros(3)

    def calibrate(self, gnss_speed: float) -> None:
        """One RLS step against a trusted Doppler speed sample."""
        if len(self._energy) < self.win:
            return
        phi = np.array([self._feature(), 1.0])
        denom = self.forgetting + float(phi @ self.covar @ phi)
        gain = (self.covar @ phi) / denom
        self.theta = self.theta + gain * (gnss_speed - float(phi @ self.theta))
        self.covar = (self.covar - np.outer(gain, phi @ self.covar)) / self.forgetting
        self.theta[0] = float(np.clip(self.theta[0], 1.0, 400.0))
        self.theta[1] = float(np.clip(self.theta[1], -6.0, 12.0))
        self._n_fits += 1
        self.calibrated = self._n_fits > 15

    def _feature(self) -> float:
        e = np.asarray(self._energy)
        return float(np.sqrt(np.mean(e * e))) if e.size else 0.0

    def update(self, acc_dynamic: np.ndarray, yaw_rate: float, frozen: bool) -> float:
        acc = np.asarray(acc_dynamic, dtype=float)
        self._acc_lp += self.hp_alpha * (acc - self._acc_lp)
        hp = acc - self._acc_lp
        self._energy.append(float(np.linalg.norm(hp * np.array([0.5, 0.5, 1.0]))))

        a_fwd = float(acc[0])
        self._still.append(abs(a_fwd) < 0.25 and abs(yaw_rate) < 0.03
                           and self._feature() < 0.12)

        self.v_vib = float(np.clip(self.theta[0] * self._feature() + self.theta[1],
                                   0.0, 60.0))
        if not frozen:
            # Integrate for responsiveness, lean on the proxy to kill bias drift.
            self.v_int += a_fwd * self.dt + 0.55 * (self.v_vib - self.v_int) * self.dt
        if len(self._still) == self._still.maxlen and all(self._still):
            self.v_int = 0.0
        self.v_int = float(np.clip(self.v_int, 0.0, 60.0))
        self.v_out += self.lp_alpha * (self.v_int - self.v_out)
        return self.v_out


# ----------------------------------------------------------------- speed engine
class SpeedEngine:
    """Rolling-window speed estimator with automatic backend selection."""

    def __init__(self, dt: float = 0.01, cfg: TCNConfig | None = None,
                 prefer: str | None = None):
        self.dt = dt
        self.cfg = cfg or TCNConfig()
        self.buffer = np.zeros((self.cfg.window, CHANNELS_IN), dtype=np.float32)
        self.filled = 0
        self.backend = "heuristic"
        self._torch_model = None
        self._onnx = None
        self._numpy_model: NumpyTCN | None = None
        self.heuristic = HeuristicSpeed(dt=dt)
        self.v_hat = 0.0
        self.v_raw = 0.0
        self.frozen = False
        self.sigma = 1.2
        self.decimation = 5   # Evaluate TCN at 20 Hz (every 50 ms), hold speed in-between
        self._step_count = 0
        self._last_v_net: float | None = None
        self._load_backend(prefer)

    # ---------------------------------------------------------------- backends
    def _load_backend(self, prefer: str | None) -> None:
        order = [prefer] if prefer else ["torch", "onnx", "numpy"]
        for name in order:
            try:
                if name == "torch" and PT_PATH.exists():
                    import torch
                    torch.set_num_threads(1)
                    model = _build_torch_model(self.cfg)
                    model.load_state_dict(torch.load(PT_PATH, map_location="cpu"))
                    model.eval()
                    self._torch_model = model
                    self.backend = "torch"
                    return
                if name == "onnx" and ONNX_PATH.exists():
                    import onnxruntime as ort
                    self._onnx = ort.InferenceSession(str(ONNX_PATH),
                                                      providers=["CPUExecutionProvider"])
                    self.backend = "onnx"
                    return
                if name == "numpy" and NPZ_PATH.exists():
                    data = np.load(NPZ_PATH)
                    self._numpy_model = NumpyTCN({k: data[k] for k in data.files},
                                                 self.cfg.dilations)
                    self.backend = "numpy"
                    return
            except Exception:
                continue
        self.backend = "heuristic"

    def reset(self, v0: float = 0.0) -> None:
        self.buffer[:] = 0.0
        self.filled = 0
        self.v_hat = v0
        self.v_raw = v0
        self.heuristic.reset(v0)
        self._step_count = 0
        self._last_v_net = v0

    # -------------------------------------------------------------------- step
    def calibrate(self, gnss_speed: float) -> None:
        """Forward a trusted GNSS Doppler speed to the fallback regressor."""
        self.heuristic.calibrate(float(gnss_speed))

    def update(self, acc_vehicle_dynamic: np.ndarray, yaw_rate: float,
               shock: bool) -> dict:
        sample = np.array([acc_vehicle_dynamic[0], acc_vehicle_dynamic[1],
                           acc_vehicle_dynamic[2], yaw_rate], dtype=np.float32)
        self.buffer = np.roll(self.buffer, -1, axis=0)
        self.buffer[-1] = sample
        self.filled = min(self.filled + 1, self.cfg.window)
        self.frozen = shock
        self._step_count += 1

        v_heur = self.heuristic.update(acc_vehicle_dynamic, float(yaw_rate), shock)
        v_net = None
        if self.backend != "heuristic" and self.filled >= self.cfg.window:
            if self._last_v_net is None or self._step_count % self.decimation == 0:
                self._last_v_net = self._infer()
            v_net = self._last_v_net

        if v_net is not None:
            self.v_raw = v_net
            self.sigma = 0.55
        else:
            self.v_raw = v_heur
            self.sigma = 1.1 if self.heuristic.calibrated else 2.5

        if shock:
            # Hold the last accepted speed through the shock.
            self.sigma = max(self.sigma, 3.0)
        else:
            self.v_hat = self.v_raw
        return {
            "v_hat": float(self.v_hat),
            "v_raw": float(self.v_raw),
            "v_heuristic": float(v_heur),
            "sigma": float(self.sigma),
            "backend": self.backend,
            "frozen": shock,
        }

    def _infer(self) -> float | None:
        x = (self.buffer - INPUT_MEAN) / INPUT_SCALE
        try:
            if self._torch_model is not None:
                import torch
                with torch.no_grad():
                    t = torch.from_numpy(x.T[None, ...].copy())
                    out = float(self._torch_model(t).item())
            elif self._onnx is not None:
                inp = {self._onnx.get_inputs()[0].name: x.T[None, ...].astype(np.float32)}
                out = float(self._onnx.run(None, inp)[0].ravel()[0])
            elif self._numpy_model is not None:
                out = self._numpy_model(x)
            else:
                return None
        except Exception:
            self.backend = "heuristic"
            return None
        return float(np.clip(out * SPEED_SCALE, 0.0, 60.0))


# -------------------------------------------------------------- training / export
def build_dataset(n_runs: int = 6, seeds: tuple[int, ...] | None = None):
    """Generate aligned IMU windows and matching ground-truth speeds."""
    from ..sensors.cabin_alignment import CabinAligner
    from ..sensors.generator import SensorSimulator, SimConfig

    seeds = seeds or tuple(1000 + 37 * i for i in range(n_runs))
    windows: list[np.ndarray] = []
    targets: list[float] = []
    for k, seed in enumerate(seeds):
        mount = (float(np.random.default_rng(seed).uniform(-25, 25)),
                 float(np.random.default_rng(seed + 1).uniform(-45, 45)),
                 float(np.random.default_rng(seed + 2).uniform(-180, 180)))
        sim = SensorSimulator(SimConfig(seed=seed, mount_euler_deg=mount,
                                        enable_potholes=(k % 2 == 0)))
        aligner = CabinAligner(dt=sim.cfg.dt)
        buf = np.zeros((WINDOW, CHANNELS_IN), dtype=np.float32)
        filled = 0
        while not sim.finished:
            pkt = sim.step()
            al = aligner.update(pkt["imu_acc"], pkt["imu_gyro"])
            ad = al["acc_dynamic"]
            buf = np.roll(buf, -1, axis=0)
            buf[-1] = [ad[0], ad[1], ad[2], al["gyro_vehicle"][2]]
            filled += 1
            if filled >= WINDOW and filled % 5 == 0:
                windows.append(buf.copy())
                targets.append(pkt["true_speed"])
    x = (np.asarray(windows, dtype=np.float32) - INPUT_MEAN) / INPUT_SCALE
    y = np.asarray(targets, dtype=np.float32)[:, None] / SPEED_SCALE
    return np.transpose(x, (0, 2, 1)), y


def train(epochs: int = 14, batch_size: int = 128, lr: float = 2e-3,
          n_runs: int = 6) -> None:
    import torch
    from torch import nn

    cfg = TCNConfig()
    x, y = build_dataset(n_runs=n_runs)
    n_val = max(1, int(0.15 * len(x)))
    perm = np.random.default_rng(0).permutation(len(x))
    val, trn = perm[:n_val], perm[n_val:]
    xt = torch.from_numpy(x[trn])
    yt = torch.from_numpy(y[trn])
    xv = torch.from_numpy(x[val])
    yv = torch.from_numpy(y[val])

    model = _build_torch_model(cfg)
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)
    loss_fn = nn.SmoothL1Loss(beta=0.05)

    for epoch in range(epochs):
        model.train()
        order = torch.randperm(len(xt))
        running = 0.0
        for i in range(0, len(order), batch_size):
            idx = order[i:i + batch_size]
            opt.zero_grad()
            loss = loss_fn(model(xt[idx]), yt[idx])
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            running += float(loss) * len(idx)
        sched.step()
        model.eval()
        with torch.no_grad():
            rmse = float(torch.sqrt(torch.mean((model(xv) - yv) ** 2))) * SPEED_SCALE
        print(f"epoch {epoch + 1:2d}/{epochs}  train={running / len(order):.5f}  "
              f"val_rmse={rmse:.3f} m/s")

    WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), PT_PATH)
    state = {k: v.detach().cpu() for k, v in model.state_dict().items()}
    np.savez(NPZ_PATH, **torch_state_to_numpy(state, cfg))
    export_onnx(model, cfg)
    print(f"saved {PT_PATH.name}, {NPZ_PATH.name}, {ONNX_PATH.name}")


def export_onnx(model=None, cfg: TCNConfig | None = None) -> Path:
    import torch

    cfg = cfg or TCNConfig()
    if model is None:
        model = _build_torch_model(cfg)
        if PT_PATH.exists():
            model.load_state_dict(torch.load(PT_PATH, map_location="cpu"))
    model.eval()
    WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
    dummy = torch.zeros(1, CHANNELS_IN, cfg.window)
    torch.onnx.export(model, dummy, str(ONNX_PATH), input_names=["imu_window"],
                      output_names=["speed_norm"], opset_version=17,
                      dynamic_axes={"imu_window": {0: "batch"},
                                    "speed_norm": {0: "batch"}})
    return ONNX_PATH


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="TCN speed engine utilities")
    parser.add_argument("--train", action="store_true", help="fit and export weights")
    parser.add_argument("--export-onnx", action="store_true")
    parser.add_argument("--epochs", type=int, default=14)
    parser.add_argument("--runs", type=int, default=6)
    args = parser.parse_args()
    if args.train:
        train(epochs=args.epochs, n_runs=args.runs)
    elif args.export_onnx:
        print(export_onnx())
    else:
        parser.print_help()
