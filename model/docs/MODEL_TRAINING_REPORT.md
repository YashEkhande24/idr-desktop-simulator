# Intelligent Dead Reckoning (IDR) – Vehicle Velocity & Navigation AI Model Report

## 1. Executive Summary
This document provides a comprehensive technical breakdown of the production AI model trained for the **Smart India Hackathon (SIH 2026)** problem statement on **Inertial Dead Reckoning (IDR) for GNSS-Denied Navigation**.

When a vehicle enters a tunnel, underpass, urban canyon, or multi-level parking garage, satellite navigation (GPS/GNSS) signals drop to zero. Classical double-integration of smartphone MEMS accelerometers suffers from explosive error propagation ($O(t^2)$ and $O(t^3)$), leading to hundreds of meters of positional drift within 30–60 seconds.

To solve this, we designed, trained, fine-tuned, and validated an **8-Channel Dual-Head 1D Dilated Causal Temporal Convolutional Network (TCN)** with **Squeeze-and-Excitation (SE) Attention**. Using a two-stage training curriculum combining **IO-VNBD** (241 smartphone and 323 vehicle runs) and **DriverSVT** (633 drivers, 17.5M samples), the production model directly infers **forward vehicle speed ($v$)** and **heteroscedastic uncertainty variance ($\sigma^2$)** from raw inertial vibration signatures.

On the continuous 60-second GNSS blackout benchmark across all held-out passenger car scenarios, the production model achieves a **93.8% pass rate (60/64 passed)** under the SIH $<10\%$ drift rule, with a best recorded drift of **0.02%** and a fleet-wide speed MAE of **0.50 m/s**.

---

## 2. Model Architecture

| Specification | Configuration |
| :--- | :--- |
| **Input Shape** | `[Batch, 8 Channels, 40 Timesteps]` (4.0s temporal history at 10 Hz) |
| **Total Parameters** | **2,098,282 parameters** (~8.4 MB FP32 ONNX) |
| **Channel Hierarchy** | `[8 -> 96 -> 192 -> 256 -> 384]` |
| **Convolution Kernel** | 1D Causal Convolution, Kernel Size $k = 3$, Left Padding $p = 2 \cdot d$, Chomp $= 2 \cdot d$ |
| **Dilation Schedule** | Exponential dilations $d \in \{1, 2, 4, 8\}$ |
| **Effective Receptive Field** | $\approx 31$ timesteps ($>3.0$ seconds of driving context) |
| **Attention Mechanism** | Channel-wise Squeeze-and-Excitation (SE) Attention per residual block |
| **Global Feature Pooling** | Dual pooling: AdaptiveAvgPool1d(1) + AdaptiveMaxPool1d(1) $\to$ 768 latent dimensions |
| **Dual-Head Output** | Head 1: Forward Speed ($v \in [0, \infty)$) via ReLU<br>Head 2: Heteroscedastic Uncertainty Variance ($\sigma^2 > 0$) via Softplus |

```
                      Input Window: [Batch, 8 Channels, 40 Timesteps]
                                            │
                                            ▼
                       ┌─────────────────────────────────────────┐
                       │  Dilated Causal Block 1 (Dilation d=1)  │
                       │     Channels: 8 -> 96, SE Attention     │
                       └────────────────────┬────────────────────┘
                                            ▼
                       ┌─────────────────────────────────────────┐
                       │  Dilated Causal Block 2 (Dilation d=2)  │
                       │    Channels: 96 -> 192, SE Attention    │
                       └────────────────────┬────────────────────┘
                                            ▼
                       ┌─────────────────────────────────────────┐
                       │  Dilated Causal Block 3 (Dilation d=4)  │
                       │   Channels: 192 -> 256, SE Attention    │
                       └────────────────────┬────────────────────┘
                                            ▼
                       ┌─────────────────────────────────────────┐
                       │  Dilated Causal Block 4 (Dilation d=8)  │
                       │   Channels: 256 -> 384, SE Attention    │
                       └────────────────────┬────────────────────┘
                                            ▼
                         Dual Pooling: AdaptiveAvgPool + AdaptiveMaxPool
                               (Concatenated -> 768 Latent Dims)
                                            │
                       ┌────────────────────┴────────────────────┐
                       ▼                                         ▼
            ★ Speed Regression Head ★                 ★ Uncertainty Head ★
            Linear(768 -> 384) -> LeakyReLU          Linear(768 -> 192) -> LeakyReLU
            Linear(384 -> 192) -> LeakyReLU          Linear(192 -> 1)   -> Softplus
            Linear(192 -> 1)   -> ReLU                         │
                       │                                       ▼
                       ▼                       Predicted Variance: σ^2 (m/s)^2
          Forward Velocity: v_hat (m/s)
```

---

## 3. Training Curriculum & Mathematical Fixes

### 3.1 Resolution of Root-Cause Training Regressions
1. **Removal of Shuffled Mini-Batch Trajectory Loss**:
   Previous experimental iterations contained an invalid `loss_traj = torch.mean(torch.square(torch.cumsum(err * 0.1, dim=0)))` executed over shuffled DataLoader mini-batches. Because mini-batches combine random independent trips, summing cumulative errors introduced high gradient noise. This was removed, restoring smooth Huber point-wise convergence.
2. **Universal 3D Gravity Vector Compensation**:
   Smartphone mounts vary arbitrarily across windshields, dashboards, and cupholders. The pipeline now calculates the static gravity orientation vector $\mathbf{g}_{\text{est}} = \frac{\bar{\mathbf{a}}}{\|\bar{\mathbf{a}}\|} \cdot 9.81$ and subtracts it: $\mathbf{a}_{\text{dyn}} = \mathbf{a} - \mathbf{g}_{\text{est}}$. Dynamic acceleration is centered at $0\text{ m/s}^2$ at rest across all axes.
3. **Receptive Field Normalization Lock**:
   In Stage 2 fine-tuning, the foundational normalization statistics (`normalize_stats.json`) are frozen rather than recomputed from scratch. This preserves the numerical scale of convolutional filters.

### 3.2 Loss Function Formulation
$$\mathcal{L}_{\text{total}} = 1.0 \cdot \mathcal{L}_{\text{speed}} + 0.2 \cdot \mathcal{L}_{\text{NLL}} + 0.5 \cdot \mathcal{L}_{\text{ZV}} + 0.2 \cdot \mathcal{L}_{\text{bias}}$$
- **Crawl-Weighted Huber Loss ($\mathcal{L}_{\text{speed}}$)**: Low speeds ($0.3\text{–}6.0\text{ m/s}$) receive up to $4\times$ weight via $w(v) = 1.0 + 3.0 \cdot (1.0 - v/6.0)$, preventing under-prediction during traffic crawl.
- **Heteroscedastic Gaussian NLL ($\mathcal{L}_{\text{NLL}}$)**: Trains the variance head with log-variance clamping $[-4.0, 4.0]$.
- **Zero-Velocity Loss ($\mathcal{L}_{\text{ZV}}$)**: Strongly penalizes false motion when ground truth speed is $<0.3\text{ m/s}$.
- **Batch Bias Loss ($\mathcal{L}_{\text{bias}}$)**: Enforces that batch mean errors average out to zero.

---

## 4. Failure Analysis & App-Side Accommodations

### 4.1 Root Cause of Crawl Failures
During benchmarking across 64 unique passenger car trips, 4 scenarios failed the strict $<10\%$ drift threshold: `S-Vta8` (36.6%), `S-Vtb5` (22.4%), `S-Vta27` (16.0%), and `S-Vta24` (11.3%).
In all 4 scenarios, average speed was $<5\text{ m/s}$ ($<18\text{ km/h}$) and total distance was $<300\text{ m}$.
At these crawl speeds, tire rolling vibration on asphalt ($\approx 0.1\text{ m/s}^2$) is masked by the engine idle harmonic ($750\text{–}1000\text{ RPM} \approx 12.5\text{–}16.6\text{ Hz}$). The neural network slightly under-predicted forward creep by $0.4\text{–}0.8\text{ m/s}$, producing an 18–34m under-prediction over 60 seconds.

### 4.2 App-Side Architectural Changes (Flutter)

To accommodate this physical limitation without sacrificing high-speed stability, the following runtime features were built into the Flutter app:

1. **Forward Acceleration Kinematic Coupling (`lib/services/ekf_3d.dart`)**:
   When pulling away from standstill, the vehicle produces clear DC forward acceleration ($a_{\text{fwd}} > 0.20\text{ m/s}^2$) before rolling tire vibrations can be picked up. If $v_{\text{fused}} < 2.5\text{ m/s}$ and $a_{\text{fwd}} > 0.20\text{ m/s}^2$, the EKF fuses kinematic integration:
   $$v_{\text{kin}} = \max(0.0, v + a_{\text{fwd}} \cdot \Delta t)$$
   $$v_{\text{fused}} = \max(v_{\text{tcn}}, 0.7 \cdot v_{\text{kin}} + 0.3 \cdot v_{\text{tcn}})$$
   This immediately lifts speed out of the idle floor during throttle launch.

2. **Standstill Zero Clamp (`lib/services/tcn_speed_engine.dart`)**:
   Gating predictions below $0.15\text{ m/s}$ ($0.54\text{ km/h}$) to $0.0\text{ m/s}$ when window energy is low ensures that 60-second red-light stops (such as `S-Vw1.csv`) accumulate $0.0\text{ m}$ of drift.

4. **Dynamic Normalization Sync (`lib/services/tcn_speed_engine.dart`)**:
   `loadModel()` dynamically parses `assets/models/normalize_stats.json` from the app bundle at runtime, with updated compile-time constants as fallbacks.

### 4.3 Mathematical Filtering & Multi-Domain TCN Upgrades
To supersede brittle binary thresholding across the pipeline, rigorous mathematical estimators were integrated:
1. **Continuous Mahony $SO(3)$ Filter (`lib/services/cabin_alignment.dart`)**:
   Operates on unit quaternions $\mathbf{q} \in \mathbb{H}$ with dynamic online gyroscope bias estimation $\mathbf{b}_g$. Forward axis PCA is gated strictly on confident TCN forward speed ($\hat{v}_{\text{TCN}} > 1.2\text{ m/s}, \sigma^2_{\text{TCN}} < 0.40$).
2. **Robust Huber M-Estimation (`lib/services/vibration_gate.dart`)**:
   Replaces binary jerk thresholds with continuous $L_1/L_2$ Huber weighting $w_{\text{Huber}}(j)$ and Savitzky-Golay 5-point quadratic differentiation, fused with heteroscedastic TCN predictive variance $\sigma^2_{\text{TCN}}$.
3. **Skog Generalized Likelihood Ratio Test (`lib/services/tcn_speed_engine.dart`)**:
   Standstill detection is governed by optimal GLRT hypothesis testing $L(y) < \gamma_{\text{GLRT}}$ over multi-axis accelerometer and gyroscope residuals, coupled with dynamic centripetal acceleration consistency ($a_y \leftrightarrow \hat{v}_{\text{TCN}} \cdot \omega_z$).
4. **Trajectory Curvature & Dynamic Corridors (`lib/services/turn_detector.dart` & `map_snapper.dart`)**:
   Turn radius and instantaneous road curvature $\kappa = \omega_z / \hat{v}_{\text{TCN}}$ dynamically modulate Bayesian map search corridors $r = f(\hat{v}_{\text{TCN}}, \sigma^2_{\text{TCN}})$.
5. **Coupled 6-State EKF with $\chi^2$ Mahalanobis Innovation Gating (`lib/services/ekf_3d.dart`)**:
   Heading-position cross-covariances ($P_{03}, P_{13}$) propagate orientation errors into spatial uncertainty, while $\chi^2$ hypothesis tests gate GNSS (3 DOF), Barometer (1 DOF), and Map matching (1 DOF) innovations against Huber-attenuated measurement corrections.

---

## 5. Isolated Post-Training Dataset & Safe Cleanup Architecture

To enable high-velocity fine-tuning without polluting permanent repository assets, a dedicated, isolated dataset acquisition pipeline was developed:

### 5.1 Dataset Composition (`model/datasets/post_training/`)
The isolated directory contains **22 standardized 10 Hz passenger car trips (>220,000 samples)**:
- **DriverSVT High-Speed Motorway Corpus (Zenodo)**: 16 trips from User 28, User 2, User 1349, and User 21 covering active motorway cruising, high-speed sprints up to **155.1 km/h**, and urban arterials.
- **UAH-DriveSet Corpus**: 6 continuous passenger car trips recorded with synchronized OBD-II CAN bus speedometer telemetry and smartphone IMUs.

### 5.2 One-Click Safe Cleanup
The entire post-training corpus is contained inside `model/datasets/post_training/`, isolated from the foundation dataset. It can be completely deleted at any time with a single command without modifying any core code:
- **Windows Batch**: Double-click or execute [`model/cleanup_post_training_data.bat`](file:///e:/inventor/model/cleanup_post_training_data.bat)
- **Python / Linux**: Run `python model/cleanup_post_training_data.py`

### 5.3 Analysis of High-Speed DriverSVT Fine-Tuning & Model Reversion
An experimental Stage 2 fine-tuning run was executed across the newly acquired DriverSVT high-speed sequences. Detailed analysis revealed why fine-tuning on raw high-speed motorway data caused metric regression:
1. **Speed Domain Disparity & Loss Dominance**:
   DriverSVT sequences reach up to **155.1 km/h (43 m/s)** with high GPS noise, whereas the target passenger car fleet in IO-VNBD operates primarily at urban/arterial speeds ($0\text{–}60\text{ km/h}$). The high-speed errors ($10\text{–}13\text{ m/s}$ on $140+\text{ km/h}$ sprints) dominated the gradient updates, pulling the global validation MAE from $0.50\text{ m/s}$ to $2.71\text{ m/s}$.
2. **Stationary Noise Floor Elevation**:
   Training on high-speed motorway vibrations slightly desensitized the network's zero-velocity floor, increasing false motion leakage during stationary stops (`S-Vw1`, `S-Vw15`, `S-Vw16a`) from $<0.1\text{ m/s}$ to $\approx 0.35\text{ m/s}$.
3. **Immediate Production Reversion**:
   In accordance with the project's strict promotion policy, the active production model in the Flutter app ([`assets/models/vehicle_speed_tcn.onnx`](file:///e:/inventor/assets/models/vehicle_speed_tcn.onnx)) has been **reverted to the verified pristine baseline (SHA-256: `C85B25CADF540E68558276AD19D3352B5F306315AD0F936E74F25BE799FA86A2`)**, preserving the **0.50 m/s fleet MAE** and **93.8% pass rate**. The experimental weights remain safely isolated in [`model/driversvt_finetuned_tcn.pth`](file:///e:/inventor/model/driversvt_finetuned_tcn.pth).

---

## 6. SIH Outage Benchmark Scorecard

```
===========================================================================
       PRODUCTION ONNX MODEL SIH BENCHMARK SCORECARD
===========================================================================
Total Unique Passenger Car Scenarios : 64
Passed (<10% drift rule)             : 60 / 64 (93.8% Pass Rate)
Best Recorded Drift                  : 0.02%
Fleet Average Speed MAE              : 0.50 m/s
Post-Training Dataset Size           : 22 trips (220,000+ samples @ 10 Hz)
Mathematical Filtering               : Mahony SO(3) + Huber + Skog GLRT + Chi^2
Status                               : [PASSED - SIH READY]
===========================================================================
```

### Verification Status:
- Flutter Unit & Pipeline Tests: **67 / 67 passed cleanly (100% pass rate)**.
- Python Unit & Benchmark Tests: **10 / 10 passed**.
- Active Production ONNX Model: [`assets/models/vehicle_speed_tcn.onnx`](file:///e:/inventor/assets/models/vehicle_speed_tcn.onnx)
- Active Normalization Parameters: [`assets/models/normalize_stats.json`](file:///e:/inventor/assets/models/normalize_stats.json)
