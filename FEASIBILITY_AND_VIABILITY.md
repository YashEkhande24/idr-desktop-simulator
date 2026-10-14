# SMART INDIA HACKATHON (SIH 2026) – SINGLE SLIDE BLUEPRINT
## Slide 4: FEASIBILITY AND VIABILITY
### Problem Statement: AI-ML based Intelligent Dead Reckoning system for seamless navigation (SIH26168)
### Team: Inventor (Team ID: 133715)

---

> [!IMPORTANT]
> **STRICT COMPLIANCE WITH OFFICIAL SIH 2026 TEMPLATE POINTERS:**
> This slide strictly adheres to the 3 mandatory pointers defined on Slide 4 of the official SIH template:
> 1. **Analysis of the feasibility of the idea** *(Left 1/3: Deep Neural Model Architecture + Top Right: Compute, Battery & Cost Feasibility)*
> 2. **Potential challenges and risks** *(Ground Indian road realities: Potholes, idle vibrations, multi-level flyovers)*
> 3. **Strategies for overcoming these challenges** *(Deterministic algorithmic defenses: Jerk variance gate, centripetal ZUPT, 3D altimetry cost)*
>
> **Spatial Guarantee:** Built as a balanced **3-Column Widescreen Layout (33% | 34% | 33%)** so the AI Model Architecture, the Benchmark Trajectory Graph, and the Risk Matrix all fit comfortably without text overcrowding.

---

# 1. VISUAL SLIDE LAYOUT WIREFRAME (16:9 SINGLE SLIDE)

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  ╭─────────────────╮                                                                                                   ╭────────────╮  │
│  │    INVENTOR     │                                     FEASIBILITY AND VIABILITY                                     │  SIH 2026  │  │
│  │ Team ID: 133715 │                                                                                                   │  SIH26168  │  │
│  ╰─────────────────╯                                                                                                   ╰────────────╯  │
├────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ ┌───────────────────────────────┐ ┌───────────────────────────────────────┐ ┌────────────────────────────────────────────────────────┐ │
│ │ 🧠 COLUMN 1: AI MODEL ENGINE  │ │ 📊 COLUMN 2: BENCHMARK VALIDATION     │ │ 🛡️ COLUMN 3: FEASIBILITY, RISKS & MITIGATION         │ │
│ │ (Technical Feasibility Proof) │ │ (Empirical Proof of Concept)          │ │ (Pointers 1, 2 & 3: Compute & Risk Matrix)           │ │
│ ├───────────────────────────────┤ ├───────────────────────────────────────┤ ├────────────────────────────────────────────────────────┤ │
│ │ • 8-Channel Kinematic Tensor: │ │ ┌───────────────────────────────────┐ │ │ ▼ COMPUTATIONAL & OPERATIONAL FEASIBILITY              │ │
│ │   - 3-axis accel (gravity-free│ │ │       IO-VNBD BENCHMARK PLOT      │ │ │ • On-Device Latency: < 4.5ms NPU / 11.2ms Mobile     │ │
│ │   - 3-axis angular rates (ω)  │ │ │   [Visual Trajectory & Speed]     │ │ │ • Battery Consumption: < 5.8% / hour (All-day nav)   │ │
│ │   - 2 Euclidean vector norms  │ │ │   • Green: IDR Lane-Hold (0.02%)  │ │ │ • Memory Footprint: < 45 MB RAM | Storage: ~15 MB    │ │
│ │ • 4-Stage Dilated Causal TCN: │ │ │   • Red: Classical INS (+194m)    │ │ │ • Commercial CapEx: ₹0 (Eliminates ₹8k–₹15k OBD)     │ │
│ │   - Dilations d in {1, 2, 4, 8│ │ └───────────────────────────────────┘ │ ├────────────────────────────────────────────────────────┤ │
│ │   - Kernel K = 3; strictly    │ │                                       │ │ ▼ TOP 3 GROUND RISKS & DETERMINISTIC DEFENSES          │ │
│ │     causal (zero future leak) │ │ • 850m Tunnel Outage (S-Vta23):       │ │                                                        │ │
│ │ • 31-Step Receptive Field:    │ │   - Baseline (INS): 184m drift (21.7%)│ │ 1. Potholes & Road Shocks (+3.5g impact spikes):       │ │
│ │   - 3.1s temporal history     │ │   - Proposed (Only DR): 0.42m (0.05%) │ │    ➔ Savitzky-Golay Jerk Gate (τ=450 m²/s⁶) flags     │ │
│ │ • Squeeze-and-Excitation (SE):│ │   - Proposed (Lane-Hold): 0.17m(0.02%)│ │      shock; inflates Kalman Q × 50 to coast.           │ │
│ │   - Channel attention (r = 4) │ │ • Speed Regression Precision:         │ │                                                        │ │
│ │ • Dual Heteroscedastic Heads: │ │   - MAE: 0.50 m/s (82.5% error cut)   │ │ 2. Traffic Signal Engine Idle (15–25 Hz rumble creep): │ │
│ │   1. Forward speed v̂ (m/s)    │ │   - RMSE: 0.68 m/s                    │ │    ➔ Centripetal ZUPT (a_lat = v·ω) clamps velocity    │ │
│ │   2. Log-variance s = log(σ²) │ │ • SIH Benchmark Criteria:             │ │      strictly to 0.0 km/h at red lights.               │ │
│ │ • Quantization & Footprint:   │ │   - Pass Rate: 93.8% (60/64 passed)   │ │                                                        │ │
│ │   - 2.09M Parameters          │ │   - Max Allowed Drift: < 10.0% [PASS] │ │ 3. Multi-Level Flyovers (Upper deck vs lower road flip)│ │
│ │   - 8.4 MB FP32 ➔ 2.1 MB INT8 │ │   - Average Fleet Drift: 2.1% [PASS]  │ │    ➔ 3D Altimetry Cost: J = d_lat + 2.5|Δz| + 6|Δψ|    │ │
│ └───────────────────────────────┘ └───────────────────────────────────────┘ └────────────────────────────────────────────────────────┘ │
├────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ ★ EDGE & FIELD READINESS : 136+ Automated Unit/E2E Tests | Field-Tested on Katraj Tunnel & Mumbai-Pune Expressway (OnePlus Nord CE4) │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

# 2. EXACT SLIDE TEXT (ORGANIZED BY THE 3 TEMPLATE POINTERS)

### Pointer 1: Analysis of the Feasibility of the Idea

#### Column 1: AI Model Architecture (Technical Feasibility Proof)
* **Kinematic Input Tensor**: Ingests $4.0\text{s}$ window ($40$ steps at $10\text{ Hz}$) across 8 features: dynamic linear acceleration ($\mathbf{a} - \mathbf{g}$), 3-axis angular rates ($\boldsymbol{\omega}$), and 2 rotation-invariant norms ($\|\mathbf{a}\|, \|\boldsymbol{\omega}\|$).
* **Dilated Causal Temporal Convolutions (TCN)**: 4 residual stages with dilation factors $d \in \{1, 2, 4, 8\}$ and kernel size $K = 3$.
* **31-Step Receptive Field**: Exactly $1 + \sum_{l=0}^3 (K - 1)d_l = 1 + 2(1+2+4+8) = 31\text{ timesteps}$ ($3.1\text{ seconds}$ of inertial context). Strictly causal left-padding eliminates future data leakage.
* **Squeeze-and-Excitation (SE) Attention**: Channel attention mechanism ($r = 4$ reduction ratio) automatically isolates structural chassis vibrations from phone mount rattle.
* **Dual Heteroscedastic Output Heads**: Jointly predicts instantaneous speed $\hat{v}$ and predictive log-variance $s = \log(\sigma^2)$, trained via Gaussian Negative Log-Likelihood (NLL) loss.
* **Model Footprint & INT8 Quantization**: 2.09M parameters | 8.4 MB (FP32) compressed to **2.1 MB in INT8 precision**.

#### Column 3 (Top): Resource & Operational Feasibility
* **Ultra-Low Latency**: **$< 4.5\text{ ms}$** raw NPU model execution / **$11.2\text{ ms}$** end-to-end mobile pipeline. Header-only C++20 SIMD core runs in **$< 7\,\mu\text{s}$ at $200\text{ Hz}$**.
* **Minimal Energy Drain**: Draws **$< 5.8\%$ battery capacity per hour** of active driving.
* **Memory & Storage**: Requires **$< 45\text{ MB}$ RAM**; offline vector maps take just **$\approx 15\text{ MB}$ per city**.
* **Zero Hardware CapEx**: Runs 100% on standard consumer smartphone MEMS, eliminating **₹8,000 to ₹15,000** aftermarket OBD-II dongles.

---

### Pointers 2 & 3: Potential Challenges, Risks & Deterministic Mitigations

#### Column 3 (Bottom): Top 3 Ground Risks & Proven Mitigations

* **Challenge 1: Potholes & Road Shocks (+3.5g impact spikes)**
  * *Root Risk:* Vertical impact forces couple into horizontal channels, tricking double-integration into a $>20\text{m}$ false forward jump.
  * *Mitigation:* **5-Point Savitzky-Golay Jerk Variance Gate** ($\tau = 450\text{ m}^2/\text{s}^6$) flags shock transients and inflates Kalman process noise $\mathbf{Q} \times 50$ for 300ms, holding state on vehicle momentum.

* **Challenge 2: Traffic Signal Engine Idle (15–25 Hz chassis rumble)**
  * *Root Risk:* Engine vibrations fool neural speed models into predicting continuous forward velocity while stationary at red lights.
  * *Mitigation:* **Centripetal-Coupled Standstill ZUPT** verifies centrifugal balance ($a_{\text{lat}} = v \cdot \omega_z$). Clamps velocity strictly to $0.0\text{ km/h}$ whenever turning rate and lateral forces are zero.

* **Challenge 3: Multi-Level Flyovers (Upper deck vs lower road flip)**
  * *Root Risk:* Identical $(x, y)$ coordinates cause standard 2D map matchers to flip erratically between upper and lower decks.
  * *Mitigation:* **3D Altimetry Cost Function** ($J = d_{\text{lat}} + 2.5|\Delta z_{\text{baro}}| + 6|\Delta \psi|$) fuses barometric pressure using the hypsometric formula ($44330(1-(P/P_0)^{1/5.255})$) to lock onto the true elevated deck.

---

# 3. COLUMN 2: BENCHMARK PLOT & VALIDATION METRICS

* **IO-VNBD Benchmark Graph**: Trajectory comparison showing:
  * **Green Line (IDR Lane-Hold)**: Holds true highway centerlines throughout the 850m tunnel outage (**0.17m drift / 0.02% error**).
  * **Cyan Line (Only DR)**: Pure inertial dead reckoning without map matching (**0.42m drift / 0.05% error**).
  * **Red Line (Classical INS)**: Explodes quadratically into $>184\text{m}$ drift ($21.7\%$ error).
* **Speed Tracking Precision**: Mean Absolute Error (MAE) of **$0.50\text{ m/s}$ ($1.8\text{ km/h}$)** against NovAtel RTK + CAN-bus Doppler ground truth (82.5% error reduction).
* **SIH Criterion Compliance**: **93.8% Pass Rate** across 64 held-out evaluation trips under the SIH $< 10\%$ drift threshold.

---

# 4. PRESENTER SCRIPT (75 SECONDS)

> *"Respected Jury Members, Slide 4 proves both the **Technical Feasibility** and the **Defensive Viability** of IDR-Navigator.
> 
> In **Column 1**, you see our deep learning speed engine: an 8-Channel Dilated Causal SE-TCN with a 31-step receptive field that captures 3.1 seconds of vehicle vibration history. We quantized the 2.09-million-parameter model to INT8, shrinking its footprint to just **2.1 MB**. On a standard phone NPU, it infers forward speed in under **4.5 milliseconds**—consuming less than 5% of our 10-hertz timing budget with under 5.8% battery draw per hour.
> 
> In **Column 2**, our benchmark trajectory plot from the IO-VNBD dataset demonstrates the result: over an 850-meter highway tunnel blackout, classical double-integration explodes by 184 meters, while our system holds the lane with only **0.17 meters of drift (0.02% error)**, achieving a **93.8% pass rate** across 64 evaluation runs.
> 
> Finally, in **Column 3**, we engineer deterministic defenses for real Indian road challenges:
> 1. Pothole shocks are isolated by our **Savitzky-Golay Jerk Gate**, which inflates Kalman noise $50\times$.
> 2. Red-light engine idle rumble is clamped to zero by our **Centripetal ZUPT**.
> 3. Multi-tier flyovers are disambiguated by our **3D Barometric Altimeter Cost Engine**.
> 
> Verified across 136 automated test cases and road-tested on the Mumbai-Pune Expressway, IDR-Navigator is 100% feasible and edge-ready."*
