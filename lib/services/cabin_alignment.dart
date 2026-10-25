import 'dart:math' as math;
import '../core/constants.dart';
import '../core/math_utils.dart';

/// Module 1: Dynamic In-Cabin Alignment
///
/// When a smartphone is mounted at an arbitrary orientation R_bv inside a vehicle,
/// the IMU measurements must be rotated into the vehicle body frame:
/// [x_fwd, y_lat, z_up].
///
/// 1. Gravity Tracking (Tilt Compensation):
///    Estimates mount roll (phi_0) and pitch (theta_0) such that g aligns with [0, 0, -1]^T.
///    Tilt is ONLY updated while stationary to prevent cornering/braking acceleration from corrupting tilt.
/// 2. Horizontal Forward Alignment (PCA):
///    In leveled frame, tracks vehicle acceleration along horizontal plane to determine forward heading.
///    Continuous execution while driving until yaw is resolved.
/// 3. Vehicle Frame Transform:
///    a_v = R_bv * a_m - [0, 0, g]^T
class CabinAligner {
  final List<Vec3> _accelWindow = [];
  final List<Vec3> _gyroWindow = [];
  final List<double> _speedWindow = [];
  final List<Vec3> _horizontalAccels = [];

  Vec3? _lowPassGravity;
  Mat3 _rBv = Mat3.identity; // Rotation from phone to vehicle body frame
  Quaternion _qBv = Quaternion.identity;
  Vec3 _gyroBias = Vec3.zero; // Online estimated gyroscope bias in rad/s

  double _mountRoll = 0.0;
  double _mountPitch = 0.0;
  double _mountYaw = 0.0;
  double _confidence = 0.0;
  bool _tiltLocked = false;
  bool _yawResolved = false;

  CabinAligner();

  Mat3 get rotationMatrix => _rBv;
  Quaternion get attitudeQuaternion => _qBv;
  Vec3 get gyroBias => _gyroBias;
  double get mountRollDeg => MathUtils.radToDeg(_mountRoll);
  double get mountPitchDeg => MathUtils.radToDeg(_mountPitch);
  double get mountYawDeg => MathUtils.radToDeg(_mountYaw);
  double get mountYaw => _mountYaw;
  double get confidence => _confidence;
  bool get isTiltLocked => _tiltLocked;
  bool get isYawResolved => _yawResolved;
  bool get isLocked => _tiltLocked && _yawResolved;

  /// Ingest an IMU sample and update alignment filter.
  /// [vTcn]: Optional forward speed from TCN Speed Engine.
  /// [tcnVariance]: Optional predictive variance from TCN Speed Engine.
  /// [vGnss]: Optional live speed from GNSS Doppler receiver.
  /// [dt]: sample period in seconds.
  void ingest(
    Vec3 rawAccel,
    Vec3 rawGyro, {
    double? vTcn,
    double? tcnVariance,
    double? vGnss,
    double dt = IdrConstants.dtImu,
  }) {
    final wNorm = rawGyro.norm;
    final aNorm = rawAccel.norm;
    final speed = vGnss ?? vTcn ?? 0.0;

    _accelWindow.add(rawAccel);
    _gyroWindow.add(rawGyro);
    _speedWindow.add(speed);

    if (_accelWindow.length > IdrConstants.alignmentSampleCount) {
      _accelWindow.removeAt(0);
      _gyroWindow.removeAt(0);
      _speedWindow.removeAt(0);
    }

    // 1. Tilt Adaptation: ONLY while stationary or quiet startup convergence
    // Under cornering (e.g. 3 m/s^2 lateral) or throttle/braking, raw acceleration
    // deviates significantly from true gravity. We only adapt gravity when the phone
    // is stationary: wNorm < 0.05 rad/s and acceleration is close to 1g.
    final bool isStationaryQuiet = (speed < 0.5) && (wNorm < 0.05) && ((aNorm - IdrConstants.gravity).abs() < 0.40);
    final bool allowAdapt = isStationaryQuiet || (!_tiltLocked && aNorm > 7.5 && aNorm < 12.0);

    if (_lowPassGravity == null) {
      _lowPassGravity = rawAccel;
    } else if (allowAdapt) {
      final double alpha = !_tiltLocked ? 0.08 : 0.02;
      _lowPassGravity = _lowPassGravity! * (1.0 - alpha) + rawAccel * alpha;
    }

    // Update gyro bias when stationary
    if (isStationaryQuiet) {
      _gyroBias = _gyroBias * 0.98 + rawGyro * 0.02;
    }

    _updateAlignment(
      vTcn: vTcn,
      tcnVariance: tcnVariance,
      vGnss: vGnss,
    );
  }

  /// Force instantaneous calibration using current accumulated window.
  void forceCalibrate() {
    if (_accelWindow.isEmpty) return;
    _updateAlignment(forceLock: true);
  }

  void reset() {
    _accelWindow.clear();
    _gyroWindow.clear();
    _speedWindow.clear();
    _horizontalAccels.clear();
    _lowPassGravity = null;
    _rBv = Mat3.identity;
    _qBv = Quaternion.identity;
    _gyroBias = Vec3.zero;
    _mountRoll = 0.0;
    _mountPitch = 0.0;
    _mountYaw = 0.0;
    _confidence = 0.0;
    _tiltLocked = false;
    _yawResolved = false;
  }

  Vec3? get lowPassGravity => _lowPassGravity;

  void _updateAlignment({
    bool forceLock = false,
    double? vTcn,
    double? tcnVariance,
    double? vGnss,
  }) {
    if (_lowPassGravity == null) return;

    final gNorm = _lowPassGravity!.norm;
    if (gNorm < 7.0 || gNorm > 12.5) return;

    final gHat = _lowPassGravity!.normalized;

    // Check consistency with earth gravity 9.80665 m/s^2
    final gravityResidual = (gNorm - IdrConstants.gravity).abs();
    final gravityScore = math.max(0.0, 1.0 - (gravityResidual / 3.0));

    // Dynamic variance stability
    var varSum = 0.0;
    if (_accelWindow.isNotEmpty) {
      for (final a in _accelWindow) {
        final diff = a - _lowPassGravity!;
        varSum += diff.normSquared;
      }
    }
    final accelVariance = _accelWindow.isNotEmpty ? (varSum / _accelWindow.length) : 0.0;
    final stabilityScore = math.max(0.0, 1.0 - (accelVariance / 2.0));
    _confidence = MathUtils.clamp(gravityScore * 0.6 + stabilityScore * 0.4, 0.0, 1.0);

    // Compute mount pitch and roll from gravity vector
    if (!_tiltLocked || forceLock) {
      _mountPitch = math.atan2(-gHat.x, math.sqrt(gHat.y * gHat.y + gHat.z * gHat.z));
      _mountRoll = math.atan2(gHat.y, gHat.z);
      _updateMatrices();
    }

    if ((!_tiltLocked || forceLock) && (_confidence >= 0.70 || forceLock) && _accelWindow.length >= 20) {
      _tiltLocked = true;
    }

    // PCA Forward Axis Alignment:
    // Continue attempting PCA while driving until yaw is resolved.
    final effectiveSpeed = vGnss ?? vTcn;
    final bool isDriving = (effectiveSpeed != null && effectiveSpeed > 1.2) ||
        (vGnss == null && vTcn == null && _accelWindow.length >= 20);

    if (!_yawResolved || forceLock) {
      if (forceLock) {
        _yawResolved = true;
        _updateMatrices();
      } else if (_tiltLocked && isDriving) {
        _attemptPcaAlignment(effectiveSpeed);
      }
    }
  }

  void _attemptPcaAlignment(double? effectiveSpeed) {
    if (_accelWindow.isEmpty) return;

    final rTilt = Mat3.fromEuler(_mountRoll, _mountPitch, 0.0);
    final rawA = _accelWindow.last;
    final rawW = _gyroWindow.last;

    // Turn rejection: centripetal acceleration corrupts longitudinal PCA
    final wZ = rTilt.transform(rawW).z;
    if (wZ.abs() > 0.08) return; // ~4.6 deg/s turn rejection

    final aLvl = rTilt.transform(rawA);
    _horizontalAccels.add(aLvl);
    if (_horizontalAccels.length > 200) {
      _horizontalAccels.removeAt(0);
    }

    if (_horizontalAccels.length < 20) return;

    // Compute sample covariance of horizontal acceleration
    var sumX = 0.0;
    var sumY = 0.0;
    for (final s in _horizontalAccels) {
      sumX += s.x;
      sumY += s.y;
    }
    final meanX = sumX / _horizontalAccels.length;
    final meanY = sumY / _horizontalAccels.length;

    var covXX = 0.0;
    var covXY = 0.0;
    var covYY = 0.0;
    for (final s in _horizontalAccels) {
      final dx = s.x - meanX;
      final dy = s.y - meanY;
      covXX += dx * dx;
      covXY += dx * dy;
      covYY += dy * dy;
    }
    final n = _horizontalAccels.length - 1;
    covXX /= n;
    covXY /= n;
    covYY /= n;

    // 2x2 eigenvalue decomposition for dominant longitudinal direction
    final trace = covXX + covYY;
    final diff = covXX - covYY;
    final disc = math.sqrt(diff * diff + 4.0 * covXY * covXY);
    final lambda1 = 0.5 * (trace + disc);
    final lambda2 = 0.5 * (trace - disc);

    // Require longitudinal dynamic energy AND anisotropy
    if (lambda1 > 0.05 && lambda1 > 2.5 * math.max(lambda2, 1e-4)) {
      final thetaPca = MathUtils.pcaOrientationAngle(covXX, covXY, covYY);
      var uX = math.cos(thetaPca);
      var uY = math.sin(thetaPca);

      // Resolve 180-deg ambiguity using speed-acceleration correlation
      double dotCorrelation = 0.0;
      if (_speedWindow.length >= 3 && _speedWindow.length == _accelWindow.length) {
        for (int i = 1; i < _accelWindow.length - 1; i++) {
          final aProj = rTilt.transform(_accelWindow[i]).x * uX + rTilt.transform(_accelWindow[i]).y * uY;
          final dv = _speedWindow[i + 1] - _speedWindow[i - 1];
          dotCorrelation += aProj * dv;
        }
      }

      if (dotCorrelation < -0.05) {
        uX = -uX;
        uY = -uY;
      }

      _mountYaw = -math.atan2(uY, uX);
      _yawResolved = true;
      _updateMatrices();
    }
  }

  void _updateMatrices() {
    final cp = math.cos(_mountPitch);
    final sp = math.sin(_mountPitch);
    final cr = math.cos(_mountRoll);
    final sr = math.sin(_mountRoll);

    final rRoll = Mat3([
      1.0, 0.0, 0.0,
      0.0, cr,  -sr,
      0.0, sr,   cr,
    ]);

    final rPitch = Mat3([
      cp,  0.0, sp,
      0.0, 1.0, 0.0,
      -sp, 0.0, cp,
    ]);

    if (_mountYaw.abs() > 1e-4) {
      final cy = math.cos(_mountYaw);
      final sy = math.sin(_mountYaw);
      final rYaw = Mat3([
        cy, -sy, 0.0,
        sy,  cy, 0.0,
        0.0, 0.0, 1.0,
      ]);
      _rBv = rYaw * (rPitch * rRoll);
    } else {
      _rBv = rPitch * rRoll;
    }
    _qBv = Quaternion.fromEuler(_mountRoll, _mountPitch, _mountYaw);
  }

  /// Transforms raw sensor acceleration into leveled vehicle frame WITHOUT gravity subtraction:
  /// returns pure specific force [f_fwd, f_lat, f_vert] in the vehicle frame.
  Vec3 transformSpecificForce(Vec3 rawAccel) {
    return _rBv.transform(rawAccel);
  }

  /// Transforms raw sensor acceleration into vehicle frame:
  /// [a_fwd, a_lat, a_vert] with gravity subtracted.
  Vec3 transformAccel(Vec3 rawAccel) {
    final aLeveled = _rBv.transform(rawAccel);
    return Vec3(aLeveled.x, aLeveled.y, aLeveled.z - IdrConstants.gravity);
  }

  /// Transforms raw sensor angular rates into vehicle frame:
  /// [w_roll, w_pitch, w_yaw].
  Vec3 transformGyro(Vec3 rawGyro) {
    return _rBv.transform(rawGyro);
  }
}
