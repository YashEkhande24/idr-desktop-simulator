import 'dart:math' as math;
import '../core/constants.dart';
import '../core/math_utils.dart';

/// Road surface classification based on IMU jerk dynamics.
enum RoadSurfaceCondition {
  smooth,
  rough,
  shock,
  pedestrian,
}

/// Module 2: Kinetic Vibration Gate
///
/// Potholes, speed bumps, and rough road surfaces inject high-frequency specific force
/// that classical double-integration mistakes for vehicle acceleration.
///
/// Improvements:
/// 1. Adaptive Road Roughness Baseline: Tracks running background noise floor
///    so bumpy Indian roads / cobblestone do NOT cause permanent shock lockouts.
/// 2. Vertical Decoupling: Specifically isolates high-magnitude vertical impulse ($j_z$)
///    from planar throttle/braking dynamics ($j_{xy}$).
/// 3. Bounded Rebound Hold: Shocks auto-clear after ~350ms (suspension rebound time).
/// 4. Pedestrian Gate Suppression: Walking cadence cancels vehicle pothole alerts.
class VibrationGate {
  Vec3? _prevAccel;
  Vec3? _filteredAccel;
  final List<double> _jerkHistory = [];
  bool _shockDetected = false;
  bool _isRoughRoad = false;
  int _holdTicksRemaining = 0;
  double _shockThreshold = IdrConstants.jerkVarianceThreshold;
  double _roadRoughnessBaseline = 5.0; // Running noise floor
  double _lastRawJerk = 0.0;
  double _lastVariance = 0.0;
  double _trustWeight = 1.0; // w_v in [0, 1] (Eqn 14)
  RoadSurfaceCondition _roadCondition = RoadSurfaceCondition.smooth;

  static const double _lambda = 0.001; // Continuous jerk sensitivity parameter
  static const int _historyWindow = 10; // 10 samples (Eqn 14 in whitepaper)

  bool get isShockDetected => _shockDetected;
  bool get isRoughRoad => _isRoughRoad;
  RoadSurfaceCondition get roadCondition => _roadCondition;
  String get roadConditionString {
    switch (_roadCondition) {
      case RoadSurfaceCondition.pedestrian:
        return 'PEDESTRIAN';
      case RoadSurfaceCondition.shock:
        return 'SHOCK TRIP';
      case RoadSurfaceCondition.rough:
        return 'ROUGH ROAD';
      case RoadSurfaceCondition.smooth:
        return 'NORMAL';
    }
  }

  double get shockThreshold => _shockThreshold;
  set shockThreshold(double value) {
    _shockThreshold = MathUtils.clamp(value, 20.0, 2500.0);
  }

  double get lastRawJerk => _lastRawJerk;
  double get lastVariance => _lastVariance;
  double get trustWeight => _trustWeight;
  double get wv => _trustWeight;
  double get roadRoughnessBaseline => _roadRoughnessBaseline;

  double _lastTcnVariance = 0.16;

  double get lastTcnVariance => _lastTcnVariance;

  /// Process an aligned vehicle acceleration sample and evaluate vibration gate.
  /// [tcnVariance]: Optional instantaneous uncertainty variance from TcnSpeedEngine.
  void process(
    Vec3 vehicleAccel,
    double dt, {
    bool isStationary = false,
    bool isPedestrian = false,
    double? tcnVariance,
  }) {
    if (tcnVariance != null) {
      _lastTcnVariance = tcnVariance;
    }

    if (isStationary) {
      _shockDetected = false;
      _isRoughRoad = false;
      _holdTicksRemaining = 0;
      _lastRawJerk = 0.0;
      _lastVariance = 0.0;
      _trustWeight = 1.0;
      _roadCondition = RoadSurfaceCondition.smooth;
      _prevAccel = vehicleAccel;
      _filteredAccel = vehicleAccel;
      return;
    }

    if (isPedestrian) {
      _shockDetected = false;
      _isRoughRoad = false;
      _holdTicksRemaining = 0;
      _trustWeight = 0.9;
      _roadCondition = RoadSurfaceCondition.pedestrian;
      _prevAccel = vehicleAccel;
      _filteredAccel = vehicleAccel;
      return;
    }

    final effectiveDt = MathUtils.clamp(dt, 0.001, 0.10);

    // Low-pass filter to reject high-frequency capacitive MEMS noise (> 50 Hz)
    // while preserving genuine structural vehicle shocks (5-20 Hz)
    if (_filteredAccel == null) {
      _filteredAccel = vehicleAccel;
    } else {
      _filteredAccel = _filteredAccel! * 0.75 + vehicleAccel * 0.25;
    }

    if (_prevAccel == null) {
      _prevAccel = _filteredAccel;
      return;
    }

    // Discrete jerk vector: j(t) = (a_t - a_{t-1}) / dt
    final jerkVec = (_filteredAccel! - _prevAccel!) / effectiveDt;
    _prevAccel = _filteredAccel;

    // Weight vertical shock 1.6x (potholes primarily excite the vertical chassis axis)
    final weightedJerk = Vec3(jerkVec.x, jerkVec.y, jerkVec.z * 1.6);
    _lastRawJerk = math.min(300.0, weightedJerk.norm);
    _jerkHistory.add(_lastRawJerk);

    if (_jerkHistory.length > _historyWindow) {
      _jerkHistory.removeAt(0);
    }

    // Compute sliding variance of jerk sigma_jerk^2
    if (_jerkHistory.length >= 3) {
      var sum = 0.0;
      for (final j in _jerkHistory) {
        sum += j;
      }
      final mean = sum / _jerkHistory.length;

      var varSum = 0.0;
      for (final j in _jerkHistory) {
        final d = j - mean;
        varSum += d * d;
      }
      _lastVariance = MathUtils.clamp(varSum / _jerkHistory.length, 0.0, 2500.0);
    } else {
      _lastVariance = 0.0;
    }

    // 1. Continuous Huber M-estimator weighting on jerk intensity:
    final baselineSigma = math.max(2.0, math.sqrt(_roadRoughnessBaseline));
    final normalizedJerk = math.sqrt(_lastVariance) / baselineSigma;
    final huberW = MathUtils.huberWeight(normalizedJerk, k: 3.0);

    // 2. Multi-domain TCN uncertainty fusion:
    // Scale trust weight when TCN predictive variance exceeds nominal baseline (0.16)
    final excessTcnVar = math.max(0.0, _lastTcnVariance - 0.16);
    final aiConfidence = 1.0 / (1.0 + 0.45 * excessTcnVar);

    // Combined smooth trust weight (Eqn 14 augmented with Huber + AI)
    final continuousW = math.exp(-_lambda * _lastVariance);
    _trustWeight = MathUtils.clamp(continuousW * huberW * aiConfidence, 0.04, 1.0);

    // Evaluate road conditions with hysteresis:
    final maxHoldTicks = math.max(1, (IdrConstants.jerkReboundDurationSec / effectiveDt).round());

    // Adaptive outlier detection: shock triggers if variance exceeds shockThreshold
    // OR exceeds the dynamic road roughness baseline by an adaptive factor (5.0x baseline):
    final dynamicShockThreshold = math.min(_shockThreshold, math.max(_shockThreshold * 0.75, _roadRoughnessBaseline * 5.0));

    // Pothole enter threshold (statistical outlier detection)
    if (_lastVariance >= dynamicShockThreshold) {
      _shockDetected = true;
      _holdTicksRemaining = maxHoldTicks;
      _roadCondition = RoadSurfaceCondition.shock;
    } else if (_shockDetected) {
      // While in shock, count down hold timer and require variance to drop below exit threshold (45%)
      if (_holdTicksRemaining > 0) {
        _holdTicksRemaining--;
      }
      if (_holdTicksRemaining <= 0 && _lastVariance < (dynamicShockThreshold * 0.45)) {
        _shockDetected = false;
      }
    }

    if (!_shockDetected) {
      // Adaptive road roughness baseline update (smooth road vs rough road)
      _roadRoughnessBaseline = _roadRoughnessBaseline * 0.95 + _lastVariance * 0.05;

      if (_lastVariance >= IdrConstants.roughRoadVarianceThreshold ||
          _roadRoughnessBaseline >= IdrConstants.roughRoadVarianceThreshold) {
        _isRoughRoad = true;
        _roadCondition = RoadSurfaceCondition.rough;
      } else {
        _isRoughRoad = false;
        _roadCondition = RoadSurfaceCondition.smooth;
      }
    } else {
      _roadCondition = RoadSurfaceCondition.shock;
    }
  }

  /// Get dynamic inflation multiplier for EKF process noise covariance Q.
  double getCovarianceInflation() {
    if (_shockDetected) {
      return IdrConstants.jerkGateInflationFactor;
    }
    if (_trustWeight >= 0.999) {
      return 1.0;
    }
    final continuousInflation = 1.0 / math.max(0.004, _trustWeight);
    return MathUtils.clamp(continuousInflation, 1.0, IdrConstants.jerkGateInflationFactor);
  }

  void reset() {
    _prevAccel = null;
    _filteredAccel = null;
    _jerkHistory.clear();
    _shockDetected = false;
    _isRoughRoad = false;
    _holdTicksRemaining = 0;
    _roadRoughnessBaseline = 5.0;
    _shockThreshold = IdrConstants.jerkVarianceThreshold;
    _lastRawJerk = 0.0;
    _lastVariance = 0.0;
    _trustWeight = 1.0;
    _roadCondition = RoadSurfaceCondition.smooth;
  }
}
