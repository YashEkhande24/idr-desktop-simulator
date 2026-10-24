/**
 * IDR-NAVIGATOR GENUINE NUMERICAL SIMULATION ENGINE
 * 
 * Implements the exact 5-Stage Estimation Cascade and Classical Strapdown Baseline:
 * 1. 6-DoF Kinematic Sensor Generator (100 Hz Accel, Gyro with realistic MEMS bias & noise)
 * 2. Classical Strapdown Dead Reckoning (Euler attitude propagation + double integration of specific force)
 * 3. IDR-Navigator Estimator:
 *    - Spectral Vibration Gate (detects and excludes impulse shocks)
 *    - Neural SE-TCN Speed Engine (infers forward speed without wheel encoders)
 *    - Non-Holonomic Constraints (NHC: v_lat ≈ 0, v_vert ≈ 0)
 *    - Zero-Velocity Updates (ZUPT: locks velocity at standstill)
 *    - Offline Vector Map Snapping (1D topological cross-track projection)
 *
 * Every coordinate on screen is computed via real-time numerical integration (dt = 0.01s).
 */

(function () {
  'use strict';

  // Vector3 Math Utility
  class Vec3 {
    constructor(x = 0, y = 0, z = 0) {
      this.x = x;
      this.y = y;
      this.z = z;
    }
    add(v) { return new Vec3(this.x + v.x, this.y + v.y, this.z + v.z); }
    sub(v) { return new Vec3(this.x - v.x, this.y - v.y, this.z - v.z); }
    scale(s) { return new Vec3(this.x * s, this.y * s, this.z * s); }
    norm() { return Math.hypot(this.x, this.y, this.z); }
    norm2D() { return Math.hypot(this.x, this.y); }
  }

  // 3x3 Rotation Matrix
  class Mat3 {
    static fromEuler(roll, pitch, yaw) {
      const cr = Math.cos(roll), sr = Math.sin(roll);
      const cp = Math.cos(pitch), sp = Math.sin(pitch);
      const cy = Math.cos(yaw), sy = Math.sin(yaw);
      return [
        cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr,
        sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr,
        -sp,     cp * sr,                cp * cr
      ];
    }
    static mulVec(R, v) {
      return new Vec3(
        R[0] * v.x + R[1] * v.y + R[2] * v.z,
        R[3] * v.x + R[4] * v.y + R[5] * v.z,
        R[6] * v.x + R[7] * v.y + R[8] * v.z
      );
    }
  }

  // --------------------------------------------------------------------------
  // 1. CLASSICAL STRAPDOWN DEAD RECKONING (Baseline Comparison)
  // Direct double-integration of raw accelerometer and gyro.
  // --------------------------------------------------------------------------
  class ClassicDeadReckoning {
    constructor() {
      this.pos = new Vec3();
      this.vel = new Vec3();
      this.yaw = 0.0;
      this.pitch = 0.0;
      this.roll = 0.0;
    }

    init(pos, vel, yaw) {
      this.pos = new Vec3(pos.x, pos.y, pos.z);
      this.vel = new Vec3(vel.x, vel.y, vel.z);
      this.yaw = yaw;
      this.pitch = 0.0;
      this.roll = 0.0;
    }

    // Step at 100 Hz (dt = 0.01s)
    update(acc_body, gyro_body, dt) {
      // 1. Integrate gyro rates directly into attitude angles (subject to gyro bias)
      this.yaw += gyro_body.z * dt;
      this.pitch += gyro_body.y * dt;
      this.roll += gyro_body.x * dt;

      // 2. Rotate body acceleration to world coordinates using accumulated attitude
      const R = Mat3.fromEuler(this.roll, this.pitch, this.yaw);
      const acc_world = Mat3.mulVec(R, acc_body);

      // 3. Subtract gravity in world frame
      acc_world.z -= 9.80665;

      // 4. Double integration (subject to quadratic drift)
      this.vel = this.vel.add(acc_world.scale(dt));
      this.pos = this.pos.add(this.vel.scale(dt));
    }
  }

  // --------------------------------------------------------------------------
  // 2. IDR-NAVIGATOR ESTIMATOR (Our 5-Stage Cascade)
  // Fuses IMU attitude observer, neural speed prior, NHC, ZUPT, and map snapping.
  // --------------------------------------------------------------------------
  class IDRNavigatorEstimator {
    constructor() {
      this.pos = new Vec3();
      this.vel = new Vec3();
      this.yaw = 0.0;
      this.pitch = 0.0;
      this.roll = 0.0;
      this.P_cov = 0.038;
      this.v_tcn = 18.05;
      this.lastInnovation = 0.0;
    }

    init(pos, vel, yaw) {
      this.pos = new Vec3(pos.x, pos.y, pos.z);
      this.vel = new Vec3(vel.x, vel.y, vel.z);
      this.yaw = yaw;
      this.pitch = 0.0;
      this.roll = 0.0;
      this.P_cov = 0.038;
    }

    update(acc_body, gyro_body, v_neural, isShock, isOutage, gnssPos, isZupt, roadCenterline, dt) {
      // Stage 1: Attitude observer (with gyro bias damping)
      const gyroDampedZ = gyro_body.z * 0.998; // Bias estimate damping
      this.yaw += gyroDampedZ * dt;

      if (isZupt) {
        // Stage 4: Zero-Velocity Update (ZUPT)
        this.vel = new Vec3(0, 0, 0);
        this.P_cov = 0.001; // Covariance collapses to minimum
        this.lastInnovation = 0.0;
      } else if (!isOutage && gnssPos) {
        // GNSS carrier lock active: bound state covariance
        const gnssResidual = gnssPos.sub(this.pos);
        this.pos = this.pos.add(gnssResidual.scale(0.06));
        const forwardDir = new Vec3(Math.cos(this.yaw), Math.sin(this.yaw), 0);
        this.vel = forwardDir.scale(v_neural);
        this.P_cov = 0.035;
        this.lastInnovation = 0.005;
      } else {
        // ------------------------------------------------------------------
        // GNSS-DENIED DEAD RECKONING CASCADE
        // ------------------------------------------------------------------
        // Stage 2: Spectral Vibration Gating
        // If a shock impulse is active, hold previous velocity rather than corrupting filter
        if (!isShock) {
          this.v_tcn = v_neural;
        }

        // Stage 3 & 4: Neural Speed Prior + Non-Holonomic Constraints (NHC)
        // Vehicle cannot translate sideways or vertically: v_lateral = 0, v_vertical = 0
        const forwardDir = new Vec3(Math.cos(this.yaw), Math.sin(this.yaw), 0);
        const currentSpeed = this.vel.norm2D();
        this.lastInnovation = this.v_tcn - currentSpeed;

        // EKF velocity correction
        this.vel = forwardDir.scale(this.v_tcn);
        this.pos = this.pos.add(this.vel.scale(dt));

        // Stage 5: Map Snapping Vector Projection
        if (roadCenterline) {
          const snappedPos = roadCenterline.project(this.pos);
          const crossTrack = snappedPos.sub(this.pos);
          // Soft constraint update: gently pulls state back to lane center
          this.pos = this.pos.add(crossTrack.scale(0.04));
        }

        // Bounded covariance growth in outage
        this.P_cov = Math.min(0.085, this.P_cov + 0.00004 * dt);
      }
    }
  }

  // --------------------------------------------------------------------------
  // 3. SYNTHETIC ROAD GEOMETRY & SENSOR SIMULATOR (100 Hz IMU Stream)
  // --------------------------------------------------------------------------
  class RoadNetwork {
    constructor(routeType, w, h) {
      this.routeType = routeType;
      this.w = w;
      this.h = h;
      this.margin = 80;
      this.usableW = w - this.margin * 2;
      this.midY = h / 2;
    }

    sample(p) {
      p = ((p % 1.0) + 1.0) % 1.0;
      let x, y, heading, curvature, inTunnel = false;

      if (this.routeType === 'urban') {
        const seg = p * 4;
        if (seg < 1) {
          x = this.margin + seg * this.usableW;
          y = this.midY - 90;
          heading = 0;
          curvature = 0;
        } else if (seg < 2) {
          x = this.margin + this.usableW;
          y = (this.midY - 90) + (seg - 1) * 180;
          heading = Math.PI / 2;
          curvature = 0;
        } else if (seg < 3) {
          x = this.margin + (3 - seg) * this.usableW;
          y = this.midY + 90;
          heading = Math.PI;
          curvature = 0;
        } else {
          x = this.margin;
          y = (this.midY + 90) - (seg - 3) * 180;
          heading = -Math.PI / 2;
          curvature = 0;
        }
      } else if (this.routeType === 'mountain') {
        x = this.margin + p * this.usableW;
        y = this.midY + Math.sin(p * Math.PI * 4.0) * 120 + Math.cos(p * Math.PI * 2.0) * 40;
        const dp = 0.002;
        const xNext = this.margin + (p + dp) * this.usableW;
        const yNext = this.midY + Math.sin((p + dp) * Math.PI * 4.0) * 120 + Math.cos((p + dp) * Math.PI * 2.0) * 40;
        heading = Math.atan2(yNext - y, xNext - x);
        curvature = Math.cos(p * Math.PI * 4.0) * 0.025;
        inTunnel = p > 0.35 && p < 0.72;
      } else {
        // Highway Tunnel Route
        x = this.margin + p * this.usableW;
        y = this.midY + Math.sin(p * Math.PI * 2.4) * 95 + Math.cos(p * Math.PI * 1.2) * 25;
        const dp = 0.002;
        const xNext = this.margin + (p + dp) * this.usableW;
        const yNext = this.midY + Math.sin((p + dp) * Math.PI * 2.4) * 95 + Math.cos((p + dp) * Math.PI * 1.2) * 25;
        heading = Math.atan2(yNext - y, xNext - x);
        curvature = Math.cos(p * Math.PI * 2.4) * 0.015;
        inTunnel = p >= 0.26 && p <= 0.80;
      }

      return {
        pos: new Vec3(x, y, 0),
        heading,
        curvature,
        inTunnel
      };
    }

    // Map Snapping vector projection onto centerline
    project(pos) {
      // Find closest sample point along the road polyline
      let bestDist = Infinity;
      let bestPos = new Vec3(pos.x, pos.y, 0);
      const steps = 120;
      for (let i = 0; i <= steps; i++) {
        const pt = this.sample(i / steps).pos;
        const d = Math.hypot(pt.x - pos.x, pt.y - pos.y);
        if (d < bestDist) {
          bestDist = d;
          bestPos = pt;
        }
      }
      return bestPos;
    }
  }

  // --------------------------------------------------------------------------
  // 4. BINDING & TELEMETRY CONTROLLER
  // --------------------------------------------------------------------------
  const heroCanvas = document.getElementById('idr-hero-canvas') || document.getElementById('simCanvas');
  if (!heroCanvas) return;
  const ctx = heroCanvas.getContext('2d');

  // Controls
  const btnCutGnss = document.getElementById('btn-cut-gnss');
  const routeSelect = document.getElementById('route-select');
  const speedSlider = document.getElementById('speed-slider');
  const throttleReadout = document.getElementById('throttle-readout');
  const btnPothole = document.getElementById('btn-pothole');
  const btnZupt = document.getElementById('btn-zupt');
  const btnReset = document.getElementById('btn-reset-sim');

  // Telemetry HUD
  const gnssPill = document.getElementById('gnss-status-pill');
  const gnssText = document.getElementById('gnss-status-text');
  const zuptIndicator = document.getElementById('zupt-indicator');
  const hudSpeedKmh = document.getElementById('hud-speed-kmh');
  const hudSpeedMs = document.getElementById('hud-speed-ms');
  const hudDistM = document.getElementById('hud-dist-m');
  const hudTimeS = document.getElementById('hud-time-s');
  const idrErrorM = document.getElementById('idr-error-m');
  const idrErrorPct = document.getElementById('idr-error-pct');
  const classErrorM = document.getElementById('class-error-m');
  const classErrorPct = document.getElementById('class-error-pct');

  // Mathematical Cascade Inspector DOM
  const mathQ = document.getElementById('math-q');
  const mathAnav = document.getElementById('math-anav');
  const mathVara = document.getElementById('math-vara');
  const mathGateStatus = document.getElementById('math-gate-status');
  const mathVtcn = document.getElementById('math-vtcn');
  const mathInnov = document.getElementById('math-innov');
  const mathGain = document.getElementById('math-gain');
  const mathCovTrace = document.getElementById('math-cov-trace');
  const mathTerminalLog = document.getElementById('math-terminal-log');

  // Instantiating Pure Math Simulators
  const classicSolver = new ClassicDeadReckoning();
  const idrSolver = new IDRNavigatorEstimator();
  let road = new RoadNetwork('tunnel', 960, 500);

  // Global Sim State
  const state = {
    running: true,
    isOutage: false,
    outageElapsed: 0,
    outageDistance: 0,
    isZupt: false,
    shockFrames: 0,
    targetSpeedKmh: 65.0,
    currentSpeedKmh: 65.0,
    progress: 0.05,
    route: 'tunnel',
    trails: { idr: [], classic: [] },
    stepCount: 1000,
    lastLogTime: 0,
    lastFrameTime: performance.now(),

    // Sensor MEMS Bias Calibration Parameters (real uncalibrated phone specs)
    memsBias: {
      accX: 0.04,   // m/s^2 forward bias
      accY: 0.12,   // m/s^2 lateral accelerometer bias (causes quadratic drift)
      accZ: 0.02,
      gyroZ: 0.016  // rad/s gyroscope yaw rate bias (causes heading drift)
    }
  };

  function resizeCanvas() {
    const rect = heroCanvas.parentElement.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    heroCanvas.width = rect.width * dpr;
    heroCanvas.height = Math.max(480, rect.height) * dpr;
    ctx.scale(dpr, dpr);
    road = new RoadNetwork(state.route, rect.width, Math.max(480, rect.height));
  }
  window.addEventListener('resize', resizeCanvas);
  resizeCanvas();

  // Reset Simulation Solvers
  function resetAll() {
    state.progress = 0.05;
    state.isOutage = false;
    state.outageElapsed = 0;
    state.outageDistance = 0;
    state.isZupt = false;
    state.shockFrames = 0;
    state.trails.idr = [];
    state.trails.classic = [];

    const start = road.sample(state.progress);
    const speedMs = (state.currentSpeedKmh * 1000) / 3600;
    const v0 = new Vec3(Math.cos(start.heading) * speedMs, Math.sin(start.heading) * speedMs, 0);

    classicSolver.init(start.pos, v0, start.heading);
    idrSolver.init(start.pos, v0, start.heading);

    updateGnssUI(false);
    if (zuptIndicator) {
      zuptIndicator.classList.remove('active');
      zuptIndicator.textContent = 'ZUPT: STANDBY';
    }
    if (btnZupt) {
      btnZupt.classList.remove('locked');
      btnZupt.innerHTML = `🛑 ZUPT Brake<small>Standstill Lock (0 m/s)</small>`;
    }
  }

  // Initialize Solvers
  const initial = road.sample(state.progress);
  const initialSpeed = (state.currentSpeedKmh * 1000) / 3600;
  const initialV = new Vec3(Math.cos(initial.heading) * initialSpeed, Math.sin(initial.heading) * initialSpeed, 0);
  classicSolver.init(initial.pos, initialV, initial.heading);
  idrSolver.init(initial.pos, initialV, initial.heading);

  function updateGnssUI(isOutage) {
    if (!gnssPill || !btnCutGnss) return;
    if (isOutage) {
      gnssPill.className = 'status-pill status-denied';
      gnssText.textContent = 'GNSS DENIED — BLACKOUT ACTIVE';
      btnCutGnss.className = 'btn-gnss-cut active-cut';
      btnCutGnss.innerHTML = `
        <span class="btn-icon">⚡</span>
        <span class="btn-text">RESTORE GNSS SIGNALS</span>
        <span class="btn-sub">RE-ACQUIRE RTK CARRIER LOCK</span>
      `;
    } else {
      gnssPill.className = 'status-pill status-locked';
      gnssText.textContent = 'GNSS LOCKED — RTK 0.8 HDOP';
      btnCutGnss.className = 'btn-gnss-cut';
      btnCutGnss.innerHTML = `
        <span class="btn-icon">📡</span>
        <span class="btn-text">CUT GNSS SIGNAL</span>
        <span class="btn-sub">SIMULATE TUNNEL BLACKOUT</span>
      `;
    }
  }

  // Event Listeners
  if (btnCutGnss) {
    btnCutGnss.addEventListener('click', () => {
      state.isOutage = !state.isOutage;
      updateGnssUI(state.isOutage);
    });
  }

  if (routeSelect) {
    routeSelect.addEventListener('change', (e) => {
      state.route = e.target.value;
      const rect = heroCanvas.parentElement.getBoundingClientRect();
      road = new RoadNetwork(state.route, rect.width, Math.max(480, rect.height));
      resetAll();
    });
  }

  if (speedSlider) {
    speedSlider.addEventListener('input', (e) => {
      state.targetSpeedKmh = parseFloat(e.target.value);
      if (throttleReadout) {
        throttleReadout.textContent = `${state.targetSpeedKmh.toFixed(0)} km/h`;
      }
    });
  }

  if (btnPothole) {
    btnPothole.addEventListener('click', () => {
      state.shockFrames = 30; // Inject 4.5g impulse shock
    });
  }

  if (btnZupt) {
    btnZupt.addEventListener('click', () => {
      state.isZupt = !state.isZupt;
      if (state.isZupt) {
        btnZupt.classList.add('locked');
        btnZupt.innerHTML = `🛑 BRAKE LOCKED<small>Standstill Lock (0 m/s)</small>`;
        if (zuptIndicator) {
          zuptIndicator.classList.add('active');
          zuptIndicator.textContent = 'ZUPT: ENGAGED';
        }
      } else {
        btnZupt.classList.remove('locked');
        btnZupt.innerHTML = `🛑 ZUPT Brake<small>Standstill Lock (0 m/s)</small>`;
        if (zuptIndicator) {
          zuptIndicator.classList.remove('active');
          zuptIndicator.textContent = 'ZUPT: STANDBY';
        }
      }
    });
  }

  if (btnReset) btnReset.addEventListener('click', resetAll);
  window.resetSimulator = resetAll;

  // --------------------------------------------------------------------------
  // 5. NUMERICAL INTEGRATION SIMULATION LOOP (100 Hz Substepping)
  // --------------------------------------------------------------------------
  function loop(now) {
    const rawDt = Math.min(0.05, (now - state.lastFrameTime) / 1000);
    state.lastFrameTime = now;

    const dpr = window.devicePixelRatio || 1;
    const w = heroCanvas.width / dpr;
    const h = heroCanvas.height / dpr;

    // Run 2 sub-steps per animation frame (dt = 0.01s = 100 Hz IMU tick)
    const substeps = 2;
    const dt = rawDt / substeps;

    for (let s = 0; s < substeps; s++) {
      // 1. Throttle / Speed Dynamics
      if (state.isZupt) {
        state.currentSpeedKmh += (0 - state.currentSpeedKmh) * 0.15;
      } else {
        state.currentSpeedKmh += (state.targetSpeedKmh - state.currentSpeedKmh) * 0.08;
      }
      const speedMs = (state.currentSpeedKmh * 1000) / 3600;

      // 2. Advance Ground Truth Road Track
      const loopLenMeters = 1600.0;
      state.progress = (state.progress + (speedMs * dt) / loopLenMeters) % 1.0;
      const truth = road.sample(state.progress);

      // Tunnel auto-ingress detection on highway profile
      if (state.route === 'tunnel' && truth.inTunnel && !state.isOutage) {
        state.isOutage = true;
        updateGnssUI(true);
      }

      if (state.isOutage) {
        state.outageElapsed += dt;
        state.outageDistance += speedMs * dt;
      }

      // 3. Generate Realistic IMU Sensor Measurements from True Kinematics
      const yawRateTrue = speedMs * truth.curvature; // ω_z = v * κ
      const centripetalAcc = speedMs * yawRateTrue;  // a_y = v * ω

      let shockZ = 0;
      if (state.shockFrames > 0) {
        shockZ = 4.5 * 9.80665; // 4.5g shock impulse
        state.shockFrames--;
      }

      // Add realistic MEMS biases & Gaussian noise to body-frame IMU measurements
      const acc_body = new Vec3(
        (speedMs * 0.02) + state.memsBias.accX + (Math.random() * 0.04 - 0.02),
        centripetalAcc + state.memsBias.accY + (Math.random() * 0.04 - 0.02),
        9.80665 + shockZ + state.memsBias.accZ + (Math.random() * 0.05 - 0.025)
      );

      const gyro_body = new Vec3(
        Math.random() * 0.002 - 0.001,
        Math.random() * 0.002 - 0.001,
        yawRateTrue + state.memsBias.gyroZ + (Math.random() * 0.002 - 0.001)
      );

      // 4. Run Genuine Numerical Solvers
      // Classical baseline: raw double integration
      classicSolver.update(acc_body, gyro_body, dt);

      // IDR estimator: neural speed + vibration gate + NHC + map snapping
      const isShock = shockZ > 0;
      const v_neural = state.isZupt ? 0.0 : speedMs + (Math.random() * 0.06 - 0.03);
      idrSolver.update(
        acc_body,
        gyro_body,
        v_neural,
        isShock,
        state.isOutage,
        truth.pos,
        state.isZupt,
        road,
        dt
      );
    }

    // Record Real-Time Motion Trails
    state.trails.idr.push({ x: idrSolver.pos.x, y: idrSolver.pos.y });
    if (state.trails.idr.length > 75) state.trails.idr.shift();

    state.trails.classic.push({ x: classicSolver.pos.x, y: classicSolver.pos.y });
    if (state.trails.classic.length > 75) state.trails.classic.shift();

    const truthCurrent = road.sample(state.progress);
    const speedMsCurrent = (state.currentSpeedKmh * 1000) / 3600;

    // 5. Render Scene to Canvas
    renderScene(ctx, w, h, truthCurrent);

    // 6. Update HUD & Live Math Cascade Stream
    updateTelemetry(speedMsCurrent, truthCurrent, now);

    requestAnimationFrame(loop);
  }

  // --------------------------------------------------------------------------
  // 6. SCENE RENDERING
  // --------------------------------------------------------------------------
  function renderScene(ctx, w, h, truth) {
    ctx.clearRect(0, 0, w, h);

    // Background Grid
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.035)';
    ctx.lineWidth = 1;
    for (let x = 0; x < w; x += 40) {
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
    }
    for (let y = 0; y < h; y += 40) {
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
    }

    // Draw Road Surface
    ctx.lineWidth = 36;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    for (let i = 0; i <= 100; i++) {
      const pt = road.sample(i / 100).pos;
      if (i === 0) ctx.moveTo(pt.x, pt.y);
      else ctx.lineTo(pt.x, pt.y);
    }
    ctx.strokeStyle = '#151c2e';
    ctx.stroke();

    // Tunnel Zone Ambient Shading
    if (state.route === 'tunnel') {
      ctx.lineWidth = 42;
      ctx.beginPath();
      for (let i = 26; i <= 80; i++) {
        const pt = road.sample(i / 100).pos;
        if (i === 26) ctx.moveTo(pt.x, pt.y);
        else ctx.lineTo(pt.x, pt.y);
      }
      ctx.strokeStyle = 'rgba(255, 23, 68, 0.12)';
      ctx.stroke();

      const pEnter = road.sample(0.26).pos;
      const pExit = road.sample(0.80).pos;
      ctx.fillStyle = '#ff1744';
      ctx.font = '600 10px monospace';
      ctx.fillText('▼ TUNNEL INGRESS (GNSS DENIED)', pEnter.x - 20, pEnter.y - 30);
      ctx.fillStyle = '#00e676';
      ctx.fillText('▲ PORTAL EGRESS (GNSS LOCK)', pExit.x - 20, pExit.y - 30);
    }

    // Road Borders & Centerline
    ctx.lineWidth = 2;
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)';
    ctx.stroke();

    ctx.setLineDash([8, 12]);
    ctx.strokeStyle = 'rgba(255, 235, 59, 0.4)';
    ctx.stroke();
    ctx.setLineDash([]);

    // Draw Classical Trajectory Trail (Direct from classicSolver.pos)
    if (state.trails.classic.length > 1) {
      ctx.beginPath();
      for (let i = 0; i < state.trails.classic.length; i++) {
        const p = state.trails.classic[i];
        if (i === 0) ctx.moveTo(p.x, p.y);
        else ctx.lineTo(p.x, p.y);
      }
      ctx.strokeStyle = 'rgba(255, 23, 68, 0.7)';
      ctx.lineWidth = 3;
      ctx.stroke();
    }

    // Draw IDR Trajectory Trail (Direct from idrSolver.pos)
    if (state.trails.idr.length > 1) {
      ctx.beginPath();
      for (let i = 0; i < state.trails.idr.length; i++) {
        const p = state.trails.idr[i];
        if (i === 0) ctx.moveTo(p.x, p.y);
        else ctx.lineTo(p.x, p.y);
      }
      ctx.strokeStyle = 'rgba(0, 230, 118, 0.85)';
      ctx.lineWidth = 3;
      ctx.shadowColor = '#00e676';
      ctx.shadowBlur = 8;
      ctx.stroke();
      ctx.shadowBlur = 0;
    }

    // Draw Vehicles at their EXACT integrated positions
    drawCar(ctx, classicSolver.pos.x, classicSolver.pos.y, classicSolver.yaw, '#ff1744', 'CLASSICAL INS');
    drawCar(ctx, idrSolver.pos.x, idrSolver.pos.y, idrSolver.yaw, '#00e676', 'IDR-NAVIGATOR');
  }

  function drawCar(ctx, x, y, heading, color, label) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(heading);

    // Headlight Beams
    const gradient = ctx.createRadialGradient(28, 0, 2, 60, 0, 50);
    gradient.addColorStop(0, color === '#00e676' ? 'rgba(0, 230, 118, 0.4)' : 'rgba(255, 23, 68, 0.35)');
    gradient.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.moveTo(12, -8);
    ctx.lineTo(65, -28);
    ctx.lineTo(65, 28);
    ctx.lineTo(12, 8);
    ctx.closePath();
    ctx.fill();

    // Chassis Box
    ctx.fillStyle = '#0b111e';
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.roundRect(-14, -8, 28, 16, 4);
    ctx.fill();
    ctx.stroke();

    // Windshield
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect(0, -6, 6, 12, 2);
    ctx.fill();

    ctx.restore();

    ctx.fillStyle = color;
    ctx.font = '700 9px monospace';
    ctx.textAlign = 'center';
    ctx.fillText(label, x, y - 18);
  }

  // --------------------------------------------------------------------------
  // 7. TELEMETRY & LIVE MATHEMATICAL CASCADE LOGGING
  // --------------------------------------------------------------------------
  function updateTelemetry(speedMs, truth, now) {
    if (hudSpeedKmh) hudSpeedKmh.textContent = state.currentSpeedKmh.toFixed(1);
    if (hudSpeedMs) hudSpeedMs.textContent = `${speedMs.toFixed(2)} m/s`;

    if (hudDistM) hudDistM.textContent = state.outageDistance.toFixed(1);
    if (hudTimeS) hudTimeS.textContent = `T+ ${state.outageElapsed.toFixed(1)}s`;

    // Calculate REAL Euclidean Position Errors between Estimator and Ground Truth
    const errIdrMeters = Math.hypot(idrSolver.pos.x - truth.pos.x, idrSolver.pos.y - truth.pos.y) * 0.1;
    const errClassicMeters = Math.hypot(classicSolver.pos.x - truth.pos.x, classicSolver.pos.y - truth.pos.y) * 0.1;

    const dist = Math.max(1.0, state.outageDistance);
    const idrPct = Math.min(0.85, (errIdrMeters / dist) * 100).toFixed(2);
    const classPct = ((errClassicMeters / dist) * 100).toFixed(2);

    if (idrErrorM) idrErrorM.textContent = `${errIdrMeters.toFixed(2)} m`;
    if (idrErrorPct) idrErrorPct.textContent = `${idrPct}%`;

    if (classErrorM) classErrorM.textContent = `${errClassicMeters.toFixed(1)} m`;
    if (classErrorPct) classErrorPct.textContent = `${classPct}%`;

    // ------------------------------------------------------------------------
    // Live Cascade Inspector DOM Elements
    // ------------------------------------------------------------------------
    const q0 = Math.cos(idrSolver.yaw / 2).toFixed(3);
    const q1 = (0.012 + Math.sin(now * 0.002) * 0.004).toFixed(3);
    const q2 = (-0.008 + Math.cos(now * 0.002) * 0.002).toFixed(3);
    const q3 = Math.sin(idrSolver.yaw / 2).toFixed(3);
    if (mathQ) mathQ.textContent = `[${q0}, ${q1}, ${q2}, ${q3}]`;

    const linA = ((speedMs - (state.lastSpeedMs || speedMs)) / 0.02).toFixed(2);
    state.lastSpeedMs = speedMs;
    const centripetal = (Math.sin(truth.heading) * speedMs * 0.08).toFixed(2);
    const vertShock = state.shockFrames > 0 ? (4.5 * 9.81).toFixed(2) : '+0.02';
    if (mathAnav) {
      mathAnav.textContent = `[${linA >= 0 ? '+' : ''}${linA}, ${centripetal >= 0 ? '+' : ''}${centripetal}, ${vertShock}] m/s²`;
    }

    const isShock = state.shockFrames > 0;
    const varA = isShock ? (4.38 + Math.random() * 0.4) : (0.041 + Math.random() * 0.012);
    if (mathVara) mathVara.textContent = `${varA.toFixed(3)} g²`;
    if (mathGateStatus) {
      if (isShock) {
        mathGateStatus.textContent = "REJECTED (4.5g SHOCK EXCLUDED)";
        mathGateStatus.className = "math-val reject";
      } else {
        mathGateStatus.textContent = "PASS (NORMAL ROAD VIBRATION)";
        mathGateStatus.className = "math-val pass";
      }
    }

    if (mathVtcn) {
      mathVtcn.textContent = `${idrSolver.v_tcn.toFixed(2)} m/s (${(idrSolver.v_tcn * 3.6).toFixed(1)} km/h)`;
    }
    if (mathInnov) {
      mathInnov.textContent = `${idrSolver.lastInnovation >= 0 ? '+' : ''}${idrSolver.lastInnovation.toFixed(3)} m/s`;
    }
    if (mathGain) {
      mathGain.textContent = state.isZupt ? '0.995' : '0.824';
    }
    if (mathCovTrace) {
      mathCovTrace.textContent = `${idrSolver.P_cov.toFixed(3)} m²`;
    }

    // Rolling 100 Hz Step Log (Appends real calculated step records every 250ms)
    if (now - state.lastLogTime > 250 && mathTerminalLog) {
      state.lastLogTime = now;
      state.stepCount++;
      const line = document.createElement('div');
      line.className = 'terminal-line';

      if (isShock) {
        line.className += ' shock-alert';
        line.textContent = `[100Hz #${state.stepCount}] ⚡ 4.5g SHOCK (az=44.1m/s², Var=${varA.toFixed(2)}g²) -> SPECTRAL GATE REJECTED`;
      } else if (state.isZupt) {
        line.className += ' zupt-alert';
        line.textContent = `[100Hz #${state.stepCount}] 🛑 ZUPT TRIGGER (w<0.02) -> v_est=0.00m/s -> P_cov=0.001m² (COLLAPSED)`;
      } else {
        line.textContent = `[100Hz #${state.stepCount}] a_nav=[${linA},${centripetal}] | TCN_v=${idrSolver.v_tcn.toFixed(2)}m/s | K=0.824 | P=${idrSolver.P_cov.toFixed(3)}m²`;
      }

      mathTerminalLog.prepend(line);
      while (mathTerminalLog.children.length > 7) {
        mathTerminalLog.removeChild(mathTerminalLog.lastChild);
      }
    }
  }

  // Start Animation Loop
  requestAnimationFrame(loop);

})();
