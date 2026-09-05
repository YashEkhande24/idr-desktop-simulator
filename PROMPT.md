# Context & Objective
Build a desktop simulation of an AI-ML based Intelligent Dead Reckoning (IDR) system 
for GNSS-denied navigation (tunnels, multi-level flyovers, urban canyons) using PySide6, 
PyTorch/NumPy, and PyQtGraph/Matplotlib.

### Core Pipelines to Implement:
1. SENSOR INGESTION & SYNTHESIZER (`generator.py`):
   - Generates Ground Truth 3D path: Straight -> Curve -> Pothole Section -> 
     Flyover/Split -> 180s Tunnel (GNSS Denied).
   - Generates 100 Hz IMU (accel [ax, ay, az] + gyro [wx, wy, wz] with arbitrary phone tilt).
   - Generates 10 Hz Barometer (pressure-altitude z_baro).
   - Generates 1 Hz GNSS with HDOP and simulated dropouts/multipath.

2. CABIN ALIGNMENT (`cabin_alignment.py`):
   - Estimates gravity vector g_hat = -mean(a) / ||mean(a)|| to remove roll and pitch.
   - Applies sliding-window PCA on horizontal accelerations to find forward vehicle axis f_hat.
   - Rotates arbitrary phone IMU coordinates into vehicle coordinate frame [x_fwd, y_lat, z_up].

3. VIBRATION GATE & TCN SPEED ENGINE (`vibration_gate.py` & `tcn_speed_engine.py`):
   - Jerk Gate: Computes j_t = (a_t - a_{t-1}) / dt; tracks variance sigma_j^2 over window k.
     If sigma_j^2 > tau_j (pothole detected), freezes speed update to prevent false accelerations.
   - TCN Speed Engine: Causal 1D Dilated ConvNet (receptive field >= 200 samples / 2 seconds) 
     taking [a_fwd, a_lat, a_vert, w_yaw] -> outputs estimated forward velocity v_hat.

4. 3D EKF FUSION WITH NON-HOLONOMIC CONSTRAINTS (`ekf_3d.py`):
   - State Vector: x = [p_x, p_y, p_z, v_x, v_y, v_z, roll, pitch, yaw]^T (9D).
   - Non-Holonomic Constraints (NHC): Lateral velocity v_y ≈ 0, vertical velocity v_z ≈ 0.
   - Measurement Updates:
     * TCN Forward Speed (v_fwd)
     * Gyroscope Yaw Rate (w_z)
     * Barometer Elevation (z_baro)
     * GNSS [x, y, z] weighted dynamically by Sigmoid HDOP Covariance:
       R_gnss(HDOP) = R_0 + [1 / (1 + exp(-k*(HDOP - HDOP_0)))] * R_max

5. BASELINE ENGINE (`Classic Double-Integration DR`):
   - Integrates measured raw acceleration directly: v = v + a*dt, p = p + v*dt without NHC/TCN.
   - Displays real-time explosive drift (>140 m) vs IDR (<4 m).

6. DESKTOP GUI (`app.py`):
   - Left Panel: Telemetry HUD (Current Speed, HDOP, GNSS Status: Available/Degraded/Denied, Drift Error).
   - Center Viewport: Interactive 2D/3D map displaying:
     * Ground Truth (White dotted)
     * Classic Dead Reckoning (Red path - drifting off)
     * IDR Proposed (Green path - constrained to road)
   - Bottom Panel: Real-time oscilloscopes for Raw Jerk vs Gated Jerk, Barometric Altitude, and TCN Speed.
   - Controls: Play, Pause, Step, Toggle Potholes, Toggle GNSS Outage, Speed Slider.

## Component Specifications & Mathematical Formulations

### Module 1: Dynamic In-Cabin Alignment (cabin_alignment.py)
When a smartphone is mounted at an arbitrary angle $\mathbf{R}_{bv}$, the IMU
measurements must be transformed into the vehicle body frame:
1. Gravity Tracking (Tilt Compensation):
   $$\mathbf{g} = \frac{\frac{1}{N}\sum_{i=1}^N \mathbf{a}_i}{\left\|\frac{1}{N}\sum_{i=1}^N \mathbf{a}_i\right\|}$$
   Determine pitch ($\theta_0$) and roll ($\phi_0$) such that $\mathbf{g}$ aligns with $[0, 0, -1]^T$.
2. Horizontal PCA (Heading Alignment): Compute covariance matrix of horizontal
   accelerations $\mathbf{C} = \text{Cov}(\mathbf{a}_{\text{horiz}})$. The
   principal eigenvector corresponds to the vehicle’s primary axis of forward motion.
3. Vehicle Frame Transform:
   $$\mathbf{a}_v = \mathbf{R}_{bv}(\mathbf{a}_m - \mathbf{b}_a - \mathbf{g})$$

### Module 2: Kinetic Vibration Gate (vibration_gate.py)
Potholes and expansion joints generate high-frequency vertical shocks that
classical double-integration mistakes for forward/lateral motion.
1. Discrete Jerk:
   $$\mathbf{j}_t = \frac{\mathbf{a}_t - \mathbf{a}_{t-1}}{\Delta t}$$
2. Sliding Variance Check: $\sigma_j^2 = \text{Var}(\mathbf{j}_{t-k:t})$
3. Gate Rule:
   $$\text{If } \sigma_j^2 > \tau_{\text{jerk}} \implies \text{Flag shock, freeze } \hat{v}_t = \hat{v}_{t-1}, \text{ inflate } \mathbf{Q}_{k} \text{ in EKF.}$$

### Module 3: TCN Speed Engine (tcn_speed_engine.py)
A lightweight 1D Temporal Convolutional Network that maps sliding IMU windows
(200 timesteps @ 100 Hz = 2 seconds) directly to forward scalar speed $\hat{v}$.
- Architecture:
  - Input shape: (batch, 4 channels, 200 samples): $[a_{\text{fwd}}, a_{\text{lat}}, a_{\text{vert}}, \omega_{\text{yaw}}]$.
  - 3 Residual Blocks with causal dilated convolutions:
    - Block 1: dilation=1, kernel_size=3, filters=32
    - Block 2: dilation=2, kernel_size=3, filters=32
    - Block 3: dilation=4, kernel_size=3, filters=64
  - Global Adaptive Average Pooling $\to$ Dense(32) $\to$ ReLU $\to$ Dense(1) $\to$ Predicted Speed $\hat{v}_t$.
- Fallback: Provide a fast heuristic mock within the file if PyTorch weights are not yet trained:
  $$\hat{v}_{\text{est}} = \int a_{\text{fwd}} \, dt \quad (\text{zero-velocity updated via standstill detector and low-pass filtered}).$$

### Module 4: 9D Extended Kalman Filter + NHC (ekf_3d.py)
- State Vector: $\mathbf{x} = [p_x, p_y, p_z, v_x, v_y, v_z, \phi, \theta, \psi]^T$
- Kinematics Propagation (100 Hz):
  $$\mathbf{p}_{k} = \mathbf{p}_{k-1} + \mathbf{v}_{k-1}\Delta t + \frac{1}{2}\mathbf{R}(\mathbf{q})\mathbf{a}_v \Delta t^2$$
  $$\mathbf{v}_{k} = \mathbf{v}_{k-1} + \mathbf{R}(\mathbf{q})\mathbf{a}_v \Delta t$$
- Non-Holonomic Constraints (Virtual Measurements): Wheeled vehicles do not drift sideways or fly:
  $$v_{\text{lateral}} = [-\sin\psi, \cos\psi, 0] \cdot \mathbf{v} \approx 0 \quad (\sigma_{\text{nhc}}^2 = 0.05)$$
  $$v_{\text{vertical}} = [0, 0, 1] \cdot \mathbf{v} \approx 0 \quad (\sigma_{\text{vert}}^2 = 0.02)$$
- Barometric Elevation:
  $$z_{\text{baro}} = 44330 \left(1 - \left(\frac{P}{1013.25}\right)^{0.1903}\right)$$
  Directly updates $p_z$ state at 10 Hz to resolve flyover vs. underpass ambiguities.
- Sigmoid HDOP GNSS Covariance:
  $$\lambda(h) = \frac{1}{1 + e^{-k(h - h_0)}}$$
  $$\mathbf{R}_{\text{GNSS}}(h) = \mathbf{R}_{\text{nominal}} + \lambda(h) \mathbf{R}_{\text{max}}$$
  When entering a tunnel, HDOP surges $\to \lambda(h) \to 1 \implies \mathbf{R}_{\text{GNSS}} \to \infty$, causing the filter to autonomously ignore corrupted GNSS coordinates.
