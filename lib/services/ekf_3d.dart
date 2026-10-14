// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import '../core/constants.dart';
import '../core/math_utils.dart';
import '../models/ekf_state.dart';

/// Module 4: 15-State 3D Error-State Kalman Filter (ESKF) with Multiplicative Quaternion
/// Attitude Parameterization, In-State 6-DOF IMU Bias Estimation, and Non-Holonomic Constraints (NHC).
///
/// Formulation:
/// - Nominal State:
///   p in R^3: Position [px, py, pz] in navigation frame (Local ENU)
///   v in R^3: Velocity [vx, vy, vz] in navigation frame (Local ENU)
///   q in H:   Attitude quaternion representing rotation from body to navigation frame
///   b_g in R^3: Gyroscope bias [bgx, bgy, bgz] in body frame (rad/s)
///   b_a in R^3: Accelerometer bias [bax, bay, baz] in body frame (m/s^2)
///
/// - Error State Vector delta_x in R^15:
///   delta_x = [delta_p (0..2), delta_v (3..5), delta_theta (6..8), delta_b_g (9..11), delta_b_a (12..14)]^T
///   where delta_theta is the rotation vector error in the navigation frame.
///
/// - Error Dynamics Transition Matrix F_delta in R^{15x15}:
///   F = I + F_c * dt
///   - F[0..2, 3..5] = I * dt (position from velocity)
///   - F[0..2, 6..8] = -[v_nav]x * dt (position from heading during turns)
///   - F[3..5, 6..8] = -[a_nav]x * dt (velocity from attitude error)
///   - F[3..5, 12..14] = -R * dt (velocity from accel bias)
///   - F[6..8, 9..11] = -R * dt (attitude from gyro bias)
///
/// - Full 15x15 Covariance Propagation:
///   P_{k|k-1} = F * P_{k-1|k-1} * F^T + Q
///
/// - Measurement Updates (Error-State Correction & Injection):
///   K = P * H^T * (H * P * H^T + R)^-1
///   delta_x = K * (z - h)
///   P = (I - K * H) * P
///   Injection:
///     p <- p + delta_p
///     v <- v + delta_v
///     q <- q(delta_theta) * q
///     b_g <- b_g + delta_b_g
///     b_a <- b_a + delta_b_a
///   Reset error state: delta_x = 0
class Ekf3D {
  // --- Nominal State Variables ---
  Vec3 _p = Vec3.zero;
  Vec3 _v = Vec3.zero;
  Quaternion _q = Quaternion.identity;
  Vec3 _bg = Vec3.zero;
  Vec3 _ba = Vec3.zero;

  // Scalar forward speed along vehicle heading
  double _forwardSpeed = 0.0;

  // Discrete multi-sample coning and sculling memory
  Vec3 _prevRotVec = Vec3.zero;
  Vec3 _prevDv = Vec3.zero;
  Vec3 _lastVehicleGyro = Vec3.zero;
  double _prevYawRate = 0.0;

  // Default mount lever-arm relative to vehicle rear axle [x_fwd, y_lat, z_up]
  Vec3 mountLeverArm = const Vec3(1.25, 0.0, 0.45);

  // Geodetic latitude for dynamic Somigliana normal gravity and Coriolis compensation
  double _latitudeDeg = 20.0;
  double get latitudeDeg => _latitudeDeg;
  void setLatitude(double latDeg) {
    if (latDeg.abs() <= 89.0) {
      _latitudeDeg = latDeg;
    }
  }

  // Sage-Husa adaptive innovation scaling factor
  double _sageHusaScale = 1.0;
  double get sageHusaScale => _sageHusaScale;

  // --- Full 15x15 Error-State Covariance Matrix ---
  // Stored as flat row-major array of 225 doubles
  final List<double> _P = List<double>.filled(225, 0.0);

  // Preallocated working buffers for zero-allocation propagation and updates
  final List<double> _F = List<double>.filled(225, 0.0);
  final List<double> _FP = List<double>.filled(225, 0.0);
  final List<double> _H = List<double>.filled(15, 0.0);
  final List<double> _V = List<double>.filled(15, 0.0);
  final List<double> _K = List<double>.filled(15, 0.0);
  final List<double> _dx = List<double>.filled(15, 0.0);

  Ekf3D({double initYaw = 0.0, double initPitch = 0.0, double initRoll = 0.0}) {
    reset(initYaw: initYaw, initPitch: initPitch, initRoll: initRoll);
  }

  // --- Public Getters ---
  double get gyroBiasZ => _bg.z;
  double get accelBiasX => _ba.x;
  double get crossCovariancePxYaw => _P[0 * 15 + 8]; // px <-> yaw (row 0, col 8)
  double get crossCovariancePyYaw => _P[1 * 15 + 8]; // py <-> yaw (row 1, col 8)
  double get crossCovariancePxVx => _P[0 * 15 + 3];  // px <-> vx (row 0, col 3)
  double get crossCovariancePyVy => _P[1 * 15 + 4];  // py <-> vy (row 1, col 4)
  double get crossCovarianceP08 => _P[0 * 15 + 8];   // px <-> yaw
  double get crossCovarianceP18 => _P[1 * 15 + 8];   // py <-> yaw

  /// Legacy aliases preserved for backwards compatibility with tests and callers
  @Deprecated('Use crossCovariancePxYaw or crossCovarianceP08 instead.')
  double get crossCovarianceP03 => _P[0 * 15 + 8]; // px <-> yaw
  @Deprecated('Use crossCovariancePyYaw or crossCovarianceP18 instead.')
  double get crossCovarianceP13 => _P[1 * 15 + 8]; // py <-> yaw

  double get forwardSpeed => _forwardSpeed;
  double get headingRad => _q.toEuler().yaw;
  double get climbRate => _v.z;
  double get covarianceTrace => _P[0 * 15 + 0] + _P[1 * 15 + 1] + _P[2 * 15 + 2];

  /// Current 3D navigation state formatted as EkfState (with full 9x9 telemetry covariance)
  EkfState get state {
    final euler = _q.toEuler();
    final cov = List<double>.filled(81, 0.0);

    // Export full 9x9 submatrix (position, velocity, attitude) from 15x15 covariance
    for (int i = 0; i < 9; i++) {
      final i15 = i * 15;
      final i9 = i * 9;
      for (int j = 0; j < 9; j++) {
        cov[i9 + j] = _P[i15 + j];
      }
    }

    return EkfState(
      position: _p,
      velocity: _v,
      attitude: Vec3(euler.roll, euler.pitch, euler.yaw),
      covariance: cov,
    );
  }

  /// Initialize heading (e.g. from compass azimuth on startup).
  void initializeHeading(double headingRad) {
    final euler = _q.toEuler();
    _q = Quaternion.fromEuler(euler.roll, euler.pitch, MathUtils.normalizeAngle(headingRad));
    _resetStateVariance(8, 0.01);
  }

  /// Initialize full 3D vehicle attitude (roll, pitch, yaw).
  void initializeAttitude({double roll = 0.0, double pitch = 0.0, double yaw = 0.0}) {
    _q = Quaternion.fromEuler(roll, pitch, MathUtils.normalizeAngle(yaw));
    _resetStateVariance(6, 0.001);
    _resetStateVariance(7, 0.001);
    _resetStateVariance(8, 0.01);
  }

  /// Translates navigation position by delta vector (used during map anchor re-projection)
  void translatePosition(Vec3 delta) {
    _p = _p + delta;
  }

  /// Sets navigation position directly (used during nominal GNSS anchoring)
  void setPosition(Vec3 pos) {
    _p = pos;
  }

  /// Reset filter state and covariance matrix to default initial values.
  void reset({double initYaw = 0.0, double initPitch = 0.0, double initRoll = 0.0}) {
    _p = Vec3.zero;
    _v = Vec3.zero;
    _q = Quaternion.fromEuler(initRoll, initPitch, MathUtils.normalizeAngle(initYaw));
    _bg = Vec3.zero;
    _ba = Vec3.zero;
    _forwardSpeed = 0.0;
    _prevRotVec = Vec3.zero;
    _prevDv = Vec3.zero;
    _lastVehicleGyro = Vec3.zero;
    _prevYawRate = 0.0;
    _sageHusaScale = 1.0;

    for (int i = 0; i < 225; i++) {
      _P[i] = 0.0;
    }

    // Position variances [px, py, pz]
    _P[0 * 15 + 0] = 1.0;
    _P[1 * 15 + 1] = 1.0;
    _P[2 * 15 + 2] = 2.0;

    // Velocity variances [vx, vy, vz]
    _P[3 * 15 + 3] = 0.25;
    _P[4 * 15 + 4] = 0.25;
    _P[5 * 15 + 5] = 0.20;

    // Attitude variances [roll, pitch, yaw]
    _P[6 * 15 + 6] = 0.001;
    _P[7 * 15 + 7] = 0.001;
    _P[8 * 15 + 8] = 0.01;

    // Gyro bias variances [bgx, bgy, bgz]
    _P[9 * 15 + 9] = 1e-4;
    _P[10 * 15 + 10] = 1e-4;
    _P[11 * 15 + 11] = 1e-4;

    // Accel bias variances [bax, bay, baz]
    _P[12 * 15 + 12] = 1e-3;
    _P[13 * 15 + 13] = 1e-3;
    _P[14 * 15 + 14] = 1e-3;
  }

  /// Kinematic nominal state strapdown integration and 15x15 covariance propagation.
  void predict({
    required Vec3 vehicleAccel,
    required Vec3 vehicleGyro,
    double dt = IdrConstants.dtImu,
    double qInflation = 1.0,
    double? vTcn,
    double? vVio,
    double gamma = 0.85,
    double wv = 1.0,
    double tcnVariance = 0.16,
    Vec3? vehicleSpecificForce,
  }) {
    final effectiveDt = MathUtils.clamp(dt, 0.001, 0.10);

    // 1. Correct IMU inputs with in-filter estimated biases
    final wUnbiased = vehicleGyro - _bg;
    final aUnbiased = vehicleAccel - _ba;
    final fUnbiased = (vehicleSpecificForce != null) ? (vehicleSpecificForce - _ba) : null;
    _lastVehicleGyro = vehicleGyro;

    // 2. Multi-sample Bortz coning correction on SO(3)
    final currRotVec = wUnbiased * effectiveDt;
    final coning = MathUtils.bortzConingVector(_prevRotVec, currRotVec);
    final effectiveRotVec = currRotVec + coning;
    final oldRotVec = _prevRotVec;
    _prevRotVec = currRotVec;

    final startYaw = headingRad;
    final dq = Quaternion.fromRotationVector(effectiveRotVec);
    _q = (_q * dq).normalized;

    final R = _q.toRotationMatrix();

    // 3. Accelerations in navigation frame with dynamic Earth Coriolis, transport rate, and geodetic normal gravity
    final aApparent = MathUtils.apparentAcceleration(vNav: _v, latDeg: _latitudeDeg, altM: _p.z);
    Vec3 aNav;
    if (fUnbiased != null) {
      final fNav = R.transform(fUnbiased);
      final normalGravity = MathUtils.wgs84NormalGravity(_latitudeDeg, _p.z);
      aNav = fNav + Vec3(0.0, 0.0, -normalGravity) - aApparent;
    } else {
      final aNavRaw = R.transform(aUnbiased);
      aNav = aNavRaw - aApparent;
    }

    // Second-order 2-sample sculling velocity correction
    final currDv = (fUnbiased ?? aUnbiased) * effectiveDt;
    final scullBody = MathUtils.scullingCorrection(oldRotVec, currRotVec, _prevDv, currDv);
    _prevDv = currDv;
    final scullNav = R.transform(scullBody);

    // 4. Multi-modal forward velocity fusion / closed-form SE(2) arc integration
    if (vTcn != null) {
      double vFused;
      if (vVio != null) {
        vFused = gamma * vTcn + (1.0 - gamma) * vVio;
      } else {
        vFused = vTcn;
      }
      _forwardSpeed = vFused;

      final fwdNav = Vec3(R.m00, R.m10, R.m20);
      final pitch = _q.toEuler().pitch;
      final vH = vFused * math.cos(pitch);
      final vZClimb = vFused * math.sin(pitch);
      
      // Preserve Kalman filter cross-track/vertical velocity corrections (e.g. from GNSS Doppler, NHC)
      // by adjusting forward velocity delta along vehicle heading rather than discarding orthogonal states
      final curFwdSpeed = fwdNav.dot(_v);
      final fwdDelta = vFused - curFwdSpeed;
      _v = _v + fwdNav * fwdDelta;
      _v = Vec3(_v.x, _v.y, vZClimb * 0.5 + _v.z * 0.5);

      // Exact SE(2) circular arc integration around true 3D quaternion yaw rate
      final deltaYaw = MathUtils.normalizeAngle(headingRad - startYaw);
      final effOmegaZ = effectiveDt > 1e-4 ? (deltaYaw / effectiveDt) : wUnbiased.z;
      final arc = MathUtils.arcStepSE2(
        speed: vH,
        yaw: startYaw,
        omegaZ: effOmegaZ,
        dt: effectiveDt,
      );
      _p = Vec3(_p.x + arc.dx, _p.y + arc.dy, _p.z + vZClimb * effectiveDt);
    } else {
      // Pure strapdown double integration with sculling velocity correction
      _p = _p + _v * effectiveDt + (aNav * effectiveDt + scullNav) * (0.5 * effectiveDt);
      _v = _v + aNav * effectiveDt + scullNav;
      _forwardSpeed = math.max(0.0, R.m00 * _v.x + R.m10 * _v.y + R.m20 * _v.z);
    }

    // 5. Build Analytical 15x15 Error-State Transition Matrix F
    for (int i = 0; i < 225; i++) {
      _F[i] = 0.0;
    }
    for (int i = 0; i < 15; i++) {
      _F[i * 15 + i] = 1.0;
    }

    // Position from velocity: F[0..2, 3..5] = I * dt
    _F[0 * 15 + 3] = effectiveDt;
    _F[1 * 15 + 4] = effectiveDt;
    _F[2 * 15 + 5] = effectiveDt;

    // Position from attitude error: -[v_nav]x * dt
    _F[0 * 15 + 7] = _v.z * effectiveDt;
    _F[0 * 15 + 8] = -_v.y * effectiveDt;
    _F[1 * 15 + 6] = -_v.z * effectiveDt;
    _F[1 * 15 + 8] = _v.x * effectiveDt;
    _F[2 * 15 + 6] = _v.y * effectiveDt;
    _F[2 * 15 + 7] = -_v.x * effectiveDt;

    // Velocity from attitude error: -[f_nav]x * dt (specific force, coupling gravity into pitch/roll)
    final fForF = (fUnbiased != null)
        ? R.transform(fUnbiased)
        : (R.transform(aUnbiased) + const Vec3(0.0, 0.0, IdrConstants.gravity));
    _F[3 * 15 + 7] = fForF.z * effectiveDt;
    _F[3 * 15 + 8] = -fForF.y * effectiveDt;
    _F[4 * 15 + 6] = -fForF.z * effectiveDt;
    _F[4 * 15 + 8] = fForF.x * effectiveDt;
    _F[5 * 15 + 6] = fForF.y * effectiveDt;
    _F[5 * 15 + 7] = -fForF.x * effectiveDt;

    // Velocity from accel bias: -R * dt
    _F[3 * 15 + 12] = -R.m00 * effectiveDt;
    _F[3 * 15 + 13] = -R.m01 * effectiveDt;
    _F[3 * 15 + 14] = -R.m02 * effectiveDt;
    _F[4 * 15 + 12] = -R.m10 * effectiveDt;
    _F[4 * 15 + 13] = -R.m11 * effectiveDt;
    _F[4 * 15 + 14] = -R.m12 * effectiveDt;
    _F[5 * 15 + 12] = -R.m20 * effectiveDt;
    _F[5 * 15 + 13] = -R.m21 * effectiveDt;
    _F[5 * 15 + 14] = -R.m22 * effectiveDt;

    // Attitude error propagation: in navigation-frame error state (dq * q), d(delta_theta)/dt = -R*delta_bg + R*wg.
    // The Jacobian d(delta_theta_dot) / d(delta_theta) is identically 0, so F[6..8, 6..8] = I_3x3.

    // Attitude from gyro bias: -R * dt
    _F[6 * 15 + 9] = -R.m00 * effectiveDt;
    _F[6 * 15 + 10] = -R.m01 * effectiveDt;
    _F[6 * 15 + 11] = -R.m02 * effectiveDt;
    _F[7 * 15 + 9] = -R.m10 * effectiveDt;
    _F[7 * 15 + 10] = -R.m11 * effectiveDt;
    _F[7 * 15 + 11] = -R.m12 * effectiveDt;
    _F[8 * 15 + 9] = -R.m20 * effectiveDt;
    _F[8 * 15 + 10] = -R.m21 * effectiveDt;
    _F[8 * 15 + 11] = -R.m22 * effectiveDt;

    // 6. Covariance Propagation: P = F * P * F^T + Q
    _propagateCovariance(
      effectiveDt: effectiveDt,
      qInflation: qInflation,
      wv: wv,
      tcnVariance: tcnVariance,
    );
  }

  void _propagateCovariance({
    required double effectiveDt,
    required double qInflation,
    required double wv,
    required double tcnVariance,
  }) {
    // 1. FP = F * P
    for (int i = 0; i < 15; i++) {
      final i15 = i * 15;
      for (int j = 0; j < 15; j++) {
        double sum = 0.0;
        for (int k = 0; k < 15; k++) {
          final f_ik = _F[i15 + k];
          if (f_ik != 0.0) {
            sum += f_ik * _P[k * 15 + j];
          }
        }
        _FP[i15 + j] = sum;
      }
    }

    // 2. P_next = FP * F^T (with symmetry enforcement)
    for (int i = 0; i < 15; i++) {
      final i15 = i * 15;
      for (int j = i; j < 15; j++) {
        final j15 = j * 15;
        double sum = 0.0;
        for (int k = 0; k < 15; k++) {
          final f_jk = _F[j15 + k];
          if (f_jk != 0.0) {
            sum += _FP[i15 + k] * f_jk;
          }
        }
        _P[i15 + j] = sum;
        if (i != j) {
          _P[j15 + i] = sum;
        }
      }
    }

    // 3. Add Process Noise Q
    final aiConfidence = 1.0 / (1.0 + MathUtils.clamp(tcnVariance, 0.04, 4.0));
    final qScale = (qInflation / (math.max(wv, 0.04) * aiConfidence)) * _sageHusaScale;

    final sa = IdrConstants.qVelStd * IdrConstants.qVelStd;
    final vl = MathUtils.vanLoanProcessNoise(sa: sa, dt: effectiveDt, scale: qScale);
    final qVel = vl.qvv;
    // Van Loan double-integration process noise: qpp = (1/3)*Sa*dt^3
    // Chassis suspension travel / road surface jitter continuous position noise: Sp * dt
    final qPosSuspension = (IdrConstants.qPosStd * IdrConstants.qPosStd) * effectiveDt * qScale * 0.01;
    final qPos = vl.qpp + qPosSuspension;
    final qAtt = (IdrConstants.qAttStd * IdrConstants.qAttStd) * effectiveDt * qScale;
    // Speed-dependent heading process noise scheduling:
    // Yaw uncertainty tightens at higher vehicle speed due to strong non-holonomic kinematic directionality,
    // and relaxes at low speed / crawl where turning maneuvers dominate.
    final double speedFactor = math.max(0.35, 1.0 / (1.0 + 0.08 * _forwardSpeed));
    final double qYaw = qAtt * speedFactor;
    final qGyrB = (IdrConstants.qGyroBiasStd * IdrConstants.qGyroBiasStd) * effectiveDt;
    final qAccB = (IdrConstants.qAccelBiasStd * IdrConstants.qAccelBiasStd) * effectiveDt;

    _P[0 * 15 + 0] += qPos;
    _P[1 * 15 + 1] += qPos;
    _P[2 * 15 + 2] += qPos;

    _P[3 * 15 + 3] += qVel;
    _P[4 * 15 + 4] += qVel;
    _P[5 * 15 + 5] += qVel * 0.25;

    // Exact continuous-discrete Van Loan cross-coupling between position and velocity (1/2 * S_a * dt^2)
    final qPosVel = vl.qpv;
    _P[0 * 15 + 3] += qPosVel;
    _P[3 * 15 + 0] += qPosVel;
    _P[1 * 15 + 4] += qPosVel;
    _P[4 * 15 + 1] += qPosVel;
    _P[2 * 15 + 5] += qPosVel * 0.25;
    _P[5 * 15 + 2] += qPosVel * 0.25;

    _P[6 * 15 + 6] += qAtt;
    _P[7 * 15 + 7] += qAtt;
    _P[8 * 15 + 8] += qYaw;

    _P[9 * 15 + 9] += qGyrB;
    _P[10 * 15 + 10] += qGyrB;
    _P[11 * 15 + 11] += qGyrB;

    _P[12 * 15 + 12] += qAccB;
    _P[13 * 15 + 13] += qAccB;
    _P[14 * 15 + 14] += qAccB;

    // Clamp diagonal variances to maintain positive semi-definiteness
    for (int i = 0; i < 15; i++) {
      if (_P[i * 15 + i] < 1e-8) {
        _P[i * 15 + i] = 1e-8;
      }
    }
  }

  void _clearH() {
    for (int i = 0; i < 15; i++) {
      _H[i] = 0.0;
    }
  }

  /// Safely resets state variance for [idx] to [varValue] and zeros out its cross-covariances
  /// to maintain positive semi-definiteness.
  void _resetStateVariance(int idx, double varValue) {
    for (int j = 0; j < 15; j++) {
      _P[idx * 15 + j] = 0.0;
      _P[j * 15 + idx] = 0.0;
    }
    _P[idx * 15 + idx] = varValue;
  }

  /// Universal ESKF scalar Kalman measurement update with error state injection.
  bool _correctScalar(List<double> H, double innov, double R, {bool updateCovariance = true}) {
    // 1. V = P * H^T (15-vector)
    for (int i = 0; i < 15; i++) {
      final i15 = i * 15;
      double sum = 0.0;
      for (int j = 0; j < 15; j++) {
        final hj = H[j];
        if (hj != 0.0) {
          sum += _P[i15 + j] * hj;
        }
      }
      _V[i] = sum;
    }

    // S = H * P * H^T + R
    double hPh = 0.0;
    for (int i = 0; i < 15; i++) {
      final hi = H[i];
      if (hi != 0.0) {
        hPh += hi * _V[i];
      }
    }

    final S = hPh + R;
    if (S <= 1e-12 || S.isNaN || S.isInfinite) return false;

    final invS = 1.0 / S;

    // 2. Kalman Gain: K = V / S
    for (int i = 0; i < 15; i++) {
      _K[i] = _V[i] * invS;
    }

    // 3. Error state correction: delta_x = K * innov
    for (int i = 0; i < 15; i++) {
      _dx[i] = _K[i] * innov;
    }

    // 4. Joseph-stabilized Covariance update:
    // P_new = (I - K*H) * P * (I - K*H)^T + K * R * K^T
    // For scalar update: P_new = P - K*V^T - V*K^T + K*S*K^T
    // Guaranteed to remain positive semi-definite under finite floating-point precision
    if (updateCovariance) {
      for (int i = 0; i < 15; i++) {
        final i15 = i * 15;
        final ki = _K[i];
        final vi = _V[i];
        for (int j = i; j < 15; j++) {
          final kj = _K[j];
          final vj = _V[j];
          final val = _P[i15 + j] - ki * vj - vi * kj + (ki * kj) * S;
          _P[i15 + j] = val;
          if (i != j) {
            _P[j * 15 + i] = val;
          }
        }
        if (_P[i15 + i] < 1e-8) {
          _P[i15 + i] = 1e-8;
        }
      }
    }

    // 5. Inject error state into nominal state
    // Position: p = p + delta_p
    _p = Vec3(_p.x + _dx[0], _p.y + _dx[1], _p.z + _dx[2]);

    // Velocity: v = v + delta_v
    _v = Vec3(_v.x + _dx[3], _v.y + _dx[4], _v.z + _dx[5]);

    // Attitude: q = q(delta_theta) * q
    final dRot = Vec3(_dx[6], _dx[7], _dx[8]);
    final dq = Quaternion.fromRotationVector(dRot);
    _q = (dq * _q).normalized;

    // Gyro bias: bg = bg + delta_bg
    _bg = Vec3(
      MathUtils.clamp(_bg.x + _dx[9], -0.15, 0.15),
      MathUtils.clamp(_bg.y + _dx[10], -0.15, 0.15),
      MathUtils.clamp(_bg.z + _dx[11], -0.15, 0.15),
    );

    // Accel bias: ba = ba + delta_ba
    _ba = Vec3(
      MathUtils.clamp(_ba.x + _dx[12], -0.50, 0.50),
      MathUtils.clamp(_ba.y + _dx[13], -0.50, 0.50),
      MathUtils.clamp(_ba.z + _dx[14], -0.50, 0.50),
    );

    // Update forward speed scalar
    final Rmat = _q.toRotationMatrix();
    _forwardSpeed = math.max(0.0, Rmat.m00 * _v.x + Rmat.m10 * _v.y + Rmat.m20 * _v.z);

    return true;
  }

  /// Apply Non-Holonomic Constraints (NHC) (Eqn 25) with vehicle lever-arm compensation.
  /// Ground vehicles cannot slip sideways (v_lat ~ 0) or fly upwards (v_z ~ 0).
  void applyNhc({double verticalReference = 0.0, Vec3? customLeverArm}) {
    updateNhc(verticalReference: verticalReference, customLeverArm: customLeverArm);
  }

  /// Full Kalman Non-Holonomic Constraints (NHC) update with vehicle lever-arm compensation.
  void updateNhc({double verticalReference = 0.0, Vec3? customLeverArm}) {
    final R = _q.toRotationMatrix();
    // Body lateral unit vector in navigation frame: column 1 of R
    final eLat = Vec3(R.m01, R.m11, R.m21);
    // Body vertical unit vector in navigation frame: column 2 of R
    final eVert = Vec3(R.m02, R.m12, R.m22);

    // Lever-arm induced velocity at IMU location due to vehicle yaw rotation around rear axle
    final arm = customLeverArm ?? mountLeverArm;
    final wU = _lastVehicleGyro - _bg;
    // v_lever_body = w x r_arm
    final vLatInduced = wU.z * arm.x - wU.x * arm.z;
    final vVertInduced = wU.x * arm.y - wU.y * arm.x;

    // Dynamic tire sideslip relaxation: in high-speed turns, centripetal acceleration creates tire slip
    final aLat = _forwardSpeed * wU.z;
    final dynamicSigmaLat2 = MathUtils.adaptiveNhcLatVariance(
      IdrConstants.sigmaNhcLat2,
      aLat,
      _forwardSpeed,
    );

    // 1. Lateral Constraint: v_lat_axle = eLat . v - vLatInduced ~ 0
    // Pure velocity constraint along body lateral axis (eliminating inverted attitude coupling)
    final vLat = eLat.dot(_v);
    final innovLat = vLatInduced - vLat;

    _clearH();
    _H[3] = eLat.x;
    _H[4] = eLat.y;
    _H[5] = eLat.z;

    _correctScalar(_H, innovLat, dynamicSigmaLat2);

    // Physical wheel grip constraint: ground vehicle tires suppress lateral slip at axle
    final vLatResid = eLat.dot(_v) - vLatInduced;
    final slipFactor = MathUtils.clamp(1.0 - (aLat.abs() / 15.0), 0.50, 0.90);
    _v = _v - eLat * (vLatResid * slipFactor);

    // 2. Vertical Constraint: v_vert_axle = eVert . v - vVertInduced ~ verticalReference
    // Pure velocity constraint along body vertical axis
    final vVert = eVert.dot(_v);
    final targetVVert = verticalReference + vVertInduced;
    final innovVert = targetVVert - vVert;

    _clearH();
    _H[3] = eVert.x;
    _H[4] = eVert.y;
    _H[5] = eVert.z;

    _correctScalar(_H, innovVert, IdrConstants.sigmaNhcVert2);

    // Road plane constraint: ground vehicles cannot fly upwards
    final vVertResid = eVert.dot(_v) - targetVVert;
    _v = _v - eVert * (vVertResid * 0.90);
  }

  /// Module 5: Smart Map-Matching Filter Kalman Update with Corridored Deadband Huber loss & Chi-Square gating.
  void updateMapMatching({
    required Vec3 normal2D,
    required double crossTrackDistance,
    required double sigma,
    double? roadElevation,
    double sigmaAlt = 2.5,
    double laneDeadbandM = 1.75,
    bool updateCovariance = true,
  }) {
    final rMap = sigma * sigma;
    _clearH();
    _H[0] = normal2D.x;
    _H[1] = normal2D.y;

    final double hPh = normal2D.x * normal2D.x * _P[0 * 15 + 0] +
        2.0 * normal2D.x * normal2D.y * _P[0 * 15 + 1] +
        normal2D.y * normal2D.y * _P[1 * 15 + 1];
    final s = hPh + rMap;

    if (s > 1e-9) {
      final db = MathUtils.deadbandHuberLoss(
        rawResidual: crossTrackDistance,
        deadbandHalfWidthM: laneDeadbandM,
        k: 2.5,
      );
      // M-estimator robust formulation:
      // The innovation is the geometric excess displacement outside the lane deadband,
      // and measurement variance is inflated by 1 / huberWeight (matching updateTcnSpeed / updateTurnVelocity)
      // to avoid double-attenuation and prevent false covariance shrinkage on outliers.
      final w = math.max(db.weight, 1e-6);
      final signedExcess = db.weight > 0 ? (db.effectiveResidual / w) : 0.0;
      final inn = -signedExcess;
      if (inn.abs() > 1e-4) {
        _correctScalar(_H, inn, rMap / w, updateCovariance: updateCovariance);
      }
    }

    // Vertical road deck constraint
    if (roadElevation != null) {
      final rAlt = sigmaAlt * sigmaAlt;
      final sZ = _P[2 * 15 + 2] + rAlt;
      if (sZ > 1e-9) {
        final innZ = roadElevation - _p.z;
        final nisZ = (innZ * innZ) / sZ;
        if (MathUtils.passChiSquareGate(nisZ, 1, pValue: 0.0027)) {
          _clearH();
          _H[2] = 1.0;
          _correctScalar(_H, innZ, rAlt, updateCovariance: updateCovariance);
        }
      }
    }
  }

  /// Module 5 Upgrade: Iterated Extended Kalman Filter (IEKF) Map-Matching Update.
  /// Runs up to [maxIterations] Gauss-Newton local refinement iterations on non-linear
  /// cross-track orthogonal projections on sharp curves and cloverleaf ramps.
  void updateMapMatchingIterated({
    required Vec3 normal2D,
    required double crossTrackDistance,
    required double sigma,
    double? roadElevation,
    double sigmaAlt = 2.5,
    double laneDeadbandM = 1.75,
    int maxIterations = 2,
  }) {
    final bool hasSecondIteration = maxIterations > 1 && crossTrackDistance.abs() > 3.0;
    final pBefore = Vec3(_p.x, _p.y, _p.z);

    // If second iteration will be performed, update state only on first iteration,
    // and update covariance on the final iteration to prevent artificial covariance shrinkage.
    updateMapMatching(
      normal2D: normal2D,
      crossTrackDistance: crossTrackDistance,
      sigma: sigma,
      roadElevation: roadElevation,
      sigmaAlt: sigmaAlt,
      laneDeadbandM: laneDeadbandM,
      updateCovariance: !hasSecondIteration,
    );

    // If large residual on non-linear curve, run second iteration with re-linearized geometric residual
    if (hasSecondIteration) {
      final dp = _p - pBefore;
      // Re-linearize cross-track distance at the updated position along road normal
      final remainingCrossTrack = crossTrackDistance + (normal2D.x * dp.x + normal2D.y * dp.y);
      if (remainingCrossTrack.abs() > laneDeadbandM) {
        updateMapMatching(
          normal2D: normal2D,
          crossTrackDistance: remainingCrossTrack,
          sigma: sigma,
          roadElevation: roadElevation,
          sigmaAlt: sigmaAlt,
          laneDeadbandM: laneDeadbandM,
          updateCovariance: true,
        );
      } else {
        // Apply final covariance update for the map observation
        _clearH();
        _H[0] = normal2D.x;
        _H[1] = normal2D.y;
        final rMap = sigma * sigma;
        _correctScalar(_H, 0.0, rMap, updateCovariance: true);
        if (roadElevation != null) {
          final rAlt = sigmaAlt * sigmaAlt;
          _clearH();
          _H[2] = 1.0;
          _correctScalar(_H, 0.0, rAlt, updateCovariance: true);
        }
      }
    }
  }

  /// Constrains heading drift using the matched road segment azimuth during GNSS outages.
  void updateMapHeading(double roadHeadingRad, double confidence) {
    if (confidence < 0.45) return;
    final euler = _q.toEuler();
    final resid = MathUtils.normalizeAngle(roadHeadingRad - euler.yaw);
    if (resid.abs() > 0.52) return;

    final rHead = 0.08 / math.max(0.1, confidence);
    final s = _P[8 * 15 + 8] + rHead;
    if (s > 1e-9) {
      final nis = (resid * resid) / s;
      if (MathUtils.passChiSquareGate(nis, 1, pValue: 0.01)) {
        _clearH();
        _H[8] = 1.0;
        _correctScalar(_H, resid, rHead);
      }
    }
  }

  /// Update forward speed from AI TCN prediction with heteroscedastic uncertainty weighting and Huber loss.
  void updateTcnSpeed(double vTcn, {double? variance}) {
    final rTcn = variance != null
        ? MathUtils.clamp(variance, 0.04, 4.0)
        : (IdrConstants.tcnSpeedNoiseStd * IdrConstants.tcnSpeedNoiseStd);

    final Rmat = _q.toRotationMatrix();
    final eFwd = Vec3(Rmat.m00, Rmat.m10, Rmat.m20);
    final vFwd = eFwd.dot(_v);
    final inn = vTcn - vFwd;

    double hPh = 0.0;
    for (int i = 0; i < 3; i++) {
      final hi = (i == 0) ? eFwd.x : ((i == 1) ? eFwd.y : eFwd.z);
      for (int j = 0; j < 3; j++) {
        final hj = (j == 0) ? eFwd.x : ((j == 1) ? eFwd.y : eFwd.z);
        hPh += hi * _P[(3 + i) * 15 + (3 + j)] * hj;
      }
    }
    final s = hPh + rTcn;
    if (s > 1e-9) {
      final nis = (inn * inn) / s;
      // Sage-Husa adaptive innovation smoothing (forgetting factor b = 0.98)
      final instantFactor = MathUtils.clamp(math.sqrt(nis) / 1.5, 0.70, 2.5);
      _sageHusaScale = _sageHusaScale * 0.98 + instantFactor * 0.02;

      final huberW = MathUtils.huberWeight(math.sqrt(nis), k: 3.0);

      _clearH();
      _H[3] = eFwd.x;
      _H[4] = eFwd.y;
      _H[5] = eFwd.z;

      _correctScalar(_H, inn, rTcn / huberW);
      _forwardSpeed = math.max(0.0, eFwd.dot(_v));
    }
  }

  /// Turn Velocity Update (TVU / CASE):
  /// Fuses 100% physics-derived centripetal speed v = a_lat / omega_z during curved driving.
  void updateTurnVelocity(double vCentripetal, {double variance = 0.25}) {
    if (vCentripetal <= 0.0 || vCentripetal > 55.0) return;
    final rTvu = MathUtils.clamp(variance, 0.04, 4.0);

    final Rmat = _q.toRotationMatrix();
    final eFwd = Vec3(Rmat.m00, Rmat.m10, Rmat.m20);
    final vFwd = eFwd.dot(_v);
    final inn = vCentripetal - vFwd;

    double hPh = 0.0;
    for (int i = 0; i < 3; i++) {
      final hi = (i == 0) ? eFwd.x : ((i == 1) ? eFwd.y : eFwd.z);
      for (int j = 0; j < 3; j++) {
        final hj = (j == 0) ? eFwd.x : ((j == 1) ? eFwd.y : eFwd.z);
        hPh += hi * _P[(3 + i) * 15 + (3 + j)] * hj;
      }
    }
    final s = hPh + rTvu;
    if (s > 1e-9) {
      final nis = (inn * inn) / s;
      final huberW = MathUtils.huberWeight(math.sqrt(nis), k: 2.5);

      _clearH();
      _H[3] = eFwd.x;
      _H[4] = eFwd.y;
      _H[5] = eFwd.z;

      _correctScalar(_H, inn, rTvu / huberW);
      _forwardSpeed = math.max(0.0, eFwd.dot(_v));
    }
  }

  /// Update elevation using Barometer with Chi-Square outlier rejection (10 Hz).
  void updateBarometer(double zBaro) {
    const rBaro = IdrConstants.baroNoiseStd * IdrConstants.baroNoiseStd;
    final s = _P[2 * 15 + 2] + rBaro;
    if (s > 1e-9) {
      if (_p.z == 0.0 && _P[2 * 15 + 2] >= 1.5) {
        _p = Vec3(_p.x, _p.y, zBaro);
        _resetStateVariance(2, rBaro);
        return;
      }

      final inn = zBaro - _p.z;
      final nis = (inn * inn) / s;

      if (MathUtils.passChiSquareGate(nis, 1, pValue: 0.0027)) {
        _clearH();
        _H[2] = 1.0;
        _correctScalar(_H, inn, rBaro);
      }
    }
  }

  /// Third-Order Baro-Inertial Vertical Velocity Damping Update:
  /// Fuses differentiated barometric climb rate into vertical velocity state (vz),
  /// mathematically stabilizing the vertical double-integration channel.
  void updateBaroClimbRate(double vZBaro, {double sigmaVz = 0.50}) {
    final rVz = sigmaVz * sigmaVz;
    final s = _P[5 * 15 + 5] + rVz;
    if (s > 1e-9) {
      if (_v.z == 0.0 && _P[5 * 15 + 5] >= 0.15) {
        _v = Vec3(_v.x, _v.y, vZBaro);
        _resetStateVariance(5, rVz);
        return;
      }
      final inn = vZBaro - _v.z;
      final nis = (inn * inn) / s;
      if (nis <= 16.0) { // 4-sigma innovation gate
        _clearH();
        _H[5] = 1.0;
        _correctScalar(_H, inn, rVz);
      }
    }
  }

  /// Update position using GNSS with Seamless Sigmoid HDOP Covariance Weighting,
  /// 3D Mount Lever-Arm Antenna Translation, and Chi-Square Gating.
  void updateGnss({
    required double gnssX,
    required double gnssY,
    required double gnssZ,
    required double hdop,
    required bool isDenied,
    Vec3? customLeverArm,
  }) {
    if (isDenied || hdop >= 20.0) return;

    // Sigmoidal HDOP inflation (unified with C++ core: bounded scale in [1.0, 101.0])
    final s = 1.0 / (1.0 + math.exp(-2.0 * (hdop - 3.5)));
    final scale = 1.0 + 100.0 * s;
    final rBase = IdrConstants.rNominalGnss;
    final rGnss = rBase * scale;

    // Translate GNSS antenna coordinate to vehicle rear-axle center: p_axle = p_gnss - R * r_mount
    final arm = customLeverArm ?? mountLeverArm;
    final R = _q.toRotationMatrix();
    final leverNav = R.transform(arm);
    final effX = gnssX - leverNav.x;
    final effY = gnssY - leverNav.y;
    final effZ = gnssZ - leverNav.z;

    final dx = effX - _p.x;
    final dy = effY - _p.y;
    final dz = effZ - _p.z;
    final dist2 = dx * dx + dy * dy;

    // Fast Acquisition / Snap on GPS teleport or vehicle launch movement
    if (hdop <= 5.0 && (dist2 > 4.0 * 4.0 || (_p.x == 0.0 && _p.y == 0.0 && (effX != 0.0 || effY != 0.0)))) {
      _p = Vec3(effX, effY, effZ);
      _resetStateVariance(0, rGnss);
      _resetStateVariance(1, rGnss);
      _resetStateVariance(2, rGnss * 3.0);
      return;
    }

    // 3D Chi-Square Mahalanobis Innovation Gating (3 DOF, critical = 14.16 for 3-sigma)
    // Evaluates exact horizontal correlated 2x2 innovation covariance block S_2D = P_pos + R_gnss * I
    final sXX = _P[0 * 15 + 0] + rGnss;
    final sYY = _P[1 * 15 + 1] + rGnss;
    final sXY = _P[0 * 15 + 1]; // P_01 horizontal cross-covariance
    final sZ = _P[2 * 15 + 2] + (rGnss * 3.0);

    final detS2D = sXX * sYY - sXY * sXY;
    double dM2;
    if (detS2D > 1e-9) {
      final dM2Horizontal = (sYY * dx * dx - 2.0 * sXY * dx * dy + sXX * dy * dy) / detS2D;
      dM2 = dM2Horizontal + (dz * dz) / sZ;
    } else {
      dM2 = (dx * dx) / sXX + (dy * dy) / sYY + (dz * dz) / sZ;
    }

    if (!MathUtils.passChiSquareGate(dM2, 3, pValue: 0.0027) && scale > 5.0) {
      return;
    }

    // Sequential scalar position updates along X, Y, Z
    _clearH();
    _H[0] = 1.0;
    _correctScalar(_H, effX - _p.x, rGnss);

    _clearH();
    _H[1] = 1.0;
    _correctScalar(_H, effY - _p.y, rGnss);

    _clearH();
    _H[2] = 1.0;
    _correctScalar(_H, effZ - _p.z, rGnss * 3.0);
  }

  /// Online Dynamic Mount Lever-Arm Adaptation:
  /// Estimates physical sensor lever-arm offset relative to the vehicle's rear axle
  /// during sustained cornering under reliable GNSS tracking:
  /// a_lat = v * omega_z + dot_omega_z * r_x  =>  r_x = (a_lat - v * omega_z) / dot_omega_z
  void adaptMountLeverArm({
    required double measuredLatAccel,
    required double yawRate,
    required double gnssSpeed,
    double dt = 0.01,
  }) {
    if (gnssSpeed < 4.0 || yawRate.abs() < 0.12) {
      _prevYawRate = yawRate;
      return;
    }

    final effDt = MathUtils.clamp(dt, 0.005, 0.10);
    final dOmegaAbs = (yawRate.abs() - _prevYawRate.abs()) / effDt;
    _prevYawRate = yawRate;

    final expectedLatA = gnssSpeed * yawRate.abs();
    final excessA = measuredLatAccel.abs() - expectedLatA;

    // Rigid body kinematics: excess lateral acceleration during angular rate change is dot_omega_z * r_x
    if (excessA.abs() > 0.05 && excessA.abs() < 2.5 && dOmegaAbs.abs() > 0.15 && (excessA * dOmegaAbs) > 0) {
      final impliedRx = MathUtils.clamp(excessA / dOmegaAbs, 0.20, 2.50);
      mountLeverArm = Vec3(
        mountLeverArm.x * 0.995 + impliedRx * 0.005,
        mountLeverArm.y,
        mountLeverArm.z,
      );
    }
  }

  /// Zero-velocity update (ZUPT) and gyro & accel bias calibration when phone/vehicle is stationary.
  void applyStandstill(double rawGyroZ, [double rawAccelX = 0.0]) {
    _forwardSpeed = 0.0;
    _v = Vec3.zero;

    // Velocity uncertainty drops to near zero
    _resetStateVariance(3, 0.0001);
    _resetStateVariance(4, 0.0001);
    _resetStateVariance(5, 0.0001);

    // Position variances contract towards 0.20 m^2 floor via congruent transformation
    // scaling both diagonal and cross-covariance rows/columns to preserve positive semi-definiteness.
    // Floor is bounded at 0.20 m^2 so the filter does not suffer from covariance starvation (K -> 0)
    // when vehicle movement resumes.
    for (int k = 0; k < 3; k++) {
      if (_P[k * 15 + k] > 0.20) {
        const double scale = 0.9959919678; // sqrt(0.992)
        for (int j = 0; j < 15; j++) {
          _P[k * 15 + j] *= scale;
          _P[j * 15 + k] *= scale;
        }
      }
    }

    // Gyro bias calibration: stationary gyro reading is pure bias
    final newGz = MathUtils.clamp(_bg.z * 0.95 + rawGyroZ * 0.05, -0.08, 0.08);
    _bg = Vec3(_bg.x, _bg.y, newGz);
    _P[11 * 15 + 11] = math.max(1e-6, _P[11 * 15 + 11] * 0.99);

    // Forward accel bias calibration with pitch slope gravity compensation
    final dynamicFwd = MathUtils.slopeCompensatedForwardAccel(
      measuredFwdAccel: rawAccelX,
      pitchRad: _q.toEuler().pitch,
    );
    final newAx = MathUtils.clamp(_ba.x * 0.95 + dynamicFwd * 0.05, -0.20, 0.20);
    _ba = Vec3(newAx, _ba.y, _ba.z);
    _P[12 * 15 + 12] = math.max(1e-6, _P[12 * 15 + 12] * 0.99);
  }

  /// Straight-Line Zero Angular Rate Update (ZARU):
  /// When vehicle is cruising on expressway straightaways (v >= 8 m/s, Var(omega_z) < 0.0004),
  /// true yaw rate is identically 0. Continuously calibrates gyro z-bias in real time.
  void applyZaru(double rawGyroZ, double dt) {
    final inn = rawGyroZ - _bg.z;
    _clearH();
    _H[11] = 1.0;
    const double rZaru = 0.002;
    _correctScalar(_H, inn, rZaru);
  }

  /// Straight-Line Zero Acceleration Update (ZACU):
  /// When vehicle is cruising on expressways at steady speed (v >= 10 m/s, Var(speed) < 0.04 m^2/s^2),
  /// true dynamic forward acceleration is near 0. Continuously calibrates forward accelerometer bias b_ax.
  void applyZacu(double rawAccelX, double dt) {
    final dynamicFwd = MathUtils.slopeCompensatedForwardAccel(
      measuredFwdAccel: rawAccelX,
      pitchRad: _q.toEuler().pitch,
    );
    final inn = dynamicFwd - _ba.x;
    _clearH();
    _H[12] = 1.0;
    const double rZacu = 0.02;
    _correctScalar(_H, inn, rZacu);
  }

  /// Fuses high-accuracy GNSS Doppler ground speed directly into forward velocity.
  void updateGnssSpeed(double speedMps, double hdop) {
    if (speedMps < 0.0 || hdop > 6.0) return;

    if (speedMps < 0.5 && hdop <= 4.0) {
      _forwardSpeed = 0.0;
      _v = Vec3.zero;
      _resetStateVariance(3, 0.0001);
      _resetStateVariance(4, 0.0001);
      _resetStateVariance(5, 0.0001);
      return;
    }

    final Rmat = _q.toRotationMatrix();
    final eFwd = Vec3(Rmat.m00, Rmat.m10, Rmat.m20);
    final vFwd = eFwd.dot(_v);
    final inn = speedMps - vFwd;

    final rGnssV = 0.04 * math.max(1.0, hdop);

    _clearH();
    _H[3] = eFwd.x;
    _H[4] = eFwd.y;
    _H[5] = eFwd.z;

    _correctScalar(_H, inn, rGnssV);
    _forwardSpeed = math.max(0.0, eFwd.dot(_v));
  }

  /// Update heading using GNSS Doppler ground track course when moving.
  void updateCourse(double courseRad, double speed, {double hdop = 1.0}) {
    if (speed < 0.6 || hdop > 6.0) return;
    final euler = _q.toEuler();
    final resid = MathUtils.normalizeAngle(courseRad - euler.yaw);

    // Initial heading bootstrap: if heading uncertainty is high (P88 >= 0.008 rad^2 ~ 5.1° std)
    // and receiving reliable moving GNSS fix, snap heading directly to prevent permanent 45° gating deadlock
    if (_P[8 * 15 + 8] >= 0.008 && hdop <= 4.0 && speed > 1.0) {
      initializeHeading(courseRad);
      return;
    }

    // Innovation gating: reject > 45 deg yaw jump from reverse gear or multi-path
    if (resid.abs() > 0.785) return;

    final speedFactor = math.max(0.2, speed / 3.0);
    final rCourse = (0.04 / (speedFactor * speedFactor)) * math.max(1.0, hdop);
    final s = _P[8 * 15 + 8] + rCourse;
    if (s <= 1e-9) return;
    final nis = (resid * resid) / s;
    if (!MathUtils.passChiSquareGate(nis, 1, pValue: 0.0027)) return;

    _clearH();
    _H[8] = 1.0; // Observes yaw error delta_theta_z

    _correctScalar(_H, resid, rCourse);
  }

  /// Unified 2D/3D GNSS Doppler Velocity Vector Update.
  /// Fuses navigation-frame velocity vector [vEast, vNorth, vUp] directly into velocity states
  /// observing velocity error, heading error, and accelerometer biases simultaneously.
  void updateGnssVelocityVector({
    required double vEast,
    required double vNorth,
    double? vUp,
    required double hdop,
    required bool isDenied,
  }) {
    if (isDenied || hdop > 6.0) return;

    final rVel = 0.04 * math.max(1.0, hdop);

    // East velocity update (State 3: v_x)
    _clearH();
    _H[3] = 1.0;
    _correctScalar(_H, vEast - _v.x, rVel);

    // North velocity update (State 4: v_y)
    _clearH();
    _H[4] = 1.0;
    _correctScalar(_H, vNorth - _v.y, rVel);

    // Optional Up velocity update (State 5: v_z)
    if (vUp != null) {
      _clearH();
      _H[5] = 1.0;
      _correctScalar(_H, vUp - _v.z, rVel * 2.5);
    }

    final Rmat = _q.toRotationMatrix();
    _forwardSpeed = math.max(0.0, Rmat.m00 * _v.x + Rmat.m10 * _v.y + Rmat.m20 * _v.z);
  }

  /// Update heading using tilt-compensated electronic compass with adaptive Kalman gain.
  void updateCompass(
    double compassEnuRad, {
    bool isStationary = false,
    double? magneticFieldNorm,
    double? expectedFieldNorm,
  }) {
    final euler = _q.toEuler();
    final resid = MathUtils.normalizeAngle(compassEnuRad - euler.yaw);

    // Angular deadband: skip update on minute magnetic fluctuations (< 0.02 rad ~ 1.15 deg)
    if (resid.abs() < 0.02) return;

    _clearH();
    _H[8] = 1.0;

    // Adaptive measurement noise:
    // When stationary, gentle constraining gain (rCompass ~ 0.20)
    // When moving, higher noise due to dynamic vehicle electromagnetic interference
    double rCompass = isStationary ? 0.20 : 0.40;

    // Adaptive magnetic disturbance inflation:
    // If field norm deviates from expected local geomagnetic field (~45-50 uT),
    // scale up measurement variance rCompass proportionally to down-weight corrupted heading.
    if (magneticFieldNorm != null && magneticFieldNorm > 0.0) {
      final targetB = expectedFieldNorm ?? 45.0;
      final devPct = (magneticFieldNorm - targetB).abs() / targetB;
      if (devPct > 0.15) {
        final inflationFactor = 1.0 + 10.0 * (devPct - 0.15);
        rCompass *= math.min(inflationFactor, 25.0);
      }
    }

    _correctScalar(_H, resid, rCompass);
  }
}
