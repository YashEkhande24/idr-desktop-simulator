import '../core/math_utils.dart';

/// 9-Dimensional Navigation State Vector for Extended Kalman Filter (EKF):
/// x = [p_x, p_y, p_z, v_x, v_y, v_z, roll, pitch, yaw]^T
class EkfState {
  final Vec3 position;  // [px, py, pz] in meters (Local ENU)
  final Vec3 velocity;  // [vx, vy, vz] in m/s
  final Vec3 attitude;  // [roll, pitch, yaw] in radians
  final List<double> covariance; // 9x9 covariance matrix (81 elements, row-major)

  const EkfState({
    required this.position,
    required this.velocity,
    required this.attitude,
    required this.covariance,
  });

  double get px => position.x;
  double get py => position.y;
  double get pz => position.z;

  double get vx => velocity.x;
  double get vy => velocity.y;
  double get vz => velocity.z;

  double get roll => attitude.x;
  double get pitch => attitude.y;
  double get yaw => attitude.z;

  double get speed => velocity.norm; // scalar speed m/s
  double get speedKmh => speed * 3.6;
  double get forwardSpeed => speed;
  double get climbRate => velocity.z;

  /// Trace of the 3D position error covariance (uncertainty metric)
  double get covarianceTrace => covariance.length >= 3 ? (covariance[0] + covariance[1] + covariance[2]) : 0.0;

  /// Default initial state at origin with standstill covariance.
  factory EkfState.initial() {
    final cov = List<double>.filled(81, 0.0);
    // Position variance (1 m std -> 1 m^2)
    cov[0 * 9 + 0] = 1.0;
    cov[1 * 9 + 1] = 1.0;
    cov[2 * 9 + 2] = 2.0;
    // Velocity variance (0.5 m/s std -> 0.25)
    cov[3 * 9 + 3] = 0.25;
    cov[4 * 9 + 4] = 0.25;
    cov[5 * 9 + 5] = 0.25;
    // Attitude variance (~1 deg std -> 0.0003)
    cov[6 * 9 + 6] = 0.001;
    cov[7 * 9 + 7] = 0.001;
    cov[8 * 9 + 8] = 0.01;

    return EkfState(
      position: Vec3.zero,
      velocity: Vec3.zero,
      attitude: Vec3.zero,
      covariance: cov,
    );
  }

  /// Create a copy with modified fields.
  EkfState copyWith({
    Vec3? position,
    Vec3? velocity,
    Vec3? attitude,
    List<double>? covariance,
  }) {
    return EkfState(
      position: position ?? this.position,
      velocity: velocity ?? this.velocity,
      attitude: attitude ?? this.attitude,
      covariance: covariance ?? List<double>.from(this.covariance),
    );
  }
}
