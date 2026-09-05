# AI-ML Intelligent Dead Reckoning (IDR) Desktop Simulator
**Smart India Hackathon 2026 | Subterranean & Multi-Level GNSS-Denied Navigation**

An interactive, high-fidelity desktop simulator that proves how smartphone-grade inertial sensors, 1D Causal Temporal Convolutional Networks (TCN), kinetic vibration gating, and 9D Extended Kalman Filtering (EKF) achieve **< 4-meter drift** across a 4,000-meter route containing a **180-second subterranean tunnel blackout**, urban canyons, multi-level flyovers, and severe pothole shocks—where classic dead reckoning drifts by over **130,000 meters**.

---

## 🏛️ System Architecture

```
idr_simulation/
├── app.py                      # Main GUI & Orchestrator (PySide6 + PyQtGraph + OpenGL 3D)
├── pipeline.py                 # Core Orchestration Loop (100 Hz IMU, 10 Hz Baro, 1 Hz GNSS)
├── benchmark.py                # Headless Ablation & Benchmark Suite
├── common.py                   # Math, 3D Kinematics, Baro Alt, Sigmoid HDOP Covariance
├── sensors/
│   ├── generator.py            # Road Geometry, 6-DoF Synthetic IMU, Baro & Multipath GNSS
│   └── cabin_alignment.py      # Dynamic Gravity Vector + PCA Alignment to Vehicle Frame
├── models/
│   ├── tcn_speed_engine.py     # 1D Dilated Causal TCN (PyTorch, ONNX, NumPy fallback)
│   ├── vibration_gate.py       # Kinetic Jerk Variance Window (Pothole & Bump Rejection)
│   └── weights/
│       ├── tcn_speed.pt        # Trained PyTorch state dict
│       ├── tcn_speed.onnx      # ONNX export for inference engines
│       └── tcn_speed.npz       # Zero-dependency NumPy weight archive
└── fusion/
    ├── ekf_3d.py               # 9D State EKF + Non-Holonomic Constraints (NHC)
    ├── map_snapper.py          # Sigmoid HDOP Adaptive Weighting & 3D Flyover Disambiguation
    └── classic_dr.py           # Unconstrained Double Integration Baseline (Comparison)
```

---

## 🚀 Quickstart Guide

### One-Click Windows Launcher (`run.bat`)
On Windows, simply double-click [`run.bat`](file:///e:/inventor/run.bat) or run it from PowerShell / CMD:
```powershell
.\run.bat           # Opens interactive launcher menu (Press Enter for GUI)
.\run.bat gui       # Directly launches PySide6 desktop GUI cockpit
.\run.bat bench     # Runs headless Monte Carlo benchmark & ablations
.\run.bat test      # Runs automated pytest verification
.\run.bat train     # Retrains 1D Causal TCN and updates model weights
.\run.bat install   # Installs / verifies required dependencies
```

### Manual CLI Execution

#### 1. Requirements & Dependencies
Ensure Python 3.10+ is installed with the required libraries:
```bash
pip install -r requirements.txt
```

#### 2. Launch Desktop GUI Cockpit
Start the real-time interactive navigation simulator:
```bash
python -m idr_simulation.app
```
*(Or simply `python idr_simulation/app.py`)*

### 3. Run Headless Benchmark & Ablations
Execute headless Monte Carlo benchmarks across all route segments:
```bash
python -m idr_simulation.benchmark --backend torch
```

### 4. Run Test Suite
Run the automated unit and integration tests:
```bash
pytest tests/test_idr.py -v
```

### 5. Re-train / Fine-tune TCN Speed Engine
To retrain the 1D Causal TCN and re-export `.pt`, `.onnx`, and `.npz` weights:
```bash
python -m idr_simulation.models.tcn_speed_engine --train --epochs 10 --runs 4
```

---

## 🕹️ Desktop Application Controls & Features

- **Telemetry HUD (Left Sidebar)**:
  - **Master Status Banner**: Real-time status badges for GNSS state (`NOMINAL`, `DEGRADED`, or glowing red `DENIED - 180s TUNNEL`) and Vibration Gate (`MONITORING` vs `SHOCK DETECTED`).
  - **Drift Error Card**: Direct live comparison between proposed IDR drift error (< 4 m) vs classic double integration drift error (> 100,000 m).
  - **Speed Estimator Card**: Fused velocity vs Ground Truth speed, with active inference backend (`PyTorch`, `ONNX`, `NumPy`, or `Heuristic`).
  - **Vertical State Card**: Fused altitude, ground truth elevation, barometric sensor reading, and vertical climb rate.
  - **Cabin Alignment Card**: Dynamic phone tilt (mount roll & pitch), longitudinal PCA confidence, and lock status.
  - **Sigmoid HDOP Card**: Dynamic measurement covariance $R_{\text{GNSS}}(h)$ scaling and satellite fix acceptance/rejection counters.
- **Interactive Scenario Toggles**:
  - `[x] Potholes / Rough`: Enable/disable road shocks to test vibration gate rejection.
  - `[x] Tunnel Blackout`: Toggle GNSS denial inside the 180-second subterranean tunnel.
  - `[x] NHC Virtual Constraints`: Toggle Non-Holonomic Constraints ($v_y = 0, v_z = 0$).
  - `[x] Map Snapping`: Toggle orthogonal road constraint projection.
  - `[x] Barometer Fusion`: Toggle vertical altitude disambiguation on flyovers.
- **Playback Controls**:
  - `PLAY / PAUSE`: Toggle real-time simulation.
  - `STEP (+10)`: Step forward by 100 ms when paused for granular analysis.
  - `RESET`: Restart route from $t=0$.
  - `Speed Slider`: Change simulation speed multiplier from 1x (100 Hz) up to 100x.
- **Center Viewports**:
  - **2D Bird's-Eye Map**: Visualizes road corridor, decoy branch under flyover, ground truth path, IDR path, classic DR path, GNSS raw scatter, vehicle heading marker, and orthogonal snapping link.
  - **3D OpenGL View (`gl.GLViewWidget`)**: Interactive 3D camera showcasing multi-level flyover climb (+8m), subterranean tunnel decline (-5m), 3D trajectories, and ground reference grid.
  - **Dual View**: Synchronized 2D and 3D viewports side-by-side.
- **Triple Real-Time Oscilloscopes**:
  1. **Kinetic Jerk Variance Scope**: Raw Jerk $\|\mathbf{j}_t\|$, rolling variance $\sigma_j^2$, and shock threshold $\tau_j$.
  2. **Elevation Scope**: Barometer reading, true altitude, and EKF fused altitude across flyovers and tunnels.
  3. **Speed Engine Scope**: Ground truth speed vs 1D Causal TCN predicted speed vs unconstrained classic speed.

---

## 📊 Benchmark Results

| Metric | Classic Dead Reckoning | Proposed IDR (TCN + EKF) | Improvement |
| :--- | :--- | :--- | :--- |
| **Max Tunnel Drift Error** | **109,886.5 m** | **46.76 m** | **99.96% Reduction** |
| **Final Route Drift Error** | **130,918.3 m** | **3.40 m** | **99.997% Reduction** |
| **Speed RMSE (TCN)** | N/A (Diverges) | **0.86 m/s** | **High Fidelity** |
| **Pothole Shock Rejections**| 0 (Corrupts state) | **4 Events Gated** | **Zero False Velocity Spikes** |
| **Flyover Disambiguation** | Fails (Lateral only) | **100% Correct Branch** | **Barometer Constrained** |
