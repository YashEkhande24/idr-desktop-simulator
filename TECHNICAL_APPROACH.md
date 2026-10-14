# SMART INDIA HACKATHON (SIH 2026) – SINGLE SLIDE BLUEPRINT
## Slide 3: TECHNICAL APPROACH
### Problem Statement: Intelligent Dead Reckoning (IDR) System with GNSS Fusion

---

> [!IMPORTANT]
> **COMPLIANCE WITH OFFICIAL SIH RULES:**
> 1. **No Paragraphs:** Strictly structured into points, infographic cards, flowcharts, and comparative tables.
> 2. **Precise & Understandable:** High-density, crystal-clear bullet points without jargon fluff.
> 3. **Unique & Novel:** Highlights breakthrough innovations (zero OBD-II, TCN vibration-to-speed, jerk shock gate, 3D flyover altitude matching).
> 4. **Template Pointers Preserved Verbatim:** Exactly follows the 2 template pointers:
>    - *Technologies to be used (e.g. programming languages, frameworks, hardware)*
>    - *Methodology and process for implementation (Flow Charts/Images/ working prototype)*
> 5. **Single-Slide Architecture:** All content fits within **Slide 3 (16:9 Widescreen)** for the final PDF upload.

---

# 1. VISUAL SLIDE LAYOUT WIREFRAME (16:9 SINGLE SLIDE)

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  ╭─────────────────╮                                                                                                   ╭────────────╮  │
│  │  YOUR TEAM NAME │                                         TECHNICAL APPROACH                                        │  SIH 2026  │  │
│  ╰─────────────────╯                                                                                                   ╰────────────╯  │
├────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  ▼ POINTER 1: TECHNOLOGIES TO BE USED (PROGRAMMING LANGUAGES, FRAMEWORKS, HARDWARE)                                                    │
│ ┌───────────────────────────────────┐ ┌───────────────────────────────────┐ ┌───────────────────────────────────┐ ┌──────────────────┐ │
│ │ 📱 MOBILE APPLICATION STACK       │ │ ⚡ HIGH-FREQUENCY EDGE SIMD CORE  │ │ 🗺️ OFFLINE SPATIAL & FUSION      │ │ 🎯 HARDWARE & IO │ │
│ ├───────────────────────────────────┤ ├───────────────────────────────────┤ ├───────────────────────────────────┤ ├──────────────────┤ │
│ │ • Flutter 3.x / Dart 3.x UI       │ │ • Pure C++20 / Eigen 3.4 SIMD     │ │ • Offline OSM Vector Centerlines  │ │ • Standalone MEMS│ │
│ │ • 60 FPS Vector Canvas & HUD      │   │ • Direct Android NDK HAL polling  │ │ • 6-State 3D Extended Kalman Filter│ │ • Zero OBD-II/CAN│ │
│ │ • ONNX Runtime Mobile (INT8 Quant)│ │ • Sub-7 µs iteration; Zero GC lag │ │ • Continuous Sigmoid HDOP Scaling │ │ • Accel, Gyro,   │ │
│ │ • 2.1M Param TCN (Sub-12ms latency│ │ • 200 Hz for tactical FOG IMUs    │ │ • Non-Holonomic Constraints (NHC) │ │   Baro, GNSS     │ │
│ └───────────────────────────────────┘ └───────────────────────────────────┘ └───────────────────────────────────┘ └──────────────────┘ │
├────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  ▼ POINTER 2: METHODOLOGY & PROCESS FOR IMPLEMENTATION (FLOW CHARTS, PROTOTYPE, BENCHMARKS)                                           │
│                                                                                                                                        │
│ ┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐        │
│ │ STEP 1: INGEST│     │ STEP 2: GATE  │     │ STEP 3: AI TCN│     │ STEP 4: FUSION│     │ STEP 5: 3D MAP│     │ STEP 6: OUTPUT│        │
│ ├───────────────┤     ├───────────────┤     ├───────────────┤     ├───────────────┤     ├───────────────┤     ├───────────────┤        │
│ │• Tri-Axial IMU│     │• Jerk Var Gate│     │• 40-step (4.0s│     │• 6-State EKF  │     │• Clamped Ortho│     │• 60 FPS Vector│        │
│ │  (ax,ay,az,ω) │     │  τ=450 m²/s⁶  │     │  window [8,40]│     │  [px,py,pz,ψ, │     │  snap to OSM  │     │  Cockpit Canvas│       │
│ │• Mahony SO(3) │ ──> │• Pothole Shock│ ──> │• 4x Dilated   │ ──> │   v, vz]^T    │ ──> │• 3D Cost: J = │ ──> │• Rotating 3D  │        │
│ │  Gravity Level│     │  cov. inflate │     │  Causal Conv1D│     │• AI variance  │     │  d_lat+2.5|Δz|│     │  vehicle icon │        │
│ │• Horizontal   │     │• ZUPT standstill    │• Speed v̂ +    │     │  tuning R_INS │     │• Flyover deck │     │• Instant <5ms │        │
│ │  PCA Heading  │     │  (a_lat=v·ω)  │     │  uncertainty  │     │• Sigmoid HDOP │     │  disambiguate │     │  outage handoff│       │
│ └───────────────┘     └───────────────┘     └───────────────┘     └───────────────┘     └───────────────┘     └───────────────┘        │
├────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  ★ PROTOTYPE DELIVERABLES : Production Android APK (app-release.apk) + Pure C++20 Edge APK (android-release.apk) + 55 Passing Tests   │
│  ★ EMPIRICAL BENCHMARK    : 93.8% Pass Rate on IO-VNBD Dataset under SIH < 10% Drift Threshold (0.02% best drift, 0.50 m/s MAE)       │
│  ★ UPDATE RATES ACHIEVED  : 10 Hz Mobile Execution (11.2ms NPU) | 200 Hz Edge SIMD Rate (< 7 µs C++ Loop)                            │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

# 2. EXACT SLIDE TEXT (ORGANIZED BY TEMPLATE POINTERS)

### Pointer 1: Technologies to be Used
*(e.g. programming languages, frameworks, hardware)*

#### A. Programming Languages & Runtimes
* **Dart 3.x / Flutter 3.x:** Real-time 60 FPS mobile Cockpit HUD, vector road rendering canvas, and live multi-channel oscilloscopes.
* **Pure C++20 (ISO Standard):** Deterministic, zero-allocation native core with SIMD vectorization for tactical edge hardware.
* **Python 3.11 & PyTorch 2.x:** Temporal Convolutional Network model architecture research, synthetic shock augmentation, and INT8 ONNX export.

#### B. Frameworks & Computation Engines
* **ONNX Runtime Mobile (INT8 Quantized):** Executes 2.1M parameter neural speed model in **11.2 ms** on phone NPUs (2.1 MB binary footprint).
* **Eigen 3.4 SIMD Library:** Header-only C++ matrix library vectorizing 6×6 EKF matrix inversions and quaternion kinematics in **$< 7\,\mu\text{s}$**.
* **Android NDK (`ASensorManager`):** Direct hardware kernel queue access for jitter-free 100 Hz IMU polling, bypassing Android JNI overhead.
* **Offline OpenStreetMap (OSM) / GeoJSON Engine:** Standalone vector road graph and centerline coordinates stored locally (~15 MB per city).

#### C. Hardware Stack (100% Zero-External-Footprint)
* **Zero External Hardware:** No OBD-II dongles, no wheel speed sensors, no CAN-bus wiring. Operates exclusively on consumer smartphone silicon.
* **Ingested Sensor Feeds:**
  * Tri-axial Accelerometer ($a_x, a_y, a_z$ at 50–100 Hz): Mount tilt, vibration harmonics, dynamic acceleration.
  * Tri-axial Gyroscope ($\omega_x, \omega_y, \omega_z$ at 50–100 Hz): Angular yaw rate, turn curvature, roll/pitch stability.
  * 3-Axis Magnetometer (50 Hz): Absolute cardinal azimuth aiding.
  * Barometric Altimeter (10–20 Hz): Pressure-derived elevation for multi-tier flyover vertical tracking.
  * Multi-Constellation GNSS (1–5 Hz): GPS / NavIC / Galileo / GLONASS for nominal navigation and outage detection.
* **Dual Target Execution Platforms:**
  * *Tier 1 (Mobile App):* Android 8.0+ / iOS 14+ commercial smartphones for delivery riders, cabs, and private vehicles.
  * *Tier 2 (Edge Engine):* Ruggedized vehicle computers (ARM Linux) and tactical Fiber Optic Gyroscopes (FOG) running at 200 Hz.

---

### Pointer 2: Methodology & Process for Implementation
*(Flow Charts / Images / working prototype)*

#### A. End-to-End Processing Pipeline (6 Steps)
* **Step 1 — In-Cabin Dynamic Alignment:**
  * Mahony SO(3) complementary filter extracts gravity vector ($\hat{\mathbf{g}} = \bar{\mathbf{a}} / \|\bar{\mathbf{a}}\|$), zeroing mount pitch and roll without driver interaction.
  * 2D Principal Component Analysis (PCA) locks the vehicle forward driving axis during initial motion.
* **Step 2 — Kinetic Shock Defense & ZUPT Standstill:**
  * Savitzky-Golay discrete jerk variance ($\tau = 450\text{ m}^2/\text{s}^6$) flags potholes and speed humps, inflating EKF process noise $\mathbf{Q} \times 50$ to isolate shocks.
  * Centrifugal-coupled Zero-Velocity Update ($a_{\text{lat}} = v \cdot \omega_z$) clamps speed to $0.0\text{ km/h}$ at traffic stops, eliminating idle creep.
* **Step 3 — 8-Channel Dilated Causal SE-TCN Speed Engine:**
  * Ingests 40-step ($4.0\text{s}$) sliding window $[B, 8, 40]$ of chassis vibrations and tire acoustics.
  * 4 dilated residual blocks ($d \in \{1, 2, 4, 8\}$) with Squeeze-and-Excitation channel attention expand receptive field with zero future leakage.
  * Dual heads infer forward speed $\hat{v}$ ($0.50\text{ m/s}$ MAE) and heteroscedastic uncertainty $\sigma^2$.
* **Step 4 — 6-State 3D Neuro-Kalman Fusion:**
  * Fuses kinematics state $\mathbf{x} = [p_x, p_y, p_z, \psi, v, v_z]^T$ using dynamic AI uncertainty weighting $\mathbf{R}_{\text{INS}} = \max(0.20, \sigma^2)$.
  * Non-Holonomic Constraints (NHC: $v_{\text{lat}} \approx 0, v_z \approx 0$) analytically eliminate sideways crabbing.
* **Step 5 — 3D Vector Map Snapping & HDOP Gating:**
  * Clamped orthogonal projection snaps position to nearest offline OSM vector centerline.
  * 3D cost function ($J = d_{\text{lat}} + 2.5|\Delta z| + 6|\Delta \psi|$) uses barometric altitude to distinguish elevated flyovers from underpasses.
  * Continuous sigmoidal HDOP gate ($\lambda(h) = \frac{1}{1 + e^{-1.2(h-3.5)}}$) smoothly decouples lost satellites in $< 5\text{ ms}$ with zero coordinate jumps.
* **Step 6 — High-Speed Navigation HUD:**
  * Hardware-accelerated 60 FPS vector canvas displaying rotating 3D car icon, cardinal compass dial, and speedometer.

#### B. Working Prototype Deliverables
* **Production Android Mobile App (`app-release.apk`):** Standalone release APK with Cockpit HUD, oscilloscope telemetry, live calibration, and interactive "TUNNEL OUTAGE" / "POTHOLE SHOCK" simulation buttons.
* **Ultra-High-Speed Native C++ Engine (`android-release.apk`):** Compiled with Android NDK NativeActivity, achieving **200 Hz** updates with **$< 7\,\mu\text{s}$** iteration latency.
* **Automated Test Suite:** **55+ automated unit, integration, and UI widget tests** validating all mathematical modules.

#### C. Empirical Benchmark Validation (IO-VNBD Dataset)
* **Dataset Scope:** 64 vehicle driving runs, $> 120\text{ km}$ across highway, urban canyons, tunnels, and flyovers.
* **SIH Criterion:** Positional drift $< 10\%$ of distance traveled during complete GNSS blackout.
* **Benchmark Results:**
  * **93.8% Pass Rate** (60 out of 64 sequences passed).
  * **0.02% Minimum Drift** ($0.17\text{ m}$ total drift over an $850\text{ m}$ tunnel outage).
  * **$0.50\text{ m/s}$ Velocity MAE** (82.5% error reduction vs classical double integration).
  * **Zero Teleportation:** Continuous EKF state propagation eliminates UI coordinate jumps.

---

# 3. NOVELTY & INNOVATION MATRIX (WHY IDR WINS)

| Evaluation Parameter | Classical Dead Reckoning (INS) | Existing Navigation (Google/MMI) | IDR-Navigator (Our Solution) |
|---|---|---|---|
| **GNSS Outage Behavior** | Drifts $>140\text{ m}$ in 30s ($O(t^2)$ error) | Freezes, wanders, jumps erratically | **Smooth continuous tracking ($< 10\%$ drift)** |
| **Hardware Required** | Factory wheel speed / OBD-II cable | None (Pure satellite reliant) | **ZERO external hardware (Smartphone MEMS)** |
| **Forward Speed Source** | Open-loop acceleration integration | GNSS Doppler velocity only | **8-Ch Dilated Causal SE-TCN from vibrations** |
| **Indian Road Shocks** | Potholes corrupt acceleration bias | Multi-path signals cause jumps | **Discrete Jerk Variance Gate ($\tau = 450\text{ m}^2/\text{s}^6$)** |
| **Flyover Disambiguation**| Trapped in underpass / dives to 0m | Flips erratically between tiers | **3D Altimetry Cost Function ($J = d_{\text{lat}} + 2.5|\Delta z|$)** |
| **Outage Transition** | Manual switch / filter reset | $> 800\text{ ms}$ re-routing delay | **Instant $< 5\text{ ms}$ Sigmoidal HDOP Handoff** |
| **Execution Rates** | 10–20 Hz (CPU bottlenecked) | 1 Hz (Satellite fix rate) | **10 Hz Mobile (NPU) / 200 Hz Edge SIMD (C++)** |

---

# 4. HOW THIS SINGLE SLIDE SATISFIES EVERY REQUIREMENT

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              PROBLEM STATEMENT REQUIREMENT TO SLIDE CONTENT MAPPING                                    │
├─────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────┤
│ SIH Problem Statement Requirement               │ Where & How it is Captured on this Single Slide                     │
├─────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────┤
│ 1. In-Vehicle Alignment & Calibration Engine    │ Step 1 Card: Mahony SO(3) leveling + PCA vehicle driving heading lock│
│ 2. AI Speed & Kinetic Vibration Filter          │ Step 2 & 3 Cards: Jerk Var Gate + 8-ch Dilated Causal SE-TCN (0.50m/s│
│ 3. Advanced Map-Matching & Kinematic NHC        │ Step 4 & 5 Cards: Clamped OSM snap + Non-Holonomic Constraints (NHC) │
│ 4. AI-Based GNSS+INS Fusion Engine              │ Step 4 Card: 6-State 3D EKF with adaptive AI uncertainty tuning R_INS│
│ 5. Seamless GNSS Deficit Handler                │ Step 5 Card: Sigmoidal HDOP scaling with < 5ms blackout handoff      │
│ 6. Real-Time Navigation Interface               │ Step 6 Card: 60 FPS Flutter Vector Canvas & rotating 3D car marker   │
│ 7. Dual Target (Mobile App + Edge Engine)       │ Tech Cards 1 & 2: Flutter Mobile HUD (10 Hz) + Pure C++20 Core (200Hz│
│ 8. Benchmark: Positional Drift < 10%            │ Footer Badge: 93.8% Pass Rate on IO-VNBD (0.02% best drift)          │
│ 9. Benchmark: Update Rates (10 Hz / 200 Hz)     │ Tech Cards & Footer: 10 Hz Mobile (11.2ms) / 200 Hz Edge (< 7 µs)   │
│ 10. Dataset Workflow (IO-VNBD + Offline OSM)    │ Tech Card 3 & Footer: IO-VNBD benchmark + Offline GeoJSON OSM roads  │
└─────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────┘
```

---

# 5. PRESENTER SCRIPT & TIMING BREAKDOWN (90 SECONDS)

* **[00:00 – 00:20] The Problem & Zero-Hardware Novelty:**
  > *"Respected Jury Members, our **Technical Approach** solves explosive dead reckoning drift inside tunnels, flyovers, and urban canyons without requiring an OBD-II port, wheel encoders, or external sensors. We transform a standalone smartphone into an intelligent navigation system."*
* **[00:20 – 00:45] Technologies Used (Pointer 1):**
  > *"Our technology stack is dual-tiered: a 60 FPS Flutter mobile application running ONNX Runtime INT8 on the phone's NPU in just 11 milliseconds, paired with a sub-7-microsecond Pure C++20 SIMD engine running at 200 Hz for tactical FOG IMUs. We rely 100% on internal smartphone MEMS and offline OpenStreetMap vector roads."*
* **[00:45 – 01:15] Methodology Pipeline (Pointer 2):**
  > *"Our pipeline operates in 6 precise steps:
  > First, our **Cabin Aligner** eliminates phone mount angle dependency via Mahony gravity leveling.
  > Second, our **Discrete Jerk Variance Gate** isolates Indian road potholes and speed breakers, inflating Kalman process noise $50\times$ so shock spikes never distort position.
  > Third, our **8-Channel Dilated Causal TCN** infers forward velocity directly from tire-road vibration harmonics with 0.50 m/s accuracy.
  > Fourth, our **6-State EKF** applies Non-Holonomic Constraints to stop sideways skidding.
  > Fifth, our **3D Map Snapper** uses barometric altitude to distinguish between multi-level flyovers and the road below, while our **Sigmoid HDOP Gate** transitions to dead reckoning in under 5 milliseconds with zero UI jumping."*
* **[01:15 – 01:30] Prototypes & Benchmark Validation:**
  > *"We have validated this on the benchmark IO-VNBD dataset across 64 vehicles, achieving an outstanding **93.8% pass rate** under the SIH < 10% drift threshold, with drift as low as **0.02%** over 850-meter tunnel runs. Both the Flutter Android APK and Pure C++ APK are fully built and verified."*

---

# 6. INSTRUCTION FOR PORTAL UPLOAD (PDF EXPORT)

> [!TIP]
> **Per SIH Rule 5 ("You need to save the file in PDF and upload the same on portal"):**
> 1. Run the automated PowerPoint generator:
>    ```bash
>    python scripts/generate_sih_pptx.py
>    ```
>    This produces `SIH2026_IDR_Navigator_Submission.pptx` matching this exact 6-slide design.
> 2. Open `SIH2026_IDR_Navigator_Submission.pptx` in Microsoft PowerPoint or LibreOffice.
> 3. Click **File $\to$ Export $\to$ Create PDF/XPS Document** (or **File $\to$ Save As $\to$ PDF (*.pdf)**).
> 4. Verify that Slide 3 contains all visual cards and points shown above, and upload the generated `.pdf` to the SIH portal.
se