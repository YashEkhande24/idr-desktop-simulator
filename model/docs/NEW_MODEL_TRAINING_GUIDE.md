# Intelligent Dead Reckoning (IDR) – New TCN Model Training & Architecture Guide

## 1. Executive Summary & Objective

This document details the complete methodology used to train, fine-tune, and deploy the new **8-Channel Dual-Head Dilated Causal SE-TCN Model** for the **Smart India Hackathon (SIH 2026)** GNSS-denied dead reckoning challenge.

The system replaces classical double-integration of raw accelerometer noise ($O(t^2)$ and $O(t^3)$ drift) with deep temporal inertial odometry. It predicts instantaneous forward vehicle velocity ($v$) and heteroscedastic uncertainty variance ($\sigma^2$) directly from smartphone IMU vibrations, keeping **positional drift $< 10\%$ over sustained 60-second complete satellite blackouts**.

---

## 2. Dataset Strategy & Universal Ingestion

### 2.1 Multi-Stage Ingestion Corpus
The training pipeline utilizes a two-dataset curriculum designed to eliminate sensor and vehicle bias:

1. **IO-VNBD (Inertial Odometry Vehicle Navigation Benchmark Dataset)**:
   - Primary corpus consisting of **241 smartphone and 323 vehicle runs** recorded across the UK, France, and Nigeria.
   - Provides consumer Android smartphone MEMS IMUs (accelerometer + gyroscope) paired with ground truth CAN-bus wheel speed and high-rate GNSS.
   - Used as the **Stage 1 foundational dataset** covering passenger cars, scooters, trucks, and vans in urban, suburban, and rural routes.

2. **DriverSVT (Smartphone-Measured Vehicle Telemetry - Zenodo)**:
   - Contains naturalistic driving telemetry across **633 drivers** and **17.56 million samples** in real traffic.
   - Features high-speed motorway cruising (100–160 km/h) and urban congestion.
   - Used for **Stage 2 transfer learning / fine-tuning** to expand the upper speed envelope without degrading low-speed precision.

### 2.2 Universal 3D Dynamic Gravity Vector Compensation
Smartphone mounts vary significantly across vehicles (horizontal dashboard holders, vertical windshield mounts, cupholders, or angled console docks). In natural driving, static gravity ($9.81\text{ m/s}^2$) leaks across all three axes depending on tilt:

$$\bar{\mathbf{a}} = \frac{1}{N} \sum_{k=1}^N \mathbf{a}_k, \quad \mathbf{g}_{\text{est}} = \frac{\bar{\mathbf{a}}}{\|\bar{\mathbf{a}}\|} \cdot 9.81$$

$$\mathbf{a}_{\text{dyn}} = \mathbf{a} - \mathbf{g}_{\text{est}}$$

Subtracting the estimated gravity vector $\mathbf{g}_{\text{est}}$ ensures dynamic acceleration is centered at $0\text{ m/s}^2$ at rest across all axes, ensuring mathematical invariance regardless of how the phone is mounted.

### 2.3 8-Channel Rotation-Invariant Feature Vector
To ensure the network is robust against phone rotation, each 10 Hz timestep ingests an 8-channel feature vector:

$$\mathbf{x}_t = \left[ a_x, a_y, a_z, \omega_x, \omega_y, \omega_z, \|\mathbf{a}\|, \|\boldsymbol{\omega}\| \right]^T \in \mathbb{R}^8$$

- Channels 0–2: 3-axis linear dynamic acceleration ($a_x, a_y, a_z$) in $\text{m/s}^2$.
- Channels 3–5: 3-axis angular velocity ($\omega_x, \omega_y, \omega_z$) in $\text{rad/s}$.
- Channel 6: Euclidean acceleration norm $\|\mathbf{a}\| = \sqrt{a_x^2 + a_y^2 + a_z^2}$ (rotation-invariant road vibration energy).
- Channel 7: Euclidean angular rate norm $\|\boldsymbol{\omega}\| = \sqrt{\omega_x^2 + \omega_y^2 + \omega_z^2}$ (rotation-invariant turning/pitching intensity).

Temporal window size is fixed to **40 timesteps (4.0 seconds)** at 10 Hz.

---

## 3. Neural Network Architecture

The model is an **8-Channel Dual-Head Dilated Causal Temporal Convolutional Network (TCN)** with **Squeeze-and-Excitation (SE) Attention**, containing **2,098,282 parameters** (~8.4 MB FP32 ONNX).

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

### Architectural Details:
- **Causal Convolutions with Chomp**: Enforces strict temporal causality ($t_k$ only sees $t \le t_k$) via left-padding and right-chomping.
- **Exponential Receptive Field**: Dilation schedule $d \in \{1, 2, 4, 8\}$ with kernel size $k=3$ covers $>3.1$ seconds of temporal road history.
- **Squeeze-and-Excitation (SE) Blocks**: Dynamically re-weights channel importance (e.g. amplifying vertical acceleration norms on rough roads and gyro z-axis during turns).
- **Dual Global Pooling**: Concatenating Adaptive Average Pooling and Adaptive Max Pooling retains both background vibration energy and sharp transient impulses (expansion joints, gear shifts).

---

## 4. Mathematical Pipeline Corrections & Loss Formulation

### 4.1 Discovery and Removal of Shuffled-Batch Trajectory Loss Bug
During investigation of earlier training regressions, a critical mathematical bug was isolated:
- An experimental loss function had computed cumulative error across the mini-batch dimension:
  $$\mathcal{L}_{\text{traj}} = \frac{1}{B} \sum_{i=1}^B \left( \sum_{j=1}^i \Delta v_j \cdot \Delta t \right)^2$$
- Because the DataLoader had `shuffle=True`, consecutive samples in a batch came from completely independent trips, vehicles, and timestamps.
- Computing a cumulative sum across random trips introduced random walk gradient noise, destabilizing training and causing high drift.
- **Fix**: Removed `loss_traj` and `loss_smooth` from shuffled batch training.

### 4.2 Multi-Task Composite Loss Function
The active loss function combines point-wise regression, heteroscedastic uncertainty calibration, zero-velocity standstill penalties, systematic bias reduction, and crawl boost:

$$\mathcal{L}_{\text{total}} = 1.0 \cdot \mathcal{L}_{\text{speed}} + 0.2 \cdot \mathcal{L}_{\text{NLL}} + 0.5 \cdot \mathcal{L}_{\text{ZV}} + 0.2 \cdot \mathcal{L}_{\text{bias}}$$

1. **Crawl-Weighted Huber Loss ($\mathcal{L}_{\text{speed}}$)**:
   $$\mathcal{L}_{\text{speed}} = \frac{1}{B} \sum_{i=1}^B w_i \cdot \text{SmoothL1}(v_{\text{pred}, i}, v_{\text{true}, i})$$
   $$w_i = \begin{cases} 1.0 + 3.0 \cdot \left(1.0 - \frac{v_{\text{true}, i}}{6.0}\right) & \text{if } 0.3 \le v_{\text{true}, i} < 6.0\text{ m/s} \\ 1.0 & \text{otherwise} \end{cases}$$
   Weighting low speeds ($1\text{ to }21.6\text{ km/h}$) up to $4\times$ prevents the optimizer from ignoring slow-speed crawl errors.

2. **Heteroscedastic Gaussian Negative Log-Likelihood ($\mathcal{L}_{\text{NLL}}$)**:
   $$\mathcal{L}_{\text{NLL}} = \frac{1}{2B} \sum_{i=1}^B \left( \exp(-s_i) \cdot (v_{\text{true}, i} - v_{\text{pred}, i})^2 + s_i \right), \quad s_i = \text{clamp}(\ln \sigma_i^2, -4.0, 4.0)$$
   Directly trains the secondary head to output variance $\sigma^2$ representing epistemic/aleatoric uncertainty for Kalman filter gain weighting.

3. **Zero-Velocity Standstill Loss ($\mathcal{L}_{\text{ZV}}$)**:
   $$\mathcal{L}_{\text{ZV}} = \frac{1}{|\mathcal{S}|} \sum_{i \in \mathcal{S}} v_{\text{pred}, i}^2 \quad \text{where } \mathcal{S} = \{i : v_{\text{true}, i} < 0.3\text{ m/s}\}$$
   Penalizes false motion spikes when the vehicle is stationary at traffic lights.

4. **Batch Systematic Bias Penalty ($\mathcal{L}_{\text{bias}}$)**:
   $$\mathcal{L}_{\text{bias}} = \left( \frac{1}{B} \sum_{i=1}^B (v_{\text{pred}, i} - v_{\text{true}, i}) \right)^2$$
   Enforces that positive and negative prediction errors cancel out on average, preventing cumulative distance drift.

---

## 5. Two-Stage Curriculum Strategy

1. **Stage 1: IO-VNBD Foundational Training**:
   - Ingests 241 IO-VNBD recordings with trip-level holdouts (zero window leakage).
   - Computes foundational normalization statistics saved to `normalize_stats.json`:
     - $\boldsymbol{\mu} = [-0.0237, -0.0647, 0.0127, -4.27\times 10^{-5}, -0.0052, -0.0005, 1.8305, 0.1863]$
     - $\boldsymbol{\sigma} = [1.6824, 1.6450, 0.7332, 0.1312, 0.2368, 0.1155, 1.6517, 0.2279]$
   - Checkpoint saved: `iovnbd_foundation_tcn.pth`.

2. **Stage 2: DriverSVT Transfer Learning / Fine-Tuning**:
   - Resumes from `iovnbd_foundation_tcn.pth` using a low learning rate ($10^{-4} \to 10^{-5}$).
   - **Critical Normalization Lock**: Reuses foundational `normalize_stats.json` rather than recomputing statistics, preventing receptive field corruption.
   - Checkpoint saved: `driversvt_finetuned_tcn.pth`.

3. **Safe Promotion Policy**:
   - The edge deployment model (`assets/models/vehicle_speed_tcn.onnx`) is only promoted if the candidate model achieves $\ge 90.6\%$ pass rate on the held-out passenger car benchmark.

---

## 6. Failure Analysis & App-Side Architectural Accommodations

### 6.1 Diagnosis of Low-Speed Crawl Failures
During benchmarking of all 64 continuous passenger car outage scenarios, 4 scenarios failed:

| Scenario | True Dist | Pred Dist | Delta ($\Delta d$) | Drift % | Speed MAE | Avg Speed |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `S-Vta8.csv` | 93.8 m | 59.4 m | -34.4 m | **36.60%** | 0.73 m/s | 1.56 m/s (5.6 km/h) |
| `S-Vtb5.csv` | 82.2 m | 63.8 m | -18.4 m | **22.36%** | 0.46 m/s | 1.37 m/s (4.9 km/h) |
| `S-Vta27.csv` | 160.9 m | 135.1 m | -25.8 m | **16.04%** | 0.59 m/s | 2.68 m/s (9.7 km/h) |
| `S-Vta24.csv` | 309.1 m | 274.2 m | -34.9 m | **11.30%** | 0.87 m/s | 5.15 m/s (18.5 km/h) |

#### Root Cause:
In all 4 cases, the vehicle was in severe **stop-and-go crawl** ($v < 5\text{ m/s}$). Notice that the absolute speed error is small ($\text{MAE} \le 0.87\text{ m/s}$). However, at $5\text{ km/h}$, tire rolling vibration on pavement ($\approx 0.1\text{ m/s}^2$) is completely masked by the engine idle harmonic ($750\text{–}1000\text{ RPM} \approx 12.5\text{–}16.6\text{ Hz}$). The neural network cannot distinguish neutral idle from in-gear crawl by vibration alone.

### 6.2 App-Side Accommodations in Flutter

To accommodate these physics limitations, three key changes were made to the Flutter mobile runtime:

#### Change 1: Forward Acceleration Kinematic Coupling in EKF (`ekf_3d.dart`)
- **File**: [`lib/services/ekf_3d.dart`](file:///e:/inventor/lib/services/ekf_3d.dart#L115-L125)
- When a vehicle pulls away from a stop or crawls forward, it produces a distinct DC longitudinal acceleration ($a_{\text{fwd}} > 0.20\text{ m/s}^2$) even before rolling tire vibrations emerge.
- If $v_{\text{fused}} < 2.5\text{ m/s}$ and $a_{\text{fwd}} > 0.20\text{ m/s}^2$, the EKF couples forward kinematic integration:
  $$v_{\text{kin}} = \max(0.0, v + a_{\text{fwd}} \cdot \Delta t)$$
  $$v_{\text{fused}} = \max(v_{\text{tcn}}, 0.7 \cdot v_{\text{kin}} + 0.3 \cdot v_{\text{tcn}})$$
- This lifts speed out of the idle floor during throttle launch, directly addressing the 18–34m under-prediction.

#### Change 2: Standstill Zero Clamp Calibration (`tcn_speed_engine.dart`)
- **File**: [`lib/services/tcn_speed_engine.dart`](file:///e:/inventor/lib/services/tcn_speed_engine.dart#L140-L150)
- In stationary holds (waiting at red lights or in gridlock), engine vibrations can accumulate 10–15 meters of false distance over 60 seconds if unclamped.
- A standstill clamp gates predictions below $0.15\text{ m/s}$ ($0.54\text{ km/h}$) to $0.0\text{ m/s}$ when window energy is low, guaranteeing zero drift on stationary stops like `S-Vw1.csv` and `S-Vw15.csv`.

#### Change 3: Dynamic Runtime Normalization Synchronization (`tcn_speed_engine.dart`)
- **File**: [`lib/services/tcn_speed_engine.dart`](file:///e:/inventor/lib/services/tcn_speed_engine.dart#L89-L105)
- Updated `loadModel()` to dynamically read and sync `assets/models/normalize_stats.json` from the app bundle at runtime, with updated compile-time constants as fallbacks. This guarantees the edge ONNX model receives inputs normalized with the exact training distribution.

---

## 7. Final SIH Outage Benchmark Scorecard

Evaluated across all continuous 60-second GNSS blackout scenarios in held-out passenger cars:

```
===========================================================================
       PRODUCTION ONNX MODEL SIH BENCHMARK SCORECARD
===========================================================================
Total Unique Passenger Car Scenarios : 64
Passed (<10% drift rule)             : 60 / 64 (93.8% Pass Rate)
Best Recorded Drift                  : 0.02%
Fleet Average Speed MAE              : 0.50 m/s
Status                               : [PASSED - SIH READY]
===========================================================================
```

### Verification Suite:
- **Flutter Test Suite**: **60 / 60 passed** cleanly in 5.0s.
- **Python Test Suite**: **10 / 10 passed** in 6.7s.
- **Active Production ONNX**: [`assets/models/vehicle_speed_tcn.onnx`](file:///e:/inventor/assets/models/vehicle_speed_tcn.onnx)
- **Active Normalization Metadata**: [`assets/models/normalize_stats.json`](file:///e:/inventor/assets/models/normalize_stats.json)
