```javascript
/**
 * Section 2: IMU Kinematics & Bosch BMI270 Sensor Noise / Bias Drift Model
 * Body frame: x = forward, y = left, z = up (right-handed, ENU-style).
 * Accelerometer outputs specific force, so a level, stationary IMU reads +g on z.
 */

const G0 = 9.80665;          // standard gravity, m/s^2
const PX_PER_METER = 1.5;    // track scale: 2400 px = 1600 m

const BMI270_DEFAULTS = Object.freeze({
  accNoiseSigma: 0.025,      // m/s^2, white noise per sample
  gyroNoiseSigma: 0.0015,    // rad/s, white noise per sample

  accBias:  { x: 0.04, y: 0.12, z: 0.02 },   // m/s^2, calibrated static bias
  gyroBias: { x: 0.0,  y: 0.0,  z: 0.016 },  // rad/s (~0.9 deg/s on z)

  // First-order Gauss-Markov bias instability (steady-state sigma, correlation time)
  accBiasWalkSigma: 0.005,   // m/s^2
  accBiasTau: 300,           // s
  gyroBiasWalkSigma: 0.0005, // rad/s
  gyroBiasTau: 200,          // s

  shockVerticalMs2: 4.5 * G0,  // ~44.1 m/s^2
  shockLateralMs2: 1.2 * G0,   // ~11.8 m/s^2
});

const vec3 = (x = 0, y = 0, z = 0) => ({ x, y, z });

class BMI270Model {
  /**
   * @param {object} [config]  overrides for BMI270_DEFAULTS
   * @param {() => number} [rng]  uniform [0,1) source (inject a seeded PRNG for repeatable runs)
   */
  constructor(config = {}, rng = Math.random) {
    this.cfg = { ...BMI270_DEFAULTS, ...config };
    this.rng = rng;
    this._spare = null; // cached second Box-Muller sample
    this.reset();
  }

  reset() {
    this.accBiasDrift = vec3();   // Gauss-Markov state (deviation from nominal bias)
    this.gyroBiasDrift = vec3();
    this._spare = null;
  }

  /** Standard Box-Muller transform: zero-mean, unit-variance Gaussian. */
  gaussian() {
    if (this._spare !== null) {
      const s = this._spare;
      this._spare = null;
      return s;
    }
    let u1 = 0;
    while (u1 <= Number.EPSILON) u1 = this.rng(); // avoid log(0)
    const u2 = this.rng();
    const r = Math.sqrt(-2 * Math.log(u1));
    const theta = 2 * Math.PI * u2;
    this._spare = r * Math.sin(theta);
    return r * Math.cos(theta);
  }

  /** Exact discrete first-order Gauss-Markov step, applied per axis. */
  _stepGaussMarkov(state, sigma, tau, dt) {
    const phi = Math.exp(-dt / tau);
    const q = sigma * Math.sqrt(1 - phi * phi);
    state.x = phi * state.x + q * this.gaussian();
    state.y = phi * state.y + q * this.gaussian();
    state.z = phi * state.z + q * this.gaussian();
  }

  /**
   * @param {{curvature:number}} truth  spline sample (curvature in 1/px, signed; + = left turn)
   * @param {number} speedMs            vehicle speed, m/s
   * @param {number} accelForwardMs2    longitudinal acceleration, m/s^2
   * @param {boolean} shockActive       inject pothole/impact impulse this sample
   * @param {number} dt                 sample period, s (0.01 at 100 Hz)
   */
  generate(truth, speedMs, accelForwardMs2 = 0, shockActive = false, dt = 0.01) {
    const c = this.cfg;
    const step = dt > 0 ? dt : 0.01;

    // 1. True kinematics
    const kappa_m = (truth?.curvature ?? 0) * PX_PER_METER; // 1/px -> 1/m
    const omega_z = speedMs * kappa_m;                       // rad/s
    const a_y = speedMs * omega_z;                           // = v^2 * kappa, m/s^2
    const a_x = accelForwardMs2;

    const trueAcc = vec3(a_x, a_y, G0);
    const trueGyro = vec3(0, 0, omega_z);

    // 4. Shock impulse (vertical jolt + lateral kick)
    if (shockActive) {
      trueAcc.z += c.shockVerticalMs2;
      trueAcc.y += c.shockLateralMs2 * (this.rng() < 0.5 ? -1 : 1);
    }

    // 3. Bias drift (Gauss-Markov random walk around calibrated nominal)
    this._stepGaussMarkov(this.accBiasDrift, c.accBiasWalkSigma, c.accBiasTau, step);
    this._stepGaussMarkov(this.gyroBiasDrift, c.gyroBiasWalkSigma, c.gyroBiasTau, step);

    // 2 + 3. Measurement = truth + nominal bias + drifting bias + white noise
    const acc_body = vec3(
      trueAcc.x + c.accBias.x + this.accBiasDrift.x + c.accNoiseSigma * this.gaussian(),
      trueAcc.y + c.accBias.y + this.accBiasDrift.y + c.accNoiseSigma * this.gaussian(),
      trueAcc.z + c.accBias.z + this.accBiasDrift.z + c.accNoiseSigma * this.gaussian(),
    );

    const gyro_body = vec3(
      trueGyro.x + c.gyroBias.x + this.gyroBiasDrift.x + c.gyroNoiseSigma * this.gaussian(),
      trueGyro.y + c.gyroBias.y + this.gyroBiasDrift.y + c.gyroNoiseSigma * this.gaussian(),
      trueGyro.z + c.gyroBias.z + this.gyroBiasDrift.z + c.gyroNoiseSigma * this.gaussian(),
    );

    return {
      acc_body,
      gyro_body,
      truthKinematics: { omega_z, a_y, a_x, kappa_m },
    };
  }
}

// Shared stateful instance so bias drift persists across 100 Hz calls.
const defaultIMU = new BMI270Model();

function generateIMU(truth, speedMs, accelForwardMs2, shockActive, dt) {
  return defaultIMU.generate(truth, speedMs, accelForwardMs2, shockActive, dt);
}

export { BMI270Model, BMI270_DEFAULTS, generateIMU, defaultIMU, G0, PX_PER_