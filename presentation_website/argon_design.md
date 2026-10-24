Here is the complete specification and code for the **IDR-Navigator Interactive Prototype Cockpit Hero Section**, designed using an Argon-inspired ultra-modern dark telemetry aesthetic (`#0b0f19` deep slate, neon status accents, frosted HUD panels, and high-contrast monospace telemetry).

---

### 1. HTML Structure: Hero Prototype Cockpit

```html
<header class="argon-hero-cockpit">
  <!-- Top Prestigious Branding Bar -->
  <div class="cockpit-topbar">
    <div class="brand-identity">
      <span class="badge-isro">ISRO SIH26168</span>
      <span class="badge-hardware">BOSCH BMI270 · 100Hz MEMS</span>
      <h1 class="project-title">IDR-Navigator <span class="version-tag">v2.4 LIVE PROTOTYPE</span></h1>
    </div>
    <div class="mission-subtitle">
      Neural-Kalman Inertial Dead Reckoning Under GNSS Denial on Commodity Smartphone IMUs
    </div>
    <div class="quick-links">
      <a href="#monograph-abstract" class="btn-argon-outline">Read Technical Monograph ↓</a>
    </div>
  </div>

  <!-- Main Interactive Cockpit Grid -->
  <div class="cockpit-grid">
    
    <!-- LEFT/CENTER: Live Simulation Viewport & HUD Overlays -->
    <div class="viewport-container">
      <canvas id="idr-hero-canvas" width="960" height="540"></canvas>

      <!-- Top-Left HUD: GNSS & System Status -->
      <div class="hud-overlay hud-top-left">
        <div id="gnss-status-pill" class="status-pill status-locked">
          <span class="pulse-dot"></span>
          <span id="gnss-status-text">GNSS LOCKED — RTK 0.8 HDOP</span>
        </div>
        <div class="telemetry-micro">
          <span>INFERENCE: <strong>2.2 ms (INT8 ONNX)</strong></span>
          <span id="zupt-indicator" class="zupt-badge">ZUPT: STANDBY</span>
        </div>
      </div>

      <!-- Top-Right HUD: Live Velocity & Distance -->
      <div class="hud-overlay hud-top-right">
        <div class="hud-metric-box">
          <span class="hud-label">GROUND VELOCITY</span>
          <div class="hud-value"><span id="hud-speed-kmh">65.0</span> <small>km/h</small></div>
          <span class="hud-sub" id="hud-speed-ms">18.05 m/s</span>
        </div>
        <div class="hud-metric-box">
          <span class="hud-label">TRAVELED (DENIED)</span>
          <div class="hud-value"><span id="hud-dist-m">0.0</span> <small>m</small></div>
          <span class="hud-sub" id="hud-time-s">T+ 0.0s</span>
        </div>
      </div>

      <!-- Bottom HUD: Live Drift Comparison Bar -->
      <div class="hud-overlay hud-bottom-bar">
        <div class="drift-card idr-card">
          <div class="legend-dot dot-green"></div>
          <div>
            <div class="drift-title">IDR-NAVIGATOR (RESNET-1D + ES-EKF)</div>
            <div class="drift-stats">
              Pos Error: <strong id="idr-error-m">0.12 m</strong> 
              (<span id="idr-error-pct">0.08%</span>)
            </div>
          </div>
        </div>

        <div class="drift-card classical-card">
          <div class="legend-dot dot-red"></div>
          <div>
            <div class="drift-title">CLASSICAL DOUBLE INTEGRATION</div>
            <div class="drift-stats">
              Pos Error: <strong id="class-error-m">0.15 m</strong> 
              (<span id="class-error-pct">0.10%</span>)
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- RIGHT: Argon Telemetry Control Deck -->
    <aside class="control-deck">
      <div class="deck-header">
        <h2>MISSION CONTROL DECK</h2>
        <button id="btn-reset-sim" class="btn-reset" title="Reset Trajectory">↺ RESET</button>
      </div>

      <!-- Primary Emergency GNSS Cut Switch -->
      <div class="control-group emergency-box">
        <label class="control-label">SATELLITE LINK OVERRIDE</label>
        <button id="btn-cut-gnss" class="btn-gnss-cut" aria-pressed="false">
          <span class="btn-icon">📡</span>
          <span class="btn-text">CUT GNSS SIGNAL</span>
          <span class="btn-sub">SIMULATE TUNNEL BLACKOUT</span>
        </button>
      </div>

      <!-- Route Profile Selector -->
      <div class="control-group">
        <label class="control-label" for="route-select">TRAJECTORY PROFILE</label>
        <select id="route-select" class="argon-select">
          <option value="tunnel">Highway Tunnel (1.6 km Straight/Curve)</option>
          <option value="urban">Urban Canyon (Stop-and-Go 90° Grids)</option>
          <option value="mountain">Winding Mountain Switchbacks</option>
        </select>
      </div>

      <!-- Speed Throttle Slider -->
      <div class="control-group">
        <div class="slider-header">
          <label class="control-label" for="speed-slider">CRUISE THROTTLE</label>
          <span id="throttle-readout" class="mono-val">65 km/h</span>
        </div>
        <input type="range" id="speed-slider" class="argon-slider" min="30" max="100" value="65" step="1">
        <div class="slider-ticks">
          <span>30 km/h</span><span>65 km/h</span><span>100 km/h</span>
        </div>
      </div>

      <!-- Perturbation & ZUPT Triggers -->
      <div class="control-group">
        <label class="control-label">PERTURBATION & CONSTRAINTS</label>
        <div class="trigger-grid">
          <button id="btn-pothole" class="btn-trigger btn-warn">
            ⚡ Pothole Shock
            <small>Inject 4.5g Z-Spike</small>
          </button>
          <button id="btn-zupt" class="btn-trigger btn-info">
            🛑 ZUPT Brake
            <small>Red Light 0 m/s Lock</small>
          </button>
        </div>
      </div>

      <!-- Live Covariance / IMU Noise Readout -->
      <div class="imu-diagnostic-box">
        <div class="diag-row">
          <span>Gyro Bias ($\hat{b}_\omega$):</span>
          <strong id="diag-gyro">0.0021 rad/s</strong>
        </div>
        <div class="diag-row">
          <span>NHC Lateral Residual:</span>
          <strong id="diag-nhc">0.014 m/s</strong>
        </div>
        <div class="diag-row">
          <span>ES-EKF Trace($\mathbf{P}$):</span>
          <strong id="diag-cov">0.042 m²</strong>
        </div>
      </div>
    </aside>

  </div>

  <!-- Bottom Executive Summary & Abstract Strip -->
  <div id="monograph-abstract" class="cockpit-abstract-strip">
    <div class="abstract-text">
      <strong>ABSTRACT:</strong> Commodity MEMS IMUs in smartphones suffer from severe non-linear scale factor asymmetries, thermal bias instability, and vibrational aliasing, causing classical strapdown dead reckoning to diverge quadratically ($>150\text{ m}$ error within $30\text{ s}$). <strong>IDR-Navigator</strong> replaces raw integration with a lightweight 1D-ResNet velocity prior tightly coupled into an Error-State Extended Kalman Filter (ES-EKF) with Non-Holonomic Constraints (NHC) and automated Zero-Velocity Updates (ZUPT), bounding horizontal drift to <strong>$&lt;0.65\%$ of distance traveled</strong>.
    </div>
    <div class="abstract-kpis">
      <div class="kpi-pill"><span>0.62%</span> RMSE Drift</div>
      <div class="kpi-pill"><span>2.2 ms</span> Latency</div>
      <div class="kpi-pill"><span>100 Hz</span> Filter Rate</div>
    </div>
  </div>
</header>
```

---

### 2. CSS Styling: Argon Telemetry & Glassmorphism HUD

```css
:root {
  --argon-bg: #0b0f19;
  --argon-panel: rgba(17, 24, 39, 0.82);
  --argon-border: rgba(255, 255, 255, 0.1);
  --argon-cyan: #11cdef;
  --argon-green: #2dce89;
  --argon-red: #f5365c;
  --argon-orange: #fb6340;
  --argon-indigo: #5e72e4;
  --font-mono: 'JetBrains Mono', 'Fira Code', monospace;
  --font-sans: 'Inter', -apple-system, sans-serif;
}

.argon-hero-cockpit {
  background: radial-gradient(circle at 15% 15%, #162038 0%, var(--argon-bg) 70%);
  color: #f8f9fe;
  font-family: var(--font-sans);
  padding: 1.25rem 2rem 2rem;
  border-bottom: 1px solid var(--argon-border);
}

/* Topbar */
.cockpit-topbar {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  align-items: center;
  gap: 1rem;
  margin-bottom: 1.25rem;
  padding-bottom: 0.75rem;
  border-bottom: 1px solid var(--argon-border);
}

.brand-identity {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.badge-isro {
  background: linear-gradient(87deg, var(--argon-orange), #fbb140);
  color: #0b0f19;
  font-weight: 800;
  font-size: 0.75rem;
  padding: 0.25rem 0.6rem;
  border-radius: 4px;
  letter-spacing: 0.05em;
}

.badge-hardware {
  background: rgba(17, 205, 239, 0.15);
  color: var(--argon-cyan);
  border: 1px solid rgba(17, 205, 239, 0.3);
  font-family: var(--font-mono);
  font-size: 0.72rem;
  padding: 0.2rem 0.5rem;
  border-radius: 4px;
}

.project-title {
  font-size: 1.35rem;
  font-weight: 700;
  margin: 0;
  letter-spacing: -0.02em;
}

.version-tag {
  font-family: var(--font-mono);
  font-size: 0.7rem;
  color: var(--argon-green);
  vertical-align: middle;
  margin-left: 0.4rem;
}

.mission-subtitle {
  font-size: 0.85rem;
  color: #8898aa;
}

.btn-argon-outline {
  color: var(--argon-cyan);
  border: 1px solid var(--argon-cyan);
  padding: 0.4rem 0.85rem;
  border-radius: 6px;
  font-size: 0.8rem;
  text-decoration: none;
  transition: all 0.2s ease;
}
.btn-argon-outline:hover {
  background: var(--argon-cyan);
  color: #0b0f19;
}

/* Main Cockpit Grid */
.cockpit-grid {
  display: grid;
  grid-template-columns: 1fr 340px;
  gap: 1.25rem;
  align-items: stretch;
}

@media (max-width: 1024px) {
  .cockpit-grid { grid-template-columns: 1fr; }
}

/* Viewport & Canvas */
.viewport-container {
  position: relative;
  background: #070a12;
  border: 1px solid var(--argon-border);
  border-radius: 12px;
  overflow: hidden;
  min-height: 500px;
  box-shadow: 0 15px 35px rgba(0, 0, 0, 0.5);
}

#idr-hero-canvas {
  width: 100%;
  height: 100%;
  display: block;
}

/* Glassmorphic HUD Overlays */
.hud-overlay {
  position: absolute;
  pointer-events: none;
  z-index: 10;
}

.hud-top-left { top: 1rem; left: 1rem; }
.hud-top-right { top: 1rem; right: 1rem; display: flex; gap: 0.75rem; }
.hud-bottom-bar {
  bottom: 1rem; left: 1rem; right: 1rem;
  display: flex; justify-content: space-between; gap: 1rem;
}

.status-pill {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.45rem 0.9rem;
  border-radius: 6px;
  font-family: var(--font-mono);
  font-size: 0.8rem;
  font-weight: 700;
  backdrop-filter: blur(8px);
}

.status-locked {
  background: rgba(45, 206, 137, 0.18);
  border: 1px solid var(--argon-green);
  color: var(--argon-green);
}

.status-denied {
  background: rgba(245, 54, 92, 0.25);
  border: 1px solid var(--argon-red);
  color: #ff8fa3;
  box-shadow: 0 0 20px rgba(245, 54, 92, 0.4);
}

.pulse-dot {
  width: 8px; height: 8px;
  border-radius: 50%;
  background: currentColor;
  animation: pulse 1.2s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.35; transform: scale(1.25); }
}

.telemetry-micro {
  margin-top: 0.5rem;
  display: flex;
  gap: 0.6rem;
  font-family: var(--font-mono);
  font-size: 0.72rem;
  color: #cbd5e1;
  background: var(--argon-panel);
  padding: 0.3rem 0.6rem;
  border-radius: 4px;
  border: 1px solid var(--argon-border);
}

.zupt-badge.active {
  color: var(--argon-cyan);
  font-weight: 700;
}

.hud-metric-box {
  background: var(--argon-panel);
  backdrop-filter: blur(8px);
  border: 1px solid var(--argon-border);
  padding: 0.5rem 0.85rem;
  border-radius: 8px;
  text-align: right;
  font-family: var(--font-mono);
}

.hud-label { font-size: 0.65rem; color: #8898aa; display: block; }
.hud-value { font-size: 1.35rem; font-weight: 700; color: #fff; }
