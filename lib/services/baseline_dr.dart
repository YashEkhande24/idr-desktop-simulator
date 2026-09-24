import '../core/constants.dart';
import '../core/math_utils.dart';
import '../models/ekf_state.dart';

/// Module 5: Baseline Engine (Classic Double-Integration Dead Reckoning)
///
/// Integrates raw unconstrained accelerations directly:
/// v_{k} = v_{k-1} + a_v * dt
/// p_{k} = p_{k-1} + v_{k-1} * dt + 0.5 * a_v * dt^2
///
/// Demonstrates the explosive quadratic drift (>140 meters) that occurs
/// without AI speed estimation, kinetic shock gating, or non-holonomic constraints.
class BaselineDr {
  double _px = 0.0;
  double _py = 0.0;
  double _pz = 0.0;
  double _vx = 0.0;
  double _vy = 0.0;
  double _vz = 0.0;
  double _roll = 0.0;
  double _pitch = 0.0;
  double _yaw = 0.0;

  BaselineDr({double initYaw = 0.0}) {
    _yaw = initYaw;
  }

  EkfState get state {
    return EkfState(
      position: Vec3(_px, _py, _pz),
      velocity: Vec3(_vx, _vy, _vz),
      attitude: Vec3(_roll, _pitch, _yaw),
      covariance: List<double>.filled(81, 0.0),
    );
  }

  /// Direct double-integration step without NHC or TCN corrections.
  void step({
    required Vec3 vehicleAccel,
    required Vec3 vehicleGyro,
    double dt = IdrConstants.dtImu,
  }) {
    final effectiveDt = dt > 1e-4 ? dt : IdrConstants.dtImu;

    // Direct gyro integration (subject to bias drift)
    _roll += vehicleGyro.x * effectiveDt;
    _pitch += vehicleGyro.y * effectiveDt;
    _yaw = MathUtils.normalizeAngle(_yaw + vehicleGyro.z * effectiveDt);

    // Transform acceleration to nav frame using uncorrected attitude
    final rNav = Mat3.fromEuler(_roll, _pitch, _yaw);
    final aNav = rNav.transform(vehicleAccel);

    // Direct double integration
    final dt2 = 0.5 * effectiveDt * effectiveDt;
    _px += _vx * effectiveDt + aNav.x * dt2;
    _py += _vy * effectiveDt + aNav.y * dt2;
    _pz += _vz * effectiveDt + aNav.z * dt2;

    _vx += aNav.x * effectiveDt;
    _vy += aNav.y * effectiveDt;
    _vz += aNav.z * effectiveDt;
  }

  /// Synchronize Classic DR with GNSS position/velocity when GNSS is nominal.
  /// Unconstrained open-loop double integration only accumulates during outages.
  void syncWithGnss({
    required Vec3 position,
    required Vec3 velocity,
    double? yaw,
  }) {
    _px = position.x;
    _py = position.y;
    _pz = position.z;
    _vx = velocity.x;
    _vy = velocity.y;
    _vz = velocity.z;
    if (yaw != null) {
      _yaw = yaw;
    }
    _roll = 0.0;
    _pitch = 0.0;
  }

  void reset({double initYaw = 0.0}) {
    _px = 0.0;
    _py = 0.0;
    _pz = 0.0;
    _vx = 0.0;
    _vy = 0.0;
    _vz = 0.0;
    _roll = 0.0;
    _pitch = 0.0;
    _yaw = initYaw;
  }
}

