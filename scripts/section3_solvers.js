```javascript
/* ============================================================================
 * SECTION 3: Dual Solvers (Classical INS Divergence vs IDR 5-Stage Cascade)
 *            + Off-Screen Radar Beacon
 * Depends on (Sections 1–2): Vec3, PX_PER_METER (1.5), G0 (9.80665)
 * ==========================================================================*/

const wrapAngle = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

/* ----------------------------------------------------------------------------
 * 1. Classical Strapdown Dead Reckoning (open-loop, divergent by design)
 * --------------------------------------------------------------------------*/
class ClassicDeadReckoning {
  constructor() {
    this.pos = new Vec3(0, 0, 0);   // pixels
    this.vel = new Vec3(0, 0, 0);   // m/s
    this.yaw = 0;                   // rad
    this.justResynced = false;
  }

  init(posPx, v0_ms, yaw) {
    this.yaw = wrapAngle(yaw);
    this.pos.x = posPx.x;
    this.pos.y = posPx.y;
    this.pos.z = 0;
    this.vel.x = Math.cos(this.yaw) * v0_ms;
    this.vel.y = Math.sin(this.yaw) * v0_ms;
    this.vel.z = 0;
  }

  update(acc_body, gyro_body, dt) {
    // Attitude: raw gyro integration (bias accumulates unbounded)
    this.yaw = wrapAngle(this.yaw + gyro_body.z * dt);

    // Body -> World rotation
    const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
    const awx = c * acc_body.x - s * acc_body.y;
    const awy = s * acc_body.x + c * acc_body.y;

    // Double integration (m/s -> px)
    this.vel.x += awx * dt;
    this.vel.y += awy * dt;
    this.pos.x += this.vel.x * PX_PER_METER * dt;
    this.pos.y += this.vel.y * PX_PER_METER * dt;
  }

  resync(posPx, v0_ms, yaw) {
    this.init(posPx, v0_ms, yaw);
    this.justResynced = true;   // consumed by renderer for flash animation
  }
}

/* ----------------------------------------------------------------------------
 * 2. IDR Navigator — 5-Stage Cascade Estimator
 * --------------------------------------------------------------------------*/
class IDRNavigatorEstimator {
  constructor() {
    this.pos = new Vec3(0, 0, 0);       // pixels
    this.vel = new Vec3(0, 0, 0);       // m/s
    this.yaw = 0;                       // rad
    this.P_cov = 0.035;                 // m^2
    this.v_tcn = 0;                     // m/s (neural speed prior, filtered)
    this.lastInnovation = new Vec3(0, 0, 0); // px (GNSS - estimate)

    // Stage 1 state
    this.b_est = 0;                     // gyro z-bias estimate (rad/s)

    // Stage 2 state (sliding variance window)
    this.WIN = 32;
    this.accWin = new Float32Array(this.WIN);
    this.winIdx = 0;
    this.winFill = 0;
    this.shockRejected = false;

    // Tunables
    this.K = {
      BIAS_ZUPT: 0.02,        // bias learning gain during ZUPT
      BIAS_DECAY: 0.9995,     // bias damping when not observable
      VAR_GATE: 1.2 * G0 * G0,// spectral gate threshold (m/s^2)^2
      TCN_ALPHA: 0.25,        // TCN prior low-pass
      SNAP_GAIN: 0.05,        // soft map-snapping gain
      YAW_SNAP_GAIN: 0.02,    // heading alignment to circuit tangent
      GNSS_GAIN: 0.15,        // position correction gain when GNSS live
      P_GNSS: 0.035,
      P_MAX: 0.085,
      P_RATE: 0.002,          // m^2/s growth during outage
      P_ZUPT: 0.001,
    };
  }

  init(posPx, v0_ms, yaw) {
    this.yaw = wrapAngle(yaw);
    this.pos.x = posPx.x; this.pos.y = posPx.y; this.pos.z = 0;
    this.v_tcn = Math.max(0, v0_ms);
    this.vel.x = Math.cos(this.yaw) * this.v_tcn;
    this.vel.y = Math.sin(this.yaw) * this.v_tcn;
    this.vel.z = 0;
    this.P_cov = this.K.P_GNSS;
    this.b_est = 0;
    this.accWin.fill(0); this.winIdx = 0; this.winFill = 0;
    this.lastInnovation.x = this.lastInnovation.y = this.lastInnovation.z = 0;
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

  update(acc_body, gyro_body, v_neural, isShock, isOutage, gnssPosPx, isZupt, circuit, dt) {
    const