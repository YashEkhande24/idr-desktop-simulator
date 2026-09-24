import '../core/math_utils.dart';

/// Raw or preprocessed IMU sample (100 Hz).
class ImuSample {
  final double timestamp; // seconds
  final Vec3 accel; // [ax, ay, az] in m/s^2
  final Vec3 gyro;  // [wx, wy, wz] in rad/s

  const ImuSample({
    required this.timestamp,
    required this.accel,
    required this.gyro,
  });

  double get ax => accel.x;
  double get ay => accel.y;
  double get az => accel.z;
  double get wx => gyro.x;
  double get wy => gyro.y;
  double get wz => gyro.z;
}

/// Barometer measurement (10 Hz).
class BaroSample {
  final double timestamp; // seconds
  final double pressureHpa; // Atmospheric pressure in hPa
  final double altitude; // Derived altitude in meters

  const BaroSample({
    required this.timestamp,
    required this.pressureHpa,
    required this.altitude,
  });

  factory BaroSample.fromPressure(double timestamp, double pressureHpa) {
    return BaroSample(
      timestamp: timestamp,
      pressureHpa: pressureHpa,
      altitude: MathUtils.pressureToAltitude(pressureHpa),
    );
  }
}

/// Magnetometer measurement for electronic compass (microteslas).
class MagSample {
  final double timestamp; // seconds
  final Vec3 magneticField; // [Bx, By, Bz] in uT
  final double headingRad; // Tilt-compensated compass heading (radians, 0 = North, pi/2 = East)

  const MagSample({
    required this.timestamp,
    required this.magneticField,
    required this.headingRad,
  });

  double get headingDeg => MathUtils.radToDeg(headingRad);
}

/// GNSS position and satellite constellation fix (1 Hz).
class GnssSample {
  final double timestamp; // seconds
  final Vec3 position; // Local ENU [x_east, y_north, z_up] in meters
  final double latitude; // WGS-84 deg
  final double longitude; // WGS-84 deg
  final double altitude; // meters
  final double speed; // m/s
  final double heading; // deg (0 = North)
  final double hdop; // Horizontal Dilution of Precision
  final double accuracy; // meters
  final bool isDenied; // simulated or real GNSS outage

  const GnssSample({
    required this.timestamp,
    required this.position,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.altitude = 0.0,
    this.speed = 0.0,
    this.heading = 0.0,
    this.hdop = 1.0,
    this.accuracy = 2.0,
    this.isDenied = false,
  });

  double get x => position.x;
  double get y => position.y;
  double get z => position.z;
}
