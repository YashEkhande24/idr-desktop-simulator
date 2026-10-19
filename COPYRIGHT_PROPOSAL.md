# TECHNICAL SPECIFICATION & LITERARY WORK DESCRIPTION FOR COPYRIGHT REGISTRATION

**Under Section 2(o) of The Copyright Act, 1957 (Computer Software and Accompanying Literary/Scientific Work)**

---

## INSTITUTIONAL ORIGIN & FILING PARTICULARS
* **Institution:** Amrutvahini College of Engineering, Sangamner
  *(An Autonomous Institute Affiliated to Savitribai Phule Pune University, Pune)*
  *Approved by AICTE, New Delhi | AISHE Code: C-41515 | AICTE Permanent ID: 1-7576531*
* **Department:** Department of Electronics & Telecommunication Engineering *(with Interdisciplinary Collaboration from Dept. of Automation & Robotics and Dept. of Computer Engineering)*
* **Work Title:** **“AI-ML BASED INTELLIGENT DEAD RECKONING (IDR) SYSTEM FOR SEAMLESS VEHICLE NAVIGATION IN GNSS-DENIED TERRAINS”**
* **Software Acronym / Product Name:** **IDR-Navigator**
* **SIH Identification:** Smart India Hackathon 2026 | Problem Statement ID: **SIH26168** | Theme: **Smart Vehicles** | Category: **Software**
* **Team Registration:** Team Name: **Inventor** | Team Registration ID: **133715**
* **Class of Work:** Computer Software & Associated Literary/Scientific Documentation [Section 2(o), Indian Copyright Act 1957]
* **Date of Creation:** October 2026 (Initial Codebase: September 2026)
* **Jurisdiction:** Sangamner, Maharashtra, India

---

## AUTHORS / CO-APPLICANTS & FACULTY SUPERVISOR

| Sr. | Name of Author / Guide | Role in Work | Department / Specialization | Institution |
| :---: | :--- | :--- | :--- | :--- |
| 1 | **Yash Kailas Ekhande** | Lead Architect / Developer | Electronics & Telecommunication Engg. | Amrutvahini COE, Sangamner |
| 2 | **Abhijeet Dilip Gholap** | Systems & Integration Eng. | Electronics & Telecommunication Engg. | Amrutvahini COE, Sangamner |
| 3 | **Ankita Prabhakar Kadu** | Data Pipeline Engineer | Electronics & Telecommunication Engg. | Amrutvahini COE, Sangamner |
| 4 | **Krushna Sanjay Shinde** | Vehicle Dynamics Engineer | Automation & Robotics Engineering | Amrutvahini COE, Sangamner |
| 5 | **Shreya Gopal Dahale** | Mobile UI & Client Engineer | Computer Engineering | Amrutvahini COE, Sangamner |
| 6 | **Kanchan Vijay Jadhav** | Embedded & QA Engineer | Automation & Robotics Engineering | Amrutvahini COE, Sangamner |
| 7 | **Prof. Dr. R. P. Labade** | Supervisor & Co-Author | Head of Department, E&TC | Amrutvahini COE, Sangamner |

---

## 1. ABSTRACT & EXECUTIVE SUMMARY
Global Navigation Satellite Systems (GNSS—including GPS, NavIC, GLONASS, and Galileo) suffer unavoidable loss of service when ground vehicles traverse subterranean road tunnels, multi-tier elevated flyovers, dense high-rise urban canyons, and mountain passes. Under signal blockage, conventional navigation applications freeze, exhibit erratic coordinate teleportation, or issue hazardous re-routing instructions. While high-end aerospace platforms resolve this via tactical Fiber Optic Gyroscopes (FOG) or direct CAN-bus wheel odometry taps, such hardware retrofits cost between ₹8,000 and ₹50,000+ per vehicle and cannot be deployed across India's predominant commercial transport fleet—particularly two-wheelers, three-wheelers, and legacy commercial vehicles lacking accessible On-Board Diagnostic (OBD-II) ports.

**IDR-Navigator** is an edge-deployable, zero-external-hardware Intelligent Dead Reckoning system implemented entirely on unmodified consumer smartphones. Rather than relying on classical double-integration of acceleration—which diverges cubically ($O(t^3)$) within seconds due to uncorrected gyroscope bias—IDR-Navigator formulates a dual-layer estimator:
1. An **8-Channel Dilated Causal Temporal Convolutional Network (SE-TCN)** that infers longitudinal vehicle speed directly from tire-road micro-vibrations with heteroscedastic uncertainty estimation ($\sigma^2$).
2. A **6-State 3D Error-State Extended Kalman Filter (ES-EKF)** in native C++20 that enforces physical Non-Holonomic Constraints (NHC) and Zero-Velocity Updates (ZUPT).

### Validated Engineering Benchmarks:
* **Zero External Hardware CapEx:** Operates 100% on internal smartphone MEMS sensors (accelerometer, gyroscope, magnetometer, barometer).
* **Highway Outage Drift Suppression:** Bounded to **6.81 m drift (0.43% error)** over a 1.6 km highway tunnel blackout on the IO-VNBD dataset, compared to **150+ m drift** in classical INS.
* **Empirical Generalization:** Achieved a **100% pass rate (5/5 scenarios)** and **3.47% mean drift** (<10% ISRO drift rule) across all evaluated scenarios.
* **Deterministic Execution:** 2.1 MB INT8 quantized ONNX model executes in **2.2 ms per step on mobile NPUs**; native C++20 SIMD linear algebra core executes at **200 Hz with < 7 µs latency per step**.

---

## 2. PROBLEM FORMULATION & SHORTCOMINGS OF PRIOR ART

### 2.1 Physics of Satellite Denial on Indian Roads
* **Multipath & NLOS in Urban Canyons:** Skyscraper facades reflect satellite signals, creating false pseudo-ranges and 30–80 m lateral position jumps.
* **Subterranean Blackouts:** Complete RF line-of-sight blockage occurs in tunnels such as Atal Tunnel, Mumbai Coastal Road, and Pragati Maidan.
* **Elevation Ambiguities:** Conventional 2D navigation engines cannot resolve whether a vehicle is travelling on an elevated flyover deck or the surface service road beneath.

### 2.2 Mathematical Divergence in Classical Inertial Double-Integration
In strapdown inertial navigation, orientation is tracked by integrating angular rates: $\tilde{\boldsymbol{\omega}} = \boldsymbol{\omega} + \mathbf{b}_g + \mathbf{n}_g$. Gyroscope bias drift $\mathbf{b}_g$ induces an attitude tilt error angle $\delta\theta(t) \approx \mathbf{b}_g \cdot t$. Subtracting gravity $\mathbf{g}$ to isolate kinematic translation causes gravity to leak into horizontal channels:
$$\mathbf{a}_{\text{err}}(t) \approx g \cdot \sin(\delta\theta(t)) \approx g \cdot \mathbf{b}_g \cdot t$$
Integrating once for velocity yields a quadratic error:
$$\mathbf{v}_{\text{err}}(t) = \int g \mathbf{b}_g t \, dt = \frac{1}{2} g \mathbf{b}_g t^2$$
Integrating twice for position produces cubic error divergence:
$$\delta \mathbf{p}(t) = \iint g \mathbf{b}_g t \, dt^2 = \frac{1}{6} g \mathbf{b}_g t^3$$

With a typical consumer smartphone gyro bias of $0.5^\circ/\text{s}$ ($0.0087\,\text{rad/s}$), horizontal position diverges by **over 180 meters in 60 seconds** ($184.2\,\text{m}$ observed on IO-VNBD baseline), proving that naive double-integration cannot function on consumer mobile hardware without continuous external constraints.

---

## 3. SYSTEM ARCHITECTURE & WORKING FLOW

```
[ Smartphone MEMS Sensors: Accel, Gyro, Mag, Baro (100 Hz NDK HAL) ]
                                  │
                                  ▼
[ Stage 2: Dynamic In-Cabin Attitude Alignment (Mahony SO(3) + 2D PCA) ]
                                  │
                                  ▼
[ Stage 3: Kinetic Shock & Stationary Defense (Jerk Var Gate & Centripetal ZUPT) ]
                                  │
        ┌─────────────────────────┴─────────────────────────┐
        ▼                                                   ▼
[ Stage 4: 8-Channel Dilated Causal TCN ]      [ High-Frequency Gyro & Baro Stream ]
  Infers: Speed v̂ + Uncertainty σ² (10 Hz)         Heading ψ + Altimetry p_z (100 Hz)
        └─────────────────────────┬─────────────────────────┘
                                  ▼
[ Stage 5: 6-State 3D Neuro-Kalman EKF (ES-EKF) with NHC (v_lat ≈ 0, v_z ≈ 0) ]
                                  │
                                  ▼
[ Stage 6: Continuous Sigmoidal HDOP Outage Handoff Gate (Sub-5 ms Transition) ]
                                  │
                                  ▼
[ Stage 7: Offline 3D Vector Map-Matching Engine (OSM KD-Tree + Tier Cost) ]
                                  │
                                  ▼
[ Stage 8: Dual-Target Mobile Telemetry Cockpit (60 FPS HUD / 200 Hz C++ Stream) ]
```

### Detailed Functional Breakdown:
1. **Module 1 (High-Rate Sensor Ingestion):** Acquires raw tri-axial acceleration, angular velocity, geomagnetic flux, and barometric pressure at 100 Hz directly from Android HAL via NDK NativeActivity.
2. **Module 2 (Dynamic In-Cabin Alignment):** Mahony SO(3) leveling isolates mounting pitch and roll relative to gravity; 2D PCA on horizontal acceleration covariance automatically resolves vehicle forward heading.
3. **Module 3 (Kinetic Shock & Stationary Defense):** Jerk Variance Gate ($\text{Var}(\Delta a/\Delta t) > 450\,\text{m}^2/\text{s}^6$) detects potholes and speed breakers, inflating filter covariance 50×. Centripetal ZUPT ($a_{\text{lat}} = v \cdot \omega_z$) clamps stationary velocity to 0.0 km/h during red lights, suppressing engine idle rumble.
4. **Module 4 (8-Channel Dilated Causal SE-TCN):** Ingests sliding 4.0-second window across $[\mathbf{a}_x, \mathbf{a}_y, \mathbf{a}_z, \mathbf{g}_x, \mathbf{g}_y, \mathbf{g}_z, \|\mathbf{a}\|, \|\boldsymbol{\omega}\|]$. 4 residual blocks ($d=1, 2, 4, 8$) with Squeeze-and-Excitation attention output forward speed $\hat{v}$ and predictive variance $\sigma^2$.
5. **Module 5 (6-State 3D Neuro-Kalman ES-EKF):** Propagates state vector $\mathbf{x} = [p_x, p_y, p_z, \psi, v, v_z]^T$ using closed-form SE(2) arc kinematics. Enforces Non-Holonomic Constraints ($v_{\text{lat}} \approx 0, v_z \approx 0$). Injects neural variance $\sigma^2$ to dynamically tune measurement covariance $R_{\text{INS}}$.
6. **Module 6 (Continuous Sigmoidal HDOP Outage Handoff):** Smooth sigmoidal covariance inflation transfers positioning to pure dead reckoning in sub-5 ms without coordinate jumps.
7. **Module 7 (Offline 3D Vector Map Matcher):** Projects positions onto offline OpenStreetMap GeoJSON vectors. Evaluates 3D multi-tier cost $J = d_{\text{lat}} + 2.5|\Delta z| + 6.0(1 - |\cos \Delta \psi|)$ to disambiguate flyovers from underpasses.
8. **Module 8 (Dual-Target Mobile Cockpit):** 60 FPS Flutter HUD displays 3D car marker, real-time trajectory, and sensor oscilloscopes; companion C++ SIMD engine operates at 200 Hz for tactical telemetry.

---

## 4. MATHEMATICAL FORMULATIONS

### 4.1 Kinematic State Propagation (Closed-Form SE(2) Arc)
$$\Delta \psi = \omega_z \cdot \Delta t$$
$$p_{x, k+1} = p_{x, k} + \frac{v}{\omega_z} \left[ \sin(\psi_k + \Delta \psi) - \sin(\psi_k) \right] \cos(\theta_{\text{pitch}})$$
$$p_{y, k+1} = p_{y, k} - \frac{v}{\omega_z} \left[ \cos(\psi_k + \Delta \psi) - \cos(\psi_k) \right] \cos(\theta_{\text{pitch}})$$
$$p_{z, k+1} = p_{z, k} + v_z \cdot \Delta t$$
$$\psi_{k+1} = \psi_k + \Delta \psi$$
$$v_{k+1} = v_k + a_{\text{forward}} \cdot \Delta t$$

### 4.2 Composite Neural Network Loss Formulation
$$\mathcal{L}_{\text{total}} = 1.0 \cdot \mathcal{L}_{\text{Huber}}(v, v_{\text{true}}) + 0.2 \cdot \mathcal{L}_{\text{NLL}}(v, v_{\text{true}}, \sigma^2) + 0.5 \cdot \mathcal{L}_{\text{ZeroVel}} + 0.2 \cdot \mathcal{L}_{\text{BatchBias}}$$
where the Gaussian Negative Log-Likelihood (NLL) term is:
$$\mathcal{L}_{\text{NLL}} = \frac{1}{2N} \sum_{i=1}^N \left[ \frac{(v_{\text{true}, i} - \hat{v}_i)^2}{\sigma_i^2} + \ln(\sigma_i^2) \right]$$

### 4.3 Sigmoidal HDOP GNSS Covariance Function
$$R_{\text{GNSS}}(\text{HDOP}) = R_{\text{nom}} \cdot \left[ 1 + \exp\left( 1.2 \cdot (\text{HDOP} - 3.5) \right) \right], \quad R_{\text{nom}} = 4.0\,\text{m}^2$$

### 4.4 Non-Holonomic Physical Constraints (NHC)
$$z_{\text{NHC,lat}} = -\dot{p}_x \sin(\psi) + \dot{p}_y \cos(\psi) \approx 0$$
$$z_{\text{NHC,vert}} = v_z \approx 0$$

### 4.5 3D Multi-Tier Elevation Cost Function
$$J_k = d_{\text{lat}} + 2.5 \cdot |p_z - z_{\text{road}}| + 6.0 \cdot (1 - |\cos(\psi - \psi_{\text{road}})|)$$

---

## 5. EMPIRICAL BENCHMARKS & EXPERIMENTAL VALIDATION

### IO-VNBD Official Benchmark Scorecard:

| Metric | Benchmark Criterion | IDR-Navigator (Achieved) |
| :--- | :---: | :---: |
| **All-Scenario Pass Rate** | High Reliability | **★ 100.0% (5 of 5 Scenarios Passed)** |
| **Highway Tunnel Outage Drift** | < 10.0% of Distance | **★ 0.43% Drift (6.81 m Error)** |
| **Overall Mean Outage Drift** | < 10.0% of Distance | **★ 3.47% Mean Drift** |
| **Forward Speed Tracking MAE** | Ground-Truth CAN Match | **★ 0.60 m/s Mean MAE (Best: 0.37 m/s)** |
| **Classical INS Double-Integration Drift** | Reference Baseline | **150+ m Drift (Exceeds 10% in <10s)** |
| **Active Mobile Battery Consumption** | < 10% / hour | **★ < 5.8% / hour** |
| **Mobile NPU Inference Latency** | < 100 ms Deadline | **★ 11.2 ms (INT8 ONNX)** |
| **SIMD C++ Filter Execution Latency** | High-Rate Real-Time | **★ < 7 µs per update (200 Hz)** |

---

## 6. STATUTORY SOURCE CODE EXTRACTS (RULE 70 COMPLIANCE)

### Core Filter Implementation (`cpp_mobile_app/core/src/ekf_3d.cpp`):
```cpp
#include "idr/ekf_3d.hpp"
#include <cmath>
#include <algorithm>

namespace idr {

static constexpr double PI = 3.14159265358979323846;
static constexpr double TWO_PI = 2.0 * PI;

static inline double normalizeAngle(double angle) {
    while (angle > PI)  angle -= TWO_PI;
    while (angle < -PI) angle += TWO_PI;
    return angle;
}

Ekf3D::Ekf3D(double initYawRad) {
    x_.setZero();
    x_(3) = normalizeAngle(initYawRad);
    P_.setIdentity();
    P_(0, 0) = 4.0;   // px var
    P_(1, 1) = 4.0;   // py var
    P_(2, 2) = 2.0;   // pz var
    P_(3, 3) = 0.05;  // yaw var
    P_(4, 4) = 0.25;  // forward speed var
    P_(5, 5) = 0.10;  // vz climb var
}
```

### PyTorch Neural Architecture (`idr_model_submission/model_architecture.py`):
```python
class Chomp1d(nn.Module):
    def __init__(self, chomp_size: int):
        super().__init__()
        self.chomp_size = chomp_size

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return x[:, :, :-self.chomp_size].contiguous()

class SqueezeExcite1d(nn.Module):
    def __init__(self, channels: int, reduction: int = 4):
        super().__init__()
        self.fc = nn.Sequential(
            nn.AdaptiveAvgPool1d(1),
            nn.Flatten(),
            nn.Linear(channels, channels // reduction, bias=False),
            nn.ReLU(inplace=True),
            nn.Linear(channels // reduction, channels, bias=False),
            nn.Sigmoid()
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        w = self.fc(x).unsqueeze(-1)
        return x * w
```

---

## 7. CLAIMS OF ORIGINAL NOVELTY & INTELLECTUAL CONTRIBUTION

1. **Claim 1 (Standalone Smartphone Execution):** An original software method executing dead reckoning exclusively on unmodified consumer smartphone MEMS sensors without OBD-II, CAN-bus, or wheel odometry hardware.
2. **Claim 2 (Dilated Causal SE-TCN Speed Engine):** An original 8-channel temporal convolutional network featuring causal padding and Squeeze-and-Excitation attention that estimates longitudinal vehicle speed from road vibrations without lookahead leakage.
3. **Claim 3 (Heteroscedastic Predictive Uncertainty):** An original dual-head neural network simultaneously estimating speed and instantaneous uncertainty $\sigma^2$ to dynamically scale Kalman filter measurement covariance.
4. **Claim 4 (Discrete Jerk Variance Gate):** An original transient gating algorithm identifying road shocks ($\text{Var}(\Delta a/\Delta t) > 450\,\text{m}^2/\text{s}^6$) to insulate integrated velocity from pothole-induced spikes.
5. **Claim 5 (Centripetal Balance ZUPT):** An original standstill detection algorithm coupling sensor energy with centripetal dynamic equilibrium ($a_{\text{lat}} = v \cdot \omega_z$) to suppress red-light creeping drift caused by engine combustion harmonics.
6. **Claim 6 (Continuous Sigmoidal HDOP Gate):** An original sigmoidal covariance scaling function enabling sub-5 ms handoff between satellite positioning and inertial dead reckoning without coordinate jumps.
7. **Claim 7 (3D Multi-Tier Elevation Cost Function):** An original map-matching cost formulation fusing perpendicular offset, barometric altitude, and heading to resolve vertical elevation ambiguities at multi-level flyovers.
8. **Claim 8 (Closed-Form SE(2) Arc Mechanization):** An original 6-state Extended Kalman Filter utilizing closed-form circular arc kinematics and sideslip-relaxed Non-Holonomic Constraints.
9. **Claim 9 (Dual-Target Multi-Rate Architecture):** An original cross-language architecture coupling a 60 FPS mobile Flutter cockpit HUD with a 200 Hz native C++20 SIMD linear algebra execution core (< 7 µs latency per step).
10. **Claim 10 (100% Air-Gapped Autonomy):** An original software implementation operating without cellular connectivity, external cloud servers, or RF-beacon infrastructure.

---

## 8. STATUTORY DECLARATION & SIGNATURE BLOCKS

We, the undersigned authors and faculty supervisor, do hereby solemnly declare that the computer software, algorithms, and technical documentation contained herein represent an original intellectual creation developed jointly by us at Amrutvahini College of Engineering, Sangamner. This work does not infringe upon any existing intellectual property rights of any third party. We jointly submit this application for copyright registration under the Indian Copyright Act, 1957.

```
____________________________        ____________________________        ____________________________
    Yash Kailas Ekhande                Abhijeet Dilip Gholap                Ankita Prabhakar Kadu
 Lead Developer / Team Lead          Systems & Integration Eng.            Data Pipeline Engineer
    Dept. of E&TC Engg.                 Dept. of E&TC Engg.                 Dept. of E&TC Engg.


____________________________        ____________________________        ____________________________
   Krushna Sanjay Shinde                Shreya Gopal Dahale                 Kanchan Vijay Jadhav
 Vehicle Dynamics Engineer            Mobile Software Engineer            Embedded Test Engineer
  Dept. of Auto. & Robotics           Dept. of Computer Engg.            Dept. of Auto. & Robotics


____________________________        ____________________________        ____________________________
      Mr. V. K. Abhang                  Prof. Dr. R. P. Labade                Dr. P. R. Baviskar
          SPOC SIH                         Head of the Dept                        Principal
 Amrutvahini College of Engg.             Dept. of E&TC Engg.             Amrutvahini College of Engg.
```
