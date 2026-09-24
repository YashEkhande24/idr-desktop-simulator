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
///    g_hat = mean(a) / ||mean(a)||
///    Estimates mount roll (phi_0) and pitch (theta_0) such that g aligns with [0, 0, -1]^T.
/// 2. Horizontal Forward Alignment:
///    Tracks vehicle acceleration along horizontal plane to determine forward heading.
/// 3. Vehicle Frame Transform:
///    a_v = R_bv * (a_m - b_a) - [0, 0, g]^T
class CabinAligner {
  final List<Vec3> _accelWindow = [];
  final List<Vec3> _gyroWindow = [];
  final List<double> _speedWindow = [];

  Vec3? _lowPassGravity;
  Mat3 _rBv = Mat3.identity; // Rotation from phone to vehicle body frame
  Quaternion _qBv = Quaternion.identity;
  Vec3 _gyroBias = Vec3.zero; // Online estimated gyroscope bias in rad/s

  double _mountRoll = 0.0;
  double _mountPitch = 0.0;
  double _mountYaw = 0.0;
  double _confidence = 0.0;
  bool _locked = false;

  // Mahony filter gains
  static const double _kp = 0.50; // Proportional gain for gravity orientation tracking
  static const double _ki = 0.015; // Integral gain for gyroscope bias tracking

  CabinAligner();

  Mat3 get rotationMatrix => _rBv;
  Quaternion get attitudeQuaternion => _qBv;
  Vec3 get gyroBias => _gyroBias;
  double get mountRollDeg => MathUtils.radToDeg(_mountRoll);
  double get mountPitchDeg => MathUtils.radToDeg(_mountPitch);
  double get mountYawDeg => MathUtils.radToDeg(_mountYaw);
  double get confidence => _confidence;
  bool get isLocked => _locked;

  /// Ingest an IMU sample and update alignment filter.
  /// [vTcn]: Optional forward speed from TCN Speed Engine.
  /// [tcnVariance]: Optional predictive variance from TCN Speed Engine.
  /// [dt]: sample period in seconds.
  void ingest(
    Vec3 rawAccel,
    Vec3 rawGyro, {
    double? vTcn,
    double? tcnVariance,
    double dt = IdrConstants.dtImu,
  }) {
    final effectiveDt = MathUtils.clamp(dt, 0.001, 0.10);

    _accelWindow.add(rawAccel);
    _gyroWindow.add(rawGyro);
    _speedWindow.add(vTcn ?? 0.0);

    if (_accelWindow.length > IdrConstants.alignmentSampleCount) {
      _accelWindow.removeAt(0);
      _gyroWindow.removeAt(0);
      _speedWindow.removeAt(0);
    }

    // Strapdown Gyro-Assisted Gravity Tracking:
    // Propagates gravity vector in sensor frame using angular velocity to eliminate phase lag
    if (_lowPassGravity == null) {
      _lowPassGravity = rawAccel;
    } else {
      Vec3 gPred = _lowPassGravity!;
      final wNorm = rawGyro.norm;
      if (wNorm > 1e-4) {
        final wUnit = rawGyro / wNorm;
        // In the body frame, the gravity vector rotates opposite to body angular velocity
        gPred = _rotateVector(_lowPassGravity!, wUnit, -wNorm * effectiveDt);
      }

      final aNorm = rawAccel.norm;
      // Orientation can only change when phone is rotating (wNorm > 0.03) or during initial lock:
      final bool allowAdapt = wNorm > 0.03 || !_locked;
      if (allowAdapt && aNorm > 7.5 && aNorm < 12.0) {
        // Fast adaptation (0.10) when actively rotating, 0.03 during startup convergence
        final alpha = wNorm > 0.10 ? 0.10 : 0.03;
        _lowPassGravity = gPred * (1.0 - alpha) + rawAccel * alpha;
      } else {
        // When wNorm < 0.03 and locked, any acceleration change is vehicle linear throttle/braking!
        // Do NOT corrupt gravity vector with vehicle linear acceleration!
        _lowPassGravity = gPred;
      }
    }

    // Dynamic Mahony SO(3) Attitude Observer:
    final aNorm = rawAccel.norm;
    // Only adapt gravity observer if acceleration magnitude is reasonably close to 1g (7.5 to 12.0 m/s^2)
    // to prevent linear acceleration shocks from corrupting tilt.
    if (aNorm > 7.5 && aNorm < 12.0) {
      final aUnit = rawAccel.normalized;

      // Estimated gravity direction in sensor frame via current orientation:
      // In vehicle frame, gravity vector points in -Z: [0, 0, -1].
      // Rotating [0, 0, 1] into sensor frame:
      final gEstSensor = _qBv.inverseRotate(const Vec3(0.0, 0.0, 1.0));

      // Error vector e = aUnit x gEstSensor
      final e = aUnit.cross(gEstSensor);

      // Dynamically de-weight Mahony gain if vehicle is accelerating aggressively according to TCN
      double dynamicKp = _kp;
      if (vTcn != null && vTcn > 2.0) {
        dynamicKp *= 0.5; // Damped adaptation during forward cruising
      }

      // Integral gyroscope bias update
      _gyroBias = _gyroBias - (e * (_ki * effectiveDt));

      // Corrected angular rate
      final wCorr = (rawGyro - _gyroBias) + (e * dynamicKp);

      // Quaternion kinematics: q_dot = 0.5 * q * [0, wCorr]
      final dq = _qBv * Quaternion(0.0, wCorr.x, wCorr.y, wCorr.z);
      _qBv = (_qBv + dq.scale(0.5 * effectiveDt)).normalized;
    }

    _updateAlignment(vTcn: vTcn, tcnVariance: tcnVariance);
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
    _lowPassGravity = null;
    _rBv = Mat3.identity;
    _qBv = Quaternion.identity;
    _gyroBias = Vec3.zero;
    _mountRoll = 0.0;
    _mountPitch = 0.0;
    _mountYaw = 0.0;
    _confidence = 0.0;
    _locked = false;
  }

  Vec3? get lowPassGravity => _lowPassGravity;

  void _updateAlignment({bool forceLock = false, double? vTcn, double? tcnVariance}) {
    if (_lowPassGravity == null) return;

    // Estimate gravity unit vector in sensor frame
    final gHat = _lowPassGravity!.normalized;
    final gNorm = _lowPassGravity!.norm;

    // Check consistency with earth gravity 9.8 m/s^2
    final gravityResidual = (gNorm - IdrConstants.gravity).abs();
    final gravityScore = math.max(0.0, 1.0 - (gravityResidual / 3.0));

    // Check dynamic variance (phone is reasonably stable)
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

    // Continuous provisional tilt removal — active immediately from sample 0
    if (gNorm > 7.0 && gNorm < 12.5) {
      final pitch = math.atan2(-gHat.x, math.sqrt(gHat.y * gHat.y + gHat.z * gHat.z));
      final roll = math.atan2(gHat.y, gHat.z);

      _mountPitch = pitch;
      _mountRoll = roll;

      final cp = math.cos(pitch);
      final sp = math.sin(pitch);
      final cr = math.cos(roll);
      final sr = math.sin(roll);

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
      _qBv = Quaternion.fromEuler(roll, pitch, _mountYaw);
    }

    if ((_confidence >= 0.70 || forceLock) && _accelWindow.length >= 20) {
      // Module 1 Section 3.2: PCA for horizontal forward axis alignment
      // Condition PCA on vehicle motion if TCN speed is provided
      final bool allowPca = (vTcn == null) || (vTcn > 1.2 && (tcnVariance ?? 0.16) < 0.40);
      if (_accelWindow.length >= 20 && allowPca) {
        _computePcaForwardAxis();
      }

      _locked = true;
    }
  }

  void _computePcaForwardAxis() {
    var sumX = 0.0;
    var sumY = 0.0;
    final leveledSamples = <Vec3>[];

    for (final rawA in _accelWindow) {
      final leveled = _rBv.transform(rawA);
      leveledSamples.add(leveled);
      sumX += leveled.x;
      sumY += leveled.y;
    }

    final meanX = sumX / leveledSamples.length;
    final meanY = sumY / leveledSamples.length;

    // Sample covariance Sigma in R^{2x2} (Eqn 9)
    var covXX = 0.0;
    var covXY = 0.0;
    var covYY = 0.0;

    for (final s in leveledSamples) {
      final dx = s.x - meanX;
      final dy = s.y - meanY;
      covXX += dx * dx;
      covXY += dx * dy;
      covYY += dy * dy;
    }

    final n = leveledSamples.length - 1;
    if (n > 0) {
      covXX /= n;
      covXY /= n;
      covYY /= n;

      // 2x2 symmetric eigenvalue decomposition for dominant forward direction (Eqn 10)
      final trace = covXX + covYY;
      final diff = covXX - covYY;
      final disc = math.sqrt(diff * diff + 4.0 * covXY * covXY);
      final lambda1 = 0.5 * (trace + disc);

      // Only fit forward axis if genuine vehicle dynamics are present (variance > 0.05 m^2/s^4)
      // Guard against fitting random MEMS thermal sensor noise at standstill/idle
      if (lambda1 > 0.05) {
        // Analytical non-degenerate PCA direction theta = 0.5 * atan2(2 * covXY, covXX - covYY)
        final thetaPca = MathUtils.pcaOrientationAngle(covXX, covXY, covYY);
        var uX = math.cos(thetaPca);
        var uY = math.sin(thetaPca);

        // Velocity-acceleration directional correlation to resolve 180-deg sign ambiguity
        double dotCorrelation = 0.0;
        if (_speedWindow.length == leveledSamples.length && _speedWindow.length >= 3) {
          for (int i = 1; i < leveledSamples.length - 1; i++) {
            final aProj = leveledSamples[i].x * uX + leveledSamples[i].y * uY;
            final dv = _speedWindow[i + 1] - _speedWindow[i - 1];
            dotCorrelation += aProj * dv;
          }
        }

        // Centripetal turning confirmation: a_lat = v * omega_z
        double centripetalCorrelation = 0.0;
        if (_gyroWindow.length == leveledSamples.length) {
          for (int i = 0; i < leveledSamples.length; i++) {
            final aLat = -uY * leveledSamples[i].x + uX * leveledSamples[i].y;
            final wZ = _gyroWindow[i].z;
            final v = i < _speedWindow.length ? _speedWindow[i] : 1.0;
            if (v > 1.0 && wZ.abs() > 0.05) {
              centripetalCorrelation += aLat * (v * wZ);
            }
          }
        }

        // Invert vector if correlation strongly indicates reverse alignment
        if (dotCorrelation < -0.05 || (dotCorrelation.abs() <= 0.05 && centripetalCorrelation < -0.05)) {
          uX = -uX;
          uY = -uY;
        }

        _mountYaw = math.atan2(uY, uX);
      }
    }
  }

  /// Transforms raw sensor acceleration into leveled vehicle frame WITHOUT gravity subtraction:
  /// returns pure specific force [f_fwd, f_lat, f_vert] in the vehicle frame.
  Vec3 transformSpecificForce(Vec3 rawAccel) {
    return _rBv.transform(rawAccel);
  }

  /// Transforms raw sensor acceleration into vehicle frame:
  /// [a_fwd, a_lat, a_vert] with gravity subtracted.
  Vec3 transformAccel(Vec3 rawAccel) {
    // Rotate into leveled vehicle frame
    final aLeveled = _rBv.transform(rawAccel);
    // Remove vertical gravity
    return Vec3(aLeveled.x, aLeveled.y, aLeveled.z - IdrConstants.gravity);
  }

  /// Transforms raw sensor angular rates into vehicle frame:
  /// [w_roll, w_pitch, w_yaw].
  Vec3 transformGyro(Vec3 rawGyro) {
    return _rBv.transform(rawGyro);
  }

  /// Exact 3D Rodrigues rotation of vector [v] around unit axis [axisUnit] by [angleRad].
  static Vec3 _rotateVector(Vec3 v, Vec3 axisUnit, double angleRad) {
    final c = math.cos(angleRad);
    final s = math.sin(angleRad);
    final kCrossV = axisUnit.cross(v);
    final kDotV = axisUnit.dot(v);
    return (v * c) + (kCrossV * s) + (axisUnit * (kDotV * (1.0 - c)));
  }
}
