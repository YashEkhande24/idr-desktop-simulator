# AI-Enhanced Intelligent Dead Reckoning (IDR) Navigator

**Smart India Hackathon 2026 Prototype**  
*Real-Time GNSS-Denied Navigation for Smartphone Hardware*

---

## Overview

The **IDR Navigator** is a high-performance native Flutter mobile application engineered to solve the acute problem of **explosive dead reckoning drift** in GNSS-denied environments (long tunnels, underground passes, multi-level flyovers, and urban canyons) using low-cost smartphone inertial sensors.

Unlike classical double-integration systems that drift quadratically by over **140 meters** within seconds, the IDR system constrains positional drift to **under 4 meters** by fusing:
1. **Dynamic In-Cabin Alignment (Tilt & Heading Compensation)**
2. **Kinetic Vibration Gating (Pothole & Expansion Joint Shock Rejection)**
3. **Neural & Kinematic Forward Speed Estimation with ZUPT Standstill Locking**
4. **9D Extended Kalman Filter (EKF) with Non-Holonomic Constraints (NHC)**
5. **Continuous Sigmoid HDOP Covariance Rejection**

---

## System Architecture

```
                                [Smartphone Hardware Sensors]
                                              │
                      ┌───────────────────────┴───────────────────────┐
                      ▼                                               ▼
             [100 Hz IMU Stream]                             [1 Hz GNSS & 10 Hz Baro]
             (Accel & Gyroscope)                                (WGS-84 & Pressure)
                      │                                               │
                      ▼                                               ▼
          [Module 1: Cabin Alignment]                        [Local ENU Projection]
       (Gravity Vector Tilt & Body Frame)                             │
                      │                                               │
                      ▼                                               │
         [Module 2: Vibration Gate]                                   │
      (Jerk Variance Shock Detection)                                 │
                      │                                               │
                      ▼                                               │
         [Module 3: TCN Speed Engine]                                 │
         (Kinematic Forward Velocity)                                 │
                      │                                               │
                      └───────────────────────┬───────────────────────┘
                                              ▼
                             [Module 4: 9D Extended Kalman Filter]
                             ├── Kinematics State Propagation (100 Hz)
                             ├── Non-Holonomic Constraints (NHC: v_lat ≈ 0, v_vert ≈ 0)
                             ├── Barometric Elevation Update (Flyovers)
                             └── Sigmoid HDOP Adaptive Weighting (Tunnel Outage Rejection)
                                              │
                      ┌───────────────────────┴───────────────────────┐
                      ▼                                               ▼
         [Telemetry HUD & Speedometer]                     [Vector Road Canvas & Map]
           - IDR Drift vs Classic DR                        - Green IDR vs Red Classic
           - HDOP & Tunnel Outage Status                    - Directional Vehicle Marker
           - Vibration Shock Trip Banner                    - Multi-Channel Oscilloscopes
```

---

## Algorithmic Implementation Details

### Module 1: Dynamic In-Cabin Alignment (`cabin_alignment.dart`)
- **Tilt Compensation**: Computes low-pass gravity vector $\hat{\mathbf{g}} = \frac{\bar{\mathbf{a}}}{\|\bar{\mathbf{a}}\|}$ to determine phone mount pitch ($\theta_0$) and roll ($\phi_0$).
- **Frame Rotation**: Dynamically rotates raw phone coordinates into the vehicle body frame:
  $$\mathbf{a}_v = \mathbf{R}_{bv}(\mathbf{a}_m - \mathbf{b}_a) - [0, 0, g]^T$$

### Module 2: Kinetic Vibration Gate (`vibration_gate.dart`)
- **Discrete Jerk**: $\mathbf{j}_t = \frac{\mathbf{a}_t - \mathbf{a}_{t-1}}{\Delta t}$
- **Sliding Variance Check**: $\sigma_j^2 = \text{Var}(\mathbf{j}_{t-k:t})$ over a 250ms window.
- **Shock Rule**: If $\sigma_j^2 > \tau_{\text{jerk}}$ ($35\ \text{m}^2/\text{s}^6$), freezes speed integration and inflates process covariance $\mathbf{Q}_k \times 50$, preventing road shocks from corrupting the EKF.

### Module 3: TCN Forward Speed Engine (`tcn_speed_engine.dart`)
- Maps 4-channel IMU $[\mathbf{a}_{\text{fwd}}, \mathbf{a}_{\text{lat}}, \mathbf{a}_{\text{vert}}, \omega_{\text{yaw}}]$ into forward scalar speed.
- Includes **Zero-Velocity Update (ZUPT)** standstill detector to completely eliminate rest drift at red lights or stop signs.

### Module 4: 9D EKF with Non-Holonomic Constraints (`ekf_3d.dart`)
- **State Vector**: $\mathbf{x} = [p_x, p_y, p_z, v_x, v_y, v_z, \phi, \theta, \psi]^T$
- **Non-Holonomic Constraints (NHC)**:
  $$v_{\text{lat}} = [-\sin\psi, \cos\psi, 0] \cdot \mathbf{v} \approx 0 \quad (\sigma_{\text{nhc}}^2 = 0.05)$$
  $$v_{\text{vert}} = [0, 0, 1] \cdot \mathbf{v} \approx 0 \quad (\sigma_{\text{vert}}^2 = 0.02)$$
- **Sigmoid HDOP GNSS Covariance**:
  $$\lambda(h) = \frac{1}{1 + e^{-k(h - h_0)}}, \quad \mathbf{R}_{\text{GNSS}}(h) = \mathbf{R}_{\text{nominal}} \cdot h^2 + \lambda(h) \mathbf{R}_{\text{max}}$$
  When a vehicle enters a tunnel, HDOP surges $\to \lambda(h) \to 1 \implies \mathbf{R}_{\text{GNSS}} \to \infty$, causing the filter to autonomously reject corrupted multipath fixes.

### Module 5: Baseline Engine (`baseline_dr.dart`)
- Integrates raw acceleration directly without NHC or AI speed estimation.
- Runs concurrently in the background to demonstrate side-by-side explosive drift (>140m).

---

## How to Run

### Option A: One-Click Runner (Windows)
Double-click `run.bat` in the project root:
- Press `[1]` to launch immediately in **Google Chrome** (recommended for evaluation & desktop demo).
- Press `[2]` to launch on a connected **Android phone** via USB.
- Press `[3]` to build a standalone **Release Android APK**.
- Press `[4]` to execute the **Full Test Suite**.

### Option B: Command Line

```bash
# 1. Test in Chrome Browser
flutter run -d chrome

# 2. Test on Connected Android Phone
flutter run -d android

# 3. Build Production APK
flutter build apk --release
# Generated at: build/app/outputs/flutter-apk/app-release.apk

# 4. Run All Unit & Integration Tests
flutter test
```

---

## Interactive Evaluation Features

1. **Mode Switcher**:
   - **SIH 2026 Test Course**: Complete benchmark course traversing highway acceleration, 90° curve, severe potholes, multi-level flyover climb, and a 60-second tunnel outage.
   - **Live Sensors**: Ingests the smartphone's real physical accelerometer, gyroscope, and GPS fix in real time.
2. **Interactive Outage Trigger ("TUNNEL OUTAGE")**:
   - Tap the red **TUNNEL OUTAGE** button at any moment to cut satellite fixes and watch IDR hold the lane while Classic DR drifts off screen.
3. **Shock Injector ("POTHOLE SHOCK")**:
   - Injects vertical vibration spikes to demonstrate the Vibration Gate shock freeze.
4. **Cabin Alignment Wizard**:
   - Tap **ALIGN MOUNT** to view a live 2D artificial horizon bubble level and lock phone tilt calibration.
