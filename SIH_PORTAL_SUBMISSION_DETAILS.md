# SMART INDIA HACKATHON (SIH 2026) — PORTAL SUBMISSION FORM DETAILS

> **Quick Copy Guide:** Each section below corresponds directly to the fields in your SIH idea submission portal. Character limits have been strictly respected. The content is written in a direct, natural engineering tone—grounded in real-world Indian road challenges, concrete architectural trade-offs, and empirical benchmarks.

---

## 1. IDEA TITLE
* **Field Character Limit:** Maximum 100 characters
* **Recommended Title:**
```text
  IDR-Navigator: Zero-Hardware Intelligent Dead Reckoning & GNSS Fusion
```
*(Character count: 68 / 100 characters)*

* **Alternative Title 1 (Formal PS Match):**
```text
Intelligent Dead Reckoning (IDR) System with GNSS Fusion for Smartphones
```
*(Character count: 71 / 100 characters)*

* **Alternative Title 2 (Technical Focus):**
```text
IDR-Navigator: Edge Neuro-Kalman Dead Reckoning & 3D Map-Matching Engine
```
*(Character count: 71 / 100 characters)*

---

## 2. TECHNOLOGY BUCKET
* **Field Type:** Dropdown Selection
* **Recommended Selection:**
  👉 **`AI/ML, Cloud Computing, Blockchain`**
  *(Reason: The core algorithmic engine is an 8-Channel Dilated Causal Temporal Convolutional Network with Squeeze-and-Excitation attention and heteroscedastic uncertainty estimation integrated with a Neuro-Kalman Filter.)*

* **Alternative Selection (if your team registered under embedded/sensor category):**
  👉 **`IoT and Electronics`**
  *(Reason: Focuses on internal smartphone MEMS sensor fusion, accelerometer/gyroscope processing, and edge hardware deployment.)*

---

## 3. ABSTRACT / SUMMARY
* **Field Character Limit:** Maximum 10,000 characters
* **Actual Character Count:** ~3,100 characters (Well within the 10,000 character limit)
* **Text to Copy-Paste:**

```text
Satellite navigation fails at the exact moments drivers need it most. When entering tunnels, navigating double-decker flyovers, or driving through dense high-rise urban corridors, GNSS signals degrade, multipath errors spike, or the fix drops entirely. Conventional navigation applications freeze, wander erratically, or jump dozens of meters across adjacent streets. While high-end autonomous vehicles handle this using expensive wheel odometry or differential GPS, commercial fleets, delivery riders, and daily commuters in India rely purely on consumer smartphones with zero external hardware connections.

We built IDR-Navigator: an intelligent dead reckoning and sensor fusion engine that operates entirely on standard smartphone hardware without requiring OBD-II dongles, CAN-bus taps, or wheel encoders. The core challenge of dead reckoning on a phone has always been error accumulation: integrating noisy smartphone accelerometer data over time causes positional drift that explodes quadratically (O(t^2)), drifting over 100 meters off-course within 30 seconds of GPS blackout. 

Instead of raw double-integration, IDR-Navigator introduces a deep learning velocity engine. We designed an 8-channel Dilated Causal Temporal Convolutional Network (SE-TCN) that continuously infers forward vehicle speed (0.50 m/s mean absolute error) directly from chassis vibration harmonics and road-tire interaction picked up by the phone’s inertial sensors. Because the model outputs both estimated velocity and heteroscedastic uncertainty, our 6-State 3D Neuro-Kalman Filter (EKF) dynamically scales its measurement trust based on road roughness.

To handle unique Indian driving conditions, our pipeline incorporates three purpose-built modules:
1. Dynamic In-Cabin Calibration: A Mahony SO(3) leveling filter and Principal Component Analysis automatically align the phone's coordinate frame with the vehicle's true forward axis, regardless of whether the phone sits in a dashboard cradle, AC vent mount, or cup holder.
2. Kinetic Shock & Standstill Gating: A discrete jerk variance gate detects sudden pothole impacts and speed breakers, temporarily inflating process noise to prevent road shocks from corrupting the positional state. When stopping at traffic lights, physics-coupled Zero-Velocity Updates (ZUPT) lock velocity to 0 km/h, preventing engine idle vibrations from causing false forward creep.
3. 3D Elevation Map Snapping & Sigmoid Gating: Clamped orthogonal projection to offline OpenStreetMap vector centerlines prevents drift across lanes, while barometric altitude costing disambiguates elevated expressway flyovers from service roads directly underneath. A continuous sigmoidal HDOP gate transitions between GNSS and dead reckoning in under 5 milliseconds with zero UI teleportation.

We validated IDR-Navigator against 64 real-world driving runs from the benchmark IO-VNBD dataset across highway, urban, and tunnel environments. Under the SIH threshold of less than 10% drift relative to distance traveled during complete satellite blackouts, our system achieved a 93.8% pass rate, reaching as low as 0.02% drift on extended 850-meter tunnel runs. The complete system is packaged as an optimized Flutter application running ONNX Runtime INT8 on mobile NPUs at 10 Hz (11.2 ms latency), alongside a standalone pure C++20 SIMD engine operating at 200 Hz (<7 microseconds per cycle) for tactical edge hardware.
```

---

## 4. IDEA DESCRIPTION
* **Field Character Limit:** Maximum 50,000 characters
* **Actual Character Count:** ~15,200 characters (Comprehensive, technically deep, natural engineering narrative)
* **Text to Copy-Paste:**

```text
1. THE REAL-WORLD PROBLEM & MOTIVATION

Global Navigation Satellite Systems (GNSS), including GPS and NavIC, form the backbone of modern logistics, public transit, and emergency response. However, satellite signals require a clear line-of-sight to orbiting constellations. In Indian metropolitan regions, satellite reception drops severely in several routine driving scenarios:
- Mountain tunnels and underground bypass corridors (e.g., Atal Tunnel, Mumbai Coastal Road, Pragati Maidan tunnel).
- Multi-tier flyovers and elevated road decks where lower-level service roads receive shadowed, reflected, or completely occluded satellite signals.
- Dense urban canyons surrounded by high-rise commercial buildings, where signal multipath effects produce erratic 30-to-80 meter coordinate jumps.

When satellite lock drops, standard navigation applications (such as Google Maps or MapmyIndia) freeze vehicle location, show a spinning compass, or guess positions along outdated straight-line trajectories. For delivery fleets (Swiggy, Zomato, Porter), cab aggregators (Ola, Uber), and emergency ambulances, these 30-to-120 second blackouts cause missed highway forks, wrong exits, customer disputes, and response delays.

High-end automotive systems solve this via Dead Reckoning (DR) by hardwiring into the vehicle's Controller Area Network (CAN-bus) or On-Board Diagnostics (OBD-II) port to read wheel speed ticks. However, this approach fails in the real Indian transportation ecosystem:
- Over 70% of commercial delivery vehicles in India are two-wheelers or three-wheelers with no OBD-II port.
- Fleet drivers and private cab owners resist installing intrusive, warranty-voiding third-party dongles.
- Smartphone-only inertial navigation has historically been dismissed because consumer MEMS sensors are noisy. Attempting to calculate position by double-integrating raw accelerometer readings (v = ∫ a dt, p = ∬ a dt²) causes errors to compound quadratically over time (O(t²)), drifting off by more than 140 meters in less than 30 seconds.

Our objective with IDR-Navigator was clear: Build an intelligent, production-ready Dead Reckoning and GNSS Fusion engine that works 100% on standalone consumer smartphones, requires zero external vehicle wiring, and maintains positional tracking with under 10% drift during complete satellite blackouts.


2. OUR CORE TECHNICAL APPROACH & ARCHITECTURAL PIPELINE

IDR-Navigator replaces open-loop mathematical integration with a hybrid deep learning and kinematic fusion pipeline. The complete software architecture operates as a synchronized 6-stage pipeline:

Stage 1: Autonomous In-Cabin Dynamic Alignment
A major flaw in previous mobile DR attempts was assuming the driver places their phone in an upright, perfectly forward-facing mount. In practice, drivers clip phones onto air vents at random tilts, place them flat on center consoles, or toss them into cup holders.
- Gravity Vector Isolation: We employ a Mahony SO(3) non-linear complementary filter running on the raw 100 Hz tri-axial accelerometer and gyroscope data to isolate the gravity vector (g_hat = a_bar / ||a_bar||). This mathematically calculates the instantaneous roll and pitch angles of the phone relative to the Earth's horizontal frame.
- Forward Heading Acquisition: Once leveled, the system applies 2D Principal Component Analysis (PCA) across horizontal acceleration vectors during initial vehicle movement. The primary eigenvector establishes the vehicle’s longitudinal driving axis, decoupling the phone's orientation from vehicle kinematics without requiring manual user calibration.

Stage 2: Kinetic Shock Gating & Standstill Defense
Indian driving surfaces are notorious for rough asphalt, severe potholes, rumblers, and unmarked speed breakers. A standard IMU registering a sharp +3.5g pothole impact will interpret that vertical impulse as rapid forward acceleration, instantly corrupting the navigation state.
- Discrete Jerk Variance Gate: We evaluate the first derivative of acceleration (jerk = da/dt) over a 250 ms rolling window using a Savitzky-Golay differentiation filter. When the jerk variance exceeds our empirically calibrated threshold (tau = 450 m²/s⁶), the system identifies a mechanical road shock rather than driver throttle input. It immediately inflates the Kalman filter process noise matrix (Q × 50), insulating the positional state from shock distortion.
- Physics-Coupled Standstill ZUPT: At red lights and heavy traffic bottlenecks, engine vibrations (15–25 Hz chassis rumble) can fool speed estimation algorithms into accumulating false forward velocity while the car is stationary. We implemented a Zero-Velocity Update (ZUPT) coupled to centrifugal physics: the system verifies whether lateral acceleration matches turn dynamics (a_lat = v · omega_z). If turn rate is zero and total acceleration variance matches stationary idle profiles, forward velocity is hard-clamped to 0.0 km/h, completely eliminating signal-stop creep.

Stage 3: 8-Channel Dilated Causal SE-TCN Speed Estimation Engine
Instead of integrating acceleration, our breakthrough insight was predicting forward vehicle speed directly from tire acoustic resonance, vehicle frame vibrations, and throttle harmonic patterns captured by smartphone inertial sensors.
- Architecture: We designed an 8-channel Temporal Convolutional Network (TCN). The network ingests a 40-step sliding window (4.0 seconds at 10 Hz) of tri-axial acceleration, angular velocity, and estimated jerk.
- Causal Dilated Convolutions: Using 4 residual dilated blocks with dilation factors d in {1, 2, 4, 8}, the network expands its receptive field to capture multi-second vibration patterns without leaking future temporal information.
- Squeeze-and-Excitation (SE) Attention: Channel-wise attention recalibrates feature maps, allowing the network to prioritize whichever axis carries the cleanest structural signal depending on the phone's physical mount.
- Heteroscedastic Uncertainty Head: Crucially, our network features dual output heads. Head 1 outputs the predicted forward speed (v_hat). Head 2 outputs the model's self-estimated variance (sigma²). When driving on smooth highways, uncertainty is minimal (~0.2 m/s²). When driving over rough gravel or cobblestones, the uncertainty head automatically scales upward.

Stage 4: 6-State 3D Neuro-Kalman Fusion Core
We formulate vehicle tracking inside a 6-State Extended Kalman Filter (EKF) with continuous state vector: x = [p_x, p_y, p_z, psi, v, v_z]^T (representing local East, North, altitude coordinates, heading angle, forward velocity, and vertical velocity).
- Dynamic AI Covariance Injection: Classical Kalman filters treat sensor measurement noise (R) as a static constant. In IDR-Navigator, the TCN's heteroscedastic uncertainty (sigma²) directly and continuously parameterizes the filter's inertial measurement covariance matrix: R_INS = max(0.20, sigma²).
- Non-Holonomic Kinematic Constraints (NHC): Cars and two-wheelers do not slide sideways like hovercrafts under normal driving conditions. We enforce strict NHC virtual measurements (v_lateral ≈ 0 and v_vertical ≈ 0 relative to heading), analytically preventing lateral crabbing and suppressing vertical altitude drift.

Stage 5: Offline 3D Map-Matching & Seamless Blackout Transition
Even the best dead reckoning accumulates drift over kilometers without bounding constraints. We combine local spatial vector mapping with a continuous handoff mechanism.
- Clamped Orthogonal Vector Snapping: The system bundles an offline OpenStreetMap (OSM) vector road database stored locally in compact GeoJSON format (~15 MB per metropolitan district). The EKF state estimate is projected onto the nearest road segment centerline.
- 3D Altimetry Disambiguation: Multi-tier flyovers present a major challenge where elevated expressway lanes run directly above ground-level service roads. Standard 2D map matchers jump wildly between upper and lower roads. We implement a 3D cost function: J = d_lateral + 2.5 |Delta z_barometric| + 6.0 |Delta psi|. By cross-referencing barometric pressure altitude changes against the vector road grade profile, the system reliably locks onto the elevated deck.
- Continuous Sigmoidal HDOP Gate: Binary switches between GPS and dead reckoning cause jarring position jumps. We designed a continuous sigmoid weighting function: lambda(h) = 1 / (1 + exp(-1.2 * (h - 3.5))), where h is the GNSS Horizontal Dilution of Precision (HDOP). As satellite geometry degrades upon entering a tunnel, GNSS measurement trust diminishes smoothly to zero in under 5 milliseconds, enabling a transparent transition to pure dead reckoning.

Stage 6: Real-Time Mobile Cockpit HUD
A 60 FPS vector canvas built in Flutter renders smooth real-time telemetry. Features include:
- A rotating 3D vehicle indicator aligned with the vehicle’s true heading rather than noisy magnetic compass readings.
- Live multi-channel oscilloscopes showing real-time accelerometer and gyroscope traces.
- Diagnostic indicators displaying current HDOP, active satellite count, Kalman filter covariance, and instant manual simulation switches ("Trigger Tunnel Blackout", "Simulate Pothole Shock") for demonstration and testing.


3. DUAL-TARGET DEPLOYMENT ARCHITECTURE

To maximize practical applicability, we implemented the system across two complementary tiers:
- Tier 1: Consumer Mobile Application (Flutter + ONNX Runtime Mobile)
  Targeted at commercial fleet drivers and commuters running Android 8.0+ or iOS 14+. The trained 2.1-million parameter SE-TCN is quantized to INT8 precision (binary footprint: 2.1 MB). Executed via ONNX Runtime Mobile with NNAPI hardware acceleration, the entire inference pass takes just 11.2 milliseconds on mid-range smartphone NPUs, easily fitting within our 10 Hz (100 ms) mobile update budget with low battery consumption.
- Tier 2: High-Frequency Edge Core (Pure C++20 + Eigen 3.4 SIMD)
  Targeted at embedded vehicle computers, telematics gateways, and tactical Fiber Optic Gyroscope (FOG) IMUs. Built in modern C++20 with zero dynamic memory allocation on the hot path, leveraging Eigen SIMD vectorization. A complete EKF predict-update step executes in under 7 microseconds (<0.007 ms), capable of running at over 200 Hz for high-speed industrial robotics and autonomous transit applications.


4. EMPIRICAL BENCHMARKS & EXPERIMENTAL VALIDATION

We rigorously evaluated IDR-Navigator against real-world vehicular sensor logs from the benchmark IO-VNBD (Inertial Odometry Vehicle Navigation Benchmark Dataset). The evaluation suite spans 64 comprehensive driving sequences covering over 120 kilometers of highway driving, tight urban city streets, multi-level intersections, and extended highway tunnel runs.

Key Benchmark Findings:
- SIH Benchmark Criterion (<10% Drift Threshold): The official hackathon metric requires maximum positional drift to remain below 10% of total distance traveled during GNSS denial. IDR-Navigator achieved a 93.8% pass rate across the 64 validation runs (60 out of 64 runs passed comfortably).
- Best-Case Performance: On an extended 850-meter highway tunnel sequence with 100% satellite blackout, our system drifted by only 0.17 meters, representing an exceptional 0.02% drift rate.
- Fleet-Wide Average Drift: Across the entire vehicle test suite, the mean drift was 2.1% of distance traveled.
- Velocity Estimation Accuracy: The SE-TCN speed engine achieved a Mean Absolute Error (MAE) of 0.50 m/s across unseen vehicle trips, representing an 82.5% error reduction compared to classical accelerometer integration.
- Quality Assurance: The repository includes 55 automated unit, integration, and UI widget tests covering vector rotations, Mahony filter convergence, EKF covariance stability, and map snapping math.


5. FEASIBILITY, COMMERCIAL VIABILITY & SOCIAL IMPACT

- Zero Retrofitting Cost: Existing commercial dead reckoning devices cost anywhere from INR 8,000 to INR 25,000 per vehicle due to specialized OBD hardware and CAN installation labor. IDR-Navigator costs INR 0 in additional hardware, requiring only an app download or SDK integration into existing logistics software.
- High Social & Economic Value: In high-stakes emergency situations, every second counts. Ambulances navigating multi-level flyovers and congested tunnels can maintain uninterrupted turn-by-turn guidance without navigation blackouts. For delivery platforms processing millions of daily orders, continuous navigation prevents incorrect turns and reduces dead kilometers.
- National Self-Reliance: The system is designed to fuse seamlessly with India's indigenous NavIC constellation alongside standard GPS, reinforcing domestic navigation robustness in border corridors, remote mountainous regions, and underground transit infrastructure.
```

---

## 5. IDEA TEMPLATE (PDF UPLOAD)
* **Field Requirement:** "Upload Idea template in pdf format. Upto 10MB Download Template"
* **Instructions for Generating & Uploading Your PDF:**

1. Your repository already contains the complete, verified 6-slide presentation deck:
   📁 **[`e:\inventor\SIH2026_IDR_Navigator_Submission.pptx`](file:///e:/inventor/SIH2026_IDR_Navigator_Submission.pptx)**
2. To convert it into the required PDF:
   - **Method A (PowerPoint / LibreOffice):** Open the PPTX file and select **File ➔ Export ➔ Create PDF/XPS** (or **Save As ➔ PDF**). Name it `SIH2026_IDR_Navigator_Submission.pdf`.
   - **Method B (Automated Script):** Run the project script:
     ```powershell
     python scripts/generate_sih_pptx.py
     ```
3. Ensure the generated PDF is under 10 MB (the current PPTX is ~691 KB, so the exported PDF will easily be under 2 MB).
4. Click **Choose File** on the portal form and select the exported `SIH2026_IDR_Navigator_Submission.pdf`.

---

## 6. YOUTUBE LINK (OPTIONAL)
* **Field Requirement:** "Youtube Link: (Optional)"
* **Recommendations:**
  - If you have recorded a video demonstration (e.g. of the running Flutter Cockpit HUD or the MP4 demo in your repo: [`Record_2026-09-25-18-51-20_281cd788c2fa2c82e5415ffa998b613e.mp4`](file:///e:/inventor/Record_2026-09-25-18-51-20_281cd788c2fa2c82e5415ffa998b613e.mp4)):
    Upload it as an **Unlisted** or **Public** video on YouTube and paste the link here.
  - If you do not have a YouTube link ready right now:
    **Leave this field completely blank.** It is explicitly marked as *(Optional)* on the portal and will not block your submission.
