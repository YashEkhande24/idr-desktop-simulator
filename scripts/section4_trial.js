```javascript
/**
 * Section 4: Outage Trial Lifecycle, Scorecard & Resynchronization Controller
 * ISRO SIH Dead-Reckoning Simulator (100 Hz sim, 960x480 canvas)
 */
class OutageTrialManager {
  constructor({
    pxPerMeter = 1.5,
    maxDuration = 30.0,      // s
    scorecardDuration = 5000, // ms (UI wall-clock)
    flashDuration = 700,      // ms
    classicSolver = null,     // default refs used on auto-complete
    truth = null,
    onComplete = null,        // optional (scorecard) => void, e.g. DOM toast
  } = {}) {
    this.pxPerMeter = pxPerMeter;
    this.maxDuration = maxDuration;
    this.scorecardDuration = scorecardDuration;
    this.flashDuration = flashDuration;
    this.classicSolver = classicSolver;
    this.truth = truth;
    this.onComplete = onComplete;

    this.trialActive = false;
    this.reason = null;
    this.lastScorecard = null;
    this._scorecardAt = -Infinity;
    this._flash = null; // { x, y, t0 }
    this._endReason = null;
    this._resetMetrics();
  }

  /* ------------------------------------------------------------ lifecycle */

  startTrial(reason = 'manual') {
    if (this.trialActive) return false;
    this._resetMetrics();
    this.reason = reason;
    this.trialActive = true;
    this._endReason = null;
    return true;
  }

  /**
   * @param {number} dt        seconds (0.01 @ 100 Hz)
   * @param {number} speedMs   truth speed, m/s
   * @param {{x,y}} truthPos   canvas px
   * @param {{x,y}} classicPos canvas px
   * @param {{x,y}} idrPos     canvas px
   * @param {boolean} egress   true when tunnel exit is reached
   */
  update(dt, speedMs, truthPos, classicPos, idrPos, egress = false) {
    if (!this.trialActive) return null;

    this.elapsed += dt;
    this.distance += Math.max(0, speedMs) * dt;

    this.classicErr = Math.hypot(classicPos.x - truthPos.x, classicPos.y - truthPos.y) / this.pxPerMe