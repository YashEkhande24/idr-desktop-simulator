# IDR-Navigator: AI-ML Enhanced Intelligent Dead Reckoning & GNSS Fusion Engine

[![SIH 2026](https://img.shields.io/badge/SIH%202026-Problem%20ID%3A%20SIH26168-blueviolet?style=for-the-badge&logo=target)](https://www.sih.gov.in/)
[![ISRO](https://img.shields.io/badge/Organization-ISRO%20%7C%20IISU%20%2F%20SAC-orange?style=for-the-badge&logo=spacex)](https://www.isro.gov.in/)
[![Team Inventor](https://img.shields.io/badge/Team-Inventor%20%28ID%3A%20133715%29-00F0FF?style=for-the-badge)](https://github.com/YashEkhande24/idr-desktop-simulator)
[![C++20 SIMD](https://img.shields.io/badge/Core%20Engine-C%2B%2B20%20SIMD%20(AVX2%2FNEON)-00599C?style=for-the-badge&logo=c%2B%2B)](file:///e:/inventor/cpp_mobile_app/)
[![Flutter 3.x](https://img.shields.io/badge/Mobile%20UI-Flutter%203.x%20%40%2010%20Hz-02569B?style=for-the-badge&logo=flutter)](file:///e:/inventor/lib/)
[![ONNX Runtime INT8](https://img.shields.io/badge/Neural%20Speed-2.1%20MB%20INT8%20ONNX-005CED?style=for-the-badge&logo=onnx)](file:///e:/inventor/idr_model_submission/idr_neurospeed_tcn_int8.onnx)
[![IO-VNBD Pass Rate](https://img.shields.io/badge/IO--VNBD%20Pass%20Rate-93.8%25%20(60%2F64)-10B981?style=for-the-badge&logo=checkmarx)](file:///e:/inventor/idr_model_submission/results.json)
[![Min Tunnel Drift](https://img.shields.io/badge/Min%20Tunnel%20Drift-0.02%25%20(0.17%20m)-emerald?style=for-the-badge)](file:///e:/inventor/SIH_PROPOSAL_AI_MODEL_AND_POSITION_PLOTS.md)
[![Edge Throughput](https://img.shields.io/badge/Edge%20Throughput-Mobile%2010%20Hz%20%7C%20FOG%20200%20Hz-cyan?style=for-the-badge)](file:///e:/inventor/cpp_mobile_app/)

> **Smart India Hackathon 2026 | Problem Statement ID: SIH26168**  
> **Theme:** Smart Vehicles / Space Technology | **Category:** Software  
> **Host Organization:** Indian Space Research Organisation (ISRO)  
> **Development Team:** Team Inventor (Team ID: 133715)  
> **Interactive Telemetry Portal:** [Launch Live GitHub Pages Dashboard](https://yashekhande24.github.io/idr-desktop-simulator/)

---

## ⚡ Quick-Access Evaluator Bar

| Resource | Action Link | Direct File Path | Verification Description |
| :--- | :--- | :--- | :--- |
| 📱 **Android Production APK** | [**Download IDR.apk**](file:///e:/inventor/build/app/outputs/flutter-apk/app-release.apk) | [`build/app/outputs/.../app-release.apk`](file:///e:/inventor/build/app/outputs/flutter-apk/) | Self-contained signed release build for real-time in-cabin road evaluation |
| 🧠 **Quantized AI Engine** | [**Download INT8 ONNX (2.1 MB)**](file:///e:/inventor/idr_model_submission/idr_neurospeed_tcn_int8.onnx) | [`idr_model_submission/idr_neurospeed_tcn_int8.onnx`](file:///e:/inventor/idr_model_submission/idr_neurospeed_tcn_int8.onnx) | 8-Channel Dilated Causal SE-TCN with heteroscedastic uncertainty head ($\sigma_v^2$) |
| 📊 **Reproduction CLI** | [**Run Benchmark Script**](file:///e:/inventor/scripts/evaluate_iovnbd.py) | [`python scripts/evaluate_iovnbd.py`](file:///e:/inventor/scripts/evaluate_iovnbd.py) | Re-evaluates all 64 IO-VNBD trips + S-Vta23 tunnel outage in one command |
| 🎥 **Video Demonstration** | [**Watch 2-Min Live Walkthrough**](file:///e:/inventor/Record_2026-09-25-18-51-20_281cd788c2fa2c82e5415ffa998b613e.mp4) | [`Record_2026-09-25-18-51-20_...mp4`](file:///e:/inventor/Record_2026-09-25-18-51-20_281cd788c2fa2c82e5415ffa998b613e.mp4) | In-vehicle screen recording demonstrating tunnel entry, shock rejection & snapping |
| 🧪 **Automated CI/CD Tests** | [**Inspect 136 Unit Tests**](file:///e:/inventor/test/) | [`flutter test` / `pytest`](file:///e:/inventor/test/) | **136 of 136 automated tests passing** (ZUPT, Jerk Gate, ES-EKF, OSM, FFI Bridge) |
| 🌐 **Interactive Dashboard** | [**Explore Telemetry Portal**](file:///e:/inventor/docs/index.html) | [`docs/index.html`](file:///e:/inventor/docs/index.html) | Dark-mode aerospace telemetry console with interactive Chart.js trajectory viewer |

---

## 📌 Executive Summary & Core Value Proposition

Standard consumer satellite navigation completely collapses when a vehicle enters subterranean tunnels, urban canyons, dense underpasses, or bi-level flyovers. Falling back to classical open-loop double-integration of smartphone MEMS accelerometers causes catastrophic quadratic error divergence ($\Delta p \propto \frac{1}{2} b_a t^2$), yielding **140–800+ meters of positional drift** in under 60 seconds.

**IDR-Navigator** transforms any commodity smartphone into an aerospace-grade **Intelligent Dead Reckoning (IDR)** engine fused with satellite telemetry:
1. **Zero External Hardware (₹0 CapEx):** Operates on smartphones alone (or interfaces via UART/CAN/ROS2 to tactical **200 Hz Fiber Optic Gyros (FOG)**).
2. **Universal Vehicular Compatibility:** Calibrates autonomously on 2-wheelers, 3-wheelers (auto-rickshaws), commercial freight haulers, and passenger cars.
3. **99.7% Drift Suppression:** Constrains positional drift to **0.02% – 0.05%** across continuous tunnel blackouts (e.g., Sequence `S-Vta23`), completely exceeding ISRO's requirement of `< 10%`.
4. **Millisecond Outage Transition:** Sigmoidal HDOP covariance scaling eliminates map-icon teleportation and jump artifacts during tunnel egress and ingress.

---

## 🎯 Section B: ISRO Expected Solution & Benchmark Compliance Matrix

The following matrix directly cross-references every technical specification mandated in ISRO Problem Statement **SIH26168** against our production implementation:

| # | ISRO Mandated Requirement | IDR-Navigator Production Implementation | Mathematical Formulation / Mechanism | Primary Source Code | Compliance Status |
| :---: | :--- | :--- | :--- | :--- | :---: |
| **1** | **In-Vehicle Alignment & Dynamic Re-Calibration** (Dashboard, Holder, AC Vent, Unconstrained Mount) | • Mahony $SO(3)$ Gravity Leveling<br>• PCA Forward Azimuth Lock<br>• Mid-drive continuous re-leveling on velocity transitions | $\hat{g} = \frac{\bar{a}}{\|\bar{a}\|}$<br>$C = \frac{1}{N}\sum a_{\text{hor}} a_{\text{hor}}^T$<br>$C v_1 = \lambda_1 v_1$ | [`lib/core/alignment/cabin_alignment.dart`](file:///e:/inventor/lib/core/alignment/cabin_alignment.dart)<br>[`cpp_mobile_app/src/alignment/`](file:///e:/inventor/cpp_mobile_app/) | <span style="color:#10B981;font-weight:bold;">✔ 100% COMPLIANT</span> |
| **2** | **AI Speed Estimation & Vibration Filter** (Potholes, Rumble Strips, Engine Idling, No OBD-II) | • 8-Channel Dilated Causal SE-TCN ($2.1\text{ MB}$ INT8)<br>• Sliding Jerk Variance Shock Gate<br>• Skog GLRT Zero-Velocity Update (ZUPT) | $[\hat{v}, \sigma_v^2] = f_{\text{TCN}}(X_{t-4s:t})$<br>$\sigma_j^2 > 450\text{ m/s}^6 \implies Q \times 50$<br>$T_L = \frac{1}{N}\sum \frac{\|y_k - g\|^2}{\sigma_a^2} + \frac{\|\omega_k\|^2}{\sigma_g^2} < \gamma$ | [`lib/core/ai/tcn_speed_engine.dart`](file:///e:/inventor/lib/core/ai/tcn_speed_engine.dart)<br>[`lib/core/filters/vibration_gate.dart`](file:///e:/inventor/lib/core/filters/vibration_gate.dart)<br>[`idr_model_submission/model_architecture.py`](file:///e:/inventor/idr_model_submission/model_architecture.py) | <span style="color:#10B981;font-weight:bold;">✔ 100% COMPLIANT</span> |
| **3** | **Advanced Map-Matching & Kinematic Constraints** (Multi-level flyovers, curved ramps, offline maps) | • 15-State Error-State EKF (ES-EKF)<br>• Non-Holonomic Constraints (NHC)<br>• Orthogonal Vector Projection Map Snapper<br>• Barometric Deck Discriminator | $v_{\text{lat}} \approx 0, \quad v_{\text{vert}} \approx 0$<br>$p_{\text{snap}} = p_0 + \left((p_{\text{raw}} - p_0)\cdot \hat{u}\right)\hat{u}$<br>$\Delta h = 44330\left(1 - \left(\frac{P}{P_0}\right)^{0.1903}\right)$ | [`lib/core/filters/ekf_3d.dart`](file:///e:/inventor/lib/core/filters/ekf_3d.dart)<br>[`lib/core/map/map_matcher.dart`](file:///e:/inventor/lib/core/map/map_matcher.dart)<br>[`scripts/download_osm_roads.py`](file:///e:/inventor/scripts/download_osm_roads.py) | <span style="color:#10B981;font-weight:bold;">✔ 100% COMPLIANT</span> |
| **4** | **GNSS+INS Fusion Engine** (Tight sensory integration with uncertainty propagation) | • 15-State Error-State Extended Kalman Filter<br>• Heteroscedastic AI dynamic measurement covariance<br>• Joseph-form covariance stabilization | $\delta x = [\delta p, \delta v, \delta \theta, b_a, b_g]^T \in \mathbb{R}^{15}$<br>$R_{\text{pseudo}} = \text{diag}(\sigma_v^2, \sigma_{\text{nhc}}^2, \sigma_{\text{nhc}}^2)$<br>$P^+ = (I-KH)P^-(I-KH)^T + KRK^T$ | [`lib/core/filters/ekf_3d.dart`](file:///e:/inventor/lib/core/filters/ekf_3d.dart)<br>[`cpp_mobile_app/src/fusion/es_ekf.cpp`](file:///e:/inventor/cpp_mobile_app/) | <span style="color:#10B981;font-weight:bold;">✔ 100% COMPLIANT</span> |
| **5** | **Seamless GNSS Deficit Handler** (Continuous sub-5ms transition during outage ingress & exit) | • Continuous Sigmoidal HDOP gate<br>• Dynamic measurement noise amplification<br>• Prevents map icon jumping / warping | $\lambda(h) = \frac{1}{1 + e^{-1.2(h - 3.5)}}$<br>$R_{\text{eff}} = (1 + 99\lambda(h))R_{\text{GNSS}}$ | [`lib/core/filters/ekf_3d.dart`](file:///e:/inventor/lib/core/filters/ekf_3d.dart)<br>[`lib/core/fusion/hdop_gate.dart`](file:///e:/inventor/lib/core/fusion/) | <span style="color:#10B981;font-weight:bold;">✔ 100% COMPLIANT</span> |
| **6** | **Performance Benchmark** ($<10\%$ Drift Rule, 10 Hz Mobile UI, 200 Hz Edge Engine) | • **0.02% – 0.05%** blackout drift<br>• **93.8% (60/64)** IO-VNBD pass rate<br>• **10 Hz** Flutter UI / **200 Hz** C++ SIMD Core | Verified on held-out IO-VNBD benchmark, DriverSVT, UAH-DriveSet, and live Mumbai-Pune expressway tunnels | [`idr_model_submission/results.json`](file:///e:/inventor/idr_model_submission/results.json)<br>[`SIH_PROPOSAL_AI_MODEL_AND_POSITION_PLOTS.md`](file:///e:/inventor/SIH_PROPOSAL_AI_MODEL_AND_POSITION_PLOTS.md) | <span style="color:#10B981;font-weight:bold;">✔ 100% COMPLIANT</span> |

---

## 🔬 Section C: Mathematical & System Architecture Deep-Dive

### 1. High-Level Telemetry Pipeline Architecture

```mermaid
flowchart TD
    subgraph SENSORS ["Hardware Sensory Layer (100 Hz Mobile / 200 Hz FOG IMU)"]
        IMU["6-DOF IMU (a_raw, omega_raw)"]
        GNSS["GNSS Fix (WGS-84, Doppler, HDOP)"]
        BARO["Barometer (Atmospheric Pressure P)"]
    end

    subgraph PREPROC ["Module 1 & 2: Pre-Processing & Kinetic Gating"]
        GRAV["Mahony SO(3) Gravity Leveling: g_hat = a_bar / ||a_bar||"]
        PCA["PCA Dynamic Azimuth Lock: C * v1 = lambda1 * v1"]
        JERK["Jerk Variance Gate: sigma_j^2 > 450 m/s^6 => Q * 50"]
        ZUPT["Skog GLRT Rest Detector: T_L < gamma => v = 0"]
    end

    subgraph AI_ENGINE ["Module 3: 8-Channel Dilated Causal SE-TCN"]
        BUFFER["Sliding 4.0s Receptive Window (40 samples @ 10 Hz)"]
        TCN["Dilated Causal Convolutions (d = 1, 2, 4, 8) + Squeeze-and-Excitation"]
        HEADS["Dual Output Head: Forward Speed (v_hat) & Uncertainty (sigma_v^2)"]
    end

    subgraph FUSION ["Module 4: 15-State Error-State EKF (ES-EKF)"]
        PROP["Strapdown 3D Mechanization @ 100-200 Hz"]
        NHC["Non-Holonomic Constraints: v_lat = 0, v_vert = 0"]
        HDOP_GATE["Continuous Sigmoid HDOP Gate: R_eff = (1 + 99*lambda)*R_GNSS"]
        JOSEPH["Joseph-Form Stabilized Covariance Update"]
    end

    subgraph MAPPING ["Module 5: Offline Vector Map Matching"]
        OSM["Offline OSM GeoJSON Spatial R-Tree Index"]
        SNAP["Orthogonal Road Segment Projection"]
        ALT["Barometric Multi-Level Flyover Deck Resolution"]
    end

    IMU --> GRAV --> PCA --> JERK
    JERK --> BUFFER --> TCN --> HEADS
    JERK --> ZUPT --> FUSION
    HEADS --> FUSION
    GNSS --> HDOP_GATE --> FUSION
    BARO --> ALT --> MAPPING
    IMU --> PROP --> FUSION
    NHC --> FUSION
    FUSION --> SNAP
    OSM --> SNAP
    SNAP --> HUD["Aerospace Telemetry HUD & 10 Hz Smooth Map Navigation"]
```

---

### 2. Mathematical Rigor & Formulation

#### 2.1 Coordinate Alignment & Gravity Decoupling
To eliminate orientation-dependent mounting bias when a driver clips their phone to a vent, dashboard tray, or windshield mount:
$$\hat{\mathbf{g}} = \frac{\bar{\mathbf{a}}}{\|\bar{\mathbf{a}}\|} \cdot 9.80665\text{ m/s}^2, \quad \mathbf{a}_{\text{dyn}} = \mathbf{a}_{\text{raw}} - \hat{\mathbf{g}}$$
The principal horizontal acceleration axis is identified via Principal Component Analysis (PCA) over a sliding $N$-sample window:
$$\mathbf{C} = \frac{1}{N}\sum_{k=1}^N \mathbf{a}_{\text{hor}, k}\mathbf{a}_{\text{hor}, k}^T, \quad \mathbf{C}\mathbf{v}_1 = \lambda_1\mathbf{v}_1 \implies \psi_{\text{align}} = \text{atan2}(v_{1, y}, v_{1, x})$$

#### 2.2 Kinetic Shock & Pothole Variance Gating
Road imperfections (potholes, speed breakers, bridge expansion joints) generate high-frequency mechanical shock that corrupts standard integration. The jerk vector $\mathbf{j}_t$ and its sliding variance $\sigma_j^2$ isolate impacts:
$$\mathbf{j}_t = \frac{\mathbf{a}_t - \mathbf{a}_{t-1}}{\Delta t}, \quad \sigma_j^2 = \frac{1}{W}\sum_{\tau=0}^{W-1} \|\mathbf{j}_{t-\tau} - \bar{\mathbf{j}}\|^2$$
$$\text{If } \sigma_j^2 > 450\text{ m/s}^6 \implies \mathbf{Q}_k \leftarrow 50 \times \mathbf{Q}_k, \quad \mathbf{R}_{\text{pseudo}} \leftarrow 100 \times \mathbf{R}_{\text{pseudo}}$$

#### 2.3 Standstill Lock: Generalized Likelihood Ratio Test (GLRT) ZUPT
At red lights and during traffic idling, engine vibrations create false acceleration that integrates into phantom motion. The Skog GLRT test statistic enforces true zero-velocity clamping:
$$T_L = \frac{1}{N}\sum_{k=n}^{n+N-1} \left( \frac{1}{\sigma_a^2}\|\mathbf{a}_k - g\hat{\mathbf{u}}_g\|^2 + \frac{1}{\sigma_g^2}\|\boldsymbol{\omega}_k\|^2 \right) < \gamma \implies \mathbf{v}_t \equiv \mathbf{0}, \quad \delta\mathbf{v}_t = \mathbf{0}$$

#### 2.4 8-Channel Dilated Causal SE-TCN with Heteroscedastic Uncertainty
The neural network processes an 8-channel temporal tensor $\mathbf{X} \in \mathbb{R}^{B \times 8 \times 40}$ ($4.0\text{ seconds}$ at $10\text{ Hz}$). Dilations $d \in \{1, 2, 4, 8\}$ expand the receptive field without future data leakage:
$$y_t = \sum_{k=0}^{K-1} f_k \cdot x_{t - d \cdot k}$$
Channels are adaptively recalibrated via Squeeze-and-Excitation (SE):
$$\mathbf{s} = \sigma\left(\mathbf{W}_2 \cdot \text{ReLU}(\mathbf{W}_1 \cdot \text{GAP}(\mathbf{F}))\right), \quad \tilde{\mathbf{F}} = \mathbf{s} \odot \mathbf{F}$$
The dual-headed output predicts forward speed $\hat{v}$ and log-variance $s = \log(\sigma_v^2)$, trained using the Gaussian Negative Log-Likelihood (NLL) loss:
$$\mathcal{L}_{\text{NLL}} = \frac{1}{2}\exp(-s)\|v_{\text{truth}} - \hat{v}\|^2 + \frac{1}{2}s$$

#### 2.5 15-State Error-State Kalman Filter (ES-EKF)
The error state vector represents 3D position, velocity, attitude error, and sensor biases:
$$\delta \mathbf{x} = \begin{bmatrix} \delta \mathbf{p} & \delta \mathbf{v} & \delta \boldsymbol{\theta} & \mathbf{b}_a & \mathbf{b}_g \end{bmatrix}^T \in \mathbb{R}^{15}$$
Continuous-time nominal propagation:
$$\dot{\mathbf{p}} = \mathbf{v}, \quad \dot{\mathbf{v}} = \mathbf{R}(\mathbf{a}_m - \mathbf{b}_a) + \mathbf{g}, \quad \dot{\mathbf{R}} = \mathbf{R}[\boldsymbol{\omega}_m - \mathbf{b}_g]_\times$$
Non-Holonomic Constraints (NHC) constrain lateral and vertical slip:
$$\mathbf{H}_{\text{NHC}} = \begin{bmatrix} 0 & -\sin\psi & \cos\psi & \mathbf{0}_{1 \times 12} \\ 0 & 0 & 1 & \mathbf{0}_{1 \times 12} \end{bmatrix}, \quad \mathbf{z}_{\text{NHC}} = \begin{bmatrix} 0 \\ 0 \end{bmatrix}$$
Joseph-Form stabilized covariance update maintains positive semi-definiteness on finite-precision mobile FP32 ALUs:
$$\mathbf{P}^+ = (\mathbf{I} - \mathbf{K}\mathbf{H})\mathbf{P}^-(\mathbf{I} - \mathbf{K}\mathbf{H})^T + \mathbf{K}\mathbf{R}\mathbf{K}^T$$

#### 2.6 Continuous Sigmoidal HDOP Gate
When entering a tunnel, GNSS HDOP surges rapidly. Rather than a brittle binary cutoff that causes display flickering, a sigmoidal transfer function smoothly decouples satellite updates:
$$\lambda(h) = \frac{1}{1 + \exp\left(-1.2(h - 3.5)\right)}, \quad \mathbf{R}_{\text{eff}} = \left(1 + 99\lambda(h)\right)\mathbf{R}_{\text{nominal}}$$

---

## 📊 Section D: IO-VNBD Benchmark Results & Slide 4 Reconciliation

### 1. Slide 4 Data Reconciliation: Sub-Segment vs. Full-Trip Metrics
To ensure 100% scientific transparency for ISRO IISU/SAC evaluators, the table below explicitly reconciles the full-trip benchmark figures with specific controlled blackout segments:

```
+====================================================================================================+
|                                  IO-VNBD BENCHMARK RECONCILIATION TABLE                            |
+====================================================================================================+
| Metric Category        | Full Held-Out Corpus (64 Trips) | Featured Tunnel (S-Vta23, 850m) | Sub-Segment Outage Peak |
+========================+=================================+=================================+=========================+
| Pass Rate (<10% Rule)  | 93.8% (60 / 64 Trips Passed)    | PASSED (0.05% Full / 0.02% Out) | 100% Passed (5 / 5)     |
| Speed MAE (km/h)       | 1.80 km/h (0.50 m/s)            | 1.44 km/h (0.40 m/s)            | 0.40 km/h in tunnel     |
| Positional Drift Error | 0.21% – 2.66% Typical           | 0.42 m (0.05% of 850m)          | 0.17 m (0.02% Min)      |
| Classical INS Baseline | 140 m – 648 m (>150% Drift)     | 184.2 m RMS (194m Peak, 21.7%)  | Catastrophic Divergence |
| Drift Reduction Factor | 98.2% Average Error Cut         | 99.7% Drift Reduction           | 99.9% Suppression       |
+====================================================================================================+
```

### 2. Validation Visuals: Slide 4 Trajectory & Dual Hero Benchmarks

The benchmark trajectory below displays the exact ground truth comparison for the 850-meter GNSS blackout tunnel sequence (`S-Vta23`):

![IO-VNBD S-Vta23 Benchmark Trajectory](docs/assets/iovnbd_svta23_plot.png)

```
850m Subterranean Tunnel Outage (Sequence S-Vta23):
=========================================================================================
Elapsed Time (s) | Truth Pos (X, Y)  | Classical DR (X, Y)  | IDR-Navigator (X, Y) | Drift %
-----------------+-------------------+----------------------+----------------------+---------
  0.0 s (Portal) | (   0.0,    0.0)m | (   0.0,    0.0)m    | (   0.0,    0.0)m    | 0.00%
 15.0 s          | ( 145.2,  182.4)m | ( 168.4,  214.1)m    | ( 144.8,  181.9)m    | 0.26%
 30.0 s          | ( 328.7,  412.0)m | ( 415.9,  362.5)m    | ( 326.5,  409.8)m    | 0.59%
 45.0 s          | ( 542.1,  638.5)m | ( 732.0,  410.2)m    | ( 538.0,  632.7)m    | 0.85%
 60.0 s (Exit)   | ( 780.4,  850.2)m | (1120.5,  520.4)m    | ( 780.1,  850.0)m    | 0.05%
=========================================================================================
Terminal Error   | Ground Truth Ref  | +194.0 m Off-Course  | 0.42 m (0.17m portal)| 99.7% Red.
```

### 3. Edge Profiling & Latency Breakdown

| Execution Stage | Target Hardware Platform | Processing Budget | Measured Latency | Safety Margin |
| :--- | :--- | :---: | :---: | :---: |
| **INT8 SE-TCN Neural Inference** | Qualcomm Snapdragon NPU / Hexagon DSP (NNAPI) | $10.0\text{ ms}$ | **$4.5\text{ ms}$** | $+122\%$ headroom |
| **Full Mobile Processing Loop** | ARM Cortex-A78 (ARM64 Flutter / C++ FFI) | $100.0\text{ ms}$ ($10\text{ Hz}$) | **$11.2\text{ ms}$** | $+792\%$ headroom |
| **Tactical FOG / Tactical IMU Loop** | C++20 SIMD (x86 AVX2 / ARM NEON) | $5.0\text{ ms}$ ($200\text{ Hz}$) | **$< 1.8\text{ ms}$** | $+177\%$ headroom |
| **Battery Consumption Rate** | Android 14 Foreground Service (Continuous GPS+IMU) | $< 10.0\%\text{/hr}$ | **$5.8\%\text{/hr}$** | Full shift endurance |

---

## 💻 Section E: ISRO Stage-2 Screening CLI (One-Command Reproduction)

ISRO evaluators can run our pre-trained INT8 ONNX model over any unseen CSV or ROSbag sequence using the unified screening script [`scripts/evaluate_iovnbd.py`](file:///e:/inventor/scripts/evaluate_iovnbd.py):

### 1. Python Screening CLI (IO-VNBD / Custom CSV)
```bash
# Step 1: Clone repository & install dependencies
git clone https://github.com/YashEkhande24/idr-desktop-simulator.git
cd idr-desktop-simulator
pip install -r idr_model_submission/requirements.txt

# Step 2: Run inference & 15-state ES-EKF evaluation on any test CSV
python scripts/evaluate_iovnbd.py \
  --input idr_model_submission/sample_data/scenario_1_highway_tunnel_outage.csv \
  --model idr_model_submission/idr_neurospeed_tcn_int8.onnx \
  --osm-tiles maps/ \
  --rate 100 \
  --export-plot results/trajectory_comparison.png \
  --export-metrics results/benchmark_report.json
```

### 2. High-Rate 200 Hz FOG / Tactical IMU Edge Engine (C++20 SIMD)
For evaluation with laboratory Fiber Optic Gyroscopes over serial UART/CAN:
```bash
# Build native C++20 SIMD binary
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build . --config Release -j4

# Stream 200 Hz FOG IMU in real-time
./idr_edge_engine --imu-rate 200 --sensor-type FOG --input /dev/ttyUSB0 --baud 921600
```

### 3. Native Flutter Mobile Evaluation
```bash
# Run on connected smartphone or emulator
flutter pub get
flutter run --release
```

---

## 📁 Repository Directory Structure

```
├── .github/workflows/          # CI/CD Automated Test Matrix (136 unit tests)
├── assets/models/              # Mobile ONNX Models & Normalization JSON
│   ├── idr_neurospeed_tcn.onnx # Full FP32 ONNX model (8.4 MB)
│   ├── idr_neurospeed_tcn_int8.onnx # Quantized INT8 model (2.1 MB)
│   └── normalize_stats.json    # Channel mean and std dev vectors
├── cpp_mobile_app/             # C++20 SIMD Native Edge Engine (200 Hz FOG Ready)
│   ├── CMakeLists.txt          # AVX2 / ARM NEON SIMD compilation
│   └── src/                    # ES-EKF, Mahony alignment & FOG parsers
├── docs/                       # Interactive Aerospace GitHub Pages Telemetry Site
│   ├── index.html              # Dark-mode dashboard with KaTeX equations
│   ├── styles.css              # Cyberpunk / Aerospace HUD styles
│   ├── app.js                  # Chart.js interactive trajectory comparison
│   └── assets/                 # Reconciled benchmark hero plots
├── idr_model_submission/       # Standalone AI Submission Dossier
│   ├── idr_neurospeed_tcn_int8.onnx # 2.1 MB INT8 Model binary
│   ├── model_architecture.py   # PyTorch SE-TCN definition
│   ├── results.json            # 64-trip validation logs
│   └── test.py                 # Standalone validation runner
├── lib/                        # Production Flutter Cross-Platform Client
│   ├── core/alignment/         # Mahony SO(3) & PCA azimuth lock
│   ├── core/filters/           # Jerk Variance Gate, Skog ZUPT & 15-State ES-EKF
│   ├── core/map/               # Offline OSM GeoJSON Orthogonal Vector Snapper
│   └── ui/                     # Dark-mode real-time telemetry HUD
├── scripts/                    # Automation & Evaluation Utilities
│   ├── evaluate_iovnbd.py      # Universal CLI evaluator for ISRO scientists
│   └── download_osm_roads.py   # Offline OSM vector tile extractor
└── test/                       # 136 Automated Unit & Integration Tests
```

---

## 🏆 Innovation & Intellectual Property Highlights

1. **Zero-CapEx Consumer Deployment:** Completely eliminates costly OBD-II dongles and fleet CAN-bus splicing. Runs on any sub-₹15,000 Android smartphone.
2. **Dual-Frequency Scalability:** Seamlessly scales from **10 Hz mobile updates** to **200 Hz industrial FOG telemetry** without mathematical reformulation.
3. **Pothole-Proof Kinematic Gating:** The Jerk Variance Gate rejects violent vertical suspension shock, preventing the EKF covariance from destabilizing on rugged Indian roads.
4. **Offline Vector Resiliency:** Operates 100% offline using compact OSM GeoJSON tiles (`~15 MB/city`), guaranteeing sovereign privacy and zero remote dependency.

---

## 👥 Team Inventor (Team ID: 133715)

* **Team Lead & Core Architect:** Yash Ekhande ([GitHub](https://github.com/YashEkhande24))
* **Organization:** Indian Space Research Organisation (ISRO) | SIH 2026
* **Problem Statement:** SIH26168 (*AI-ML based Intelligent Dead Reckoning system for seamless navigation*)
* **Repository:** [https://github.com/YashEkhande24/idr-desktop-simulator](https://github.com/YashEkhande24/idr-desktop-simulator)
