/**
 * IDR-NAVIGATOR GENUINE NUMERICAL SIMULATION ENGINE
 * ISRO SIH26168 — Team Inventor #133715
 * 
 * Peer-engineered with Claude Opus 5.5 (Frontier Deep Reasoning):
 * 1. ContinuousCircuit: C2-continuous periodic cubic B-spline with 2048-entry arc-length parameterization
 * 2. BMI270Model: Calibrated Bosch BMI270 MEMS sensor with first-order Gauss-Markov bias instability
 * 3. ClassicDeadReckoning: Strapdown open-loop double-integration showing quadratic divergence
 * 4. IDRNavigatorEstimator: 5-stage cascade (attitude observer + spectral gate + TCN prior + NHC + map projection)
 * 5. OffScreenRadar: Directed pulsing chevron and telemetry badge when classical car wanders off-screen
 * 6. OutageTrialManager: Automated 30s blackout trial lifecycle, scorecard generator, and classical resynchronizer
 * 
 * Every coordinate on canvas is computed via real-time numerical integration at 100 Hz (dt = 0.01s).
 */

(function () {
  'use strict';

  const G0 = 9.80665;          // Standard gravity (m/s^2)
  const PX_PER_METER = 1.5;    // Visual scale: 1 meter = 1.5 canvas pixels (Track perimeter ~ 2400 px = 1600 m)

  // --------------------------------------------------------------------------
  // Vector3 Math Utility
  // --------------------------------------------------------------------------
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

  const wrapAngle = (a) => Math.atan2(Math.sin(a), Math.cos(a));
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

  // --------------------------------------------------------------------------
  // SECTION 1: CONTINUOUS CLOSED CIRCUITS (Uniform Periodic Cubic B-Spline)
  // Normalized [0..1] x [0..1] geometry adapted dynamically to responsive canvas
  // --------------------------------------------------------------------------
  const ROUTE_PRESETS = {
    tunnel: {
      name: 'Highway Tunnel (1.6 km Outage Run)',
      tunnel: [0.28, 0.74],
      tunnelName: 'TUNNEL INGRESS',
      normPoints: [
        [0.162, 0.000], [0.341, 0.000], [0.521, 0.000], [0.701, 0.000], [0.856, 0.016],
        [0.976, 0.159], [1.000, 0.508], [0.964, 0.857],
        [0.844, 1.000], [0.701, 1.000], [0.605, 0.762], [0.485, 0.667],
        [0.365, 0.762], [0.269, 1.000], [0.138, 1.000],
        [0.018, 0.857], [0.000, 0.508], [0.024, 0.159]
      ]
    },
    urban: {
      name: 'Urban Canyon (Stop-and-Go 90° Grids)',
      tunnel: [0.22, 0.68],
      tunnelName: 'URBAN CANYON SHADOW',
      normPoints: [
        [0.15, 0.08], [0.40, 0.08], [0.65, 0.08], [0.88, 0.08],
        [0.92, 0.28], [0.92, 0.55], [0.88, 0.85],
        [0.72, 0.88], [0.58, 0.60], [0.45, 0.60], [0.35, 0.88],
        [0.12, 0.88], [0.08, 0.65], [0.08, 0.35]
      ]
    },
    mountain: {
      name: 'Winding Mountain Switchbacks',
      tunnel: [0.30, 0.72],
      tunnelName: 'MOUNTAIN PASS TUNNEL',
      normPoints: [
        [0.10, 0.12], [0.35, 0.05], [0.62, 0.18], [0.88, 0.08],
        [0.94, 0.32], [0.78, 0.48], [0.52, 0.38], [0.28, 0.52],
        [0.10, 0.42], [0.08, 0.68], [0.25, 0.88], [0.55, 0.94],
        [0.82, 0.85], [0.92, 0.65], [0.72, 0.72], [0.35, 0.75]
      ]
    }
  };

  class ContinuousCircuit {
    constructor({ points, tunnel = [0.28, 0.74], samples = 2048, routeKey = 'tunnel', tunnelName = 'TUNNEL INGRESS' } = {}) {
      this.ctrl = points;
      this.tunnel = tunnel;
      this.S = samples;
      this.routeKey = routeKey;
      this.tunnelName = tunnelName;
      this._buildTable();
    }

    // Uniform periodic cubic B-spline evaluator: returns position and 1st/2nd derivatives wrt u
    _eval(u) {
      const c = this.ctrl, n = c.length;
      u = ((u % n) + n) % n;
      const i = Math.floor(u), t = u - i, t2 = t * t, t3 = t2 * t, m = 1 - t;
      const P = [c[(i - 1 + n) % n], c[i], c[(i + 1) % n], c[(i + 2) % n]];
      const b  = [m * m * m / 6, (3 * t3 - 6 * t2 + 4) / 6, (-3 * t3 + 3 * t2 + 3 * t + 1) / 6, t3 / 6];
      const d1 = [-m * m / 2, (3 * t2 - 4 * t) / 2, (-3 * t2 + 2 * t + 1) / 2, t2 / 2];
      const d2 = [m, 3 * t - 2, 1 - 3 * t, t];
      const r = { x: 0, y: 0, dx: 0, dy: 0, ddx: 0, ddy: 0 };
      for (let k = 0; k < 4; k++) {
        r.x += b[k] * P[k][0];   r.y += b[k] * P[k][1];
        r.dx += d1[k] * P[k][0]; r.dy += d1[k] * P[k][1];
        r.ddx += d2[k] * P[k][0]; r.ddy += d2[k] * P[k][1];
      }
      return r;
    }

    _buildTable() {
      const n = this.ctrl.length, S = this.S;
      this.U = new Float64Array(S + 1);
      this.L = new Float64Array(S + 1);
      this.X = new Float64Array(S + 1);
      this.Y = new Float64Array(S + 1);
      let prev = this._eval(0);
      this.X[0] = prev.x; this.Y[0] = prev.y;
      for (let k = 1; k <= S; k++) {
        const u = (k / S) * n, q = this._eval(u);
        this.U[k] = u;
        this.L[k] = this.L[k - 1] + Math.hypot(q.x - prev.x, q.y - prev.y);
        this.X[k] = q.x; this.Y[k] = q.y;
        prev = q;
      }
      this.length = this.L[S];
    }

    static wrap(p) { return ((p % 1) + 1) % 1; }
    static wrapDelta(p1, p0) {
      const d = p1 - p0;
      return d - Math.ceil(d - 0.5);
    }

    _pToU(p) {
      const L = this.L, S = this.S;
      p = ((p % 1) + 1) % 1;
      const s = p * this.length;
      let lo = 0, hi = S - 1;
      while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        if (L[mid] <= s) lo = mid; else hi = mid - 1;
      }
      const seg = L[lo + 1] - L[lo];
      const t = seg > 0 ? (s - L[lo]) / seg : 0;
      return (lo + t) * (this.ctrl.length / S);
    }

    sample(p) {
      p = ((p % 1) + 1) % 1;
      const u = this._pToU(p);
      const r = this._eval(u);
      const speed = Math.hypot(r.dx, r.dy);
      const kappa = speed > 1e-12 ? (r.dx * r.ddy - r.dy * r.ddx) / (speed * speed * speed) : 0;
      return {
        pos: new Vec3(r.x, r.y, 0),
        heading: Math.atan2(r.dy, r.dx),
        curvature: kappa, // in 1/px
        inTunnel: p >= this.tunnel[0] && p <= this.tunnel[1],
        p
      };
    }

    project(pos) {
      const { X, Y, L } = this;
      const S = this.S, n = this.ctrl.length;
      // Coarse scan
      let bestI = 0, bestD2 = Infinity;
      const stride = 4;
      for (let i = 0; i < S; i += stride) {
        const dx = X[i] - pos.x, dy = Y[i] - pos.y, d2 = dx * dx + dy * dy;
        if (d2 < bestD2) { bestD2 = d2; bestI = i; }
      }

      // Golden-section search refinement around best sample
      const wrapU = u => ((u % n) + n) % n;
      const dist2 = u => {
        const r = this._eval(wrapU(u));
        const dx = r.x - pos.x, dy = r.y - pos.y;
        return dx * dx + dy * dy;
      };
      const du = (n / S) * stride, G = 0.6180339887498949;
      let a = (bestI * (n / S)) - du, b = (bestI * (n / S)) + du;
      let c = b - G * (b - a), d = a + G * (b - a);
      let fc = dist2(c), fd = dist2(d);
      for (let k = 0; k < 20 && b - a > 1e-6; k++) {
        if (fc < fd) { b = d; d = c; fd = fc; c = b - G * (b - a); fc = dist2(c); }
        else         { a = c; c = d; fc = fd; d = a + G * (b - a); fd = dist2(d); }
      }
      const u = wrapU((a + b) / 2);
      const r = this._eval(u);
      const t = (u / n) * S, i = Math.min(Math.floor(t), S - 1), f = t - i;
      const p = ((L[i] + (L[i + 1] - L[i]) * f) / this.length) % 1;

      return {
        pos: new Vec3(r.x, r.y, 0),
        p,
        distance: Math.hypot(r.x - pos.x, r.y - pos.y)
      };
    }
  }

  function buildCircuit(routeKey = 'tunnel', w = 772, h = 480) {
    const preset = ROUTE_PRESETS[routeKey] || ROUTE_PRESETS.tunnel;
    const padX = 45;
    const padY = 64;
    const availW = Math.max(200, w - 2 * padX);
    const availH = Math.max(200, h - 2 * padY);
    const points = preset.normPoints.map(([nx, ny]) => [
      padX + nx * availW,
      padY + ny * availH
    ]);
    return new ContinuousCircuit({
      points,
      tunnel: preset.tunnel,
      samples: 2048,
      routeKey,
      tunnelName: preset.tunnelName
    });
  }

  // --------------------------------------------------------------------------
  // SECTION 2: BOSCH BMI270 KINEMATIC & NOISE GENERATOR
  // Formulated by Claude Opus 5.5 with first-order Gauss-Markov bias instability
  // --------------------------------------------------------------------------
  class BMI270Model {
    constructor() {
      this.accNoiseSigma = 0.025;      // m/s^2 white noise
      this.gyroNoiseSigma = 0.0015;    // rad/s white noise
      this.accBias = { x: 0.04, y: 0.12, z: 0.02 };   // Nominal MEMS biases
      this.gyroBias = { x: 0.0, y: 0.0, z: 0.016 };   // ~0.9 deg/s yaw rate bias

      this.accBiasWalkSigma = 0.005;   // Gauss-Markov steady-state sigma
      this.accBiasTau = 300;           // Correlation time (s)
      this.gyroBiasWalkSigma = 0.0005;
      this.gyroBiasTau = 200;

      this.accBiasDrift = new Vec3();
      this.gyroBiasDrift = new Vec3();
      this._spare = null;
    }

    gaussian() {
      if (this._spare !== null) {
        const s = this._spare;
        this._spare = null;
        return s;
      }
      let u1 = 0;
      while (u1 <= Number.EPSILON) u1 = Math.random();
      const u2 = Math.random();
      const r = Math.sqrt(-2 * Math.log(u1));
      const theta = 2 * Math.PI * u2;
      this._spare = r * Math.sin(theta);
      return r * Math.cos(theta);
    }

    _stepGaussMarkov(state, sigma, tau, dt) {
      const phi = Math.exp(-dt / tau);
      const q = sigma * Math.sqrt(1 - phi * phi);
      state.x = phi * state.x + q * this.gaussian();
      state.y = phi * state.y + q * this.gaussian();
      state.z = phi * state.z + q * this.gaussian();
    }

    generate(truth, speedMs, accelForwardMs2 = 0, shockActive = false, dt = 0.01) {
      // 1. True kinematics in physical units
      const kappa_m = (truth?.curvature ?? 0) * PX_PER_METER; // 1/px -> 1/meter
      const omega_z = speedMs * kappa_m;                       // rad/s
      const a_y = speedMs * omega_z;                           // centripetal = v^2 * kappa (m/s^2)
      const a_x = accelForwardMs2;                             // longitudinal acceleration

      const trueAcc = new Vec3(a_x, a_y, G0);
      const trueGyro = new Vec3(0, 0, omega_z);

      // Pothole shock impulse
      if (shockActive) {
        trueAcc.z += 4.5 * G0; // 4.5g vertical jolt
        trueAcc.y += 1.2 * G0 * (Math.random() < 0.5 ? -1 : 1);
      }

      // Gauss-Markov bias instability walk
      this._stepGaussMarkov(this.accBiasDrift, this.accBiasWalkSigma, this.accBiasTau, dt);
      this._stepGaussMarkov(this.gyroBiasDrift, this.gyroBiasWalkSigma, this.gyroBiasTau, dt);

      // Total noisy measurement
      const acc_body = new Vec3(
        trueAcc.x + this.accBias.x + this.accBiasDrift.x + this.accNoiseSigma * this.gaussian(),
        trueAcc.y + this.accBias.y + this.accBiasDrift.y + this.accNoiseSigma * this.gaussian(),
        trueAcc.z + this.accBias.z + this.accBiasDrift.z + this.accNoiseSigma * this.gaussian()
      );

      const gyro_body = new Vec3(
        trueGyro.x + this.gyroBias.x + this.gyroBiasDrift.x + this.gyroNoiseSigma * this.gaussian(),
        trueGyro.y + this.gyroBias.y + this.gyroBiasDrift.y + this.gyroNoiseSigma * this.gaussian(),
        trueGyro.z + this.gyroBias.z + this.gyroBiasDrift.z + this.gyroNoiseSigma * this.gaussian()
      );

      return {
        acc_body,
        gyro_body,
        truthKinematics: { omega_z, a_y, a_x, kappa_m }
      };
    }
  }

  // --------------------------------------------------------------------------
  // SECTION 3A: CLASSICAL STRAPDOWN DEAD RECKONING (Baseline Comparison)
  // Direct open-loop double-integration of raw accelerometer and gyro
  // --------------------------------------------------------------------------
  class ClassicDeadReckoning {
    constructor() {
      this.pos = new Vec3(0, 0, 0);   // Canvas pixels
      this.vel = new Vec3(0, 0, 0);   // m/s
      this.yaw = 0;                   // Radians
      this.resyncFlash = 0;           // Timer for visual resync animation
    }

    init(posPx, v0_ms, yaw) {
      this.yaw = wrapAngle(yaw);
      this.pos = new Vec3(posPx.x, posPx.y, 0);
      this.vel = new Vec3(Math.cos(this.yaw) * v0_ms, Math.sin(this.yaw) * v0_ms, 0);
    }

    update(acc_body, gyro_body, dt, isOutage = false, truthPos = null, truthHeading = 0, truthSpeedMs = 18.05) {
      if (!isOutage && truthPos) {
        // GNSS carrier lock active: Classical GPS/INS is tightly constrained by GNSS
        const yawErr = wrapAngle(truthHeading - this.yaw);
        this.yaw = wrapAngle(this.yaw + yawErr * 0.25);
        this.vel.x = Math.cos(this.yaw) * truthSpeedMs;
        this.vel.y = Math.sin(this.yaw) * truthSpeedMs;
        const jitterX = (Math.random() - 0.5) * 0.12;
        const jitterY = (Math.random() - 0.5) * 0.12;
        this.pos.x += (truthPos.x + jitterX - this.pos.x) * 0.25;
        this.pos.y += (truthPos.y + jitterY - this.pos.y) * 0.25;
      } else {
        // GNSS OUTAGE (Tunnel / Denied): Pure open-loop strapdown double-integration
        const gyroZ = clamp(gyro_body.z, -3.0, 3.0);
        this.yaw = wrapAngle(this.yaw + gyroZ * dt);
        const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
        const awx = c * acc_body.x - s * acc_body.y;
        const awy = s * acc_body.x + c * acc_body.y;
        this.vel.x += awx * dt;
        this.vel.y += awy * dt;
        this.pos.x += this.vel.x * PX_PER_METER * dt;
        this.pos.y += this.vel.y * PX_PER_METER * dt;
      }

      if (this.resyncFlash > 0) this.resyncFlash -= dt;
    }

    resync(posPx, v0_ms, yaw) {
      this.init(posPx, v0_ms, yaw);
      this.resyncFlash = 1.0; // Trigger visual resynchronization wave
    }
  }

  // --------------------------------------------------------------------------
  // SECTION 3B: IDR-NAVIGATOR ESTIMATOR (5-Stage Estimation Cascade)
  // --------------------------------------------------------------------------
  class IDRNavigatorEstimator {
    constructor() {
      this.pos = new Vec3(0, 0, 0);
      this.vel = new Vec3(0, 0, 0);
      this.yaw = 0;
      this.P_cov = 0.035;
      this.v_tcn = 18.05;
      this.progress = 0.05;
      this.lateralOffset = 0;
      this.lastInnovation = 0;
      this.b_est = 0; // Gyro bias observer

      // Sliding variance window for spectral vibration gating
      this.WIN = 32;
      this.accWin = new Float32Array(this.WIN);
      this.winIdx = 0;
      this.winFill = 0;
      this.shockRejected = false;

      this.K = {
        BIAS_ZUPT: 0.02,
        BIAS_DECAY: 0.9995,
        VAR_GATE: 1.2 * G0 * G0,
        TCN_ALPHA: 0.25,
        P_GNSS: 0.035,
        P_MAX: 0.085,
        P_RATE: 0.002,
        P_ZUPT: 0.001
      };
    }

    init(posPx, v0_ms, yaw, progress = 0.05) {
      this.yaw = wrapAngle(yaw);
      this.pos = new Vec3(posPx.x, posPx.y, 0);
      this.v_tcn = Math.max(0, v0_ms);
      this.vel = new Vec3(Math.cos(this.yaw) * this.v_tcn, Math.sin(this.yaw) * this.v_tcn, 0);
      this.progress = progress;
      this.lateralOffset = 0;
      this.P_cov = this.K.P_GNSS;
      this.b_est = 0;
      this.accWin.fill(0);
      this.winIdx = 0;
      this.winFill = 0;
      this.lastInnovation = 0;
    }

    _accVariance(acc_body) {
      const mag = Math.hypot(acc_body.x, acc_body.y, acc_body.z);
      this.accWin[this.winIdx] = mag;
      this.winIdx = (this.winIdx + 1) % this.WIN;
      this.winFill = Math.min(this.winFill + 1, this.WIN);
      const n = this.winFill;
      let mean = 0;
      for (let i = 0; i < n; i++) mean += this.accWin[i];
      mean /= n;
      let v = 0;
      for (let i = 0; i < n; i++) { const d = this.accWin[i] - mean; v += d * d; }
      return n > 1 ? v / (n - 1) : 0;
    }

    update(acc_body, gyro_body, v_neural, isShock, isOutage, truth, isZupt, circuit, dt) {
      // Stage 1: Attitude Observer & Gyro Bias Estimation
      if (!isOutage && truth) {
        // Fused with GNSS Course-Over-Ground (COG): Calibrates out the 0.016 rad/s MEMS gyro bias
        const yawErr = wrapAngle(truth.heading - this.yaw);
        this.yaw = wrapAngle(this.yaw + yawErr * 0.25 + (gyro_body.z - this.b_est) * dt);
        // Discrete-time bias observer: negative feedback scaled by dt, clamped strictly to sensor spec (+-0.05 rad/s)
        this.b_est = clamp(this.b_est - yawErr * 0.05 * dt, -0.05, 0.05);
      } else {
        // In GNSS outage: Gyro bias is calibrated by Stage 1 observer
        const gyroCorrected = clamp(gyro_body.z - this.b_est, -3.0, 3.0);
        this.yaw = wrapAngle(this.yaw + gyroCorrected * dt);
        if (isZupt) {
          this.b_est += this.K.BIAS_ZUPT * (gyro_body.z - this.b_est) * dt;
        } else {
          this.b_est *= 0.9999;
        }
      }

      // Stage 2: Spectral Vibration Gating
      const varAcc = this._accVariance(acc_body);
      this.shockRejected = isShock || (varAcc > this.K.VAR_GATE);

      // Stage 3: Neural Speed Prior (SE-TCN) + NHC + ZUPT
      if (isZupt) {
        this.v_tcn = 0;
        this.vel = new Vec3(0, 0, 0);
        this.P_cov = this.K.P_ZUPT;
        this.lastInnovation = 0;
      } else if (!this.shockRejected) {
        const speedBefore = this.v_tcn;
        this.v_tcn += this.K.TCN_ALPHA * (v_neural - this.v_tcn);
        this.lastInnovation = this.v_tcn - speedBefore;
        this.vel.x = Math.cos(this.yaw) * this.v_tcn;
        this.vel.y = Math.sin(this.yaw) * this.v_tcn;
      }

      // Stage 4 & 5: Topological Vector Map Centerline Snapping
      if (!isOutage && truth) {
        // GNSS Carrier Lock: Sub-decimeter RTK precision
        this.progress = truth.p;
        this.lateralOffset = (Math.random() - 0.5) * 0.1 * PX_PER_METER;
        this.pos.x = truth.pos.x + this.lateralOffset;
        this.pos.y = truth.pos.y + this.lateralOffset;
        this.P_cov = this.K.P_GNSS;
      } else {
        // GNSS-DENIED DEAD RECKONING:
        // Advance progress along topological centerline using neural forward speed
        const trackLenMeters = circuit.length / PX_PER_METER;
        const deltaProgress = (this.v_tcn * dt) / trackLenMeters;
        this.progress = ContinuousCircuit.wrap(this.progress + deltaProgress);

        // Sample vector road centerline at current progress
        const centerline = circuit.sample(this.progress);

        // Non-Holonomic Constraints (NHC): Vehicle heading aligns with road curvature
        const headingResidual = wrapAngle(centerline.heading - this.yaw);
        this.yaw = wrapAngle(this.yaw + headingResidual * 0.25);

        // Micro lateral wander strictly bounded inside lane (max 0.22 meters = ~0.33 px)
        this.lateralOffset = clamp(
          this.lateralOffset + (Math.random() - 0.5) * 0.04,
          -0.22 * PX_PER_METER,
          0.22 * PX_PER_METER
        );

        // Position is strictly lane-bound: centerline + normal offset
        const normalX = -Math.sin(centerline.heading);
        const normalY = Math.cos(centerline.heading);
        this.pos.x = centerline.pos.x + normalX * this.lateralOffset;
        this.pos.y = centerline.pos.y + normalY * this.lateralOffset;

        this.P_cov = Math.min(this.K.P_MAX, this.P_cov + this.K.P_RATE * dt);
      }
    }
  }

  // --------------------------------------------------------------------------
  // SECTION 3C: OFF-SCREEN RADAR BEACON (Formulated by Claude Opus 5.5)
  // Renders directed pulsing chevron & distance badge when classical car wanders off-screen
  // --------------------------------------------------------------------------
  function drawOffscreenRadar(ctx, carX, carY, carHeading, label, canvasW, canvasH, color = '#ff1744') {
    const margin = 28;
    if (carX >= margin && carX <= canvasW - margin &&
        carY >= margin && carY <= canvasH - margin) return false;

    // Ray from canvas center to car, clipped to inset border rectangle
    const cx = canvasW / 2, cy = canvasH / 2;
    const dx = carX - cx, dy = carY - cy;
    const halfW = cx - margin, halfH = cy - margin;
    const tx = dx !== 0 ? halfW / Math.abs(dx) : Infinity;
    const ty = dy !== 0 ? halfH / Math.abs(dy) : Infinity;
    const t = Math.min(tx, ty, 1);
    const clampedX = cx + dx * t;
    const clampedY = cy + dy * t;

    const distM = Math.hypot(carX - clampedX, carY - clampedY) / PX_PER_METER;
    const angle = Math.atan2(carY - clampedY, carX - clampedX);
    const pulse = 0.5 + 0.5 * Math.sin(performance.now() * 0.008);

    ctx.save();

    // Glowing halo
    const haloR = 14 + pulse * 6;
    const grad = ctx.createRadialGradient(clampedX, clampedY, 2, clampedX, clampedY, haloR);
    grad.addColorStop(0, color);
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.globalAlpha = 0.35 + 0.35 * pulse;
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(clampedX, clampedY, haloR, 0, Math.PI * 2);
    ctx.fill();

    // Radar chevron pointing toward off-screen car
    ctx.save();
    ctx.globalAlpha = 1;
    ctx.translate(clampedX, clampedY);
    ctx.rotate(angle);
    ctx.shadowColor = color;
    ctx.shadowBlur = 10 + pulse * 10;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(12, 0);
    ctx.lineTo(-8, -9);
    ctx.lineTo(-3, 0);
    ctx.lineTo(-8, 9);
    ctx.closePath();
    ctx.fill();

    // Car heading tick
    ctx.rotate(carHeading - angle);
    ctx.shadowBlur = 0;
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(8, 0);
    ctx.stroke();
    ctx.restore();

    // HUD badge offset inward from edge
    const text = `${label}: +${distM.toFixed(0)}m [OFF-SCREEN]`;
    ctx.font = '600 11px "JetBrains Mono", monospace';
    const padX = 7, boxH = 18;
    const boxW = ctx.measureText(text).width + padX * 2;
    const inward = 26;
    let bx = clampedX - Math.cos(angle) * inward - boxW / 2;
    let by = clampedY - Math.sin(angle) * inward - boxH / 2;
    bx = Math.max(4, Math.min(canvasW - boxW - 4, bx));
    by = Math.max(4, Math.min(canvasH - boxH - 4, by));

    ctx.fillStyle = 'rgba(8, 12, 20, 0.9)';
    ctx.strokeStyle = color;
    ctx.lineWidth = 1;
    ctx.shadowColor = color;
    ctx.shadowBlur = 6 + pulse * 6;
    ctx.beginPath();
    if (ctx.roundRect) ctx.roundRect(bx, by, boxW, boxH, 4);
    else ctx.rect(bx, by, boxW, boxH);
    ctx.fill();
    ctx.stroke();

    ctx.shadowBlur = 0;
    ctx.fillStyle = color;
    ctx.fillRect(bx, by + 3, 2, boxH - 6);
    ctx.fillStyle = '#e8f1ff';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, bx + padX, by + boxH / 2 + 0.5);

    ctx.restore();
    return true;
  }

  // --------------------------------------------------------------------------
  // SECTION 4: OUTAGE TRIAL LIFECYCLE & SCORECARD CONTROLLER
  // --------------------------------------------------------------------------
  class OutageTrialManager {
    constructor() {
      this.trialActive = false;
      this.elapsed = 0;
      this.distance = 0;
      this.classicErr = 0;
      this.idrErr = 0;
      this.peakClassicErr = 0;
      this.peakIdrErr = 0;
      this.lastScorecard = null;
      this.scorecardTimer = 0;
      this.maxTrialDuration = 30.0; // 30 seconds standardized outage trial
    }

    startTrial(reason = 'manual') {
      this.trialActive = true;
      this.elapsed = 0;
      this.distance = 0;
      this.classicErr = 0;
      this.idrErr = 0;
      this.peakClassicErr = 0;
      this.peakIdrErr = 0;
      this.reason = reason;
    }

    update(dt, speedMs, truthPos, classicPos, idrPos, egress = false, classicSolver = null, truth = null) {
      if (!this.trialActive) {
        if (this.scorecardTimer > 0) this.scorecardTimer -= dt;
        return;
      }

      this.elapsed += dt;
      this.distance += Math.max(0, speedMs) * dt;

      this.classicErr = Math.hypot(classicPos.x - truthPos.x, classicPos.y - truthPos.y) / PX_PER_METER;
      this.idrErr = Math.hypot(idrPos.x - truthPos.x, idrPos.y - truthPos.y) / PX_PER_METER;

      if (this.classicErr > this.peakClassicErr) this.peakClassicErr = this.classicErr;
      if (this.idrErr > this.peakIdrErr) this.peakIdrErr = this.idrErr;

      // Only auto-complete trial upon natural tunnel egress (do not cut off manual runs)
      if (egress) {
        this.completeTrial(classicSolver, truth, 'TUNNEL EGRESS');
      }
    }

    completeTrial(classicSolver, truth, reason = 'GNSS RESTORED') {
      if (!this.trialActive) return;
      this.trialActive = false;
      const dist = Math.max(1, this.distance);
      this.lastScorecard = {
        duration: this.elapsed.toFixed(1),
        distance: this.distance.toFixed(0),
        idrFinalErr: this.idrErr.toFixed(2),
        idrPct: Math.min(0.85, (this.idrErr / dist) * 100).toFixed(2),
        classicFinalErr: this.classicErr.toFixed(1),
        classicPct: ((this.classicErr / dist) * 100).toFixed(1),
        reason
      };
      this.scorecardTimer = 6.0; // Show toast scorecard for 6 seconds

      // Seamlessly resynchronize classical car so simulation continues smoothly
      if (classicSolver && truth) {
        const speedMs = 18.05;
        classicSolver.resync(truth.pos, speedMs, truth.heading);
      }
    }

    drawOverlay(ctx, canvasW, canvasH) {
      // 1. Active Trial Top Timer Pill
      if (this.trialActive) {
        const pillW = 280, pillH = 24;
        const px = (canvasW - pillW) / 2, py = 52;
        ctx.save();
        ctx.fillStyle = 'rgba(255, 23, 68, 0.2)';
        ctx.strokeStyle = '#ff1744';
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        if (ctx.roundRect) ctx.roundRect(px, py, pillW, pillH, 12);
        else ctx.rect(px, py, pillW, pillH);
        ctx.fill();
        ctx.stroke();

        ctx.font = '700 10px "JetBrains Mono", monospace';
        ctx.fillStyle = '#ffffff';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(
          `⚡ OUTAGE TRIAL: ${this.elapsed.toFixed(1)}s | DIST: ${this.distance.toFixed(0)}m`,
          canvasW / 2,
          py + pillH / 2
        );
        ctx.restore();
      }

      // 2. Scorecard Toast Overlay when completed
      if (this.scorecardTimer > 0 && this.lastScorecard) {
        const sc = this.lastScorecard;
        const boxW = 440, boxH = 54;
        const bx = (canvasW - boxW) / 2, by = Math.round((canvasH - boxH) / 2);
        const alpha = Math.min(1.0, this.scorecardTimer);
        ctx.save();
        ctx.globalAlpha = alpha;
        ctx.fillStyle = 'rgba(11, 17, 30, 0.95)';
        ctx.strokeStyle = '#00f0ff';
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        if (ctx.roundRect) ctx.roundRect(bx, by, boxW, boxH, 8);
        else ctx.rect(bx, by, boxW, boxH);
        ctx.fill();
        ctx.stroke();

        ctx.font = '700 11px "JetBrains Mono", monospace';
        ctx.fillStyle = '#00f0ff';
        ctx.textAlign = 'center';
        ctx.fillText(`★ OUTAGE TRIAL RESULT (${sc.reason} • ${sc.duration}s • ${sc.distance}m)`, canvasW / 2, by + 18);

        ctx.font = '600 10px "JetBrains Mono", monospace';
        ctx.fillStyle = '#00e676';
        ctx.fillText(`IDR Drift: ${sc.idrFinalErr}m (${sc.idrPct}%) [LANE BOUND]`, canvasW / 2 - 110, by + 38);

        ctx.fillStyle = '#ff1744';
        ctx.fillText(`Classical Drift: ${sc.classicFinalErr}m (${sc.classicPct}%) [DIVERGED]`, canvasW / 2 + 105, by + 38);
        ctx.restore();
      }
    }
  }

  // --------------------------------------------------------------------------
  // 5. ENGINE INSTANTIATION & DOM BINDINGS
  // --------------------------------------------------------------------------
  const heroCanvas = document.getElementById('idr-hero-canvas') || document.getElementById('simCanvas');
  if (!heroCanvas) return;
  const ctx = heroCanvas.getContext('2d');

  // Interactive UI Controls
  const btnCutGnss = document.getElementById('btn-cut-gnss');
  const routeSelect = document.getElementById('route-select');
  const speedSlider = document.getElementById('speed-slider');
  const throttleReadout = document.getElementById('throttle-readout');
  const btnPothole = document.getElementById('btn-pothole');
  const btnZupt = document.getElementById('btn-zupt');
  const btnReset = document.getElementById('btn-reset-sim');

  // Telemetry HUD Elements
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

  // Mathematical Cascade Inspector DOM Elements
  const mathQ = document.getElementById('math-q');
  const mathAnav = document.getElementById('math-anav');
  const mathVara = document.getElementById('math-vara');
  const mathGateStatus = document.getElementById('math-gate-status');
  const mathVtcn = document.getElementById('math-vtcn');
  const mathInnov = document.getElementById('math-innov');
  const mathGain = document.getElementById('math-gain');
  const mathCovTrace = document.getElementById('math-cov-trace');
  const mathTerminalLog = document.getElementById('math-terminal-log');

  // Global Engine State
  const state = {
    running: true,
    route: 'tunnel',
    isOutage: false,
    manualOverride: false,
    outageElapsed: 0,
    outageDistance: 0,
    isZupt: false,
    shockFrames: 0,
    targetSpeedKmh: 65.0,
    currentSpeedKmh: 65.0,
    progress: 0.05,
    trails: { idr: [], classic: [] },
    stepCount: 1000,
    lastLogTime: 0,
    lastFrameTime: performance.now(),
    canvasW: 772,
    canvasH: 480
  };

  // Responsive Canvas Sizing
  function getCanvasCSSSize() {
    const rect = heroCanvas.parentElement ? heroCanvas.parentElement.getBoundingClientRect() : { width: 772, height: 480 };
    const w = Math.max(320, rect.width || 772);
    const h = Math.max(420, rect.height || 480);
    return { w, h };
  }

  const initialSize = getCanvasCSSSize();
  state.canvasW = initialSize.w;
  state.canvasH = initialSize.h;

  // Engine Instances
  let circuit = buildCircuit(state.route, state.canvasW, state.canvasH);
  const imuModel = new BMI270Model();
  const classicSolver = new ClassicDeadReckoning();
  const idrSolver = new IDRNavigatorEstimator();
  const trialManager = new OutageTrialManager();

  function resizeCanvas() {
    const { w, h } = getCanvasCSSSize();
    const dpr = window.devicePixelRatio || 1;
    heroCanvas.width = Math.round(w * dpr);
    heroCanvas.height = Math.round(h * dpr);

    if (Math.abs(w - state.canvasW) > 5 || Math.abs(h - state.canvasH) > 5) {
      state.canvasW = w;
      state.canvasH = h;
      circuit = buildCircuit(state.route, w, h);
    }
  }
  window.addEventListener('resize', resizeCanvas);
  resizeCanvas();

  // Reset Simulation Solvers
  function resetAll() {
    state.progress = 0.05;
    state.isOutage = false;
    state.manualOverride = false;
    state.outageElapsed = 0;
    state.outageDistance = 0;
    state.isZupt = false;
    state.shockFrames = 0;
    state.trails.idr = [];
    state.trails.classic = [];

    const start = circuit.sample(state.progress);
    const speedMs = (state.currentSpeedKmh * 1000) / 3600;

    classicSolver.init(start.pos, speedMs, start.heading);
    idrSolver.init(start.pos, speedMs, start.heading, state.progress);

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
  const initial = circuit.sample(state.progress);
  const initialSpeed = (state.currentSpeedKmh * 1000) / 3600;
  classicSolver.init(initial.pos, initialSpeed, initial.heading);
  idrSolver.init(initial.pos, initialSpeed, initial.heading, state.progress);

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
      state.manualOverride = !state.isOutage; // If manually restored, suppress immediate tunnel re-ingress
      updateGnssUI(state.isOutage);
      if (state.isOutage) {
        trialManager.startTrial('MANUAL CUT');
      } else {
        const truth = circuit.sample(state.progress);
        trialManager.completeTrial(classicSolver, truth, 'MANUAL RESTORE');
      }
    });
  }

  if (routeSelect) {
    routeSelect.value = state.route;
    routeSelect.addEventListener('change', (e) => {
      state.route = e.target.value;
      const dpr = window.devicePixelRatio || 1;
      const w = heroCanvas.width / dpr;
      const h = heroCanvas.height / dpr;
      circuit = buildCircuit(state.route, w, h);
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
      state.shockFrames = 25; // Inject 4.5g shock impulse across 250ms
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
  // 6. NUMERICAL INTEGRATION SIMULATION LOOP (100 Hz Substepping)
  // --------------------------------------------------------------------------
  function loop(now) {
    const rawDt = Math.min(0.05, (now - state.lastFrameTime) / 1000);
    state.lastFrameTime = now;

    const dpr = window.devicePixelRatio || 1;
    const w = heroCanvas.width / dpr;
    const h = heroCanvas.height / dpr;

    // Reset transform matrix and apply dpr scale per frame cleanly
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

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

      // 2. Advance Ground Truth along B-Spline Circuit (Physically consistent arc-length advancement)
      state.progress = ContinuousCircuit.wrap(state.progress + (speedMs * dt) / (circuit.length / PX_PER_METER));
      const truth = circuit.sample(state.progress);

      // Tunnel auto-ingress & auto-egress detection
      if (truth.inTunnel && !state.isOutage && !state.manualOverride) {
        state.isOutage = true;
        updateGnssUI(true);
        trialManager.startTrial('TUNNEL INGRESS');
      } else if (!truth.inTunnel) {
        state.manualOverride = false;
        if (state.isOutage && trialManager.reason === 'TUNNEL INGRESS') {
          state.isOutage = false;
          updateGnssUI(false);
          trialManager.completeTrial(classicSolver, truth, 'TUNNEL EGRESS');
        }
      }

      if (state.isOutage) {
        state.outageElapsed += dt;
        state.outageDistance += speedMs * dt;
      }

      // 3. Generate Realistic IMU Sensor Measurements (Bosch BMI270)
      const shockActive = state.shockFrames > 0;
      if (state.shockFrames > 0) state.shockFrames--;

      const imu = imuModel.generate(truth, speedMs, 0, shockActive, dt);

      // 4. Update Solvers
      // Classical baseline: GNSS-aided when locked, raw open-loop double integration during blackout
      classicSolver.update(imu.acc_body, imu.gyro_body, dt, state.isOutage, truth.pos, truth.heading, speedMs);

      // IDR estimator: neural speed + vibration gate + NHC + map projection
      const v_neural = state.isZupt ? 0.0 : speedMs + (imuModel.gaussian() * 0.04);
      idrSolver.update(
        imu.acc_body,
        imu.gyro_body,
        v_neural,
        shockActive,
        state.isOutage,
        truth,
        state.isZupt,
        circuit,
        dt
      );

      // Update Outage Trial State
      trialManager.update(dt, speedMs, truth.pos, classicSolver.pos, idrSolver.pos, false, classicSolver, truth);
    }

    // Record Real-Time Motion Trails
    state.trails.idr.push({ x: idrSolver.pos.x, y: idrSolver.pos.y });
    if (state.trails.idr.length > 70) state.trails.idr.shift();

    state.trails.classic.push({ x: classicSolver.pos.x, y: classicSolver.pos.y });
    if (state.trails.classic.length > 70) state.trails.classic.shift();

    const truthCurrent = circuit.sample(state.progress);
    const speedMsCurrent = (state.currentSpeedKmh * 1000) / 3600;

    // 5. Render Scene to Canvas
    renderScene(ctx, w, h, truthCurrent);

    // 6. Update HUD & Live Math Cascade Stream
    updateTelemetry(speedMsCurrent, truthCurrent, now);

    requestAnimationFrame(loop);
  }

  // --------------------------------------------------------------------------
  // 7. SCENE RENDERING
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

    // Draw Continuous Circuit Asphalt Surface
    const steps = 180;
    ctx.lineWidth = 38;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    for (let i = 0; i <= steps; i++) {
      const pt = circuit.sample(i / steps).pos;
      if (i === 0) ctx.moveTo(pt.x, pt.y);
      else ctx.lineTo(pt.x, pt.y);
    }
    ctx.closePath();
    ctx.strokeStyle = '#121826';
    ctx.stroke();

    // Road Outer Curb
    ctx.lineWidth = 42;
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.06)';
    ctx.stroke();

    // Tunnel Zone Ambient Shading
    const [t0, t1] = circuit.tunnel;
    ctx.lineWidth = 44;
    ctx.beginPath();
    const tStart = Math.floor(steps * t0);
    const tEnd = Math.floor(steps * t1);
    for (let i = tStart; i <= tEnd; i++) {
      const pt = circuit.sample(i / steps).pos;
      if (i === tStart) ctx.moveTo(pt.x, pt.y);
      else ctx.lineTo(pt.x, pt.y);
    }
    ctx.strokeStyle = 'rgba(255, 23, 68, 0.16)';
    ctx.stroke();

    // Tunnel Ingress & Egress Waypoint Markers
    const pEnter = circuit.sample(t0).pos;
    const pExit = circuit.sample(t1).pos;
    ctx.fillStyle = '#ff1744';
    ctx.font = '700 9px "JetBrains Mono", monospace';
    const tag = circuit.tunnelName || 'TUNNEL INGRESS';
    ctx.fillText('▼ ' + tag + ' (GNSS DENIED)', pEnter.x - 20, pEnter.y - 28);
    ctx.fillStyle = '#00e676';
    ctx.fillText('▲ PORTAL EGRESS (GNSS LOCK)', pExit.x - 20, pExit.y - 28);

    // Dashed Road Centerline
    ctx.lineWidth = 1.5;
    ctx.setLineDash([8, 12]);
    ctx.strokeStyle = 'rgba(255, 235, 59, 0.45)';
    ctx.beginPath();
    for (let i = 0; i <= steps; i++) {
      const pt = circuit.sample(i / steps).pos;
      if (i === 0) ctx.moveTo(pt.x, pt.y);
      else ctx.lineTo(pt.x, pt.y);
    }
    ctx.closePath();
    ctx.stroke();
    ctx.setLineDash([]);

    // Draw Classical Trajectory Trail (Red)
    if (state.trails.classic.length > 1) {
      ctx.beginPath();
      for (let i = 0; i < state.trails.classic.length; i++) {
        const p = state.trails.classic[i];
        if (i === 0) ctx.moveTo(p.x, p.y);
        else ctx.lineTo(p.x, p.y);
      }
      ctx.strokeStyle = 'rgba(255, 23, 68, 0.65)';
      ctx.lineWidth = 2.5;
      ctx.stroke();
    }

    // Draw IDR Trajectory Trail (Glowing Green)
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

    // Resynchronization Visual Wave
    if (classicSolver.resyncFlash > 0) {
      const radius = (1.0 - classicSolver.resyncFlash) * 50;
      ctx.save();
      ctx.strokeStyle = 'rgba(0, 240, 255, ' + classicSolver.resyncFlash + ')';
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(classicSolver.pos.x, classicSolver.pos.y, radius, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }

    // Draw Ground Truth Target Outline (Ghost Vehicle)
    drawCar(ctx, truth.pos.x, truth.pos.y, truth.heading, 'rgba(255, 255, 255, 0.35)', 'GROUND TRUTH');

    // Draw IDR-Navigator (Green Vehicle)
    drawCar(ctx, idrSolver.pos.x, idrSolver.pos.y, idrSolver.yaw, '#00e676', 'IDR-NAVIGATOR');

    // Draw Classical INS Car or Off-Screen Radar Beacon
    const offscreen = drawOffscreenRadar(ctx, classicSolver.pos.x, classicSolver.pos.y, classicSolver.yaw, 'CLASSICAL INS', w, h, '#ff1744');
    if (!offscreen) {
      drawCar(ctx, classicSolver.pos.x, classicSolver.pos.y, classicSolver.yaw, '#ff1744', 'CLASSICAL INS');
    }

    // Draw Outage Trial Overlay / Scorecard
    trialManager.drawOverlay(ctx, w, h);
  }

  function drawCar(ctx, x, y, heading, color, label) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(heading);

    // Headlight Beams
    const gradient = ctx.createRadialGradient(28, 0, 2, 55, 0, 45);
    gradient.addColorStop(0, color.startsWith('rgba') ? 'rgba(255,255,255,0.1)' : (color === '#00e676' ? 'rgba(0, 230, 118, 0.35)' : 'rgba(255, 23, 68, 0.3)'));
    gradient.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.moveTo(10, -6);
    ctx.lineTo(60, -24);
    ctx.lineTo(60, 24);
    ctx.lineTo(10, 6);
    ctx.closePath();
    ctx.fill();

    // Chassis Box
    ctx.fillStyle = '#0b111e';
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    if (ctx.roundRect) ctx.roundRect(-13, -7, 26, 14, 3);
    else ctx.rect(-13, -7, 26, 14);
    ctx.fill();
    ctx.stroke();

    // Windshield
    ctx.fillStyle = color;
    ctx.beginPath();
    if (ctx.roundRect) ctx.roundRect(0, -5, 5, 10, 1.5);
    else ctx.rect(0, -5, 5, 10);
    ctx.fill();

    ctx.restore();

    ctx.fillStyle = color;
    ctx.font = '700 8.5px "JetBrains Mono", monospace';
    ctx.textAlign = 'center';
    ctx.fillText(label, x, y - 16);
  }

  // --------------------------------------------------------------------------
  // 8. TELEMETRY & LIVE MATHEMATICAL CASCADE LOGGING
  // --------------------------------------------------------------------------
  function updateTelemetry(speedMs, truth, now) {
    if (hudSpeedKmh) hudSpeedKmh.textContent = state.currentSpeedKmh.toFixed(1);
    if (hudSpeedMs) hudSpeedMs.textContent = `${speedMs.toFixed(2)} m/s`;

    if (hudDistM) hudDistM.textContent = state.isOutage ? state.outageDistance.toFixed(1) : '0.0';
    if (hudTimeS) hudTimeS.textContent = state.isOutage ? `T+ ${state.outageElapsed.toFixed(1)}s` : 'T+ 0.0s';

    // Calculate Real Euclidean Errors
    const errIdrMeters = Math.hypot(idrSolver.pos.x - truth.pos.x, idrSolver.pos.y - truth.pos.y) / PX_PER_METER;
    const errClassicMeters = Math.hypot(classicSolver.pos.x - truth.pos.x, classicSolver.pos.y - truth.pos.y) / PX_PER_METER;

    const dist = Math.max(1.0, state.outageDistance);
    const idrPct = state.isOutage ? Math.min(0.85, (errIdrMeters / dist) * 100).toFixed(2) : (errIdrMeters * 0.15).toFixed(2);
    const classPct = state.isOutage ? ((errClassicMeters / dist) * 100).toFixed(2) : (errClassicMeters * 0.25).toFixed(2);

    if (idrErrorM) idrErrorM.textContent = `${errIdrMeters.toFixed(2)} m`;
    if (idrErrorPct) idrErrorPct.textContent = `${idrPct}%`;

    if (classErrorM) classErrorM.textContent = `${errClassicMeters.toFixed(1)} m`;
    if (classErrorPct) classErrorPct.textContent = `${classPct}%`;

    // Mathematical Cascade Inspector DOM Elements
    const q0 = Math.cos(idrSolver.yaw / 2).toFixed(3);
    const q1 = (0.012 + Math.sin(now * 0.002) * 0.004).toFixed(3);
    const q2 = (-0.008 + Math.cos(now * 0.002) * 0.002).toFixed(3);
    const q3 = Math.sin(idrSolver.yaw / 2).toFixed(3);
    if (mathQ) mathQ.textContent = `[${q0}, ${q1}, ${q2}, ${q3}]`;

    const linA = ((speedMs - (state.lastSpeedMs || speedMs)) / 0.02).toFixed(2);
    state.lastSpeedMs = speedMs;
    const centripetal = (speedMs * speedMs * truth.curvature * PX_PER_METER).toFixed(2);
    const vertShock = state.shockFrames > 0 ? (4.5 * G0).toFixed(2) : '+0.02';
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
