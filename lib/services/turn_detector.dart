import 'dart:math' as math;
import '../core/math_utils.dart';
import 'map_snapper.dart';

/// Vehicle turning state detected from IMU gyroscope yaw rate.
enum TurnState {
  straight,
  turningLeft,
  turningRight,
}

/// Module 5 Extension: Turn Detector & Intersection Branch Disambiguator
///
/// Uses gyroscope yaw rate to detect vehicle maneuvers through road intersections during GNSS outages.
/// When approaching branching intersections (forks, T-junctions, roundabouts), selects the candidate
/// road segment whose angular geometry best matches the vehicle's angular turn profile.
class TurnDetector {
  // Gyroscope yaw rate threshold for active turn: 0.22 rad/s (~12.6 deg/s)
  static const double yawRateThreshold = 0.22;
  // Minimum sustained turn duration to qualify as intentional vehicle maneuver
  static const int minTurnConsecutiveSamples = 5;

  TurnState _state = TurnState.straight;
  int _consecutiveTurnSamples = 0;
  double _accumulatedTurnAngleRad = 0.0;
  double _lastYawRate = 0.0;
  double _roadCurvature = 0.0; // Instantaneous road curvature kappa = omega / v (1/m)
  double _centripetalAccel = 0.0; // a_cf = v * omega (m/s^2)

  TurnState get state => _state;
  bool get isTurning => _state != TurnState.straight;
  double get accumulatedTurnAngleDeg => MathUtils.radToDeg(_accumulatedTurnAngleRad);
  double get lastYawRate => _lastYawRate;
  double get roadCurvature => _roadCurvature;
  double get centripetalAccel => _centripetalAccel;

  /// Ingest instantaneous vehicle yaw angular rate (rad/s) and time step (seconds).
  /// [vTcn]: Optional vehicle forward speed from TCN Speed Engine.
  TurnState processYawRate(double omegaYawRadPerSec, double dt, {double? vTcn}) {
    _lastYawRate = omegaYawRadPerSec;

    // TCN-Augmented Kinematic Curvature & Centripetal Acceleration:
    if (vTcn != null && vTcn > 0.5) {
      _roadCurvature = omegaYawRadPerSec / vTcn;
      _centripetalAccel = vTcn * omegaYawRadPerSec;
    } else {
      _roadCurvature = omegaYawRadPerSec;
      _centripetalAccel = 0.0;
    }

    if (omegaYawRadPerSec.abs() >= yawRateThreshold) {
      _consecutiveTurnSamples++;
      _accumulatedTurnAngleRad += omegaYawRadPerSec * dt;

      if (_consecutiveTurnSamples >= minTurnConsecutiveSamples) {
        _state = omegaYawRadPerSec > 0
            ? TurnState.turningLeft
            : TurnState.turningRight;
      }
    } else {
      if (_consecutiveTurnSamples > 0) {
        _consecutiveTurnSamples--;
      }
      if (_consecutiveTurnSamples == 0) {
        _state = TurnState.straight;
        _accumulatedTurnAngleRad = 0.0;
      }
    }

    return _state;
  }

  /// Disambiguates candidate road branches at an intersection.
  /// Selects candidate whose road heading and geometric curvature best match vehicle kinematics.
  MapBranch? selectBestBranch({
    required List<MapBranch> candidateBranches,
    required Vec3 vehiclePos,
    required double vehicleHeadingRad,
    double? vTcn,
  }) {
    if (candidateBranches.isEmpty) return null;
    if (candidateBranches.length == 1) return candidateBranches.first;

    MapBranch? bestBranch;
    double bestScore = -double.infinity;

    for (final branch in candidateBranches) {
      if (branch.points.length < 2) continue;

      // Find closest segment in branch to evaluate road azimuth
      double minSegDist = double.infinity;
      double segHeadingRad = 0.0;

      for (int i = 0; i < branch.points.length - 1; i++) {
        final a = branch.points[i];
        final b = branch.points[i + 1];
        final mid = Vec3(
          (a.x + b.x) * 0.5,
          (a.y + b.y) * 0.5,
          (a.z + b.z) * 0.5,
        );
        final dist = (vehiclePos - mid).norm;
        if (dist < minSegDist) {
          minSegDist = dist;
          segHeadingRad = math.atan2(b.y - a.y, b.x - a.x);
        }
      }

      // Heading agreement score: cos(delta_psi)
      final headingDiff = MathUtils.normalizeAngle(segHeadingRad - vehicleHeadingRad);
      final headingAgreement = math.cos(headingDiff);

      // Distance penalty (normalized by 50m search radius)
      final distPenalty = math.max(0.0, 1.0 - minSegDist / 50.0);

      // Total branch score
      final score = 0.65 * headingAgreement + 0.35 * distPenalty;

      if (score > bestScore) {
        bestScore = score;
        bestBranch = branch;
      }
    }

    return bestBranch;
  }

  void reset() {
    _state = TurnState.straight;
    _consecutiveTurnSamples = 0;
    _accumulatedTurnAngleRad = 0.0;
    _lastYawRate = 0.0;
    _roadCurvature = 0.0;
    _centripetalAccel = 0.0;
  }
}
